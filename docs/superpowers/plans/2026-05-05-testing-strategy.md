# ImageCRC Full Functional Testing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cover every feature and functional path of ImageCRC with automated tests — pure logic, codec round-trip, concurrency/cancellation, perceptual quality, and UI smoke — wired into CI.

**Architecture:** Six sequential phases. Phase 1 lays the test infrastructure and proves the pure-logic surface. Phases 2–6 build on it (fixtures, then concurrency, then perceptual quality, then XCUITest, then CI). Each phase produces independently-mergeable, green tests. Refactors needed for testability (`Converter` and `FileChooser` protocols) land in Phase 3 only when they unlock the VM tests.

**Tech Stack:** Swift 5.10, Swift Testing framework (`import Testing`, `@Test`, `#expect`), XCTest+XCUITest (UI only), libwebp via SwiftPM, ImageIO, pngquant subprocess, GitHub Actions for CI.

> **User policy:** Per spooosh's standing preference, never run `git commit` without explicit approval. Each task ends with a commit *snippet* the user runs manually after reviewing the diff. The executor stops after green tests and reports.

---

## Phase Overview

| # | Phase | Exit Criteria | Est | Open Holes Addressed |
|---|-------|---------------|-----|----------------------|
| 1 | Pure unit tests + test infra | Green coverage of `OutputPlanner`, `ImageResizer`, `FilenameResolver`, settings models, formats, summary math; helpers (`TempDirectory`, `SyntheticImage`) live | 1–2 days | none yet |
| 2 | Codec round-trip + fixtures | `Tests/Fixtures/Images/` populated; round-trip green for JPEG/PNG-lossless/WebP/AVIF/HEIC/SVG; `pngquant` ветка под env-флагом; **EXIF orientation** probe + fix; **color profile** probe + fix | 2–3 days | EXIF, color profiles |
| 3 | Concurrency + cancellation + VM | `ImageConverter` integration tests (batch, cancel в каждой фазе, монотонность счётчика); `Converter` и `FileChooser` протоколы + fakes; VM transition tests | 2–3 days | premultiplied alpha (если всплывёт) |
| 4 | Perceptual quality (SSIM/PSNR) | Golden snapshots для матрицы `format × q={20,50,80,100}`; детерминированный pngquant; tolerance-based assertions | 2–3 days | none |
| 5 | UI smoke (XCUITest) | Отдельный XCUITest target в `project.yml`; happy path: drop файла → start → completion sheet; accessibility identifiers расставлены | 1–2 days | none |
| 6 | CI | GitHub Actions macos-14: `brew install pngquant` + `swift test` + `xcodebuild test` (для XCUITest) | 1 day | none |

**Phases 2–6 will receive their own detailed plans** under `docs/superpowers/plans/` once their predecessor lands. This document fully details Phase 1 only; later phases have outlines (key tasks + exit criteria) below.

---

## File Structure (full target)

```
Tests/
├── UnitTests/                       # Phase 1 — pure, no fixtures, no subprocess
│   ├── Support/
│   │   ├── TempDirectory.swift      # RAII tmp dir helper
│   │   └── SyntheticImage.swift     # CGImage builders for resize tests
│   ├── ConversionSettingsTests.swift
│   ├── ConversionSummaryTests.swift
│   ├── FilenameResolverTests.swift
│   ├── ImageResizerTests.swift
│   ├── InputFormatTests.swift
│   ├── OutputFormatTests.swift
│   ├── OutputPlannerTests.swift
│   └── ResizeSettingsTests.swift
├── CodecTests/                      # Phase 2 — needs fixtures
│   └── (round-trip per format)
├── IntegrationTests/                # Phase 3 — full ImageConverter + VM
│   └── (batch, cancel, VM events)
├── GoldenTests/                     # Phase 4 — perceptual snapshots
│   ├── Support/SSIM.swift
│   └── (per format × quality)
├── UITests/                         # Phase 5 — XCUITest, project.yml only
│   └── HappyPathTests.swift
└── Fixtures/
    ├── Images/                      # Phase 2
    │   ├── checker-64.png
    │   ├── photo-64.jpg
    │   └── ... (one per format)
    └── Snapshots/                   # Phase 4
        └── ... (golden output bytes / SSIM baselines)
```

`Package.swift` test target after Phase 1 stays at `sources: ["UnitTests"]`. Phase 2 expands it to add `CodecTests` and a `resources: [.copy("Fixtures")]` declaration.

---

# Phase 1 — Pure Unit Tests + Test Infrastructure

**Already done:** `Package.swift` and `project.yml` have the test target wired; one smoke test (`PackageWiringTests.swift`) is green. This phase replaces that placeholder with real coverage.

