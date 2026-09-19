#!/bin/sh
# Kabin: uzak repoyla birebir esitle.
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
echo "LCD OK, TV senkron degil: sh kiosk/crt-tv.sh"
echo "X/menu yok: cd /mnt/games/ArcadeBox && sudo sh kiosk/crt-stock.sh && sudo reboot"
