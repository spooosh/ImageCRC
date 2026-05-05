# ImageCRC Phase 2 — Codec Round-Trip + Phase 1 Sweep

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cover Phase 1 coverage gaps surfaced by party-mode review, then exercise every encoder/decoder via round-trip tests using synthesised fixtures, then close two known production holes (EXIF orientation, colour-profile preservation) via probe-then-fix.

**Architecture:** Six sequential sections (A–F). Sections A–B are *sweep* — close Phase 1 gaps without new infrastructure. Section C adds minimal codec infra (no `Fixtures/Images/` dir; fixtures are synthesised in-test). Sections D–E exercise the round-trip path and fix two real production bugs. Section F finishes pngquant + SVG. Each section is independently mergeable; user can pause between sections.

**Tech Stack:** Swift 5.10, Swift Testing, ImageIO, libwebp via SwiftPM, pngquant subprocess, `TempDirectory` and `SyntheticImage` helpers from Phase 1 (now at `Tests/Support/`).

> **User policy:** Per spooosh's standing preference, never run `git commit` without explicit approval. Each task ends with a commit *snippet* the user runs manually after reviewing the diff. Subagents may commit on the `tests/phase-1` feature branch (branch is also where Phase 2 lives — name kept for continuity).
>
> **No fixtures on disk.** Phase 2 deliberately does NOT add `Tests/Fixtures/Images/` files. All test images are synthesised at runtime via `SyntheticImage` builders and written to `TempDirectory`. This keeps the repo light and makes tests hermetic. Real-world fixtures (camera photos with EXIF/ICC) get added in Phase 4 when SSIM baselines need them.

---

## Section Overview

| # | Section | Tasks | Goal |
|---|---------|-------|------|
| A | Sweep Phase 1 gaps | T1–T4 | Close Lens 2 coverage holes (fill+enlarge, allCases exhaustiveness, FilenameResolver edge cases, savingsRatio edges) |
| B | Sweep party-mode minor | T5–T7 | Close minor gaps (env-coupled defaultBaseline, utType/allowedUTTypes, EncoderFormat & ConversionResult helpers) |
| C | Codec infrastructure | T8–T9 | Extend `SyntheticImage` for codec tests; wire `Tests/CodecTests/` |
| D | Codec round-trip | T10–T12 | Encode → write → decode for every supported format, assert dims preserved |
| E | Probe-then-fix open holes | T13–T14 | EXIF orientation + colour-profile preservation — write failing test, then fix production |
| F | pngquant + SVG | T15–T16 | PNGQuantizer happy path + missing-binary, SVG decode |

**Phase 2 done when:**

- `swift test` ≥ 50 tests across ≥ 12 suites, all green
- All Lens 2 + party-mode minor gaps closed (or explicitly deferred to Phase 3+ in commit body)
- ImageIODecoder applies EXIF orientation correctly
- ImageResizer preserves the input's RGB colour profile (Display P3, Adobe RGB) instead of forcing DeviceRGB
- pngquant subprocess gated under `IMAGECRC_TEST_REQUIRE_PNGQUANT=1` env var (off by default in dev; on in Phase 6 CI)
- No new SwiftPM warnings beyond the existing two (`xcodeproj` exclude, `dmg` unhandled)
- User approval to write Phase 3 plan

**Estimated time:** 2–3 days.

---

## File structure delta

```
Tests/
├── Support/                       # Phase 1 (already moved from UnitTests/Support)
│   ├── TempDirectory.swift
│   └── SyntheticImage.swift       # extended in T8 with gradient/orientation builders
├── UnitTests/                     # Phase 1 (existing)
│   └── ... (8 suites — unchanged outside T1–T7 edits)
└── CodecTests/                    # NEW — Section C onwards
    ├── ImageIOEncodersTests.swift
    ├── WebPEncoderTests.swift
    ├── ImageDecoderTests.swift
    ├── SVGDecoderTests.swift
    ├── EXIFOrientationTests.swift
    ├── ColorProfilePreservationTests.swift
    └── PNGQuantizerTests.swift
```

`Package.swift` test target: extend `sources` from `["Support", "UnitTests"]` to `["Support", "UnitTests", "CodecTests"]`. Mirror in `project.yml`.

---

# Section A — Sweep Phase 1 gaps

---

### Task 1: ImageResizer fill-mode coverage

**Why:** Lens 2 found that all current `fill`-mode tests use sources LARGER than targets. Fill-without-enlarge upscale and fill+enlarge=true (centered crop after upscale) are entirely uncovered. A regression in the no-upscale guard for fill mode would ship green.

**Files:**
- Modify: `Tests/UnitTests/ImageResizerTests.swift` (append cases to `ImageResizerFillTests`)

- [ ] **Step 1: Append three tests to `ImageResizerFillTests`**

```swift
    @Test("fill with both dims and enlarge=false caps at source dims")
    func fillNoUpscale() {
        // 100x100 source, target 400x400 fill, enlarge=false.
        // raw scale = max(4, 4) = 4 → clamped to 1 → intermediate 100x100;
        // fill geometry: outputW = min(100, 400) = 100; same for H.
        let img = SyntheticImage.solid(width: 100, height: 100)
        var s = ResizeSettings()
        s.width = 400
        s.height = 400
        s.mode = .fill
        s.enlarge = false
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 100, "fill+enlarge=false must not upscale")
        #expect(out.height == 100)
    }

    @Test("fill with enlarge=true upscales then crops to target")
    func fillEnlargeAndCrop() {
        // 100x50 source, target 200x200 fill, enlarge=true.
        // raw scale = max(2, 4) = 4 → intermediate 400x200;
        // fill geometry: outputW = min(400, 200) = 200; outputH = min(200, 200) = 200;
        // drawX = (200 - 400) / 2 = -100, drawY = 0 — centered horizontal crop.
        let img = SyntheticImage.solid(width: 100, height: 50)
        var s = ResizeSettings()
        s.width = 200
        s.height = 200
        s.mode = .fill
        s.enlarge = true
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 200)
        #expect(out.height == 200)
    }

    @Test("fill with aspect-matching dims produces no crop")
    func fillNoCropWhenAspectMatches() {
        // 200x100 source, target 100x50 (same 2:1 aspect) fill.
        // scale = max(0.5, 0.5) = 0.5 → intermediate 100x50;
        // fill geometry: outputW = min(100, 100), outputH = min(50, 50);
        // drawX = drawY = 0.
        let img = SyntheticImage.solid(width: 200, height: 100)
        var s = ResizeSettings()
        s.width = 100
        s.height = 50
        s.mode = .fill
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 100)
        #expect(out.height == 50)
    }
```

- [ ] **Step 2: Run**

Run: `swift test --filter "ImageResizer"`
Expected: 11 tests across 3 suites pass (was 8, +3 new fill cases).

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/ImageResizerTests.swift
git commit -m "$(cat <<'EOF'
test(resizer): cover fill-mode upscale, enlarge+crop, aspect-matching

Lens 2 of party-mode review surfaced that all existing fill tests use
source > target. Add three cases covering the no-upscale guard for fill,
fill+enlarge=true with centered horizontal crop, and aspect-matching
fill that should produce no crop.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: OutputPlanner allCases-driven exhaustiveness

