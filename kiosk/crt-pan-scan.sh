#!/bin/sh
# panX taramasi — SADECE Firefox CSS (fb degistirmez).
# Bitince reset + PAL576i.
#   export DISPLAY=:0
#   sh kiosk/crt-pan-scan.sh

export DISPLAY="${DISPLAY:-:0}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/config.json"

trap 'sh "$ROOT/kiosk/crt-display-reset.sh"' EXIT INT TERM

sh "$ROOT/kiosk/crt-display-reset.sh" 2>/dev/null || true
pkill firefox-esr 2>/dev/null || true
sleep 1

echo "=== panX taramasi (Ctrl+C = reset) ==="

for px in 0 -80 -120 -160 -200 -240 -280; do
  echo ">>> panX=$px (8 sn)"
  python3 - "$CFG" "$px" <<'PY'
import json, sys
p, x = sys.argv[1], float(sys.argv[2])
cfg = json.load(open(p, encoding="utf-8"))
d = cfg.setdefault("display", {})
d["panX"] = x
d["fbPanX"] = 0
d["hpos"] = 0
d["crt"] = True
d["preferredMode"] = "PAL576i"
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open(p, "a").write("\n")
PY
  sh "$ROOT/kiosk/crt-display-reset.sh" 2>/dev/null || true
  pkill firefox-esr 2>/dev/null || true
  sleep 1
  python3 "$ROOT/backend/arcadebox.py" --kiosk --no-browser >/dev/null 2>&1 &
  sleep 2
  firefox-esr --kiosk --no-remote --profile "$HOME/.arcadebox-firefox" \
    "http://127.0.0.1:7842/" >/dev/null 2>&1 &
  sleep 8
done

echo "En iyi panX bulduysan: sh kiosk/crt-pan.sh -200 && sudo reboot"
