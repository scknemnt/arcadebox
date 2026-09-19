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
echo "GORUNTU GITTİ / renk test sonrasi:"
echo "  sudo sh kiosk/crt-rollback.sh && sudo reboot"
echo
echo "CRT ilk kurulum: sudo sh kiosk/crt-arcelik.sh && sudo reboot"
echo "Kayma ince ayar: sh kiosk/crt-pan.sh -120"
echo "SCART kart HW: cat kiosk/CRT-SCART-HW.txt"
