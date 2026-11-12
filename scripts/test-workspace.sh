#!/bin/zsh
# Real native/WebKit workspace switching, isolated from the user's library and preferences.
set -euo pipefail
cd "${0:A:h}/.."
BUILD_DIR="${PAPER_READER_BUILD_DIR:-$HOME/Library/Caches/PaperReader/Build}"
REPORT_DIR="${PAPER_READER_TEST_REPORT_DIR:-$BUILD_DIR/Reports}"
TEST_ROOT="$(mktemp -d /tmp/PaperReader-Workspace.XXXXXX)"
mkdir -p "$REPORT_DIR"
for LANGUAGE in en zh-Hans; do
  EXTRA=()
  if [[ -n "${PAPER_READER_TEST_CLOUD_ROOT:-}" ]]; then
    EXTRA+=(--env "PAPER_READER_TEST_CLOUD_ROOT=$PAPER_READER_TEST_CLOUD_ROOT/Validation-${TEST_ROOT:t}-$LANGUAGE")
  fi
  open -n -W "$BUILD_DIR/Apps/Paper Reader.app" \
    --env "PAPER_READER_TEST_APPEARANCE=${PAPER_READER_TEST_APPEARANCE:-}" \
    --env "PAPER_READER_LIBRARY=$TEST_ROOT/$LANGUAGE/OriginalLibrary" \
    --env "PAPER_READER_TEST_OUTPUT=$REPORT_DIR/workspace-$LANGUAGE.json" \
    "${EXTRA[@]}" --args --self-test --workspace-self-test -AppleLanguages "($LANGUAGE)"
  python3 - "$REPORT_DIR/workspace-$LANGUAGE.json" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]))
assert report['success'],report.get('error','Workspace validation failed')
print('Native workspace:',len(report['checks']),'checks passed; real iCloud:',report['realICloudFolderUsed'])
PY
done
print "Workspace reports: $REPORT_DIR/workspace-en.json, $REPORT_DIR/workspace-zh-Hans.json"
