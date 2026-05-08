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
          .enabled(if: CodecCapability.heicEncodeAvailable),
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
          .timeLimit(.minutes(1)),
          .enabled(if: CodecCapability.avifEncodeAvailable),
          arguments: [
            // macOS ImageIO AVIF rejects q=1.0 (lossless codepath unsupported);
            // q=0.99 is the practical ceiling — observed SSIM ≈ 0.9999.
            (q: 0.99, minSSIM: 0.95),
            (q: 0.8,  minSSIM: 0.90),
            (q: 0.5,  minSSIM: 0.80),
            (q: 0.2,  minSSIM: 0.60),
          ])
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
