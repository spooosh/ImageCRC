# ImageCRC Phase 4 — Perceptual Quality + Phase 3 Sweep

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build SSIM/PSNR perceptual-quality metrics in pure Swift, use them to pin codec quality across the format × quality matrix as regression guards, then close three open holes from Phase 3.

**Architecture:** Pure-Swift metrics (no vendor deps, no external libraries). Baselines hard-coded as ranges in test code, not stored in JSON — over-engineering for the regression-detection ROI. Each lossy encoder gets SSIM tests at four quality points (20/50/80/100), with thresholds chosen to catch catastrophic regressions while allowing small encoder drift across macOS minor versions.

**Tech Stack:** Swift 5.10, Swift Testing, `RGBABuffer.make(from:)` for pixel access, no vImage / Accelerate (keeps the metrics readable and portable).

> **User policy:** Per spooosh's standing preference, never run `git commit` without explicit approval. Subagents may commit on `tests/phase-1`. All Phases 1–4 work merges to `main` as one batch when Phase 6 finishes.

---

## Section Overview

| # | Section | Tasks | Goal |
|---|---------|-------|------|
| A | Perceptual metrics | T1–T3 | PSNR + SSIM helpers in `Tests/Support/`; self-tested against known patterns |
| B | Quality regression matrix | T4–T6 | Lossy encoders (JPEG / WebP / HEIC / AVIF) at q ∈ {20, 50, 80, 100} pinned to SSIM ≥ threshold; pngquant gated case |
| C | Phase 3 sweep | T7–T9 | Pixel-level coverage for orientations 2/3/4/5/7; localization-resilient `ConversionError` assertions; output-size sanity bounds |

**Phase 4 done when:**

- `swift test` exits 0 with at least 90 tests across at least 30 suites (Phase 3 left 76/26 + 1 skipped + 1 known issue; this phase adds ~15 tests across ~5 new suites)
- No SwiftPM warnings beyond pre-existing two
- `Tests/Support/PerceptualMetrics.swift` exposes `PSNR` and `SSIM` static functions, both self-tested
- Lossy encoders have SSIM tests at four quality points with explicit thresholds
- Less-common EXIF orientations (2, 3, 4, 5, 7) have at least one sentinel-pixel test each
- `ConversionError` assertions use typed pattern matching where possible, not substring matching against the description string
- Encoder output size invariants pinned (`0 < bytes < 5 × source` for synthetic gradient inputs)
- User approval to write Phase 5 plan

**Estimated time:** 2–3 days. Section A is the most novel work (metric implementation); Sections B–C are mostly mechanical once the metrics exist.

**Deliberately deferred:**
- Real-world fixture testing (camera photos with EXIF + ICC) — not needed for the regression-detection use case; synthetic gradients are sufficient
- pngquant missing-binary deterministic test — would require Bundle.main shimming; permanent gap, documented in Phase 2 commit `31057b3`
- TIFF-dict EXIF fallback verification via manual byte injection — Phase 3 T11's `withKnownIssue` is the chosen accommodation

---

## File structure delta

```
Tests/
├── Support/
│   ├── PerceptualMetrics.swift   # NEW — PSNR + SSIM helpers
│   └── ... (existing)
├── CodecTests/
│   ├── PerceptualQualityTests.swift  # NEW — Section B
│   ├── EncoderSizeTests.swift        # NEW — Section C / T9
│   └── ... (extends EXIFOrientationTests.swift in T7)
├── IntegrationTests/
│   └── ... (extends ImageConverterErrorTests.swift in T8)
└── ... (no other changes)
```

No `Package.swift` / `project.yml` changes — all new files land under existing `Support/` and `CodecTests/` source dirs which are already wired.

---

# Section A — Perceptual metrics

---

### Task 1: PSNR helper

**Why:** PSNR (peak signal-to-noise ratio) is the simpler of the two metrics — sum of squared error per pixel, log-scaled. Land it first; SSIM (T2) reuses the same `RGBABuffer` access pattern.

**Files:**
- Create: `Tests/Support/PerceptualMetrics.swift`

- [ ] **Step 1: Create the file with PSNR**

```swift
// Tests/Support/PerceptualMetrics.swift
import Foundation
@testable import ImageCRC

/// Pure-Swift perceptual-quality metrics over RGBA8 packed buffers
/// (premultipliedLast, byteOrder32Big — the layout produced by
/// RGBABuffer.make(from:)). Used by Phase 4 codec quality regression tests.
enum PerceptualMetrics {
    /// Peak signal-to-noise ratio in decibels. Identical buffers return
    /// `.infinity`. Higher = closer match. Practical scale:
    ///   ≥ 40 dB — visually indistinguishable
    ///   30–40  — perceptible but acceptable lossy
    ///   < 25   — visibly degraded
    /// Computed across RGB channels (alpha ignored).
    static func psnr(_ a: RGBABuffer, _ b: RGBABuffer) -> Double {
        precondition(a.width == b.width && a.height == b.height,
                     "PSNR requires same-size buffers; got \(a.width)x\(a.height) vs \(b.width)x\(b.height)")
        let pixelCount = a.width * a.height
        guard pixelCount > 0 else { return .infinity }

        var sumSquaredError: Double = 0
        for i in 0..<pixelCount {
            let off = i * 4
            let dr = Double(a.bytes[off])     - Double(b.bytes[off])
            let dg = Double(a.bytes[off + 1]) - Double(b.bytes[off + 1])
            let db = Double(a.bytes[off + 2]) - Double(b.bytes[off + 2])
            sumSquaredError += dr * dr + dg * dg + db * db
        }
        let mse = sumSquaredError / Double(pixelCount * 3)
        if mse == 0 { return .infinity }
        return 20.0 * log10(255.0 / sqrt(mse))
    }
}
```

