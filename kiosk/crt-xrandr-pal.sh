#!/bin/sh
# VGA-SCART: Arçelik — SADECE PAL576i (baska modlar cizgi/siyah yapar).
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

xrandr --newmode "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync 2>/dev/null || true
xrandr --addmode "$OUT" PAL576i 2>/dev/null || true

xrandr --output "$OUT" --transform 1,0,0,0,1,0,0,0,1 2>/dev/null || true
xrandr --fb 720x576 2>/dev/null || true
xrandr --output "$OUT" --pos 0x0 2>/dev/null || true

if xrandr --output "$OUT" --mode PAL576i 2>/dev/null; then
  echo "OK: PAL576i on $OUT"
  xrandr --query | grep -E "connected|\*"
  exit 0
fi

if xrandr --output "$OUT" --mode 640x480 2>/dev/null; then
  echo "OK: 640x480 on $OUT (PAL576i olmadi)"
  xrandr --query | grep -E "connected|\*"
  exit 0
fi

echo "PAL576i secilemedi:"
xrandr --query
exit 1
