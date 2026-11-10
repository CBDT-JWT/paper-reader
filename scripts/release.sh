#!/bin/zsh
# Publish from a clean, tested source commit. Stable publication fails closed without Developer ID/notarization.
set -euo pipefail
cd "${0:A:h}/.."
MODE="${1:-stable}"
NOTES="${2:-docs/releases/0.3.0.md}"
[[ "$(uname -m)" == arm64 ]] || { print "This release pipeline currently publishes Apple Silicon builds only." >&2; exit 1; }
[[ "$MODE" == stable || "$MODE" == preview ]] || { print 'Usage: scripts/release.sh stable|preview notes.md'; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { print 'Commit the release source before publishing.' >&2; exit 1; }
if [[ "$MODE" == stable ]]; then python3 scripts/release/preflight.py; fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' scripts/Info.plist)"
TAG="v$VERSION"
[[ "$MODE" == preview ]] && TAG="$TAG-preview.1"
EXISTING_DRAFT=false
if EXISTING_DRAFT="$(gh release view "$TAG" --repo CBDT-JWT/paper-reader --json isDraft --jq .isDraft 2>/dev/null)"; then
  [[ "$EXISTING_DRAFT" == true ]] || { print "Release $TAG is published. Do not overwrite published binaries." >&2; exit 1; }
else
  EXISTING_DRAFT=false
fi
scripts/build-app.sh release
APP="${PAPER_READER_BUILD_DIR:-$HOME/Library/Caches/PaperReader/Build}/Apps/Paper Reader.app"
PROFILE="${PAPER_READER_NOTARY_PROFILE:-PaperReader}"
if [[ "$MODE" == stable ]]; then
  xcrun notarytool submit build/PaperReader-macOS.zip --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose "$APP"
fi
scripts/build-dmg.sh "$APP"
DMG="build/release/PaperReader-$VERSION-arm64.dmg"
if [[ "$MODE" == stable ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi
(cd build/release && shasum -a 256 "${DMG:t}" > SHA256SUMS.txt)
PUBLISH_NOTES="$PWD/build/release/release-notes.md"
cp "$NOTES" "$PUBLISH_NOTES"
if [[ "$MODE" == stable ]]; then
  print '\nDistribution: Developer ID signed, Apple notarized, and Gatekeeper assessed. Updates and their feed are signed with the Paper Reader Ed25519 key.' >> "$PUBLISH_NOTES"
else
  print '\nDistribution: development preview with an ad-hoc signature. This build is not Developer ID signed or Apple notarized; macOS may block opening it. It is excluded from the stable update feed.' >> "$PUBLISH_NOTES"
fi
ARGS=(--repo CBDT-JWT/paper-reader --target "$(git rev-parse HEAD)" --title "Paper Reader $VERSION" --notes-file "$PUBLISH_NOTES" --draft)
[[ "$MODE" == preview ]] && ARGS+=(--prerelease)
if [[ "$EXISTING_DRAFT" == true ]]; then
  gh release edit "$TAG" --repo CBDT-JWT/paper-reader --target "$(git rev-parse HEAD)" --title "Paper Reader $VERSION" --notes-file "$PUBLISH_NOTES"
  gh release upload "$TAG" --repo CBDT-JWT/paper-reader --clobber "$DMG" build/release/SHA256SUMS.txt
else
  gh release create "$TAG" "$DMG" build/release/SHA256SUMS.txt "${ARGS[@]}"
fi
if [[ "$MODE" == stable ]]; then
  TOOLS="${PAPER_READER_BUILD_DIR:-$HOME/Library/Caches/PaperReader/Build}/artifacts/sparkle/Sparkle/bin"
  FEED_DIR="$(mktemp -d /tmp/PaperReader-Appcast.XXXXXX)"
  cp "$DMG" "$FEED_DIR/"
  "$TOOLS/generate_appcast" --account dev.paperreader.mac --maximum-deltas 0 \
    --download-url-prefix "https://github.com/CBDT-JWT/paper-reader/releases/download/$TAG/" \
    --link https://www.weitao-jiang.cn/paper-reader/ "$FEED_DIR"
  "$TOOLS/sign_update" --account dev.paperreader.mac "$FEED_DIR/appcast.xml"
  "$TOOLS/sign_update" --account dev.paperreader.mac --verify "$FEED_DIR/appcast.xml"
  cp "$FEED_DIR/appcast.xml" website/appcast.xml
fi
python3 - "$MODE" "$VERSION" "$TAG" "$DMG" <<'PY'
import hashlib,json,sys
from pathlib import Path
mode,version,tag,dmg=sys.argv[1:]
info={'version':version,'status':mode,'architecture':'arm64','minimumSystemVersion':'14.0',
 'url':f'https://github.com/CBDT-JWT/paper-reader/releases/download/{tag}/{Path(dmg).name}',
 'sha256':hashlib.sha256(Path(dmg).read_bytes()).hexdigest(),'notarized':mode=='stable'}
Path('website/release.json').write_text(json.dumps(info,indent=2)+'\n')
PY
gh release edit "$TAG" --repo CBDT-JWT/paper-reader --draft=false
# Update the public website/feed only after its immutable archive is available.
git add website/release.json website/appcast.xml
git commit -m "Publish $TAG download metadata and verified update feed"
git push origin HEAD
scripts/deploy-website.sh
