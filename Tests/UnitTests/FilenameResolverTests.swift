// Tests/UnitTests/FilenameResolverTests.swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("FilenameResolver")
struct FilenameResolverTests {
    @Test("first resolve uses base name as-is")
    func firstResolveBare() async throws {
        let tmp = try TempDirectory()
        let r = FilenameResolver()
        let url = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: "jpg")
        #expect(url.lastPathComponent == "photo.jpg")
        #expect(url.deletingLastPathComponent().path == tmp.url.path)
    }

    @Test("repeated resolves disambiguate sequentially")
    func collisionInMemory() async throws {
        let tmp = try TempDirectory()
        let r = FilenameResolver()
        let a = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: "jpg")
        let b = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: "jpg")
        let c = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: "jpg")
        #expect(a.lastPathComponent == "photo.jpg")
        #expect(b.lastPathComponent == "photo (1).jpg")
        #expect(c.lastPathComponent == "photo (2).jpg")
    }

    @Test("existing on-disk files are skipped")
    func collisionOnDisk() async throws {
        let tmp = try TempDirectory()
        let preexisting = tmp.url.appendingPathComponent("photo.jpg")
        try Data().write(to: preexisting)
        let r = FilenameResolver()
        let url = await r.resolve(outputDirectory: tmp.url, baseName: "photo", ext: "jpg")
        #expect(url.lastPathComponent == "photo (1).jpg")
    }

    @Test("parallel resolves never return the same path")
    func parallelUnique() async throws {
        let tmp = try TempDirectory()
        let r = FilenameResolver()
        // Task.detached forces each call onto its own task; without it, async let
        // on a non-async actor method serialises through the actor's executor
        // and the test never actually exercises concurrent contention.
        async let a = Task.detached { await r.resolve(outputDirectory: tmp.url, baseName: "p", ext: "png") }.value
        async let b = Task.detached { await r.resolve(outputDirectory: tmp.url, baseName: "p", ext: "png") }.value
        async let c = Task.detached { await r.resolve(outputDirectory: tmp.url, baseName: "p", ext: "png") }.value
        async let d = Task.detached { await r.resolve(outputDirectory: tmp.url, baseName: "p", ext: "png") }.value
        let urls = await [a, b, c, d]
        let paths = urls.map { $0.path }
        #expect(Set(paths).count == 4, "all parallel resolves must yield unique paths; got \(paths)")
    }

    @Test("reset() releases reserved names")
    func resetClears() async throws {
        let tmp = try TempDirectory()
        let r = FilenameResolver()
        _ = await r.resolve(outputDirectory: tmp.url, baseName: "x", ext: "png")
        await r.reset()
        let after = await r.resolve(outputDirectory: tmp.url, baseName: "x", ext: "png")
        #expect(after.lastPathComponent == "x.png")
    }
}
