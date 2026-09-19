#!/bin/sh
# DEPRECATED — Arçelik'te sadece PAL576i calisiyorsa:
#   sh kiosk/crt-pal576i-hpos.sh
#
# Eski: standart PAL 864 modlari (cogu TV'de goruntu vermez).
#   export DISPLAY=:0
#   sh kiosk/crt-timing-scan.sh

export DISPLAY="${DISPLAY:-:0}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  xrandr --query 2>/dev/null | grep -q "^${o} connected" && OUT="$o" && break
done
[ -n "$OUT" ] || { echo "VGA yok"; exit 1; }

pkill firefox-esr 2>/dev/null || true
sleep 1

add() {
  n="$1"
  shift
  xrandr --newmode "$n" "$@" 2>/dev/null || true
  xrandr --addmode "$OUT" "$n" 2>/dev/null || true
}

# htotal 864 = PAL TV beklentisi (Intel PAL576i 1611 kullanir — SCART'ta kayma yapar)
add "PAL576-864"  25.20 720 736 802 864 576 582 587 625 interlace -hsync -vsync
add "PAL576-L08"  25.20 720 728 810 864 576 582 587 625 interlace -hsync -vsync
add "PAL576-L16"  25.20 720 720 798 864 576 582 587 625 interlace -hsync -vsync
add "PAL576-L24"  25.20 720 712 786 864 576 582 587 625 interlace -hsync -vsync
add "PAL576-SCART" 13.50 720 738 846 864 576 582 587 625 interlace -hsync -vsync
add "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync

try() {
  m="$1"
  echo ">>> $m (8 sn — tam ekran renk)"
  xrandr --output "$OUT" --mode "$m" 2>/dev/null || { echo "    mod secilemedi"; return 1; }
  xrandr --output "$OUT" --transform 1,0,0,0,1,0,0,0,1 2>/dev/null || true
  xsetroot -solid "#cc0000"
  sleep 8
}

echo "=== PAL timing taramasi ($OUT) ==="
echo "Kirmizi tam ekran mi? Solda siyah var mi? En iyi modu not al."
echo

for m in PAL576-864 PAL576-L08 PAL576-L16 PAL576-L24 PAL576-SCART PAL576i; do
  try "$m" || true
done

xsetroot -solid "#120404"
echo
echo "En iyi mod bulunduysa:"
echo "  sh kiosk/crt-set-mode.sh PAL576-864"
echo "TV servis menusu H-POS da dene (Arçelik 3370 S)."
