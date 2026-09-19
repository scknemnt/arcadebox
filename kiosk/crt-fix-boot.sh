#!/bin/sh
# X calismiyor / siyah ekran — boot zincirini duzelt.
#   cd /mnt/games/ArcadeBox
#   sh kiosk/git-pull.sh
#   sh kiosk/crt-fix-boot.sh
#   sudo reboot
#
# arcadebox kullanicisi ile calistir (sudo sadece xorg icin sorulur).

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HOME_DIR="${HOME:-/home/arcadebox}"
CFG="$ROOT/config.json"

echo "=== CRT boot duzeltme ==="
echo "ArcadeBox: $ROOT"

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

cat > "$HOME_DIR/.xprofile" <<XPROF
export DISPLAY="\${DISPLAY:-:0}"
sleep 2
for d in /mnt/games/ArcadeBox "$ROOT" "$HOME/ArcadeBox"; do
  [ -f "\$d/kiosk/crt-xrandr-pal.sh" ] && sh "\$d/kiosk/crt-xrandr-pal.sh" && break
done
XPROF
echo "OK: $HOME_DIR/.xprofile"

cat > "$HOME_DIR/.xinitrc" <<'XINIT'
#!/bin/sh
xset s off 2>/dev/null || true
xset -dpms 2>/dev/null || true
xset s noblank 2>/dev/null || true
openbox &
i=0
while [ "$i" -lt 60 ]; do
  for d in /mnt/games/ArcadeBox /mnt/arcade/ArcadeBox "$HOME/ArcadeBox"; do
    if [ -f "$d/kiosk/linux-start.sh" ]; then
      exec sh "$d/kiosk/linux-start.sh"
    fi
  done
  mount /mnt/games 2>/dev/null || mount -a 2>/dev/null || true
  i=$((i + 1))
  sleep 1
done
echo "ArcadeBox bulunamadi"
sleep 60
XINIT
chmod +x "$HOME_DIR/.xinitrc"
echo "OK: $HOME_DIR/.xinitrc (/mnt/games oncelikli)"

PROFILE="$HOME_DIR/.bash_profile"
touch "$PROFILE"
if ! grep -q "Arcade Box PC kiosk" "$PROFILE" 2>/dev/null; then
  cat >> "$PROFILE" <<'PROF'

# Arcade Box PC kiosk
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx "$HOME/.xinitrc" -- :0 vt1 -nocursor
fi
PROF
  echo "OK: .bash_profile startx eklendi"
else
  echo "OK: .bash_profile zaten var"
fi

if [ "$(id -u)" -eq 0 ]; then
  _xorg=1
else
  echo "Xorg sadelestirme (sudo):"
  sudo -v && _xorg=1 || _xorg=0
fi
if [ "${_xorg:-0}" = "1" ]; then
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
  echo "OK: minimal Xorg"
  systemctl disable arcadebox-kiosk.service 2>/dev/null || true
fi

echo
echo ">>> sudo reboot <<<"
echo "SSH ile X baslatma (alternatif): sudo systemctl start getty@tty1.service"
