import Foundation

enum ConversionEvent: Sendable {
    case willStart(file: ImageFile)
    case didComplete(result: ConversionResult, completed: Int, total: Int)
    case didFinish(summary: ConversionSummary)
}
