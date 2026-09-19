#!/bin/sh
# Görüntü gittiyse — framebuffer/mod sifirla, PAL576i geri getir.
#   export DISPLAY=:0
#   sh kiosk/crt-display-reset.sh
#   sudo reboot

export DISPLAY="${DISPLAY:-:0}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/config.json"

echo "=== CRT display reset ==="

python3 - "$CFG" <<'PY'
import json, sys
p = sys.argv[1]
try:
    cfg = json.load(open(p, encoding="utf-8"))
except Exception:
    cfg = {}
d = cfg.setdefault("display", {})
d["fbPanX"] = 0
d["hpos"] = 0
d["panX"] = 0
d["crt"] = True
d["width"] = 720
d["height"] = 576
d["preferredMode"] = "PAL576i"
d["output"] = "vga"
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open(p, "a").write("\n")
print("config: fbPanX=0 hpos=0 preferredMode=PAL576i")
PY

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  xrandr --query 2>/dev/null | grep -q "^${o} connected" && OUT="$o" && break
done

if [ -n "$OUT" ]; then
  xrandr --fb 720x576 2>/dev/null || true
  xrandr --output "$OUT" --transform 1,0,0,0,1,0,0,0,1 2>/dev/null || true
  xrandr --output "$OUT" --pos 0x0 2>/dev/null || true
  xrandr --output "$OUT" --reflect normal 2>/dev/null || true
  xrandr --newmode "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync 2>/dev/null || true
  xrandr --addmode "$OUT" PAL576i 2>/dev/null || true
  if xrandr --output "$OUT" --mode PAL576i 2>/dev/null; then
    echo "OK: PAL576i on $OUT"
  else
    xrandr --output "$OUT" --auto 2>/dev/null || true
    echo "UYARI: PAL576i secilemedi — xrandr --query"
    xrandr --query 2>/dev/null | head -20
  fi
  xsetroot -solid "#120404" 2>/dev/null || true
else
  echo "VGA cikisi bulunamadi"
fi

pkill firefox-esr 2>/dev/null || true
echo
echo "Simdi: sudo reboot"
echo "  veya: sh kiosk/linux-start.sh"
