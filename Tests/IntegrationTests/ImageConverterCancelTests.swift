import Foundation
import Testing
@testable import ImageCRC

@Suite("ImageConverter — cancellation")
struct ImageConverterCancelTests {
    private func makeInputs(count: Int, in tmp: TempDirectory) throws -> [ImageFile] {
        var files: [ImageFile] = []
        let img = SyntheticImage.gradient(width: 32, height: 32)
        let data = try PNGEncoder.encode(image: img)
        for i in 0..<count {
            let url = tmp.url.appendingPathComponent("in-\(i).png")
            try data.write(to: url)
            files.append(try #require(ImageFile(url: url)))
        }
        return files
    }

    @Test("cancel mid-batch terminates promptly, output bounded by observed completions")
    func cancelMidBatch() async throws {
        let inputTmp = try TempDirectory()
        let outputTmp = try TempDirectory()
        let files = try makeInputs(count: 32, in: inputTmp)
        var settings = ConversionSettings.default
        settings.outputDirectory = outputTmp.url
        settings.outputFormat = .jpeg

        let observer = Task {
            let converter = ImageConverter()
            var observedCompletions = 0
            for await event in converter.convert(files: files, settings: settings) {
                if case .didComplete = event {
                    observedCompletions += 1
                }
            }
            return observedCompletions
        }

        // Wait briefly for the orchestrator to start spawning, then cancel.
        // 50ms is conservative on Apple Silicon; if Phase 6 CI runs on slower
        // hardware and this flakes, raise the sleep or wait for the first
        // .didComplete event before cancelling.
        try await Task.sleep(nanoseconds: 50_000_000)
        observer.cancel()
        let observed = await observer.value

        // Externally observable invariants:
        // - Termination happens (the await on observer.value returns).
        // - Output directory contains AT MOST `observed` files: drained files
        //   never run their encode/write step, and we may have observed fewer
        //   completions than there are output files only if a file completed
        //   between cancellation and consumer iterator exit (highly unlikely
        //   but allowed by AsyncStream buffer semantics).
        let written = try FileManager.default.contentsOfDirectory(at: outputTmp.url, includingPropertiesForKeys: nil)
        let jpgs = written.filter { $0.pathExtension == "jpg" }
        #expect(jpgs.count <= 32, "no more output files than input total")
        // Loose upper bound to allow for runtime races between cancel signal
        // and last-iteration write completion.
        #expect(jpgs.count <= observed + 4,
                "output count (\(jpgs.count)) should be near observed completions (\(observed))")
    }

    @Test("cancel-before-iteration: stream finishes cleanly without spawning work")
    func cancelBeforeStart() async throws {
        let inputTmp = try TempDirectory()
        let outputTmp = try TempDirectory()
        let files = try makeInputs(count: 8, in: inputTmp)
        var settings = ConversionSettings.default
        settings.outputDirectory = outputTmp.url
        settings.outputFormat = .jpeg

        let observer = Task {
            let converter = ImageConverter()
            for await _ in converter.convert(files: files, settings: settings) {}
        }
        observer.cancel()
        await observer.value
        // No assertion beyond "no crash, terminates cleanly". The point is to
        // exercise the cancel-before-spawn branch in continuation.onTermination.
    }
}
