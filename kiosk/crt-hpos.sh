#!/bin/sh
# Arçelik CRT yatay kayma testi — sol siyah serit icin.
#   export DISPLAY=:0
#   sh kiosk/crt-hpos.sh
#
# Her adimda CRT'ye bak; en iyi goruntude Ctrl+C, son satirdaki mod/transform'i not al.
#
# NOT: Tum modlar AYNI gorunuyorsa sorun X11 degil, Firefox/UI olabilir.
#   git pull sonrasi config.json crt:true 720x576 olmali.
#   Ince ayar: config.json icinde "panX": -40 (sola), "panY": 0

export DISPLAY="${DISPLAY:-:0}"
OUT=""
for o in VGA-1 VGA-0 VGA1; do
  if xrandr --query 2>/dev/null | grep -q "^${o} connected"; then
    OUT="$o"
    break
  fi
done
[ -n "$OUT" ] || { echo "VGA yok"; exit 1; }

echo "=== CRT yatay hizalama ($OUT) ==="
echo "Aktif mod:"
xrandr --query | grep -E "^\s+\*?|connected"

add_mode() {
  name="$1"
  shift
  xrandr --newmode "$name" "$@" 2>/dev/null || true
  xrandr --addmode "$OUT" "$name" 2>/dev/null || true
}

# Standart PAL satir genisligi (htotal 864) — Arçelik cogu model
add_mode "PAL576-SCART" 13.50 720 738 846 864 576 582 587 625 interlace -hsync -vsync
add_mode "PAL576-SCARTp" 13.50 720 738 846 864 576 582 587 625 interlace +hsync +vsync

try() {
  desc="$1"
  mode="$2"
  tx="${3:-0}"
  echo ">>> $desc (transform x=$tx)"
  xrandr --output "$OUT" --mode "$mode" 2>/dev/null || return 1
  if [ "$tx" != "0" ]; then
    xrandr --output "$OUT" --transform 1,0,"$tx",0,1,0,0,0,1 2>/dev/null || true
  else
    xrandr --output "$OUT" --transform 1,0,0,0,1,0,0,0,1 2>/dev/null || true
  fi
  sleep 6
}

for m in PAL576-SCART PAL576-SCARTp PAL576-AR PAL576i; do
  try "$m" "$m" 0 || true
done

echo ">>> PAL576-SCART + sola kaydirma (transform)"
for tx in -0.04 -0.08 -0.12 -0.16 -0.20; do
  try "PAL576-SCART tx=$tx" "PAL576-SCART" "$tx" || true
done

echo
echo "En iyi mod/transform bulunca crt-arcelik.sh icine yazilir."
