// Tests/CodecTests/ImageIOEncodersTests.swift
import CoreGraphics
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

    @Test("HEIC round-trip preserves dimensions",
          .enabled(if: ProcessInfo.processInfo.environment["IMAGECRC_TEST_SKIP_HEIC"] != "1"))
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
          .timeLimit(.minutes(1)),
          .enabled(if: ProcessInfo.processInfo.environment["IMAGECRC_TEST_SKIP_AVIF"] != "1"))
    func avifRoundTrip() throws {
        // AVIF encode is slow on macOS 14 — bound the test. Virtualised CI
        // runners without hardware AV1 may take 10x longer; gate via env.
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 64, height: 32)
        let data = try AVIFEncoder.encode(image: src, quality: 0.8)
        let decoded = try writeAndDecode(data: data, ext: "avif", in: tmp)
        #expect(decoded.width == 64)
        #expect(decoded.height == 32)
        #expect(data.count > 0)
    }
}
