#!/bin/sh
# Arçelik 3370 S (ve benzeri PAL SCART TV) — Intel VGA.
#   sudo sh kiosk/crt-arcelik.sh
#   sudo reboot
#
# Boot: PAL576i (25.2 MHz — guvenli). Hizalama: xrandr ile PAL576-SCART dene.

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-arcelik.sh"
  exit 1
fi

# Yatay ince ayar: saga kayma varsa negatif (sola), orn. -0.08
HPOS="${1:-0}"

echo "=== Arçelik SCART profili (hpos transform=$HPOS) ==="

mkdir -p /etc/X11/xorg.conf.d
rm -f /etc/X11/xorg.conf.d/20-arcade-scart.conf

cat > /etc/X11/xorg.conf.d/10-arcadebox.conf <<'EOF'
# Arcade Box — Arçelik PAL SCART (htotal 864 = standart PAL satir)
Section "Monitor"
    Identifier "VGA-SCART"
    Modeline "PAL576-SCART" 13.50 720 738 846 864 576 582 587 625 interlace -hsync -vsync
    Modeline "PAL576-AR" 25.20 720 744 808 1611 576 581 586 625 interlace -hsync -vsync
    Modeline "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync
    Modeline "640x480" 25.18 640 656 672 832 480 490 492 525 -hsync -vsync
    Option "IgnoreEDID" "true"
    Option "PreferredMode" "PAL576i"
EndSection

Section "Device"
    Identifier "IntelGPU"
    Driver "modesetting"
    BusID "PCI:0:2:0"
    Option "UseEDID" "false"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "IntelGPU"
    Monitor "VGA-SCART"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "PAL576i" "640x480" "PAL576-AR" "PAL576-SCART"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
EOF

USER_NAME="${SUDO_USER:-arcadebox}"
HOME_DIR="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"
RC="${HOME_DIR}/.xprofile"
mkdir -p "$(dirname "$RC")"
cat > "$RC" <<XPROF
# Arçelik SCART — xrandr PAL modu
for d in "$ROOT" /mnt/games/ArcadeBox "\$HOME/ArcadeBox"; do
  if [ -f "\$d/kiosk/crt-xrandr-pal.sh" ]; then
    sh "\$d/kiosk/crt-xrandr-pal.sh" && break
  fi
done
HPOS="${HPOS}"
if [ "\$HPOS" != "0" ] && command -v xrandr >/dev/null 2>&1; then
  for out in VGA-1 VGA-0 VGA1; do
    if xrandr --query 2>/dev/null | grep -q "^\${out} connected"; then
      xrandr --output "\$out" --transform 1,0,\$HPOS,0,1,0,0,0,1 2>/dev/null || true
      break
    fi
  done
fi
XPROF
chown "$USER_NAME:$USER_NAME" "$RC" 2>/dev/null || true

if [ -f "$ROOT/kiosk/crt-scart-display.sh" ]; then
  sh "$ROOT/kiosk/crt-scart-display.sh"
fi

echo "Yazildi: 10-arcadebox.conf + .xprofile"
echo "Test (reboot oncesi): export DISPLAY=:0 && sh kiosk/crt-hpos.sh"
echo "Ince ayar: sudo sh kiosk/crt-arcelik.sh -0.08"
echo "sudo reboot"
