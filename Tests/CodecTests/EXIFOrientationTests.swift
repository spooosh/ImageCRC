// Tests/CodecTests/EXIFOrientationTests.swift
import Foundation
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("ImageIODecoder — EXIF orientation")
struct EXIFOrientationTests {
    @Test("orientation=6 (90° CW) swaps width and height after decode")
    func orientation6SwapsDims() throws {
        let tmp = try TempDirectory()
        // Source is 100 wide × 50 tall. With EXIF orientation=6, the camera
        // recorded "landscape sensor; rotate 90 CW for display" — meaning the
        // logical image is 50 wide × 100 tall.
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let data = SyntheticImage.jpegData(from: src, exifOrientation: 6)
        let url = tmp.url.appendingPathComponent("rotated.jpg")
        try data.write(to: url)

        let decoded = try ImageIODecoder.decode(url: url)
        #expect(decoded.width == 50, "EXIF orientation=6 must swap width/height")
        #expect(decoded.height == 100)
    }

    @Test("orientation=1 (normal) preserves dimensions as-is")
    func orientation1NoOp() throws {
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let data = SyntheticImage.jpegData(from: src, exifOrientation: 1)
        let url = tmp.url.appendingPathComponent("normal.jpg")
        try data.write(to: url)

        let decoded = try ImageIODecoder.decode(url: url)
        #expect(decoded.width == 100)
        #expect(decoded.height == 50)
    }

    @Test("orientation=8 (270° CW / 90° CCW) also swaps")
    func orientation8Swaps() throws {
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let data = SyntheticImage.jpegData(from: src, exifOrientation: 8)
        let url = tmp.url.appendingPathComponent("rotated8.jpg")
        try data.write(to: url)

        let decoded = try ImageIODecoder.decode(url: url)
        #expect(decoded.width == 50)
        #expect(decoded.height == 100)
    }

    @Test("orientation=6 places the original left edge at the top after rotation")
    func orientation6PixelGeometry() throws {
        // Without this test, a transposed rotation matrix (e.g. 90° CCW where
        // we wanted CW) would still pass the dim-swap assertions above.
        // Sample an actual pixel to verify the rotation is geometrically right.
        let tmp = try TempDirectory()
        // Horizontal gradient: red at x=0, blue at x=W-1. Source 100w × 50h.
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let data = SyntheticImage.jpegData(from: src, exifOrientation: 6)
        let url = tmp.url.appendingPathComponent("rotated6-pixel.jpg")
        try data.write(to: url)

        let decoded = try ImageIODecoder.decode(url: url)
        #expect(decoded.width == 50)
        #expect(decoded.height == 100)

        // After orientation=6 (90° CW for display), the original left edge (red)
        // becomes the new top edge. Sample a pixel near top-center; R must
        // dominate B with enough slack for JPEG quantisation.
        let buf = try RGBABuffer.make(from: decoded)
        let x = 25
        let y = 5
        let i = y * buf.bytesPerRow + x * 4
        let r = Int(buf.bytes[i])
        let b = Int(buf.bytes[i + 2])
        #expect(r > b + 50,
                "expected red-dominant pixel near top of orientation=6 decoded image; got R=\(r), B=\(b)")
    }
}
