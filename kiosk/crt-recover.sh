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

INTEL_BUS=""
if command -v lspci >/dev/null 2>&1; then
  _slot="$(lspci 2>/dev/null | awk '/VGA|Display/ && /Intel|8086/ { print $1; exit }')"
  if [ -n "$_slot" ]; then
    _b=$((16#$(echo "$_slot" | cut -d: -f1)))
    _d=$(echo "$_slot" | cut -d: -f2 | cut -d. -f1)
    _f=$(echo "$_slot" | cut -d. -f2)
    INTEL_BUS="PCI:${_b}:${_d}:${_f}"
    echo "Intel BusID: $INTEL_BUS"
  fi
fi

mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/10-arcadebox.conf <<EOF
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
$( [ -n "$INTEL_BUS" ] && printf '    BusID "%s"\n' "$INTEL_BUS" )
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
cat > "$RC" <<XPROF
# CRT — xrandr ile PAL modu (Xorg 1024x768 acarsa TV siyah kalir)
for d in "$ROOT" /mnt/games/ArcadeBox "\$HOME/ArcadeBox"; do
  if [ -f "\$d/kiosk/crt-xrandr-pal.sh" ]; then
    sh "\$d/kiosk/crt-xrandr-pal.sh" && break
  fi
done
XPROF
chown "$USER_NAME:$USER_NAME" "$RC" 2>/dev/null || true

echo "Yazildi: 10-arcadebox.conf (PreferredMode=PAL576i) + .xprofile"
echo
echo "Reboot OLMADAN hemen dene (SSH):"
echo "  export DISPLAY=:0"
echo "  sh $ROOT/kiosk/crt-xrandr-pal.sh"
echo
echo "Goruntu gelirse: sudo reboot"
echo
echo "Reboot sonrasi test (SSH):"
echo "  export DISPLAY=:0"
echo "  xrandr --query | grep '\\*'"
echo "  cat /tmp/arcadebox-kiosk.log | tail -20"
