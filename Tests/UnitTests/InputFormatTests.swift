// Tests/UnitTests/InputFormatTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("InputFormat")
struct InputFormatTests {
    @Test("init from URL maps each supported extension")
    func mapsExtensions() {
        let cases: [(String, InputFormat)] = [
            ("photo.jpg",  .jpeg),
            ("photo.JPG",  .jpeg),
            ("photo.jpeg", .jpeg),
            ("img.png",    .png),
            ("img.PNG",    .png),
            ("vec.svg",    .svg),
            ("anim.webp",  .webp),
            ("shot.avif",  .avif),
            ("phone.heic", .heic),
        ]
        for (name, expected) in cases {
            let url = URL(fileURLWithPath: "/tmp/\(name)")
            #expect(InputFormat(url: url) == expected, "for \(name)")
        }
    }

    @Test("init returns nil for unsupported extensions")
    func rejectsUnsupported() {
        for ext in ["bmp", "tiff", "gif", "ico", "pdf", ""] {
            let url = URL(fileURLWithPath: "/tmp/file.\(ext)")
            #expect(InputFormat(url: url) == nil, "should reject .\(ext)")
        }
        // Extensionless filename — different URL parse path than trailing dot
        let noExt = URL(fileURLWithPath: "/tmp/file")
        #expect(InputFormat(url: noExt) == nil, "should reject extensionless file")
    }

    @Test("allowedExtensions covers exactly the recognized set")
    func allowedExtensionsSet() {
        let expected: Set<String> = ["jpg", "jpeg", "png", "svg", "webp", "avif", "heic"]
        #expect(InputFormat.allowedExtensions == expected)
    }
}
