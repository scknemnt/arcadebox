#!/bin/sh
# X acildiktan sonra PAL576i (15.6 kHz). Boot'ta Xorg PreferredMode YOK.
#   export DISPLAY=:0
#   sh kiosk/crt-xrandr-pal.sh

export DISPLAY="${DISPLAY:-:0}"
HOME_DIR="${HOME:-/home/arcadebox}"

if [ -z "${XAUTHORITY:-}" ]; then
  [ -f "$HOME_DIR/.Xauthority" ] && export XAUTHORITY="$HOME_DIR/.Xauthority"
  _auth="$(ps aux 2>/dev/null | awk '/Xorg.*:0/{for(i=1;i<=NF;i++) if($i=="-auth"){print $(i+1); exit}}')"
  [ -n "$_auth" ] && [ -f "$_auth" ] && export XAUTHORITY="$_auth"
fi

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  if xrandr --query 2>/dev/null | grep -q "^${o} connected"; then
    OUT="$o"
    break
  fi
done
[ -n "$OUT" ] || { echo "VGA yok"; xrandr --query 2>/dev/null; exit 1; }

xrandr --newmode "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync 2>/dev/null || true
xrandr --addmode "$OUT" PAL576i 2>/dev/null || true

BACK=""
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
if [ -f "$ROOT/config.json" ]; then
  BACK="$(python3 - "$ROOT/config.json" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1], encoding="utf-8")).get("display", {}).get("hsyncBack") or "")
except Exception:
    print("")
PY
)"
fi

if [ -n "$BACK" ] && [ "$BACK" != "0" ]; then
  hse=$((1611 - BACK))
  hss=$((hse - 118))
  if [ "$hss" -gt 720 ]; then
    name="PAL576i-b${BACK}"
    xrandr --newmode "$name" 25.20 720 $hss $hse 1611 576 581 586 625 interlace -hsync -vsync 2>/dev/null || true
    xrandr --addmode "$OUT" "$name" 2>/dev/null || true
    if xrandr --output "$OUT" --mode "$name" 2>/dev/null; then
      echo "OK: $name back=$BACK on $OUT"
      xrandr --query | grep -E "connected|\*"
      exit 0
    fi
  fi
fi

if xrandr --output "$OUT" --mode PAL576i 2>/dev/null; then
  echo "OK: PAL576i on $OUT (15.6 kHz)"
  xrandr --query | grep -E "connected|\*"
  exit 0
fi

echo "PAL576i secilemedi:"
xrandr --query
exit 1
