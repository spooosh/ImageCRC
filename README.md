# ImageCRC

Native macOS app for bulk image optimization and format conversion.

- **Input**: JPG, JPEG, PNG, SVG, WebP, AVIF, HEIC
- **Output**: JPG, PNG, WebP, AVIF
- Quality control (0–100%), output folder picker, animated progress overlay, auto-opens the output folder when done.

## Requirements

- macOS 14 Sonoma or newer (AVIF encoding requires 14+).
- Xcode 15.3+ **or** Command Line Tools for Xcode 15.3+ — provides the Swift 5.10 toolchain. Verify with `swift --version`. If missing: `xcode-select --install`.
- [Homebrew](https://brew.sh) — used to install `pngquant` below.
- **pngquant** — `brew install pngquant`. Required for PNG output at quality < 100 (the lossless ImageIO bytes are piped through `pngquant` for indexed-color quantization). `Scripts/make-app.sh` looks it up via `brew --prefix pngquant` and bundles the binary into `Contents/Resources/bin/` of the `.app`. Without it, `swift build` still succeeds, but `make-app.sh` prints a warning and PNG conversion below 100% quality will fail at runtime.

SwiftPM dependencies (`libwebp` via `SDWebImage/libwebp-Xcode`) resolve automatically on the first `swift build` — no manual install needed.

### Optional

- **XcodeGen** — `brew install xcodegen`. Only needed if you want to regenerate `ImageCRC.xcodeproj` from `project.yml` (`xcodegen generate`). The SwiftPM build (`make-app.sh`) does not use Xcode.

All other tools used by the build/packaging scripts (`codesign`, `sips`, `iconutil`, `hdiutil`, `/usr/libexec/PlistBuddy`) ship with macOS / the Xcode CLI tools.

## Build & run

```bash
./Scripts/make-app.sh
open ./ImageCRC.app
```

The script does `swift build -c release`, assembles a `.app` bundle with an ad-hoc signature, and leaves it at `./ImageCRC.app`.

## Stack

- Swift + SwiftUI (single-window, `@Observable` state)
- ImageIO for JPG/PNG/HEIC/AVIF; libwebp (via `SDWebImage/libwebp-Xcode` SwiftPM package) for WebP encoding; `NSImage` for SVG rasterization
- `TaskGroup`-based parallel conversion (bounded by CPU count), cancellable job

## Design doc

See `docs/superpowers/specs/2026-04-17-img-cc-design.md`.