**Phase 1 scope:** No fixtures. No subprocess. No concurrency beyond `async let`. No UI. Synthetic `CGImage` only, built via `CGContext`.

**Files affected by Phase 1:**

- Create:
  - `Tests/UnitTests/Support/TempDirectory.swift`
  - `Tests/UnitTests/Support/SyntheticImage.swift`
  - `Tests/UnitTests/OutputPlannerTests.swift`
  - `Tests/UnitTests/ConversionSettingsTests.swift`
  - `Tests/UnitTests/ResizeSettingsTests.swift`
  - `Tests/UnitTests/InputFormatTests.swift`
  - `Tests/UnitTests/OutputFormatTests.swift`
  - `Tests/UnitTests/FilenameResolverTests.swift`
  - `Tests/UnitTests/ImageResizerTests.swift`
  - `Tests/UnitTests/ConversionSummaryTests.swift`
- Delete: `Tests/UnitTests/PackageWiringTests.swift` (subsumed)

---

### Task 1: Test infrastructure — `TempDirectory` helper

Создаёт уникальный временный каталог в `FileManager.default.temporaryDirectory`, кладёт его в RAII-обёртку, чистит на `deinit`. Используется в `FilenameResolverTests` (Phase 1) и в Phase 2/3.

**Files:**
- Create: `Tests/UnitTests/Support/TempDirectory.swift`
- Test: covered indirectly by Task 7 (`FilenameResolverTests`)

- [ ] **Step 1: Write the helper**

```swift
// Tests/UnitTests/Support/TempDirectory.swift
import Foundation

/// RAII wrapper for a unique temporary directory under
/// `FileManager.default.temporaryDirectory`. Removes the directory on `deinit`.
/// Construction can fail if the FS rejects the create — the initialiser throws.
final class TempDirectory {
    let url: URL

    init(prefix: String = "imagecrc-test") throws {
        let base = FileManager.default.temporaryDirectory
        let unique = "\(prefix)-\(UUID().uuidString)"
        self.url = base.appendingPathComponent(unique, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --target ImageCRCTests`
Expected: build succeeds, no warnings.

- [ ] **Step 3: Commit (after user approval)**

```bash
git add Tests/UnitTests/Support/TempDirectory.swift
git commit -m "test(infra): add TempDirectory RAII helper"
```

---

### Task 2: Test infrastructure — `SyntheticImage` helper

Строит solid-color `CGImage` нужного размера с указанным `colorSpace`. Используется в `ImageResizerTests`.

**Files:**
- Create: `Tests/UnitTests/Support/SyntheticImage.swift`

- [ ] **Step 1: Write the helper**

```swift
// Tests/UnitTests/Support/SyntheticImage.swift
import CoreGraphics
import Foundation

enum SyntheticImage {
    /// Solid-colour RGBA premultiplied CGImage of the given dimensions.
    /// Crashes deliberately on failure — these are test-only constructors and
    /// silent fallbacks would mask wiring bugs.
    static func solid(
        width: Int,
        height: Int,
        red: CGFloat = 1,
        green: CGFloat = 0,
        blue: CGFloat = 0,
        alpha: CGFloat = 1,
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
            fatalError("SyntheticImage: failed to create CGContext (\(width)x\(height))")
        }
        ctx.setFillColor(red: red, green: green, blue: blue, alpha: alpha)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage() else {
            fatalError("SyntheticImage: CGContext.makeImage() returned nil")
        }
        return image
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build --target ImageCRCTests`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/Support/SyntheticImage.swift
git commit -m "test(infra): add SyntheticImage CGImage helper"
```

---

### Task 3: Tests for `OutputPlanner.plan(for:selected:)`

Тестируем все комбинации `InputFormat × OutputFormat`. Особое внимание: `.sameAsOrigin + .svg` → `.copy`, всё остальное — `.encode(...)`.

**Files:**
- Create: `Tests/UnitTests/OutputPlannerTests.swift`

- [ ] **Step 1: Write the failing test (test-first; impl exists)**

```swift
// Tests/UnitTests/OutputPlannerTests.swift
import Testing
@testable import ImageCRC

