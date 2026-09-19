#!/bin/sh
# X + CRT menu boot duzelt — MUTLAKA root ile:
#   cd /mnt/games/ArcadeBox
#   sh kiosk/git-pull.sh
#   sudo sh kiosk/crt-fix-boot.sh
#   sudo reboot

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
loginctl enable-linger "$USER_NAME" 2>/dev/null || true

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

# Bozuk eski startx bloklarini sil — temiz dosya yaz
cat > "$HOME_DIR/.bash_profile" <<EOF
# Arcade Box CRT kiosk
if [ -f "\$HOME/.profile" ]; then
  . "\$HOME/.profile"
fi
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  exec startx "$HOME_DIR/.xinitrc" -- :0 vt1 -nocursor
fi
EOF

if [ -f "$HOME_DIR/.profile" ]; then
  python3 - "$HOME_DIR/.profile" <<'PY'
import re, sys
p = sys.argv[1]
try:
    t = open(p, encoding="utf-8").read()
except OSError:
    sys.exit(0)
t = re.sub(
    r"\n# Arcade Box[^\n]*\nif \[ -z \"\$DISPLAY\"[^\n]*\n[^\n]*\nfi\n?",
    "\n",
    t,
    flags=re.MULTILINE,
)
t = re.sub(r"\nif \[ -z \"\$DISPLAY\"[^\n]*\n\s*exec startx[^\n]*\nfi\n?", "\n", t)
t = re.sub(r"\n\s*exec startx[^\n]*\n", "\n", t)
open(p, "w", encoding="utf-8").write(t.rstrip() + "\n")
print("OK: .profile temizlendi")
PY
else
  cat > "$HOME_DIR/.profile" <<'PROF'
# ~/.profile
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
PROF
fi
echo "OK: .bash_profile yenilendi"

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

# getty autologin + startx (systemd kiosk ile cakismasin)
systemctl disable arcadebox-kiosk.service 2>/dev/null || true
systemctl stop arcadebox-kiosk.service 2>/dev/null || true

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USER_NAME} --noclear %I \$TERM
EOF
systemctl enable getty@tty1.service 2>/dev/null || true
systemctl daemon-reload
echo "OK: getty autologin tty1"

chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.xprofile" "$HOME_DIR/.xinitrc" \
  "$HOME_DIR/.profile" "$HOME_DIR/.bash_profile" 2>/dev/null || true

echo
echo ">>> sudo reboot <<<"
echo "SSH hatasi gitti mi: bash -l  (fi hatasi olmamali)"
echo "Log: tail -30 /tmp/arcadebox-startx.log"
