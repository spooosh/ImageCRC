import Foundation
import Testing
@testable import ImageCRC

@Suite("ImageConverter — error paths")
struct ImageConverterErrorTests {
    private func makeInput(in tmp: TempDirectory, name: String = "in.png") throws -> ImageFile {
        let img = SyntheticImage.gradient(width: 16, height: 16)
        let data = try PNGEncoder.encode(image: img)
        let url = tmp.url.appendingPathComponent(name)
        try data.write(to: url)
        return try #require(ImageFile(url: url))
    }

    @Test("outputDirectory == nil produces all .outputDirectoryMissing failures")
    func outputDirNil() async throws {
        let inputTmp = try TempDirectory()
        let files = [
            try makeInput(in: inputTmp, name: "a.png"),
            try makeInput(in: inputTmp, name: "b.png"),
        ]
        var settings = ConversionSettings.default
        settings.outputDirectory = nil
        settings.outputFormat = .jpeg

        var summary: ConversionSummary?
        var willStartCount = 0
        let converter = ImageConverter()
        for await event in converter.convert(files: files, settings: settings) {
            switch event {
            case .willStart: willStartCount += 1
            case .didFinish(let s): summary = s
            case .didComplete: break
            }
        }

        #expect(willStartCount == 0, "no .willStart should fire when output dir is missing")
        let final = try #require(summary)
        #expect(final.failures.count == 2)
        #expect(final.successes.isEmpty)
        for failure in final.failures {
            switch failure.outcome {
            case .failure(.outputDirectoryMissing):
                break  // expected
            case .failure(let other):
                Issue.record("expected .outputDirectoryMissing; got .\(other)")
            default:
                Issue.record("expected .failure(.outputDirectoryMissing); got \(failure.outcome)")
            }
        }
    }

    @Test("createDirectory failure produces all .writeFailed failures")
    func outputDirCreateFails() async throws {
        // /dev/null is a character device — createDirectory on a path under it
        // fails. The orchestrator's catch block at ImageConverter.swift:44
        // converts the create error into per-file .writeFailed outcomes for
        // every input. Note: this exercises the dir-create branch, not the
        // per-file write-failure branch inside processOne.
        let inputTmp = try TempDirectory()
        let files = [try makeInput(in: inputTmp)]
        var settings = ConversionSettings.default
        settings.outputDirectory = URL(fileURLWithPath: "/dev/null/imagecrc-bogus")
        settings.outputFormat = .jpeg

        var summary: ConversionSummary?
        let converter = ImageConverter()
        for await event in converter.convert(files: files, settings: settings) {
            if case .didFinish(let s) = event { summary = s }
        }

        let final = try #require(summary)
        #expect(final.failures.count == 1)
        #expect(final.successes.isEmpty)
        switch final.failures[0].outcome {
        case .failure(.writeFailed):
            break  // expected — the createDirectory failure surfaces as .writeFailed
        case .failure(let other):
            Issue.record("expected .writeFailed; got .\(other)")
        default:
            Issue.record("expected .failure(.writeFailed); got \(final.failures[0].outcome)")
        }
    }
}
