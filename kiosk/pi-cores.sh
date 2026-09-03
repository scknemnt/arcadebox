#!/bin/sh
# Pi 4 64-bit: libretro core (.so) indir. Windows .dll burada calismaz.
#   sh kiosk/pi-cores.sh

set -eu
USER_NAME="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="${HOME:-/home/$USER_NAME}"
DEST="$HOME_DIR/.config/retroarch/cores"
BASE="https://buildbot.libretro.com/nightly/linux/aarch64/latest"
mkdir -p "$DEST"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

if ! command -v unzip >/dev/null 2>&1 || ! command -v wget >/dev/null 2>&1; then
  if [ "$(id -u)" -eq 0 ]; then
    apt-get install -y unzip wget ca-certificates
  else
    echo "sudo apt-get install -y unzip wget  sonra tekrar dene."
    exit 1
  fi
fi

# Stella, Nestopia, FCEUmm, Snes9x, Genesis Plus GX, FBNeo, PCSX ReARMed
for c in \
  stella_libretro \
  stella2014_libretro \
  nestopia_libretro \
  fceumm_libretro \
  snes9x_libretro \
  genesis_plus_gx_libretro \
  fbneo_libretro \
  pcsx_rearmed_libretro
do
  echo "Indiriliyor: $c"
  if wget -q --show-progress -O "$WORKDIR/$c.so.zip" "$BASE/${c}.so.zip"; then
    unzip -o -q "$WORKDIR/$c.so.zip" -d "$DEST"
  else
    echo "ATLANDI: $c (indirilemedi)"
  fi
done

if [ "$(id -u)" -eq 0 ]; then
  chown -R "$USER_NAME:" "$HOME_DIR/.config/retroarch" || true
fi

echo
echo "Core klasoru: $DEST"
ls -lh "$DEST"/*.so 2>/dev/null || echo "Hic .so yok — internet / buildbot kontrol et."
