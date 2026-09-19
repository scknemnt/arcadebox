#!/bin/sh
# UYARI: Bu test bazi Intel VGA'larda goruntuyu bozabilir.
# Bitince MUTLAKA: sh kiosk/crt-display-reset.sh
#
#   export DISPLAY=:0
#   sh kiosk/crt-fb-pan.sh

export DISPLAY="${DISPLAY:-:0}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

trap 'sh "$ROOT/kiosk/crt-display-reset.sh"' EXIT INT TERM

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  xrandr --query 2>/dev/null | grep -q "^${o} connected" && OUT="$o" && break
done
[ -n "$OUT" ] || { echo "VGA yok"; exit 1; }

pkill firefox-esr 2>/dev/null || true
sleep 1
sh "$ROOT/kiosk/crt-display-reset.sh" 2>/dev/null || true

echo "=== Framebuffer konum testi ($OUT) ==="
echo "Bitince otomatik reset yapilir. Ctrl+C = reset + cikis."
echo

for pos in 0 -40 -80 -120 -160 -200; do
  echo ">>> --fb 960x576 --pos ${pos}x0"
  xrandr --fb 960x576 2>/dev/null || true
  xrandr --output "$OUT" --mode PAL576i --pos "${pos}x0" 2>/dev/null || true
  xsetroot -solid "#cc0000" 2>/dev/null || true
  sleep 6
done

echo "Test bitti — reset uygulaniyor..."
