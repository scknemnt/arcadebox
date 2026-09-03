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
unclutter -idle 0.4 -root >/dev/null 2>&1 &
exec python3 backend/arcadebox.py --kiosk
