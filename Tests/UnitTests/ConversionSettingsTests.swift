// Tests/UnitTests/ConversionSettingsTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("ConversionSettings")
struct ConversionSettingsTests {
    @Test("default has documented baseline")
    func defaultBaseline() {
        let s = ConversionSettings.default
        #expect(s.quality == 80)
        #expect(s.outputFormat == .jpeg)
        #expect(s.resize == ResizeSettings())
        // outputDirectory depends on FileManager.urls(for: .picturesDirectory).
        // Some sandboxed CI runners lack ~/Pictures; in that case the resolver
        // returns nil, which is a valid state. When non-nil, the directory
        // must end in "ImageCRC".
        if let dir = s.outputDirectory {
            #expect(dir.lastPathComponent == "ImageCRC")
        }
    }

    @Test("normalizedQuality clamps and scales")
    func normalizedQuality() {
        var s = ConversionSettings.default
        s.quality = 0;   #expect(s.normalizedQuality == 0.0)
        s.quality = 50;  #expect(s.normalizedQuality == 0.5)
        s.quality = 100; #expect(s.normalizedQuality == 1.0)
        s.quality = 150; #expect(s.normalizedQuality == 1.0)
        s.quality = -1;  #expect(s.normalizedQuality == 0.0)
    }

    @Test("isReady mirrors outputDirectory presence")
    func isReady() {
        var s = ConversionSettings.default
        s.outputDirectory = nil
        #expect(s.isReady == false)
        s.outputDirectory = URL(fileURLWithPath: "/tmp")
        #expect(s.isReady == true)
    }
}
