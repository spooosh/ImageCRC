# Same-as-origin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `Origin` option to the Output Format picker that keeps each file in its input format — raster inputs re-encode (including a new HEIC path), SVG is copied as-is.

**Architecture:** Split the user-facing `OutputFormat` from an internal `EncoderFormat` via a new `OutputPlanner`. Planner returns a per-file `FileOutputPlan` (`.encode(EncoderFormat)` or `.copy`). `ImageConverter.processOne` branches on that plan; the copy branch uses `FileManager.copyItem` and reports input bytes as output bytes.

**Tech Stack:** Swift 5.10 · SwiftUI · ImageIO (HEIC via `public.heic` UTType) · existing libwebp / pngquant paths untouched.

**Commits:** User's preference is to commit locally and not have the workflow auto-commit. Each task ends with a `swift build -c release` checkpoint instead of a `git commit` step. The user will commit on their own cadence.

**Spec:** `docs/superpowers/specs/2026-04-18-same-as-origin-design.md`

---

## File Structure

**New files:**
- `Services/OutputPlanner.swift` — `EncoderFormat`, `FileOutputPlan`, `OutputPlanner.plan(for:selected:)`
- `Services/Encoders/HEICEncoder.swift` — ImageIO HEIC encoder, mirrors `AVIFEncoder`

**Modified files:**
- `Models/ConversionError.swift` — `encodeFailed(format:)` changes from `OutputFormat` to `EncoderFormat`
- `Services/Encoders/JPEGEncoder.swift` — call-site update
- `Services/Encoders/PNGEncoder.swift` — call-site update
- `Services/Encoders/PNGQuantizer.swift` — call-site update
- `Services/Encoders/WebPEncoder.swift` — call-site update
- `Services/Encoders/AVIFEncoder.swift` — call-site update
- `Services/Encoders/RGBABuffer.swift` — call-site update
- `Services/Encoders/ImageEncoder.swift` — dispatch switches to `EncoderFormat`, adds `.heic` arm
- `Services/ImageConverter.swift` — `processOne` branches on `OutputPlanner.plan(...)`
- `Models/OutputFormat.swift` — new `.sameAsOrigin` case
- `Views/SettingsPanelView.swift` — caption under the format picker when `.sameAsOrigin` is selected

`Package.swift` and `project.yml` are **not** modified — no new source directories.

---

## Task 1: Introduce `EncoderFormat`, `FileOutputPlan`, `OutputPlanner`

**Files:**
- Create: `Services/OutputPlanner.swift`

- [ ] **Step 1: Create the planner file**

Create `Services/OutputPlanner.swift` with:

```swift
import Foundation

/// What an encoder can actually produce. Distinct from the user-facing
/// `OutputFormat` because `HEIC` is only reachable via the `.sameAsOrigin`
/// path — it is never shown as a picker option — and because `.sameAsOrigin`
/// itself is a routing choice, not an encoder target.
enum EncoderFormat: String, Hashable, Sendable {
    case jpeg
    case png
    case webp
    case avif
    case heic

    var displayName: String {
        switch self {
        case .jpeg: return "JPG"
        case .png:  return "PNG"
        case .webp: return "WebP"
        case .avif: return "AVIF"
        case .heic: return "HEIC"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png:  return "png"
        case .webp: return "webp"
        case .avif: return "avif"
        case .heic: return "heic"
        }
    }
}

/// Per-file execution plan: either we re-encode to a specific encoder target,
/// or we copy the source file verbatim (SVG on the `.sameAsOrigin` path).
enum FileOutputPlan: Sendable {
    case encode(EncoderFormat)
    case copy
}

enum OutputPlanner {
    /// Resolve a plan for one file. The `.sameAsOrigin` branch is added in a later
    /// task together with the new `OutputFormat` case.
    static func plan(for input: InputFormat, selected: OutputFormat) -> FileOutputPlan {
        switch selected {
        case .jpeg: return .encode(.jpeg)
        case .png:  return .encode(.png)
        case .webp: return .encode(.webp)
        case .avif: return .encode(.avif)
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build -c release`
Expected: clean build (no warnings about non-exhaustive switches; `OutputFormat` still has only 4 cases).

---

## Task 2: Migrate `ConversionError.encodeFailed` from `OutputFormat` to `EncoderFormat`

