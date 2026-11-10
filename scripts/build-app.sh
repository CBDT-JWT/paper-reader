#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
CONFIGURATION="${1:-debug}"
python3 scripts/localize.py --check
if [[ -d WebEditor/node_modules ]]; then
  (cd WebEditor && npm run build)
elif [[ ! -f Sources/PaperReader/Resources/Editor/editor.js ]]; then
  (cd WebEditor && npm ci && npm run build)
fi
# Build/sign outside synced Documents folders: File Provider may add FinderInfo to bundles.
BUILD_DIR="${PAPER_READER_BUILD_DIR:-$HOME/Library/Caches/PaperReader/Build}"
swift build --scratch-path "$BUILD_DIR" -c "$CONFIGURATION"
BIN_DIR="$(swift build --scratch-path "$BUILD_DIR" -c "$CONFIGURATION" --show-bin-path)"
STAGING_APP="$BUILD_DIR/Apps/Paper Reader.app"
mkdir -p "$STAGING_APP/Contents/MacOS" "$STAGING_APP/Contents/Resources"
cp "$BIN_DIR/PaperReader" "$STAGING_APP/Contents/MacOS/PaperReader"
for RESOURCE_BUNDLE in "$BIN_DIR"/PaperReader_*.bundle; do
  RESOURCE_NAME="${RESOURCE_BUNDLE:t}"
  rm -rf "$STAGING_APP/Contents/Resources/$RESOURCE_NAME"
  ditto --norsrc --noextattr "$RESOURCE_BUNDLE" "$STAGING_APP/Contents/Resources/$RESOURCE_NAME"
done
CORE_RESOURCES="$BIN_DIR/PaperReader_PaperCore.bundle/Contents/Resources"
if [[ ! -d "$CORE_RESOURCES" ]]; then CORE_RESOURCES="$BIN_DIR/PaperReader_PaperCore.bundle"; fi
for LANGUAGE in en zh-Hans; do
  ditto --norsrc --noextattr "$CORE_RESOURCES/$LANGUAGE.lproj" "$STAGING_APP/Contents/Resources/$LANGUAGE.lproj"
done
cp scripts/Info.plist "$STAGING_APP/Contents/Info.plist"
xattr -cr "$STAGING_APP"
codesign --force --deep --sign - "$STAGING_APP"
mkdir -p build
APP_PATH="$PWD/build/Paper Reader.app"
# A launch shortcut avoids reintroducing sync-provider metadata into the signed bundle.
if [[ -e "$APP_PATH" && ! -L "$APP_PATH" ]]; then rm -rf "$APP_PATH"; fi
ln -sfn "$STAGING_APP" "$APP_PATH"
codesign --verify --deep --strict "$STAGING_APP"
ditto -c -k --keepParent --norsrc --noextattr "$STAGING_APP" "$PWD/build/PaperReader-macOS.zip"
print "Built: $STAGING_APP"
print "Launch shortcut: $APP_PATH"
print "Portable archive: $PWD/build/PaperReader-macOS.zip"
