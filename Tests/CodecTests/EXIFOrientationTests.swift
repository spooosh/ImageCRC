// Tests/CodecTests/EXIFOrientationTests.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
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

    @Test("less-common orientations preserve or swap dims as expected",
          arguments: [
            (orient: 2, swap: false),  // upMirrored
            (orient: 3, swap: false),  // down (180°)
            (orient: 4, swap: false),  // downMirrored
            (orient: 5, swap: true),   // leftMirrored (90° CCW + flip)
            (orient: 7, swap: true),   // rightMirrored (90° CW + flip)
          ])
    func lessCommonOrientations(orient: Int, swap: Bool) throws {
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let data = SyntheticImage.jpegData(from: src, exifOrientation: orient)
        let url = tmp.url.appendingPathComponent("o\(orient).jpg")
        try data.write(to: url)
        let decoded = try ImageIODecoder.decode(url: url)
        if swap {
            #expect(decoded.width == 50, "orientation=\(orient): expected swap to 50w")
            #expect(decoded.height == 100, "orientation=\(orient): expected swap to 100h")
        } else {
            #expect(decoded.width == 100, "orientation=\(orient): expected no swap")
            #expect(decoded.height == 50)
        }
    }

    @Test("orientation in nested TIFF dictionary is honoured when top-level is absent")
    func tiffDictFallback() throws {
        // Synthesise a JPEG with the orientation tag stored ONLY in the TIFF
        // dictionary by writing through CGImageDestination with a custom props
        // dict that omits the top-level key.
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let mutableData = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        let tiffDict: [CFString: Any] = [
            kCGImagePropertyTIFFOrientation: 6,
        ]
        let props: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: tiffDict,
        ]
        CGImageDestinationAddImage(dest, src, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let url = tmp.url.appendingPathComponent("tiff-only.jpg")
        try (mutableData as Data).write(to: url)

        // Precondition verification: confirm ImageIO did NOT promote the TIFF
        // orientation to the top level. If it did, this test cannot validate
        // the fallback path — record an issue and skip the assertion.
        let writtenSource = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let writtenProps = CGImageSourceCopyPropertiesAtIndex(writtenSource, 0, nil) as? [CFString: Any]
        let topLevelOrient = writtenProps?[kCGImagePropertyOrientation] as? UInt32
        let nestedOrient = (writtenProps?[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFOrientation] as? UInt32

        if topLevelOrient != nil {
            Issue.record("ImageIO promoted TIFF-dict orientation to the top-level key on write; this test cannot validate the fallback path. topLevel=\(topLevelOrient ?? 0), nested=\(nestedOrient ?? 0). Consider an alternative synthesis (manual EXIF byte injection) or accept this test as inactive on this macOS version.")
            return
        }
        #expect(nestedOrient == 6, "precondition: TIFF dict must carry orientation=6")

        let decoded = try ImageIODecoder.decode(url: url)
        #expect(decoded.width == 50, "TIFF-dict orientation=6 must apply via fallback")
        #expect(decoded.height == 100)
    }
}
