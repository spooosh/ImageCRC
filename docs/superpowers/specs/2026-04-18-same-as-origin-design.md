# Same as origin — Output Format

**Status:** Approved · **Date:** 2026-04-18

## 1. Purpose

Add a fifth option to the Output Format picker — **Origin** — that keeps each file in its input format. Raster inputs are decoded → resized → re-encoded in the matching format. SVG files bypass the pipeline entirely and are copied as-is. HEIC gains a new encoder as a side effect (HEIC-in → HEIC-out through this path only; HEIC is **not** exposed as a standalone picker option).

## 2. User-facing surface

### 2.1 Format picker

`SettingsPanelView.outputSection` segmented control gains a fifth segment labeled **Origin**.

Final order: `JPG · PNG · WebP · AVIF · Origin`.

### 2.2 Inline hint

When `settings.outputFormat == .sameAsOrigin`, a caption appears directly under the segmented control, matching the style of the existing PNG/pngquant hint and the resize-empty hint:

> *SVG files are copied as-is — resize and quality don't apply.*

The quality slider and the Resize section remain enabled and fully functional — they still apply to every non-SVG file in the batch.

### 2.3 Nothing else moves

No changes to the drop zone, file list, Convert button, progress overlay, or completion sheet.

## 3. Per-file routing

The user's selected format and the per-file execution plan are now two different things. A file with input format X and selected format `sameAsOrigin` encodes as X; a file with input format SVG and selected format `sameAsOrigin` is copied. Rather than overloading `OutputFormat`, introduce a minimal internal type split.

### 3.1 Types

```swift
// User-facing; drives the picker.
enum OutputFormat {
    case jpeg, png, webp, avif, sameAsOrigin
}

// Internal; drives the encoder dispatch.
enum EncoderFormat {
    case jpeg, png, webp, avif, heic
}

enum FileOutputPlan {
    case encode(EncoderFormat)
    case copy   // SVG pass-through
}
```

`OutputFormat.sameAsOrigin` has no meaningful `fileExtension` / `utType` on its own — those fields are not consulted on the sameAsOrigin path, because routing always goes through `OutputPlanner` first.

### 3.2 Planner

New `Services/OutputPlanner.swift`:

```swift
enum OutputPlanner {
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
}
```

The planner is pure, trivially unit-testable, and leaves `ImageConverter` thin.

## 4. Encoders

### 4.1 New `HEICEncoder`

`Services/Encoders/HEICEncoder.swift` mirrors `AVIFEncoder` one-for-one:

- ImageIO `CGImageDestination` with UTType `public.heic`.
- Quality via `kCGImageDestinationLossyCompressionQuality`, clamped to `[0, 1]`.
- Same error shape on destination-creation / finalize failures.

ImageIO has supported HEIC encode since macOS 10.13; our deployment target is 14, so no gating needed.

### 4.2 `ImageEncoder` signature change

`ImageEncoder.encode(image:to:quality:)` changes its `to:` argument from `OutputFormat` to `EncoderFormat`. Dispatch adds `.heic → HEICEncoder`. The PNG slow-path (lossless at `q==100`, pngquant below) is unchanged.

## 5. `ImageConverter.processOne`

Routing becomes:

```
let plan = OutputPlanner.plan(for: file.inputFormat, selected: format)
switch plan {
case .encode(let ef):
    let cgImage = try ImageDecoder.decode(file: file)
    check cancellation
    let resized = ImageResizer.resize(cgImage, settings: resize)
    check cancellation
    let data = try await ImageEncoder.encode(image: resized, to: ef, quality: quality)
    check cancellation
    resolve outputURL (ext = ef.fileExtension)
    write data

case .copy:
    check cancellation
    resolve outputURL (ext = "svg")
    try FileManager.default.copyItem(at: file.url, to: outputURL)
```

- `.copy` bypasses decode/resize/encode entirely — quality and resize settings have no effect on SVG, as advertised.
- Copy path reports `ConversionResult.success(originalBytes: file.byteSize, outputBytes: file.byteSize)`; existing summary math (`savingsRatio`) degrades to 0% savings for a pure-SVG batch, which is correct.
- Copy errors map to `ConversionError.writeFailed(url: outputURL, underlying: error.localizedDescription)`.
- Output extension on copy is normalized to lowercase `.svg`, matching the rest of the output path convention.

## 6. Errors

`ConversionError.encodeFailed(format:underlying:)` changes its `format` parameter from `OutputFormat` to `EncoderFormat`. The error is about the encoder that actually failed, not the user's picker choice. Display names on `EncoderFormat` mirror `OutputFormat` for uniformity (`"JPG"`, `"PNG"`, `"WebP"`, `"AVIF"`, `"HEIC"`). The existing `errorDescription` template (`"Could not encode as \(format.displayName)"`) keeps working unchanged.

## 7. Target-config sync

No new source directories, so `Package.swift` and `project.yml` need no edits.

## 8. Out of scope

- No HEIC as a standalone picker option.
- No SVG optimization (no bundled `svgo` or similar).
- No SVG resize via XML attribute rewriting.
- No per-format quality slider (global slider still applies uniformly to all non-SVG files).
- No UI treatment for "all files are SVG, so quality/resize are no-ops" — the global caption is sufficient.

## 9. Testing

`Tests/Fixtures/` is still empty and Swift Testing isn't wired up. Validation is manual for this change:

1. Mixed batch (jpg + png + webp + avif + heic + svg) → Origin → verify each output file has the correct extension, opens in Preview, and has resize + quality applied to the raster files but not the SVG.
2. Origin + SVG-only batch → copy succeeds, output bytes equal input bytes.
3. Origin + HEIC input with various quality values → round-trip opens cleanly.
4. Cancellation mid-job with mixed batch → in-flight tasks terminate, remaining files marked cancelled.
5. Filename collision on Origin (two `photo.svg` from different folders in one batch) → second file becomes `photo (1).svg`.
