#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
APP="${1:-$HOME/Library/Caches/PaperReader/Build/Apps/Paper Reader.app}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
VENV="$HOME/Library/Caches/PaperReader/Packaging/venv"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install 'dmgbuild==1.6.7'
fi
mkdir -p build/release
OUTPUT="$PWD/build/release/PaperReader-$VERSION-arm64.dmg"
"$VENV/bin/dmgbuild" -s scripts/release/dmg-settings.py -D app="$APP" "Paper Reader" "$OUTPUT"
if [[ -n "${PAPER_READER_SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$PAPER_READER_SIGN_IDENTITY" "$OUTPUT"
fi
hdiutil verify "$OUTPUT"
print "DMG: $OUTPUT"
