#!/bin/sh
# X + menu boot duzelt — MUTLAKA root ile:
#   cd /mnt/games/ArcadeBox
#   sh kiosk/git-pull.sh
#   sudo sh kiosk/crt-fix-boot.sh
#   sudo reboot
#
# SSH'den X ACILMAZ (vt1 izni). Reboot veya:
#   sudo systemctl start arcadebox-kiosk.service

set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-fix-boot.sh"
  exit 1
fi

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
USER_NAME="${SUDO_USER:-arcadebox}"
HOME_DIR="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="/home/$USER_NAME"
CFG="$ROOT/config.json"

echo "=== CRT boot duzeltme (root) ==="
echo "Kullanici: $USER_NAME  ArcadeBox: $ROOT"

mount /mnt/games 2>/dev/null || mount -a 2>/dev/null || true
ln -sfn /mnt/games/ArcadeBox "$HOME_DIR/ArcadeBox" 2>/dev/null || true

usermod -aG video,tty,input,audio,render,sudo "$USER_NAME" 2>/dev/null || true

python3 - "$CFG" <<'PY'
import json, sys
p = sys.argv[1]
try:
    cfg = json.load(open(p, encoding="utf-8"))
except Exception:
    cfg = {}
d = cfg.setdefault("display", {})
d.update({
    "fbPanX": 0, "hpos": 0, "panX": 0,
    "crt": True, "width": 720, "height": 576,
    "preferredMode": "PAL576i", "output": "vga",
})
cfg["theme"] = "amiga-crt"
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open(p, "a").write("\n")
print("config.json OK")
PY

cat > "$HOME_DIR/.xprofile" <<'XPROF'
export DISPLAY="${DISPLAY:-:0}"
sleep 2
for d in /mnt/games/ArcadeBox "$HOME/ArcadeBox"; do
  [ -f "$d/kiosk/crt-xrandr-pal.sh" ] && sh "$d/kiosk/crt-xrandr-pal.sh" && break
done
XPROF

cat > "$HOME_DIR/.xinitrc" <<'XINIT'
#!/bin/sh
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true
openbox &
mount /mnt/games 2>/dev/null || mount -a 2>/dev/null || true
i=0
while [ "$i" -lt 60 ]; do
  for d in /mnt/games/ArcadeBox "$HOME/ArcadeBox"; do
    if [ -f "$d/kiosk/linux-start.sh" ]; then
      exec sh "$d/kiosk/linux-start.sh"
    fi
  done
  sleep 1
  i=$((i + 1))
done
echo "ArcadeBox bulunamadi" >> /tmp/arcadebox-kiosk.log
sleep 120
XINIT
chmod +x "$HOME_DIR/.xinitrc"

# Eski bozuk "exec startx" satirlarini sil — systemd kiosk kullan
for prof in "$HOME_DIR/.profile" "$HOME_DIR/.bash_profile"; do
  if [ -f "$prof" ]; then
    grep -v "Arcade Box" "$prof" | grep -v "exec startx" | grep -v "startx.*xinitrc" > "${prof}.new" || true
    mv "${prof}.new" "$prof"
  fi
  touch "$prof"
done
echo "OK: .profile temizlendi (startx kaldirildi — systemd kullanilir)"

mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/10-arcadebox.conf <<'EOF'
Section "Device"
    Identifier "IntelGPU"
    Driver "modesetting"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "IntelGPU"
    DefaultDepth 24
EndSection
Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
EOF

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USER_NAME} --noclear %I \$TERM
EOF

if [ -f "$ROOT/kiosk/arcadebox-kiosk.service" ]; then
  sed "s|/home/arcadebox|$HOME_DIR|g" "$ROOT/kiosk/arcadebox-kiosk.service" \
    > /etc/systemd/system/arcadebox-kiosk.service
  systemctl daemon-reload
  systemctl enable arcadebox-kiosk.service
  echo "OK: arcadebox-kiosk.service etkin"
fi

chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.xprofile" "$HOME_DIR/.xinitrc" \
  "$HOME_DIR/.profile" "$HOME_DIR/.bash_profile" 2>/dev/null || true

echo
echo ">>> sudo reboot <<<"
echo "Acil test (reboot oncesi): sudo systemctl start arcadebox-kiosk.service"
echo "Log: journalctl -u arcadebox-kiosk.service -n 30 --no-pager"
