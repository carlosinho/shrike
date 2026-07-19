<h1 align="center">Shrike</h1>

<table>
  <tr>
    <td width="240" align="center" valign="top">
      <img src="docs/Shrike.png" alt="Shrike logo" width="180" />
    </td>
    <td valign="middle">
      <strong>Shrike</strong> is a small macOS command-line tool that shrinks JPEG and PNG images to a target width or height, preserving the aspect ratio and the original format.
      <br /><br />
      A shrike is also a small songbird known for storing food on thorns and branches, a distinctive behavior that helps it save meals for later. Just don't ask me about what that <em>food</em> actually is. 😂
    </td>
  </tr>
</table>

<p align="center">
  <img src="docs/shrike-scrn.png" alt="Shrike CLI screenshot" width="900" />
</p>

[![CI](https://github.com/carlosinho/shrike/actions/workflows/ci.yml/badge.svg)](https://github.com/carlosinho/shrike/actions/workflows/ci.yml)

## Usage

```
shrike <path> <pixels> [--height] [-c | --copy]
```

```sh
shrike photo.jpg 800           # resize to 800px wide, overwrite in place
shrike photo.jpg 600 --height  # resize to 600px tall, overwrite in place
shrike photo.jpg 800 -c        # write photo-800w.jpg, leave the original alone
shrike photo.png 600 --height -c   # writes photo-600h.png
shrike --help
```

## Behavior

- **Shrink only.** If the image already fits within the requested size, nothing is resized (with `-c`, an unchanged copy is still written so the expected output file exists). Exit code is 0 either way.
- **Format is preserved.** JPEG stays JPEG, PNG stays PNG. Anything else (HEIC, WebP, …) is rejected, as is a file whose extension doesn't match its actual content.
- **Safe overwrites.** In-place mode writes the full result to a temporary file in the same directory, then swaps it in atomically — a crash or a full disk never corrupts the original.
- **EXIF orientation is handled.** Rotated camera photos come out upright; the orientation flag is reset so viewers don't rotate them a second time. Other metadata (EXIF dates, GPS, color profile) is preserved.
- **PNG transparency is preserved.** JPEGs are re-encoded at quality 0.85 — note that repeatedly resizing the same JPEG in place loses a little quality each time, which is inherent to the format.
- Copy names are deterministic (`photo.jpg` → `photo-800w.jpg` / `photo-600h.jpg`), so re-running the same command overwrites the same copy instead of piling up new files.

### Exit codes

| Code | Meaning |
|------|---------|
| 0    | Success, including the "already small enough" no-op |
| 2    | File or image error (missing file, unsupported/mismatched format, decode/write failure) |
| 64   | Usage error (bad arguments; standard `EX_USAGE` from swift-argument-parser) |

## Building and installing

Requires macOS 13+ and the Xcode Command Line Tools (Swift 5.9+). The only dependency is [swift-argument-parser](https://github.com/apple/swift-argument-parser), fetched automatically on the first build; image work uses the system ImageIO/CoreGraphics frameworks.

### 1. Build

Clone the repository and run the build from the project root — the directory containing `Package.swift`:

```sh
git clone https://github.com/carlosinho/shrike.git
cd shrike
swift build -c release
```

This produces a single self-contained binary at `.build/release/shrike`. It has no runtime dependencies, so it can be copied anywhere and run from there.

### 2. Install so it works from any directory

Your shell finds commands by searching the directories listed in `$PATH`, so to run `shrike` from anywhere, copy the binary into one of those directories. `/usr/local/bin` is on the default PATH of every macOS install:

```sh
sudo cp .build/release/shrike /usr/local/bin/
```

No-sudo alternative: if a user-writable directory such as `~/.local/bin` or `~/bin` is already on your PATH (check with `echo $PATH`), copy the binary there instead.

### 3. Verify

Open any directory and run:

```sh
which shrike     # should print the directory you copied the binary into
shrike --version
shrike ~/Desktop/some-photo.jpg 800 -c
```

Once installed, the project directory is no longer needed at runtime — the binary is standalone. It only matters again when you want to change the code: rebuild and re-copy (steps 1–2) to update the installed version.

### Updating

To update to the latest version, pull the newest code in the cloned project directory, rebuild, and re-copy the binary:

```sh
cd shrike        # wherever you cloned the repository
git pull
swift build -c release
sudo cp .build/release/shrike /usr/local/bin/
```

(If you installed to a user-writable directory instead, copy there and skip `sudo`.) Check the result with `shrike --version`. If you deleted the project directory after installing, just clone and install again per steps 1–2.

### Running without installing

From the project root you can always run the tool directly:

```sh
.build/release/shrike photo.jpg 800
# or, slightly slower (checks whether a rebuild is needed first):
swift run shrike photo.jpg 800
```

## GUI app

An optional drag-and-drop front-end for the same engine. Build it with:

```sh
scripts/make-app.sh
```

This produces `dist/Shrike.app` (ad-hoc signed, for local use) — launch it from there or copy it to `/Applications`. The window shows four preset tiles (800 / 1000 / 1200 / 1800 px by default; the gear button lets you set your own four sizes and switch to a darker theme, both remembered between launches): drop a JPEG or PNG on a tile to shrink it to that size, with a Width/Height toggle and a Copy mode checkbox below. The GUI links the same `ShrikeCore` engine as the CLI — it does not call the `shrike` binary — so everything behaves identically: same shrink-only rule, formats, atomic writes, and copy naming, with one deliberate difference: **Copy mode is on by default** in the GUI, so an accidental drop writes a `photo-800w.jpg` next to the original instead of overwriting it. Uncheck it to resize in place.

The GUI is versioned independently of the CLI — it's a separate product with its own number, visible in the app's About panel (Shrike menu → About Shrike).

## Tests

```sh
swift run shrike-tests
```

The test target is a plain executable with a minimal built-in harness, because the Command Line Tools toolchain ships neither XCTest nor Swift Testing (they come with full Xcode). It covers the dimension math, in-place and copy resizing, the no-upscale rule, EXIF orientation and metadata handling, PNG transparency, and the error paths.

## Known limitations (proof of concept)

- One file per invocation — no globs or directories.
- JPEG and PNG only.
- JPEG quality is fixed at 0.85.
- Requires the file extension (`.jpg`/`.jpeg`/`.png`, any case) to match the actual image content.

## Roadmap

Planned features and open design questions live in [ROADMAP.md](ROADMAP.md).
