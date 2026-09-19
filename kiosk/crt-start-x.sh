#!/bin/sh
# SSH'den X + menu baslat (Can't open display :0 ise).
#   cd /mnt/games/ArcadeBox
#   sh kiosk/crt-fix-boot.sh
#   sh kiosk/crt-start-x.sh

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HOME_DIR="${HOME:-/home/arcadebox}"
LOG=/tmp/arcadebox-startx.log

if ! pgrep -x Xorg >/dev/null 2>&1; then
  echo "X baslatiliyor (vt1)..."
  if command -v openvt >/dev/null 2>&1; then
    sudo openvt -c 1 -f -- runuser -l arcadebox -c \
      "exec startx $HOME_DIR/.xinitrc -- :0 vt1 -nocursor >>$LOG 2>&1" &
  else
    sudo runuser -l arcadebox -c \
      "exec startx $HOME_DIR/.xinitrc -- :0 vt1 -nocursor >>$LOG 2>&1" &
  fi
  n=0
  while [ "$n" -lt 30 ]; do
    if pgrep -x Xorg >/dev/null 2>&1; then
      echo "Xorg calisiyor."
      break
    fi
    n=$((n + 1))
    sleep 1
  done
  if ! pgrep -x Xorg >/dev/null 2>&1; then
    echo "X baslamadi. Log:"
    tail -30 "$LOG" 2>/dev/null || true
    tail -20 "$HOME_DIR/.local/share/xorg/Xorg.0.log" 2>/dev/null || true
    exit 1
  fi
else
  echo "Xorg zaten calisiyor."
fi

sleep 2
export DISPLAY=:0
if [ -f "$ROOT/kiosk/crt-xrandr-pal.sh" ]; then
  sh "$ROOT/kiosk/crt-xrandr-pal.sh" || true
fi

if ! pgrep firefox-esr >/dev/null 2>&1; then
  echo "Firefox baslatiliyor..."
  runuser -l arcadebox -c "cd '$ROOT' && sh kiosk/linux-start.sh" >>"$LOG" 2>&1 &
  sleep 5
fi

export DISPLAY=:0
xrandr --query 2>/dev/null | grep -E 'connected|\*' || true
pgrep -a Xorg || true
pgrep -a firefox || true
echo "Log: $LOG"
