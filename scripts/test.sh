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
REPORT_DIR="${PAPER_READER_TEST_REPORT_DIR:-$BUILD_DIR/Reports}"
mkdir -p "$REPORT_DIR"
TEST_ROOT="$(mktemp -d /tmp/PaperReader-Integration.XXXXXX)"
python3 scripts/mock-ai-server.py "$TEST_ROOT/port" &
MOCK_PID=$!
trap 'kill "$MOCK_PID" 2>/dev/null || true' EXIT
for attempt in {1..30}; do if [[ -f "$TEST_ROOT/port" ]]; then break; fi; sleep 0.1; done
MOCK_PORT="$(cat "$TEST_ROOT/port")"
for LANGUAGE in en zh-Hans; do
  # Launch Services establishes the normal foreground activation contract on recent macOS.
  open -n -W "$BUILD_DIR/Apps/Paper Reader.app" \
    --env "PAPER_READER_LIBRARY=$TEST_ROOT/$LANGUAGE/Library" \
    --env "PAPER_READER_MOCK_API=http://127.0.0.1:$MOCK_PORT/v1" \
    --env "PAPER_READER_SKIP_INTERACTIVE_FOCUS=${PAPER_READER_SKIP_INTERACTIVE_FOCUS:-0}" \
    --env "PAPER_READER_TEST_OUTPUT=$REPORT_DIR/integration-$LANGUAGE.json" \
    --args --self-test -AppleLanguages "($LANGUAGE)"
  python3 - "$REPORT_DIR/integration-$LANGUAGE.json" <<'PYRESULT'
import json,sys
report=json.load(open(sys.argv[1]))
assert report['success'],report.get('error','Native validation failed')
print('Native integration:',len(report['checks']),'checks passed')
PYRESULT
done
print "Reports: $REPORT_DIR/integration-en.json, $REPORT_DIR/integration-zh-Hans.json"
print "Rendered exports and isolated libraries: $TEST_ROOT"
scripts/test-workspace.sh
