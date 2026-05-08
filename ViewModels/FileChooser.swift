import Foundation
import AppKit
import UniformTypeIdentifiers

/// Abstraction over NSOpenPanel for production; tests inject FakeFileChooser
/// from Tests/Support/.
protocol FileChooser {
    @MainActor func chooseDirectory(initial: URL?) -> URL?
    @MainActor func chooseFiles(allowedTypes: [UTType]) -> [URL]
}

/// Production implementation using NSOpenPanel modally on the main thread.
struct AppKitFileChooser: FileChooser {
    @MainActor func chooseDirectory(initial: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose output folder"
        if let initial { panel.directoryURL = initial }
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor func chooseFiles(allowedTypes: [UTType]) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = allowedTypes
        panel.prompt = "Add"
        panel.message = "Add images or a folder"
        return panel.runModal() == .OK ? panel.urls : []
    }
}
