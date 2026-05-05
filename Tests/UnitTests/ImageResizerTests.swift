// Tests/UnitTests/ImageResizerTests.swift
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("ImageResizer — no-op")
struct ImageResizerNoopTests {
    @Test("inactive settings return the input dimensions unchanged")
    func inactivePassesThrough() {
        let img = SyntheticImage.solid(width: 200, height: 100)
        let out = ImageResizer.resize(img, settings: ResizeSettings())
        // Phase 2 may add unconditional colorspace normalisation that breaks
        // pointer-identity; assert dims only. The "no work was done" perf
        // contract is enforced by code review, not this unit test.
        #expect(out.width == 200)
        #expect(out.height == 100)
    }

    @Test("explicit dimensions equal to source produce a no-op")
    func samesizeNoop() {
        let img = SyntheticImage.solid(width: 200, height: 100)
        var s = ResizeSettings()
        s.width = 200
        s.height = 100
        s.mode = .fit
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 200 && out.height == 100)
    }
}

@Suite("ImageResizer — fit")
struct ImageResizerFitTests {
    @Test("fit picks the smaller of the two scale factors")
    func fitDownscaleByMin() {
        // 400x200 source, target 100x100 fit → scale = min(0.25, 0.5) = 0.25
        // → output 100x50
        let img = SyntheticImage.solid(width: 400, height: 200)
        var s = ResizeSettings()
        s.width = 100
        s.height = 100
        s.mode = .fit
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 100)
        #expect(out.height == 50)
    }

    @Test("fit with only width set scales by width ratio")
    func fitWidthOnly() {
        let img = SyntheticImage.solid(width: 400, height: 200)
        var s = ResizeSettings()
        s.width = 200
        s.mode = .fit
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 200)
        #expect(out.height == 100)
    }

    @Test("enlarge=false caps scale at 1.0 so upscale targets become no-op")
    func noUpscaleGuard() {
        let img = SyntheticImage.solid(width: 100, height: 100)
        var s = ResizeSettings()
        s.width = 400
        s.height = 400
        s.mode = .fit
        s.enlarge = false
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 100, "enlarge=false must not upscale")
        #expect(out.height == 100)
    }

    @Test("enlarge=true allows scale > 1.0")
    func enlargeAllowsUpscale() {
        let img = SyntheticImage.solid(width: 100, height: 100)
        var s = ResizeSettings()
        s.width = 200
        s.height = 200
        s.mode = .fit
        s.enlarge = true
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 200)
        #expect(out.height == 200)
    }
}

@Suite("ImageResizer — fill")
struct ImageResizerFillTests {
    @Test("fill with both dims crops to the smaller-of-(intermediate, target)")
    func fillCropsToTarget() {
        // 400x200 → target 100x100 fill → scale = max(0.25, 0.5) = 0.5
        // → intermediate 200x100; output = min(200,100) x min(100,100) = 100x100
        let img = SyntheticImage.solid(width: 400, height: 200)
        var s = ResizeSettings()
        s.width = 100
        s.height = 100
        s.mode = .fill
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 100)
        #expect(out.height == 100)
    }

    @Test("fill with one dim only behaves like fit")
    func fillWithOneDim() {
        let img = SyntheticImage.solid(width: 400, height: 200)
        var s = ResizeSettings()
        s.height = 50
        s.mode = .fill
        let out = ImageResizer.resize(img, settings: s)
        // Without both targets, fill geometry path is bypassed → behaves like fit.
        #expect(out.width == 100)
        #expect(out.height == 50)
    }

    @Test("fill with both dims and enlarge=false caps at source dims")
    func fillNoUpscale() {
        // 100x100 source, target 400x400 fill, enlarge=false.
        // raw scale = max(4, 4) = 4 → clamped to 1 → intermediate 100x100;
        // fill geometry: outputW = min(100, 400) = 100; same for H.
        let img = SyntheticImage.solid(width: 100, height: 100)
        var s = ResizeSettings()
        s.width = 400
        s.height = 400
        s.mode = .fill
        s.enlarge = false
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 100, "fill+enlarge=false must not upscale")
        #expect(out.height == 100)
    }

    @Test("fill with enlarge=true upscales then crops to target")
    func fillEnlargeAndCrop() {
        // 100x50 source, target 200x200 fill, enlarge=true.
        // raw scale = max(2, 4) = 4 → intermediate 400x200;
        // fill geometry: outputW = min(400, 200) = 200; outputH = min(200, 200) = 200;
        // drawX = (200 - 400) / 2 = -100, drawY = 0 — centered horizontal crop.
        let img = SyntheticImage.solid(width: 100, height: 50)
        var s = ResizeSettings()
        s.width = 200
        s.height = 200
        s.mode = .fill
        s.enlarge = true
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 200)
        #expect(out.height == 200)
    }

    @Test("fill with aspect-matching dims produces no crop")
    func fillNoCropWhenAspectMatches() {
        // 200x100 source, target 100x50 (same 2:1 aspect) fill.
        // scale = max(0.5, 0.5) = 0.5 → intermediate 100x50;
        // fill geometry: outputW = min(100, 100), outputH = min(50, 50);
        // drawX = drawY = 0.
        let img = SyntheticImage.solid(width: 200, height: 100)
        var s = ResizeSettings()
        s.width = 100
        s.height = 50
        s.mode = .fill
        let out = ImageResizer.resize(img, settings: s)
        #expect(out.width == 100)
        #expect(out.height == 50)
    }
}