**Why:** Lens 2 found that `OutputPlannerTests.directFormats` and `sameAsOriginRaster` hard-code the input list. If a future dev adds `case gif` to `InputFormat` and "fixes" the now-non-exhaustive switch in `OutputPlanner.plan` with a `default: return .copy` clause, every existing test passes green while production silently produces wrong output. Drive iteration from `InputFormat.allCases` to force every new case to either declare its plan or fail loudly.

**Files:**
- Modify: `Tests/UnitTests/OutputPlannerTests.swift` (add suite + tests)

- [ ] **Step 1: Append a new suite to the file**

```swift
@Suite("OutputPlanner — exhaustiveness")
struct OutputPlannerExhaustivenessTests {
    @Test("every InputFormat has an explicit sameAsOrigin plan",
          arguments: InputFormat.allCases)
    func sameAsOriginExhaustive(input: InputFormat) {
        let plan = OutputPlanner.plan(for: input, selected: .sameAsOrigin)
        // Plan must be either an explicit encode for that format, or a copy.
        // A bogus default-clause that returns .encode(.jpeg) would fail this
        // for every input that isn't actually JPEG.
        switch (input, plan) {
        case (.jpeg, .encode(.jpeg)),
             (.png,  .encode(.png)),
             (.webp, .encode(.webp)),
             (.avif, .encode(.avif)),
             (.heic, .encode(.heic)),
             (.svg,  .copy):
            break  // expected
        default:
            Issue.record("Unexpected sameAsOrigin plan for \(input): \(plan)")
        }
    }

    @Test("every InputFormat × every direct OutputFormat encodes to that format",
          arguments: InputFormat.allCases,
          [OutputFormat.jpeg, .png, .webp, .avif])
    func directFormatsExhaustive(input: InputFormat, selected: OutputFormat) {
        let expected: EncoderFormat = {
            switch selected {
            case .jpeg: return .jpeg
            case .png:  return .png
            case .webp: return .webp
            case .avif: return .avif
            case .sameAsOrigin: fatalError("not reachable")
            }
        }()
        #expect(OutputPlanner.plan(for: input, selected: selected) == .encode(expected),
                "for input=\(input) selected=\(selected)")
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter OutputPlanner`
Expected: 6 tests / 2 suites pass (3 from `OutputPlannerTests` + 1 + (6 InputFormat × 4 OutputFormat = 24) parameterised cases reported as 1 + 24 = 25 in Swift Testing — actual count from the runner may vary; what matters is green).

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/OutputPlannerTests.swift
git commit -m "$(cat <<'EOF'
test(planner): drive OutputPlanner exhaustiveness from InputFormat.allCases

Existing tests hardcoded the input list, so adding a new InputFormat case
and a default: clause to the planner switch would silently route the new
format to a wrong encoder. Drive iteration from .allCases so every future
input must either be matched or fail the test with Issue.record.

Uses Swift Testing's @Test(arguments:) for per-case reporting.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: FilenameResolver edge cases

**Why:** Lens 2 found that all current resolver tests use clean lowercase 3-letter ext. Empty `ext`, leading-dot `ext`, missing `outputDirectory`, and special chars in `baseName` are uncovered.

**Files:**
- Modify: `Tests/UnitTests/FilenameResolverTests.swift` (append cases)

- [ ] **Step 1: Append four tests to `FilenameResolverTests`**

```swift
    @Test("empty extension produces a trailing-dot filename")
    func emptyExtension() async throws {
        let tmp = try TempDirectory()
        let r = FilenameResolver()
        let url = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: "")
        // Document the current behaviour: "photo." with a trailing dot.
        // If a future change rejects empty ext, this test will fail loudly
        // and the caller can be updated.
        #expect(url.lastPathComponent == "photo.")
    }

    @Test("leading-dot extension produces a double-dot filename")
    func leadingDotExtension() async throws {
        let tmp = try TempDirectory()
        let r = FilenameResolver()
        // Current behaviour: ".jpg" gets prepended with another dot → "photo..jpg".
        // This documents the contract: callers must NOT include the leading dot.
        let url = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: ".jpg")
        #expect(url.lastPathComponent == "photo..jpg",
                "callers must pass extension without leading dot")
    }

    @Test("missing output directory still returns a candidate path")
    func missingOutputDirectory() async throws {
        // The resolver does not create the directory — it only reserves names.
        // If the caller hands it a non-existent dir, fileExists is always false
        // and the bare name is returned. The eventual write is the caller's
        // responsibility.
        let nonExistent = URL(fileURLWithPath: "/tmp/imagecrc-resolver-missing-\(UUID().uuidString)")
        let r = FilenameResolver()
        let url = await r.resolve(outputDirectory: nonExistent, baseName: "x", ext: "png")
        #expect(url.lastPathComponent == "x.png")
        #expect(url.deletingLastPathComponent().path == nonExistent.path)
    }

    @Test("baseName with spaces and unicode is preserved verbatim")
    func unicodeBaseName() async throws {
        let tmp = try TempDirectory()
        let r = FilenameResolver()
        let url = await r.resolve(outputDirectory: tmp.url, baseName: "фото 1", ext: "jpg")
        #expect(url.lastPathComponent == "фото 1.jpg")
    }
```

- [ ] **Step 2: Run**

Run: `swift test --filter FilenameResolverTests`
Expected: 9/9 (5 existing + 4 new).

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/FilenameResolverTests.swift
git commit -m "$(cat <<'EOF'
test(resolver): cover empty/leading-dot ext, missing dir, unicode baseName

Lens 2 of party-mode review flagged these edge cases as uncovered. Each
test documents current behaviour so future changes — even unintentional
— surface as test failures with explanatory messages.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: ConversionSummary edge cases

**Why:** Lens 2 found that `savingsRatio` is only tested for the positive-savings case (1000 → 250). Negative savings (output > original — possible with PNG-to-PNG quantization on already-tiny images, or AVIF on simple sources) is uncovered. A `max(0, ...)` clamp added to `savingsRatio` would silently lie.

**Files:**
- Modify: `Tests/UnitTests/ConversionSummaryTests.swift` (append cases)

- [ ] **Step 1: Append two tests to `ConversionSummaryTests`**

```swift
    @Test("savingsRatio is negative when output is larger than original")
    func savingsRatioNegativeWhenOutputBigger() throws {
        let summary = ConversionSummary(
            total: 1,
            successes: [successResult(orig: 1000, out: 1500)],
            failures: [],
            cancelled: 0,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        let ratio = try #require(summary.savingsRatio)
        // 1 - 1500/1000 = -0.5. Negative result is a valid signal that the
        // output is larger; do NOT clamp to 0.
        #expect(abs(ratio - (-0.5)) < 1e-9)
    }

    @Test("savingsRatio is nil when totalOriginalBytes is 0")
    func savingsRatioNilWhenOriginalZero() {
        // Edge: a successful conversion with zero original bytes (empty
        // input file) — divide-by-zero must not crash; impl returns nil.
        let summary = ConversionSummary(
            total: 1,
            successes: [successResult(orig: 0, out: 100)],
            failures: [],
            cancelled: 0,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        #expect(summary.savingsRatio == nil)
    }
```

Note: change the `savingsRatioComputed` test signature to `func savingsRatioComputed() throws` if it isn't already, so `try #require` compiles. Verify in step 2.

- [ ] **Step 2: Verify the existing `savingsRatioComputed` already uses `try #require` correctly**

It currently reads `let ratio = try! #require(summary.savingsRatio)`. Per Lens 1 feedback, this should be `try #require` with `func ... throws`. Update if needed:

