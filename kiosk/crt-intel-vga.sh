#!/bin/sh
# Anakart Intel VGA + SCART TV — nouveau kapat, tek Xorg conf, PAL576i.
#   sudo sh kiosk/crt-intel-vga.sh
#   sudo reboot
#
# VGA kablosu anakartta; ekran karti (NVIDIA) kullanilmiyor.

set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-intel-vga.sh"
  exit 1
fi

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

echo "=== Intel onboard VGA + SCART ==="

# NVIDIA varsa X onu secer; Intel VGA bos kalir
if lspci -nn 2>/dev/null | grep -qiE 'nvidia|10de:'; then
  echo "NVIDIA bulundu — nouveau devre disi (Intel VGA icin)."
  cat > /etc/modprobe.d/blacklist-nouveau.conf <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
  update-initramfs -u 2>/dev/null || true
else
  echo "NVIDIA yok — blacklist atlaniyor."
fi

mkdir -p /etc/X11/xorg.conf.d
rm -f /etc/X11/xorg.conf.d/20-arcade-scart.conf

cat > /etc/X11/xorg.conf.d/10-arcadebox.conf <<'EOF'
# Arcade Box — Intel onboard VGA, SCART PAL576i (~15.6 kHz)
Section "Monitor"
    Identifier "VGA-SCART"
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
        Modes "PAL576i" "640x480"
    EndSubSection
EndSection

Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
EOF

echo "Yazildi: /etc/X11/xorg.conf.d/10-arcadebox.conf"

if [ -f "$ROOT/kiosk/crt-scart-display.sh" ]; then
  sh "$ROOT/kiosk/crt-scart-display.sh"
fi

echo
echo "sudo reboot"
echo "Sonra: xrandr --query | grep PAL576i"
lspci -nn 2>/dev/null | grep -iE 'vga|display|3d' || true
