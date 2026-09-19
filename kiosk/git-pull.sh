#!/bin/sh
# Kabin: uzak repoyla birebir esitle (yerel diff silinir).
#   sh kiosk/git-pull.sh

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== Arcade Box — tam senkron ==="
git fetch origin main
git reset --hard origin/main
git clean -fd -e roms -e bios -e music -e emulators

echo
echo "Guncel:"
git log -1 --oneline
echo
echo "CRT kurulum: sudo sh kiosk/crt-arcelik.sh && sudo reboot"
echo "Ekran gelmiyorsa: sudo sh kiosk/crt-recover.sh && sudo reboot"
echo "X yok: sh kiosk/crt-fix-boot.sh && sh kiosk/crt-start-x.sh"
echo "       veya sudo reboot"
echo "TAM SİYAH: sh kiosk/crt-emergency.sh && sudo reboot"
echo "Goruntu bozuksa: sh kiosk/crt-display-reset.sh && sudo reboot"
echo "Saga kayma: sh kiosk/crt-pan-scan.sh"
echo "SCART kart HW: cat kiosk/CRT-SCART-HW.txt"
