#!/bin/sh
# Oyunlar 2x hizliysa: TV 120 Hz veya vsync yok.
#   sudo sh kiosk/pi-hiz.sh
#   sudo reboot

set -eu
USER_NAME="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="/home/$USER_NAME"
CFG="$HOME_DIR/.config/retroarch/retroarch.cfg"
mkdir -p "$(dirname "$CFG")"

python3 - "$CFG" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
keys = {
    "video_vsync": "true",
    "video_hard_sync": "true",
    "video_threaded": "false",
    "video_swap_interval": "0",
    "video_refresh_rate": "60",
    "vrr_runloop_enable": "false",
    "run_ahead_enabled": "false",
    "audio_enable": "true",
    "audio_sync": "true",
    "audio_rate_control": "true",
    "audio_driver": "sdl2",
    "fastforward_ratio": "1.0",
    "input_toggle_fast_forward": "nul",
    "input_hold_fast_forward": "nul",
}
text = path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
lines = text.splitlines()
seen = set()
out = []
for line in lines:
    stripped = line.strip()
    key = stripped.split("=")[0].strip() if "=" in stripped else ""
    if key in keys:
        out.append(f'{key} = "{keys[key]}"')
        seen.add(key)
    else:
        out.append(line)
for key, value in keys.items():
    if key not in seen:
        out.append(f'{key} = "{value}"')
path.write_text("\n".join(out) + "\n", encoding="utf-8")
print("retroarch.cfg ok:", path)
PY

if [ "$(id -u)" -eq 0 ]; then
  chown "$USER_NAME:" "$CFG" 2>/dev/null || true
  CONFIG=/boot/firmware/config.txt
  [ -f "$CONFIG" ] || CONFIG=/boot/config.txt
  if [ -f "$CONFIG" ] && ! grep -q "hdmi_mode=16" "$CONFIG"; then
    printf '\n# Arcade Box 60Hz\nhdmi_group=1\nhdmi_mode=16\nhdmi_group:1=1\nhdmi_mode:1=16\n' >> "$CONFIG"
    echo "config.txt 60 Hz yazildi"
  fi
fi

echo "reboot et, sonra bir oyun ac."
