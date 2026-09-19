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

# PAL TV / SCART icin once 640x480 ve 720x576 dene (readme: 640x480i ideal)
try_mode "640x480 @60" --mode 640x480 --rate 60 || true
try_mode "720x576 @50 PAL" --mode 720x576 --rate 50 || true
try_mode "800x600 @60" --mode 800x600 --rate 60 || true
try_mode "auto" --auto || true

# Ozel 640x480i modeline (interlaced — bazi SCART TV icin sart)
if ! xrandr --query | grep -q '640x480i'; then
  echo ">>> 640x480i modeline ekleniyor..."
  xrandr --newmode "640x480i" 25.18 640 672 696 832 480 483 486 525 interlace -hsync -vsync 2>/dev/null || true
  xrandr --addmode "$VGA" "640x480i" 2>/dev/null || true
fi
try_mode "640x480i interlaced" --mode 640x480i 2>/dev/null || true

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
echo "6. readme.txt: progressive 640x480 yetmeyebilir — 640x480i veya Soft15khz"
echo
echo "Arcade Box kalici mod: sudo sh kiosk/crt-scart-display.sh"
