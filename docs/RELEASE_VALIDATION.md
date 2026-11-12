# Distribution validation — 2026-11-13



## Current release 0.4.6 / build 11

Published [v0.4.6 on GitHub](https://github.com/CBDT-JWT/paper-reader/releases/tag/v0.4.6) from source `69be249`. The final Ask AI control is an icon-only button directly beside the reading tools in the PDF toolbar, with a localized name and configured shortcut in its tooltip. This placement follows the user's final instruction. The reader retains the light pastel-blue native top chrome, neutral PDF canvas and bottom-left page capsule.

Downloaded the public 11,068,088-byte DMG. SHA-256 `518bcea1ae7b9c99cff09aa8d1ef5e5710a178ca56960a36a9abc5e925767dbc` matches the published checksum and live HTTPS release manifest. Read-only mounting verified version 0.4.6 (11) and the Applications link. Strict recursive code-signature, stapler and Gatekeeper checks passed for the downloaded app and DMG. Application notarization `f56d1b7d-06ac-48d8-89cd-3b38e73e975d` and DMG notarization `0a2c797a-e00c-475c-a7f5-6c3796b0cc02` were Accepted. The live signed feed verifies with Sparkle's official verifier and exactly matches the repository feed.

Completed the actual Sparkle update from installed 0.4.5 to 0.4.6. The About dialog showed 0.4.6 (11). The 27-paper workspace reopened on the selected paper at 2/8 with the shared note saved. Native accessibility shows `reader.askAI` immediately after `reader.tools`, with help text containing the configured shortcut. Clicking the icon opened the AI composer with provider/model controls, and Escape closed it. No question or private paper was sent. The installed executable, Info.plist and signature manifest match the public app byte-for-byte. Its strict signature, ticket and Gatekeeper checks passed after update.

Source verification [43256198317](https://github.com/CBDT-JWT/paper-reader/actions/runs/43256198317) and website deployment [43257401619](https://github.com/CBDT-JWT/Home/actions/runs/43257401619) succeeded. Final coverage includes 53 Swift core tests, 12 editor tests, six signature tests and 30 native workspace checks in each language. The signed release build also passed those 30 checks per language. Reader/full-screen regression coverage remains the 150-per-language 0.4.4 run documented below.

Page-only AI note citations now carry their originating paper and portable filename. New approved note proposals normalize these citations before preview. Legacy per-paper notes receive the same conversion during merging. Previously merged sections bearing application migration markers receive a one-time coordinated repair and a complete local pre-repair recovery copy. The actual workspace's two legacy page links were repaired, with surrounding Markdown byte-identical after excluding source URLs. Unmarked old page links retain their text because the originating paper cannot be established automatically. Core tests cover both the conversion and this preservation behavior, and the native reader test verifies switching papers to the cited page.

The earlier duplicate-index incident and its repair are recorded below and in [folder document evidence](FOLDER_DOCUMENTS.md). Its recovery snapshot remains on the local Mac. Actual two-Mac concurrent iCloud editing, Intel, third-party cloud AI inference and local-model inference remain untested. Earlier macOS has core/build CI coverage, while its full native window interactions remain unverified.

## Historical release 0.4.5 / build 10

Published [v0.4.5 on GitHub](https://github.com/CBDT-JWT/paper-reader/releases/tag/v0.4.5) from source commit `f8b535f`. Downloaded the public 11,063,200-byte DMG again. SHA-256 `2e9c404334751042264b68f0f65ce6e10d068111a0f7972253c41426059ba85c` matches the published checksum and live website metadata. Mounted read-only, verified version/build and the `/Applications` destination link, and passed strict recursive code-signature, stapler and Gatekeeper checks for both the public app and DMG.

Application notarization `2eaa8e00-0f62-4c34-9b10-7f6e6c6ec487` and DMG notarization `5f31ecf6-168b-4a69-8d40-35b8017a505c` were Accepted. Both Gatekeeper assessments identify Notarized Developer ID, team `Q83556V27Y`. The live HTTPS release manifest and appcast match the repository. Sparkle's official verifier accepts the production-signed live appcast. [Source verification 43252922939](https://github.com/CBDT-JWT/paper-reader/actions/runs/43252922939) and [website deployment 43254127404](https://github.com/CBDT-JWT/Home/actions/runs/43254127404) succeeded.

Performed the actual update from installed 0.4.4 through Check for Updates, Install Update and Install and Relaunch. The About dialog displayed 0.4.5 (10). The original 27-paper workspace, selected paper on page 2/8 and saved shared `notes.md` reopened successfully. The top Ask AI button and bottom-left page capsule were present. The installed executable, Info.plist and signature manifest match the public DMG byte-for-byte. Its signature, stapled ticket and Gatekeeper assessment passed after replacement. A copy of the previous installation remains outside the workspace.

This release passes 51 Swift core tests locally and on GitHub's earlier macOS runner, 12 editor tests, six Sparkle signature tests, and 29 real native workspace checks per language. The signed release application also passed those 29 checks per language in isolated disposable folders. Production dependency auditing reported zero vulnerabilities. The preceding 0.4.4 reader run passed 150 foreground checks per language, including full-screen focus and the supplied seven-page paper. Final 0.4.5 changes cover annotation identity compatibility and shared-note draft recovery. Foreground reader geometry was covered by that preceding run.

Earlier PDFKit preserves the custom embedded annotation record while omitting the standard /NM name during serialization. Ownership now follows the namespaced embedded record, retaining canonical and legacy custom-key compatibility. A regression fixture with no /NM verifies reading and undo deletion. The existing third-party annotation, fractional geometry, legacy migration and stale-save rejection tests pass on the CI runner. A read-only local check also reopened both annotations written by 0.4.4 in the existing paper.

The folder workspace now uses one shared root Markdown, lazy root assets and direct standard PDF annotations. Native chrome follows system appearance with a pastel-blue light toolbar, neutral PDF canvas and consistent flat rounded panels. During earlier UI inspection an unintentionally launched development instance overlapped an older installed version and produced duplicate metadata. The active index was repaired to 27 unique PDFs after a full local recovery snapshot. All 108 pre-existing migrated-note archives were retained byte-identically. One paper received its two legacy line annotations and its seven original page-content renderings stayed byte-identical. Recovery material remains local. See [folder document evidence](FOLDER_DOCUMENTS.md).

Actual two-Mac concurrent iCloud editing, Intel, third-party cloud AI inference and local-model inference remain untested. Older macOS has CI coverage for core tests and release packaging. Its full native window interactions remain unverified. Figure and caption detection remains heuristic for unusual layouts.

## Historical release 0.4.4 / build 9

Published from `932b457` with application notarization `c7af5402-2fa7-4cb8-85b2-c3d6a10706e6` and DMG notarization `32f048e1-067f-4fb2-91fb-d3d797365a45`, both Accepted. Its public DMG SHA-256 is `ebc08de5a29a8fe597ba84e55d55a9ca80c8dd267e3b896008cdd698950e96cc`. Local 50 core tests, 12 editor tests, 150 foreground native reader checks and 29 workspace checks per language passed. Older-macOS CI exposed missing annotation identities after PDF serialization. Version 0.4.5 addresses that compatibility failure and supersedes this release.

## Historical release 0.4.3 / build 8

Published [v0.4.3 on GitHub](https://github.com/CBDT-JWT/paper-reader/releases/tag/v0.4.3) from source commit `4584f83`. Downloaded the public 10,908,253-byte DMG again. SHA-256 `d011a09792b63593a7b350324d16f1157c2442dbf319a9ed19a29aae8041137a` matches both the published checksum file and website metadata. Mounted it read-only and verified the application version/build and `/Applications` destination link. Strict recursive code-signature verification, stapler and Gatekeeper checks passed for the public app and DMG.

Application notarization `b6c1808e-fb51-4f96-b68d-aa95d3abcf86` and DMG notarization `d2034190-f1b2-4539-997f-e8cf6a8f12d4` were Accepted. Both assessments identify the Developer ID Application team `Q83556V27Y` and return Notarized Developer ID.

The live HTTPS website metadata matches the repository manifest. Sparkle's official verifier accepts the production-signed live appcast. The signed 0.4.2 / build 7 host discovers 0.4.3 / build 8 through Sparkle's information-check API. GitHub verification [run 42975674638](https://github.com/CBDT-JWT/paper-reader/actions/runs/42975674638) and website deployment [run 42975703852](https://github.com/CBDT-JWT/Home/actions/runs/42975703852) completed successfully.

Performed the actual application update through the installed 0.4.2 menu. Sparkle offered 0.4.3, downloaded the public archive and enabled Install and Relaunch. That action replaced the application in `/Applications` and reopened the existing workspace with its 27-paper tree, selected paper, reading position and saved note. The About dialog displayed version 0.4.3 (8). The installed executable, Info.plist and signature resource manifest match the public DMG app byte-for-byte. Its strict signature, stapled ticket and Gatekeeper assessment pass after replacement. The previous installation was backed up outside the workspace before updating.

Validation passed 39 Swift tests, 12 editor tests and 150 native checks in each language, including foreground/full-screen focus, read-only traversal of the supplied seven-page paper and actual Codex catalogue/inference checks. A subsequent AI-only run passed 21 checks per language after the final model-field and shared-schema changes. Workspace checks passed 15 per language using disposable ordinary folders. Six Sparkle signature checks passed with disposable keys. The production dependency audit reported zero vulnerabilities. See [AI validation](AI_VALIDATION.md) and [focus validation](FOCUS_MOTION.md).

Actual third-party cloud access and local model inference remain untested in this release. Loopback fixtures cover their model-discovery, streaming and tool HTTP contracts. Figure and caption detection remains heuristic for unusual document layouts. Intel and older macOS runtime validation remain pending.

## Historical release 0.4.2 / build 7

Published at https://github.com/CBDT-JWT/paper-reader/releases/tag/v0.4.2. The public DMG checksum matches the website metadata. Downloaded the archive from GitHub, mounted it read-only, validated app and DMG tickets with stapler, and verified strict recursive code signatures. Gatekeeper accepted both as Notarized Developer ID.

Application notarization `5d14989e-6b60-472f-877c-e2f8f1066033` and DMG notarization `4ff4ecb0-7969-485c-af12-9d932936fc41` were Accepted. The live HTTPS appcast verifies with the production Ed25519 key and announces build 7 with the matching archive URL.

32 Swift tests, 11 editor tests and 85 native integration checks pass in each language. The interactive full-screen checks ran successfully. Workspace integration passes 15 checks per language. [Focus validation](FOCUS_MOTION.md) records geometry, intermediate camera movement, velocity changes and fractional-edge pixel coverage.

Installed the public notarized app in Applications and reopened the current workspace. Through the actual toolbar and popover, enabled focus, started playback, changed speed from 45 to 50, paused and restored 45. The linked note showed saved status and the cloud note showed uploaded status. A stale development instance was closed while replacing the old app to clear the local index contention.

## Historical release: 0.4.1 / build 6

Published at https://github.com/CBDT-JWT/paper-reader/releases/tag/v0.4.1 and linked from the live HTTPS website. 0.4.1 supersedes 0.4.0 and fixes unsandboxed workspace bookmark reopening across application launches.

- Application notarization `2565030e-6195-43c3-a2b6-731bcfe23167`: **Accepted**. DMG notarization `eb4f3a39-3a8d-4abd-a865-c70d78111e2d`: **Accepted**. Developer ID Application team Q83556V27Y.
- Downloaded the public 8,614,613-byte DMG from GitHub, verified SHA-256 against SHA256SUMS.txt and website metadata, mounted read-only, and validated the DMG and included app tickets with stapler. Gatekeeper accepted both as **Notarized Developer ID**; strict recursive code-signature validation passed.
- The actual public app executable resolves a persisted ordinary workspace bookmark in a fresh process. The source/native suite passes 29 Swift tests, 11 editor tests, 53 baseline checks per language and 15 workspace checks per language (ordinary folder and real single-Mac iCloud Drive). Nine interactive focus checks were explicitly skipped in this session. See [cloud and folder evidence](ICLOUD_VALIDATION.md).
- Retrieved the live HTTPS feed and verified its production Ed25519 signature with Sparkle’s official verifier. Its version, immutable download URL and length match the published artifact. The original signed 0.3.0 / build 4 host discovers **0.4.1 / build 6** through Sparkle’s real information-check API. Automatic binary replacement/relaunch is still not validated.
- No private papers, API keys, Apple credentials, signing keys or user workspace bookmarks are included in public assets or test reports.

The original 0.3.0 release evidence follows for continuity.

## 0.3.0 historical release validation — 2026-11-10

Environment: Apple Silicon, macOS 27.3 / Xcode 27 / Swift 6.4 / Node 26.4.

- Swift core tests: **19 passed**. Editor tests: **11 passed**; production dependency audit: zero reported vulnerabilities.
- Real native app / bundled WKWebView / PDFKit: **53 passed in English and 53 in Simplified Chinese** with explicit noninteractive focus mode. Covers actual offline editor/math/diagrams, Markdown preservation and conflict checks, captures/source links, native file tree drag payloads and folder/sort persistence, sidecar annotations and PDF export, AI proposal approval/undo and loopback streaming/tool/image requests, long paginated note export, embedded Sparkle loading and public feed/key packaging.
- **Nine foreground/fullscreen mask interaction checks were skipped**, explicitly recorded as `interactiveFocusSkipped: true`. Current macOS desktop session refused foreground activation. Normal interactive runs failed at that prerequisite, before enabling the mask. Earlier 0.2.1 interactive focus/window checks remain historical evidence only; this release does not claim them revalidated. Reports now default to a cache directory because an atomic report rename in the synced Documents directory blocked the test's main thread during investigation.
- Installer: a real DMG was built and mounted read-only; embedded app signatures verified, `/Applications` link checked, Finder window bounds 760×460 and app/destination icon positions checked from `.DS_Store`. A copy installed into an isolated directory passed 53 native checks from the packaged release executable (interactive focus checks explicitly skipped).
- GitHub CI: clean checkout core/editor tests, optimized app packaging and signature tests passed in runs 42809852498 and 42810123330 after fixing build-directory initialization.
- Sparkle official CLI: **six checks passed**, using disposable private test keys, including successful archive/feed signature verification and rejection of tampered content. Production signing key was generated in login Keychain; private material was not exported. Initial unattended Keychain prompts blocked foreground tests; after the publisher granted access locally, production-key signing and verification of the initial appcast passed. Mandatory signed-feed validation is enabled.
- Live update endpoint: the actual Sparkle framework loaded and parsed the public HTTPS appcast and returned a valid empty stable feed (zero updates). This verifies configuration and real feed retrieval; it is not an installation/relaunch test. Reproduce with `scripts/verify-update-feed.swift`, linking the resolved Sparkle framework.
- Website: rendered and inspected at 1440px and 390px; Chinese/English switching and browser persistence checked; no horizontal overflow at 390px. Demo artwork is a rendering of actual native workspace views, PDFKit pages and WKWebView snapshots at measured live frames, with a locally generated paper. It is not a screenshot of private research or a mock HTML product UI. Public product page and update endpoint returned HTTPS 200; the appcast is served without caching. Existing homepage deployment runs completed successfully.

Reproduce normal validation with `scripts/test.sh`. In a desktop session that cannot activate test windows, explicitly use `PAPER_READER_SKIP_INTERACTIVE_FOCUS=1 scripts/test.sh`; that is partial GUI coverage, not a substitute for an interactive run. Reports: `~/Library/Caches/PaperReader/Build/Reports/` by default. Override with `PAPER_READER_TEST_REPORT_DIR` outside synced folders. `python3 scripts/test-release.py` exercises Sparkle signatures without accessing the production private key.

## Final distribution verification

The publisher installed a matching Developer ID Application certificate and configured the local `PaperReader` notarization profile. Release **v0.3.0** is published at https://github.com/CBDT-JWT/paper-reader/releases/tag/v0.3.0 and linked from the live website.

- Application notarization: **Accepted**, submission `4298d105-bcd4-4f2b-b779-523bfc2f14d9`.
- DMG notarization: **Accepted**, submission `6041fa7d-9ab9-43d9-8381-7c90a3290187`.
- Stapler validation succeeded for the original application and DMG. Both Gatekeeper assessments returned **Notarized Developer ID**.
- Downloaded the actual public GitHub DMG again. Its SHA-256 matches the published checksum and website manifest; size is 8,409,342 bytes. Rechecked the downloaded DMG’s signature, stapled ticket and Gatekeeper assessment, then mounted it read-only. The embedded app’s signature, stapled ticket and Gatekeeper assessment also passed.
- Copied that app from the downloaded DMG into an isolated installation directory. The actual hardened-runtime / Developer ID signed executable passed **53 English and 53 Simplified Chinese native checks**, with the nine interactive focus checks explicitly skipped as above. No user research library was used.
- Retrieved the live HTTPS appcast and verified its production Ed25519 signature with Sparkle’s official tool. The enclosure URL, file length and archive checksum match the published download. The appcast contains one stable release, build 4 / version 0.3.0, requiring macOS 14+ and arm64.
- Sparkle loaded and validated that signed live feed from the published app bundle and correctly offered no newer update to build 4. A separately re-signed temporary host fixture with build 3 discovered eligible update **0.3.0 / build 4** through the real Sparkle information-check API. This tests update discovery, not automatic replacement/relaunch; that fixture was not distributed or notarized as an older release.

The complete old-to-new automatic installation/relaunch sequence, Intel, older macOS versions, and the nine foreground/fullscreen checks remain outside this release’s completed validation. There is no claim that every phase’s advanced feature or every environment has been validated. Public release verification metadata is recorded in [release-distribution.json](release-distribution.json).
