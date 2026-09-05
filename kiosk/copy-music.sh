#!/bin/sh
# USB veya Windows'tan kopyalanan MP3'leri music/ klasorune tasi.
# Ornek: sudo sh kiosk/copy-music.sh /media/arcadebox/USB/music

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/music"
mkdir -p "$DEST"
SRC="${1:-.}"

count=0
for f in "$SRC"/*.mp3 "$SRC"/*.MP3 "$SRC"/*.ogg "$SRC"/*.OGG; do
  [ -f "$f" ] || continue
  cp -n "$f" "$DEST/" 2>/dev/null || cp "$f" "$DEST/"
  count=$((count + 1))
done

echo "$count parca -> $DEST"
ls -la "$DEST"/*.mp3 "$DEST"/*.ogg 2>/dev/null || ls -la "$DEST"