- [ ] **Step 2: Verify build**

Run: `swift build --target ImageCRCTests`
Expected: green.

- [ ] **Step 3: Commit**

```bash
git add Tests/Support/PerceptualMetrics.swift
git commit -m "$(cat <<'EOF'
test(infra): add PSNR helper for perceptual-quality metrics

Pure-Swift PSNR over RGBA8 buffers from RGBABuffer.make(from:). RGB
channels only (alpha ignored). Identical buffers return .infinity;
returns log-scaled dB otherwise.

First of two metrics — SSIM follows in T2. Section B uses both.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: SSIM helper

**Why:** SSIM (structural similarity) is more sensitive to perceptual differences than PSNR — better at catching encoder regressions that change image structure rather than just adding noise. We use a simplified single-window variant computed on luminance.

**Files:**
- Modify: `Tests/Support/PerceptualMetrics.swift` (append SSIM)

- [ ] **Step 1: Append SSIM**

Add to `enum PerceptualMetrics`:

```swift
    /// Simplified single-window SSIM on luminance (BT.601). Returns a value
    /// in [-1, 1]; 1.0 means identical, lower means structurally divergent.
    /// Practical scale for lossy codec output:
    ///   ≥ 0.99 — visually indistinguishable
    ///   0.95–0.99 — slight artifacts, typical q=80 JPEG
    ///   0.85–0.95 — visible degradation, q=50ish
    ///   < 0.80 — heavy compression
    /// Real SSIM uses Gaussian windowing — this single-window variant is
    /// adequate for regression detection but not for absolute quality scoring.
    static func ssim(_ a: RGBABuffer, _ b: RGBABuffer) -> Double {
        precondition(a.width == b.width && a.height == b.height,
                     "SSIM requires same-size buffers; got \(a.width)x\(a.height) vs \(b.width)x\(b.height)")
        let n = a.width * a.height
        guard n > 0 else { return 1.0 }

        // Convert each pixel to BT.601 luminance.
        var aL = [Double](repeating: 0, count: n)
        var bL = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let off = i * 4
            aL[i] = 0.299 * Double(a.bytes[off])
                  + 0.587 * Double(a.bytes[off + 1])
                  + 0.114 * Double(a.bytes[off + 2])
            bL[i] = 0.299 * Double(b.bytes[off])
                  + 0.587 * Double(b.bytes[off + 1])
                  + 0.114 * Double(b.bytes[off + 2])
        }

        let muA = aL.reduce(0, +) / Double(n)
        let muB = bL.reduce(0, +) / Double(n)

        var sigmaASq: Double = 0
        var sigmaBSq: Double = 0
        var sigmaAB: Double = 0
        for i in 0..<n {
            let dA = aL[i] - muA
            let dB = bL[i] - muB
            sigmaASq += dA * dA
            sigmaBSq += dB * dB
            sigmaAB  += dA * dB
        }
        sigmaASq /= Double(n)
        sigmaBSq /= Double(n)
        sigmaAB  /= Double(n)

        // SSIM stabilizing constants for 8-bit input (L = 255):
        // C1 = (0.01 * L)^2, C2 = (0.03 * L)^2
        let c1 = 6.5025      // (0.01 * 255)^2
        let c2 = 58.5225     // (0.03 * 255)^2

        let numerator   = (2 * muA * muB + c1) * (2 * sigmaAB + c2)
        let denominator = (muA * muA + muB * muB + c1) * (sigmaASq + sigmaBSq + c2)
        return numerator / denominator
    }
```

- [ ] **Step 2: Verify build**

Run: `swift build --target ImageCRCTests`
Expected: green.

- [ ] **Step 3: Commit**

```bash
git add Tests/Support/PerceptualMetrics.swift
git commit -m "$(cat <<'EOF'
test(infra): add simplified SSIM on BT.601 luminance

Single-window SSIM (no Gaussian smoothing) over BT.601 luminance.
Adequate for regression detection across format × quality matrix; not
a substitute for full Wang-Bovik SSIM in absolute quality scoring.

Pairs with the PSNR helper from T1.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Self-test the metrics

**Why:** PSNR and SSIM are easy to get subtly wrong (off-by-one in MSE divisor, missed alpha channel, etc.). Pin both with sanity tests against known patterns: identical → max, fully different → low, small noise → mid-high.

**Files:**
- Create: `Tests/CodecTests/PerceptualMetricsTests.swift`

