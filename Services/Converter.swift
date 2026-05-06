import Foundation

/// Abstraction over batch image conversion. Production uses `ImageConverter`;
/// tests inject a `FakeConverter` from `Tests/Support/`.
protocol Converter: Sendable {
    func convert(files: [ImageFile], settings: ConversionSettings) -> AsyncStream<ConversionEvent>
}
