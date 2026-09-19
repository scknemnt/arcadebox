#!/bin/sh
# CRT saga kayma — donanim mi yazilim mi?
#   export DISPLAY=:0
#   sh kiosk/crt-shift-test.sh
#
# 1) Kirmizi tam ekran: solda siyah serit varsa DONANIM/timing (xrandr/TV H-POS)
# 2) Sadece Firefox kayik, kirmizi tam: YAZILIM (panX)

export DISPLAY="${DISPLAY:-:0}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  xrandr --query 2>/dev/null | grep -q "^${o} connected" && OUT="$o" && break
done
[ -n "$OUT" ] || { echo "VGA yok"; exit 1; }

if [ -f "$ROOT/kiosk/crt-xrandr-pal.sh" ]; then
  sh "$ROOT/kiosk/crt-xrandr-pal.sh" || true
fi

echo "=== CRT kayma testi ($OUT) ==="
echo "Her adimda CRT'ye bak. Bitirmek icin Ctrl+C."
echo

try() {
  desc="$1"
  shift
  echo ">>> $desc"
  "$@" 2>/dev/null || true
  sleep 5
}

try "TAM KIRMIZI (xsetroot) — solda siyah var mi?" xsetroot -solid "#cc0000"
try "TAM YESIL" xsetroot -solid "#00aa00"
try "TAM MAVI" xsetroot -solid "#0000cc"

for tx in 0 -0.06 -0.10 -0.14 -0.18 -0.22; do
  try "xrandr transform x=$tx (tum cikti kayar)" \
    xrandr --output "$OUT" --transform "1,0,$tx,0,1,0,0,0,1"
done

try "transform sifir" xrandr --output "$OUT" --transform "1,0,0,0,1,0,0,0,1"

if [ -f "$ROOT/frontend/crt-test.html" ]; then
  echo ">>> Firefox test sayfasi (720x576 cerceve)"
  pkill firefox-esr 2>/dev/null || true
  sleep 1
  python3 "$ROOT/backend/arcadebox.py" --kiosk --no-browser >/dev/null 2>&1 &
  sleep 2
  firefox-esr --kiosk "http://127.0.0.1:7842/crt-test.html" 2>/dev/null &
  sleep 8
fi

echo
echo "Sonuc:"
echo "  Kirmizi de saga kayiksa -> timing/TV H-POS veya SCART sync (74HC86 daha cok resim yok/kayma yapar)"
echo "  Kirmizi tam, menu kayiksa -> sh kiosk/crt-pan.sh -120 && sudo reboot"
echo "  En iyi transform degerini: sh kiosk/crt-pan.sh xrandr -0.12"
