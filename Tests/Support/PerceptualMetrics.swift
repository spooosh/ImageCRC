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
}
