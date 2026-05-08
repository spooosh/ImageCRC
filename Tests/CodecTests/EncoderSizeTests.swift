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
