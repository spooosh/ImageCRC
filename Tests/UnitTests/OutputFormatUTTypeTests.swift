// Tests/UnitTests/OutputFormatUTTypeTests.swift
import Testing
import UniformTypeIdentifiers
@testable import ImageCRC

@Suite("OutputFormat — UTType")
struct OutputFormatUTTypeTests {
    @Test("each format resolves to the expected UTType identifier")
    func utTypeIdentifiers() {
        #expect(OutputFormat.jpeg.utType == .jpeg)
        #expect(OutputFormat.png.utType == .png)
        #expect(OutputFormat.webp.utType.identifier == "org.webmproject.webp",
                "system UTType registry must still recognise WebP")
        #expect(OutputFormat.avif.utType.identifier == "public.avif",
                "system UTType registry must still recognise AVIF")
        #expect(OutputFormat.sameAsOrigin.utType == .image,
                "sameAsOrigin is a routing choice, not a writeable target")
    }
}
