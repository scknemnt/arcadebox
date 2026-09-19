#!/bin/sh
# SSH ile ekran gelmiyorsa — Xorg'u guvenli PAL576i moduna al.
#   cd /mnt/games/ArcadeBox
#   sudo sh kiosk/crt-recover.sh
#   sudo reboot
#
# Sebep: PAL576-SCART (13.5 MHz) bazi Intel VGA'larda X acilisinda patlar;
# PAL576i (25.2 MHz) daha once calisiyordu.

set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-recover.sh"
  exit 1
fi

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
USER_NAME="${SUDO_USER:-arcadebox}"
HOME_DIR="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"

echo "=== CRT kurtarma — boot modu PAL576i ==="

mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/10-arcadebox.conf <<'EOF'
# Arcade Box — guvenli boot PAL576i; ince ayar xrandr ile (.xprofile)
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

RC="${HOME_DIR}/.xprofile"
mkdir -p "$(dirname "$RC")"
cat > "$RC" <<'XPROF'
# CRT — once calisan PAL576i, sonra istege bagli PAL576-SCART
if command -v xrandr >/dev/null 2>&1; then
  for out in VGA-1 VGA-0 VGA1; do
    if xrandr --query 2>/dev/null | grep -q "^${out} connected"; then
      xrandr --output "$out" --mode PAL576i 2>/dev/null && break
      xrandr --output "$out" --mode 640x480 2>/dev/null && break
      xrandr --output "$out" --auto 2>/dev/null && break
    fi
  done
fi
XPROF
chown "$USER_NAME:$USER_NAME" "$RC" 2>/dev/null || true

echo "Yazildi: 10-arcadebox.conf (PreferredMode=PAL576i) + .xprofile"
echo "sudo reboot"
echo
echo "Reboot sonrasi test (SSH):"
echo "  export DISPLAY=:0"
echo "  xrandr --query | grep '\\*'"
echo "  cat /tmp/arcadebox-kiosk.log | tail -20"
