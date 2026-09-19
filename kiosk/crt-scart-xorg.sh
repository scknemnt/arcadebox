#!/bin/sh
# SCART TV icin PAL 15 kHz modeline — xrandr tek basina yetmez (Intel/NVIDIA min clock).
#   sudo sh kiosk/crt-scart-xorg.sh [nvidia|intel|auto]
#   sudo reboot
#
# 25.2 MHz dot clock + genis htotal = ~15.6 kHz satir (surucu 13 MHz modu reddeder).

set -eu

MODE="${1:-auto}"
CONF="/etc/X11/xorg.conf.d/20-arcade-scart.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-scart-xorg.sh [nvidia|intel|auto]"
  exit 1
fi

has_intel() {
  lspci -nn 2>/dev/null | grep -iE 'VGA|Display|Graphics' | grep -qi intel
}

has_nvidia() {
  lspci -nn 2>/dev/null | grep -iE 'VGA|3D' | grep -qi nvidia
}

if [ "$MODE" = "auto" ]; then
  if has_nvidia; then
    MODE="nvidia"
  elif has_intel; then
    MODE="intel"
  else
    echo "VGA bulunamadi."
    exit 1
  fi
fi

mkdir -p /etc/X11/xorg.conf.d

# PAL576i: 25.2 MHz, htotal 1611 -> ~15.64 kHz (SCART TV)
PAL_MODE='Modeline "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync'
VGA_MODE='Modeline "640x480" 25.18 640 656 672 832 480 490 492 525 -hsync -vsync'

case "$MODE" in
  nvidia)
    echo "SCART Xorg: nouveau (NVIDIA VGA soketi)"
    cat > "$CONF" <<EOF
# Arcade Box — VGA-SCART PAL (nouveau)
Section "Monitor"
    Identifier "VGA-SCART"
    $PAL_MODE
    $VGA_MODE
    Option "IgnoreEDID" "true"
    Option "PreferredMode" "PAL576i"
EndSection

Section "Device"
    Identifier "ArcadeGPU"
    Driver "nouveau"
    Option "ModeValidation" "AllowNonEdidModes, NoMaxPClkCheck, NoHorizSyncCheck, NoVertRefreshCheck"
    Option "ConnectedMonitor" "CRT"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "ArcadeGPU"
    Monitor "VGA-SCART"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "PAL576i" "640x480"
    EndSubSection
EndSection
EOF
    ;;
  intel)
    echo "SCART Xorg: modesetting (anakart VGA)"
    cat > "$CONF" <<EOF
# Arcade Box — VGA-SCART PAL (Intel)
Section "Monitor"
    Identifier "VGA-SCART"
    $PAL_MODE
    $VGA_MODE
    Option "IgnoreEDID" "true"
    Option "PreferredMode" "PAL576i"
EndSection

Section "Device"
    Identifier "ArcadeGPU"
    Driver "modesetting"
    Option "UseEDID" "false"
    Option "Monitor-VGA-SCART" "PreferredMode PAL576i"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "ArcadeGPU"
    Monitor "VGA-SCART"
    DefaultDepth 24
    SubSection "Display"
        Depth 24
        Modes "PAL576i" "640x480"
    EndSubSection
EndSection
EOF
    ;;
  *)
    echo "Kullanim: sudo sh kiosk/crt-scart-xorg.sh [nvidia|intel|auto]"
    exit 1
    ;;
esac

echo "Yazildi: $CONF"
echo "Kalici VGA modu: sudo sh kiosk/crt-scart-display.sh"
echo "sudo reboot"
lspci -nn 2>/dev/null | grep -iE 'vga|display|3d' || true
