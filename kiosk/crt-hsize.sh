#!/bin/sh
# Sol kenar kilitli (945'te sola sifir). H buyuyunce SADECE saga genisler.
# Back porch sabit 238 (b350 + w945). Dikey 576 ayni.
#
#   sh kiosk/crt-hsize.sh           # saga tarama
#   sh kiosk/crt-hsize.sh 1100      # kilitle + firefox kapat

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
BACK=238
VT="576 581 586 625 interlace -hsync -vsync"

apply_w() {
  H="$1"
  hse=$((HTOT - BACK))
  hss=$((hse - SYNCW))
  front=$((hss - H))
  if [ "$front" -lt 8 ] || [ "$H" -ge "$hss" ]; then
    echo "atla H=$H front=$front (max ~$((hss - 8)))"
    return 1
  fi
  name="PAL576i-w${H}"
  echo ">>> $name  $H $hss $hse $HTOT  front=$front sync=$SYNCW back=$BACK (sol kilit)"
  xrandr --newmode "$name" $CLK $H $hss $hse $HTOT $VT 2>/dev/null || true
  xrandr --addmode "$OUT" "$name" 2>/dev/null || true
  xrandr --output "$OUT" --mode "$name" 2>/dev/null || { echo "    secilemedi"; return 1; }
  return 0
}

save_cfg() {
  H="$1"
  python3 - "$ROOT/config.json" "$H" "$BACK" <<'PY'
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
print("config: hdisplay=%s hsyncBack=%s (sol kilit)" % (w, b))
PY
}

echo "=== PAL576i saga genislet ($OUT) sol=back $BACK ==="
echo "Firefox eski boyutta kalirsa goruntu UZAMAZ. Her kilitlemede pkill sart."
echo

if [ -n "${1:-}" ]; then
  apply_w "$1" || exit 1
  save_cfg "$1"
  pkill firefox-esr 2>/dev/null || true
  echo "Tamam. Simdi: sh kiosk/linux-start.sh"
  exit 0
fi

for H in 945 1020 1100 1180 1240; do
  apply_w "$H" || true
  sleep 8
done

apply_w 1100 || apply_w 945 || true
echo
echo "Sag kenar oturunca: sh kiosk/crt-hsize.sh 1100 && sh kiosk/linux-start.sh"