@Suite("OutputPlanner")
struct OutputPlannerTests {
    @Test("Direct output formats always encode to that format regardless of input")
    func directFormats() {
        let inputs: [InputFormat] = [.jpeg, .png, .svg, .webp, .avif, .heic]
        let cases: [(OutputFormat, EncoderFormat)] = [
            (.jpeg, .jpeg),
            (.png,  .png),
            (.webp, .webp),
            (.avif, .avif),
        ]
        for input in inputs {
            for (selected, expected) in cases {
                let plan = OutputPlanner.plan(for: input, selected: selected)
                #expect(plan == .encode(expected),
                        "Expected \(expected) for input=\(input) selected=\(selected), got \(plan)")
            }
        }
    }

    @Test("sameAsOrigin maps each raster input to the matching encoder")
    func sameAsOriginRaster() {
        let cases: [(InputFormat, EncoderFormat)] = [
            (.jpeg, .jpeg),
            (.png,  .png),
            (.webp, .webp),
            (.avif, .avif),
            (.heic, .heic),
        ]
        for (input, expected) in cases {
            let plan = OutputPlanner.plan(for: input, selected: .sameAsOrigin)
            #expect(plan == .encode(expected))
        }
    }

    @Test("sameAsOrigin + SVG resolves to a verbatim copy")
    func sameAsOriginSVG() {
        let plan = OutputPlanner.plan(for: .svg, selected: .sameAsOrigin)
        #expect(plan == .copy)
    }
}
```

Note: `FileOutputPlan` and `EncoderFormat` are `Hashable`/`Equatable`-by-synthesis since both are pure enums; `==` works.

- [ ] **Step 2: Run the test**

Run: `swift test --filter OutputPlannerTests`
Expected: 3 tests pass. If any fails — that's a bug in `OutputPlanner.plan`; investigate before continuing.

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/OutputPlannerTests.swift
git commit -m "test(planner): cover full OutputPlanner combinatorics"
```

---

### Task 4: Tests for `ConversionSettings`

Тестируем `normalizedQuality` (clamp + scale), `isReady` (зависит от `outputDirectory`), и значения `default`.

**Files:**
- Create: `Tests/UnitTests/ConversionSettingsTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/UnitTests/ConversionSettingsTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("ConversionSettings")
struct ConversionSettingsTests {
    @Test("default has documented baseline")
    func defaultBaseline() {
        let s = ConversionSettings.default
        #expect(s.quality == 80)
        #expect(s.outputFormat == .jpeg)
        #expect(s.resize == ResizeSettings())
        // outputDirectory may be nil if the user has no Pictures dir,
        // but on a normal macOS install it should resolve.
        #expect(s.outputDirectory?.lastPathComponent == "ImageCRC")
    }

    @Test("normalizedQuality clamps and scales")
    func normalizedQuality() {
        var s = ConversionSettings.default
        s.quality = 0;   #expect(s.normalizedQuality == 0.0)
        s.quality = 50;  #expect(s.normalizedQuality == 0.5)
        s.quality = 100; #expect(s.normalizedQuality == 1.0)
        s.quality = 150; #expect(s.normalizedQuality == 1.0)
        s.quality = -1;  #expect(s.normalizedQuality == 0.0)
    }

    @Test("isReady mirrors outputDirectory presence")
    func isReady() {
        var s = ConversionSettings.default
        s.outputDirectory = nil
        #expect(s.isReady == false)
        s.outputDirectory = URL(fileURLWithPath: "/tmp")
        #expect(s.isReady == true)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter ConversionSettingsTests`
Expected: 3 pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/ConversionSettingsTests.swift
git commit -m "test(settings): cover ConversionSettings clamp, defaults, isReady"
```

---

### Task 5: Tests for `ResizeSettings`

`isActive` triggers when *any* dimension is set; mode default; raw equality for `Hashable`.

**Files:**
- Create: `Tests/UnitTests/ResizeSettingsTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/UnitTests/ResizeSettingsTests.swift
import Testing
@testable import ImageCRC

@Suite("ResizeSettings")
struct ResizeSettingsTests {
    @Test("default is inactive with fit mode and no enlarge")
    func defaults() {
        let r = ResizeSettings()
        #expect(r.isActive == false)
        #expect(r.mode == .fit)
        #expect(r.width == nil)
        #expect(r.height == nil)
        #expect(r.enlarge == false)
    }

