#!/bin/sh
# TAM SİYAH EKRAN — once crt-rollback dene:
#   sudo sh kiosk/crt-rollback.sh && sudo reboot
#
# Sadece config/xprofile:
#   sh kiosk/crt-emergency.sh && sudo reboot
#
# sudo OLMADAN calistir (arcadebox kullanicisi). Root gerekirse script sorar.

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
CFG="$ROOT/config.json"
USER_NAME="${USER:-arcadebox}"
HOME_DIR="${HOME:-/home/arcadebox}"

export DISPLAY="${DISPLAY:-:0}"
if [ -z "${XAUTHORITY:-}" ]; then
  if [ -f "$HOME_DIR/.Xauthority" ]; then
    export XAUTHORITY="$HOME_DIR/.Xauthority"
  else
    _auth="$(ps aux 2>/dev/null | awk '/Xorg.*:0/{for(i=1;i<=NF;i++) if($i ~ /^-auth$/){print $(i+1); exit}}')"
    [ -n "$_auth" ] && [ -f "$_auth" ] && export XAUTHORITY="$_auth"
  fi
fi

echo "=== CRT ACIL KURTARMA ==="
echo "DISPLAY=$DISPLAY XAUTHORITY=${XAUTHORITY:-yok}"

python3 - "$CFG" <<'PY'
import json, sys
p = sys.argv[1]
try:
    cfg = json.load(open(p, encoding="utf-8"))
except Exception:
    cfg = {}
d = cfg.setdefault("display", {})
d.update({
    "fbPanX": 0, "hpos": 0, "panX": 0,
    "crt": True, "width": 720, "height": 576,
    "preferredMode": "PAL576i", "output": "vga",
})
json.dump(cfg, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open(p, "a").write("\n")
print("config.json sifirlandi")
PY

# .xprofile — sadece PAL576i, fb/transform YOK
cat > "$HOME_DIR/.xprofile" <<'XPROF'
export DISPLAY="${DISPLAY:-:0}"
sleep 2
for d in /mnt/games/ArcadeBox "$HOME/ArcadeBox"; do
  if [ -f "$d/kiosk/crt-xrandr-pal.sh" ]; then
    sh "$d/kiosk/crt-xrandr-pal.sh" && break
  fi
done
XPROF

echo ".xprofile yazildi: $HOME_DIR/.xprofile"

# Canli X dene
if command -v xrandr >/dev/null 2>&1 && xrandr --query >/dev/null 2>&1; then
  echo "X calisiyor — PAL576i zorlaniyor..."
  sh "$ROOT/kiosk/crt-display-reset.sh" || true
else
  echo "X yanit vermiyor (normal — reboot sonrasi duzelir)"
fi

# Xorg — minimal Intel (boot'ta PAL zorlamadan)
if [ "$(id -u)" -eq 0 ]; then
  _do_xorg=1
else
  echo
  echo "Xorg sadelestirmek icin sudo sifresi:"
  sudo -v && _do_xorg=1 || _do_xorg=0
fi

if [ "${_do_xorg:-0}" = "1" ]; then
  mkdir -p /etc/X11/xorg.conf.d
  cat > /etc/X11/xorg.conf.d/10-arcadebox.conf <<'EOF'
# Arcade Box acil — Intel VGA, PAL xrandr ile (.xprofile)
Section "Device"
    Identifier "IntelGPU"
    Driver "modesetting"
    Option "UseEDID" "false"
EndSection
Section "Screen"
    Identifier "Screen0"
    Device "IntelGPU"
    DefaultDepth 24
EndSection
Section "ServerLayout"
    Identifier "Layout0"
    Screen 0 "Screen0"
EndSection
EOF
  echo "Xorg sadelestirildi: /etc/X11/xorg.conf.d/10-arcadebox.conf"
fi

pkill firefox-esr 2>/dev/null || true
echo
echo ">>> sudo reboot <<<"
echo "Reboot sonrasi SSH:"
echo "  export DISPLAY=:0 && xrandr --query | grep '\\*'"
