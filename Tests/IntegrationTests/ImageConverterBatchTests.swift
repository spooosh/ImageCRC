import Foundation
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("ImageConverter — batch happy path")
struct ImageConverterBatchTests {
    /// Build N synthesised PNGs in `tmp` and wrap them as ImageFile values.
    private func makeInputs(count: Int, in tmp: TempDirectory) throws -> [ImageFile] {
        var files: [ImageFile] = []
        let img = SyntheticImage.gradient(width: 32, height: 16)
        let data = try PNGEncoder.encode(image: img)
        for i in 0..<count {
            let url = tmp.url.appendingPathComponent("in-\(i).png")
            try data.write(to: url)
            files.append(try #require(ImageFile(url: url)))
        }
        return files
    }

    @Test("16-file batch: all success, monotonic counter, exact event count")
    func batchAllSuccess() async throws {
        let inputTmp = try TempDirectory()
        let outputTmp = try TempDirectory()
        let files = try makeInputs(count: 16, in: inputTmp)
        var settings = ConversionSettings.default
        settings.outputDirectory = outputTmp.url
        settings.outputFormat = .jpeg

        var willStartCount = 0
        var didCompleteCount = 0
        var lastCompleted = 0
        var summary: ConversionSummary?

        let converter = ImageConverter()
        for await event in converter.convert(files: files, settings: settings) {
            switch event {
            case .willStart:
                willStartCount += 1
            case .didComplete(_, let completed, let total):
                didCompleteCount += 1
                #expect(completed > lastCompleted, "counter must be strictly monotonic")
                #expect(completed <= total)
                lastCompleted = completed
            case .didFinish(let s):
                summary = s
            }
        }

        #expect(willStartCount == 16)
        #expect(didCompleteCount == 16)
        #expect(lastCompleted == 16)
        let final = try #require(summary)
        #expect(final.successes.count == 16)
        #expect(final.failures.isEmpty)
        #expect(final.cancelled == 0)
        #expect(final.total == 16)
    }

    @Test("output files are written to the chosen directory with .jpg extension")
    func outputFilesPresent() async throws {
        let inputTmp = try TempDirectory()
        let outputTmp = try TempDirectory()
        let files = try makeInputs(count: 4, in: inputTmp)
        var settings = ConversionSettings.default
        settings.outputDirectory = outputTmp.url
        settings.outputFormat = .jpeg

        let converter = ImageConverter()
        for await _ in converter.convert(files: files, settings: settings) {}

        let written = try FileManager.default.contentsOfDirectory(at: outputTmp.url, includingPropertiesForKeys: nil)
        let jpgs = written.filter { $0.pathExtension == "jpg" }
        #expect(jpgs.count == 4)
    }
}