```swift
    @Test("savingsRatio is 1 - out/orig")
    func savingsRatioComputed() throws {
        // ... body unchanged ...
        let ratio = try #require(summary.savingsRatio)
        #expect(abs(ratio - 0.75) < 1e-9)
    }
```

- [ ] **Step 3: Run**

Run: `swift test --filter ConversionSummaryTests`
Expected: 6/6 (4 existing + 2 new).

- [ ] **Step 4: Commit**

```bash
git add Tests/UnitTests/ConversionSummaryTests.swift
git commit -m "$(cat <<'EOF'
test(summary): cover negative savings, zero-original, fix try! → try #require

savingsRatio must surface negative values when output exceeds original
(documents intended behaviour: do not clamp). totalOriginalBytes==0 must
return nil, not crash. Also replace try! with try #require per Lens 1.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section B — Sweep party-mode minor gaps

---

### Task 5: ConversionSettings — defang `~/Pictures` env coupling

**Why:** `ConversionSettingsTests.defaultBaseline` asserts `s.outputDirectory?.lastPathComponent == "ImageCRC"`. On a sandboxed CI runner without `~/Pictures`, the assertion silently passes (`nil != "ImageCRC"` → fails) — env-dependent flake. Split into a non-flaky assertion + a separate path-shape assertion that doesn't depend on `FileManager` resolving Pictures.

**Files:**
- Modify: `Tests/UnitTests/ConversionSettingsTests.swift`

- [ ] **Step 1: Replace the `defaultBaseline` assertions for `outputDirectory`**

Current:

```swift
        // outputDirectory may be nil if the user has no Pictures dir,
        // but on a normal macOS install it should resolve.
        #expect(s.outputDirectory?.lastPathComponent == "ImageCRC")
```

New:

```swift
        // outputDirectory depends on FileManager.urls(for: .picturesDirectory).
        // Some sandboxed CI runners lack ~/Pictures; in that case the resolver
        // returns nil, which is a valid state. When non-nil, the directory
        // must end in "ImageCRC".
        if let dir = s.outputDirectory {
            #expect(dir.lastPathComponent == "ImageCRC")
        }
```

- [ ] **Step 2: Run**

Run: `swift test --filter ConversionSettingsTests`
Expected: 3/3 still pass on dev machine. On CI without `~/Pictures` (verified in Phase 6), no flake.

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/ConversionSettingsTests.swift
git commit -m "$(cat <<'EOF'
test(settings): defang ~/Pictures env coupling in defaultBaseline

The previous form asserted lastPathComponent == "ImageCRC" against an
optional URL; on a CI runner without ~/Pictures this passes false-green.
Split into "if let dir { ... }" so a nil result is a valid state and the
suffix check only runs when the FS actually resolved a directory.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: OutputFormat.utType + InputFormat.allowedUTTypes

**Why:** Final reviewer flagged both as untested. Used by the file-picker filter (`InputFormat.allowedUTTypes` → `NSOpenPanel.allowedContentTypes`) and by encoder routing (`OutputFormat.utType` → `CGImageDestinationCreateWithData`). Silent regression if the system UTType registry shifts (e.g. macOS 15 deprecates `org.webmproject.webp`).

**Files:**
- Create: `Tests/UnitTests/OutputFormatUTTypeTests.swift`
- Modify: `Tests/UnitTests/InputFormatTests.swift` (append suite)

- [ ] **Step 1: Create `Tests/UnitTests/OutputFormatUTTypeTests.swift`**

```swift
// Tests/UnitTests/OutputFormatUTTypeTests.swift
import Testing
import UniformTypeIdentifiers
@testable import ImageCRC

@Suite("OutputFormat — UTType")
struct OutputFormatUTTypeTests {
    @Test("each format resolves to the expected UTType identifier")
    func utTypeIdentifiers() {
        #expect(OutputFormat.jpeg.utType == .jpeg)
        #expect(OutputFormat.png.utType == .png)
        #expect(OutputFormat.webp.utType.identifier == "org.webmproject.webp",
                "system UTType registry must still recognise WebP")
        #expect(OutputFormat.avif.utType.identifier == "public.avif",
                "system UTType registry must still recognise AVIF")
        #expect(OutputFormat.sameAsOrigin.utType == .image,
                "sameAsOrigin is a routing choice, not a writeable target")
    }
}
```

- [ ] **Step 2: Append a suite to `InputFormatTests.swift`**

```swift
@Suite("InputFormat — UTTypes")
struct InputFormatUTTypeTests {
    @Test("allowedUTTypes always includes the standard formats")
    func standardTypesPresent() {
        let ids = Set(InputFormat.allowedUTTypes.map { $0.identifier })
        #expect(ids.contains(UTType.jpeg.identifier))
        #expect(ids.contains(UTType.png.identifier))
        #expect(ids.contains(UTType.heic.identifier))
        #expect(ids.contains(UTType.svg.identifier))
    }

    @Test("allowedUTTypes includes WebP and AVIF on systems that recognise them")
    func optionalTypesIncluded() {
        let ids = Set(InputFormat.allowedUTTypes.map { $0.identifier })
        // The static initializer drops these silently if the lookup fails.
        // A regression in the system registry would shrink the set; pin the
        // expectation that they are present on macOS 14+.
        #expect(ids.contains("org.webmproject.webp"))
        #expect(ids.contains("public.avif"))
    }
}
```

Note: also need `import UniformTypeIdentifiers` at the top of `InputFormatTests.swift` if not already present. Add it.

- [ ] **Step 3: Run**

Run: `swift test --filter "UTType"`
Expected: 3/3 (1 from OutputFormat, 2 from InputFormat).

- [ ] **Step 4: Commit**

```bash
git add Tests/UnitTests/OutputFormatUTTypeTests.swift Tests/UnitTests/InputFormatTests.swift
git commit -m "$(cat <<'EOF'
test(formats): cover OutputFormat.utType and InputFormat.allowedUTTypes

The static UTType lookups for WebP and AVIF fail silently to UTType.image
or get dropped from allowedUTTypes if the system registry shifts. Pin the
expected identifiers so a macOS upgrade that breaks lookup surfaces here
rather than at runtime in the file picker.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: EncoderFormat tests + ConversionResult helpers

**Why:** Final reviewer flagged that `EncoderFormat` (`displayName`, `fileExtension`) is exercised only transitively through `OutputPlannerTests`, and that `ConversionResult.{isSuccess,isFailure}` helpers are untested.

**Files:**
- Create: `Tests/UnitTests/EncoderFormatTests.swift`
- Create: `Tests/UnitTests/ConversionResultTests.swift`

- [ ] **Step 1: `Tests/UnitTests/EncoderFormatTests.swift`**

```swift
// Tests/UnitTests/EncoderFormatTests.swift
import Testing
@testable import ImageCRC

@Suite("EncoderFormat")
struct EncoderFormatTests {
    @Test("fileExtension matches each encoder format")
    func fileExtensions() {
        #expect(EncoderFormat.jpeg.fileExtension == "jpg")
        #expect(EncoderFormat.png.fileExtension  == "png")
        #expect(EncoderFormat.webp.fileExtension == "webp")
        #expect(EncoderFormat.avif.fileExtension == "avif")
        #expect(EncoderFormat.heic.fileExtension == "heic")
    }

    @Test("displayName is non-empty for every format")
    func displayNames() {
        for f: EncoderFormat in [.jpeg, .png, .webp, .avif, .heic] {
            #expect(f.displayName.isEmpty == false, "\(f).displayName must not be empty")
        }
    }
}
```

