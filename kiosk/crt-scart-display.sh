#!/bin/sh
# Kalici CRT/SCART VGA modu — xrandr + Arcade Box config
#   sudo sh kiosk/crt-scart-display.sh
#
# 800x600 yerine once 640x480 / 720x576 dener (VGA-SCART readme).

set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "sudo sh kiosk/crt-scart-display.sh"
  exit 1
fi

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
USER_NAME="${SUDO_USER:-arcade}"
HOME_DIR="$(getent passwd "$USER_NAME" 2>/dev/null | cut -d: -f6)"
RC="${HOME_DIR}/.xprofile"

mkdir -p "$(dirname "$RC")"
cat > "$RC" <<XPROF
# Arcade Box — VGA → SCART (xrandr PAL modlari)
for d in "$ROOT" /mnt/games/ArcadeBox "\$HOME/ArcadeBox"; do
  if [ -f "\$d/kiosk/crt-xrandr-pal.sh" ]; then
    sh "\$d/kiosk/crt-xrandr-pal.sh" && break
  fi
done
XPROF
chown "$USER_NAME:$USER_NAME" "$RC" 2>/dev/null || true

# config.json — CRT profili
python3 <<PY
import json
from pathlib import Path
p = Path("$ROOT/config.json")
cfg = json.loads(p.read_text(encoding="utf-8"))
cfg["theme"] = "amiga-crt"
cfg.setdefault("display", {})
cfg["display"].update({
    "width": 720,
    "height": 576,
    "aspect": "4:3",
    "scale": "fill",
    "output": "vga",
    "crt": True,
    "panX": cfg.get("display", {}).get("panX", 0),
    "panY": cfg.get("display", {}).get("panY", 0),
    "hpos": cfg.get("display", {}).get("hpos", 0),
})
p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("config.json theme=amiga-crt display=720x576 crt:true")
PY

echo "Yazildi: $RC"
echo "Simdi: export DISPLAY=:0 && sh kiosk/crt-scart-test.sh"
echo "Sonra: sudo reboot"
