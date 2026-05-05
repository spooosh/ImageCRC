// Tests/UnitTests/EncoderFormatTests.swift
import Testing
@testable import ImageCRC

@Suite("EncoderFormat")
struct EncoderFormatTests {
    @Test("fileExtension matches each encoder format")
    func fileExtensions() {
        #expect(EncoderFormat.jpeg.fileExtension == "jpg")
        #expect(EncoderFormat.png.fileExtension  == "png")
        #expect(EncoderFormat.webp.fileExtension == "webp")
        #expect(EncoderFormat.avif.fileExtension == "avif")
        #expect(EncoderFormat.heic.fileExtension == "heic")
    }

    @Test("displayName is non-empty for every format")
    func displayNames() {
        for f: EncoderFormat in [.jpeg, .png, .webp, .avif, .heic] {
            #expect(f.displayName.isEmpty == false, "\(f).displayName must not be empty")
        }
    }
}
