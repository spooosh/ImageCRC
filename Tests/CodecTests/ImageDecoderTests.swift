// Tests/CodecTests/ImageDecoderTests.swift
import Foundation
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("ImageDecoder — dispatch by InputFormat")
struct ImageDecoderDispatchTests {
    /// AVIF and HEIC encode require hardware codecs (AV1 / HEVC) that
    /// virtualised macOS CI runners lack — IOServiceGetMatchingService fails.
    /// Filter them out of the dispatch sweep when the matching skip flag is
    /// set; locally on Apple Silicon both run sub-second.
    private static let formatsToTest: [InputFormat] = {
        let env = ProcessInfo.processInfo.environment
        var all: [InputFormat] = [.jpeg, .png, .heic, .avif, .webp]
        if env["IMAGECRC_TEST_SKIP_AVIF"] == "1" {
            all.removeAll { $0 == .avif }
        }
        if env["IMAGECRC_TEST_SKIP_HEIC"] == "1" {
            all.removeAll { $0 == .heic }
        }
        return all
    }()

    private func encodeAndWrap(
        format: InputFormat, in tmp: TempDirectory
    ) throws -> ImageFile {
        let src = SyntheticImage.gradient(width: 48, height: 24)
        let data: Data
        let ext: String
        switch format {
        case .jpeg:
            data = try JPEGEncoder.encode(image: src, quality: 0.9); ext = "jpg"
        case .png:
            data = try PNGEncoder.encode(image: src); ext = "png"
        case .heic:
            data = try HEICEncoder.encode(image: src, quality: 0.9); ext = "heic"
        case .avif:
            data = try AVIFEncoder.encode(image: src, quality: 0.9); ext = "avif"
        case .webp:
            data = try WebPEncoder.encode(image: src, quality: 0.9); ext = "webp"
        case .svg:
            // SVG has its own decode path tested in SVGDecoderTests.
            fatalError("not used here")
        }
        let url = tmp.url.appendingPathComponent("in.\(ext)")
        try data.write(to: url)
        return try #require(ImageFile(url: url))
    }

    @Test("decode dispatches correctly for each raster InputFormat",
          arguments: ImageDecoderDispatchTests.formatsToTest)
    func dispatch(_ format: InputFormat) throws {
        let tmp = try TempDirectory()
        let file = try encodeAndWrap(format: format, in: tmp)
        let decoded = try ImageDecoder.decode(file: file)
        #expect(decoded.width == 48)
        #expect(decoded.height == 24)
    }
}
