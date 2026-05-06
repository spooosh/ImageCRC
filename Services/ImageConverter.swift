import Foundation
import CoreGraphics

struct ImageConverter: Converter {
    /// Run a batch conversion job. Returns a stream of events the caller can observe for
    /// progress, per-file completion, and the final summary. Cancelling the consumer (or the
    /// enclosing Task) cancels all in-flight work.
    func convert(
        files: [ImageFile],
        settings: ConversionSettings
    ) -> AsyncStream<ConversionEvent> {
        AsyncStream { continuation in
            let job = Task.detached(priority: .userInitiated) {
                await Self.run(files: files, settings: settings, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                job.cancel()
            }
        }
    }

    private static func run(
        files: [ImageFile],
        settings: ConversionSettings,
        continuation: AsyncStream<ConversionEvent>.Continuation
    ) async {
        let total = files.count
        guard let outputDir = settings.outputDirectory else {
            let summary = ConversionSummary(
                total: total,
                successes: [],
                failures: files.map { f in
                    ConversionResult(id: UUID(), source: f.url, outcome: .failure(.outputDirectoryMissing))
                },
                cancelled: 0,
                outputDirectory: URL(fileURLWithPath: NSHomeDirectory())
            )
            continuation.yield(.didFinish(summary: summary))
            continuation.finish()
            return
        }

        do {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        } catch {
            let failures = files.map { f in
                ConversionResult(
                    id: UUID(),
                    source: f.url,
                    outcome: .failure(.writeFailed(url: outputDir, underlying: error.localizedDescription))
                )
            }
            let summary = ConversionSummary(
                total: total,
                successes: [],
                failures: failures,
                cancelled: 0,
                outputDirectory: outputDir
            )
            continuation.yield(.didFinish(summary: summary))
            continuation.finish()
            return
        }

        let resolver = FilenameResolver()
        let concurrency = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let quality = settings.normalizedQuality
        let format = settings.outputFormat
        let resize = settings.resize

        var successes: [ConversionResult] = []
        var failures: [ConversionResult] = []
        var cancelledCount = 0
        var completed = 0

        await withTaskGroup(of: ConversionResult.self) { group in
            var iterator = files.makeIterator()

            func spawnNext() -> Bool {
                guard let file = iterator.next() else { return false }
                continuation.yield(.willStart(file: file))
                group.addTask {
                    await processOne(
                        file: file,
                        outputDir: outputDir,
                        format: format,
                        quality: quality,
                        resize: resize,
                        resolver: resolver
                    )
                }
                return true
            }

            for _ in 0..<concurrency {
                if Task.isCancelled { break }
                if !spawnNext() { break }
            }

            while let result = await group.next() {
                completed += 1
                switch result.outcome {
                case .success:   successes.append(result)
                case .failure:   failures.append(result)
                case .cancelled: cancelledCount += 1
                }
                continuation.yield(.didComplete(result: result, completed: completed, total: total))

                if Task.isCancelled {
                    // Drain remaining file list as cancelled.
                    while let file = iterator.next() {
                        cancelledCount += 1
                        completed += 1
                        let r = ConversionResult(id: UUID(), source: file.url, outcome: .cancelled)
                        continuation.yield(.didComplete(result: r, completed: completed, total: total))
                    }
                    continue
                }
                _ = spawnNext()
            }
        }

        let summary = ConversionSummary(
            total: total,
            successes: successes,
            failures: failures,
            cancelled: cancelledCount,
            outputDirectory: outputDir
        )
        continuation.yield(.didFinish(summary: summary))
        continuation.finish()
    }

    private static func processOne(
        file: ImageFile,
        outputDir: URL,
        format: OutputFormat,
        quality: Double,
        resize: ResizeSettings,
        resolver: FilenameResolver
    ) async -> ConversionResult {
        if Task.isCancelled {
            return ConversionResult(id: UUID(), source: file.url, outcome: .cancelled)
        }

        let plan = OutputPlanner.plan(for: file.inputFormat, selected: format)
        let baseName = file.url.deletingPathExtension().lastPathComponent

        switch plan {
        case .encode(let encoderFormat):
            do {
                let cgImage = try ImageDecoder.decode(file: file)
                if Task.isCancelled {
                    return ConversionResult(id: UUID(), source: file.url, outcome: .cancelled)
                }
                let resized = ImageResizer.resize(cgImage, settings: resize)
                if Task.isCancelled {
                    return ConversionResult(id: UUID(), source: file.url, outcome: .cancelled)
                }
                let data = try await ImageEncoder.encode(image: resized, to: encoderFormat, quality: quality)
                if Task.isCancelled {
                    return ConversionResult(id: UUID(), source: file.url, outcome: .cancelled)
                }

                let outputURL = await resolver.resolve(
                    outputDirectory: outputDir,
                    baseName: baseName,
                    ext: encoderFormat.fileExtension
                )
                do {
                    try data.write(to: outputURL, options: .atomic)
                } catch {
                    return ConversionResult(
                        id: UUID(),
                        source: file.url,
                        outcome: .failure(.writeFailed(url: outputURL, underlying: error.localizedDescription))
                    )
                }

                return ConversionResult(
                    id: UUID(),
                    source: file.url,
                    outcome: .success(
                        outputURL: outputURL,
                        originalBytes: file.byteSize,
                        outputBytes: Int64(data.count)
                    )
                )
            } catch let err as ConversionError {
                return ConversionResult(id: UUID(), source: file.url, outcome: .failure(err))
            } catch {
                return ConversionResult(
                    id: UUID(),
                    source: file.url,
                    outcome: .failure(.decodeFailed(url: file.url, underlying: error.localizedDescription))
                )
            }

        case .copy:
            let outputURL = await resolver.resolve(
                outputDirectory: outputDir,
                baseName: baseName,
                ext: "svg"
            )
            if Task.isCancelled {
                return ConversionResult(id: UUID(), source: file.url, outcome: .cancelled)
            }
            do {
                try FileManager.default.copyItem(at: file.url, to: outputURL)
            } catch {
                return ConversionResult(
                    id: UUID(),
                    source: file.url,
                    outcome: .failure(.writeFailed(url: outputURL, underlying: error.localizedDescription))
                )
            }
            return ConversionResult(
                id: UUID(),
                source: file.url,
                outcome: .success(
                    outputURL: outputURL,
                    originalBytes: file.byteSize,
                    outputBytes: file.byteSize
                )
            )
        }
    }
}
