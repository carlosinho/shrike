# Shrike architecture

Developer documentation for the current implementation. The README covers usage, installation, and the feature roadmap; this file covers how the code works and why. Everything below describes what exists now — future ideas live only in the README's "Possible future features" section and are not repeated here.

## System design philosophy

Shrike is a single-purpose, single-file-per-invocation CLI. The guiding choices:

- **Lean on the OS for image work.** All decoding, scaling, and encoding go through Apple's ImageIO/CoreGraphics. Shrike contains no codec code and has exactly one third-party dependency (`swift-argument-parser`, CLI parsing only). This is why the release binary is self-contained and why formats behave the way macOS behaves.
- **Logic and CLI are separate targets.** `Sources/ShrikeCore` (library) holds every decision worth testing; `Sources/shrike` (executable) only parses arguments, calls `ImageResizer.run(_:)`, and formats output. The CLI target contains no image logic at all.
- **Pure functions where possible.** The two decisions most likely to have bugs — dimension math (`ImageResizer.targetSize`) and copy naming (`ImageResizer.copyURL`) — are pure static functions with no I/O, tested directly.
- **No state.** There is no persistence, config file, cache, database, or environment variable. Every invocation is fully described by its arguments. (Sections on persistence, state transitions, and auth are therefore intentionally absent.)

## Package layout

| Target | Kind | Contents |
|---|---|---|
| `ShrikeCore` | library | `ImageResizer.swift` — all types and logic |
| `shrike` | executable | `Shrike.swift` — ArgumentParser command, output/exit-code mapping |
| `shrike-tests` | executable | `main.swift` — test harness + all tests (see Testing) |

Public API of `ShrikeCore`: `ResizeRequest` (input), `ImageResizer.run(_:)` (the pipeline), `ResizeOutcome` (`.resized` / `.noResizeNeeded`), `ShrikeError`, plus the value types `PixelSize`, `ResizeDimension`, `ImageFormat`.

## Key invariants

These hold everywhere and the tests enforce them:

1. **Never upscale.** `targetSize` returns `nil` unless the requested pixel count is *strictly less* than the current size along the chosen dimension. Equal size is a no-op, not a re-encode.
2. **Aspect ratio is preserved** with `.rounded()` (half away from zero) on the derived dimension, clamped to a minimum of 1px (a 10000×10 image resized to 100 wide yields 100×1, not 100×0).
3. **Format in = format out**, decided by *content*, not extension: `CGImageSourceGetType` must be `public.jpeg` or `public.png`, and the file extension must agree (`jpg`/`jpeg`/`png`, case-insensitive). Anything else throws before any write happens.
4. **The original file is never truncated.** Every write goes to a temp file (`.shrike-<UUID>.tmp`) in the *destination's own directory* — same volume, so the swap (`FileManager.replaceItemAt`, or `moveItem` when the destination doesn't exist yet) is atomic. A crash, full disk, or encode failure leaves the original byte-identical.
5. **Output pixels are always upright** and the EXIF orientation flag is reset to 1 in every place it appears (top-level, TIFF dictionary). Writing upright pixels while keeping the old flag would make viewers rotate the image twice; this invariant is the reason `outputProperties` exists.
6. **Copy naming is deterministic**: `<stem>-<pixels><w|h>.<original ext, case preserved>`, always in the source's directory. Re-running the same command overwrites the same copy (the write path replaces an existing destination).
7. **`-c` always produces the named copy on success paths** — including the no-resize case, where the source bytes are copied verbatim — so scripts can rely on `photo-800w.jpg` existing after exit 0.

## Main data flow

One pipeline, in `ImageResizer.run(_:)` top to bottom:

1. **Existence check** (`FileManager`, rejects directories) → `ShrikeError.fileNotFound`.
2. **Open + sniff**: `CGImageSourceCreateWithURL` + `CGImageSourceGetType` → `notAnImage` if unreadable; `detectFormat` → `unsupportedFormat` (e.g. `public.heic`) or `extensionMismatch`.
3. **Read properties, not pixels**: stored width/height and the EXIF orientation come from `CGImageSourceCopyPropertiesAtIndex`. For orientations 5–8 the *displayed* size is the stored size swapped — all user-facing math uses the displayed size.
4. **Decide**: `targetSize` → `nil` means the no-op path (optionally copying the file verbatim for `-c`) and the function returns without ever decoding pixels. This makes "already small enough" cheap even on huge files.
5. **Decode upright**: `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailWithTransform` and `MaxPixelSize` set to the image's own larger dimension — i.e. a full-size decode with the EXIF rotation baked in. This deliberately trades memory for correctness: it avoids hand-writing the 8-case orientation affine transform, which is the classic source of rotated/mirrored-output bugs.
6. **Scale exactly**: draw into a `CGContext` of the computed target size, `interpolationQuality = .high`. The context uses the source's color space when its model is RGB (preserves Display P3 / ICC profiles), else falls back to sRGB. PNG gets premultiplied alpha; JPEG gets an alpha-free layout (JPEG cannot store alpha).
7. **Re-attach metadata**: the source property dictionary is carried over wholesale, with orientation reset (invariant 5), `Exif PixelX/YDimension` updated to the new size, and `kCGImageDestinationLossyCompressionQuality = 0.85` added for JPEG.
8. **Write atomically** (invariant 4) and return `.resized` with before/after sizes; the CLI layer turns that into the `4032×3024 → 800×600` line.

## CLI surface and exit codes

The "API" is the command line, defined entirely in `Sources/shrike/Shrike.swift`: two positional arguments (`path`, `pixels`), two flags (`--height`, `-c`/`--copy`), plus ArgumentParser's generated `--help`/`--version`.

Exit-code mapping lives in exactly two places:

