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
