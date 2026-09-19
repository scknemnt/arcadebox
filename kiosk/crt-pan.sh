#!/bin/sh
# CRT kayma ince ayar.
#   sh kiosk/crt-pan.sh -120          # Firefox/CSS (yazilim)
#   sh kiosk/crt-pan.sh xrandr -0.12  # VGA cikisi (timing/donanim)
#   sh kiosk/crt-pan.sh -120 -0.12    # ikisi birden

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/config.json"
export DISPLAY="${DISPLAY:-:0}"

MODE="css"
PANX="0"
PANY="0"
HPOS="0"

case "${1:-}" in
  xrandr|hpos)
    MODE="xrandr"
    HPOS="${2:-0}"
    ;;
  *)
    PANX="${1:-0}"
    PANY="${2:-0}"
    if [ "$PANY" != "0" ] && echo "$PANY" | grep -q '^-'; then
      HPOS="$PANY"
      PANY="0"
    fi
    ;;
esac

python3 - "$CFG" "$PANX" "$PANY" "$HPOS" <<'PY'
import json, sys
path = sys.argv[1]
panx, pany, hpos = float(sys.argv[2]), float(sys.argv[3]), float(sys.argv[4])
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)
d = cfg.setdefault("display", {})
d["panX"] = panx
d["panY"] = pany
d["hpos"] = hpos
d["crt"] = True
d["width"] = 720
d["height"] = 576
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"panX={panx} panY={pany} hpos={hpos} -> {path}")
PY

if [ "$HPOS" != "0" ] && command -v xrandr >/dev/null 2>&1; then
  for out in VGA-1 VGA-0 VGA1; do
    if xrandr --query 2>/dev/null | grep -q "^${out} connected"; then
      xrandr --output "$out" --transform "1,0,$HPOS,0,1,0,0,0,1" 2>/dev/null && \
        echo "xrandr transform uygulandi: $HPOS on $out"
      break
    fi
  done
fi

echo "Tam etki icin: sudo reboot"