- [ ] **Step 1: Write the suite**

```swift
// Tests/CodecTests/PerceptualMetricsTests.swift
import Foundation
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("Perceptual metrics — self-test")
struct PerceptualMetricsSelfTest {
    @Test("PSNR of identical buffers is +infinity")
    func psnrIdentical() throws {
        let img = SyntheticImage.gradient(width: 64, height: 64)
        let buf = try RGBABuffer.make(from: img)
        let psnr = PerceptualMetrics.psnr(buf, buf)
        #expect(psnr == .infinity)
    }

    @Test("SSIM of identical buffers is 1.0")
    func ssimIdentical() throws {
        let img = SyntheticImage.gradient(width: 64, height: 64)
        let buf = try RGBABuffer.make(from: img)
        let ssim = PerceptualMetrics.ssim(buf, buf)
        #expect(abs(ssim - 1.0) < 1e-9)
    }

    @Test("PSNR of fully inverted buffers is around 7.6 dB")
    func psnrInverted() throws {
        // For each pixel, channel diff is 255. MSE = 255^2 = 65025 per channel.
        // PSNR = 20 * log10(255 / 255) = 0 dB. Wait — PSNR = 20*log10(255/sqrt(MSE))
        // = 20*log10(255/255) = 0 dB exactly when buffers are fully complementary.
        // But our channel-summed MSE is 65025*3/3 = 65025 → sqrt = 255 → PSNR = 0.
        let red = try RGBABuffer.make(from: SyntheticImage.solid(
            width: 16, height: 16, red: 1, green: 0, blue: 0))
        let cyan = try RGBABuffer.make(from: SyntheticImage.solid(
            width: 16, height: 16, red: 0, green: 1, blue: 1))
        let psnr = PerceptualMetrics.psnr(red, cyan)
        // Per-pixel: dR=255, dG=255, dB=255. SSE per pixel = 3*65025. MSE = 65025.
        // PSNR = 20*log10(255 / sqrt(65025)) = 20*log10(1) = 0 dB.
        #expect(abs(psnr - 0.0) < 0.5, "expected ~0 dB for fully complementary; got \(psnr)")
    }

    @Test("SSIM of fully inverted buffers is below 0.1")
    func ssimInverted() throws {
        let red = try RGBABuffer.make(from: SyntheticImage.solid(
            width: 16, height: 16, red: 1, green: 0, blue: 0))
        let cyan = try RGBABuffer.make(from: SyntheticImage.solid(
            width: 16, height: 16, red: 0, green: 1, blue: 1))
        let ssim = PerceptualMetrics.ssim(red, cyan)
        // Both buffers are uniform within themselves (sigmaSq = 0), so the
        // structural term is dominated by C1/C2; the luminance term is the
        // dominant signal. Red luminance ≈ 76, cyan ≈ 179 — different but
        // the simplified SSIM doesn't drop to 0.
        #expect(ssim < 0.5, "fully complementary uniforms must score <0.5; got \(ssim)")
    }

    @Test("PSNR and SSIM both decline as noise grows")
    func metricsDeclineWithNoise() throws {
        let base = SyntheticImage.gradient(width: 64, height: 64)
        let baseBuf = try RGBABuffer.make(from: base)

        // JPEG q=100 should be near-lossless.
        let high = try JPEGEncoder.encode(image: base, quality: 1.0)
        let highTmp = try TempDirectory()
        let highURL = highTmp.url.appendingPathComponent("h.jpg")
        try high.write(to: highURL)
        let highBuf = try RGBABuffer.make(from: ImageIODecoder.decode(url: highURL))

        // JPEG q=20 should be visibly degraded.
        let low = try JPEGEncoder.encode(image: base, quality: 0.2)
        let lowTmp = try TempDirectory()
        let lowURL = lowTmp.url.appendingPathComponent("l.jpg")
        try low.write(to: lowURL)
        let lowBuf = try RGBABuffer.make(from: ImageIODecoder.decode(url: lowURL))

        let psnrHigh = PerceptualMetrics.psnr(baseBuf, highBuf)
        let psnrLow  = PerceptualMetrics.psnr(baseBuf, lowBuf)
        let ssimHigh = PerceptualMetrics.ssim(baseBuf, highBuf)
        let ssimLow  = PerceptualMetrics.ssim(baseBuf, lowBuf)

        #expect(psnrHigh > psnrLow, "PSNR must decline with quality; got high=\(psnrHigh), low=\(psnrLow)")
        #expect(ssimHigh > ssimLow, "SSIM must decline with quality; got high=\(ssimHigh), low=\(ssimLow)")
    }
}
```

- [ ] **Step 2: Run**

`swift test --filter "Perceptual metrics"` — expect 5/5.
`swift test` — expect 81/27 + 1 skipped + 1 known issue (was 76/26; +5 tests, +1 suite).

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/PerceptualMetricsTests.swift
git commit -m "$(cat <<'EOF'
test(metrics): self-test PSNR and SSIM helpers

Identical buffers must score max (PSNR=+inf, SSIM=1.0). Fully
complementary buffers score low. Both metrics must decline as JPEG
quality drops from 1.0 to 0.2. Pins the math so future encoder tests
(Section B) have a trustworthy baseline.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section B — Quality regression matrix

