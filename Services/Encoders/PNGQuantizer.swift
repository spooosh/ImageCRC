import Foundation

/// Subprocess bridge to `pngquant` (libimagequant) for lossy PNG compression.
/// Caller must ensure `quality < 100` — at `quality == 100` we emit the pure
/// lossless ImageIO PNG and skip quantization entirely.
enum PNGQuantizer {
    static func quantize(pngData: Data, quality: Int) async throws -> Data {
        let binaryURL = try locateBinary()

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [
            "--quality", "0-\(max(0, min(99, quality)))",
            "--speed", "4",
            "--strip",
            "--output", "-",
            "-",
        ]

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                let outBox = ByteBox()
                let errBox = ByteBox()
                let ioGroup = DispatchGroup()
                let ioQueue = DispatchQueue.global(qos: .userInitiated)

                ioGroup.enter()
                ioQueue.async {
                    outBox.data = stdout.fileHandleForReading.readDataToEndOfFile()
                    ioGroup.leave()
                }
                ioGroup.enter()
                ioQueue.async {
                    errBox.data = stderr.fileHandleForReading.readDataToEndOfFile()
                    ioGroup.leave()
                }

                process.terminationHandler = { proc in
                    ioGroup.wait()
                    let status = proc.terminationStatus
                    if status == 0 {
                        continuation.resume(returning: outBox.data)
                    } else {
                        let message = String(data: errBox.data, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let detail = (message?.isEmpty == false) ? ": \(message!)" : ""
                        continuation.resume(throwing: ConversionError.encodeFailed(
                            format: .png,
                            underlying: "pngquant exit \(status)\(detail)"
                        ))
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: ConversionError.encodeFailed(
                        format: .png,
                        underlying: "pngquant launch failed: \(error.localizedDescription)"
                    ))
                    return
                }

                ioQueue.async {
                    let handle = stdin.fileHandleForWriting
                    defer { try? handle.close() }
                    try? handle.write(contentsOf: pngData)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    // MARK: - Binary lookup

    private static let candidateBinaryPaths = [
        "/opt/homebrew/bin/pngquant",
        "/usr/local/bin/pngquant",
        "/usr/bin/pngquant",
    ]

    private static func locateBinary() throws -> URL {
        if let bundled = Bundle.main.url(
            forResource: "pngquant",
            withExtension: nil,
            subdirectory: "bin"
        ), FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        for path in candidateBinaryPaths
        where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw ConversionError.encodeFailed(
            format: .png,
            underlying: "pngquant binary not found. Install via: brew install pngquant"
        )
    }

    private final class ByteBox: @unchecked Sendable {
        var data = Data()
    }
}
