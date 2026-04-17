# img-cc — Native macOS Bulk Image Optimizer/Converter

**Status:** Approved · **Date:** 2026-04-17

## 1. Purpose

Native macOS app for bulk optimization and format conversion of images. User drops a batch of files, picks a target format and a quality percentage (0–100), chooses an output folder, and runs the job. While encoding happens in the background, an animated progress overlay is shown. On completion, a success summary appears and the output folder opens automatically.

## 2. Supported Formats

| Format | Input | Output | Implementation |
|---|---|---|---|
| JPG / JPEG | ✓ | ✓ | `ImageIO` |
| PNG | ✓ | ✓ | `ImageIO` |
| HEIC | ✓ | — | `ImageIO` (native since 10.13) |
| AVIF | ✓ | ✓ | `ImageIO` (encode requires macOS 14+) |
| WebP | ✓ | ✓ | Decode via `ImageIO`; encode via **libwebp** (SwiftPM) |
| SVG | ✓ | — | `NSImage` SVG support (macOS 14+); WKWebView snapshot fallback |

## 3. Tech Stack

- Swift 5.10 · SwiftUI · `@Observable`
- Deployment target: **macOS 14.0 (Sonoma)**
- Xcode project with SwiftPM for third-party deps
- Dependencies:
  - libwebp (via [SDWebImageWebPCoder](https://github.com/SDWebImage/libwebp-Xcode) or a direct libwebp SPM wrapper — pick smallest viable option during implementation)
- Tests: **Swift Testing** framework + small binary fixtures per format

## 4. Architecture

```
img-cc/
├── App/
│   └── ImgCCApp.swift              # @main, single Window scene
├── Models/
│   ├── ImageFile.swift             # URL, size, UTI, thumbnail cache ref
│   ├── OutputFormat.swift          # enum: jpeg, png, webp, avif
│   ├── ConversionSettings.swift    # quality, format, outputDirectory
│   └── ConversionResult.swift      # success/failure per file
├── ViewModels/
│   └── ConversionViewModel.swift   # @Observable state, public actions
├── Services/
│   ├── ImageConverter.swift        # actor; TaskGroup orchestration
│   ├── Decoders/
│   │   ├── ImageIODecoder.swift    # jpg/png/heic/avif/webp
│   │   └── SVGDecoder.swift        # NSImage + WKWebView fallback
│   ├── Encoders/
│   │   ├── JPEGEncoder.swift
│   │   ├── PNGEncoder.swift
│   │   ├── AVIFEncoder.swift
│   │   └── WebPEncoder.swift       # libwebp bridge
│   ├── FilenameResolver.swift      # collision-safe names
│   └── FolderOpener.swift          # NSWorkspace.open wrapper
└── Views/
    ├── ContentView.swift
    ├── DropZoneView.swift
    ├── FileListView.swift
    ├── FileRowView.swift
    ├── SettingsPanelView.swift
    ├── ProgressOverlayView.swift   # Canvas-based animated progress
    └── CompletionSheetView.swift
```

### 4.1 Data flow
1. User adds files → `ConversionViewModel.add(urls:)` validates UTI, builds `[ImageFile]`.
2. User sets `ConversionSettings` (quality, output format, output directory).
3. User clicks Convert → VM calls `ImageConverter.run(files:settings:)`.
4. Converter creates `TaskGroup`; concurrency = `ProcessInfo.processInfo.activeProcessorCount`.
5. Per file: `Decoder.decode(url:) -> CGImage` → `Encoder.encode(image:quality:to:)`.
6. VM updates `progress: Double` and `currentFilename: String?` atomically (actor-isolated then hopped to `@MainActor`).
7. On finish, VM emits `CompletionSummary` and triggers `NSWorkspace.shared.open(outputDirectory)`.

## 5. Quality Semantics (0–100)

- Slider value `q ∈ [0, 100]`; internally mapped to `CGFloat(q) / 100.0`.
- Applied to `kCGImageDestinationLossyCompressionQuality` for JPEG, AVIF.
- Passed to libwebp `WebPConfig.quality` for WebP.
- PNG is lossless → slider **has no effect** (UI shows tooltip "PNG is lossless; quality setting is ignored").

## 6. UI Specification

- Single non-document window, 900×640 minimum size.
- Layout top-to-bottom:
  1. **DropZoneView** — dashed rounded rectangle, accepts `NSItemProvider` drops; shows "Drop images here or click to browse" with SF Symbol.
  2. **FileListView** — scrollable list of `FileRowView` (64px thumbnail, filename, size, format pill, remove button). Empty state: hidden.
  3. **SettingsPanelView** — horizontal:
     - Quality slider (0–100, default **80**) with live value label.
     - Format segmented picker: JPG · PNG · WebP · AVIF (default **WebP**).
     - Output folder: read-only text field + "Choose…" button (uses `NSOpenPanel`). Default: `~/Pictures/img-cc`.
  4. **Action bar** — "Clear" (secondary) and "Convert N images" (primary). Primary disabled until files + output dir present.
- **ProgressOverlayView**: full-window overlay while converting. Circular progress ring (SwiftUI `Canvas`), pulsating gradient, animated checkmark sweep around the ring, filename + counter below. "Cancel" button.
- **CompletionSheetView**: sheet with success icon, "Converted X of Y images", optional "Show errors" disclosure list, "Done" button. Output folder auto-opens on sheet appearance.

## 7. Concurrency & Cancellation

- `ImageConverter` is an `actor`.
- `TaskGroup` with bounded concurrency (semaphore-style: launch up to `N`, await any, launch next).
- Progress: `AsyncStream<ConversionEvent>` emitted to VM for UI updates.
- User "Cancel" → calls `task.cancel()`; checks `Task.isCancelled` in inner loop; partial outputs stay on disk, VM reports "X of Y completed before cancel".

## 8. Filename Collision Strategy

- Output path: `{outputDir}/{basename}.{newExt}`.
- If exists: append `" (1)"`, `(2)`, … until unique.
- No overwrite by default; no UI toggle in MVP.
- Encapsulated in `FilenameResolver`.

## 9. Error Handling

- Per-file errors are captured into `ConversionResult.failure(file, error)`.
- Loop continues for remaining files.
- Summary shows `"N succeeded, M failed"`; disclosure lists each failed file with localized error message.
- Decoder/encoder errors typed via `enum ConversionError: Error`.

## 10. Sandbox & Signing

- **App Sandbox disabled** for MVP (direct FS access to chosen output folder; simpler, no security-scoped bookmarks).
- Code signing: ad-hoc (`codesign -s -`) — sufficient for local run; distribution is out of scope.

## 11. Testing Strategy

- `ImageConverterTests` — round-trip per format using tiny fixture files in `Tests/Fixtures/`.
- `FilenameResolverTests` — collision numbering.
- `ConversionViewModelTests` — state transitions: idle → running → completed/cancelled.
- `SVGDecoderTests` — rasterization of a known small SVG produces expected size.
- No UI tests in MVP.

## 12. Out of Scope (MVP)

- Resizing / max-dimension constraints.
- EXIF/metadata preservation toggles (default: strip unless needed by encoder).
- Batch presets / history.
- SVG output, HEIC output.
- Dark mode custom theming (rely on system).
- Localization beyond English UI strings (Russian can be added post-MVP).
- App Store distribution, sandboxing, notarization.

## 13. Non-Goals / YAGNI

- No Core Data / persistence of jobs.
- No multi-window or document model.
- No background daemon; job lives with window.
