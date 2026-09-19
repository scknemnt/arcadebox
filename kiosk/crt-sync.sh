#!/bin/sh
# TV senkron: once gercek saat nedir, sonra 15 kHz dene.
#   cd /mnt/games/ArcadeBox
#   sh kiosk/crt-sync.sh

export DISPLAY="${DISPLAY:-:0}"
HOME_DIR="${HOME:-/home/arcadebox}"

if [ -z "${XAUTHORITY:-}" ]; then
  [ -f "$HOME_DIR/.Xauthority" ] && export XAUTHORITY="$HOME_DIR/.Xauthority"
  _auth="$(ps aux 2>/dev/null | awk '/Xorg.*:0/{for(i=1;i<=NF;i++) if($i=="-auth"){print $(i+1); exit}}')"
  [ -n "$_auth" ] && [ -f "$_auth" ] && export XAUTHORITY="$_auth"
fi

if ! xrandr --query >/dev/null 2>&1; then
  echo "X yok. DISPLAY=$DISPLAY XAUTHORITY=${XAUTHORITY:-yok}"
  exit 1
fi

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  xrandr --query 2>/dev/null | grep -q "^${o} connected" && OUT="$o" && break
done
[ -n "$OUT" ] || { echo "VGA yok"; exit 1; }

echo "=== CRT sync ($OUT) ==="
echo "XAUTHORITY=${XAUTHORITY:-yok}"
echo
echo "--- aktif mod (*current). 15.64 kHz = PAL, 31+ kHz = TV kayar ---"
xrandr --verbose 2>/dev/null | awk '
  /\*current/ {print; c=1; next}
  c && /h:/ {print; next}
  c && /v:/ {print; c=0}
'

add() {
  xrandr --newmode "$1" $2 2>/dev/null || true
  xrandr --addmode "$OUT" "$1" 2>/dev/null || true
}

# 25.2 / 1611 = 15.64 kHz (Intel 13.5 MHz kabul etmez)
add PAL576i     "25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync"
add PAL576-AR   "25.20 720 744 808 1611 576 581 586 625 interlace -hsync -vsync"
add 640x480i15  "25.20 640 680 744 1611 480 483 486 525 interlace -hsync -vsync"

try() {
  m="$1"
  echo
  echo ">>> $m — TV ye 12 sn bak (kilit / kayma / cizgi)"
  xrandr --output "$OUT" --off 2>/dev/null || true
  sleep 1
  if xrandr --output "$OUT" --mode "$m" 2>/dev/null; then
    echo "secildi: $m"
    xrandr --verbose 2>/dev/null | awk '/\*|Clock|h:|v:/ {print; if (++n>=8) exit}'
  else
    echo "OLMADI: $m"
  fi
  sleep 12
}

try PAL576i
try 640x480i15
try PAL576-AR

echo
echo "En iyi moda donuluyor: PAL576i"
xrandr --output "$OUT" --mode PAL576i 2>/dev/null || true
echo
echo "Bitti. Hangi saniyede TV duzeldi? (PAL576i / 640x480i15 / PAL576-AR / hicbiri)"
echo "Hicbiri + saat 65 MHz kaldiysa Intel modeli uygulamadi."