    @Test("isActive flips once any dimension is set")
    func isActive() {
        var r = ResizeSettings()
        r.width = 100
        #expect(r.isActive)
        r.width = nil
        r.height = 100
        #expect(r.isActive)
        r.width = 200
        r.height = 200
        #expect(r.isActive)
        r.width = nil
        r.height = nil
        #expect(r.isActive == false)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter ResizeSettingsTests`
Expected: 2 pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/ResizeSettingsTests.swift
git commit -m "test(settings): cover ResizeSettings defaults and isActive"
```

---

### Task 6: Tests for `InputFormat`

`init?(url:)` от расширения, регистрозависимость, неподдерживаемые расширения, `allowedExtensions` set integrity.

**Files:**
- Create: `Tests/UnitTests/InputFormatTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/UnitTests/InputFormatTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("InputFormat")
struct InputFormatTests {
    @Test("init from URL maps each supported extension")
    func mapsExtensions() {
        let cases: [(String, InputFormat)] = [
            ("photo.jpg",  .jpeg),
            ("photo.JPG",  .jpeg),
            ("photo.jpeg", .jpeg),
            ("img.png",    .png),
            ("img.PNG",    .png),
            ("vec.svg",    .svg),
            ("anim.webp",  .webp),
            ("shot.avif",  .avif),
            ("phone.heic", .heic),
        ]
        for (name, expected) in cases {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            #expect(InputFormat(url: url) == expected, "for \(name)")
        }
    }

    @Test("init returns nil for unsupported extensions")
    func rejectsUnsupported() {
        for ext in ["bmp", "tiff", "gif", "ico", "pdf", ""] {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            #expect(InputFormat(url: url) == nil, "should reject .\(ext)")
        }
    }

    @Test("allowedExtensions covers exactly the recognized set")
    func allowedExtensionsSet() {
        let expected: Set<String> = ["jpg", "jpeg", "png", "svg", "webp", "avif", "heic"]
        #expect(InputFormat.allowedExtensions == expected)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter InputFormatTests`
Expected: 3 pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/InputFormatTests.swift
git commit -m "test(formats): cover InputFormat URL parsing and allowed set"
```

---

### Task 7: Tests for `OutputFormat`

`fileExtension`, `isLossless`, `displayName`, `utType` non-nil.

**Files:**
- Create: `Tests/UnitTests/OutputFormatTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/UnitTests/OutputFormatTests.swift
import Testing
@testable import ImageCRC

@Suite("OutputFormat")
struct OutputFormatTests {
    @Test("fileExtension matches each format")
    func fileExtensions() {
        #expect(OutputFormat.jpeg.fileExtension == "jpg")
        #expect(OutputFormat.png.fileExtension == "png")
        #expect(OutputFormat.webp.fileExtension == "webp")
        #expect(OutputFormat.avif.fileExtension == "avif")
        #expect(OutputFormat.sameAsOrigin.fileExtension == "")
    }

    @Test("isLossless only for PNG")
    func isLossless() {
        #expect(OutputFormat.png.isLossless)
        for f in [OutputFormat.jpeg, .webp, .avif, .sameAsOrigin] {
            #expect(f.isLossless == false, "\(f) should not be lossless")
        }
    }

    @Test("displayName is non-empty for every format")
    func displayNamesNonEmpty() {
        for f in OutputFormat.allCases {
            #expect(f.displayName.isEmpty == false, "\(f).displayName must not be empty")
        }
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter OutputFormatTests`
Expected: 3 pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/OutputFormatTests.swift
git commit -m "test(formats): cover OutputFormat extensions, isLossless, displayName"
```

---

### Task 8: Tests for `FilenameResolver`

Базовый случай, коллизия имён (один и тот же baseName → ` (1)`, ` (2)`), параллельный resolve через `async let` (актор сериализует), reset() очищает reserved set, существующие файлы на диске обходятся.

**Files:**
- Create: `Tests/UnitTests/FilenameResolverTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/UnitTests/FilenameResolverTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("FilenameResolver")
struct FilenameResolverTests {
    @Test("first resolve uses base name as-is")
    func firstResolveBare() async throws {
        let tmp = try TempDirectory()
        let r = FilenameResolver()
        let url = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: "jpg")
        #expect(url.lastPathComponent == "photo.jpg")
        #expect(url.deletingLastPathComponent().path == tmp.url.path)
    }

    @Test("repeated resolves disambiguate sequentially")
    func collisionInMemory() async throws {
        let tmp = try TempDirectory()
        let r = FilenameResolver()
        let a = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: "jpg")
        let b = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: "jpg")
        let c = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: "jpg")
        #expect(a.lastPathComponent == "photo.jpg")
        #expect(b.lastPathComponent == "photo (1).jpg")
        #expect(c.lastPathComponent == "photo (2).jpg")
    }

    @Test("existing on-disk files are skipped")
    func collisionOnDisk() async throws {
        let tmp = try TempDirectory()
        let preexisting = tmp.url.appendingPathComponent("photo.jpg")
        try Data().write(to: preexisting)
        let r = FilenameResolver()
        let url = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: "jpg")
        #expect(url.lastPathComponent == "photo (1).jpg")
    }

    @Test("parallel resolves never return the same path")
    func parallelUnique() async throws {
        let tmp = try TempDirectory()
        let r = FilenameResolver()
        async let a = r.resolve(outputDirectory: tmp.url, baseName: "p", ext: "png")
        async let b = r.resolve(outputDirectory: tmp.url, baseName: "p", ext: "png")
        async let c = r.resolve(outputDirectory: tmp.url, baseName: "p", ext: "png")
        async let d = r.resolve(outputDirectory: tmp.url, baseName: "p", ext: "png")
        let urls = await [a, b, c, d]
        let paths = urls.map { $0.path }
        #expect(Set(paths).count == 4, "all parallel resolves must yield unique paths; got \(paths)")
    }

    @Test("reset() releases reserved names")
    func resetClears() async throws {
        let tmp = try TempDirectory()
        let r = FilenameResolver()
        _ = await r.resolve(outputDirectory: tmp.url, baseName: "x", ext: "png")
        await r.reset()
        let after = await r.resolve(outputDirectory: tmp.url, baseName: "x", ext: "png")
        #expect(after.lastPathComponent == "x.png")
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter FilenameResolverTests`
Expected: 5 pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/FilenameResolverTests.swift
git commit -m "test(resolver): cover FilenameResolver collisions, parallel, reset"
```

---

### Task 9: Tests for `ImageResizer` — no-op cases

Когда `isActive == false` (нет width/height), либо размеры совпадают с input, либо колапс в zero — на выходе тот же `CGImage` (или хотя бы тех же размеров).

**Files:**
- Create: `Tests/UnitTests/ImageResizerTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/UnitTests/ImageResizerTests.swift
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("ImageResizer — no-op")
struct ImageResizerNoopTests {
    @Test("inactive settings return the input unchanged")
    func inactivePassesThrough() {
        let img = SyntheticImage.solid(width: 200, height: 100)
        let out = ImageResizer.resize(img, settings: ResizeSettings())
        // Reference equality: when settings inactive, the impl returns `image` directly.
        #expect(out === img)
    }

    @Test("explicit dimensions equal to source produce a no-op")
    func samesizeNoop() {
        let img = SyntheticImage.solid(width: 200, height: 100)
        var s = ResizeSettings()
        s.width = 200
        s.height = 100
        s.mode = .fit
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 200 && out.height == 100)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter ImageResizerNoopTests`
Expected: 2 pass.

- [ ] **Step 3: Commit (defer until Tasks 10–11 also land — see Task 11 for full commit)**

---

### Task 10: Tests for `ImageResizer` — fit mode + no-upscale guard

Fit downscales by min(sx, sy). With `enlarge == false` the scale is clamped to ≤ 1, so a tiny source target can't produce upscale.

**Files:**
- Modify: `Tests/UnitTests/ImageResizerTests.swift` (append suite)

- [ ] **Step 1: Append the suite**

```swift
@Suite("ImageResizer — fit")
struct ImageResizerFitTests {
    @Test("fit picks the smaller of the two scale factors")
    func fitDownscaleByMin() {
        // 400x200 source, target 100x100 fit → scale = min(0.25, 0.5) = 0.25
        // → output 100x50
        let img = SyntheticImage.solid(width: 400, height: 200)
        var s = ResizeSettings()
        s.width = 100
        s.height = 100
        s.mode = .fit
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 100)
        #expect(out.height == 50)
    }

    @Test("fit with only width set scales by width ratio")
    func fitWidthOnly() {
        let img = SyntheticImage.solid(width: 400, height: 200)
        var s = ResizeSettings()
        s.width = 200
        s.mode = .fit
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 200)
        #expect(out.height == 100)
    }

    @Test("enlarge=false caps scale at 1.0 so upscale targets become no-op")
    func noUpscaleGuard() {
        let img = SyntheticImage.solid(width: 100, height: 100)
        var s = ResizeSettings()
        s.width = 400
        s.height = 400
        s.mode = .fit
        s.enlarge = false
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 100, "enlarge=false must not upscale")
        #expect(out.height == 100)
    }

    @Test("enlarge=true allows scale > 1.0")
    func enlargeAllowsUpscale() {
        let img = SyntheticImage.solid(width: 100, height: 100)
        var s = ResizeSettings()
        s.width = 200
        s.height = 200
        s.mode = .fit
        s.enlarge = true
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 200)
        #expect(out.height == 200)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter ImageResizerFitTests`
Expected: 4 pass.

---

### Task 11: Tests for `ImageResizer` — fill mode + centered crop

Fill scales by `max(sx, sy)`, then crops to `min(intermediate, target)` centered. With odd sizes draw offset is `(target - intermediate) / 2` in integer math.

**Files:**
- Modify: `Tests/UnitTests/ImageResizerTests.swift` (append suite)

- [ ] **Step 1: Append the suite**

```swift
@Suite("ImageResizer — fill")
struct ImageResizerFillTests {
    @Test("fill with both dims crops to the smaller-of-(intermediate, target)")
    func fillCropsToTarget() {
        // 400x200 → target 100x100 fill → scale = max(0.25, 0.5) = 0.5
        // → intermediate 200x100; output = min(200,100) x min(100,100) = 100x100
        let img = SyntheticImage.solid(width: 400, height: 200)
        var s = ResizeSettings()
        s.width = 100
        s.height = 100
        s.mode = .fill
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 100)
        #expect(out.height == 100)
    }

    @Test("fill with one dim only behaves like fit")
    func fillWithOneDim() {
        let img = SyntheticImage.solid(width: 400, height: 200)
        var s = ResizeSettings()
        s.height = 50
        s.mode = .fill
        let out = ImageResizer.resize(img, settings: s)
        // Without both targets, fill geometry path is bypassed → behaves like fit.
        #expect(out.width == 100)
        #expect(out.height == 50)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter "ImageResizer"`
Expected: all 8 ImageResizer tests pass (Tasks 9 + 10 + 11).

- [ ] **Step 3: Commit (covers Tasks 9, 10, 11)**

```bash
git add Tests/UnitTests/ImageResizerTests.swift
git commit -m "test(resizer): cover fit/fill, no-upscale guard, centered crop"
```

---

### Task 12: Tests for `ConversionSummary`

`totalOriginalBytes`, `totalOutputBytes`, `savingsRatio`, `wasCancelled`. Игнорирование failures/cancelled из total bytes.

**Files:**
- Create: `Tests/UnitTests/ConversionSummaryTests.swift`

- [ ] **Step 1: Write the test**

```swift
// Tests/UnitTests/ConversionSummaryTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("ConversionSummary")
struct ConversionSummaryTests {
    private func successResult(orig: Int64, out: Int64) -> ConversionResult {
        ConversionResult(
            id: UUID(),
            source: URL(fileURLWithPath: "/tmp/in.jpg"),
            outcome: .success(
                outputURL: URL(fileURLWithPath: "/tmp/out.jpg"),
                originalBytes: orig,
                outputBytes: out
            )
        )
    }

    @Test("totalOriginalBytes and totalOutputBytes sum only successes")
    func totals() {
        let summary = ConversionSummary(
            total: 3,
            successes: [successResult(orig: 1000, out: 400),
                        successResult(orig: 2000, out: 600)],
            failures: [],
            cancelled: 0,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        #expect(summary.totalOriginalBytes == 3000)
        #expect(summary.totalOutputBytes == 1000)
    }

    @Test("savingsRatio is 1 - out/orig")
    func savingsRatioComputed() {
        let summary = ConversionSummary(
            total: 1,
            successes: [successResult(orig: 1000, out: 250)],
            failures: [],
            cancelled: 0,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        let ratio = try! #require(summary.savingsRatio)
        #expect(abs(ratio - 0.75) < 1e-9)
    }

    @Test("savingsRatio is nil when no successes")
    func savingsRatioNilWhenEmpty() {
        let summary = ConversionSummary(
            total: 0,
            successes: [],
            failures: [],
            cancelled: 0,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        #expect(summary.savingsRatio == nil)
    }

    @Test("wasCancelled mirrors cancelled > 0")
    func wasCancelled() {
        let s0 = ConversionSummary(total: 1, successes: [], failures: [], cancelled: 0,
                                   outputDirectory: URL(fileURLWithPath: "/tmp"))
        let s1 = ConversionSummary(total: 1, successes: [], failures: [], cancelled: 1,
                                   outputDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(s0.wasCancelled == false)
        #expect(s1.wasCancelled == true)
    }
}
```

- [ ] **Step 2: Run**

Run: `swift test --filter ConversionSummaryTests`
Expected: 4 pass.

- [ ] **Step 3: Commit**

```bash
git add Tests/UnitTests/ConversionSummaryTests.swift
git commit -m "test(summary): cover ConversionSummary totals, savingsRatio, wasCancelled"
```

---

### Task 13: Cleanup — remove `PackageWiringTests.swift`

Покрытие из smoke-теста полностью перенесено в `ConversionSettingsTests`. Удаляем дубликат.

**Files:**
- Delete: `Tests/UnitTests/PackageWiringTests.swift`

- [ ] **Step 1: Delete the file**

Run: `rm Tests/UnitTests/PackageWiringTests.swift`

- [ ] **Step 2: Run the full test suite**

Run: `swift test`
Expected output (counts approximate, structure exact):

```
Suite "OutputPlanner" passed
Suite "ConversionSettings" passed
Suite "ResizeSettings" passed
Suite "InputFormat" passed
Suite "OutputFormat" passed
Suite "FilenameResolver" passed
Suite "ImageResizer — no-op" passed
Suite "ImageResizer — fit" passed
Suite "ImageResizer — fill" passed
Suite "ConversionSummary" passed
Test run with 30+ tests in 10 suites passed
```

- [ ] **Step 3: Commit**

```bash
git add -A Tests/UnitTests/PackageWiringTests.swift  # tracks deletion
git commit -m "test: drop placeholder PackageWiringTests, coverage absorbed into model suites"
```

---

## Phase 1 Done When

- [ ] `swift test` exits 0
- [ ] At least 30 tests across 10 suites pass
- [ ] No SwiftPM warnings introduced by test target (pre-existing warnings about `ImageCRC.xcodeproj` exclude and `ImageCRC-0.1.0.dmg` are out of scope)
- [ ] No code outside `Tests/` was modified (Phase 1 is pure-add; refactors live in Phase 3)
- [ ] User approval to write the Phase 2 plan

---

# Phase 2 — Codec Round-Trip + Fixtures (outline)

**Detailed plan written when:** Phase 1 is merged/landed and user gives green light.

**Scope outline:**

- Populate `Tests/Fixtures/Images/` with one minimal file per `InputFormat` (sizes ≤ 64×64 to keep repo light): `checker-64.png`, `photo-64.jpg`, `phone-64.heic`, `anim-64.webp`, `vec-64.svg`, `shot-64.avif`. Generation script in `Scripts/generate-fixtures.sh` so contributors can rebuild.
- Update `Package.swift` test target: add `sources: ["UnitTests", "CodecTests"]` and `resources: [.copy("Fixtures")]`. Mirror in `project.yml`.
- `CodecTests/`:
  - `ImageDecoderTests.swift` — decode each fixture → non-nil CGImage with expected `width × height`.
  - `JPEGEncoderTests.swift`, `PNGEncoderTests.swift` (lossless ветка), `WebPEncoderTests.swift`, `AVIFEncoderTests.swift`, `HEICEncoderTests.swift` — round-trip каждый: synthetic input → encode → decode → compare dimensions + tolerance pixel diff.
  - `RGBABufferTests.swift` — staging для WebP, проверка что premultiplied RGBA bytes валидны.
  - `PNGQuantizerTests.swift` — gated on `pngquant` availability via `#expect`-skip; round-trip lossy PNG decode.
- **EXIF orientation probe**: фикстура `photo-rotated-64.jpg` с EXIF tag 6 (90° CW). Test: после `ImageDecoder.decode` width/height swap'нуты как и должно быть. Expected: **fail at first** — `ImageIODecoder` сейчас не применяет orientation. Fix lives in same phase.
- **Color profile probe**: фикстура `photo-p3-64.heic`. Test: `ImageResizer.resize` с активными настройками сохраняет `colorSpace.name` (если был P3, остаётся P3). Expected: **fail at first** — `ImageResizer` форсит DeviceRGB. Fix.
- Phase 2 done when: every supported format round-trips green, EXIF + color profile fixes landed, fixtures repo'd.

**Estimated tasks:** 12–16 bite-sized.

---

# Phase 3 — Concurrency + Cancellation + VM (outline)

**Refactors required (must land first in this phase):**

1. **`Converter` protocol** — extract from `ImageConverter`:
   ```swift
   protocol Converter: Sendable {
       static func convert(files: [ImageFile], settings: ConversionSettings) -> AsyncStream<ConversionEvent>
   }
   ```
   `ImageConverter` becomes `enum ImageConverter: Converter`. `ConversionViewModel` takes a `Converter.Type` injection (default `ImageConverter.self`).

2. **`FileChooser` protocol** — wrap `NSOpenPanel`:
   ```swift
   protocol FileChooser {
       func chooseDirectory(initial: URL?) -> URL?
       func chooseFiles(allowedTypes: [UTType]) -> [URL]
   }
   ```
   `AppKitFileChooser: FileChooser` for prod, `FakeFileChooser` for tests.

**Test scope:**

- `IntegrationTests/ImageConverterBatchTests.swift`:
  - Batch of 50 synthetic-PNG fixtures → JPEG. All `.success`, `completed == total`, monotonic counter, exactly `total` `.didComplete` events.
  - `outputDirectory == nil` → all `.failure(.outputDirectoryMissing)`, summary terminal, no `.willStart`.
  - Output dir на read-only path (`/dev/null/foo`) → all `.failure(.writeFailed)`.
  - Same input file 100×: `FilenameResolver` produces 100 unique paths.
- `IntegrationTests/ImageConverterCancelTests.swift`:
  - Spawn 50-file job, cancel after first 5 `.didComplete` events. Expect: `successes + failures + cancelled == total`, monotonic counter to 50, summary `wasCancelled == true`.
  - Cancel-before-start variant.
- `IntegrationTests/ConversionViewModelTests.swift`:
  - `FakeConverter` emits scripted events; assert `phase` transitions `idle → running → completed`, `progress` reaches 1.0, `currentFilename` updates on `.willStart`, `summary` set on `.didFinish`.
  - `start()` guarded by `canStart` (no files, no outputDir, already running).
  - `cancel()` cancels job; subsequent `.didFinish` still resets state.
  - `dismissCompletion()` resets to idle.

**Estimated tasks:** 14–18 bite-sized.

---

# Phase 4 — Perceptual Quality (SSIM/PSNR) (outline)

**Scope:**

- `GoldenTests/Support/SSIM.swift` — pure-Swift SSIM implementation over RGBA bytes (no vendor deps). Validate against known reference image pair to anchor the metric.
- For each `(format, quality)` ∈ `{jpeg, png, webp, avif} × {20, 50, 80, 100}`: encode `fixtures/photo-256.jpg` through `ImageEncoder.encode` → decode → compare to source via SSIM. Assert `ssim ≥ baseline[format][q]` with tolerance.
- Baselines stored in `Tests/Fixtures/Snapshots/perceptual-baselines.json`. Initial values established with one run, then frozen; future regressions blocked.
- pngquant determinism: pass `--speed 4` (already does) + `--posterize 0` + fixed seed via `IM_PNGQUANT_DETERMINISTIC=1` env if available; otherwise widen tolerance for PNG `q < 100`.
- Output byte-size sanity bounds: `0 < size < 5 × source` for every cell.

**Estimated tasks:** 8–10 bite-sized.

---

# Phase 5 — UI Smoke (XCUITest) (outline)

**Scope:**

- `project.yml`: add `ImageCRCUITests` target (`type: bundle.ui-testing`, depends on `ImageCRC`). XCUITest cannot run via `swift test`; this target is Xcode-only — invoked in CI via `xcodebuild test`.
- Accessibility identifiers added to key SwiftUI views: `dropZone`, `addFilesButton`, `outputFolderButton`, `qualitySlider`, `formatPicker`, `startButton`, `cancelButton`, `completionSheet`, `dismissButton`.
- `UITests/HappyPathTests.swift`:
  - Launch app with `IM_UI_TEST=1` env → app uses a temp output dir + ships an in-bundle dummy PNG it can pre-load (small `--ui-test-mode` codepath). Open question: do we ship a test-mode hook in the app, or drive via real `NSOpenPanel` automation? Leaning toward env-flag + injected fixture for determinism.
  - Click `addFilesButton` → file appears in list → click `startButton` → wait for `completionSheet` (timeout 30s) → click `dismissButton` → state returns to idle.
- `UITests/CancelFlowTests.swift`:
  - Mid-run cancel button works, completion sheet shows `cancelled > 0`.

**Estimated tasks:** 6–8 bite-sized + small in-app accessibility wiring.

---

# Phase 6 — CI (outline)

**Scope:**

- `.github/workflows/test.yml`:
  ```yaml
  on: [push, pull_request]
  jobs:
    test:
      runs-on: macos-14
      steps:
        - uses: actions/checkout@v4
        - run: brew install pngquant xcodegen
        - run: swift test
        - run: xcodegen generate
        - run: |
            xcodebuild test \
              -project ImageCRC.xcodeproj \
              -scheme ImageCRC \
              -destination 'platform=macOS,arch=arm64'
  ```
- Cache `.build/` and Homebrew between runs (`actions/cache`).
- README badge for build status.
- Upload XCUITest screenshots on failure.

**Estimated tasks:** 4–6 bite-sized.

---

## Self-Review (writing-plans skill checklist)

**Spec coverage:** every functional area named in the QA brief — pure logic, codecs, concurrency, cancellation, perceptual quality, UI smoke, CI — is covered by a phase. Open holes (EXIF orientation, color profiles) explicitly land in Phase 2 with probe-then-fix tasks. Premultiplied alpha hole would surface in Phase 2 codec round-trip; placeholder in Phase 3 if it surfaces later.

**Placeholder scan:** Phase 1 contains zero TBDs, every step has runnable code or commands. Phases 2–6 are deliberately outlines (not bite-sized) — flagged at the top of the document so this is scope, not slop.

**Type consistency:** `EncoderFormat`, `FileOutputPlan`, `InputFormat`, `OutputFormat`, `ResizeSettings`, `ConversionSettings`, `ConversionSummary`, `ConversionResult.Outcome`, `FilenameResolver.resolve(outputDirectory:baseName:ext:)` — all symbols and signatures verified against the actual source files in `Models/`, `Services/`. `ImageResizer.resize` returns `CGImage` (sometimes `===` input). `FilenameResolver` is an `actor` so all calls require `await`.

**Deferred decisions:**
- Phase 5 has an open question about XCUITest hook strategy (in-app test-mode flag vs full UI automation of `NSOpenPanel`). To be resolved when Phase 5 plan is written.
- pngquant determinism in Phase 4 may need investigation; tolerance widening is the safe fallback.
