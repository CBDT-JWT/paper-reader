# App icon

`AppIcon.png` is the project-owned source bitmap generated with the built-in imagegen tool; `AppIcon.icns` contains the standard macOS 16–1024 pixel representations. Run `scripts/build-icon.sh` to rebuild it. The app packager copies the ICNS into the main bundle and sets CFBundleIconFile. Resizing uses macOS sips/iconutil and preserves alpha.

Design prompt: a restrained native macOS icon for a research PDF and Markdown workspace, with two overlapping warm-white paper pages, a folded cobalt reading tab, charcoal strokes and one small amber highlight. No lettering, AI sparkle, brain or magnifier. Centered rounded-square tile with transparent surroundings. A second imagegen pass retained the composition and requested a cleaner outer alpha silhouette. No third-party logos or source art were used.

The exact generation and edit prompts are recorded in [app-icon-prompts.txt](app-icon-prompts.txt).
