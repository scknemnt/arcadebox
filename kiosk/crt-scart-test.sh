#!/bin/sh
# VGA → SCART test (Debian kabin). Kablo takili, CRT acik:
#   export DISPLAY=:0
#   sh kiosk/crt-scart-test.sh
#
# veya SSH ile:
#   ssh arcade@IP "export DISPLAY=:0; sh ~/ArcadeBox/kiosk/crt-scart-test.sh"

set -eu

export DISPLAY="${DISPLAY:-:0}"

echo "=== Arcade Box CRT/SCART test ==="
date
echo "DISPLAY=$DISPLAY"
echo

echo "--- lspci VGA ---"
lspci -nn 2>/dev/null | grep -iE 'vga|display|3d' || echo "(lspci yok)"
echo

echo "--- X provider (hangi GPU aktif?) ---"
xrandr --listproviders 2>/dev/null || true
echo

if ! command -v xrandr >/dev/null 2>&1; then
  echo "xrandr yok. Kur: sudo apt-get install -y x11-xserver-utils"
  exit 1
fi

if ! xrandr --query >/dev/null 2>&1; then
  echo "X calismiyor veya DISPLAY yanlis."
  echo "  startx veya kiosk servisi acik mi?"
  echo "  root ise: su - arcade -c 'export DISPLAY=:0; sh kiosk/crt-scart-test.sh'"
  exit 1
fi

echo "--- xrandr (bagli cikis) ---"
xrandr --query | grep -E ' connected|^Screen'
echo

VGA=""
for out in VGA-1 VGA-0 VGA1 VGA-2; do
  if xrandr --query | grep -q "^${out} connected"; then
    VGA="$out"
    break
  fi
done

if [ -z "$VGA" ]; then
  echo "VGA connected gorunmuyor. HDMI'ye mi bagli?"
  xrandr --query | grep connected
  echo
  echo "Kablo mavi VGA sokette mi? BIOS Internal Graphics / ekran karti dogru mu?"
  exit 1
fi

echo "VGA cikis: $VGA"
echo

try_mode() {
  name="$1"
  shift
  echo ">>> Deneme: $name"
  if xrandr --output "$VGA" --auto "$@" 2>&1; then
    echo "    OK — CRT'de goruntu var mi?"
    sleep 2
    return 0
  fi
  echo "    basarisiz"
  return 1
}

add_mode() {
  name="$1"
  shift
  echo ">>> Modeline: $name"
  xrandr --newmode "$name" "$@" 2>&1 || true
  xrandr --addmode "$VGA" "$name" 2>&1 || true
}

# SCART TV cogu 15.625 kHz PAL bekler; 640x480@60 VGA ~31 kHz'tir (TV siyah kalabilir)
add_mode "576i-pal" 13.50 720 738 846 978 576 582 587 625 interlace -hsync -vsync
add_mode "640x480-15k" 15.750 640 664 736 840 480 491 501 525 -hsync -vsync
add_mode "640x512i-pal" 13.50 640 664 760 840 512 517 523 561 interlace -hsync -vsync

try_mode "576i-pal (15.6 kHz — SCART TV icin oncelik)" --mode 576i-pal || true
try_mode "640x480-15k (arcade/15kHz)" --mode 640x480-15k || true
try_mode "640x512i-pal" --mode 640x512i-pal || true
try_mode "640x480 @60 (~31 kHz VGA)" --mode 640x480 --rate 60 || true
try_mode "800x600 @60" --mode 800x600 --rate 60 || true
try_mode "auto" --auto || true

echo
echo "--- Mevcut mod ---"
xrandr --query | grep -A1 "^${VGA} "
echo
echo "=== Donanim kontrol (goruntu hala yoksa) ==="
echo "1. SCART pin 8 (switch) ~9-12V — RGB modu icin (bazi TV'ler composite'a duser)"
echo "2. SCART pin 16 ~1-3V — blanking (RGB acik)"
echo "3. Sync: pin 20 composite sync — 74HC86 cikisi"
echo "4. Kablo VGA'dan mi gidiyor? (HDMI degil)"
echo "5. POST/BIOS ekranda hic gorunuyor mu? Hayir = kablo/sync donanim"
echo "6. SCART TV genelde 15 kHz PAL ister; 640x480@60 = 31 kHz (siyah ekran normal olabilir)"
echo "7. VGA monitor tak — PC cikisi var mi? (varsa sorun TV tarama / SCART donanim)"
echo "8. Baska cihazdan SCART (DVD/konsol) — TV calisiyor mu?"
echo "9. Multimetre: SCART pin 8 ~9-12V (LM2577), pin 16 ~1-3V (RGB blanking)"
echo
echo "Arcade Box kalici mod: sudo sh kiosk/crt-scart-display.sh"
echo "15 kHz xrandr reddediyorsa: sudo sh kiosk/crt-scart-xorg.sh auto && sudo reboot"
