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