---

### Task 4: JPEG quality matrix

**Why:** JPEG is the most-used encoder; pin SSIM at four quality points so encoder regressions (e.g. ImageIO defaults shifting on a future macOS) surface here.

**Files:**
- Create: `Tests/CodecTests/PerceptualQualityTests.swift`

- [ ] **Step 1: Write the suite**

```swift
// Tests/CodecTests/PerceptualQualityTests.swift
import Foundation
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("Perceptual quality — JPEG matrix")
struct JPEGQualityMatrixTests {
    private func roundTrip(_ image: CGImage, quality: Double, ext: String = "jpg") throws -> RGBABuffer {
        let data = try JPEGEncoder.encode(image: image, quality: quality)
        let tmp = try TempDirectory()
        let url = tmp.url.appendingPathComponent("out.\(ext)")
        try data.write(to: url)
        let decoded = try ImageIODecoder.decode(url: url)
        return try RGBABuffer.make(from: decoded)
    }

    /// Threshold table per quality level. Lower bounds chosen to catch
    /// catastrophic encoder regressions (e.g. ImageIO falling back to
    /// monochrome) while allowing 0.05+ drift on the actual SSIM value
    /// across macOS minor versions.
    @Test("JPEG SSIM thresholds across quality matrix",
          arguments: [
            (q: 1.0,  minSSIM: 0.97),
            (q: 0.8,  minSSIM: 0.93),
            (q: 0.5,  minSSIM: 0.85),
            (q: 0.2,  minSSIM: 0.65),
          ])
    func ssimMatrix(q: Double, minSSIM: Double) throws {
        let src = SyntheticImage.gradient(width: 128, height: 128)
        let srcBuf = try RGBABuffer.make(from: src)
        let outBuf = try roundTrip(src, quality: q)
        let ssim = PerceptualMetrics.ssim(srcBuf, outBuf)
        #expect(ssim >= minSSIM,
                "JPEG q=\(q): expected SSIM ≥ \(minSSIM), got \(ssim)")
    }
}
```

- [ ] **Step 2: Run**

`swift test --filter "JPEG matrix"` — expect 4 sub-cases pass.

If any sub-case fails, **read the actual SSIM value** in the failure message. Two outcomes:
- The threshold is too tight → loosen by ~0.05 with a comment explaining
- The encoder genuinely regressed → escalate as DONE_WITH_CONCERNS

`swift test` — expect 82/28 + 1 skipped + 1 known issue (parameterised test counts as 1 in top-level).

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/PerceptualQualityTests.swift
git commit -m "$(cat <<'EOF'
test(codec): JPEG SSIM thresholds across quality matrix

Pin SSIM lower bounds for q ∈ {1.0, 0.8, 0.5, 0.2} on a synthesised
gradient. Bounds chosen to allow encoder drift across macOS minor
versions while catching catastrophic regressions.

Thresholds may need tightening once we know the actual SSIM landing
points on this macOS version — initial values are conservative.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: WebP / HEIC / AVIF quality matrix

**Why:** Same machinery as T4 but for the other lossy ImageIO + libwebp encoders. Each has its own quality characteristics, so per-encoder threshold tables.

**Files:**
- Modify: `Tests/CodecTests/PerceptualQualityTests.swift` (append three suites)

- [ ] **Step 1: Append three suites**

