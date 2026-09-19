#!/bin/sh
# PAL576i ayni zamanlama, 4 sync polaritesi.
#   cd /mnt/games/ArcadeBox
#   sh kiosk/crt-polarity.sh
#
# TV her adimda 10 sn: kilitlendi mi?

export DISPLAY="${DISPLAY:-:0}"
HOME_DIR="${HOME:-/home/arcadebox}"
if [ -z "${XAUTHORITY:-}" ]; then
  [ -f "$HOME_DIR/.Xauthority" ] && export XAUTHORITY="$HOME_DIR/.Xauthority"
  _auth="$(ps aux 2>/dev/null | awk '/Xorg.*:0/{for(i=1;i<=NF;i++) if($i=="-auth"){print $(i+1); exit}}')"
  [ -n "$_auth" ] && [ -f "$_auth" ] && export XAUTHORITY="$_auth"
fi

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  xrandr --query 2>/dev/null | grep -q "^${o} connected" && OUT="$o" && break
done
[ -n "$OUT" ] || { echo "VGA yok"; exit 1; }

echo "=== PAL576i polarite ($OUT) ==="
echo "Onceki log: 15.64 kHz GELIYOR. Polarite / SCART pin 16 (RGB) kaldi."

add() {
  xrandr --newmode "$1" $2 2>/dev/null || true
  xrandr --addmode "$OUT" "$1" 2>/dev/null || true
}

add PAL576i   "25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync"
add PAL576i-hp "25.20 720 768 848 1611 576 581 586 625 interlace +hsync -vsync"
add PAL576i-vp "25.20 720 768 848 1611 576 581 586 625 interlace -hsync +vsync"
add PAL576i-pp "25.20 720 768 848 1611 576 581 586 625 interlace +hsync +vsync"

try() {
  echo
  echo ">>> $1 — 10 sn TV"
  xrandr --output "$OUT" --mode "$1" 2>/dev/null || echo "olmadi"
  xrandr --verbose 2>/dev/null | awk '/\*.*current|Interlace \*current/ {print; getline; print; getline; print; exit}'
  sleep 10
}

try PAL576i
try PAL576i-hp
try PAL576i-vp
try PAL576i-pp

xrandr --output "$OUT" --mode PAL576i 2>/dev/null || true
echo
echo "Hangi isimde kilitlendi? Hicbiri: 74HC86 / Q1 Q2 / C4 C5 polarite / SCART 16 RGB."
