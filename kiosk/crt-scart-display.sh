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
cat > "$RC" <<'XPROF'
# Arcade Box — VGA → SCART (PAL576i — Xorg modeline, SCART TV)
if command -v xrandr >/dev/null 2>&1; then
  for out in VGA-1 VGA-0 VGA1; do
    if xrandr --query 2>/dev/null | grep -q "^${out} connected"; then
      xrandr --output "$out" --mode PAL576i 2>/dev/null && break
      xrandr --output "$out" --mode 640x480 --rate 60 2>/dev/null && break
      xrandr --output "$out" --auto 2>/dev/null && break
    fi
  done
fi
XPROF
chown "$USER_NAME:$USER_NAME" "$RC" 2>/dev/null || true

# config.json — CRT profili
python3 <<PY
import json
from pathlib import Path
p = Path("$ROOT/config.json")
cfg = json.loads(p.read_text(encoding="utf-8"))
cfg.setdefault("display", {})
cfg["display"].update({
    "width": 720,
    "height": 576,
    "aspect": "4:3",
    "scale": "fill",
    "output": "vga",
    "crt": True,
})
p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("config.json display -> 720x576 PAL576i crt:true")
PY

echo "Yazildi: $RC"
echo "Simdi: export DISPLAY=:0 && sh kiosk/crt-scart-test.sh"
echo "Sonra: sudo reboot"