```swift
@Suite("Perceptual quality — WebP matrix")
struct WebPQualityMatrixTests {
    @Test("WebP SSIM thresholds across quality matrix",
          arguments: [
            (q: 1.0,  minSSIM: 0.97),
            (q: 0.8,  minSSIM: 0.93),
            (q: 0.5,  minSSIM: 0.85),
            (q: 0.2,  minSSIM: 0.65),
          ])
    func ssimMatrix(q: Double, minSSIM: Double) throws {
        let src = SyntheticImage.gradient(width: 128, height: 128)
        let srcBuf = try RGBABuffer.make(from: src)
        let data = try WebPEncoder.encode(image: src, quality: q)
        let tmp = try TempDirectory()
        let url = tmp.url.appendingPathComponent("out.webp")
        try data.write(to: url)
        let outBuf = try RGBABuffer.make(from: ImageIODecoder.decode(url: url))
        let ssim = PerceptualMetrics.ssim(srcBuf, outBuf)
        #expect(ssim >= minSSIM,
                "WebP q=\(q): expected SSIM ≥ \(minSSIM), got \(ssim)")
    }
}

@Suite("Perceptual quality — HEIC matrix")
struct HEICQualityMatrixTests {
    @Test("HEIC SSIM thresholds across quality matrix",
          arguments: [
            (q: 1.0,  minSSIM: 0.97),
            (q: 0.8,  minSSIM: 0.93),
            (q: 0.5,  minSSIM: 0.85),
            (q: 0.2,  minSSIM: 0.65),
          ])
    func ssimMatrix(q: Double, minSSIM: Double) throws {
        let src = SyntheticImage.gradient(width: 128, height: 128)
        let srcBuf = try RGBABuffer.make(from: src)
        let data = try HEICEncoder.encode(image: src, quality: q)
        let tmp = try TempDirectory()
        let url = tmp.url.appendingPathComponent("out.heic")
        try data.write(to: url)
        let outBuf = try RGBABuffer.make(from: ImageIODecoder.decode(url: url))
        let ssim = PerceptualMetrics.ssim(srcBuf, outBuf)
        #expect(ssim >= minSSIM,
                "HEIC q=\(q): expected SSIM ≥ \(minSSIM), got \(ssim)")
    }
}

@Suite("Perceptual quality — AVIF matrix")
struct AVIFQualityMatrixTests {
    @Test("AVIF SSIM thresholds across quality matrix",
          arguments: [
            (q: 1.0,  minSSIM: 0.95),    // AVIF q=1.0 is more lossy than JPEG q=1.0
            (q: 0.8,  minSSIM: 0.90),
            (q: 0.5,  minSSIM: 0.80),
            (q: 0.2,  minSSIM: 0.60),
          ],
          .timeLimit(.minutes(1)))
    func ssimMatrix(q: Double, minSSIM: Double) throws {
        // AVIF encode is slow on macOS 14 — bound the test.
        let src = SyntheticImage.gradient(width: 128, height: 128)
        let srcBuf = try RGBABuffer.make(from: src)
        let data = try AVIFEncoder.encode(image: src, quality: q)
        let tmp = try TempDirectory()
        let url = tmp.url.appendingPathComponent("out.avif")
        try data.write(to: url)
        let outBuf = try RGBABuffer.make(from: ImageIODecoder.decode(url: url))
        let ssim = PerceptualMetrics.ssim(srcBuf, outBuf)
        #expect(ssim >= minSSIM,
                "AVIF q=\(q): expected SSIM ≥ \(minSSIM), got \(ssim)")
    }
}
```

- [ ] **Step 2: Run**

`swift test --filter "Perceptual quality"` — expect 4 suites × 4 sub-cases = 16 sub-cases pass (reported as 4 tests at top-level counter — one parameterised test per suite).

If any sub-case fails, follow the same "loosen-or-escalate" pattern from T4.

`swift test` — expect 85/31 + 1 skipped + 1 known issue (was 82/28; +3 tests, +3 suites — each parameterised counts as 1).

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/PerceptualQualityTests.swift
git commit -m "$(cat <<'EOF'
test(codec): WebP/HEIC/AVIF SSIM thresholds across quality matrix

Same shape as the JPEG matrix from T4: four quality points per encoder
on a 128x128 gradient, SSIM lower bounds tuned per encoder. AVIF gets
a 1-minute time limit because encode is slow on macOS 14, plus tighter
thresholds because AVIF q=1.0 is genuinely more lossy than JPEG q=1.0.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: pngquant quality (env-gated)

**Why:** pngquant subprocess output isn't bit-deterministic across runs (libimagequant uses random number generation in palette selection), but SSIM should land in a stable range. Gate on `IMAGECRC_TEST_REQUIRE_PNGQUANT=1` so dev runs stay hermetic.

**Files:**
- Modify: `Tests/CodecTests/PNGQuantizerTests.swift` (append a quality test)

- [ ] **Step 1: Append the test**

Find the existing `PNGQuantizerTests` struct (single test `happyPath`). Append:

```swift
    @Test("pngquant SSIM threshold at quality=70",
          .enabled(if: ProcessInfo.processInfo.environment["IMAGECRC_TEST_REQUIRE_PNGQUANT"] == "1"))
    func ssimAtQuality70() async throws {
        let src = SyntheticImage.gradient(width: 256, height: 256)
        let srcBuf = try RGBABuffer.make(from: src)
        let lossless = try PNGEncoder.encode(image: src)
        let quantized = try await PNGQuantizer.quantize(pngData: lossless, quality: 70)
        let tmp = try TempDirectory()
        let url = tmp.url.appendingPathComponent("q70.png")
        try quantized.write(to: url)
        let outBuf = try RGBABuffer.make(from: ImageIODecoder.decode(url: url))
        let ssim = PerceptualMetrics.ssim(srcBuf, outBuf)
        // pngquant at q=70 on a smooth gradient should preserve perceptual
        // structure well even though pixel-exact output varies run-to-run.
        // Threshold loose to allow libimagequant non-determinism.
        #expect(ssim >= 0.85,
                "pngquant q=70 on a gradient: expected SSIM ≥ 0.85, got \(ssim)")
    }
```

- [ ] **Step 2: Run**

Without env var:
```bash
swift test --filter PNGQuantizer
```
Expected: existing `happyPath` skipped, new `ssimAtQuality70` skipped (both env-gated).

With env var (only if `pngquant` is installed):
```bash
IMAGECRC_TEST_REQUIRE_PNGQUANT=1 swift test --filter PNGQuantizer
```
Expected: 2/2 pass.

`swift test` (without env var) — expect 86/31 + 2 skipped + 1 known issue (was 85/31 + 1 skipped; +1 test, +1 skipped because new test is also gated).

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/PNGQuantizerTests.swift
git commit -m "$(cat <<'EOF'
test(codec): pngquant SSIM threshold at q=70 (env-gated)

