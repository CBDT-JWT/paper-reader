#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
BUILD_DIR="${PAPER_READER_BUILD_DIR:-$HOME/Library/Caches/PaperReader/Build}"
mkdir -p build
if [[ ! -d WebEditor/node_modules ]]; then (cd WebEditor && npm ci); fi
(cd WebEditor && npm test && npm audit --omit=dev)
swift test --scratch-path "$BUILD_DIR"
scripts/build-app.sh
TEST_ROOT="$(mktemp -d /tmp/PaperReader-Integration.XXXXXX)"
print "Isolated integration library: $TEST_ROOT/Library"
PAPER_READER_LIBRARY="$TEST_ROOT/Library" \
PAPER_READER_TEST_OUTPUT="$PWD/build/integration-results.json" \
"$BUILD_DIR/Apps/Paper Reader.app/Contents/MacOS/PaperReader" --self-test
print "Integration report: $PWD/build/integration-results.json"
print "Rendered export pages: $TEST_ROOT/Export"
