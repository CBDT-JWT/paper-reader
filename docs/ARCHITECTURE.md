# Architecture and implementation checkpoints

Phase 1 is the current delivery target. Phase 2 features are only claimed when verified.

- `PaperCore`: Sendable domain records, actor-owned SQLite index and atomic file store, Core Graphics PDF rasterization. No SwiftUI dependencies.
- `PaperReader`: MainActor application state, command registry, SwiftUI shell, AppKit PDFView, WKWebView adapter. Views dispatch actions; file IO is in an actor.
- `WebEditor`: pinned MIT Tiptap 3, official Markdown adapter, KaTeX; esbuild bundles all JS, CSS and fonts offline. Source and generated resources are versioned.
- Library layout: `<Application Support>/PaperReader/Library/<UUID>/{paper.pdf,note.md,assets/,sources.json}`. The SQLite index is rebuildable from per-paper `paper.json`; PDFs are copied without modification. No account required.
- JS bridge messages always carry paper ID. Native state rejects stale messages after switching. JS serialization is synchronous at every editor update; atomic IO happens asynchronously. Explicit save, export, switching and termination flush pending work. Unrepresentable imported Markdown is rejected before replacing a note. Relative local image assets are preflighted, copied under new UUID names and rewritten in the Markdown tree.
- Source references: relative images plus standard Markdown links `paperreader://source/<UUID>`. Page and PDF-space rectangle are stored independently in `sources.json`.
- Custom URL scheme serves only bundled editor assets and the active library's contained assets; arbitrary path traversal and remote editor subresources are blocked.
- PDF crop service owns a fresh CGPDFDocument per detached task. PDFKit UI document stays on MainActor. Coordinates are PDF user space, transformed through crop-box rotation for raster output.

## Independently verifiable steps

1. Build native package and app bundle; launch a real native window.
2. Offline WKWebView loads Tiptap and KaTeX; text editing emits Markdown.
3. Supported Markdown parse → edit → serialize → parse preserves structure, math, tables, tasks, images and source links.
4. Persistent paper IDs, note association, atomic save and external-change rejection; restart and recovery.
5. PDF selection rectangle renders at 3× in page coordinates, including rotations; image inserts at note cursor and links back to PDF.
6. Native open/import/export and adjustable native split views; verify with a real generated PDF fixture.

## Next phases

Phase 2 remaining: full hierarchical folder management, complete configurable command bindings, robust import of arbitrary Markdown dialects, production print pagination, multi-window note view, broad hardware/performance testing.
Phase 3: sidecar annotations with undo, column-aware line layout/cache/mask, metadata lookup/validation and citation formats. No approximation claiming multi-column support in Phase 1.
Phase 4: provider protocol, Codex App Server transport, cloud streaming, constrained read/search tools, explicit diff approval and undo. No arbitrary shell/file tool exposed. Codex CLI is not local inference.

## Risks

Tiptap's official Markdown package is beta. Guard import by semantic round-trip validation and preserve original imports. Markdown normalization is expected, byte-for-byte formatting preservation is not. Unsupported syntax must not be silently overwritten.
WKWebView and PDFKit require actual macOS integration tests beyond pure unit tests. Export uses asynchronous WebKit print pagination and a MainActor completion bridge, writes to a temporary file, then atomically replaces the destination. A real 11-page fixture passed; broad layout QA remains before a production claim. SwiftPM resources are copied into the app bundle by the build script. App is ad-hoc signed in a non-synced cache directory, with a launch symlink and portable ZIP, and is not notarized for distribution.