Same gating as the existing pngquant happy-path test — runs only when
IMAGECRC_TEST_REQUIRE_PNGQUANT=1 is set, since pngquant is a system
binary not present on every dev machine.

Threshold (SSIM ≥ 0.85) is loose to accommodate libimagequant's
internal non-determinism in palette selection. The point is regression
detection, not absolute pixel matching.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section C — Phase 3 sweep

---

### Task 7: Pixel-level coverage for orientations 2/3/4/5/7

**Why:** Phase 3 T12 added dim-swap coverage for the five less-common EXIF orientations but no pixel-level test (analogous to the sentinel-pixel test that exists for orientation 6). A transform-table bug for any of these would still ship green. Add at least one sentinel-pixel test per orientation.

**Files:**
- Modify: `Tests/CodecTests/EXIFOrientationTests.swift` (append one parameterised test)

- [ ] **Step 1: Append the test**

The current file has:
- `orientation6PixelGeometry` — sentinel-pixel test for EXIF 6 (left edge → top after 90° CW)
- `lessCommonOrientations` — dim-swap only for 2/3/4/5/7
- `tiffDictFallback` — `withKnownIssue` wrapper

Append a new parameterised pixel test inside the struct. The expected sentinel-pixel coordinates per orientation are derived from the EXIF spec — for a horizontal red→blue gradient (red at x=0, blue at x=W-1) on a `100x50` source:

| EXIF | Description | Source-(0,0) → Display-(?,?) | Expected red-dominant sample |
|------|-------------|------------------------------|-----------------------------|
| 2 | upMirrored | (W-1, 0) | top-right of display (no swap) |
| 3 | down (180°) | (W-1, H-1) | bottom-right of display |
| 4 | downMirrored | (0, H-1) | bottom-left of display |
| 5 | leftMirrored (transpose) | (0, 0) | top-left of swapped display (which is now H wide × W tall) |
| 7 | rightMirrored | (W-1, H-1) | bottom-right of swapped display |

```swift
    @Test("less-common orientations place red gradient stop at expected sentinel pixel",
          arguments: [
            // (orient, sampleX, sampleY, swappedDims)
            // After applying the orientation, sample one pixel from the displayed
            // image and assert it's red-dominant. Coordinates use a 5px inset from
            // the corner to avoid JPEG block-edge artifacts.
            (orient: 2, x: 95, y:  5, swap: false),  // upMirrored: top-RIGHT is red
            (orient: 3, x: 95, y: 45, swap: false),  // 180°: bottom-RIGHT is red
            (orient: 4, x:  5, y: 45, swap: false),  // downMirrored: bottom-LEFT is red
            (orient: 5, x:  5, y:  5, swap: true),   // leftMirrored on swapped dims (50w x 100h): top-LEFT is red
            (orient: 7, x: 45, y: 95, swap: true),   // rightMirrored on swapped dims (50w x 100h): bottom-RIGHT is red
          ])
    func lessCommonOrientationsPixelGeometry(orient: Int, x: Int, y: Int, swap: Bool) throws {
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let data = SyntheticImage.jpegData(from: src, exifOrientation: orient)
        let url = tmp.url.appendingPathComponent("o\(orient)-pixel.jpg")
        try data.write(to: url)

        let decoded = try ImageIODecoder.decode(url: url)
        let expectedW = swap ? 50 : 100
        let expectedH = swap ? 100 : 50
        #expect(decoded.width == expectedW)
        #expect(decoded.height == expectedH)

        let buf = try RGBABuffer.make(from: decoded)
        let i = y * buf.bytesPerRow + x * 4
        let r = Int(buf.bytes[i])
        let b = Int(buf.bytes[i + 2])
        #expect(r > b + 50,
                "orientation=\(orient): expected red-dominant pixel at (\(x),\(y)); got R=\(r), B=\(b)")
    }
```

**Important:** the table above assumes specific spatial mappings derived from the EXIF/TIFF spec. If a sub-case fails, **don't change the expected coordinates to make the test pass** — the production transform in `ImageIODecoder.applyOrientation` is wrong for that case. Escalate as DONE_WITH_CONCERNS.

- [ ] **Step 2: Run**

`swift test --filter EXIF` — expect all green (5 sub-cases for the new test).

`swift test` — expect 87/31 + 2 skipped + 1 known issue (was 86/31; +1 test as parameterised counts as 1).

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/EXIFOrientationTests.swift
git commit -m "$(cat <<'EOF'
test(codec): sentinel-pixel coverage for less-common EXIF orientations

Phase 3 T12 only checked dim-swap for orientations 2/3/4/5/7. Add a
sentinel-pixel test per orientation: encode a horizontal red→blue
gradient with each EXIF tag, decode, and sample a pixel near where the
original red edge should land in display coordinates. Wrong transform
matrix (e.g. mirror flipped, axis swapped) would fail here.

Coordinates are derived from the EXIF spec, not from observation. If a
sub-case fails, the production transform in ImageIODecoder is wrong.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Localization-resilient `ConversionError` assertions

