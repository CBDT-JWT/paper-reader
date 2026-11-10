# Distribution and updates

Website: https://www.weitao-jiang.cn/paper-reader/
Source: https://github.com/CBDT-JWT/paper-reader

The current development machine has an **Apple Development** identity only. That is not a Developer ID distribution identity. Do not call ad-hoc/development builds notarized, or put them in the stable appcast.

## One-time production setup

1. Enroll in the Apple Developer Program. In Xcode / Apple Developer Certificates, create and install a **Developer ID Application** certificate and its private key. The key must remain in Keychain.
2. Store notarization credentials locally (the interactive command prompts securely):
   ```sh
   xcrun notarytool store-credentials PaperReader
   ```
   Use an Apple ID app-specific password with the appropriate team, or Apple's supported App Store Connect API credentials. Do not put passwords, `.p12`, `.p8`, or private update keys in this repository.
3. The Sparkle Ed25519 key was generated under Keychain account `dev.paperreader.mac`. Its **public** key is committed in `scripts/Info.plist`. Preserve and securely back up the private key in Keychain; replacing it without a supported key rotation would break installed clients. On a new publisher Mac, use Sparkle's documented secure key import. `scripts/release/setup-update-key.sh` generates/shows the public key without exporting private material.
4. Authorize Sparkle's signing tools in the local Keychain prompt when needed. Neither the build nor CI exports the private key.

## Publish a stable release

Increment both version and monotonically increasing build number in `scripts/Info.plist`; write release notes. Commit the source and run the full test suite first:

```sh
scripts/test.sh
export PAPER_READER_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export PAPER_READER_NOTARY_PROFILE='PaperReader'
scripts/release.sh stable docs/releases/0.3.0.md
```

The script checks the identity and notarization profile before building, embeds Sparkle with relative framework search paths, signs nested helpers inside-out with hardened runtime and timestamps, submits/staples/validates the application, creates the Finder drag-to-Applications DMG, signs and notarizes/staples the DMG, and assesses both with Gatekeeper. No `--deep` is used for signing. Existing Sparkle helper sandbox entitlements are preserved. The final DMG is uploaded as an immutable GitHub release asset with SHA-256 checksum. Sparkle's official `generate_appcast` signs the archive and feed using the Keychain key; the feed is verified before publication. The release is published before the website points at the new download.

`scripts/deploy-website.sh` copies **only** this project's website and adds two product routes to the existing private `CBDT-JWT/Home` Flask repository. Its existing self-hosted deployment workflow handles deployment. The personal homepage and DNS are retained. Override `PAPER_READER_WEBSITE_REPO` with a clean checkout path if needed. Monitor `gh run list --repo CBDT-JWT/Home`, then verify the public page, JSON and appcast over HTTPS. Release metadata changes are committed separately for an audit trail.

The publisher needs `gh` authentication with access to both repositories; binaries and signing/notarization credentials are never stored on the web server. This is a repeatable **local release pipeline**, not a claim that hosted CI already has distribution certificates.

## Preview releases

`scripts/release.sh preview docs/releases/0.3.0.md` publishes a clearly labeled development prerelease. It does not require a Developer ID certificate and does **not** add its archive to the stable appcast. Website metadata records `notarized: false`. macOS can block an unnotarized download. A preview does not fulfill production signing requirements.

## End-user updates

Sparkle 2.10.1 is pinned with its upstream checksum and revision. The app embeds the framework and helpers. The App menu has “Check for Updates…”; Settings offers automatic checks. Sparkle manages consent/scheduling and validates the Ed25519 archive signature before extraction. The publisher also signs the feed; mandatory feed-signature enforcement is currently disabled so that the initial empty feed remains usable before signing authorization. System profiling is disabled. The application delegate flushes notes before terminating for an update. Feed URL: `https://www.weitao-jiang.cn/paper-reader/appcast.xml`.

The supported binary currently targets **Apple Silicon / macOS 14+**. Intel is not advertised or validated. A complete production replacement/relaunch test requires a notarized old/new build pair; it cannot be claimed from an ad-hoc build or a signature round trip alone.

References checked 2026-11-10: [Sparkle integration and signing](https://sparkle-project.org/documentation/), [programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution), [dmgbuild settings](https://dmgbuild.readthedocs.io/en/stable/settings.html). Sparkle 2.10.1 is MIT licensed; full bundled notices are preserved in `assets/Sparkle-LICENSE.txt` and its framework. dmgbuild 1.6.7 is MIT licensed, used only as packaging tooling; release artifacts and project maintenance were checked before adoption.
