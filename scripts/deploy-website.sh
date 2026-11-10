#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
DEST="${PAPER_READER_WEBSITE_REPO:-$HOME/Library/Caches/PaperReader/Home-web}"
[[ -d "$DEST/.git" ]] || { print 'Clone CBDT-JWT/Home to PAPER_READER_WEBSITE_REPO first.' >&2; exit 1; }
[[ -z "$(git -C "$DEST" status --porcelain)" ]] || { print 'Website checkout has uncommitted changes.' >&2; exit 1; }
git -C "$DEST" pull --ff-only
python3 scripts/release/install-website.py "$DEST"
python3 -m py_compile "$DEST/app.py"
git -C "$DEST" add --sparse app.py static/paper-reader
if ! git -C "$DEST" diff --cached --quiet; then
  git -C "$DEST" commit -m 'Publish Paper Reader product site and update feed'
  git -C "$DEST" push origin master
fi
print 'Website source pushed; monitor: gh run list --repo CBDT-JWT/Home'