- `validate()` throws `ValidationError` for `pixels <= 0` → ArgumentParser exits with **64** (`EX_USAGE`), same as any malformed invocation.
- `run()` catches `ShrikeError`, prints `shrike: <description>` to **stderr**, and throws `ExitCode(2)`. All success paths (including no-op) print to stdout and exit **0**.

Anything that changes these mappings is a breaking change for scripts.

## Performance decisions

- **Peak memory is ~2 decoded copies of the image** (upright full-size decode + target-size context): roughly `W×H×4` bytes each, e.g. ~145 MB for a 6016×6016 photo. Accepted for a one-shot CLI; the alternative (ImageIO downsampling during decode via a smaller `MaxPixelSize`) was rejected because it controls the *longest* edge only and can be off by a pixel on the requested dimension.
- **The no-op path never decodes pixels** (step 4 above) — checking a 100 MB PNG that's already small enough reads only its header.
- JPEG quality is a compile-time constant: `ImageResizer.jpegQuality = 0.85`.
- No parallelism anywhere; one file, one pass.

## Failure handling and edge cases

Every failure is a typed `ShrikeError` case with a one-line, user-readable `description`:

| Case | Trigger |
|---|---|
| `fileNotFound` | missing path, or path is a directory |
| `notAnImage` | ImageIO can't identify the file at all |
| `unsupportedFormat` | real image, wrong type (message includes the detected UTI, e.g. `public.heic`) |
| `extensionMismatch` | e.g. PNG bytes in a `.jpg` file (message names the actual format) |
| `decodeFailed` | properties/pixels unreadable, or the scale context failed |
| `writeFailed` | temp-file creation, encode finalize, or the final swap failed (reason included) |

Intentional edge-case behavior worth knowing before changing it:

- **Failed writes clean up after themselves**: the temp file is removed on both the finalize-failure and swap-failure paths.
- **Non-RGB sources are converted**: a grayscale JPEG comes out as RGB (sRGB fallback in step 6). Accepted — output is visually identical, slightly larger.
- **Bit depth is normalized to 8 bits/channel**: a 16-bit PNG is written back as 8-bit. Accepted for the shrinking use case.
- **An existing file at the copy destination is silently replaced** — that's what makes re-runs idempotent (invariant 6) — including a verbatim `removeItem` + `copyItem` on the no-resize `-c` path.
- **Orientation values 5–8 swap the reported dimensions** (step 3); tests cover orientation 6 down to pixel colors, not just sizes.

## Security considerations

- **Content sniffing over extension trust** (invariant 3) prevents encoding a file as something it isn't; malformed/hostile image parsing risk is delegated entirely to Apple's ImageIO, which is the same attack surface as Preview/Quick Look and receives OS security updates.
- **No network, no subprocesses, no shell interpolation.** Paths are used as `URL(fileURLWithPath:)` arguments only; symlinks resolve however the OS resolves them (no special handling — overwriting a symlinked image replaces the *link target's* content via the swap).
- **Privacy trade-off, deliberate:** EXIF metadata *including GPS* is preserved on resize. Right for "shrink my photo", wrong for "publish to the web" — a `--strip-metadata` flag is listed in the README as future work, not implemented.
- Temp filenames embed a UUID, so they're not guessable/collidable in shared directories.

## Scalability constraints

By design, not accident: one file per process, whole image in memory, no recursion into directories, no concurrency. The core is already shaped for a future batch mode (the CLI loop would call `ImageResizer.run` per file); what would *not* survive very large images (panoramas beyond a few hundred megapixels) is the full-size decode in step 5, which would need tiled or downsample-during-decode handling.

## Testing and maintenance notes

- **`swift run shrike-tests`** runs everything. The harness is hand-rolled (~50 lines: `expect`/`expectEqual`/`require` + a `test` runner with per-test temp directories) because the Xcode **Command Line Tools toolchain ships neither XCTest nor Swift Testing** — both come only with full Xcode. If this project ever standardizes on machines with Xcode, the target can be converted back to a real test framework; the assertions map 1:1.
- **Fixtures are generated, not checked in**: a blue image with a red top-left quadrant (rotation becomes visible in pixel samples) and an optional transparent left half (alpha survival). Fixture EXIF (orientation, `DateTimeOriginal`) is written through `CGImageDestination` properties.
- **What's covered**: dimension math, copy naming, in-place vs copy writes, the no-upscale rule (including byte-identical originals), orientation-6 round trip down to pixel colors, EXIF preservation + pixel-dimension update, PNG transparency, and the `fileNotFound` / `extensionMismatch` / non-image error paths.
- **What's not covered**: the `shrike` executable target itself (argument parsing, output text, exit codes were verified manually against the release binary — with `sips` checking sizes/formats/ICC profiles — but have no automated tests), `unsupportedFormat` (needs a HEIC fixture), and `writeFailed` (needs induced I/O failure).
- **CI** (`.github/workflows/ci.yml`) runs `swift build -c release` + `swift run shrike-tests` on `macos-latest` for pushes to `main` and PRs. GitHub's macOS runners include full Xcode, so CI would not catch an accidental XCTest import creeping back in — it builds fine there and breaks only on CLT-only machines.
- **Version string** lives in `CommandConfiguration(version:)` in `Sources/shrike/Shrike.swift` and must be bumped in lockstep with release tags (`v0.1.0` ↔ `"0.1.0"`). `Package.resolved` is committed to pin the argument-parser version.
- **Adding a format** touches three places in `ImageResizer.swift`: `ImageFormat` (case + `utTypeIdentifier` + `validExtensions` + `displayName`), `detectFormat`'s UTI switch, and — for formats with alpha or lossy encoding — the `alphaInfo`/quality decisions in `scale` and `outputProperties`.
