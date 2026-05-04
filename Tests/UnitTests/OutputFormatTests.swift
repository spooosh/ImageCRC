// Tests/UnitTests/OutputFormatTests.swift
import Testing
@testable import ImageCRC

@Suite("OutputFormat")
struct OutputFormatTests {
    @Test("fileExtension matches each format")
    func fileExtensions() {
        #expect(OutputFormat.jpeg.fileExtension == "jpg")
        #expect(OutputFormat.png.fileExtension == "png")
        #expect(OutputFormat.webp.fileExtension == "webp")
        #expect(OutputFormat.avif.fileExtension == "avif")
        #expect(OutputFormat.sameAsOrigin.fileExtension == "")
    }

    @Test("isLossless only for PNG")
    func isLossless() {
        #expect(OutputFormat.png.isLossless)
        for f in [OutputFormat.jpeg, .webp, .avif, .sameAsOrigin] {
            #expect(f.isLossless == false, "\(f) should not be lossless")
        }
    }

    @Test("displayName is non-empty for every format")
    func displayNamesNonEmpty() {
        for f in OutputFormat.allCases {
            #expect(f.displayName.isEmpty == false, "\(f).displayName must not be empty")
        }
    }
}
