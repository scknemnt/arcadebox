#!/bin/sh
# Kabin PC (i7 / VGA) — Debian Stable. Bir kez:
#   sudo sh kiosk/debian-kur.sh
#   sudo reboot

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
if [ ! -f "$ROOT/backend/arcadebox.py" ]; then
  for d in /mnt/games/ArcadeBox /mnt/arcade/ArcadeBox /media/*/ArcadeBox /media/*/*/ArcadeBox "$HOME/ArcadeBox"; do
    if [ -f "$d/backend/arcadebox.py" ]; then
      ROOT="$d"
      break
    fi
  done
fi
USER_NAME="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="/home/$USER_NAME"

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/debian-kur.sh  ile calistir."
  exit 1
fi

echo "Arcade Box kok: $ROOT"
echo "Kullanici:      $USER_NAME"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  python3 \
  p7zip-full \
  unzip \
  wget \
  ca-certificates \
  xserver-xorg \
  xinit \
  x11-xserver-utils \
  openbox \
  unclutter \
  chromium \
  firefox-esr \
  retroarch \
  joystick \
  mesa-utils \
  libgl1-mesa-dri \
  firmware-linux-free \
  sudo

DEBIAN_FRONTEND=noninteractive apt-get install -y \
  firmware-linux-nonfree \
  firmware-misc-nonfree \
  firmware-realtek \
  firmware-amd-graphics \
  2>/dev/null || true

apt-get install -y \
  libretro-snes9x \
  libretro-nestopia \
  libretro-genesisplusgx \
  libretro-stella \
  libretro-fbneo \
  libretro-mame \
  2>/dev/null || true

usermod -aG input,plugdev,video,audio,render,sudo "$USER_NAME" 2>/dev/null || true
cat > /etc/udev/rules.d/99-arcadebox-pads.rules <<'EOF'
KERNEL=="js[0-9]*", MODE="0666"
SUBSYSTEM=="input", ATTRS{idVendor}=="054c", MODE="0666"
EOF
modprobe joydev 2>/dev/null || true

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
systemctl daemon-reload || true
systemctl set-default multi-user.target || true

PROFILE="$HOME_DIR/.bash_profile"
touch "$PROFILE"
if ! grep -q "Arcade Box PC kiosk" "$PROFILE" 2>/dev/null; then
  cat >> "$PROFILE" <<EOF

# Arcade Box PC kiosk
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  exec startx "$HOME_DIR/.xinitrc" -- :0 vt1 -nocursor
fi
EOF
fi
chown "$USER_NAME:" "$PROFILE" || true

XINITRC="$HOME_DIR/.xinitrc"
cat > "$XINITRC" <<'EOF'
#!/bin/sh
xset s off
xset -dpms
xset s noblank
openbox &
i=0
while [ "$i" -lt 40 ]; do
  for d in \
    "$HOME/ArcadeBox" \
    /mnt/games/ArcadeBox \
    /mnt/arcade/ArcadeBox \
    /media/*/ArcadeBox \
    /media/*/*/ArcadeBox \
    /mnt/*/ArcadeBox
  do
    if [ -f "$d/kiosk/linux-start.sh" ]; then
      exec sh "$d/kiosk/linux-start.sh"
    fi
  done
  i=$((i + 1))
  sleep 1
done
echo "ArcadeBox bulunamadi. Klasoru ~/ArcadeBox veya /mnt/games/ArcadeBox yap."
sleep 30
EOF
chown "$USER_NAME:" "$XINITRC" || true
chmod +x "$XINITRC" 2>/dev/null || true

if [ -f "$ROOT/kiosk/pi-cores.sh" ]; then
  echo "Libretro core indiriliyor (x86_64)..."
  sh "$ROOT/kiosk/pi-cores.sh" || true
fi

if [ -f "$ROOT/kiosk/debian-display.sh" ]; then
  echo "Ekran (VGA) yapilandiriliyor..."
  sh "$ROOT/kiosk/debian-display.sh" auto || true
fi

echo
echo "Kurulum bitti. sudo reboot"
echo "ArcadeBox: $ROOT"
command -v chromium >/dev/null && echo "chromium: OK" || echo "chromium: EKSIK"
command -v retroarch >/dev/null && echo "retroarch: OK" || echo "retroarch: EKSIK"
command -v startx >/dev/null && echo "startx: OK" || echo "startx: EKSIK"
lspci -nn 2>/dev/null | grep -i -E 'vga|3d' || true
