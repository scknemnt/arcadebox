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

LSPCI=""
for c in /usr/bin/lspci /usr/sbin/lspci lspci; do
  if [ -x "$c" ]; then
    LSPCI="$c"
    break
  fi
done

lspci_list() {
  if [ -n "$LSPCI" ]; then
    "$LSPCI" -nn 2>/dev/null || true
  fi
}

has_nvidia() {
  lspci_list | grep -iE 'VGA|Display|Graphics|3D' | grep -qiE 'nvidia|10de:'
}

has_intel() {
  lspci_list | grep -iE 'VGA|Display|Graphics|3D' | grep -qiE 'intel|8086:'
}

if [ "$MODE" = "auto" ]; then
  if [ -z "$LSPCI" ]; then
    echo "lspci bulunamadi. Kur: apt-get install -y pciutils"
    echo "VGA kablo ekran kartindaysa: sudo sh kiosk/crt-scart-xorg.sh nvidia"
    echo "VGA kablo anakarttaysa:     sudo sh kiosk/crt-scart-xorg.sh intel"
    exit 1
  fi
  if has_nvidia; then
    MODE="nvidia"
  elif has_intel; then
    MODE="intel"
  else
    echo "VGA bulunamadi. lspci ciktisi:"
    lspci_list | grep -iE 'vga|display|graphics|3d' || lspci_list | head -5
    echo "Elle dene: sudo sh kiosk/crt-scart-xorg.sh nvidia   (ekran karti VGA)"
    echo "           sudo sh kiosk/crt-scart-xorg.sh intel    (anakart VGA)"
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
    echo "Not: Anakart VGA icin tek conf onerilir: sudo sh kiosk/crt-intel-vga.sh"
    MAIN="/etc/X11/xorg.conf.d/10-arcadebox.conf"
    cat > "$MAIN" <<EOF
# Arcade Box — Intel onboard VGA, SCART PAL576i
Section "Monitor"
    Identifier "VGA-SCART"
    $PAL_MODE
    $VGA_MODE
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
        Modes "PAL576i" "640x480"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
EOF
    rm -f "$CONF"
    CONF="$MAIN"
    if lspci_list | grep -qiE 'nvidia|10de:'; then
      echo "NVIDIA algilandi — nouveau blacklist icin: sudo sh kiosk/crt-intel-vga.sh"
    fi
    ;;
  *)
    echo "Kullanim: sudo sh kiosk/crt-scart-xorg.sh [nvidia|intel|auto]"
    exit 1
    ;;
esac

echo "Yazildi: $CONF"
echo "Kalici VGA modu: sudo sh kiosk/crt-scart-display.sh"
echo "sudo reboot"
lspci_list | grep -iE 'vga|display|3d' || true
