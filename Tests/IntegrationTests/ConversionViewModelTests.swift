import Foundation
import Testing
@testable import ImageCRC

@MainActor
@Suite("ConversionViewModel — phase transitions")
struct ConversionViewModelPhaseTests {
    private func makeFile(in tmp: TempDirectory, name: String = "a.png") throws -> ImageFile {
        let img = SyntheticImage.solid(width: 8, height: 8)
        let data = try PNGEncoder.encode(image: img)
        let url = tmp.url.appendingPathComponent(name)
        try data.write(to: url)
        return try #require(ImageFile(url: url))
    }

    private func waitForPhase(_ vm: ConversionViewModel, _ target: ConversionViewModel.Phase, timeoutMs: Int = 1000) async throws {
        let start = Date()
        while vm.phase != target {
            if Date().timeIntervalSince(start) > Double(timeoutMs) / 1000.0 {
                Issue.record("timed out waiting for phase=\(target); current=\(vm.phase)")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)  // 5ms
        }
    }

    @Test("scripted events drive idle → running → completed")
    func happyPath() async throws {
        let tmp = try TempDirectory()
        let file = try makeFile(in: tmp)
        let outputURL = tmp.url.appendingPathComponent("out.jpg")

        let result = ConversionResult(
            id: UUID(),
            source: file.url,
            outcome: .success(outputURL: outputURL, originalBytes: 100, outputBytes: 50)
        )
        let summary = ConversionSummary(
            total: 1,
            successes: [result],
            failures: [],
            cancelled: 0,
            outputDirectory: tmp.url
        )

        let fake = FakeConverter(events: [
            .willStart(file: file),
            .didComplete(result: result, completed: 1, total: 1),
            .didFinish(summary: summary),
        ])

        let vm = ConversionViewModel(converter: fake)
        vm.files = [file]
        vm.settings.outputDirectory = tmp.url

        #expect(vm.phase == .idle)
        vm.start()
        #expect(vm.phase == .running)

        try await waitForPhase(vm, .completed)
        #expect(vm.completed == 1)
        #expect(vm.total == 1)
        #expect(vm.progress == 1.0)
        #expect(vm.summary?.successes.count == 1)
        #expect(vm.currentFilename == nil, "currentFilename clears on .didFinish")
    }

    @Test(".willStart updates currentFilename")
    func willStartUpdatesFilename() async throws {
        let tmp = try TempDirectory()
        let file = try makeFile(in: tmp, name: "photo.png")

        let fake = FakeConverter(events: [
            .willStart(file: file),
        ])

        let vm = ConversionViewModel(converter: fake)
        vm.files = [file]
        vm.settings.outputDirectory = tmp.url
        vm.start()

        // Wait briefly for the willStart event to land.
        let start = Date()
        while vm.currentFilename == nil {
            if Date().timeIntervalSince(start) > 1 { Issue.record("timed out"); break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(vm.currentFilename == "photo.png")
    }
}

@MainActor
@Suite("ConversionViewModel — canStart, cancel, dismiss")
struct ConversionViewModelGuardTests {
    private func makeFile(in tmp: TempDirectory) throws -> ImageFile {
        let img = SyntheticImage.solid(width: 8, height: 8)
        let data = try PNGEncoder.encode(image: img)
        let url = tmp.url.appendingPathComponent("a.png")
        try data.write(to: url)
        return try #require(ImageFile(url: url))
    }

    @Test("canStart is false when files is empty")
    func canStartNoFiles() throws {
        let vm = ConversionViewModel(converter: FakeConverter())
        vm.settings.outputDirectory = URL(fileURLWithPath: "/tmp")
        #expect(vm.canStart == false)
    }

    @Test("canStart is false when outputDirectory is nil")
    func canStartNoOutputDir() throws {
        let tmp = try TempDirectory()
        let file = try makeFile(in: tmp)
        let vm = ConversionViewModel(converter: FakeConverter())
        vm.files = [file]
        vm.settings.outputDirectory = nil
        #expect(vm.canStart == false)
    }

    @Test("canStart is true with files and output dir set")
    func canStartReady() throws {
        let tmp = try TempDirectory()
        let file = try makeFile(in: tmp)
        let vm = ConversionViewModel(converter: FakeConverter())
        vm.files = [file]
        vm.settings.outputDirectory = tmp.url
        #expect(vm.canStart == true)
    }

    @Test("dismissCompletion resets state to idle")
    func dismissResets() async throws {
        let tmp = try TempDirectory()
        let file = try makeFile(in: tmp)
        let result = ConversionResult(
            id: UUID(), source: file.url,
            outcome: .success(outputURL: tmp.url.appendingPathComponent("o.jpg"),
                              originalBytes: 1, outputBytes: 1)
        )
        let summary = ConversionSummary(
            total: 1, successes: [result], failures: [], cancelled: 0,
            outputDirectory: tmp.url
        )
        let fake = FakeConverter(events: [
            .didComplete(result: result, completed: 1, total: 1),
            .didFinish(summary: summary),
        ])
        let vm = ConversionViewModel(converter: fake)
        vm.files = [file]
        vm.settings.outputDirectory = tmp.url
        vm.start()

        // Wait for completed phase.
        let start = Date()
        while vm.phase != .completed {
            if Date().timeIntervalSince(start) > 1 { Issue.record("timeout"); return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        vm.dismissCompletion()
        #expect(vm.phase == .idle)
        #expect(vm.summary == nil)
        #expect(vm.completed == 0)
        #expect(vm.total == 0)
        #expect(vm.progress == 0)
        #expect(vm.currentFilename == nil)
    }

    @Test("chooseOutputDirectory routes through FakeFileChooser")
    func fileChooserRouting() throws {
        let chooser = FakeFileChooser(directoryToReturn: URL(fileURLWithPath: "/tmp/chosen"))
        let vm = ConversionViewModel(converter: FakeConverter(), fileChooser: chooser)
        vm.chooseOutputDirectory()
        #expect(vm.settings.outputDirectory?.path == "/tmp/chosen")
    }
}
