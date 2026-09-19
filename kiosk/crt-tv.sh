#!/bin/sh
# LCD tamam, TV senkron degil: stok 31 kHz VGA PAL SCART'a uymaz.
# X ayaktayken PAL576i uygula (reboot yok).
#   cd /mnt/games/ArcadeBox
#   sh kiosk/crt-tv.sh

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
export DISPLAY="${DISPLAY:-:0}"
HOME_DIR="${HOME:-/home/arcadebox}"

if [ -z "${XAUTHORITY:-}" ]; then
  [ -f "$HOME_DIR/.Xauthority" ] && export XAUTHORITY="$HOME_DIR/.Xauthority"
  _auth="$(ps aux 2>/dev/null | awk '/Xorg.*:0/{for(i=1;i<=NF;i++) if($i=="-auth"){print $(i+1); exit}}')"
  [ -n "$_auth" ] && [ -f "$_auth" ] && export XAUTHORITY="$_auth"
fi

echo "=== CRT TV PAL576i ==="
echo "DISPLAY=$DISPLAY XAUTHORITY=${XAUTHORITY:-yok}"
echo "VGA kablo: anakart -> SCART kart -> TV AV1"

sh "$ROOT/kiosk/crt-xrandr-pal.sh"
