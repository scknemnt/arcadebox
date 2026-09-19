#!/bin/sh
# VGA-SCART: PAL modlarini xrandr ile ekle ve sec (Xorg config yuklenmese bile).
#   export DISPLAY=:0
#   sh kiosk/crt-xrandr-pal.sh

export DISPLAY="${DISPLAY:-:0}"

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  if xrandr --query 2>/dev/null | grep -q "^${o} connected"; then
    OUT="$o"
    break
  fi
done
[ -n "$OUT" ] || { echo "VGA cikisi yok"; xrandr --query 2>/dev/null; exit 1; }

add_mode() {
  name="$1"
  shift
  xrandr --newmode "$name" "$@" 2>/dev/null || true
  xrandr --addmode "$OUT" "$name" 2>/dev/null || true
}

add_mode "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync
add_mode "PAL576-AR" 25.20 720 744 808 1611 576 581 586 625 interlace -hsync -vsync
add_mode "PAL576-SCART" 13.50 720 738 846 864 576 582 587 625 interlace -hsync -vsync
add_mode "640x480-pal" 25.18 640 656 672 832 480 490 492 525 -hsync -vsync

xrandr --output "$OUT" --transform 1,0,0,0,1,0,0,0,1 2>/dev/null || true

for m in PAL576i PAL576-AR PAL576-SCART 640x480-pal 640x480; do
  if xrandr --output "$OUT" --mode "$m" 2>/dev/null; then
    echo "OK: $m on $OUT"
    xrandr --query | grep -E "connected|\*"
    exit 0
  fi
done

echo "PAL modu secilemedi — mevcut modlar:"
xrandr --query
exit 1
