#!/bin/sh
# Kalici PAL mod + yatay hizalama (Arçelik — PAL576i).
#   sudo sh kiosk/crt-set-mode.sh PAL576i
#   sudo sh kiosk/crt-set-mode.sh PAL576i -0.20
#   sudo sh kiosk/crt-set-mode.sh PAL576i-H2

set -eu
MODE="${1:-PAL576i}"
HPOS="${2:-0}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-set-mode.sh $MODE [$HPOS]"
  exit 1
fi

USER_NAME="${SUDO_USER:-arcadebox}"
HOME_DIR="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"
RC="${HOME_DIR}/.xprofile"
CFG="$ROOT/config.json"

case "$MODE" in
  PAL576-864)
    ML='Modeline "PAL576-864" 25.20 720 736 802 864 576 582 587 625 interlace -hsync -vsync'
    ;;
  PAL576-SCART)
    ML='Modeline "PAL576-SCART" 13.50 720 738 846 864 576 582 587 625 interlace -hsync -vsync'
    ;;
  PAL576i-H1)
    ML='Modeline "PAL576i-H1" 25.20 720 754 834 1611 576 581 586 625 interlace -hsync -vsync'
    ;;
  PAL576i-H2)
    ML='Modeline "PAL576i-H2" 25.20 720 748 828 1611 576 581 586 625 interlace -hsync -vsync'
    ;;
  PAL576i-H3)
    ML='Modeline "PAL576i-H3" 25.20 720 762 842 1611 576 581 586 625 interlace -hsync -vsync'
    ;;
  PAL576i|*)
    MODE="PAL576i"
    ML='Modeline "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync'
    ;;
esac

mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/10-arcadebox.conf <<EOF
Section "Monitor"
    Identifier "VGA-SCART"
    $ML
    Modeline "640x480" 25.18 640 656 672 832 480 490 492 525 -hsync -vsync
    Option "IgnoreEDID" "true"
    Option "PreferredMode" "$MODE"
EndSection
Section "Device"
    Identifier "IntelGPU"
    Driver "modesetting"
    Option "UseEDID" "false"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "IntelGPU"
    Monitor "VGA-SCART"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "$MODE" "PAL576i" "640x480"
    EndSubSection
EndSection
Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
EOF

python3 - "$CFG" "$MODE" "$HPOS" <<'PY'
import json, sys
path, mode, hpos = sys.argv[1], sys.argv[2], float(sys.argv[3])
try:
    cfg = json.load(open(path, encoding="utf-8"))
except Exception:
    cfg = {}
d = cfg.setdefault("display", {})
d["preferredMode"] = mode
d["hpos"] = hpos
d["crt"] = True
d["width"] = 720
d["height"] = 576
d["output"] = "vga"
json.dump(cfg, open(path, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open(path, "a", encoding="utf-8").write("\n")
print(f"config: preferredMode={mode} hpos={hpos}")
PY

cat > "$RC" <<XPROF
export DISPLAY="\${DISPLAY:-:0}"
export PREFERRED_MODE="$MODE"
export HPOS_TRANSFORM="$HPOS"
for d in "$ROOT" /mnt/games/ArcadeBox "\$HOME/ArcadeBox"; do
  if [ -f "\$d/kiosk/crt-xrandr-pal.sh" ]; then
    sh "\$d/kiosk/crt-xrandr-pal.sh" && break
  fi
done
XPROF
chown "$USER_NAME:$USER_NAME" "$RC" 2>/dev/null || true

echo "Mod=$MODE hpos=$HPOS -> xorg + config.json + .xprofile"
echo "sudo reboot"
