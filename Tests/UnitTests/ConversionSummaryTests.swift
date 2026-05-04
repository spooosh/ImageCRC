// Tests/UnitTests/ConversionSummaryTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("ConversionSummary")
struct ConversionSummaryTests {
    private func successResult(orig: Int64, out: Int64) -> ConversionResult {
        ConversionResult(
            id: UUID(),
            source: URL(fileURLWithPath: "/tmp/in.jpg"),
            outcome: .success(
                outputURL: URL(fileURLWithPath: "/tmp/out.jpg"),
                originalBytes: orig,
                outputBytes: out
            )
        )
    }

    @Test("totalOriginalBytes and totalOutputBytes sum only successes")
    func totals() {
        let summary = ConversionSummary(
            total: 3,
            successes: [successResult(orig: 1000, out: 400),
                        successResult(orig: 2000, out: 600)],
            failures: [],
            cancelled: 0,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        #expect(summary.totalOriginalBytes == 3000)
        #expect(summary.totalOutputBytes == 1000)
    }

    @Test("savingsRatio is 1 - out/orig")
    func savingsRatioComputed() {
        let summary = ConversionSummary(
            total: 1,
            successes: [successResult(orig: 1000, out: 250)],
            failures: [],
            cancelled: 0,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        let ratio = try! #require(summary.savingsRatio)
        #expect(abs(ratio - 0.75) < 1e-9)
    }

    @Test("savingsRatio is nil when no successes")
    func savingsRatioNilWhenEmpty() {
        let summary = ConversionSummary(
            total: 0,
            successes: [],
            failures: [],
            cancelled: 0,
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        #expect(summary.savingsRatio == nil)
    }

    @Test("wasCancelled mirrors cancelled > 0")
    func wasCancelled() {
        let s0 = ConversionSummary(total: 1, successes: [], failures: [], cancelled: 0,
                                   outputDirectory: URL(fileURLWithPath: "/tmp"))
        let s1 = ConversionSummary(total: 1, successes: [], failures: [], cancelled: 1,
                                   outputDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(s0.wasCancelled == false)
        #expect(s1.wasCancelled == true)
    }
}
