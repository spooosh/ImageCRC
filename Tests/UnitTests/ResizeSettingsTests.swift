// Tests/UnitTests/ResizeSettingsTests.swift
import Testing
@testable import ImageCRC

@Suite("ResizeSettings")
struct ResizeSettingsTests {
    @Test("default is inactive with fit mode and no enlarge")
    func defaults() {
        let r = ResizeSettings()
        #expect(r.isActive == false)
        #expect(r.mode == .fit)
        #expect(r.width == nil)
        #expect(r.height == nil)
        #expect(r.enlarge == false)
    }

    @Test("isActive flips once any dimension is set")
    func isActive() {
        var r = ResizeSettings()
        r.width = 100
        #expect(r.isActive)
        r.width = nil
        r.height = 100
        #expect(r.isActive)
        r.width = 200
        r.height = 200
        #expect(r.isActive)
        r.width = nil
        r.height = nil
        #expect(r.isActive == false)
    }
}
