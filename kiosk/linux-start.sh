#!/bin/sh
# Pi 4 HDMI kiosk. SD'de OS, USB'de Arcade Box olabilir.
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
if [ ! -f "$ROOT/backend/arcadebox.py" ]; then
  for d in /media/*/ArcadeBox /media/*/*/ArcadeBox /mnt/arcade/ArcadeBox /mnt/*/ArcadeBox "$HOME/ArcadeBox"; do
    if [ -f "$d/backend/arcadebox.py" ]; then
      ROOT="$d"
      break
    fi
  done
fi
cd "$ROOT" || exit 1
xset s off 2>/dev/null
xset -dpms 2>/dev/null
xset s noblank 2>/dev/null
# Pi HDMI 50 Hz. Kabin PC (VGA/LCD) kendi yenilemesinde kalsin.
if [ -e /sys/firmware/devicetree/base/model ] && command -v xrandr >/dev/null 2>&1; then
  for out in HDMI-1 HDMI-2 HDMI-A-1 HDMI-A-2; do
    xrandr --output "$out" --mode 1280x720 --rate 50 2>/dev/null || \
    xrandr --output "$out" --mode 1920x1080 --rate 50 2>/dev/null || \
    xrandr --output "$out" --rate 50 2>/dev/null || true
  done
  xrandr -r 50 2>/dev/null || true
fi
unclutter -idle 0.4 -root >/dev/null 2>&1 &

wait=0
while [ "$wait" -lt 45 ]; do
  if [ -f "$ROOT/backend/arcadebox.py" ]; then
    break
  fi
  wait=$((wait + 1))
  sleep 1
done

URL="http://127.0.0.1:7842/"

# Kabin PC (x86_64): Chromium crash — Firefox ESR shell'den ac.
if [ "$(uname -m)" = "x86_64" ] && command -v firefox-esr >/dev/null 2>&1; then
  python3 backend/arcadebox.py --kiosk --no-browser &
  srv=$!
  sleep 2
  firefox-esr --kiosk "$URL" &
  wait $srv
  exit 0
fi

exec python3 backend/arcadebox.py --kiosk