- [ ] **Step 2: `Tests/UnitTests/ConversionResultTests.swift`**

```swift
// Tests/UnitTests/ConversionResultTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("ConversionResult")
struct ConversionResultTests {
    private func make(_ outcome: ConversionResult.Outcome) -> ConversionResult {
        ConversionResult(id: UUID(), source: URL(fileURLWithPath: "/tmp/in.jpg"), outcome: outcome)
    }

    @Test("isSuccess and isFailure mirror the Outcome case")
    func helpers() {
        let success = make(.success(outputURL: URL(fileURLWithPath: "/tmp/out.jpg"),
                                    originalBytes: 100, outputBytes: 80))
        let failure = make(.failure(.outputDirectoryMissing))
        let cancelled = make(.cancelled)

        #expect(success.isSuccess == true)
        #expect(success.isFailure == false)

        #expect(failure.isSuccess == false)
        #expect(failure.isFailure == true)

        #expect(cancelled.isSuccess == false)
        #expect(cancelled.isFailure == false,
                "cancelled is neither success nor failure — own bucket")
    }
}
```

- [ ] **Step 3: Run**

Run: `swift test --filter "EncoderFormat|ConversionResult"`
Expected: 3/3 across 2 suites (2 EncoderFormat + 1 ConversionResult).

- [ ] **Step 4: Commit**

```bash
git add Tests/UnitTests/EncoderFormatTests.swift Tests/UnitTests/ConversionResultTests.swift
git commit -m "$(cat <<'EOF'
test(formats): direct EncoderFormat suite + ConversionResult helpers

EncoderFormat was only exercised transitively through OutputPlannerTests;
ConversionResult.isSuccess/isFailure were untested. The cancelled-case
boolean tri-state is non-obvious enough to pin explicitly.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section C — Codec infrastructure

---

### Task 8: SyntheticImage extensions for codec round-trip

**Why:** Solid-color images compress to nearly-empty bytes and don't exercise color encoders meaningfully. Round-trip tests need a `gradient` builder for non-trivial encoder output, plus a `jpegDataWithEXIFOrientation` helper for Section E.

**Files:**
- Modify: `Tests/Support/SyntheticImage.swift` (extend the enum with new static methods)

- [ ] **Step 1: Add a `gradient` builder + `jpegDataWithEXIFOrientation`**

Append to `enum SyntheticImage`:

```swift
    /// Linear horizontal red→blue gradient. Non-trivial color content for codec tests.
    /// Crashes on context creation failure (test-only contract).
    static func gradient(
        width: Int,
        height: Int,
        colorSpace: CGColorSpace = CGColorSpaceCreateDeviceRGB()
    ) -> CGImage {
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            fatalError("SyntheticImage.gradient: failed to create CGContext (\(width)x\(height))")
        }
        guard let cgGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                     CGColor(red: 0, green: 0, blue: 1, alpha: 1)] as CFArray,
            locations: [0.0, 1.0]
        ) else {
            fatalError("SyntheticImage.gradient: failed to create CGGradient")
        }
        ctx.drawLinearGradient(
            cgGradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: width, y: 0),
            options: []
        )
        guard let image = ctx.makeImage() else {
            fatalError("SyntheticImage.gradient: makeImage() returned nil")
        }
        return image
    }

    /// Encode a CGImage to JPEG with a specific EXIF orientation tag.
    /// Used by EXIF orientation probe-then-fix tests.
    /// `orientation` follows the TIFF/EXIF spec: 1=normal, 6=90° CW, 8=270° CW, etc.
    static func jpegData(from image: CGImage, exifOrientation: Int) -> Data {
        let mutableData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            fatalError("SyntheticImage.jpegData: destination creation failed")
        }
        let props: [CFString: Any] = [
            kCGImagePropertyOrientation: exifOrientation
        ]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            fatalError("SyntheticImage.jpegData: finalize failed")
        }
        return mutableData as Data
    }
```

Note: the `jpegData` helper needs `import ImageIO` and `import UniformTypeIdentifiers` at the top of `SyntheticImage.swift`. Add them.

- [ ] **Step 2: Verify it compiles**

Run: `swift build --target ImageCRCTests`
Expected: green.

Run `swift test`. Expected: same count as before this task (no new tests yet — just helpers).

- [ ] **Step 3: Commit**

```bash
git add Tests/Support/SyntheticImage.swift
git commit -m "$(cat <<'EOF'
test(infra): add gradient builder and EXIF-orientation JPEG helper

Solid-color images compress to nearly-empty bytes and don't meaningfully
exercise codec output. gradient() produces a horizontal red→blue ramp.
jpegData(from:exifOrientation:) writes a JPEG with a specific EXIF
orientation tag for the upcoming probe-then-fix test in Section E.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Wire `Tests/CodecTests/` source dir

**Why:** Codec tests need their own directory under `Tests/`. Add it to both `Package.swift` and `project.yml`. No fixtures dir yet (Phase 2 synthesises everything).

**Files:**
- Modify: `Package.swift` (extend test target sources)
- Modify: `project.yml` (mirror)
- Create: `Tests/CodecTests/.gitkeep` (so the empty dir is tracked)

- [ ] **Step 1: Update `Package.swift`**

Current test target block:

```swift
        .testTarget(
            name: "ImageCRCTests",
            dependencies: ["ImageCRC"],
            path: "Tests",
            exclude: ["Fixtures"],
            sources: ["Support", "UnitTests"]
        )
```

New (note: explicit `.gitkeep` exclude is defensive — SwiftPM normally skips dotfiles via `.skipsHiddenFiles` but pinning the exclude prevents future SwiftPM behaviour shifts from emitting an "unhandled file" warning that would violate the Phase 2 done-when "no new warnings" rule):

```swift
        .testTarget(
            name: "ImageCRCTests",
            dependencies: ["ImageCRC"],
            path: "Tests",
            exclude: ["Fixtures", "CodecTests/.gitkeep"],
            sources: ["Support", "UnitTests", "CodecTests"]
        )
```

- [ ] **Step 2: Update `project.yml`**

Extend the `ImageCRCTests.sources` list:

```yaml
  ImageCRCTests:
    type: bundle.unit-test
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: Tests/Support
      - path: Tests/UnitTests
      - path: Tests/CodecTests
```

- [ ] **Step 3: Create the directory**

```bash
mkdir -p Tests/CodecTests
touch Tests/CodecTests/.gitkeep
```

- [ ] **Step 4: Verify**

Run: `swift build --target ImageCRCTests`
Expected: green (empty dir is fine).

Run: `swift test`
Expected: same count as before (no new tests).

- [ ] **Step 5: Commit**

```bash
git add Package.swift project.yml Tests/CodecTests/.gitkeep
git commit -m "$(cat <<'EOF'
chore(tests): wire Tests/CodecTests source dir for Phase 2 round-trip suite

Add the directory to both Package.swift sources and project.yml mirror.
.gitkeep tracks the empty dir until Section D fills it. Fixtures stay
synthesised in-test — no Tests/Fixtures/Images/ in Phase 2.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section D — Codec round-trip

---

### Task 10: ImageIO encoders round-trip (JPEG/PNG/HEIC/AVIF)

**Why:** Verify that for each ImageIO-backed encoder, encoding a synthesised gradient → writing to TempDirectory → decoding via `ImageIODecoder` produces a non-nil `CGImage` with preserved dimensions.

**Files:**
- Create: `Tests/CodecTests/ImageIOEncodersTests.swift`

- [ ] **Step 1: Write the suite**

```swift
// Tests/CodecTests/ImageIOEncodersTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("ImageIO encoders — round-trip")
struct ImageIOEncodersRoundTripTests {
    private func writeAndDecode(
        data: Data, ext: String, in tmp: TempDirectory
    ) throws -> CGImage {
        let url = tmp.url.appendingPathComponent("out.\(ext)")
        try data.write(to: url)
        return try ImageIODecoder.decode(url: url)
    }

