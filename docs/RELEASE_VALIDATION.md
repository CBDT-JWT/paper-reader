# Distribution validation — 2026-11-10

## Current release: 0.4.1 / build 6

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
