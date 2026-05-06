import Foundation
import Observation
import AppKit

@MainActor
@Observable
final class ConversionViewModel {
    enum Phase: Equatable {
        case idle
        case running
        case completed
    }

    // Input
    var files: [ImageFile] = []
    var settings: ConversionSettings = .default

    // Progress
    private(set) var phase: Phase = .idle
    private(set) var progress: Double = 0
    private(set) var completed: Int = 0
    private(set) var total: Int = 0
    private(set) var currentFilename: String? = nil

    // Result
    private(set) var summary: ConversionSummary? = nil

    private var job: Task<Void, Never>?

    @ObservationIgnored
    private let converter: any Converter

    init(converter: any Converter = ImageConverter()) {
        self.converter = converter
    }

    // MARK: - File management

    /// Add URLs (files or folders). Folders are scanned shallowly for supported extensions.
    func addURLs(_ urls: [URL]) {
        var collected: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if let contents = try? fm.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) {
                    collected.append(contentsOf: contents)
                }
            } else {
                collected.append(url)
            }
        }

        let existing = Set(files.map { $0.url.standardizedFileURL })
        var added: [ImageFile] = []
        for u in collected {
            let std = u.standardizedFileURL
            guard !existing.contains(std) else { continue }
            guard InputFormat.allowedExtensions.contains(u.pathExtension.lowercased()) else { continue }
            if let f = ImageFile(url: std) {
                added.append(f)
            }
        }
        files.append(contentsOf: added)
    }

    func remove(_ file: ImageFile) {
        files.removeAll { $0.id == file.id }
    }

    func clearFiles() {
        files.removeAll()
    }

    // MARK: - Settings

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose output folder"
        if let current = settings.outputDirectory {
            panel.directoryURL = current
        }
        let response = panel.runModal()
        if response == .OK, let url = panel.url {
            settings.outputDirectory = url
        }
    }

    func browseForFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = InputFormat.allowedUTTypes
        panel.prompt = "Add"
        panel.message = "Add images or a folder"
        let response = panel.runModal()
        if response == .OK {
            addURLs(panel.urls)
        }
    }

    // MARK: - Run / cancel

    var canStart: Bool {
        !files.isEmpty && settings.isReady && phase != .running
    }

    func start() {
        guard canStart else { return }
        guard let _ = settings.outputDirectory else { return }

        summary = nil
        completed = 0
        total = files.count
        progress = 0
        currentFilename = nil
        phase = .running

        let snapshot = files
        let settingsSnapshot = settings

        let converter = self.converter
        job = Task { [weak self] in
            let stream = converter.convert(files: snapshot, settings: settingsSnapshot)
            for await event in stream {
                guard let self else { return }
                self.apply(event)
            }
        }
    }

    func cancel() {
        job?.cancel()
    }

    func dismissCompletion() {
        phase = .idle
        summary = nil
        completed = 0
        total = 0
        progress = 0
        currentFilename = nil
    }

    // MARK: - Event handling

    private func apply(_ event: ConversionEvent) {
        switch event {
        case .willStart(let file):
            currentFilename = file.displayName
        case .didComplete(_, let done, let tot):
            completed = done
            total = tot
            progress = tot > 0 ? Double(done) / Double(tot) : 0
        case .didFinish(let summary):
            self.summary = summary
            self.phase = .completed
            self.currentFilename = nil
            self.job = nil
        }
    }

    // MARK: - Formatting helpers for UI

    var progressText: String {
        total > 0 ? "\(completed) / \(total)" : ""
    }
}