    @Test("JPEG round-trip preserves dimensions")
    func jpegRoundTrip() throws {
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 64, height: 32)
        let data = try JPEGEncoder.encode(image: src, quality: 0.8)
        let decoded = try writeAndDecode(data: data, ext: "jpg", in: tmp)
        #expect(decoded.width == 64)
        #expect(decoded.height == 32)
        #expect(data.count > 0)
    }

    @Test("PNG round-trip preserves dimensions and is lossless")
    func pngRoundTrip() throws {
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 64, height: 32)
        let data = try PNGEncoder.encode(image: src)
        let decoded = try writeAndDecode(data: data, ext: "png", in: tmp)
        #expect(decoded.width == 64)
        #expect(decoded.height == 32)
        #expect(data.count > 0)
    }

    @Test("HEIC round-trip preserves dimensions")
    func heicRoundTrip() throws {
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 64, height: 32)
        let data = try HEICEncoder.encode(image: src, quality: 0.8)
        let decoded = try writeAndDecode(data: data, ext: "heic", in: tmp)
        #expect(decoded.width == 64)
        #expect(decoded.height == 32)
        #expect(data.count > 0)
    }

    @Test("AVIF round-trip preserves dimensions",
          .timeLimit(.minutes(1)))
    func avifRoundTrip() throws {
        // AVIF encode is slow on macOS 14 — bound the test.
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 64, height: 32)
        let data = try AVIFEncoder.encode(image: src, quality: 0.8)
        let decoded = try writeAndDecode(data: data, ext: "avif", in: tmp)
        #expect(decoded.width == 64)
        #expect(decoded.height == 32)
        #expect(data.count > 0)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter "ImageIO encoders"`
Expected: 4/4 across 1 suite. AVIF may take a couple seconds — within the 1-minute time limit.

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/ImageIOEncodersTests.swift
git commit -m "$(cat <<'EOF'
test(codec): JPEG/PNG/HEIC/AVIF round-trip via ImageIO

Encode a 64x32 synthesised gradient, write to TempDirectory, decode via
ImageIODecoder; assert dimensions preserved and data non-empty. AVIF gets
a 1-minute time limit since macOS 14 encode is slower than the others.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: WebP encoder round-trip

**Why:** WebP uses libwebp via SwiftPM (not ImageIO) and stages through `RGBABuffer`. Separate task because it exercises a different code path.

**Files:**
- Create: `Tests/CodecTests/WebPEncoderTests.swift`

- [ ] **Step 1: Write the suite**

```swift
// Tests/CodecTests/WebPEncoderTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("WebP encoder — round-trip")
struct WebPEncoderRoundTripTests {
    @Test("WebP round-trip preserves dimensions")
    func webpRoundTrip() throws {
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 64, height: 32)
        let data = try WebPEncoder.encode(image: src, quality: 0.8)
        #expect(data.count > 0)
        // Sanity check: WebP signature is "RIFF" at byte 0 then "WEBP" at byte 8.
        #expect(data.starts(with: [0x52, 0x49, 0x46, 0x46]),
                "WebP must start with 'RIFF' magic")

        let url = tmp.url.appendingPathComponent("out.webp")
        try data.write(to: url)
        let decoded = try ImageIODecoder.decode(url: url)
        #expect(decoded.width == 64)
        #expect(decoded.height == 32)
    }

    @Test("WebP encode of a 1x1 image still produces valid output")
    func webpMinimalSize() throws {
        let src = SyntheticImage.solid(width: 1, height: 1)
        let data = try WebPEncoder.encode(image: src, quality: 1.0)
        #expect(data.count > 0)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter "WebP"`
Expected: 2/2.

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/WebPEncoderTests.swift
git commit -m "$(cat <<'EOF'
test(codec): WebP encoder round-trip via libwebp + ImageIO decode

WebP takes a separate path (libwebp + RGBABuffer staging) so its tests
live in their own suite. Includes a 1x1 minimum-size case to exercise
the smallest valid input through RGBABuffer.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: ImageDecoder dispatch via ImageFile

**Why:** `ImageDecoder.decode(file:)` dispatches by `InputFormat`. Verify the dispatch works for each non-SVG format (SVG gets its own task in Section F).

**Files:**
- Create: `Tests/CodecTests/ImageDecoderTests.swift`

- [ ] **Step 1: Write the suite**

```swift
// Tests/CodecTests/ImageDecoderTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("ImageDecoder — dispatch by InputFormat")
struct ImageDecoderDispatchTests {
    private func encodeAndWrap(
        format: InputFormat, in tmp: TempDirectory
    ) throws -> ImageFile {
        let src = SyntheticImage.gradient(width: 48, height: 24)
        let data: Data
        let ext: String
        switch format {
        case .jpeg:
            data = try JPEGEncoder.encode(image: src, quality: 0.9); ext = "jpg"
        case .png:
            data = try PNGEncoder.encode(image: src); ext = "png"
        case .heic:
            data = try HEICEncoder.encode(image: src, quality: 0.9); ext = "heic"
        case .avif:
            data = try AVIFEncoder.encode(image: src, quality: 0.9); ext = "avif"
        case .webp:
            data = try WebPEncoder.encode(image: src, quality: 0.9); ext = "webp"
        case .svg:
            // SVG has its own decode path tested in SVGDecoderTests.
            fatalError("not used here")
        }
        let url = tmp.url.appendingPathComponent("in.\(ext)")
        try data.write(to: url)
        return try #require(ImageFile(url: url))
    }

    @Test("decode dispatches correctly for each raster InputFormat",
          arguments: [InputFormat.jpeg, .png, .heic, .avif, .webp])
    func dispatch(_ format: InputFormat) throws {
        let tmp = try TempDirectory()
        let file = try encodeAndWrap(format: format, in: tmp)
        let decoded = try ImageDecoder.decode(file: file)
        #expect(decoded.width == 48)
        #expect(decoded.height == 24)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter ImageDecoder`
Expected: 5/5 (one per format).

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/ImageDecoderTests.swift
git commit -m "$(cat <<'EOF'
test(codec): ImageDecoder dispatch for every raster InputFormat

Round-trip a synthesised 48x24 gradient through each encoder, write to
TempDirectory with correct extension, then decode via ImageDecoder.decode
which dispatches by file.inputFormat. Asserts dims preserved.

SVG decode lives in SVGDecoderTests in Section F.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section E — Probe-then-fix open holes

---

### Task 13: EXIF orientation probe-then-fix

**Why:** Plan Phase 1 finalisation flagged that `ImageIODecoder` does not honour the EXIF orientation tag. A photo from an iPhone in portrait mode has orientation=6 (90° CW); the visible image is portrait but the raw pixels are landscape. Without applying the tag, ImageCRC saves a sideways image — the single most common user-visible bug in image converters.

