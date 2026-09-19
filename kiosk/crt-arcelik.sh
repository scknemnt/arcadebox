#!/bin/sh
# Arçelik 3370 S (ve benzeri PAL SCART TV) — PAL576-AR modeline + Intel VGA.
#   sudo sh kiosk/crt-arcelik.sh
#   sudo reboot

set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-arcelik.sh"
  exit 1
fi

echo "=== Arçelik SCART profili (3370 S vb.) ==="

mkdir -p /etc/X11/xorg.conf.d
rm -f /etc/X11/xorg.conf.d/20-arcade-scart.conf

cat > /etc/X11/xorg.conf.d/10-arcadebox.conf <<'EOF'
# Arcade Box — Arçelik PAL SCART (~15.6 kHz, 25.2 MHz)
Section "Monitor"
    Identifier "VGA-SCART"
    # PAL576-AR: PAL576i ile ayni satir hizi, daraltilmis yatay porch (kenar mavi azalir)
    Modeline "PAL576-AR" 25.20 720 744 808 1611 576 581 586 625 interlace -hsync -vsync
    Modeline "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync
    Modeline "640x480" 25.18 640 656 672 832 480 490 492 525 -hsync -vsync
    Option "IgnoreEDID" "true"
    Option "PreferredMode" "PAL576-AR"
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
        Modes "PAL576-AR" "PAL576i" "640x480"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
EOF

# .xprofile — once PAL576-AR, sonra PAL576i; 640x480 YOK
USER_NAME="${SUDO_USER:-arcadebox}"
HOME_DIR="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"
RC="${HOME_DIR}/.xprofile"
mkdir -p "$(dirname "$RC")"
cat > "$RC" <<'XPROF'
# Arçelik SCART — PAL576-AR / PAL576i (640x480 kenar mavi yapar, kullanma)
if command -v xrandr >/dev/null 2>&1; then
  for out in VGA-1 VGA-0 VGA1; do
    if xrandr --query 2>/dev/null | grep -q "^${out} connected"; then
      for m in PAL576-AR PAL576i; do
        xrandr --output "$out" --mode "$m" 2>/dev/null && break 2
      done
    fi
  done
fi
XPROF
chown "$USER_NAME:$USER_NAME" "$RC" 2>/dev/null || true

if [ -f "$ROOT/kiosk/crt-scart-display.sh" ]; then
  sh "$ROOT/kiosk/crt-scart-display.sh"
fi

echo "Yazildi: 10-arcadebox.conf + .xprofile"
echo "sudo reboot"
echo "Sonra: xrandr --query | grep -E 'PAL576|\*'"
