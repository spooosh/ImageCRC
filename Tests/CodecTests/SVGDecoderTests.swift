// Tests/CodecTests/SVGDecoderTests.swift
import Foundation
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("SVGDecoder")
struct SVGDecoderTests {
    private static let minimalSVG = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="64" height="48" viewBox="0 0 64 48">
      <rect x="0" y="0" width="64" height="48" fill="red"/>
      <circle cx="32" cy="24" r="16" fill="blue"/>
    </svg>
    """

    @Test("minimal SVG with explicit width/height decodes to non-zero CGImage")
    func minimalSVGDecodes() throws {
        let tmp = try TempDirectory()
        let url = tmp.url.appendingPathComponent("test.svg")
        try Self.minimalSVG.write(to: url, atomically: true, encoding: .utf8)

        let decoded = try SVGDecoder.decode(url: url)
        #expect(decoded.width > 0)
        #expect(decoded.height > 0)
        // NSImage may decide on its own raster size; we only pin "non-zero".
        // Pinning exact dims would couple to NSImage internals.
    }

    @Test("ImageDecoder.decode dispatches SVG to SVGDecoder")
    func dispatchSVG() throws {
        let tmp = try TempDirectory()
        let url = tmp.url.appendingPathComponent("test.svg")
        try Self.minimalSVG.write(to: url, atomically: true, encoding: .utf8)

        let file = try #require(ImageFile(url: url))
        #expect(file.inputFormat == .svg)
        let decoded = try ImageDecoder.decode(file: file)
        #expect(decoded.width > 0)
        #expect(decoded.height > 0)
    }
}