**This task includes a production-code change.** Test and fix land as one commit (`fix(decoder): apply EXIF orientation in ImageIODecoder`) so the branch is never red.

**Files:**
- Create: `Tests/CodecTests/EXIFOrientationTests.swift`
- Modify: `Services/Decoders/ImageIODecoder.swift`

- [ ] **Step 1: Write the failing probe test (do NOT commit yet)**

```swift
// Tests/CodecTests/EXIFOrientationTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("ImageIODecoder — EXIF orientation")
struct EXIFOrientationTests {
    @Test("orientation=6 (90° CW) swaps width and height after decode")
    func orientation6SwapsDims() throws {
        let tmp = try TempDirectory()
        // Source is 100 wide × 50 tall. With EXIF orientation=6, the camera
        // recorded "landscape sensor; rotate 90 CW for display" — meaning the
        // logical image is 50 wide × 100 tall.
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let data = SyntheticImage.jpegData(from: src, exifOrientation: 6)
        let url = tmp.url.appendingPathComponent("rotated.jpg")
        try data.write(to: url)

        let decoded = try ImageIODecoder.decode(url: url)
        // After applying orientation: width and height should be swapped.
        #expect(decoded.width == 50, "EXIF orientation=6 must swap width/height")
        #expect(decoded.height == 100)
    }

    @Test("orientation=1 (normal) preserves dimensions as-is")
    func orientation1NoOp() throws {
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let data = SyntheticImage.jpegData(from: src, exifOrientation: 1)
        let url = tmp.url.appendingPathComponent("normal.jpg")
        try data.write(to: url)

        let decoded = try ImageIODecoder.decode(url: url)
        #expect(decoded.width == 100)
        #expect(decoded.height == 50)
    }

    @Test("orientation=8 (270° CW / 90° CCW) also swaps")
    func orientation8Swaps() throws {
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let data = SyntheticImage.jpegData(from: src, exifOrientation: 8)
        let url = tmp.url.appendingPathComponent("rotated8.jpg")
        try data.write(to: url)

        let decoded = try ImageIODecoder.decode(url: url)
        #expect(decoded.width == 50)
        #expect(decoded.height == 100)
    }

    @Test("orientation=6 places the original left edge at the top after rotation")
    func orientation6PixelGeometry() throws {
        // Without this test, a transposed rotation matrix (e.g. 90° CCW where
        // we wanted CW) would still pass the dim-swap assertions above.
        // Sample an actual pixel to verify the rotation is geometrically right.
        let tmp = try TempDirectory()
        // Horizontal gradient: red at x=0, blue at x=W-1. Source 100w × 50h.
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let data = SyntheticImage.jpegData(from: src, exifOrientation: 6)
        let url = tmp.url.appendingPathComponent("rotated6-pixel.jpg")
        try data.write(to: url)

        let decoded = try ImageIODecoder.decode(url: url)
        #expect(decoded.width == 50)
        #expect(decoded.height == 100)

        // After orientation=6 (90° CW for display), the original left edge (red)
        // becomes the new top edge. Sample a pixel near top-center; R must
        // dominate B with enough slack for JPEG quantisation.
        let buf = try RGBABuffer.make(from: decoded)
        let x = 25
        let y = 5
        let i = y * buf.bytesPerRow + x * 4
        let r = buf.bytes[i]
        let b = buf.bytes[i + 2]
        #expect(r > b + 50,
                "expected red-dominant pixel near top of orientation=6 decoded image; got R=\(r), B=\(b)")
    }
}
```

- [ ] **Step 2: Verify the test fails (probe)**

Run: `swift test --filter EXIF`
Expected: 1/4 pass (only `orientation1NoOp`). The three rotation-affected tests fail because `ImageIODecoder.decode` does not apply orientation.

- [ ] **Step 3: Apply the fix to `Services/Decoders/ImageIODecoder.swift`**

Replace the body of `decode(url:)` with:

```swift
import Foundation
import ImageIO
import CoreGraphics

enum ImageIODecoder {
    /// Decode any ImageIO-supported format (jpg, png, heic, avif, webp on macOS 14+) to CGImage.
    /// Honours the EXIF orientation tag when present — the returned CGImage's width/height
    /// reflect the visually-correct orientation, not the raw sensor layout.
    static func decode(url: URL) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldAllowFloat: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else {
            throw ConversionError.decodeFailed(url: url, underlying: "CGImageSource create failed")
        }
        guard CGImageSourceGetCount(source) > 0 else {
            throw ConversionError.decodeFailed(url: url, underlying: "No image in file")
        }
        guard let raw = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            throw ConversionError.decodeFailed(url: url, underlying: "CGImage create failed")
        }

        // Read EXIF orientation if present. CGImagePropertyOrientation values:
        // 1 = up, 2 = upMirrored, 3 = down, 4 = downMirrored,
        // 5 = leftMirrored, 6 = right (90° CW), 7 = rightMirrored, 8 = left (90° CCW).
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationRaw = props?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        guard let orientation = CGImagePropertyOrientation(rawValue: orientationRaw) else {
            return raw
        }
        if orientation == .up { return raw }
        return Self.applyOrientation(orientation, to: raw)
    }

    /// Bake an EXIF orientation into the pixels by drawing through a
    /// transformed CGContext. Returns a fresh CGImage whose width/height
    /// reflect the visually-correct orientation.
    private static func applyOrientation(
        _ orientation: CGImagePropertyOrientation, to image: CGImage
    ) -> CGImage {
        let srcW = image.width
        let srcH = image.height
        // For 90° rotations (.right / .left / their mirrored variants) the output
        // canvas swaps width and height.
        let swap: Bool = {
            switch orientation {
            case .left, .right, .leftMirrored, .rightMirrored: return true
            default: return false
            }
        }()
        let outW = swap ? srcH : srcW
        let outH = swap ? srcW : srcH

        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        // Build the affine transform that maps source pixels into the output
        // canvas. Order matters: translate first to position the origin, then
        // rotate / flip.
        switch orientation {
        case .up:
            break
        case .upMirrored:
            ctx.translateBy(x: CGFloat(outW), y: 0)
            ctx.scaleBy(x: -1, y: 1)
        case .down:
            ctx.translateBy(x: CGFloat(outW), y: CGFloat(outH))
            ctx.rotate(by: .pi)
        case .downMirrored:
            ctx.translateBy(x: 0, y: CGFloat(outH))
            ctx.scaleBy(x: 1, y: -1)
        case .leftMirrored:
            ctx.translateBy(x: CGFloat(outW), y: CGFloat(outH))
            ctx.rotate(by: .pi / 2)
            ctx.scaleBy(x: 1, y: -1)
        case .right:
            ctx.translateBy(x: CGFloat(outW), y: 0)
            ctx.rotate(by: .pi / 2)
        case .rightMirrored:
            ctx.scaleBy(x: -1, y: 1)
            ctx.rotate(by: .pi / 2)
        case .left:
            ctx.translateBy(x: 0, y: CGFloat(outH))
            ctx.rotate(by: -.pi / 2)
        @unknown default:
            return image
        }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))
        return ctx.makeImage() ?? image
    }
}
```

- [ ] **Step 4: Verify the fix**

Run: `swift test --filter EXIF`
Expected: 4/4 pass.

Run full suite: `swift test`
Expected: all green; total count went up by 4.

- [ ] **Step 5: Commit (test + fix together — single logical change)**

