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

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
# Arcelik: w840, b350 merkez → back=290. Config varsa onu kullan.
HDISP="1240"
BACK="238"
if [ -f "$ROOT/config.json" ]; then
  eval "$(python3 - "$ROOT/config.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8")).get("display", {})
    hd = d.get("hdisplay")
    bk = d.get("hsyncBack")
    if hd and int(hd) != 720:
        print("HDISP=%s" % hd)
        if bk:
            print("BACK=%s" % bk)
except Exception:
    pass
PY
)"
fi

if [ -n "$HDISP" ] && [ -n "$BACK" ] && [ "$HDISP" != "720" -o "$BACK" != "0" ]; then
  hse=$((1611 - BACK))
  hss=$((hse - 118))
  if [ "$hss" -gt "$HDISP" ] && [ "$HDISP" -ge 640 ]; then
    name="PAL576i-w${HDISP}"
    xrandr --newmode "$name" 25.20 "$HDISP" $hss $hse 1611 576 581 586 625 interlace -hsync -vsync 2>/dev/null || true
    xrandr --addmode "$OUT" "$name" 2>/dev/null || true
    if xrandr --output "$OUT" --mode "$name" 2>/dev/null; then
      echo "OK: $name H=$HDISP back=$BACK on $OUT"
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
