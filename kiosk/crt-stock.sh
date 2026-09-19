#!/bin/sh
# ee6f0d6 donemindeki CALISAN goruntu yolu:
#   duz Intel VGA + xrandr --auto
#   PAL modeline / UseEDID false / PreferredMode YOK
#
#   cd /mnt/games/ArcadeBox
#   git pull
#   sudo sh kiosk/crt-stock.sh
#   sudo reboot

set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-stock.sh"
  exit 1
fi

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
USER_NAME="${SUDO_USER:-arcadebox}"
HOME_DIR="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="/home/$USER_NAME"
CFG="$ROOT/config.json"

echo "=== CRT stock VGA (ee6f0d6 yolu) ==="
echo "Kullanici: $USER_NAME  ArcadeBox: $ROOT"

mount /mnt/games 2>/dev/null || mount -a 2>/dev/null || true
ln -sfn /mnt/games/ArcadeBox "$HOME_DIR/ArcadeBox" 2>/dev/null || true

usermod -aG video,tty,input,audio,render,sudo "$USER_NAME" 2>/dev/null || true
loginctl enable-linger "$USER_NAME" 2>/dev/null || true

# config: crt false — linux-start xrandr --auto kullanir
python3 - "$CFG" <<'PY'
import json, sys
p = sys.argv[1]
try:
    cfg = json.load(open(p, encoding="utf-8"))
except Exception:
    cfg = {}
d = cfg.setdefault("display", {})
d.update({
    "fbPanX": 0, "hpos": 0, "panX": 0, "panY": 0,
    "crt": False, "output": "vga",
})
d.pop("preferredMode", None)
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open(p, "a").write("\n")
print("config.json crt=false (stock VGA)")
PY

# Xorg: debian-display intel — PAL/EDID kapatma YOK
mkdir -p /etc/X11/xorg.conf.d
rm -f /etc/X11/xorg.conf.d/20-arcade-scart.conf
cat > /etc/X11/xorg.conf.d/10-arcadebox.conf <<'EOF'
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
echo "OK: Xorg stock Intel (PAL yok)"

# Boot: getty autologin + startx (debian-kiosk-fix)
systemctl disable arcadebox-kiosk.service 2>/dev/null || true
systemctl stop arcadebox-kiosk.service 2>/dev/null || true
systemctl enable getty@tty1.service 2>/dev/null || true

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USER_NAME} --noclear %I \$TERM
EOF

cat > "$HOME_DIR/.xinitrc" <<'XINIT'
#!/bin/sh
xsetroot -solid "#8b1a1a" 2>/dev/null || true
xset s off
xset -dpms
xset s noblank
mount /mnt/games 2>/dev/null || mount -a 2>/dev/null || true
if [ -f "$HOME/ArcadeBox/kiosk/openbox-rc.xml" ]; then
  openbox --config-file "$HOME/ArcadeBox/kiosk/openbox-rc.xml" &
else
  openbox &
fi
for d in "$HOME/ArcadeBox" /mnt/games/ArcadeBox; do
  if [ -f "$d/kiosk/linux-start.sh" ]; then
    exec sh "$d/kiosk/linux-start.sh"
  fi
done
echo "ArcadeBox bulunamadi" >> /tmp/arcadebox-kiosk.log
sleep 3600
XINIT
chmod +x "$HOME_DIR/.xinitrc"

# PAL zorlamayi kaldir
cat > "$HOME_DIR/.xprofile" <<'XPROF'
# stock VGA — PAL/xrandr zorlama yok
true
XPROF

# Bozuk .profile tamamen yaz
cat > "$HOME_DIR/.profile" <<'PROF'
# ~/.profile — Arcade Box
if [ -n "$BASH_VERSION" ]; then
  if [ -f "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
  fi
fi
PROF

cat > "$HOME_DIR/.bash_profile" <<EOF
# Arcade Box kiosk
if [ -f "\$HOME/.profile" ]; then
  . "\$HOME/.profile"
fi
if [ -z "\$DISPLAY" ] && [ "\$(tty)" = "/dev/tty1" ]; then
  exec startx "$HOME_DIR/.xinitrc" -- :0 vt1
fi
EOF

chown "$USER_NAME:$USER_NAME" \
  "$HOME_DIR/.xinitrc" "$HOME_DIR/.xprofile" \
  "$HOME_DIR/.profile" "$HOME_DIR/.bash_profile" "$CFG" 2>/dev/null || true

systemctl daemon-reload
systemctl set-default multi-user.target 2>/dev/null || true
pkill firefox-esr 2>/dev/null || true

echo
echo "Tamam. PAL576i / UseEDID / PreferredMode kaldirildi."
echo ">>> sudo reboot <<<"
echo
echo "LCD ve TV'de stok VGA (1024x768 veya 640x480) gelmeli."
echo "Hala cizgi: TV AV1 + VGA kablo anakartta mi kontrol."