```bash
git add Tests/CodecTests/EXIFOrientationTests.swift Services/Decoders/ImageIODecoder.swift
git commit -m "$(cat <<'EOF'
fix(decoder): apply EXIF orientation in ImageIODecoder

ImageIODecoder previously ignored the EXIF orientation tag, so iPhone
portraits (orientation=6) decoded as sideways landscape — the most
common user-visible bug class in image converters.

Read kCGImagePropertyOrientation from CGImageSourceCopyPropertiesAtIndex
and bake the rotation into the pixels via a transformed CGContext. The
returned CGImage's width/height now reflect the visually-correct
orientation, so downstream resize and encode see the user-intended
dimensions.

Adds three probe tests in Tests/CodecTests/EXIFOrientationTests.swift
covering normal (1), 90° CW (6), and 90° CCW (8) — the three orientations
real-world cameras actually emit. A sentinel-pixel test confirms the
rotation matrix is geometrically correct (not just dim-swapping correct).

Known limitation: this reads orientation from the top-level
kCGImagePropertyOrientation key. ImageIO usually promotes EXIF
orientation there for JPEGs and HEICs, but for some edited files the
value lives only inside kCGImagePropertyTIFFDictionary. If a real-world
file with this layout surfaces, fall back to the nested lookup before
the rotation defaults to .up.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: Color profile probe-then-fix

**Why:** `ImageResizer` forces `CGColorSpaceCreateDeviceRGB()` whenever the input color space's model isn't `.rgb` (line 32–35) — but on the active path, even when it IS `.rgb`, the new context's color space is determined by the original `image.colorSpace`. The bug is more subtle than "always forces DeviceRGB":

Re-read `ImageResizer.swift:32-35`:
```swift
let colorSpace: CGColorSpace = {
    if let cs = image.colorSpace, cs.model == .rgb { return cs }
    return CGColorSpaceCreateDeviceRGB()
}()
```

This **does** preserve the input colorspace when it's RGB. So Display P3 should round-trip. The reviewer's flag may have been speculative. Verify before fixing.

**Smoke-only scope:** this probe checks **colorspace name preservation**, not chromaticity preservation. With the resizer's current `bitsPerComponent: 8` bitmap config, P3 wide-gamut chromaticities can clip silently even when the colorspace label survives. **Chromaticity-level preservation is a Phase 4 concern** (perceptual quality + SSIM) — Phase 2 deliberately scopes this task to "the colorspace label round-trips" only.

**This task includes a production-code change ONLY if the probe finds a real bug.**

**Files:**
- Create: `Tests/CodecTests/ColorProfilePreservationTests.swift`
- Possibly modify: `Services/ImageResizer.swift` (if probe finds a bug)

- [ ] **Step 1: Write the probe test**

```swift
// Tests/CodecTests/ColorProfilePreservationTests.swift
import Foundation
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("ImageResizer — color profile preservation")
struct ColorProfilePreservationTests {
    @Test("Display P3 input is preserved through resize")
    func displayP3Preserved() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let img = SyntheticImage.solid(width: 100, height: 100, colorSpace: p3)
        // Sanity: source actually carries P3.
        let srcName = img.colorSpace?.name as String?
        #expect(srcName == (CGColorSpace.displayP3 as String),
                "synthesised P3 image must carry displayP3 colorspace; got \(srcName ?? "nil")")

        var s = ResizeSettings()
        s.width = 50
        s.height = 50
        s.mode = .fit
        let resized = ImageResizer.resize(img, settings: s)

        let resizedName = resized.colorSpace?.name as String?
        #expect(resizedName == (CGColorSpace.displayP3 as String),
                "Display P3 must survive resize; got \(resizedName ?? "nil")")
    }

    @Test("inactive resize trivially preserves colorspace (===)")
    func inactivePreservesColorspace() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let img = SyntheticImage.solid(width: 100, height: 100, colorSpace: p3)
        let out = ImageResizer.resize(img, settings: ResizeSettings())
        // Inactive path returns the same image, so colorspace is preserved by definition.
        #expect((out.colorSpace?.name as String?) == (CGColorSpace.displayP3 as String))
    }
}
```

- [ ] **Step 2: Run the probe**

Run: `swift test --filter "color profile"`

Two outcomes:

**Outcome A — both tests pass.** The reviewer was wrong; `ImageResizer` already preserves P3. **Skip Step 3.** Commit only the test (without the `fix(...)` portion of the message), under subject `test(resizer): pin Display P3 colorspace preservation`.

**Outcome B — `displayP3Preserved` fails.** The bug is real. Proceed to Step 3.

- [ ] **Step 3 (only if Outcome B): Apply the fix to `Services/ImageResizer.swift`**

The current logic at line 32–35:

```swift
let colorSpace: CGColorSpace = {
    if let cs = image.colorSpace, cs.model == .rgb { return cs }
    return CGColorSpaceCreateDeviceRGB()
}()
```

If the bug is real, it likely means the bitmap context is created with the right colorspace but `ctx.draw(image, ...)` is silently converting. Investigate by inspecting the post-draw `ctx.colorSpace` vs `makeImage().colorSpace`. The fix may involve setting `bitmapInfo` to match the source's bits/component or using a wider bitmap format. This should be researched at execution time — do not pre-commit a fix that might be wrong.

If Outcome B and the fix is non-trivial (>30 lines or involves new bitmap-format logic), report DONE_WITH_CONCERNS and escalate. The orchestrator can then split this into a dedicated phase.

- [ ] **Step 4: Run, verify**

Run: `swift test`
Expected: all green.

- [ ] **Step 5: Commit**

If Outcome A:
```bash
git add Tests/CodecTests/ColorProfilePreservationTests.swift
git commit -m "$(cat <<'EOF'
test(resizer): pin Display P3 colorspace preservation through resize

The party-mode reviewer flagged this as a potential bug. The probe shows
the existing logic at ImageResizer.swift:32-35 already preserves the
input colorspace when it's RGB — so the test here serves as a regression
guard rather than triggering a fix.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

