import Foundation

enum ConversionError: LocalizedError, Sendable {
    case decodeFailed(url: URL, underlying: String?)
    case encodeFailed(format: OutputFormat, underlying: String?)
    case writeFailed(url: URL, underlying: String?)
    case outputDirectoryMissing
    case unsupportedInput(URL)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .decodeFailed(let url, let underlying):
            let base = "Could not decode \(url.lastPathComponent)"
            return underlying.map { "\(base): \($0)" } ?? base
        case .encodeFailed(let format, let underlying):
            let base = "Could not encode as \(format.displayName)"
            return underlying.map { "\(base): \($0)" } ?? base
        case .writeFailed(let url, let underlying):
            let base = "Could not write \(url.lastPathComponent)"
            return underlying.map { "\(base): \($0)" } ?? base
        case .outputDirectoryMissing:
            return "Output directory is not set"
        case .unsupportedInput(let url):
            return "Unsupported input file: \(url.lastPathComponent)"
        case .cancelled:
            return "Cancelled"
        }
    }
}
