# Architecture

0.4 implements the core workflow across Phases 1–4. README lists deliberately bounded or deferred capabilities; this is not a claim of exhaustive production certification.

## Module boundaries

- **PaperCore**: Sendable domain records; actor-owned SQLite and atomic file store; rebuildable manifests; folders/trash; Core Graphics crop renderer; pure column layout and reading-order algorithm; Crossref/arXiv clients; bibliographic formatting; system language resolution; provider protocol and OpenAI-compatible SSE client. No SwiftUI dependency.
- **PaperReader**: MainActor orchestration (`AppModel`), shared `CommandRegistry`, native NSOutlineView library UI, AppKit PDF view and native overlays, WKWebView adapter, settings, AI controller, Codex JSON-RPC client. Views dispatch commands; persistent IO runs in the library actor.
- **WebEditor**: pinned Tiptap 3, official Markdown adapter, KaTeX, custom image resizing and Mermaid code-block node views. esbuild includes JS/CSS/fonts/licenses in the application; no CDN at runtime.

## Data flow and ownership

Paper UUID is the only identity; title/logical filename/folder are mutable attributes. New imports retain their original filename in an optional manifest field; older records fall back to the existing title. LibrarySort applies natural filename/title ordering or import date within every folder, with preferences persisted. Organization mutations read current manifests inside the actor; metadata and reading updates patch only their own fields. The native outline owns drag sessions and keeps row identities stable across reading-state changes; business-data reloads are deferred during a drag. Folder and paper drag providers use a dedicated UTI and share the same validated organization operations as context menus. Naming uses a SwiftUI sheet on the workspace, including in full screen. Each paper has ordinary PDF/Markdown/assets and independent source, annotation, metadata and conversation records. SQLite is rebuilt from manifests at startup. Folder cycles are rejected. Trash moves the entire managed directory and supports restoration.

The WebKit bridge carries paper ID on every edit. Stale updates are rejected. One save worker owns revision transitions; switching, export and termination flush WebKit and the queue. Atomic note replacement retains the previous file. External edits are polled every two seconds and checked again on save; conflict copies preserve both authors' content. Unsupported Markdown fails before mutation; semantic round-trip validation does not promise original whitespace.

PDFKit UI documents are transferred once from background construction and then used on MainActor. The last three remain cached. PDF coordinates are canonical; crop renderer owns a separate CGPDFDocument per background task and handles rotation/crop origin. Page text/layout extraction uses fresh, worker-owned PDFKit documents; the visible document is not shared with workers. PDFKit annotated export is handled by a short-lived instance of the same executable in `--export-annotations` mode: annotation construction, serialization and release run on that process's main thread, while the interactive process awaits asynchronously. The helper has no UI, model access or shell evaluation.

## Focus and annotations

Annotation records are independent PDF-space geometry, with undo/redo snapshots and serialized atomic sidecar saves. Laser marks expire and never persist. Source highlights are separate temporary overlays.

Focus extracts character rectangles once per page and reconstructs physical rows/gutters, retaining composed Unicode characters. Near-zero-size invisible vector metadata is rejected. Logical text breaks are hints: a citation font change must not fragment a physical line. Substantial prose establishes typical body width, height and horizontal extent; median group extents prevent centered titles or dense figure labels from bridging columns. Spanning blocks are separate, and overlapping font boxes use the closest physical baseline rather than padded title hit boxes. Focus windows stay within one column and one vertical band. Reading order traverses each column before advancing, with spanning headings/formulas between bands. Manual columns clip geometry explicitly. Scan fallback is a geometric band, not OCR.

Mouse tracking updates the anchor; a click under the drag threshold toggles pinning. Pinned arrows navigate cached reading order; adjacent cached pages can be crossed. Scrolling in mouse mode re-anchors within the viewport. When a pinned line is off-screen, the dark field remains enabled with no visible hole.

`ScreenFocusMask` creates one nonactivating, mouse-transparent NSPanel per NSScreen.frame with fullScreenAuxiliary and canJoinAllApplications collection roles. It keeps panels independent so attaching them as child windows cannot reset their level to the document window level. Native full-screen start/end and active-Space notifications resynchronize visibility and geometry. A CAShapeLayer draws a black mask with merged rectangular holes converted from PDF to window to screen coordinates. Windows are above the app/menu bar and hide when the app resigns active. No screen capture, global input interception or screen-recording permission is used. Esc disables focus. Geometry observers filter the PDF window to avoid feedback from mask windows.

## AI safety and interchangeability

