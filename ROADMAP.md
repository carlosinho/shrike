# Development

## Status

> v0.1.0 released — proof of concept complete. Single-file JPEG/PNG shrinking works end to end and is tagged.

## Roadmap

### v0.1.0 — Proof of concept

- [x] Resize to target width or height (`<path> <pixels> [--height]`) — dimension math is a pure static function (`ImageResizer.targetSize`), aspect ratio preserved with `.rounded()`, derived dimension clamped to min 1px
- [x] Shrink-only rule — `targetSize` returns `nil` unless strictly smaller; equal size is a no-op, never a re-encode, and the no-op path never decodes pixels (cheap even on huge files)
- [x] JPEG and PNG support with format preservation — format decided by content sniff (`CGImageSourceGetType`), and the extension must agree; anything else (HEIC, WebP, mismatched extension) is rejected before any write
- [x] In-place mode with atomic overwrite — full result written to a `.shrike-<UUID>.tmp` in the destination's own directory, then swapped via `FileManager.replaceItemAt`; crash/full disk never corrupts the original; temp file cleaned up on failure
- [x] Copy mode (`-c`/`--copy`) with deterministic naming — `<stem>-<pixels><w|h>.<ext>` in the source's directory; re-runs overwrite the same copy; on the no-resize path an unchanged copy is still written so scripts can rely on the output file existing
- [x] EXIF orientation handling — full-size decode with `kCGImageSourceCreateThumbnailWithTransform` bakes rotation in (deliberately trades memory for correctness vs. hand-writing the 8-case transform); orientation flag reset to 1 everywhere it appears so viewers don't double-rotate
- [x] Metadata preservation — source property dictionary carried over wholesale (EXIF dates, GPS, color profile), with `Exif PixelX/YDimension` updated to the new size
- [x] PNG transparency preserved (premultiplied alpha); JPEG re-encoded at fixed quality 0.85 (compile-time constant `ImageResizer.jpegQuality`)
- [x] Color profile preservation — scale context uses the source color space when its model is RGB (Display P3 / ICC survive), sRGB fallback otherwise
- [x] Typed errors + stable exit codes — every failure is a `ShrikeError` case printed to stderr; 0 success (incl. no-op), 2 file/image error, 64 usage error (`EX_USAGE`)
- [x] Core/CLI split — `ShrikeCore` library holds all logic; `shrike` executable only parses args (swift-argument-parser) and maps output/exit codes
- [x] Test suite (`swift run shrike-tests`) — hand-rolled harness (CLT toolchain ships no XCTest/Swift Testing); covers dimension math, copy naming, in-place vs copy, no-upscale (byte-identical originals), orientation-6 down to pixel colors, EXIF preservation, PNG transparency, error paths; fixtures generated at runtime, not checked in
- [x] CI — GitHub Actions on `macos-latest`: `swift build -c release` + `swift run shrike-tests` on pushes to `main` and PRs

### v0.2.0

- [x] GUI helper app/module — SwiftUI front-end (`shrike-gui` target) per the `shrike-ui.png` template, blue palette included: 2×2 grid of drop tiles (defaults 800/1000/1200/1800 px, user-configurable via the gear button and remembered in `UserDefaults`, as is a dark-mode switch — the GUI's only state), Width/Height toggle, Copy mode checkbox; `scripts/make-app.sh` wraps the binary in an ad-hoc-signed `dist/Shrike.app` (gitignored). Decisions made: links `ShrikeCore` directly (no shelling out to the CLI); SwiftPM target + bundle script (not an Xcode project) to keep the CLT-only toolchain; Copy mode defaults to ON in the GUI (safe drag-and-drop, diverges from CLI); GUI versioned independently of the CLI (`GUIVersion.current` in `Sources/shrike-gui/Version.swift` → Info.plist via the script). See "GUI front-end" in ARCHITECTURE.md.

### Backlog / Future

- [ ] `-s` - status - simply displays the current width and height of the image without doing anything to it
- [ ] Fit-within-box mode — a single `--max 1200` constraining the longest edge - whether it's width or height
- [ ] Batch mode — accept multiple paths or a directory (`shrike *.jpg 800 -c`), per-file summary, nonzero exit if any file fails. Core is already shaped for it: the CLI loop would call `ImageResizer.run` per file.
- [ ] `--quality <0–1>` — control JPEG re-encode quality instead of the fixed 0.85
- [ ] HEIC input — ImageIO already decodes HEIC natively; blocked on the output-format decision (see Decisions Pending)
- [ ] `-o <path>` — explicit output path as an alternative to the automatic `-800w` copy naming
- [ ] `--strip-meta` — drop EXIF/GPS instead of preserving it, for images headed to the public web (also flagged as a privacy trade-off in ARCHITECTURE.md)
- [ ] Shell completions — swift-argument-parser can generate them (`shrike --generate-completion-script zsh`)
- [ ] WebP output — needs a third-party encoder; ImageIO doesn't write WebP

## Known Issues / Tech Debt

- **Untested CLI target** — argument parsing, output text, and exit codes were only verified manually against the release binary (with `sips`); no automated tests for the `shrike` executable itself.
- **Untested GUI target** — drop handling and layout of `shrike-gui` are verified manually only (same precedent as the CLI target); all resize decisions live in the tested core.
- **Test coverage gaps** — `unsupportedFormat` (needs a HEIC fixture) and `writeFailed` (needs induced I/O failure) are not covered.
- **CI blind spot** — GitHub's macOS runners include full Xcode, so CI would not catch an accidental XCTest import creeping back in; it builds fine there and breaks only on CLT-only machines.
- **Hand-rolled test harness** — intentional, because the Command Line Tools toolchain ships neither XCTest nor Swift Testing. If the project ever standardizes on machines with full Xcode, convert back to a real framework; assertions map 1:1.
- **Peak memory ≈ 2 decoded copies** (~`W×H×4` bytes each, e.g. ~145 MB for 6016×6016) — accepted for a one-shot CLI. The full-size decode would not survive very large panoramas (hundreds of megapixels); would need tiled or downsample-during-decode handling.
- **Repeated in-place JPEG resizing loses quality each time** — inherent to the format, documented, not fixable.
- **Non-RGB sources converted to RGB** (grayscale JPEG comes out RGB via sRGB fallback) — accepted; visually identical, slightly larger.
- **Bit depth normalized to 8 bits/channel** (16-bit PNG written back as 8-bit) — accepted for the shrinking use case.
- **EXIF metadata including GPS is preserved** — deliberate privacy trade-off; right for "shrink my photo", wrong for publishing to the web. `--strip-metadata` (backlog) is the fix.
- **Manual version bumps** — both versions are bumped by hand, but each product now has a single source of truth (see "Testing and maintenance notes" in ARCHITECTURE.md): the CLI's in `CommandConfiguration(version:)` (`Sources/shrike/Shrike.swift`, lockstep with `v*` tags), the GUI's in `GUIVersion.current` (`Sources/shrike-gui/Version.swift`, propagated to the app bundle's Info.plist by `scripts/make-app.sh`). The two are independent and drift apart by design.
- **One file per invocation, no globs/directories** — by design until batch mode lands.
- **Requires extension to match content** — `.jpg`/`.jpeg`/`.png` only, any case; a correct image with the wrong extension is rejected.

## Decisions Pending

- **HEIC input: what format is the output?** ImageIO can decode HEIC today; the open design question is whether the result stays HEIC or converts to JPEG.
- **WebP output: which third-party encoder?** ImageIO doesn't write WebP, so adding it means picking and vendoring an encoder dependency.
