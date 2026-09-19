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
echo "PAL576i saga kayma: sh kiosk/crt-pal576i-hpos.sh"