**Why:** Phase 3 T7 (`ImageConverterErrorTests.outputDirNil` and `outputDirCreateFails`) asserts on `errorDescription` substrings (`"Output directory"`, `"write"`, `"Could not"`). The current `Models/ConversionError.swift` has hardcoded English strings, but if localization is added later (or a contributor edits the strings), these tests break for a non-functional reason. Replace substring matching with typed pattern matching against the enum cases.

**Files:**
- Modify: `Tests/IntegrationTests/ImageConverterErrorTests.swift`

- [ ] **Step 1: Replace the substring assertions with typed pattern matching**

In `outputDirNil`, replace this block:

```swift
        for failure in final.failures {
            if case .failure(let err) = failure.outcome {
                #expect(err.errorDescription?.contains("Output directory") == true,
                        "outcome must surface outputDirectoryMissing; got \(err)")
            } else {
                Issue.record("expected .failure; got \(failure.outcome)")
            }
        }
```

with:

```swift
        for failure in final.failures {
            switch failure.outcome {
            case .failure(.outputDirectoryMissing):
                break  // expected
            case .failure(let other):
                Issue.record("expected .outputDirectoryMissing; got .\(other)")
            default:
                Issue.record("expected .failure(.outputDirectoryMissing); got \(failure.outcome)")
            }
        }
```

In `outputDirCreateFails`, replace:

```swift
        if case .failure(let err) = final.failures[0].outcome {
            #expect(err.errorDescription?.contains("write") == true
                    || err.errorDescription?.contains("Could not") == true,
                    "outcome must surface a write/create failure; got \(err)")
        } else {
            Issue.record("expected .failure; got \(final.failures[0].outcome)")
        }
```

with:

```swift
        switch final.failures[0].outcome {
        case .failure(.writeFailed):
            break  // expected — the createDirectory failure surfaces as .writeFailed
        case .failure(let other):
            Issue.record("expected .writeFailed; got .\(other)")
        default:
            Issue.record("expected .failure(.writeFailed); got \(final.failures[0].outcome)")
        }
```

- [ ] **Step 2: Run**

`swift test --filter ImageConverterError` — expect 2/2 still pass.
`swift test` — expect same count as before (no new tests).

- [ ] **Step 3: Commit**

```bash
git add Tests/IntegrationTests/ImageConverterErrorTests.swift
git commit -m "$(cat <<'EOF'
test(converter): typed pattern match instead of error-string substring

Phase 3 T7 asserted on errorDescription substrings ("Output directory",
"write", "Could not"). Those work today because the strings are hardcoded
English, but they tie test stability to copy choice — adding localization
or rewording the message would break tests for a non-functional reason.

Switch to pattern-matching the typed ConversionError enum cases directly.
Future error-message edits are independent of test stability.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Encoder output size sanity bounds

**Why:** A regression that doubles encoder output (e.g. forgetting to call `kCGImageDestinationLossyCompressionQuality`) wouldn't be caught by SSIM tests — the perceptual quality might still be fine even though the file is huge. Pin a loose upper bound (`outputBytes < 5 × sourceBytes`) and a lower bound (`outputBytes > 0`) for each lossy encoder.

**Files:**
- Create: `Tests/CodecTests/EncoderSizeTests.swift`

- [ ] **Step 1: Write the suite**

```swift
// Tests/CodecTests/EncoderSizeTests.swift
import Foundation
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("Encoder output size — sanity bounds")
struct EncoderSizeBoundsTests {
    /// 256x256 RGBA8 raw size = 256 * 256 * 4 = 262144 bytes. Lossy encoder
    /// output should be smaller than this raw size and certainly smaller than
    /// 5x raw (which would only happen with a serious encoder regression).
    private let rawByteCount = 256 * 256 * 4

