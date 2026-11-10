#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/../.."
BUILD_DIR="${PAPER_READER_BUILD_DIR:-$HOME/Library/Caches/PaperReader/Build}"
TOOL="$BUILD_DIR/artifacts/sparkle/Sparkle/bin/generate_keys"
[[ -x "$TOOL" ]] || { print 'Run swift package resolve first.' >&2; exit 1; }
# Private Ed25519 key stays in login Keychain. Only the public key is printed.
"$TOOL" --account dev.paperreader.mac