**Files:**
- Modify: `Models/ConversionError.swift`
- Modify: `Services/Encoders/JPEGEncoder.swift`
- Modify: `Services/Encoders/PNGEncoder.swift`
- Modify: `Services/Encoders/PNGQuantizer.swift`
- Modify: `Services/Encoders/WebPEncoder.swift`
- Modify: `Services/Encoders/AVIFEncoder.swift`
- Modify: `Services/Encoders/RGBABuffer.swift`

- [ ] **Step 1: Update `ConversionError`**

In `Models/ConversionError.swift`, change the `encodeFailed` associated type from `OutputFormat` to `EncoderFormat`. The body of `errorDescription` is unchanged because `EncoderFormat.displayName` mirrors `OutputFormat.displayName`.

Replace:

```swift
case encodeFailed(format: OutputFormat, underlying: String?)
```

with:

```swift
case encodeFailed(format: EncoderFormat, underlying: String?)
```

No other edits in this file.

- [ ] **Step 2: Update `JPEGEncoder.swift` call sites (2)**

Both `.jpeg` references stay — they now refer to `EncoderFormat.jpeg` because Swift infers the contextual type from the `encodeFailed` parameter. Nothing to change in `JPEGEncoder.swift` textually, but re-open the file and confirm both lines still compile as-is:

```swift
throw ConversionError.encodeFailed(format: .jpeg, underlying: "Destination creation failed")
// …
throw ConversionError.encodeFailed(format: .jpeg, underlying: "Finalize failed")
```

If the build complains, the call sites need explicit `EncoderFormat.jpeg`. Don't change them until we see a build error in Step 8 — contextual lookup should resolve them.

- [ ] **Step 3: Review `PNGEncoder.swift`**

Same as Step 2 for `PNGEncoder.swift`. Both `.png` references resolve via context. No textual change expected.

- [ ] **Step 4: Review `PNGQuantizer.swift`**

Same for all 3 `.png` references in `PNGQuantizer.swift` (lines 54, 64, 104 in the current file). No textual change expected.

- [ ] **Step 5: Review `WebPEncoder.swift`**

Same for the single `.webp` reference. No textual change expected.

- [ ] **Step 6: Review `AVIFEncoder.swift`**

Same for both `.avif` references. No textual change expected.

- [ ] **Step 7: Review `RGBABuffer.swift`**

Same for the single `.webp` reference on line 31. No textual change expected.

- [ ] **Step 8: Build**

Run: `swift build -c release`
Expected: clean build. If any call site errors with "cannot infer contextual base", change the offending site to fully-qualified `EncoderFormat.jpeg` / `.png` / `.webp` / `.avif` and rebuild.

---

## Task 3: Add `HEICEncoder`

**Files:**
- Create: `Services/Encoders/HEICEncoder.swift`

- [ ] **Step 1: Create the encoder**

Create `Services/Encoders/HEICEncoder.swift` with:

```swift
import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum HEICEncoder {
    /// HEIC encoding via ImageIO. Supported since macOS 10.13; our deployment
    /// target is 14 so no availability gating is required.
    static func encode(image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        let heicType = UTType("public.heic") ?? UTType.image
        guard let dest = CGImageDestinationCreateWithData(
            data as CFMutableData,
            heicType.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.encodeFailed(format: .heic, underlying: "Destination creation failed")
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: max(0.0, min(1.0, quality))
        ]
        CGImageDestinationAddImage(dest, image, options as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw ConversionError.encodeFailed(format: .heic, underlying: "Finalize failed")
        }
        return data as Data
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build -c release`
Expected: clean build. The new encoder is not yet dispatched to by anyone.

---

## Task 4: Switch `ImageEncoder` to `EncoderFormat`, wire HEIC, refactor `ImageConverter.processOne` to use the planner

**Files:**
- Modify: `Services/Encoders/ImageEncoder.swift`
- Modify: `Services/ImageConverter.swift`

- [ ] **Step 1: Update `ImageEncoder.swift`**

Replace the whole body of `Services/Encoders/ImageEncoder.swift` with:

