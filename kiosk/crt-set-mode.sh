#!/bin/sh
# Kalici PAL mod secimi (.xprofile + xorg modeline).
#   sudo sh kiosk/crt-set-mode.sh PAL576-864

set -eu
MODE="${1:-PAL576-864}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-set-mode.sh $MODE"
  exit 1
fi

USER_NAME="${SUDO_USER:-arcadebox}"
HOME_DIR="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"
RC="${HOME_DIR}/.xprofile"

case "$MODE" in
  PAL576-864)
    ML='Modeline "PAL576-864" 25.20 720 736 802 864 576 582 587 625 interlace -hsync -vsync'
    XR='720 736 802 864'
    ;;
  PAL576-L16)
    ML='Modeline "PAL576-L16" 25.20 720 720 798 864 576 582 587 625 interlace -hsync -vsync'
    XR='720 720 798 864'
    ;;
  PAL576-SCART)
    ML='Modeline "PAL576-SCART" 13.50 720 738 846 864 576 582 587 625 interlace -hsync -vsync'
    XR='720 738 846 864'
    ;;
  PAL576i)
    ML='Modeline "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync'
    XR='720 768 848 1611'
    ;;
  *)
    echo "Bilinmeyen mod: $MODE"
    exit 1
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
        Modes "$MODE" "640x480"
    EndSubSection
EndSection
Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
EOF

cat > "$RC" <<XPROF
export DISPLAY="\${DISPLAY:-:0}"
export PREFERRED_MODE="$MODE"
for d in "$ROOT" /mnt/games/ArcadeBox "\$HOME/ArcadeBox"; do
  if [ -f "\$d/kiosk/crt-xrandr-pal.sh" ]; then
    sh "\$d/kiosk/crt-xrandr-pal.sh" && break
  fi
done
XPROF
chown "$USER_NAME:$USER_NAME" "$RC" 2>/dev/null || true

echo "Mod: $MODE -> 10-arcadebox.conf + .xprofile"
echo "sudo reboot"
