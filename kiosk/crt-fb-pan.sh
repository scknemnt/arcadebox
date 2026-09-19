#!/bin/sh
# Intel VGA transform calismiyorsa — framebuffer konumu dene.
#   export DISPLAY=:0
#   sh kiosk/crt-fb-pan.sh
#
# Her adim 6 sn kirmizi ekran. Ctrl+C ile cik.

export DISPLAY="${DISPLAY:-:0}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  xrandr --query 2>/dev/null | grep -q "^${o} connected" && OUT="$o" && break
done
[ -n "$OUT" ] || { echo "VGA yok"; exit 1; }

pkill firefox-esr 2>/dev/null || true
sleep 1
[ -f "$ROOT/kiosk/crt-xrandr-pal.sh" ] && sh "$ROOT/kiosk/crt-xrandr-pal.sh" || true

echo "=== Framebuffer konum testi ($OUT) ==="
echo "Soldaki siyah azaliyor mu? En iyi pos degerini not al."
echo

for pos in 0 -40 -80 -120 -160 -200 40 80 120; do
  echo ">>> --fb 960x576 --pos ${pos}x0"
  xrandr --fb 960x576 2>/dev/null || true
  xrandr --output "$OUT" --mode PAL576i --pos "${pos}x0" 2>/dev/null || \
    xrandr --output "$OUT" --pos "${pos}x0" 2>/dev/null || true
  xsetroot -solid "#cc0000" 2>/dev/null || true
  sleep 6
done

xrandr --fb 720x576 2>/dev/null || true
xrandr --output "$OUT" --pos 0x0 2>/dev/null || true
xsetroot -solid "#120404" 2>/dev/null || true
echo
echo "En iyi pos bulunduysa config.json:"
echo '  "display": { "fbPanX": -120 }'
echo "Sonra: sh kiosk/git-pull.sh && sudo reboot"
