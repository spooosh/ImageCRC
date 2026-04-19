# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & run

- `./Scripts/make-app.sh` — `swift build -c release`, assembles `./img-cc.app` (ad-hoc signed), bundles `pngquant` from `brew --prefix pngquant` into `Contents/Resources/bin/`. This is the canonical build. Set `CONFIG=debug` to build debug.
- `swift build` / `swift build -c release` — compile only; no `.app` wrapper, and `pngquant` isn't bundled so PNG lossy encoding will fall back to system paths (`/opt/homebrew/bin/pngquant`, `/usr/local/bin/pngquant`). `brew install pngquant` is required for PNG `q<100`.
- `open ./img-cc.app` — launch the built app.
- `xcodegen generate` — regenerate `img-cc.xcodeproj` from `project.yml` (only needed if working in Xcode).
- `swift test` — Swift Testing framework. `Tests/Fixtures/` is wired into the Package layout; tests themselves are not landed yet.

Deployment target is macOS 14 (AVIF encode requires it). Swift 5.10.

## Target config lives in two places

`Package.swift` (SwiftPM CLI build → `make-app.sh`) and `project.yml` (XcodeGen → Xcode project) both describe the executable target independently. When adding a new top-level source directory, update **both**:
- `Package.swift` → `sources: [...]` array.
- `project.yml` → `targets.img-cc.sources` list.
The current source roots are `App`, `Models`, `ViewModels`, `Services`, `Views` (+ `Resources` in Xcode only).

## Architecture

Classic MVVM-ish split, single-window SwiftUI app.

- **`App/ImgCCApp.swift`** — `@main`, single `Window` scene, owns the `ConversionViewModel`.
- **`ViewModels/ConversionViewModel.swift`** — `@MainActor @Observable`. The only bridge between UI and the converter. `start()` snapshots files + settings and drives an `AsyncStream<ConversionEvent>` from `ImageConverter.convert(...)`, applying events to `phase` / `progress` / `summary`. `cancel()` cancels the enclosing `Task`, which propagates via `continuation.onTermination` into the converter's detached job.
- **`Services/ImageConverter.swift`** — orchestrator. Not an actor; it's a pure `enum` with static funcs. Spawns a `Task.detached(priority: .userInitiated)` that runs a `TaskGroup` bounded by `ProcessInfo.processInfo.activeProcessorCount` (launch-N-then-feed-as-one-finishes pattern). On cancel, drains remaining input as `.cancelled` results so the UI counter stays monotonic. Emits events through an `AsyncStream` continuation.
- **`Services/Decoders/`** — `ImageDecoder` dispatches by `InputFormat`: SVG → `SVGDecoder` (NSImage rasterization), everything else → `ImageIODecoder`.
- **`Services/Encoders/`** — `ImageEncoder` dispatches by `OutputFormat`:
  - JPEG / AVIF → ImageIO (`kCGImageDestinationLossyCompressionQuality`).
  - WebP → `libwebp` (SwiftPM dep via `SDWebImage/libwebp-Xcode`), which needs an `RGBABuffer` staged from the `CGImage`.
  - PNG → ImageIO lossless at `q==100`; at `q<100` the lossless bytes are piped through `pngquant` via `PNGQuantizer` (stdin→stdout subprocess with `--quality 0-N --speed 4 --strip`). Binary lookup order: `Bundle.main/Contents/Resources/bin/pngquant` → `/opt/homebrew/bin` → `/usr/local/bin` → `/usr/bin`.
- **`Services/ImageResizer.swift`** — no-op when `ResizeSettings.isActive == false`. Supports `.fit` / `.fill`; never upscales unless `enlarge == true`; `.fill` + both dimensions performs a centered crop via negative draw offsets in a smaller `CGContext`.
- **`Services/FilenameResolver.swift`** — `actor`. Reserves resolved names to avoid collisions both on disk and across in-flight TaskGroup writes. Calls from the group must `await` it.
- **`Models/`** — value types, all `Sendable`. `ConversionSettings.default` seeds output dir to `~/Pictures/img-cc`, format to JPEG, quality 80. `ResizeSettings.isActive` gates the whole resize path.

### Event contract

`ConversionEvent` is the only thing that crosses the `@MainActor` boundary:
- `.willStart(file:)` — about to decode; used to update `currentFilename`.
- `.didComplete(result:completed:total:)` — per-file outcome with running counters.
- `.didFinish(summary:)` — terminal; VM transitions to `.completed` and surfaces the `CompletionSheetView`.

Cancellation is always cooperative: the converter checks `Task.isCancelled` between decode → resize → encode → write, and failed writes return `.failure` (not `.cancelled`) so the summary distinguishes them.

## Quality slider semantics

Slider is `Int 0...100`; `ConversionSettings.normalizedQuality` exposes `Double ∈ [0,1]`. JPEG/AVIF/WebP use it directly. PNG is lossless at `q==100`; below that it's quantized to indexed color by `pngquant` (≤256 colors, Floyd-Steinberg).

## Sandbox / signing

App Sandbox is **off** for MVP (direct FS access to chosen output folder, no security-scoped bookmarks). Signing is ad-hoc (`codesign -s -`). `pngquant` is GPL v3, so any distributed `.app` is a combined GPL v3 work — no App Store distribution.

## Specs

- `docs/superpowers/specs/2026-04-17-img-cc-design.md` — original design, quality semantics, concurrency model.
- `docs/superpowers/specs/2026-04-18-resize-design.md` — resize feature design.