```swift
import Foundation
import CoreGraphics

enum ImageEncoder {
    static func encode(image: CGImage, to format: EncoderFormat, quality: Double) async throws -> Data {
        switch format {
        case .jpeg: return try JPEGEncoder.encode(image: image, quality: quality)
        case .png:  return try await encodePNG(image: image, quality: quality)
        case .avif: return try AVIFEncoder.encode(image: image, quality: quality)
        case .webp: return try WebPEncoder.encode(image: image, quality: quality)
        case .heic: return try HEICEncoder.encode(image: image, quality: quality)
        }
    }

    /// PNG path: always produces a valid ImageIO PNG first, then — if the slider
    /// is below 100 — runs it through pngquant for indexed-color compression.
    private static func encodePNG(image: CGImage, quality: Double) async throws -> Data {
        let lossless = try PNGEncoder.encode(image: image)
        let q = Int((quality * 100).rounded())
        if q >= 100 {
            return lossless
        }
        return try await PNGQuantizer.quantize(pngData: lossless, quality: q)
    }
}
```

- [ ] **Step 2: Refactor `ImageConverter.processOne`**

In `Services/ImageConverter.swift`, replace the existing `processOne` function with the version below. Key changes:
- `format: OutputFormat` stays as the signature parameter (it's what the user picked), but the work inside switches on `OutputPlanner.plan(...)`.
- The `.copy` branch resolves a filename with `ext: "svg"` and uses `FileManager.copyItem`.
- Cancellation is checked before copy.
- Copy failures map to `ConversionError.writeFailed`.
- On copy success, `outputBytes == originalBytes` (`file.byteSize`).

Replace the current `processOne` body with:

```swift
    private static func processOne(
        file: ImageFile,
        outputDir: URL,
        format: OutputFormat,
        quality: Double,
        resize: ResizeSettings,
        resolver: FilenameResolver
    ) async -> ConversionResult {
        if Task.isCancelled {
            return ConversionResult(id: UUID(), source: file.url, outcome: .cancelled)
        }

        let plan = OutputPlanner.plan(for: file.inputFormat, selected: format)
        let baseName = file.url.deletingPathExtension().lastPathComponent

        switch plan {
        case .encode(let encoderFormat):
            do {
                let cgImage = try ImageDecoder.decode(file: file)
                if Task.isCancelled {
                    return ConversionResult(id: UUID(), source: file.url, outcome: .cancelled)
                }
                let resized = ImageResizer.resize(cgImage, settings: resize)
                if Task.isCancelled {
                    return ConversionResult(id: UUID(), source: file.url, outcome: .cancelled)
                }
                let data = try await ImageEncoder.encode(image: resized, to: encoderFormat, quality: quality)
                if Task.isCancelled {
                    return ConversionResult(id: UUID(), source: file.url, outcome: .cancelled)
                }

                let outputURL = await resolver.resolve(
                    outputDirectory: outputDir,
                    baseName: baseName,
                    ext: encoderFormat.fileExtension
                )
                do {
                    try data.write(to: outputURL, options: .atomic)
                } catch {
                    return ConversionResult(
                        id: UUID(),
                        source: file.url,
                        outcome: .failure(.writeFailed(url: outputURL, underlying: error.localizedDescription))
                    )
                }

                return ConversionResult(
                    id: UUID(),
                    source: file.url,
                    outcome: .success(
                        outputURL: outputURL,
                        originalBytes: file.byteSize,
                        outputBytes: Int64(data.count)
                    )
                )
            } catch let err as ConversionError {
                return ConversionResult(id: UUID(), source: file.url, outcome: .failure(err))
            } catch {
                return ConversionResult(
                    id: UUID(),
                    source: file.url,
                    outcome: .failure(.decodeFailed(url: file.url, underlying: error.localizedDescription))
                )
            }

        case .copy:
            let outputURL = await resolver.resolve(
                outputDirectory: outputDir,
                baseName: baseName,
                ext: "svg"
            )
            if Task.isCancelled {
                return ConversionResult(id: UUID(), source: file.url, outcome: .cancelled)
            }
            do {
                try FileManager.default.copyItem(at: file.url, to: outputURL)
            } catch {
                return ConversionResult(
                    id: UUID(),
                    source: file.url,
                    outcome: .failure(.writeFailed(url: outputURL, underlying: error.localizedDescription))
                )
            }
            return ConversionResult(
                id: UUID(),
                source: file.url,
                outcome: .success(
                    outputURL: outputURL,
                    originalBytes: file.byteSize,
                    outputBytes: file.byteSize
                )
            )
        }
    }
```

The surrounding `run(files:settings:continuation:)` function and its `spawnNext()` closure keep calling `processOne(file:outputDir:format:quality:resize:resolver:)` with the same argument shape — no change needed there.

- [ ] **Step 3: Build**

Run: `swift build -c release`
Expected: clean build. The `.copy` branch is dead at runtime for now (`.sameAsOrigin` doesn't exist yet in `OutputFormat`), but it compiles and is ready for Task 5.

---

## Task 5: Add `.sameAsOrigin` to `OutputFormat`; teach the planner about it

**Files:**
- Modify: `Models/OutputFormat.swift`
- Modify: `Services/OutputPlanner.swift`

- [ ] **Step 1: Add the enum case**

Replace `Models/OutputFormat.swift` entirely with:

```swift
import Foundation
import UniformTypeIdentifiers

enum OutputFormat: String, CaseIterable, Identifiable, Hashable, Sendable {
    case jpeg
    case png
    case webp
    case avif
    case sameAsOrigin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .jpeg:         return "JPG"
        case .png:          return "PNG"
        case .webp:         return "WebP"
        case .avif:         return "AVIF"
        case .sameAsOrigin: return "Origin"
        }
    }

    /// Meaningful only for direct-encode picker choices. `.sameAsOrigin` resolves
    /// the effective extension per-file via `OutputPlanner`, so the empty string
    /// here is intentional and never read on that path.
    var fileExtension: String {
        switch self {
        case .jpeg:         return "jpg"
        case .png:          return "png"
        case .webp:         return "webp"
        case .avif:         return "avif"
        case .sameAsOrigin: return ""
        }
    }

    var utType: UTType {
        switch self {
        case .jpeg:         return .jpeg
        case .png:          return .png
        case .webp:         return UTType("org.webmproject.webp") ?? UTType.image
        case .avif:         return UTType("public.avif") ?? UTType.image
        case .sameAsOrigin: return .image
        }
    }

    var isLossless: Bool {
        self == .png
    }
}
```

- [ ] **Step 2: Extend the planner**

In `Services/OutputPlanner.swift`, replace the `plan(for:selected:)` body with the full routing:

```swift
    static func plan(for input: InputFormat, selected: OutputFormat) -> FileOutputPlan {
        switch selected {
        case .jpeg: return .encode(.jpeg)
        case .png:  return .encode(.png)
        case .webp: return .encode(.webp)
        case .avif: return .encode(.avif)
        case .sameAsOrigin:
            switch input {
            case .jpeg: return .encode(.jpeg)
            case .png:  return .encode(.png)
            case .webp: return .encode(.webp)
            case .avif: return .encode(.avif)
            case .heic: return .encode(.heic)
            case .svg:  return .copy
            }
        }
    }
```

- [ ] **Step 3: Build**

Run: `swift build -c release`
Expected: clean build. The segmented picker will now show five options (JPG / PNG / WebP / AVIF / Origin) via `OutputFormat.allCases`. No UI caption yet.

---

## Task 6: Add the SVG-copy caption in `SettingsPanelView`

**Files:**
- Modify: `Views/SettingsPanelView.swift`

- [ ] **Step 1: Add the caption**

In `Views/SettingsPanelView.swift`, inside `outputSection`, the inner `VStack` currently reads:

```swift
VStack(alignment: .leading, spacing: 6) {
    Text("Format")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
    FullWidthSegmented(
        selection: $settings.outputFormat,
        options: OutputFormat.allCases,
        title: { $0.displayName }
    )
}
```

Replace it with:

```swift
VStack(alignment: .leading, spacing: 6) {
    Text("Format")
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
    FullWidthSegmented(
        selection: $settings.outputFormat,
        options: OutputFormat.allCases,
        title: { $0.displayName }
    )
    if settings.outputFormat == .sameAsOrigin {
        Text("SVG files are copied as-is — resize and quality don't apply.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
```

No other edits in this file.

- [ ] **Step 2: Build**

Run: `swift build -c release`
Expected: clean build.

---

## Task 7: Manual validation

No automated tests for this change — `Tests/Fixtures/` is empty and Swift Testing isn't wired up. Validate by packaging the app and running the checklist below against live files.

- [ ] **Step 1: Rebuild the app bundle**

Run: `./Scripts/make-app.sh`
Expected: `✓ Built img-cc.app` with bundled `pngquant`.

- [ ] **Step 2: Launch**

Run: `open ./img-cc.app`

- [ ] **Step 3: Picker shows five options**

Verify the Output-settings Format row shows `JPG · PNG · WebP · AVIF · Origin`, with segments of equal width and `Origin` not overflowing its pill.

- [ ] **Step 4: Caption toggles with selection**

Select `Origin` — caption *"SVG files are copied as-is — resize and quality don't apply."* appears directly under the segmented row. Select any other format — caption disappears.

- [ ] **Step 5: Mixed batch round-trip**

Add a mixed batch to the drop zone: at least one file per input format (`.jpg`, `.png`, `.webp`, `.avif`, `.heic`, `.svg`). Leave quality at the default, enter `resize: 800 × 0` (width only, fit). Pick a clean output folder. Select `Origin`. Convert.

Expected after completion:
- `.jpg` file → `.jpg` output at width 800, re-encoded.
- `.png` file → `.png` output at width 800; if the PNG used `<256` colors, bytes should drop vs. source.
- `.webp` file → `.webp` output at width 800.
- `.avif` file → `.avif` output at width 800, opens in Preview.
- `.heic` file → `.heic` output at width 800, opens in Preview. **(New path — scrutinize this one.)**
- `.svg` file → `.svg` output, byte-identical to source (size in completion sheet matches exactly), not resized.

- [ ] **Step 6: SVG-only batch**

Add only SVG files. Select `Origin`. Convert. Completion sheet reports `N of N succeeded`; savings ratio shows `0.0%` because input bytes == output bytes.

- [ ] **Step 7: HEIC quality sweep**

Add a single HEIC. Select `Origin`. Convert at quality `100`, then `80`, then `30`, into the same output folder. Verify you end up with `photo.heic`, `photo (1).heic`, `photo (2).heic` and that file sizes monotonically decrease with quality.

- [ ] **Step 8: Filename collision on SVG copy**

Take two different SVG files named `icon.svg` from two directories and add them to one batch. Select `Origin`. Convert. Output folder contains `icon.svg` and `icon (1).svg`; both files match their respective sources byte-for-byte.

- [ ] **Step 9: Cancellation mid-job**

Add 20+ large raster files plus a few SVGs. Select `Origin`. Start the job and hit Cancel about halfway. The completion summary should show `X succeeded, 0 failed, (Y cancelled)` with `X + Y ≈ total`. No spurious `writeFailed` errors should appear for either raster or SVG items.

---

## Self-Review

**Spec coverage:**
- §2.1 picker with five segments → Task 5 (enum) + Task 6 (UI auto-picks up `allCases`).
- §2.2 inline hint → Task 6.
- §2.3 no other UI changes → respected (no edits to DropZone, FileList, etc.).
- §3 type split (`OutputFormat` / `EncoderFormat` / `FileOutputPlan`) → Task 1.
- §3.2 planner → Task 1 (stub) + Task 5 (full routing).
- §4.1 HEIC encoder → Task 3.
- §4.2 `ImageEncoder` signature swap + `.heic` dispatch → Task 4 Step 1.
- §5 `processOne` plan branch → Task 4 Step 2.
- §6 error type swap → Task 2.
- §7 no target-config sync → confirmed, no edits to `Package.swift` / `project.yml`.
- §9 manual validation → Task 7 covers all five spec scenarios (mixed batch, SVG-only, HEIC sweep, collision, cancellation).

**Placeholder scan:** no TBD / TODO / "handle edge cases" placeholders. Every step shows the exact code or command.

**Type consistency:** `EncoderFormat` cases (`jpeg/png/webp/avif/heic`) and display names / extensions match between Task 1 (definition), Task 3 (HEIC use), Task 4 (dispatch), and Task 5 (planner). `OutputFormat` cases (`jpeg/png/webp/avif/sameAsOrigin`) are consistent between Task 5 (definition), Task 5 (planner) and Task 6 (UI check).

**Commit strategy:** plan contains zero `git commit` steps; user commits at their own cadence.
