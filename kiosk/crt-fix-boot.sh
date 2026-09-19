#!/bin/sh
# X calismiyor — autologin + startx + PAL576i duzelt.
#   cd /mnt/games/ArcadeBox
#   sh kiosk/git-pull.sh
#   sh kiosk/crt-fix-boot.sh
#   sudo reboot
# SSH aninda: sh kiosk/crt-start-x.sh

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HOME_DIR="${HOME:-/home/arcadebox}"
USER_NAME="$(whoami)"
CFG="$ROOT/config.json"

echo "=== CRT boot duzeltme ==="
echo "ArcadeBox: $ROOT"

mount /mnt/games 2>/dev/null || sudo mount -a 2>/dev/null || true

if [ -d /mnt/games/ArcadeBox ] && [ ! -L "$HOME_DIR/ArcadeBox" ]; then
  rm -rf "$HOME_DIR/ArcadeBox" 2>/dev/null || true
  ln -sfn /mnt/games/ArcadeBox "$HOME_DIR/ArcadeBox" 2>/dev/null || true
  echo "OK: ~/ArcadeBox -> /mnt/games/ArcadeBox"
fi

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

STARTX_BLOCK='# Arcade Box PC kiosk — startx on tty1
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx "$HOME/.xinitrc" -- :0 vt1 -nocursor
fi'

for prof in "$HOME_DIR/.bash_profile" "$HOME_DIR/.profile"; do
  touch "$prof"
  grep -v "Arcade Box" "$prof" 2>/dev/null | grep -v "startx.*xinitrc" > "${prof}.tmp" || true
  mv "${prof}.tmp" "$prof"
  printf '\n%s\n' "$STARTX_BLOCK" >> "$prof"
  echo "OK: $prof"
done

if [ "$(id -u)" -eq 0 ]; then
  _sudo=1
else
  echo "getty autologin + xorg (sudo sifresi):"
  sudo -v && _sudo=1 || _sudo=0
fi

if [ "${_sudo:-0}" = "1" ]; then
  mkdir -p /etc/systemd/system/getty@tty1.service.d
  cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USER_NAME} --noclear %I \$TERM
EOF
  systemctl daemon-reload 2>/dev/null || true
  echo "OK: getty autologin ($USER_NAME)"

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
  systemctl disable arcadebox-kiosk.service 2>/dev/null || true
  systemctl stop arcadebox-kiosk.service 2>/dev/null || true
  echo "OK: minimal Xorg"
fi

echo
echo "1) sudo reboot   (normal yol)"
echo "2) sh kiosk/crt-start-x.sh   (SSH aninda X ac)"
