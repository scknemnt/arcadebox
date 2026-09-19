#!/bin/sh
# Renk test / fb-pan / timing taramasi sonrasi TAM GERI ALMA.
# Calisan durum: commit 03bb4b6 (PAL576i + menu, kayma olabilir).
#
#   cd /mnt/games/ArcadeBox
#   sh kiosk/git-pull.sh
#   sudo sh kiosk/crt-rollback.sh
#   sudo reboot

set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-rollback.sh"
  exit 1
fi

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
USER_NAME="${SUDO_USER:-arcadebox}"
HOME_DIR="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="/home/$USER_NAME"
CFG="$ROOT/config.json"

echo "=== CRT rollback (03bb4b6) ==="
echo "Kullanici: $USER_NAME  ArcadeBox: $ROOT"

mount /mnt/games 2>/dev/null || mount -a 2>/dev/null || true
ln -sfn /mnt/games/ArcadeBox "$HOME_DIR/ArcadeBox" 2>/dev/null || true
chown -R "$USER_NAME:$USER_NAME" "$ROOT" 2>/dev/null || true

usermod -aG video,tty,input,audio,render,sudo "$USER_NAME" 2>/dev/null || true
loginctl enable-linger "$USER_NAME" 2>/dev/null || true

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
    "crt": True, "width": 720, "height": 576,
    "preferredMode": "PAL576i", "output": "vga",
})
cfg["theme"] = "amiga-crt"
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open(p, "a").write("\n")
print("config.json sifirlandi (PAL576i, pan/hpos=0)")
PY

# --- Boot: debian-kiosk-fix (kanitli) ---
systemctl disable arcadebox-kiosk.service 2>/dev/null || true
systemctl stop arcadebox-kiosk.service 2>/dev/null || true

mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin ${USER_NAME} --noclear %I \$TERM
EOF
systemctl enable getty@tty1.service 2>/dev/null || true

cat > "$HOME_DIR/.xinitrc" <<'XINIT'
#!/bin/sh
xsetroot -solid "#1a0505" 2>/dev/null || true
xset s off
xset -dpms
xset s noblank
openbox &
mount /mnt/games 2>/dev/null || mount -a 2>/dev/null || true
for d in "$HOME/ArcadeBox" /mnt/games/ArcadeBox; do
  if [ -f "$d/kiosk/linux-start.sh" ]; then
    exec sh "$d/kiosk/linux-start.sh"
  fi
done
echo "ArcadeBox bulunamadi" >> /tmp/arcadebox-kiosk.log
sleep 120
XINIT
chmod +x "$HOME_DIR/.xinitrc"

cat > "$HOME_DIR/.profile" <<'PROF'
# ~/.profile — Arcade Box (temiz)
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
  exec startx "$HOME_DIR/.xinitrc" -- :0 vt1 -nocursor
fi
EOF

cat > "$HOME_DIR/.xprofile" <<'XPROF'
export DISPLAY="${DISPLAY:-:0}"
sleep 2
for d in /mnt/games/ArcadeBox "$HOME/ArcadeBox"; do
  [ -f "$d/kiosk/crt-xrandr-pal.sh" ] && sh "$d/kiosk/crt-xrandr-pal.sh" && break
done
XPROF

# --- Xorg: PAL576i guvenli boot (crt-recover) ---
INTEL_BUS=""
if command -v lspci >/dev/null 2>&1; then
  _slot="$(lspci 2>/dev/null | awk '/VGA|Display/ && /Intel|8086/ { print $1; exit }')"
  if [ -n "$_slot" ]; then
    _b=$((16#$(echo "$_slot" | cut -d: -f1)))
    _d=$(echo "$_slot" | cut -d: -f2 | cut -d. -f1)
    _f=$(echo "$_slot" | cut -d. -f2)
    INTEL_BUS="PCI:${_b}:${_d}:${_f}"
  fi
fi

mkdir -p /etc/X11/xorg.conf.d
rm -f /etc/X11/xorg.conf.d/20-arcade-scart.conf
cat > /etc/X11/xorg.conf.d/10-arcadebox.conf <<EOF
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
        Modes "PAL576i" "640x480"
    EndSubSection
EndSection
Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
EOF

chown "$USER_NAME:$USER_NAME" "$HOME_DIR/.xinitrc" "$HOME_DIR/.xprofile" \
  "$HOME_DIR/.profile" "$HOME_DIR/.bash_profile" "$CFG" 2>/dev/null || true

systemctl daemon-reload
systemctl set-default multi-user.target 2>/dev/null || true

pkill firefox-esr 2>/dev/null || true

echo
echo "Tamam. Ayarlar renk testinden ONCEKI haline alindi."
echo ">>> sudo reboot <<<"
echo
echo "Reboot sonrasi SSH test:"
echo "  export DISPLAY=:0 && xrandr --query | grep '\\*'"
echo "  tail -20 /tmp/arcadebox-kiosk.log"
