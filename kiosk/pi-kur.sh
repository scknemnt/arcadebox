#!/bin/sh
# Raspberry Pi 4 — HDMI once, CRT/SCART sonra.
# Lite 64-bit uzerinde bir kez:  sudo sh kiosk/pi-kur.sh

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
if [ ! -f "$ROOT/backend/arcadebox.py" ]; then
  for d in /mnt/usb/ArcadeBox /mnt/arcade/ArcadeBox /media/*/ArcadeBox /media/*/*/ArcadeBox; do
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
  echo "sudo sh kiosk/pi-kur.sh  ile calistir."
  exit 1
fi

echo "Arcade Box koku: $ROOT"
echo "Kullanici:       $USER_NAME"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  python3 \
  p7zip-full \
  xserver-xorg \
  xinit \
  x11-xserver-utils \
  openbox \
  unclutter \
  chromium \
  retroarch \
  || DEBIAN_FRONTEND=noninteractive apt-get install -y chromium-browser python3 xserver-xorg xinit openbox unclutter retroarch

# Core paketleri distroya gore degisir; olanlari al, kalani RetroArch Online Updater.
apt-get install -y \
  libretro-snes9x \
  libretro-nestopia \
  libretro-genesisplusgx \
  libretro-stella \
  libretro-stella2014 \
  libretro-fbneo \
  libretro-mame \
  libretro-pcsx-rearmed \
  libretro-mesen \
  2>/dev/null || true

# Konsol otomatik giris (HDMI tty1). raspi-config yoksa da yaz.
if command -v raspi-config >/dev/null 2>&1; then
  raspi-config nonint do_boot_behaviour B2 || true
fi
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF
systemctl daemon-reload || true

# Lite USB'yi otomatik baglamaz. Kingston ESD-USB -> /mnt/arcade
mkdir -p /mnt/arcade
if ! grep -q "LABEL=ESD-USB" /etc/fstab 2>/dev/null; then
  echo "LABEL=ESD-USB  /mnt/arcade  vfat  defaults,utf8,uid=1000,gid=1000,umask=000,nofail,user,x-systemd.automount  0  0" >> /etc/fstab
fi
mount /mnt/arcade 2>/dev/null || mount -L ESD-USB /mnt/arcade 2>/dev/null || true

PROFILE="$HOME_DIR/.bash_profile"
touch "$PROFILE"
chown "$USER_NAME:" "$PROFILE" || true
if ! grep -q "Arcade Box HDMI kiosk" "$PROFILE" 2>/dev/null; then
  cat >> "$PROFILE" <<EOF

# Arcade Box HDMI kiosk (USB ArcadeBox)
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  exec startx "$HOME_DIR/.xinitrc" -- :0 vt1 -nocursor
fi
EOF
  chown "$USER_NAME:" "$PROFILE" || true
fi

XINITRC="$HOME_DIR/.xinitrc"
cat > "$XINITRC" <<'EOF'
#!/bin/sh
xset s off
xset -dpms
xset s noblank
openbox &
i=0
while [ "$i" -lt 45 ]; do
  mount /mnt/arcade 2>/dev/null || mount -L ESD-USB /mnt/arcade 2>/dev/null || true
  for d in /mnt/arcade/ArcadeBox /mnt/usb/ArcadeBox /media/*/ArcadeBox /media/*/*/ArcadeBox /mnt/*/ArcadeBox "$HOME/ArcadeBox"; do
    if [ -f "$d/kiosk/linux-start.sh" ]; then
      exec sh "$d/kiosk/linux-start.sh"
    fi
  done
  i=$((i + 1))
  sleep 1
done
echo "ArcadeBox USB bulunamadi. Flash diski mavi USB3 portuna tak."
sleep 30
EOF
chown "$USER_NAME:" "$XINITRC" || true
chmod +x "$XINITRC" 2>/dev/null || true

# HDMI0 ve HDMI1 (Pi 4'te iki soket). CRT/SCART sonra 800x600.
CONFIG=/boot/firmware/config.txt
[ -f "$CONFIG" ] || CONFIG=/boot/config.txt
if [ -f "$CONFIG" ] && ! grep -q "Arcade Box HDMI" "$CONFIG"; then
  cat >> "$CONFIG" <<'EOF'

# Arcade Box HDMI — PAL 50 Hz (CRT/SCART 800x600)
hdmi_force_hotplug=1
hdmi_force_hotplug:1=1
hdmi_drive=2
disable_overscan=1
hdmi_group=1
hdmi_mode=31
hdmi_group:1=1
hdmi_mode:1=31
arm_boost=0
EOF
fi

echo
echo "Kurulum bitti. reboot et."
echo "Ilk acilis HDMI'da Arcade Box kiosk."
echo "PS3 kolu USB tak, bir tusa bas."
echo "CRT/SCART icin sonra 800x600 ayarlanir."
command -v chromium >/dev/null && echo "chromium: OK" || true
command -v chromium-browser >/dev/null && echo "chromium-browser: OK" || true
command -v retroarch >/dev/null && echo "retroarch: OK" || echo "retroarch: EKSIK"
command -v startx >/dev/null && echo "startx: OK" || echo "startx: EKSIK"
df -h / | tail -1
