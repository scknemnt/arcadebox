#!/bin/sh
# VGA-SCART: PAL576i + hpos (Arçelik — baska modlar goruntu vermeyebilir).
#   export DISPLAY=:0
#   sh kiosk/crt-xrandr-pal.sh

export DISPLAY="${DISPLAY:-:0}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  if xrandr --query 2>/dev/null | grep -q "^${o} connected"; then
    OUT="$o"
    break
  fi
done
[ -n "$OUT" ] || { echo "VGA yok"; xrandr --query 2>/dev/null; exit 1; }

add_mode() {
  name="$1"
  shift
  xrandr --newmode "$name" "$@" 2>/dev/null || true
  xrandr --addmode "$OUT" "$name" 2>/dev/null || true
}

add_mode "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync
add_mode "PAL576i-H1" 25.20 720 754 834 1611 576 581 586 625 interlace -hsync -vsync
add_mode "PAL576i-H2" 25.20 720 748 828 1611 576 581 586 625 interlace -hsync -vsync
add_mode "PAL576i-H3" 25.20 720 762 842 1611 576 581 586 625 interlace -hsync -vsync
add_mode "PAL576i-H4" 25.20 720 756 836 1611 576 581 586 625 interlace -hsync -vsync

PREF="${PREFERRED_MODE:-}"
HPOS="${HPOS_TRANSFORM:-}"
if [ -z "$HPOS" ] && [ -f "$ROOT/config.json" ]; then
  HPOS="$(python3 - "$ROOT/config.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8")).get("display", {})
    print(d.get("hpos", 0))
except Exception:
    print(0)
PY
)"
fi
if [ -z "$PREF" ] && [ -f "$ROOT/config.json" ]; then
  PREF="$(python3 - "$ROOT/config.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8")).get("display", {})
    print(d.get("preferredMode", "PAL576i"))
except Exception:
    print("PAL576i")
PY
)"
fi
[ -n "$PREF" ] || PREF="PAL576i"

apply_hpos() {
  if [ -n "$HPOS" ] && [ "$HPOS" != "0" ] && [ "$HPOS" != "0.0" ]; then
    xrandr --output "$OUT" --transform "1,0,$HPOS,0,1,0,0,0,1" 2>/dev/null && \
      echo "hpos transform=$HPOS" || echo "UYARI: transform uygulanamadi"
  else
    xrandr --output "$OUT" --transform 1,0,0,0,1,0,0,0,1 2>/dev/null || true
  fi
}

try_mode() {
  m="$1"
  if xrandr --output "$OUT" --mode "$m" 2>/dev/null; then
    xrandr --output "$OUT" --reflect normal 2>/dev/null || true
    apply_hpos
    echo "OK: $m on $OUT"
    xrandr --query | grep -E "connected|\*"
    return 0
  fi
  return 1
}

if try_mode "$PREF"; then exit 0; fi

for m in PAL576i PAL576i-H1 PAL576i-H2 PAL576i-H3 PAL576i-H4; do
  try_mode "$m" && exit 0
done

echo "PAL576i secilemedi:"
xrandr --query
exit 1
