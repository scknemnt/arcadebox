#!/bin/sh
# PS3 / USB encoder: input grubu + js cihaz izni.
#   sudo sh kiosk/pi-pad.sh
#   sudo reboot

set -eu
USER_NAME="${SUDO_USER:-$USER}"

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/pi-pad.sh  ile calistir."
  exit 1
fi

usermod -aG input,plugdev,video,audio "$USER_NAME" || true
DEBIAN_FRONTEND=noninteractive apt-get install -y joystick udev 2>/dev/null || true
modprobe joydev 2>/dev/null || true
mkdir -p /etc/modules-load.d
echo joydev > /etc/modules-load.d/arcadebox-joydev.conf

cat > /etc/udev/rules.d/99-arcadebox-pads.rules <<'EOF'
KERNEL=="js[0-9]*", MODE="0666"
SUBSYSTEM=="input", ATTRS{idVendor}=="054c", MODE="0666"
EOF
udevadm control --reload-rules 2>/dev/null || true
udevadm trigger 2>/dev/null || true

echo "Kullanici $USER_NAME  input grubuna eklendi."
echo "Kol: $(ls /dev/input/js* 2>/dev/null || echo 'js yok — USB kolu tak')"
echo "sudo reboot  sonra bir oyun ac."
