#!/bin/sh
# SSH'den vt1 acma CALISMAZ (Permission denied normal).
# Bunun yerine systemd kiosk servisi:

export DISPLAY="${DISPLAY:-:0}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

echo "=== CRT X baslat (systemd) ==="
echo "Once: sudo sh kiosk/crt-fix-boot.sh"
echo

if [ "$(id -u)" -ne 0 ]; then
  echo "Calistir: sudo systemctl start arcadebox-kiosk.service"
  echo "Log:      journalctl -u arcadebox-kiosk.service -n 40 --no-pager"
  sudo systemctl start arcadebox-kiosk.service 2>/dev/null || true
else
  systemctl start arcadebox-kiosk.service
fi

sleep 5
if pgrep -x Xorg >/dev/null 2>&1; then
  echo "Xorg OK"
  export DISPLAY=:0
  [ -f "$ROOT/kiosk/crt-xrandr-pal.sh" ] && sh "$ROOT/kiosk/crt-xrandr-pal.sh" || true
  xrandr --query 2>/dev/null | grep -E 'connected|\*' || true
else
  echo "Xorg yok. Log:"
  journalctl -u arcadebox-kiosk.service -n 25 --no-pager 2>/dev/null || true
  tail -15 "$HOME/.local/share/xorg/Xorg.0.log" 2>/dev/null || true
  echo
  echo ">>> sudo reboot <<<"
fi
