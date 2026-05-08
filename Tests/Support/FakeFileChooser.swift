import Foundation
import UniformTypeIdentifiers
@testable import ImageCRC

/// Test double for `FileChooser`. Returns scripted URLs on each invocation.
@MainActor
final class FakeFileChooser: FileChooser {
    var directoryToReturn: URL?
    var filesToReturn: [URL]

    private(set) var lastChooseDirectoryInitial: URL?
    private(set) var lastChooseFilesAllowedTypes: [UTType] = []

    init(directoryToReturn: URL? = nil, filesToReturn: [URL] = []) {
        self.directoryToReturn = directoryToReturn
        self.filesToReturn = filesToReturn
    }

    @MainActor func chooseDirectory(initial: URL?) -> URL? {
        lastChooseDirectoryInitial = initial
        return directoryToReturn
    }

    @MainActor func chooseFiles(allowedTypes: [UTType]) -> [URL] {
        lastChooseFilesAllowedTypes = allowedTypes
        return filesToReturn
    }
}
