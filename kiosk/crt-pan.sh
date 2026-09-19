#!/bin/sh
# config.json panX/panY ince ayar (Firefox UI kaymasi icin).
#   sh kiosk/crt-pan.sh -40
#   sh kiosk/crt-pan.sh -40 0
# Kabin: git pull + Firefox yeniden baslat (reboot veya linux-start)

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/config.json"
PANX="${1:-0}"
PANY="${2:-0}"

python3 - "$CFG" "$PANX" "$PANY" <<'PY'
import json, sys
path, panx, pany = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
with open(path, encoding="utf-8") as f:
    cfg = json.load(f)
cfg.setdefault("display", {})
cfg["display"]["panX"] = panx
cfg["display"]["panY"] = pany
cfg["display"]["crt"] = True
cfg["display"]["width"] = 720
cfg["display"]["height"] = 576
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, indent=2, ensure_ascii=False)
    f.write("\n")
print(f"panX={panx} panY={pany} -> {path}")
PY

echo "Firefox yeniden baslat: sudo reboot  veya  pkill firefox-esr && sh kiosk/linux-start.sh"