`AIProvider` consumes `AIRequest` and streams text/status events. Cloud and local HTTP clients implement the OpenAI-compatible chat/SSE/function protocol; loopback HTTP is permitted, other endpoints require HTTPS. Codex starts a stdio App Server with shell, apps, image-file tools, MCP/plugins, multi-agent and built-in web search disabled; ephemeral read-only threads expose only the declared research tools. Permission and unknown capability requests are refused.

Only the app resolves the current paper/note/source index. Model tools never take arbitrary file paths. Rendered PDF images are attached through native multimodal fields, not filenames. External scholarly retrieval uses Crossref and returns actual metadata URLs. User must enable it in settings.

AI note tools create a proposal only. The user sees before/after content and applies explicitly; the editor compares the expected original Markdown before replacement, validates supported syntax, and creates a separate undo group. Conversations are saved per paper and restored across launches. API keys use Keychain; provider preferences use UserDefaults. Codex is a local transport process and may use remote inference.

## UI and localization

Native three-column split layout remembers widths/visibility. Adaptive toolbars have 30-point icon targets, hidden redundant menu indicators, spacing and native semantic colors; UI fonts use 12/14/20 points and common radius 8. Editor/document content uses reading typography.

Chinese source keys resolve through `L`; generated English/Chinese resources are bundled in both SwiftPM and the app's main bundle so system menus choose the same language. Web editor receives a matching language parameter. `localize.py --check` rejects missing English entries without rewriting files. Unsupported system languages fall back to English; document content is never translated automatically.

## Validation strategy

Pure tests cover identity/file safety, coordinate transforms, metadata/citations and two/three-column layouts including spanning blocks. Node tests cover Markdown parse/edit/serialize semantics, source links, math, image sizes and Mermaid source retention. The real app's isolated self-test covers WebKit, PDFKit, whole-screen native window coverage including isOnActiveSpace, real full-screen entry/re-enabling/exit, folder and paper NSItemProvider drop handling, natural sorting, focus pinning, annotated PDF export, diffs/undo, HTTP SSE/tool/image contracts and multipage native print export in both languages. Optional live tests verify Crossref and installed Codex model listing/text/vision. See VALIDATION.md for exact evidence and limits.

## Folder workspaces and iCloud Drive (0.4)

`WorkspaceLocation` owns a user-selected persistent folder bookmark. It does not assume that a hardcoded iCloud path is authoritative: resource ubiquity is checked on the selection/ancestors. `NSOpenPanel` is the normal authorization surface. The Developer ID build does not adopt App Sandbox and uses ordinary bookmarks, resolved without the sandbox-only `withSecurityScope` flag. A new-process verifier checks persistence across process boundaries, not only in the creating process. No CloudKit container or iCloud entitlement is required to coordinate ordinary user-selected iCloud Drive documents. The known Mobile Documents path is only a picker hint.

`LibraryStore.documentsRoot` links discovered PDFs through a contained, symlink-rejecting relative path. The shared `.paper-reader/<UUID>` directory holds manifests, notes, assets and sidecars; migrated managed PDFs may remain there as `paper.pdf`. `WorkspaceLibrary` preserves IDs through app moves and a device-local resource-identifier map for Finder moves. `LibraryOrganization` performs physical moves only in folder workspaces and refuses overwrites/cycles/nonempty folder removal. External originals survive removal from the workspace index.

SQLite is always in local Application Support for selected workspaces, partitioned by folder-path hash. Reading positions and conversation files live in local `DeviceData`; shared manifests contain no device reading position. Old conversations migrate locally when switching, and the cloud copy excludes conversations, databases and drafts. The original local library remains available.

`CoordinatedFiles` owns NSFileCoordinator read/write/move operations off MainActor, checks evicted/legacy placeholders, and never treats a known pending download as an empty note or metadata array. The presenter and a coalesced polling fallback rescan folder changes and reload clean notes. Note compare-and-write happens inside one coordinated write. NSFileVersion note conflict data is copied to ordinary Markdown files before resolving its system flags. Folder/annotation/metadata conflicts are not an automatic CRDT merge.

`NoteDraftJournal` is an independent actor on local storage, so a stalled cloud coordinator cannot block draft staging. Monotonic sequence numbers reject reordered stages; successful note writes clear only matching drafts. Reopening recovers a draft against its base revision, or archives both sides before the user chooses. Switching freezes WebKit mutations, drains document jobs and saves, prepares the destination, then replaces the model. Failed preparation leaves the previous workspace usable. The bootstrap has recovery buttons if a saved folder is unavailable.
