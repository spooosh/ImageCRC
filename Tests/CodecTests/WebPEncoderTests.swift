// Tests/CodecTests/WebPEncoderTests.swift
import CoreGraphics
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
