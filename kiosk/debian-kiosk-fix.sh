#!/bin/sh
# Login ekraninda bir kez:  sudo sh kiosk/debian-kiosk-fix.sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/debian-kiosk-fix.sh"
  exit 1
fi

USER_NAME="${SUDO_USER:-arcadebox}"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
ROOT=""
for d in /mnt/games/ArcadeBox /home/$USER_NAME/ArcadeBox; do
  if [ -f "$d/backend/arcadebox.py" ]; then
    ROOT="$d"
    break
  fi
done
[ -n "$ROOT" ] || { echo "ArcadeBox bulunamadi"; exit 1; }

echo "ArcadeBox: $ROOT"
chown -R "$USER_NAME:$USER_NAME" "$ROOT"

apt-get install -y firefox-esr xserver-xorg xinit openbox unclutter \
  alsa-utils firmware-linux-nonfree pipewire pipewire-pulse wireplumber \
  pulseaudio-utils 2>/dev/null || true

# Ses: varsayilan cikis ac
if command -v amixer >/dev/null 2>&1; then
  amixer sset Master 90% unmute 2>/dev/null || true
  amixer sset PCM 90% unmute 2>/dev/null || true
  amixer sset Headphone 90% unmute 2>/dev/null || true
  amixer sset Speaker 90% unmute 2>/dev/null || true
  alsactl store 2>/dev/null || true
fi
loginctl enable-linger "$USER_NAME" 2>/dev/null || true

rm -f /etc/X11/xorg.conf.d/10-arcadebox.conf
if [ -f "$ROOT/kiosk/debian-display.sh" ]; then
  sh "$ROOT/kiosk/debian-display.sh" intel 2>/dev/null || true
fi

# systemd kiosk cakismasin — getty autologin + startx
systemctl disable arcadebox-kiosk.service 2>/dev/null || true
systemctl stop arcadebox-kiosk.service 2>/dev/null || true

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER_NAME --noclear %I \$TERM
EOF

usermod -aG video,tty,input,audio,render,sudo "$USER_NAME" 2>/dev/null || true

XINITRC="$HOME_DIR/.xinitrc"
cat > "$XINITRC" <<'EOF'
#!/bin/sh
xset s off
xset -dpms
xset s noblank
openbox &
for d in "$HOME/ArcadeBox" /mnt/games/ArcadeBox; do
  if [ -f "$d/kiosk/linux-start.sh" ]; then
    exec sh "$d/kiosk/linux-start.sh"
  fi
done
echo "ArcadeBox bulunamadi"
sleep 60
EOF
chown "$USER_NAME:" "$XINITRC"
chmod +x "$XINITRC"

PROFILE="$HOME_DIR/.bash_profile"
touch "$PROFILE"
grep -q "Arcade Box kiosk" "$PROFILE" 2>/dev/null || cat >> "$PROFILE" <<EOF

# Arcade Box kiosk
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  exec startx "$HOME_DIR/.xinitrc" -- :0 vt1 -nocursor
fi
EOF
chown "$USER_NAME:" "$PROFILE"

if [ -f "$ROOT/config.json" ]; then
  python3 <<PY
import json
from pathlib import Path
p = Path("$ROOT/config.json")
cfg = json.loads(p.read_text(encoding="utf-8"))
cfg["kiosk"] = True
cfg["fastBoot"] = True
disp = cfg.setdefault("display", {})
disp["aspect"] = "4:3"
disp["scale"] = "fill"
disp["output"] = "vga"
disp["crt"] = False
ra = cfg.setdefault("retroarch", {})
ra["exe"] = ""
ra["cores"] = ""
p.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8")
PY
  chown "$USER_NAME:" "$ROOT/config.json"
fi

ln -sfn "$ROOT" "$HOME_DIR/ArcadeBox"

systemctl daemon-reload
systemctl set-default multi-user.target

if [ -f /etc/default/grub ]; then
  if ! grep -q 'loglevel=3' /etc/default/grub; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="[^"]*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.udev.log_level=3"/' /etc/default/grub
    update-grub 2>/dev/null || true
  fi
fi

echo
echo "Tamam. sudo reboot"
echo "Manuel test (login sonrasi): startx"
