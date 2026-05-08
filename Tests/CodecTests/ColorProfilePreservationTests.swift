// Tests/CodecTests/ColorProfilePreservationTests.swift
import Foundation
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("ImageResizer — color profile preservation")
struct ColorProfilePreservationTests {
    @Test("Display P3 input is preserved through resize")
    func displayP3Preserved() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let img = SyntheticImage.solid(width: 100, height: 100, colorSpace: p3)
        // Sanity: source actually carries P3.
        let srcName = img.colorSpace?.name as String?
        #expect(srcName == (CGColorSpace.displayP3 as String),
                "synthesised P3 image must carry displayP3 colorspace; got \(srcName ?? "nil")")

        var s = ResizeSettings()
        s.width = 50
        s.height = 50
        s.mode = .fit
        let resized = ImageResizer.resize(img, settings: s)

        let resizedName = resized.colorSpace?.name as String?
        #expect(resizedName == (CGColorSpace.displayP3 as String),
                "Display P3 must survive resize; got \(resizedName ?? "nil")")
    }

    @Test("inactive resize trivially preserves colorspace (===)")
    func inactivePreservesColorspace() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let img = SyntheticImage.solid(width: 100, height: 100, colorSpace: p3)
        let out = ImageResizer.resize(img, settings: ResizeSettings())
        // Inactive path returns the same image, so colorspace is preserved by definition.
        #expect((out.colorSpace?.name as String?) == (CGColorSpace.displayP3 as String))
    }
}
