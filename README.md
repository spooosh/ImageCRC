# img-cc

Native macOS app for bulk image optimization and format conversion.

- **Input**: JPG, JPEG, PNG, SVG, WebP, AVIF, HEIC
- **Output**: JPG, PNG, WebP, AVIF
- Quality control (0–100%), output folder picker, animated progress overlay, auto-opens the output folder when done.

## Build & run

```bash
./Scripts/make-app.sh
open ./img-cc.app
```

The script does `swift build -c release`, assembles a `.app` bundle with an ad-hoc signature, and leaves it at `./img-cc.app`.

## Requirements

- macOS 14 Sonoma or newer (AVIF encoding requires 14+)
- Xcode command-line Swift toolchain (`swift --version` → 5.10+)

## Stack

- Swift + SwiftUI (single-window, `@Observable` state)
- ImageIO for JPG/PNG/HEIC/AVIF; libwebp (via `SDWebImage/libwebp-Xcode` SwiftPM package) for WebP encoding; `NSImage` for SVG rasterization
- `TaskGroup`-based parallel conversion (bounded by CPU count), cancellable job

## Design doc

See `docs/superpowers/specs/2026-04-17-img-cc-design.md`.
