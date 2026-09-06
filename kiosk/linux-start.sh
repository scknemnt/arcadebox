#!/bin/sh
# Arcade Box kiosk — systemd / startx
# Log: /tmp/arcadebox-kiosk.log

LOG=/tmp/arcadebox-kiosk.log
exec >>"$LOG" 2>&1
echo "=== $(date) linux-start ==="

export DISPLAY="${DISPLAY:-:0}"

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
if [ ! -f "$ROOT/backend/arcadebox.py" ]; then
  for d in /mnt/games/ArcadeBox /mnt/arcade/ArcadeBox /media/*/ArcadeBox /media/*/*/ArcadeBox /mnt/*/ArcadeBox "$HOME/ArcadeBox"; do
    if [ -f "$d/backend/arcadebox.py" ]; then
      ROOT="$d"
      break
    fi
  done
fi

# HDD gec baglanirsa bekle
wait=0
while [ "$wait" -lt 60 ]; do
  if [ -f "$ROOT/backend/arcadebox.py" ]; then
    break
  fi
  mount /mnt/games 2>/dev/null || mount -a 2>/dev/null || true
  if [ -f /mnt/games/ArcadeBox/backend/arcadebox.py ]; then
    ROOT="/mnt/games/ArcadeBox"
    break
  fi
  wait=$((wait + 1))
  sleep 1
done

if [ ! -f "$ROOT/backend/arcadebox.py" ]; then
  echo "HATA: ArcadeBox bulunamadi. lsblk + fstab kontrol."
  lsblk >>"$LOG" 2>&1
  cat /etc/fstab >>"$LOG" 2>&1
  sleep 300
  exit 1
fi

cd "$ROOT" || exit 1
echo "ROOT=$ROOT"

xset s off 2>/dev/null
xset -dpms 2>/dev/null
xset s noblank 2>/dev/null

if [ -e /sys/firmware/devicetree/base/model ] && command -v xrandr >/dev/null 2>&1; then
  for out in HDMI-1 HDMI-2 HDMI-A-1 HDMI-A-2; do
    xrandr --output "$out" --mode 1280x720 --rate 50 2>/dev/null || \
    xrandr --output "$out" --mode 1920x1080 --rate 50 2>/dev/null || \
    xrandr --output "$out" --rate 50 2>/dev/null || true
  done
  xrandr -r 50 2>/dev/null || true
fi

if [ "$(uname -m)" = "x86_64" ] && command -v xrandr >/dev/null 2>&1; then
  for out in VGA-1 VGA-0 HDMI-1; do
    xrandr --output "$out" --auto 2>/dev/null && break
  done
fi

unclutter -idle 0.4 -root >/dev/null 2>&1 &

# Firefox / menu muzigi icin ses sunucusu (minimal Debian'da yok)
if command -v pipewire >/dev/null 2>&1; then
  pipewire >/dev/null 2>&1 &
  wireplumber >/dev/null 2>&1 &
  sleep 1
elif command -v pulseaudio >/dev/null 2>&1; then
  pulseaudio --daemonize=true 2>/dev/null || true
fi

URL="http://127.0.0.1:7842/"

if [ "$(uname -m)" = "x86_64" ] && command -v firefox-esr >/dev/null 2>&1; then
  modprobe joydev 2>/dev/null || true
  FF_BASE="$HOME/.mozilla/firefox-esr"
  mkdir -p "$FF_BASE"
  for prof in "$FF_BASE"/*.default-esr "$FF_BASE"/*.default; do
    [ -d "$prof" ] || continue
    touch "$prof/user.js"
    sed -i '/media.autoplay/d;/dom.gamepad/d;/browser.display.background_color/d;/browser.display.use_system_colors/d;/browser.cache.disk.enable/d' "$prof/user.js" 2>/dev/null || true
    cat >>"$prof/user.js" <<'EOF'
user_pref("media.autoplay.default", 0);
user_pref("media.autoplay.enabled", true);
user_pref("media.autoplay.block-webaudio", false);
user_pref("media.autoplay.allow-muted", true);
user_pref("media.block-autoplay-until-in-foreground", false);
user_pref("dom.gamepad.enabled", true);
user_pref("dom.gamepad.non_standard_events.enabled", true);
user_pref("browser.display.background_color", "#120404");
user_pref("browser.display.use_system_colors", false);
user_pref("browser.cache.disk.enable", true);
EOF
  done
  python3 backend/arcadebox.py --kiosk --no-browser &
  srv=$!
  sleep 1
  if ! kill -0 "$srv" 2>/dev/null; then
    echo "HATA: python server hemen kapandi"
    wait "$srv" 2>/dev/null || true
    exit 1
  fi
  echo "python pid=$srv, firefox-esr aciliyor DISPLAY=$DISPLAY"
  exec firefox-esr --kiosk --no-first-run --disable-session-restore --no-remote "$URL"
fi

exec python3 backend/arcadebox.py --kiosk
