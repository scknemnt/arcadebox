#!/bin/sh
# PAL576i H-sync (htotal 1611 sabit — 15.64 kHz bozulmasin).
# Goruntu sagdaysa arka porch buyuk: sync'i saga (htotal'e) cek.
#
#   cd /mnt/games/ArcadeBox
#   sh kiosk/crt-hsync.sh          # tarama (8 sn, Firefox acik kalsin)
#   sh kiosk/crt-hsync.sh 146      # tek deger uygula
#
# Mevcut: 720 768 848 1611  → front=48  sync=80  back=763  (sagda %50)
# PAL olcekli: back ~146 (5.8 us @ 25.2 MHz)

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

# 25.20 720 576i 1611  — polarite calisan PAL576i ile ayni
CLK="25.20"
HDISP=720
HTOT=1611
SYNCW=118
VT="576 581 586 625 interlace -hsync -vsync"

apply_back() {
  back="$1"
  hsyncend=$((HTOT - back))
  hsyncstart=$((hsyncend - SYNCW))
  if [ "$hsyncstart" -le "$HDISP" ]; then
    echo "atla back=$back (hsyncstart $hsyncstart <= $HDISP)"
    return 1
  fi
  name="PAL576i-b${back}"
  front=$((hsyncstart - HDISP))
  echo ">>> $name  720 $hsyncstart $hsyncend $HTOT  front=$front sync=$SYNCW back=$back"
  xrandr --newmode "$name" $CLK $HDISP $hsyncstart $hsyncend $HTOT $VT 2>/dev/null || true
  xrandr --addmode "$OUT" "$name" 2>/dev/null || true
  xrandr --output "$OUT" --mode "$name" 2>/dev/null || {
    echo "    secilemedi"
    return 1
  }
  return 0
}

echo "=== PAL576i H-sync ($OUT) ==="
echo "htotal=$HTOT sabit (15.64 kHz). back kuculunce goruntu SOLA kayar."
echo

if [ -n "${1:-}" ]; then
  apply_back "$1" || exit 1
  echo "Kalici icin config'e yazilacak: display.hsyncBack=$1"
  if [ -f "$ROOT/config.json" ]; then
    python3 - "$ROOT/config.json" "$1" <<'PY'
import json, sys
p, b = sys.argv[1], int(sys.argv[2])
cfg = json.load(open(p, encoding="utf-8"))
d = cfg.setdefault("display", {})
d["hsyncBack"] = b
d["preferredMode"] = "PAL576i"
d["crt"] = True
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open(p, "a").write("\n")
print("config.json hsyncBack=%s" % b)
PY
  fi
  exit 0
fi

# 763 = simdi (sagda). 146 = PAL us. Ara adimlar.
for b in 763 500 350 250 180 146 110; do
  apply_back "$b" || true
  sleep 8
done

apply_back 146 || apply_back 180 || true
echo
echo "En iyi back degeri (goruntu ortada, kilit duruyor):"
echo "  sh kiosk/crt-hsync.sh 146"
echo "  (146 dar/sol, 250-350 orta, 500 hala sag)"
