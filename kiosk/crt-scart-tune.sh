#!/bin/sh
# SCART TV model taramasi — Arçelik vb. icin PAL modeline dene.
#   export DISPLAY=:0
#   sh kiosk/crt-scart-tune.sh

export DISPLAY="${DISPLAY:-:0}"

VGA=""
for out in VGA-1 VGA-0 VGA1; do
  if xrandr --query 2>/dev/null | grep -q "^${out} connected"; then
    VGA="$out"
    break
  fi
done

if [ -z "$VGA" ]; then
  echo "VGA connected yok"
  exit 1
fi

echo "=== SCART model taramasi ($VGA) ==="
echo "Aktif mod:"
xrandr --query | grep -E '^\s+[0-9]|connected|\*'
echo

add_try() {
  name="$1"
  shift
  echo ">>> $name"
  xrandr --newmode "$name" "$@" 2>/dev/null || true
  xrandr --addmode "$VGA" "$name" 2>/dev/null || true
  if xrandr --output "$VGA" --mode "$name" 2>/dev/null; then
    echo "    AKTIF — CRT'ye bak (8 sn)"
    sleep 8
    return 0
  fi
  echo "    basarisiz"
  return 1
}

# Xorg'dan gelen mod
add_try "PAL576i" 2>/dev/null || xrandr --output "$VGA" --mode PAL576i 2>/dev/null && sleep 8

# Yayin PAL 576i (27 MHz — bir cok Arçelik/Grundig TV)
add_try "PAL576-TV" 27.00 720 732 796 864 576 581 586 625 interlace -hsync -vsync || true
add_try "PAL576-TVp" 27.00 720 732 796 864 576 581 586 625 interlace +hsync +vsync || true

# Alternatif 15 kHz (25 MHz dot clock)
add_try "PAL576-25" 25.20 720 768 848 1611 576 581 586 625 interlace -hsync -vsync || true

xrandr --output "$VGA" --mode 640x480 2>/dev/null && echo ">>> 640x480 (31 kHz — kenar mavi normal)" && sleep 5

echo
echo "Arçelik icin genelde PAL576i. Kalici:"
echo "  sudo sh kiosk/crt-intel-vga.sh PAL576i"
echo "  sudo reboot"
