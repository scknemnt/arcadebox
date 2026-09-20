#!/bin/sh
# PAL576i-b250 merkezli, aktif genislik tarama (15.64 kHz, htotal 1611).
#   sh kiosk/crt-hsize.sh           # 8 sn adimlar
#   sh kiosk/crt-hsize.sh 1000      # kalici

export DISPLAY="${DISPLAY:-:0}"
HOME_DIR="${HOME:-/home/arcadebox}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

if [ -z "${XAUTHORITY:-}" ]; then
  [ -f "$HOME_DIR/.Xauthority" ] && export XAUTHORITY="$HOME_DIR/.Xauthority"
  _auth="$(ps aux 2>/dev/null | awk '/Xorg.*:0/{for(i=1;i<=NF;i++) if($i=="-auth"){print $(i+1); exit}}')"
  [ -n "$_auth" ] && [ -f "$_auth" ] && export XAUTHORITY="$_auth"
fi

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  xrandr --query 2>/dev/null | grep -q "^${o} connected" && OUT="$o" && break
done
[ -n "$OUT" ] || { echo "VGA yok"; exit 1; }

CLK="25.20"
HTOT=1611
SYNCW=118
H0=720
B0=250
VT="576 581 586 625 interlace -hsync -vsync"

apply_w() {
  H="$1"
  d=$((H - H0))
  back=$((B0 - d / 2))
  hse=$((HTOT - back))
  hss=$((hse - SYNCW))
  front=$((hss - H))
  if [ "$back" -lt 40 ] || [ "$front" -lt 8 ] || [ "$hss" -le "$H" ]; then
    echo "atla H=$H back=$back front=$front"
    return 1
  fi
  name="PAL576i-w${H}"
  echo ">>> $name  $H $hss $hse $HTOT  front=$front sync=$SYNCW back=$back"
  xrandr --newmode "$name" $CLK $H $hss $hse $HTOT $VT 2>/dev/null || true
  xrandr --addmode "$OUT" "$name" 2>/dev/null || true
  xrandr --output "$OUT" --mode "$name" 2>/dev/null || { echo "    secilemedi"; return 1; }
  return 0
}

save_cfg() {
  H="$1"
  d=$((H - H0))
  back=$((B0 - d / 2))
  python3 - "$ROOT/config.json" "$H" "$back" <<'PY'
import json, sys
p, w, b = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
cfg = json.load(open(p, encoding="utf-8"))
d = cfg.setdefault("display", {})
d.update({
    "crt": True, "output": "vga",
    "width": w, "height": 576,
    "hdisplay": w, "hsyncBack": b,
    "preferredMode": "PAL576i",
})
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open(p, "a").write("\n")
print("config: hdisplay=%s hsyncBack=%s" % (w, b))
PY
}

echo "=== PAL576i genislik ($OUT)  merkez=b250 ==="
echo "H buyuyunce TV'de sag-sol dolar. Kilit bozulursa bir onceki."
echo

if [ -n "${1:-}" ]; then
  apply_w "$1" || exit 1
  save_cfg "$1"
  echo "Firefox: pkill firefox-esr; sh kiosk/linux-start.sh"
  exit 0
fi

for H in 720 840 920 1000 1080 1140; do
  apply_w "$H" || true
  sleep 8
done

apply_w 1000 || apply_w 920 || true
echo
echo "En iyi genislik:"
echo "  sh kiosk/crt-hsize.sh 1000"
echo "Sonra: pkill firefox-esr; sh kiosk/linux-start.sh"
