#!/bin/sh
# CRT yatay cizgiler / resim yok — sadece PAL576i zorla.
#   cd /mnt/games/ArcadeBox
#   export DISPLAY=:0
#   sh kiosk/crt-lines-fix.sh
#
# X erisilemiyorsa once:
#   sudo sh kiosk/crt-recover.sh && sudo reboot

export DISPLAY="${DISPLAY:-:0}"
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
HOME_DIR="${HOME:-/home/arcadebox}"

if [ -z "${XAUTHORITY:-}" ]; then
  [ -f "$HOME_DIR/.Xauthority" ] && export XAUTHORITY="$HOME_DIR/.Xauthority"
  _auth="$(ps aux 2>/dev/null | awk '/Xorg.*:0/{for(i=1;i<=NF;i++) if($i ~ /^-auth$/){print $(i+1); exit}}')"
  [ -n "$_auth" ] && [ -f "$_auth" ] && export XAUTHORITY="$_auth"
fi

if ! xrandr --query >/dev/null 2>&1; then
  echo "X yok. Calistir: sudo sh kiosk/crt-recover.sh && sudo reboot"
  exit 1
fi

OUT=""
for o in VGA-1 VGA-0 VGA1; do
  xrandr --query 2>/dev/null | grep -q "^${o} connected" && OUT="$o" && break
done
[ -n "$OUT" ] || { echo "VGA yok"; xrandr --query; exit 1; }

echo "=== CRT yatay cizgi duzeltme ($OUT) ==="
echo "Onceki mod:"
xrandr --query 2>/dev/null | grep -E "connected|\*" || true

pkill firefox-esr 2>/dev/null || true

# Sadece PAL576i — SCART/864 modlari Arçelik'te cizgi/siyah yapar
xrandr --output "$OUT" --transform 1,0,0,0,1,0,0,0,1 2>/dev/null || true
xrandr --output "$OUT" --reflect normal 2>/dev/null || true
xrandr --fb 720x576 2>/dev/null || true
xrandr --output "$OUT" --pos 0x0 2>/dev/null || true

xrandr --newmode "PAL576i" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync 2>/dev/null || true
xrandr --addmode "$OUT" PAL576i 2>/dev/null || true

if xrandr --output "$OUT" --mode PAL576i 2>/dev/null; then
  echo "OK: PAL576i"
else
  echo "PAL576i olmadi — 640x480 deneniyor..."
  xrandr --output "$OUT" --mode 640x480 2>/dev/null || \
  xrandr --output "$OUT" --auto 2>/dev/null || true
fi

xsetroot -solid "#cc0000" 2>/dev/null || true
echo "TV'de KIRMIZI tam ekran goruyor musun? (8 sn)"
sleep 8
xsetroot -solid "#120404" 2>/dev/null || true

echo
xrandr --query 2>/dev/null | grep -E "connected|\*" || true
echo
echo "Kirmizi geldi -> sh kiosk/linux-start.sh"
echo "Hala cizgi -> sudo sh kiosk/crt-recover.sh && sudo reboot"
