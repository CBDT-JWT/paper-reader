# 0.4.1 folder workspace / iCloud validation — 2026-11-10

## Implemented and exercised

- 29 Swift tests pass, including nine workspace tests and an independent draft-journal test. Coverage includes in-place discovery, hierarchy, UUID association across independent local indexes, private reading state, physical moves/renames, Finder rename identity, original-file preservation on removal, coordinated stale-note conflicts, copying with assets/source references while excluding SQLite and conversations, cloud placeholders, remotely removed documents and malformed manifests. Draft ordering, reopening, conditional clear and recovery of both versions are verified.
- 11 editor tests pass; production dependency audit reports no known vulnerabilities. All 268 UI localization keys have English entries.
- Baseline native integration: 53 checks pass in English and 53 in Simplified Chinese. This includes real PDFKit, WKWebView, captures, source navigation, Markdown semantics, math, exports and AI protocol fixtures. Nine foreground/fullscreen-focus checks are explicitly skipped because this session cannot reliably activate their test windows. Earlier focus evidence remains in WORKSPACE_FIXES.md; this release does not invent new foreground results.
- New native workspace integration: 15 checks pass in each language using an ordinary shared folder, and 14 in each language using an actual iCloud Drive folder. It exercises the production bootstrap/model replacement, local-draft recovery in WebKit, byte-preserving PDF copy, note identity, original-library retention, local index placement, bookmark reopening in a newly launched application process, relative screenshot rendering, independent-store edit reload, in-place nested PDF discovery, native rename, filesystem refresh, and return to the original library.
- Generated diagnostic Markdown files, including a note under hidden `.paper-reader`, reached `ubiquitousItemIsUploaded == true` with no upload error on this Mac. An initial system error 4355 cleared without changing the user's iCloud switch. This proves single-Mac Drive upload, not remote-device receipt.
- Six Sparkle signature checks pass using disposable keys: archive and appcast signing/verification and tamper rejection. No private research documents or secrets are committed to the repository or included in the website demo.

## Reproduce

```sh
PAPER_READER_SKIP_INTERACTIVE_FOCUS=1 scripts/test.sh
# Optional: generated fixtures only, under a folder you choose in iCloud Drive.
PAPER_READER_TEST_CLOUD_ROOT='/absolute/path/to/an/iCloud Drive/test folder' scripts/test-workspace.sh
python3 scripts/test-release.py
```

The workspace runner isolates the original library and uses a separate preferences suite. Reports are in `~/Library/Caches/PaperReader/Build/Reports/workspace-{en,zh-Hans}.json`. It creates fresh generated workspaces; it never opens the user's production library or uses production AI credentials. The cloud runner does not assert upload timing or a second Mac's visibility.

## Limits

No second physical Mac was available. Multi-device upload/download ordering, concurrent offline edits across physical Macs, low-disk conditions, provider outages lasting hours and large cloud libraries have not been exhaustively tested. This is file sync, not real-time collaborative editing or a distributed database. Notes use expected-revision checks plus local drafts and system-version copies; folder structure, annotations and metadata do not implement automatic merging. Avoid simultaneous organization/annotation changes on multiple devices. API keys, conversation history and reading positions are deliberately local.

Published archive signing, notarization, Gatekeeper and live-feed results are recorded separately in RELEASE_VALIDATION.md / release-distribution.json after publication.

## Relaunch correction in 0.4.1

The first 0.4.0 test resolved a security-scoped bookmark only inside its creating process. A real restart exposed Cocoa error 259 with sandbox-scoped resolution in this unsandboxed Developer ID application. 0.4.1 uses ordinary persistent bookmarks and resolves them without `withSecurityScope`, following the API’s App Sandbox distinction. A separate invocation of the actual app executable must now resolve the saved bookmark successfully before the workspace test passes. Folder chooser content types are explicitly restricted to directories.

API references: [Apple bookmark creation](https://developer.apple.com/documentation/foundation/nsurl/bookmarkdata(options:includingresourcevaluesforkeys:relativeto:)), [App Sandbox file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox). The correction changes no OS security settings or entitlements.