    @Test("JPEG q=80 output is smaller than raw, larger than zero")
    func jpegBounds() throws {
        let src = SyntheticImage.gradient(width: 256, height: 256)
        let data = try JPEGEncoder.encode(image: src, quality: 0.8)
        #expect(data.count > 0)
        #expect(data.count < rawByteCount,
                "JPEG q=0.8 must be smaller than raw RGBA; got \(data.count) vs raw \(rawByteCount)")
    }

    @Test("WebP q=80 output is smaller than raw, larger than zero")
    func webpBounds() throws {
        let src = SyntheticImage.gradient(width: 256, height: 256)
        let data = try WebPEncoder.encode(image: src, quality: 0.8)
        #expect(data.count > 0)
        #expect(data.count < rawByteCount)
    }

    @Test("HEIC q=80 output is smaller than raw, larger than zero")
    func heicBounds() throws {
        let src = SyntheticImage.gradient(width: 256, height: 256)
        let data = try HEICEncoder.encode(image: src, quality: 0.8)
        #expect(data.count > 0)
        #expect(data.count < rawByteCount)
    }

    @Test("AVIF q=80 output is smaller than raw, larger than zero",
          .timeLimit(.minutes(1)))
    func avifBounds() throws {
        let src = SyntheticImage.gradient(width: 256, height: 256)
        let data = try AVIFEncoder.encode(image: src, quality: 0.8)
        #expect(data.count > 0)
        #expect(data.count < rawByteCount)
    }

    @Test("PNG (lossless) output bounded — for a smooth gradient, less than 5x raw")
    func pngBounds() throws {
        // PNG can be larger than raw for noisy input, but a smooth gradient
        // compresses well. Loose 5x raw upper bound for sanity.
        let src = SyntheticImage.gradient(width: 256, height: 256)
        let data = try PNGEncoder.encode(image: src)
        #expect(data.count > 0)
        #expect(data.count < 5 * rawByteCount,
                "PNG (lossless) on a gradient must compress; got \(data.count) vs raw \(rawByteCount)")
    }
}
```

- [ ] **Step 2: Run**

`swift test --filter "Encoder output size"` — expect 5/5.
`swift test` — expect 92/32 + 2 skipped + 1 known issue (was 87/31; +5 tests, +1 suite).

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/EncoderSizeTests.swift
git commit -m "$(cat <<'EOF'
test(codec): output size sanity bounds for each encoder

A regression that doubles encoder output (e.g. dropping the quality
option) would pass SSIM tests but fail user expectations. Pin loose
bounds: lossy encoders produce output smaller than raw RGBA, lossless
PNG produces less than 5x raw on a smooth gradient. Catches catastrophic
encoder regressions without coupling to specific compression ratios.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 Done When

- [ ] `swift test` exits 0 with **92 tests + 2 skipped + 1 known issue** across **32 suites** (Phase 3 ended at 76/26 + 1 skipped + 1 known issue; Phase 4 adds 16 tests / 6 suites)
- [ ] No SwiftPM warnings beyond pre-existing two
- [ ] `Tests/Support/PerceptualMetrics.swift` exists with `psnr` and `ssim` static functions, both self-tested
- [ ] JPEG / WebP / HEIC / AVIF have SSIM tests at q ∈ {0.2, 0.5, 0.8, 1.0}
- [ ] pngquant SSIM test exists, gated on `IMAGECRC_TEST_REQUIRE_PNGQUANT=1`
- [ ] EXIF orientations 2, 3, 4, 5, 7 each have at least one sentinel-pixel assertion
- [ ] `ConversionError` assertions pattern-match typed enum cases, not error-description substrings
- [ ] Each encoder has output-size sanity bounds
- [ ] User approval to write Phase 5 plan

**Deliberately deferred (won't be addressed in Phase 4):**
- Real-world camera fixtures with EXIF + ICC — synthesised gradients are sufficient for regression detection
- pngquant missing-binary deterministic test — would require Bundle.main shimming; permanent gap
- TIFF-dict fallback verification via manual EXIF byte injection — Phase 3 T11's `withKnownIssue` is the chosen accommodation

---

## Pause points

User policy: all phases on `tests/phase-1`, merge to main as one batch later.

- **After Section A (T1–T3):** metrics infrastructure in place + self-tested. Section B can be done as a separate sitting if desired.
- **After Section B (T1–T6):** encoder quality regression matrix complete. Section C is independent sweep.
- **After Section C (T1–T9):** Phase 4 done; ready for Phase 5 (UI smoke / XCUITest).

---

## Self-review

**Spec coverage:** every Phase 4 commitment from the original roadmap (SSIM/PSNR machinery, perceptual baselines for format × quality, pngquant gated) is covered by T1–T6. Phase 3 sweep candidates (pixel-level orientations, localization-resilient errors, output-size bounds) covered by T7–T9. Real-world fixtures + pngquant missing-binary explicitly deferred with rationale.

**Placeholder scan:** every code block has runnable code. T4–T6 SSIM thresholds may need tightening at execution time once the actual SSIM landing points are observed — the plan instructs the executor to "loosen by ~0.05 with a comment" if a sub-case fails, OR escalate as DONE_WITH_CONCERNS if the encoder genuinely regressed. That's a documented decision point, not a placeholder.

**Type consistency:** `RGBABuffer.make(from:)` from `Services/Encoders/RGBABuffer.swift` returns `RGBABuffer { let bytes: [UInt8]; let width: Int; let height: Int; let bytesPerRow: Int }`. All metric and quality tests use this exact API. `JPEGEncoder.encode(image:quality:) throws -> Data`, `WebPEncoder.encode(image:quality:) throws -> Data`, etc. — verified against current source.

**Cancellation/AVIF time-bound:** `.timeLimit(.minutes(1))` is the same pattern Phase 2 used for the AVIF round-trip test. Phase 4 reuses for AVIF perceptual quality (T5) and AVIF size bounds (T9). Should be safe on Apple Silicon.

**Cross-task consistency:** SSIM thresholds in T4 (JPEG) and T5 (WebP/HEIC/AVIF) follow the same per-quality table shape, with AVIF tightened slightly because its q=1.0 is genuinely more lossy.

**Deferred decisions:**
- SSIM thresholds may need a tightening pass after first execution (intentionally conservative now)
- AVIF time-limit may need raising on slow CI runners (Phase 6 concern)
