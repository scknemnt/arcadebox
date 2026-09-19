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
echo "Yatay cizgi / goruntu yok:"
echo "  sudo sh kiosk/crt-stock.sh && sudo reboot"
