#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
ICON_DIR="${PAPER_READER_BUILD_DIR:-$HOME/Library/Caches/PaperReader/Build}/Icons/AppIcon.iconset"
mkdir -p "$ICON_DIR"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" assets/AppIcon.png --out "$ICON_DIR/icon_${SIZE}x${SIZE}.png" >/dev/null
  RETINA_SIZE=$((SIZE * 2))
  sips -z "$RETINA_SIZE" "$RETINA_SIZE" assets/AppIcon.png --out "$ICON_DIR/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICON_DIR" -o assets/AppIcon.icns
