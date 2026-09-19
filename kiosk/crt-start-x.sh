#!/bin/sh
# SSH'den vt1 acma CALISMAZ. Reboot sonrasi otomatik acilir.
# Acil: sudo sh kiosk/crt-fix-boot.sh && sudo reboot

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

echo "=== CRT X ==="
echo "SSH'den X baslatilamaz (vt1 izni yok)."
echo "Calistir: sudo sh kiosk/crt-fix-boot.sh && sudo reboot"
echo

if pgrep -x Xorg >/dev/null 2>&1; then
  echo "Xorg zaten calisiyor."
  export DISPLAY=:0
  [ -f "$ROOT/kiosk/crt-xrandr-pal.sh" ] && sh "$ROOT/kiosk/crt-xrandr-pal.sh" || true
  xrandr --query 2>/dev/null | grep -E 'connected|\*' || true
else
  echo "Xorg yok — reboot gerekli."
  tail -15 "$HOME/.local/share/xorg/Xorg.0.log" 2>/dev/null || true
fi
