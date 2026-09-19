#!/bin/sh
# SSH'den menu ac (reboot yok). X zaten aciksa (imlec varsa):
#   cd /mnt/games/ArcadeBox
#   sh kiosk/start-ui.sh

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
export DISPLAY="${DISPLAY:-:0}"
export MOZ_ENABLE_WAYLAND=0
export GDK_BACKEND=x11
HOME_DIR="${HOME:-/home/arcadebox}"

if [ -z "${XAUTHORITY:-}" ]; then
  [ -f "$HOME_DIR/.Xauthority" ] && export XAUTHORITY="$HOME_DIR/.Xauthority"
  _auth="$(ps aux 2>/dev/null | awk '/Xorg.*:0/{for(i=1;i<=NF;i++) if($i=="-auth"){print $(i+1); exit}}')"
  [ -n "$_auth" ] && [ -f "$_auth" ] && export XAUTHORITY="$_auth"
fi

if ! xset q >/dev/null 2>&1; then
  echo "X yok (DISPLAY=$DISPLAY). Once reboot veya tty1 startx."
  exit 1
fi

xsetroot -solid "#8b1a1a" 2>/dev/null || true
cd "$ROOT"

if ! python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:7842/', timeout=0.4)" >/dev/null 2>&1; then
  python3 backend/arcadebox.py --kiosk --no-browser >/tmp/arcadebox-ui.log 2>&1 &
  n=0
  while [ "$n" -lt 40 ]; do
    python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:7842/', timeout=0.2)" >/dev/null 2>&1 && break
    n=$((n + 1))
    sleep 0.1
  done
fi

FF_PROF="$HOME_DIR/.arcadebox-firefox"
mkdir -p "$FF_PROF"
rm -f "$FF_PROF/lock" "$FF_PROF/.parentlock" "$FF_PROF/parent.lock" 2>/dev/null || true
pkill -x firefox-esr 2>/dev/null || true
sleep 1

echo "Firefox aciliyor DISPLAY=$DISPLAY"
firefox-esr --kiosk --no-first-run --disable-session-restore --no-remote --profile "$FF_PROF" "http://127.0.0.1:7842/"
