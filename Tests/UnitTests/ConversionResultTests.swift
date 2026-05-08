// Tests/UnitTests/ConversionResultTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("ConversionResult")
struct ConversionResultTests {
    private func make(_ outcome: ConversionResult.Outcome) -> ConversionResult {
        ConversionResult(id: UUID(), source: URL(fileURLWithPath: "/tmp/in.jpg"), outcome: outcome)
    }

    @Test("isSuccess and isFailure mirror the Outcome case")
    func helpers() {
        let success = make(.success(outputURL: URL(fileURLWithPath: "/tmp/out.jpg"),
                                    originalBytes: 100, outputBytes: 80))
        let failure = make(.failure(.outputDirectoryMissing))
        let cancelled = make(.cancelled)

        #expect(success.isSuccess == true)
        #expect(success.isFailure == false)

        #expect(failure.isSuccess == false)
        #expect(failure.isFailure == true)

        #expect(cancelled.isSuccess == false)
        #expect(cancelled.isFailure == false,
                "cancelled is neither success nor failure — own bucket")
    }
}
