import Testing
@testable import ImageCRC

@Suite("Package wiring")
struct PackageWiringTests {
    @Test("ConversionSettings.default has expected baseline values")
    func defaultSettings() {
        let settings = ConversionSettings.default
        #expect(settings.quality == 80)
        #expect(settings.outputFormat == .jpeg)
    }

    @Test("normalizedQuality clamps to 0...1 and scales linearly")
    func normalizedQualityClamps() {
        var settings = ConversionSettings.default
        settings.quality = 0
        #expect(settings.normalizedQuality == 0.0)
        settings.quality = 50
        #expect(settings.normalizedQuality == 0.5)
        settings.quality = 100
        #expect(settings.normalizedQuality == 1.0)
        settings.quality = 150
        #expect(settings.normalizedQuality == 1.0)
        settings.quality = -10
        #expect(settings.normalizedQuality == 0.0)
    }
}
