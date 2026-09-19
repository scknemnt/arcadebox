#!/bin/sh
# Kabin: yerel kiosk degisikliklerini at, uzak repoyu cek.
#   sh kiosk/git-pull.sh

set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "=== Arcade Box git pull ==="
git status -sb

# Sadece takip edilen dosyalardaki yerel diffleri geri al (kiosk scriptleri vb.)
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Yerel degisiklikler geri aliniyor..."
  git checkout -- .
fi

git pull origin main

echo
echo "Guncel commit:"
git log -1 --oneline
echo
echo "Sonra: sudo sh kiosk/crt-arcelik.sh && sudo reboot"
