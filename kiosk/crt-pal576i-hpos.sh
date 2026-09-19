#!/bin/sh
# PAL576i uzerinde yatay hizalama (Arçelik SCART).
# Baska modlar goruntu vermiyorsa SADECE PAL576i + transform/modeline dene.
#   export DISPLAY=:0
#   sh kiosk/crt-pal576i-hpos.sh
#
# Her adim 6 sn — CRT'ye bak. En iyi adimda Ctrl+C, satiri not al.

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

add "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync
add "PAL576i-H1" 25.20 720 754 834 1611 576 581 586 625 interlace -hsync -vsync
add "PAL576i-H2" 25.20 720 748 828 1611 576 581 586 625 interlace -hsync -vsync
add "PAL576i-H3" 25.20 720 762 842 1611 576 581 586 625 interlace -hsync -vsync
add "PAL576i-H4" 25.20 720 756 836 1611 576 581 586 625 interlace -hsync -vsync

try_mode() {
  m="$1"
  echo ">>> mod $m"
  xrandr --output "$OUT" --mode "$m" 2>/dev/null || { echo "    secilemedi"; return 1; }
  xrandr --output "$OUT" --transform 1,0,0,0,1,0,0,0,1 2>/dev/null || true
  xsetroot -solid "#cc0000" 2>/dev/null || true
  sleep 6
}

try_tx() {
  tx="$1"
  echo ">>> PAL576i transform x=$tx"
  xrandr --output "$OUT" --mode PAL576i 2>/dev/null || true
  xrandr --output "$OUT" --transform "1,0,$tx,0,1,0,0,0,1" 2>/dev/null || true
  xsetroot -solid "#0066cc" 2>/dev/null || true
  sleep 6
}

echo "=== PAL576i yatay hizalama ($OUT) ==="
echo "Kirmizi/mavi tam ekran mi? Soldaki siyah azaldi mi?"
echo

xrandr --output "$OUT" --mode PAL576i 2>/dev/null || true

for m in PAL576i PAL576i-H1 PAL576i-H2 PAL576i-H3 PAL576i-H4; do
  try_mode "$m" || true
done

echo ">>> transform taramasi (PAL576i)"
for tx in 0 -0.05 -0.10 -0.15 -0.20 -0.25 -0.30 -0.35 -0.40 -0.45; do
  try_tx "$tx" || true
done

xsetroot -solid "#120404" 2>/dev/null || true
echo
echo "Kalici kaydet:"
echo "  sudo sh kiosk/crt-set-mode.sh PAL576i -0.20"
echo "  sudo sh kiosk/crt-set-mode.sh PAL576i-H2"
echo "TV servis menusu H-POS da dene (Arçelik)."
