#!/bin/sh
# Ekran cikisi: NVIDIA VGA veya anakart VGA (Intel).
#   sudo sh kiosk/debian-display.sh nvidia
#   sudo sh kiosk/debian-display.sh intel
#   sudo sh kiosk/debian-display.sh auto

set -eu

MODE="${1:-auto}"
CONF="/etc/X11/xorg.conf.d/10-arcadebox.conf"

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/debian-display.sh [nvidia|intel|auto]"
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
    echo "VGA bulunamadi. lspci | grep -i vga"
    exit 1
  fi
fi

mkdir -p /etc/X11/xorg.conf.d

case "$MODE" in
  nvidia)
    echo "NVIDIA (GeForce) VGA — kablo ekran kartindaki mavi sokette."
    cat > "$CONF" <<'EOF'
Section "Device"
    Identifier "ArcadeGPU"
    Driver "nouveau"
    BusID "PCI:1:0:0"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "ArcadeGPU"
    DefaultDepth 24
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
EOF
    ;;
  intel)
    echo "Intel onboard VGA — BIOS'ta Internal Graphics: Enabled, kablo anakartta."
    cat > "$CONF" <<'EOF'
Section "Device"
    Identifier "ArcadeGPU"
    Driver "modesetting"
    BusID "PCI:0:2:0"
EndSection

Section "Screen"
    Identifier "Screen0"
    Device "ArcadeGPU"
    DefaultDepth 24
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
EOF
    ;;
  *)
    echo "Kullanim: sudo sh kiosk/debian-display.sh [nvidia|intel|auto]"
    exit 1
    ;;
esac

apt-get install -y xserver-xorg-video-nouveau 2>/dev/null || true
echo "Yazildi: $CONF"
lspci -nn | grep -iE 'vga|display' || true
echo "sudo reboot"
