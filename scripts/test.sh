#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
BUILD_DIR="${PAPER_READER_BUILD_DIR:-$HOME/Library/Caches/PaperReader/Build}"
mkdir -p build
python3 scripts/localize.py --check
if [[ ! -d WebEditor/node_modules ]]; then (cd WebEditor && npm ci); fi
(cd WebEditor && npm test && npm audit --omit=dev)
swift test --scratch-path "$BUILD_DIR"
scripts/build-app.sh
TEST_ROOT="$(mktemp -d /tmp/PaperReader-Integration.XXXXXX)"
python3 scripts/mock-ai-server.py "$TEST_ROOT/port" &
MOCK_PID=$!
trap 'kill "$MOCK_PID" 2>/dev/null || true' EXIT
for attempt in {1..30}; do if [[ -f "$TEST_ROOT/port" ]]; then break; fi; sleep 0.1; done
MOCK_PORT="$(cat "$TEST_ROOT/port")"
for LANGUAGE in en zh-Hans; do
  PAPER_READER_LIBRARY="$TEST_ROOT/$LANGUAGE/Library" \
  PAPER_READER_MOCK_API="http://127.0.0.1:$MOCK_PORT/v1" \
  PAPER_READER_TEST_OUTPUT="$PWD/build/integration-$LANGUAGE.json" \
  "$BUILD_DIR/Apps/Paper Reader.app/Contents/MacOS/PaperReader" --self-test -AppleLanguages "($LANGUAGE)"
done
print "Reports: build/integration-en.json, build/integration-zh-Hans.json"
print "Rendered exports and isolated libraries: $TEST_ROOT"
