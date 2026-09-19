#!/bin/sh
# panX taramasi — transform calismiyorsa Firefox icinde sola kaydir.
#   export DISPLAY=:0
#   sh kiosk/crt-pan-scan.sh
#
# Her deger 8 sn. Menü hizalaninca Ctrl+C, degeri not al.

export DISPLAY="${DISPLAY:-:0}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/config.json"

for px in 0 -80 -120 -160 -200 -240 -280 -320; do
  echo ">>> panX=$px (8 sn)"
  python3 - "$CFG" "$px" <<'PY'
import json, sys
p, x = sys.argv[1], float(sys.argv[2])
cfg = json.load(open(p, encoding="utf-8"))
cfg.setdefault("display", {})["panX"] = x
cfg["display"]["crt"] = True
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open(p, "a").write("\n")
PY
  pkill firefox-esr 2>/dev/null || true
  sleep 1
  python3 "$ROOT/backend/arcadebox.py" --kiosk --no-browser >/dev/null 2>&1 &
  sleep 2
  firefox-esr --kiosk --no-remote --profile "$HOME/.arcadebox-firefox" \
    "http://127.0.0.1:7842/?pan=$px" >/dev/null 2>&1 &
  sleep 8
done

echo
echo "En iyi panX:"
echo "  sh kiosk/crt-pan.sh -240"
echo "  sudo reboot"
