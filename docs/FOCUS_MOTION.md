# Focus motion validation — 2026-11-11

The focus controller owns the reading-line anchor and cached layouts. `FocusMotion` interpolates the aperture and PDF clip-view origin together. The frame uses a single bounding rectangle for its context lines, constrained to the selected column. The reading anchor remains separate from the rectangle centre, which can differ with unequal context counts.

The mask contains a single reusable black-alpha penumbra texture. Gaussian coverage is constrained to the inside of the frame. A minimum two-device-pixel overlap covers the antialiasing join between texture and exterior mask. This removes corner patches, outward halo and bright hairlines while leaving the paper visible through the transparent core. The template is cached by softness and display scale. Moving the frame reuses its layer contents.

At a column/page handoff, the camera eases to the destination while the aperture briefly fades, keeping its viewport anchor central. Same-column automatic motion integrates the current speed on every frame. Arrow input interrupts playback. Layout loading, motion cancellation, document changes and application deactivation use the same controller state. Exiting focus constrains the scroll position back to normal document limits.

## Checks

- Swift geometry tests verify context containment, interline coverage, column/gutter boundaries, spanning titles, manual-column clipping and left-bottom/right-top order. The complete Swift suite has 32 tests. The editor suite has 11 tests. Native integration passes 85 checks in each language, with interactive focus/full-screen checks enabled, and workspace integration passes 15 checks per language.
- Native tests use real generated three-page PDFs and PDFKit scroll views. They check forward/reverse column handoffs, intermediate camera positions and frame centring, page handoff, first/last-page centring, manual column calibration, live speed changes, manual interruption, app-deactivation handling and stopping at the document end.
- Core Animation snapshots check clear core / soft edge / dim exterior pixels, symmetric corners, absence of a bright seam at fractional positions 0.125 / 0.25 / 0.5 / 0.75, and stable exterior dimming while fading. A PDF-backed preview is rendered with the same mask layers.
- Full-screen integration checks exercise entering full screen, enabling focus there and returning to the normal window, including active-Space membership and coverage of the displays connected to this Mac.
- Editor round-trip/export tests and the existing workspace tests are rerun alongside focus tests. UI strings follow the app’s system-language selection.

Synthetic test libraries and images stay outside the production library. Sustained refresh rates across different displays, PDF sizes and GPUs require separate benchmarking. Layout detection remains heuristic for unusual papers and SVG labels. Manual column calibration is available. Automatic progression requires extractable text.
