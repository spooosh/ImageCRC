import Foundation

struct ConversionResult: Identifiable, Sendable {
    let id: UUID
    let source: URL
    let outcome: Outcome

    enum Outcome: Sendable {
        case success(outputURL: URL, originalBytes: Int64, outputBytes: Int64)
        case failure(ConversionError)
        case cancelled
    }

    var isSuccess: Bool {
        if case .success = outcome { return true }
        return false
    }

    var isFailure: Bool {
        if case .failure = outcome { return true }
        return false
    }
}

struct ConversionSummary: Sendable {
    let total: Int
    let successes: [ConversionResult]
    let failures: [ConversionResult]
    let cancelled: Int
    let outputDirectory: URL

    var wasCancelled: Bool { cancelled > 0 }

    var totalOriginalBytes: Int64 {
        successes.reduce(0) { acc, r in
            if case .success(_, let orig, _) = r.outcome { return acc + orig }
            return acc
        }
    }

    var totalOutputBytes: Int64 {
        successes.reduce(0) { acc, r in
            if case .success(_, _, let out) = r.outcome { return acc + out }
            return acc
        }
    }

    var savingsRatio: Double? {
        guard totalOriginalBytes > 0 else { return nil }
        return 1.0 - Double(totalOutputBytes) / Double(totalOriginalBytes)
    }
}