If Outcome B:
```bash
git add Tests/CodecTests/ColorProfilePreservationTests.swift Services/ImageResizer.swift
git commit -m "$(cat <<'EOF'
fix(resizer): preserve Display P3 colorspace through resize

[describe the actual fix found at execution time]

Probe test pins both the active and inactive paths for P3 round-trip.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section F — pngquant + SVG

---

### Task 15: PNGQuantizer — happy path + missing-binary fallback

**Why:** PNG `q < 100` runs through pngquant subprocess. Two failure modes need testing: (a) happy path produces a smaller PNG, (b) when binary is missing, the call throws a typed `ConversionError.encodeFailed(.png, ...)` instead of hanging or producing silent garbage.

The "missing binary" case is hard to test deterministically without controlling `Bundle.main` lookup. Approach: gate the happy-path test on `IMAGECRC_TEST_REQUIRE_PNGQUANT=1` env var (off by default in dev for hermeticity; on in Phase 6 CI where `brew install pngquant` runs first). The missing-binary path is documentable but skipped from automation.

**Files:**
- Create: `Tests/CodecTests/PNGQuantizerTests.swift`

- [ ] **Step 1: Write the suite**

```swift
// Tests/CodecTests/PNGQuantizerTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("PNGQuantizer")
struct PNGQuantizerTests {
    /// Skipped unless IMAGECRC_TEST_REQUIRE_PNGQUANT=1 is set, since the
    /// subprocess depends on a system-installed binary not present on every
    /// developer machine. Phase 6 CI sets the env var after `brew install pngquant`.
    @Test("pngquant produces a smaller PNG for a non-trivial gradient",
          .enabled(if: ProcessInfo.processInfo.environment["IMAGECRC_TEST_REQUIRE_PNGQUANT"] == "1"))
    func happyPath() async throws {
        let src = SyntheticImage.gradient(width: 256, height: 256)
        let lossless = try PNGEncoder.encode(image: src)
        let quantized = try await PNGQuantizer.quantize(pngData: lossless, quality: 70)
        #expect(quantized.count > 0)
        #expect(quantized.count < lossless.count,
                "lossy PNG must be smaller than lossless source for a non-trivial gradient")
        // Sanity: quantized output is still a valid PNG (signature 89 50 4E 47).
        #expect(quantized.starts(with: [0x89, 0x50, 0x4E, 0x47]),
                "pngquant output must remain a valid PNG")
    }
}
```

- [ ] **Step 2: Run**

Run locally without the env var:

```bash
swift test --filter PNGQuantizer
```

Expected: the test reports as skipped (Swift Testing displays skipped tests but doesn't count them as failures).

Run with the env var (only if you have pngquant installed via `brew install pngquant`):

```bash
IMAGECRC_TEST_REQUIRE_PNGQUANT=1 swift test --filter PNGQuantizer
```

Expected: 1/1 pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/PNGQuantizerTests.swift
git commit -m "$(cat <<'EOF'
test(codec): PNGQuantizer happy path gated on IMAGECRC_TEST_REQUIRE_PNGQUANT

The pngquant subprocess depends on a system binary not present on every
developer machine. Gate the round-trip test on an env var so swift test
stays hermetic in dev but Phase 6 CI (which installs pngquant first)
runs it.

The missing-binary failure mode is documented but not automated; testing
it deterministically would require shimming Bundle.main lookups.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: SVG decode test

**Why:** SVG goes through `SVGDecoder` (NSImage rasterization), not ImageIO. Verify a minimal `<svg>` document decodes to a non-zero CGImage.

**Files:**
- Create: `Tests/CodecTests/SVGDecoderTests.swift`

- [ ] **Step 1: Write the suite**

```swift
// Tests/CodecTests/SVGDecoderTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("SVGDecoder")
struct SVGDecoderTests {
    private static let minimalSVG = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="64" height="48" viewBox="0 0 64 48">
      <rect x="0" y="0" width="64" height="48" fill="red"/>
      <circle cx="32" cy="24" r="16" fill="blue"/>
    </svg>
    """

    @Test("minimal SVG with explicit width/height decodes to non-zero CGImage")
    func minimalSVGDecodes() throws {
        let tmp = try TempDirectory()
        let url = tmp.url.appendingPathComponent("test.svg")
        try Self.minimalSVG.write(to: url, atomically: true, encoding: .utf8)

        let decoded = try SVGDecoder.decode(url: url)
        #expect(decoded.width > 0)
        #expect(decoded.height > 0)
        // NSImage may decide on its own raster size; we only pin "non-zero".
        // Pinning exact dims would couple to NSImage internals.
    }

    @Test("ImageDecoder.decode dispatches SVG to SVGDecoder")
    func dispatchSVG() throws {
        let tmp = try TempDirectory()
        let url = tmp.url.appendingPathComponent("test.svg")
        try Self.minimalSVG.write(to: url, atomically: true, encoding: .utf8)

        let file = try #require(ImageFile(url: url))
        #expect(file.inputFormat == .svg)
        let decoded = try ImageDecoder.decode(file: file)
        #expect(decoded.width > 0)
        #expect(decoded.height > 0)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter SVG`
Expected: 2/2.

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/SVGDecoderTests.swift
git commit -m "$(cat <<'EOF'
test(codec): SVG decode via NSImage rasterization

Minimal SVG with explicit width/height decodes to a non-zero CGImage via
SVGDecoder. Also pin that ImageDecoder.decode dispatches .svg input to
SVGDecoder rather than ImageIODecoder.

Dimensions are checked for "non-zero" only — pinning exact pixel counts
would couple to NSImage's raster decisions.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 Done When

- [ ] `swift test` exits 0
- [ ] At least 50 tests across at least 12 suites pass (Phase 1 left 28/9; this phase adds ~25+ tests across ~5 new suites)
- [ ] No SwiftPM warnings beyond pre-existing two
- [ ] EXIF orientation 6 and 8 produce dim-swapped output from `ImageIODecoder`
- [ ] Display P3 input either round-trips through `ImageResizer` (if the existing logic was already correct) OR is fixed in the same commit as the probe test
- [ ] pngquant happy-path is gated on `IMAGECRC_TEST_REQUIRE_PNGQUANT=1` and passes when set
- [ ] SVG decode produces non-zero output
- [ ] User approval to write Phase 3 plan

**Deliberately NOT covered in Phase 2** (acknowledged scope gaps):
- `OutputFormat.fileExtension` / `isLossless` / `displayName` — the original Phase 1 Task 7 suite was deleted in commit `40ae2d7` per the party-mode review's Path A as "trivial property-getter tests with refactor-tax > bug-prevention value". Only `OutputFormat.utType` is covered here (Task 6) because that exercises a runtime UTType registry lookup that can drift across macOS versions. Rationale documented in `40ae2d7` commit body.
- Chromaticity-level color preservation — Task 14 is a smoke-only probe of colorspace *name* round-trip; pixel-level wide-gamut precision is a Phase 4 concern.
- pngquant missing-binary deterministic test — would require shimming `Bundle.main` lookup; documented in Task 14's commit but skipped from automation.

---

## Pause points

The user opted to do all phases on `tests/phase-1` and merge to `main` as a single batch later. Natural pause points within Phase 2 if needed:

- **After Section B (Tasks 1–7):** all sweep done; codec work is a separate logical unit
- **After Section D (Tasks 1–12):** all round-trip green; probe-then-fix is a deliberate production change that the user may want to review before signing off
- **After Section E (Tasks 1–14):** the only remaining work is pngquant and SVG, both small

---

## Self-review

**Spec coverage:** every Phase 2 commitment from the original roadmap (codec round-trip, EXIF orientation probe-then-fix, color profile probe-then-fix, pngquant gated, fixtures) plus every Lens 2 + party-mode minor finding has a task. The fixtures-on-disk plan from the original roadmap is deliberately replaced with synthesised in-test fixtures, with rationale documented in the header.

**Placeholder scan:** Section E Task 14 contains a conditional fix ("only if Outcome B"). The fix details are deliberately deferred to execution time because the bug may not exist — applying a speculative fix is worse than verifying the probe first. Documented as "not a placeholder, but a probe-first decision point".

**Type consistency:** `ImageFile(url:)` is a failable initialiser — covered by `try #require`. `ImageDecoder.decode(file:)` is throwing-sync — used directly. `ImageEncoder.encode(image:to:quality:)` is `async throws` — Phase 2 doesn't use it (each per-format encoder is called directly). `PNGQuantizer.quantize(pngData:quality:)` is `async throws` — covered. All signatures verified against the actual source files in `Services/Encoders/` and `Services/Decoders/`.

**Deferred decisions:**
- Color profile fix shape (Task 14, Outcome B) — pending probe result
- pngquant missing-binary automated test — documented but skipped (deterministic shim is more work than the test is worth in Phase 2)
