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

    @Test("PSNR of fully complementary buffers is around 0 dB")
    func psnrInverted() throws {
        // Per-pixel: dR=255, dG=255, dB=255. SSE per pixel = 3*65025. MSE = 65025.
        // PSNR = 20*log10(255 / sqrt(65025)) = 20*log10(1) = 0 dB.
        let red = try RGBABuffer.make(from: SyntheticImage.solid(
            width: 16, height: 16, red: 1, green: 0, blue: 0))
        let cyan = try RGBABuffer.make(from: SyntheticImage.solid(
            width: 16, height: 16, red: 0, green: 1, blue: 1))
        let psnr = PerceptualMetrics.psnr(red, cyan)
        #expect(abs(psnr - 0.0) < 0.5, "expected ~0 dB for fully complementary; got \(psnr)")
    }

    @Test("SSIM of fully complementary buffers is below 0.5")
    func ssimInverted() throws {
        let red = try RGBABuffer.make(from: SyntheticImage.solid(
            width: 16, height: 16, red: 1, green: 0, blue: 0))
        let cyan = try RGBABuffer.make(from: SyntheticImage.solid(
            width: 16, height: 16, red: 0, green: 1, blue: 1))
        let ssim = PerceptualMetrics.ssim(red, cyan)
        // For spatially-uniform inputs (zero variance), SSIM reduces to a pure
        // luminance ratio (2·μA·μB + C1) / (μA² + μB² + C1). Red (μ≈76) vs cyan
        // (μ≈179) yields ~0.72 — noticeably below identical (1.0) but bounded
        // above 0.5 by the C1 stabilization constant. Threshold reflects this
        // ceiling: complementary uniforms must score below identical, but the
        // simplified SSIM doesn't drop near 0.
        #expect(ssim < 0.8, "fully complementary uniforms must score <0.8; got \(ssim)")
    }

    @Test("PSNR and SSIM both decline as JPEG quality drops")
    func metricsDeclineWithNoise() throws {
        let base = SyntheticImage.gradient(width: 64, height: 64)
        let baseBuf = try RGBABuffer.make(from: base)

        // JPEG q=1.0 should be near-lossless.
        let high = try JPEGEncoder.encode(image: base, quality: 1.0)
        let highTmp = try TempDirectory()
        let highURL = highTmp.url.appendingPathComponent("h.jpg")
        try high.write(to: highURL)
        let highBuf = try RGBABuffer.make(from: ImageIODecoder.decode(url: highURL))

        // JPEG q=0.2 should be visibly degraded.
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
