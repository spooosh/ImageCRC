import Foundation
@testable import ImageCRC

/// Test double for `Converter`. The caller scripts the events that the
/// returned AsyncStream will emit, in order. The stream finishes after the
/// last event is yielded. Cancellation is honoured: if the consuming task
/// is cancelled, the stream stops yielding remaining events.
///
/// Note: callers must script `.didFinish` to terminate the VM's running
/// phase. With an empty events array the stream finishes immediately
/// without ever yielding `.didFinish`, leaving the VM stuck in `.running`.
struct FakeConverter: Converter {
    let events: [ConversionEvent]

    init(events: [ConversionEvent] = []) {
        self.events = events
    }

    func convert(files: [ImageFile], settings: ConversionSettings) -> AsyncStream<ConversionEvent> {
        AsyncStream { continuation in
            let job = Task {
                for event in events {
                    if Task.isCancelled { break }
                    continuation.yield(event)
                    // Yield to the runloop between events so the consuming VM
                    // can apply each one before the next arrives — closer to
                    // how the real ImageConverter behaves.
                    await Task.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                job.cancel()
            }
        }
    }
}
