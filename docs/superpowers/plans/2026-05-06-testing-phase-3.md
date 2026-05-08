# ImageCRC Phase 3 — Concurrency, Cancellation, ViewModel + Phase 2 Sweep

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cover the orchestrator (`ImageConverter`), the cancellation contract, and the `ConversionViewModel` event-driven UI bridge with end-to-end integration tests. Land the two protocol extractions (`Converter`, `FileChooser`) needed to inject fakes for VM tests. Sweep two open holes from Phase 2 (TIFF-dict EXIF fallback, pixel tests for less-common orientations).

**Architecture:** Two protocol extractions land first as production refactors (Section A) — small surface, high-leverage. Then test infrastructure (Section B) adds an `IntegrationTests/` source dir + `FakeConverter` + `FakeFileChooser` helpers. Sections C–E exercise the orchestrator: batch happy paths (C), error paths (D), cancellation drain semantics (E). Section F covers the VM via the fake. Section G sweeps Phase 2 holes.

**Tech Stack:** Swift 5.10, Swift Testing, `@MainActor @Observable` for VM, `AsyncStream<ConversionEvent>` for converter→VM bridge, `actor FilenameResolver` for collision arbitration. Integration tests synthesise inputs via `SyntheticImage` and write to `TempDirectory` (no on-disk fixtures, same policy as Phase 2).

> **User policy:** Per spooosh's standing preference, never run `git commit` without explicit approval. Subagents may commit on the `tests/phase-1` branch. All Phase 1, 2, 3 work merges to `main` as one batch when Phase 6 finishes.

---

## Section Overview

| # | Section | Tasks | Goal |
|---|---------|-------|------|
| A | Protocol extractions | T1–T2 | Land `Converter` + `FileChooser` production refactor (small surface, enables VM injection) |
| B | Test infra | T3–T5 | `Tests/IntegrationTests/` wiring + `FakeConverter` + `FakeFileChooser` helpers |
| C | ImageConverter happy path | T6 | Batch of N synthesised PNGs → JPEG: monotonic progress, exact event count, all-success |
| D | ImageConverter error paths | T7 | `outputDirectory == nil` → all `outputDirectoryMissing`; write to read-only dir → all `writeFailed` |
| E | Cancellation | T8 | Cancel mid-batch — drain semantics, `successes + failures + cancelled == total`, monotonic counter to total, `wasCancelled == true` |
| F | ViewModel | T9–T10 | VM phase transitions through scripted events (`FakeConverter`); `canStart`/`cancel`/`dismissCompletion` semantics |
| G | Phase 2 sweep | T11–T12 | TIFF-dictionary fallback for EXIF orientation; pixel tests for the less-common 180°/mirrored EXIF cases |

**Phase 3 done when:**

- `swift test` exits 0 with 76 tests + 1 skipped = 77 reported across 26 suites (Phase 2 left 61/21 + 1 skipped; this phase adds 15 tests across 5 new suites)
- No SwiftPM warnings beyond pre-existing two
- `Converter` protocol exists; `ImageConverter` conforms; `ConversionViewModel.start()` calls through the injected `Converter`
- `FileChooser` protocol exists; `AppKitFileChooser` is the production impl; `chooseOutputDirectory()` and `browseForFiles()` route through it
- `ImageConverter` integration tests cover: batch all-success; output-dir nil; output-dir create fails; cancel mid-batch; cancel before start
- VM tests cover: idle → running → completed transitions; `canStart` guards; `cancel()` cancels job and surfaces summary; `dismissCompletion()` resets
- `ImageIODecoder` reads orientation from the nested TIFF dict as a fallback when not on top level
- Less-common EXIF orientations (3 = 180°, 5/7 = mirrored 90°) have at least dim-swap coverage; orientations 2, 4 (mirrored 0/180°) optional
- User approval to write Phase 4 plan

**Estimated time:** 2–3 days. Section A + B is the highest-risk part (production refactor); C–G are largely test-additive.

---

## File structure delta

```
ImageCRC/                          # Production (refactored)
├── Services/
│   ├── Converter.swift            # NEW — protocol
│   ├── ImageConverter.swift       # MODIFIED — struct conforming to Converter
│   └── ...
└── ViewModels/
    ├── ConversionViewModel.swift  # MODIFIED — Converter + FileChooser injection
    └── FileChooser.swift          # NEW — protocol + AppKitFileChooser

Tests/
├── Support/
│   ├── FakeConverter.swift        # NEW — scripted-event Converter
│   └── FakeFileChooser.swift      # NEW — scripted-URL FileChooser
├── UnitTests/                     # unchanged
├── CodecTests/                    # adds T11, T12 to existing EXIFOrientationTests.swift
└── IntegrationTests/              # NEW dir, Section C–F
    ├── ImageConverterBatchTests.swift
    ├── ImageConverterErrorTests.swift
    ├── ImageConverterCancelTests.swift
    └── ConversionViewModelTests.swift
```

`Package.swift` test target: extend `sources` from `["Support", "UnitTests", "CodecTests"]` to `["Support", "UnitTests", "CodecTests", "IntegrationTests"]`. Mirror in `project.yml`.

For production: also need `Package.swift` `sources` for the executable target to pick up the new files. Currently the source roots are `App, Models, ViewModels, Services, Views`. New files live in those existing roots — no Package.swift change for production.

---

# Section A — Protocol extractions

---

### Task 1: `Converter` protocol + `ImageConverter` conformance + VM injection

**Why:** `ConversionViewModel.start()` directly calls `ImageConverter.convert(...)`. To test the VM we need to inject a fake. Lift the static func behind a protocol with an instance method, default the VM's parameter to the production impl so app entry-point doesn't change.

**Files:**
- Create: `Services/Converter.swift`
- Modify: `Services/ImageConverter.swift` (enum → struct; static → instance)
- Modify: `ViewModels/ConversionViewModel.swift` (init + call site)

- [ ] **Step 1: Create `Services/Converter.swift`**

```swift
import Foundation

/// Abstraction over batch image conversion. Production uses `ImageConverter`;
/// tests inject a `FakeConverter` from `Tests/Support/`.
protocol Converter: Sendable {
    func convert(files: [ImageFile], settings: ConversionSettings) -> AsyncStream<ConversionEvent>
}
```

- [ ] **Step 2: Convert `ImageConverter` to struct + instance method**

In `Services/ImageConverter.swift`, change the type from `enum ImageConverter { static func convert(...) }` to `struct ImageConverter: Converter { func convert(...) }`. The function bodies (private static `run`, private static `processOne`) stay as `private static` — only the public entry point becomes an instance method.

Replace:
```swift
enum ImageConverter {
    static func convert(...) -> AsyncStream<ConversionEvent> { ... }
    private static func run(...) async { ... }
    private static func processOne(...) async -> ConversionResult { ... }
}
```

with:
```swift
struct ImageConverter: Converter {
    func convert(files: [ImageFile], settings: ConversionSettings) -> AsyncStream<ConversionEvent> {
        // body unchanged — but the inner `await run(...)` call references run as a static
        // member of the type, which still works since run remains private static.
        AsyncStream { continuation in
            let job = Task.detached(priority: .userInitiated) {
                await Self.run(files: files, settings: settings, continuation: continuation)
            }
            continuation.onTermination = { @Sendable _ in
                job.cancel()
            }
        }
    }

    private static func run(...) async { ... }      // body unchanged
    private static func processOne(...) async -> ConversionResult { ... }  // body unchanged
}
```

The only line-level changes: `enum` → `struct ImageConverter: Converter`, and the public `convert` becomes a non-static instance method, with its body wrapping `Self.run(...)` instead of `run(...)`.

- [ ] **Step 3: Update `ConversionViewModel` to inject `Converter`**

In `ViewModels/ConversionViewModel.swift`:

1. Add a stored property and inject via init (with production default):

```swift
@MainActor
@Observable
final class ConversionViewModel {
    // ... existing properties ...

    private let converter: any Converter

    init(converter: any Converter = ImageConverter()) {
        self.converter = converter
    }

    // ... rest unchanged ...
}
```

**If the `@Observable` macro complains about the existential `any Converter` stored property** (Swift 5.10 macro × existential interaction is mostly fine but not guaranteed), use the `@ObservationIgnored` attribute as a fallback — it tells the macro to skip the field entirely:

```swift
@ObservationIgnored
private let converter: any Converter
```

`converter` is a `let` constant and never observed by the UI, so excluding it from the `@Observable` machinery is correct regardless of whether the macro requires it.

2. Update the call site at line 127:

Before:
```swift
let stream = ImageConverter.convert(files: snapshot, settings: settingsSnapshot)
```

After:
```swift
let stream = converter.convert(files: snapshot, settings: settingsSnapshot)
```

- [ ] **Step 4: Verify production compiles + app entry unchanged**

`App/ImageCRCApp.swift:5` reads `@State private var viewModel = ConversionViewModel()`. The new init has a default value, so this call site is unchanged. Confirm by reading `ImageCRCApp.swift` and verifying no edits are needed.

Run `swift build -c release` — expect green. Run `swift test` — expect 61/21 + 1 skipped, NO regression in counts.

- [ ] **Step 5: Commit**

```bash
git add Services/Converter.swift Services/ImageConverter.swift ViewModels/ConversionViewModel.swift
git commit -m "$(cat <<'EOF'
refactor(converter): extract Converter protocol for VM injection

Lift the static convert(files:settings:) entry point onto a Converter
protocol with one instance method. ImageConverter becomes a struct
conforming to it; the private run/processOne stay as private static
since they have no per-instance state.

ConversionViewModel takes a `Converter` parameter with a default value
of `ImageConverter()`, so the app entry point in ImageCRCApp.swift is
unchanged. Tests can now inject a FakeConverter (Section B).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `FileChooser` protocol + `AppKitFileChooser` + VM injection

**Why:** VM's `chooseOutputDirectory()` and `browseForFiles()` call `NSOpenPanel.runModal()` directly. Untestable from a Swift Testing harness (modal panels block the runloop). Wrap in a protocol; VM tests can use `FakeFileChooser`.

**Files:**
- Create: `ViewModels/FileChooser.swift` (protocol + AppKit impl)
- Modify: `ViewModels/ConversionViewModel.swift` (inject + route through chooser)

- [ ] **Step 1: Create `ViewModels/FileChooser.swift`**

```swift
import Foundation
import AppKit
import UniformTypeIdentifiers

/// Abstraction over NSOpenPanel for production; tests inject FakeFileChooser
/// from Tests/Support/.
@MainActor
protocol FileChooser {
    func chooseDirectory(initial: URL?) -> URL?
    func chooseFiles(allowedTypes: [UTType]) -> [URL]
}

/// Production implementation using NSOpenPanel modally on the main thread.
@MainActor
struct AppKitFileChooser: FileChooser {
    func chooseDirectory(initial: URL?) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose output folder"
        if let initial { panel.directoryURL = initial }
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseFiles(allowedTypes: [UTType]) -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = allowedTypes
        panel.prompt = "Add"
        panel.message = "Add images or a folder"
        return panel.runModal() == .OK ? panel.urls : []
    }
}
```

- [ ] **Step 2: Update `ConversionViewModel` to inject `FileChooser`**

In `ConversionViewModel.swift`:

1. Add to init:

```swift
private let converter: any Converter
private let fileChooser: any FileChooser

init(
    converter: any Converter = ImageConverter(),
    fileChooser: any FileChooser = AppKitFileChooser()
) {
    self.converter = converter
    self.fileChooser = fileChooser
}
```

2. Replace the body of `chooseOutputDirectory()`:

Before:
```swift
func chooseOutputDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    // ... existing NSOpenPanel setup ...
    let response = panel.runModal()
    if response == .OK, let url = panel.url {
        settings.outputDirectory = url
    }
}
```

After:
```swift
func chooseOutputDirectory() {
    if let url = fileChooser.chooseDirectory(initial: settings.outputDirectory) {
        settings.outputDirectory = url
    }
}
```

3. Replace the body of `browseForFiles()`:

Before:
```swift
func browseForFiles() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    // ... existing NSOpenPanel setup ...
    let response = panel.runModal()
    if response == .OK {
        addURLs(panel.urls)
    }
}
```

After:
```swift
func browseForFiles() {
    let urls = fileChooser.chooseFiles(allowedTypes: InputFormat.allowedUTTypes)
    if !urls.isEmpty {
        addURLs(urls)
    }
}
```

4. Remove `import AppKit` from `ConversionViewModel.swift` if it's only used for `NSOpenPanel` — verify by checking the rest of the file. Currently the file has `import AppKit` because of NSOpenPanel; if no other AppKit symbols remain, drop the import. (Other VM code uses `Foundation` and `Observation` only.)

- [ ] **Step 3: Verify production compiles**

Run `swift build -c release` — expect green.

Run `swift test` — expect 61/21 + 1 skipped, no regression.

**Optional manual smoke (skip in autonomous execution):** if a human is available, run `./Scripts/make-app.sh` and `open ./ImageCRC.app` to manually click "Choose output folder" and "Add files" — confirms the panels still appear. The Section F VM tests (T10's `fileChooserRouting`) cover the routing correctness automatically; this manual smoke is belt-and-braces, not required for task completion.

- [ ] **Step 4: Commit**

```bash
git add ViewModels/FileChooser.swift ViewModels/ConversionViewModel.swift
git commit -m "$(cat <<'EOF'
refactor(vm): extract FileChooser protocol around NSOpenPanel

ConversionViewModel.chooseOutputDirectory and .browseForFiles previously
called NSOpenPanel.runModal directly. Wrap behind a FileChooser protocol
with an AppKitFileChooser production impl; VM tests inject a fake.

App entry point unchanged — VM's init defaults to AppKitFileChooser.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section B — Test infrastructure

---

### Task 3: Wire `Tests/IntegrationTests/` source dir

**Why:** Integration tests need their own directory. Defensive `.gitkeep` exclude follows the same pattern as Phase 2 Task 9 for CodecTests.

**Files:**
- Modify: `Package.swift` (extend test target sources)
- Modify: `project.yml` (mirror)
- Create: `Tests/IntegrationTests/.gitkeep`

- [ ] **Step 1: Update `Package.swift`**

Current:
```swift
        .testTarget(
            name: "ImageCRCTests",
            dependencies: ["ImageCRC"],
            path: "Tests",
            exclude: ["Fixtures", "CodecTests/.gitkeep"],
            sources: ["Support", "UnitTests", "CodecTests"]
        )
```

New:
```swift
        .testTarget(
            name: "ImageCRCTests",
            dependencies: ["ImageCRC"],
            path: "Tests",
            exclude: ["Fixtures", "CodecTests/.gitkeep", "IntegrationTests/.gitkeep"],
            sources: ["Support", "UnitTests", "CodecTests", "IntegrationTests"]
        )
```

- [ ] **Step 2: Update `project.yml`**

Append `- path: Tests/IntegrationTests` under `ImageCRCTests.sources`.

- [ ] **Step 3: Create the dir + .gitkeep**

```bash
mkdir -p Tests/IntegrationTests
touch Tests/IntegrationTests/.gitkeep
```

- [ ] **Step 4: Verify**

Run `swift build --target ImageCRCTests` — green.
Run `swift test` — expect 61/21 + 1 skipped.

- [ ] **Step 5: Commit**

```bash
git add Package.swift project.yml Tests/IntegrationTests/.gitkeep
git commit -m "$(cat <<'EOF'
chore(tests): wire Tests/IntegrationTests source dir for Phase 3

Same pattern as CodecTests in Phase 2 — add path to both Package.swift
sources and project.yml mirror, with a defensive .gitkeep exclude.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `FakeConverter` test helper

**Why:** VM tests need a `Converter` that emits scripted events without doing real work. Sits in `Tests/Support/` so both `IntegrationTests/` and (future) `UnitTests/` can use it.

**Files:**
- Create: `Tests/Support/FakeConverter.swift`

- [ ] **Step 1: Write the helper**

```swift
import Foundation
@testable import ImageCRC

/// Test double for `Converter`. The caller scripts the events that the
/// returned AsyncStream will emit, in order. The stream finishes after the
/// last event is yielded. Cancellation is honoured: if the consuming task
/// is cancelled, the stream stops yielding remaining events.
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
```

- [ ] **Step 2: Verify it compiles**

Run `swift build --target ImageCRCTests` — green.

- [ ] **Step 3: Commit**

```bash
git add Tests/Support/FakeConverter.swift
git commit -m "$(cat <<'EOF'
test(infra): add FakeConverter for VM event-flow tests

Scripts a sequence of ConversionEvents and yields them through an
AsyncStream, matching the real Converter contract. Used by Section F
to drive ConversionViewModel through phase transitions without
touching real codecs or files.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `FakeFileChooser` test helper

**Why:** VM tests for `chooseOutputDirectory()` and `browseForFiles()` need a fake. Scripted return values per call.

**Files:**
- Create: `Tests/Support/FakeFileChooser.swift`

- [ ] **Step 1: Write the helper**

```swift
import Foundation
import UniformTypeIdentifiers
@testable import ImageCRC

/// Test double for `FileChooser`. Returns scripted URLs on each invocation.
@MainActor
final class FakeFileChooser: FileChooser {
    var directoryToReturn: URL?
    var filesToReturn: [URL]

    private(set) var lastChooseDirectoryInitial: URL?
    private(set) var lastChooseFilesAllowedTypes: [UTType] = []

    init(directoryToReturn: URL? = nil, filesToReturn: [URL] = []) {
        self.directoryToReturn = directoryToReturn
        self.filesToReturn = filesToReturn
    }

    func chooseDirectory(initial: URL?) -> URL? {
        lastChooseDirectoryInitial = initial
        return directoryToReturn
    }

    func chooseFiles(allowedTypes: [UTType]) -> [URL] {
        lastChooseFilesAllowedTypes = allowedTypes
        return filesToReturn
    }
}
```

- [ ] **Step 2: Verify**

Run `swift build --target ImageCRCTests` — green.

- [ ] **Step 3: Commit**

```bash
git add Tests/Support/FakeFileChooser.swift
git commit -m "$(cat <<'EOF'
test(infra): add FakeFileChooser for VM file-picker tests

Scriptable returns for chooseDirectory/chooseFiles, plus capture of the
last-call arguments so tests can assert what the VM passed in.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section C — ImageConverter happy path

---

### Task 6: Batch all-success integration test

**Why:** The orchestrator's claim is "encode N files in parallel, emit one `.willStart` per file, one `.didComplete` per file with monotonic counter, then `.didFinish`". Verify end-to-end with synthesised PNG inputs converting to JPEG.

**Files:**
- Create: `Tests/IntegrationTests/ImageConverterBatchTests.swift`

- [ ] **Step 1: Write the suite**

```swift
import Foundation
import CoreGraphics
import Testing
@testable import ImageCRC

@Suite("ImageConverter — batch happy path")
struct ImageConverterBatchTests {
    /// Build N synthesised PNGs in `tmp` and wrap them as ImageFile values.
    private func makeInputs(count: Int, in tmp: TempDirectory) throws -> [ImageFile] {
        var files: [ImageFile] = []
        let img = SyntheticImage.gradient(width: 32, height: 16)
        let data = try PNGEncoder.encode(image: img)
        for i in 0..<count {
            let url = tmp.url.appendingPathComponent("in-\(i).png")
            try data.write(to: url)
            files.append(try #require(ImageFile(url: url)))
        }
        return files
    }

    @Test("16-file batch: all success, monotonic counter, exact event count")
    func batchAllSuccess() async throws {
        let inputTmp = try TempDirectory()
        let outputTmp = try TempDirectory()
        let files = try makeInputs(count: 16, in: inputTmp)
        var settings = ConversionSettings.default
        settings.outputDirectory = outputTmp.url
        settings.outputFormat = .jpeg

        var willStartCount = 0
        var didCompleteCount = 0
        var lastCompleted = 0
        var summary: ConversionSummary?

        let converter = ImageConverter()
        for await event in converter.convert(files: files, settings: settings) {
            switch event {
            case .willStart:
                willStartCount += 1
            case .didComplete(_, let completed, let total):
                didCompleteCount += 1
                #expect(completed > lastCompleted, "counter must be strictly monotonic")
                #expect(completed <= total)
                lastCompleted = completed
            case .didFinish(let s):
                summary = s
            }
        }

        #expect(willStartCount == 16)
        #expect(didCompleteCount == 16)
        #expect(lastCompleted == 16)
        let final = try #require(summary)
        #expect(final.successes.count == 16)
        #expect(final.failures.isEmpty)
        #expect(final.cancelled == 0)
        #expect(final.total == 16)
    }

    @Test("output files are written to the chosen directory with .jpg extension")
    func outputFilesPresent() async throws {
        let inputTmp = try TempDirectory()
        let outputTmp = try TempDirectory()
        let files = try makeInputs(count: 4, in: inputTmp)
        var settings = ConversionSettings.default
        settings.outputDirectory = outputTmp.url
        settings.outputFormat = .jpeg

        let converter = ImageConverter()
        for await _ in converter.convert(files: files, settings: settings) {}

        let written = try FileManager.default.contentsOfDirectory(at: outputTmp.url, includingPropertiesForKeys: nil)
        let jpgs = written.filter { $0.pathExtension == "jpg" }
        #expect(jpgs.count == 4)
    }
}
```

- [ ] **Step 2: Run**

Run `swift test --filter "ImageConverter — batch"` — expect 2/2.
Run `swift test` — expect 63/22 + 1 skipped (was 61/21 + 1; +2 tests, +1 suite).

- [ ] **Step 3: Commit**

```bash
git add Tests/IntegrationTests/ImageConverterBatchTests.swift
git commit -m "$(cat <<'EOF'
test(converter): batch happy path — monotonic progress, all-success

End-to-end run of ImageConverter with 16 synthesised PNG inputs converted
to JPEG. Asserts the event contract (one .willStart per file, one
.didComplete per file, monotonic counter, exactly N events of each) and
that output files actually land on disk.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section D — ImageConverter error paths

---

### Task 7: Output-directory error paths

**Why:** Two error states the orchestrator must surface cleanly: (a) `outputDirectory == nil`, (b) `outputDirectory` is read-only / can't be created.

**Files:**
- Create: `Tests/IntegrationTests/ImageConverterErrorTests.swift`

- [ ] **Step 1: Write the suite**

```swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("ImageConverter — error paths")
struct ImageConverterErrorTests {
    private func makeInput(in tmp: TempDirectory, name: String = "in.png") throws -> ImageFile {
        let img = SyntheticImage.gradient(width: 16, height: 16)
        let data = try PNGEncoder.encode(image: img)
        let url = tmp.url.appendingPathComponent(name)
        try data.write(to: url)
        return try #require(ImageFile(url: url))
    }

    @Test("outputDirectory == nil produces all .outputDirectoryMissing failures")
    func outputDirNil() async throws {
        let inputTmp = try TempDirectory()
        let files = [
            try makeInput(in: inputTmp, name: "a.png"),
            try makeInput(in: inputTmp, name: "b.png"),
        ]
        var settings = ConversionSettings.default
        settings.outputDirectory = nil
        settings.outputFormat = .jpeg

        var summary: ConversionSummary?
        var willStartCount = 0
        let converter = ImageConverter()
        for await event in converter.convert(files: files, settings: settings) {
            switch event {
            case .willStart: willStartCount += 1
            case .didFinish(let s): summary = s
            case .didComplete: break
            }
        }

        #expect(willStartCount == 0, "no .willStart should fire when output dir is missing")
        let final = try #require(summary)
        #expect(final.failures.count == 2)
        #expect(final.successes.isEmpty)
        for failure in final.failures {
            if case .failure(let err) = failure.outcome {
                #expect(err.errorDescription?.contains("Output directory") == true,
                        "outcome must surface outputDirectoryMissing; got \(err)")
            } else {
                Issue.record("expected .failure; got \(failure.outcome)")
            }
        }
    }

    @Test("createDirectory failure produces all .writeFailed failures")
    func outputDirCreateFails() async throws {
        // /dev/null is a character device — createDirectory on a path under it
        // fails. The orchestrator's catch block at ImageConverter.swift:44
        // converts the create error into per-file .writeFailed outcomes for
        // every input. Note: this exercises the dir-create branch, not the
        // per-file write-failure branch inside processOne.
        let inputTmp = try TempDirectory()
        let files = [try makeInput(in: inputTmp)]
        var settings = ConversionSettings.default
        settings.outputDirectory = URL(fileURLWithPath: "/dev/null/imagecrc-bogus")
        settings.outputFormat = .jpeg

        var summary: ConversionSummary?
        let converter = ImageConverter()
        for await event in converter.convert(files: files, settings: settings) {
            if case .didFinish(let s) = event { summary = s }
        }

        let final = try #require(summary)
        #expect(final.failures.count == 1)
        #expect(final.successes.isEmpty)
        if case .failure(let err) = final.failures[0].outcome {
            #expect(err.errorDescription?.contains("write") == true
                    || err.errorDescription?.contains("Could not") == true,
                    "outcome must surface a write/create failure; got \(err)")
        } else {
            Issue.record("expected .failure; got \(final.failures[0].outcome)")
        }
    }
}
```

- [ ] **Step 2: Run**

Run `swift test --filter "ImageConverter — error"` — expect 2/2.
Run `swift test` — expect 65/23 + 1 skipped (+2 tests, +1 suite).

- [ ] **Step 3: Commit**

```bash
git add Tests/IntegrationTests/ImageConverterErrorTests.swift
git commit -m "$(cat <<'EOF'
test(converter): error paths — missing output dir, unwritable target

Pin the two terminal-failure behaviours: outputDirectory==nil produces
.outputDirectoryMissing failures with no .willStart events, and an
unwritable output path produces .writeFailed failures. Both terminate
with .didFinish.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section E — Cancellation

---

### Task 8: Cancellation observable invariants

**Why:** The orchestrator's contract on cancel includes an internal drain loop that emits `.cancelled` for remaining files (`ImageConverter.run:109–117`). However, **drain events are not externally observable** through the public `AsyncStream` API: when the consumer drops the stream (or its task is cancelled), `continuation.onTermination` fires → `job.cancel()` → drain runs → drain `yield(...)` calls go to a terminated continuation and are silently discarded. `.didFinish` similarly never reaches the consumer after cancellation.

So we cannot observe drain *events* externally. What we CAN observe:
1. Cancel-before-iteration terminates cleanly.
2. Cancel mid-batch terminates promptly without crash.
3. After mid-batch cancel, the output directory contains AT MOST as many files as `.didComplete` events the consumer observed before its task was cancelled.

Drain accounting (`successes + failures + cancelled == total` in the summary) is verified by code review, not this test — the events are internal.

**Files:**
- Create: `Tests/IntegrationTests/ImageConverterCancelTests.swift`

- [ ] **Step 1: Write the suite**

```swift
import Foundation
import Testing
@testable import ImageCRC

@Suite("ImageConverter — cancellation")
struct ImageConverterCancelTests {
    private func makeInputs(count: Int, in tmp: TempDirectory) throws -> [ImageFile] {
        var files: [ImageFile] = []
        let img = SyntheticImage.gradient(width: 32, height: 32)
        let data = try PNGEncoder.encode(image: img)
        for i in 0..<count {
            let url = tmp.url.appendingPathComponent("in-\(i).png")
            try data.write(to: url)
            files.append(try #require(ImageFile(url: url)))
        }
        return files
    }

    @Test("cancel mid-batch terminates promptly, output bounded by observed completions")
    func cancelMidBatch() async throws {
        let inputTmp = try TempDirectory()
        let outputTmp = try TempDirectory()
        let files = try makeInputs(count: 32, in: inputTmp)
        var settings = ConversionSettings.default
        settings.outputDirectory = outputTmp.url
        settings.outputFormat = .jpeg

        let observer = Task {
            let converter = ImageConverter()
            var observedCompletions = 0
            for await event in converter.convert(files: files, settings: settings) {
                if case .didComplete = event {
                    observedCompletions += 1
                }
            }
            return observedCompletions
        }

        // Wait briefly for the orchestrator to start spawning, then cancel.
        // 50ms is conservative on Apple Silicon; if Phase 6 CI runs on slower
        // hardware and this flakes, raise the sleep or wait for the first
        // .didComplete event before cancelling.
        try await Task.sleep(nanoseconds: 50_000_000)
        observer.cancel()
        let observed = await observer.value

        // Externally observable invariants:
        // - Termination happens (the await on observer.value returns).
        // - Output directory contains AT MOST `observed` files: drained files
        //   never run their encode/write step, and we may have observed fewer
        //   completions than there are output files only if a file completed
        //   between cancellation and consumer iterator exit (highly unlikely
        //   but allowed by AsyncStream buffer semantics).
        let written = try FileManager.default.contentsOfDirectory(at: outputTmp.url, includingPropertiesForKeys: nil)
        let jpgs = written.filter { $0.pathExtension == "jpg" }
        #expect(jpgs.count <= 32, "no more output files than input total")
        // Loose upper bound to allow for runtime races between cancel signal
        // and last-iteration write completion.
        #expect(jpgs.count <= observed + 4,
                "output count (\(jpgs.count)) should be near observed completions (\(observed))")
    }

    @Test("cancel-before-iteration: stream finishes cleanly without spawning work")
    func cancelBeforeStart() async throws {
        let inputTmp = try TempDirectory()
        let outputTmp = try TempDirectory()
        let files = try makeInputs(count: 8, in: inputTmp)
        var settings = ConversionSettings.default
        settings.outputDirectory = outputTmp.url
        settings.outputFormat = .jpeg

        let observer = Task {
            let converter = ImageConverter()
            for await _ in converter.convert(files: files, settings: settings) {}
        }
        observer.cancel()
        await observer.value
        // No assertion beyond "no crash, terminates cleanly". The point is to
        // exercise the cancel-before-spawn branch in continuation.onTermination.
    }
}
```

- [ ] **Step 2: Run**

Run `swift test --filter "ImageConverter — cancellation"` — expect 2/2.
Run twice in a row to catch flakes — cancellation tests are timing-sensitive.

Run `swift test` — expect 67/24 + 1 skipped (+2 tests, +1 suite).

- [ ] **Step 3: Commit**

```bash
git add Tests/IntegrationTests/ImageConverterCancelTests.swift
git commit -m "$(cat <<'EOF'
test(converter): cancellation observable invariants

Drain events are internal (yielded to a terminated continuation after
consumer drops the stream) — they cannot be observed externally. What
this test pins is what *is* observable: prompt termination, no crash,
and output directory bounded by observed completion events.

Drain accounting (successes+failures+cancelled==total) remains verified
by code review of ImageConverter.run:109-117.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section F — ViewModel

---

### Task 9: VM phase transitions via FakeConverter

**Why:** Drive the VM through a scripted event sequence and assert `phase`, `progress`, `currentFilename`, and `summary` track correctly.

**Files:**
- Create: `Tests/IntegrationTests/ConversionViewModelTests.swift`

- [ ] **Step 1: Write the test suite (transitions only — guards are Task 10)**

```swift
import Foundation
import Testing
@testable import ImageCRC

@MainActor
@Suite("ConversionViewModel — phase transitions")
struct ConversionViewModelPhaseTests {
    private func makeFile(in tmp: TempDirectory, name: String = "a.png") throws -> ImageFile {
        let img = SyntheticImage.solid(width: 8, height: 8)
        let data = try PNGEncoder.encode(image: img)
        let url = tmp.url.appendingPathComponent(name)
        try data.write(to: url)
        return try #require(ImageFile(url: url))
    }

    private func waitForPhase(_ vm: ConversionViewModel, _ target: ConversionViewModel.Phase, timeoutMs: Int = 1000) async throws {
        let start = Date()
        while vm.phase != target {
            if Date().timeIntervalSince(start) > Double(timeoutMs) / 1000.0 {
                Issue.record("timed out waiting for phase=\(target); current=\(vm.phase)")
                return
            }
            try await Task.sleep(nanoseconds: 5_000_000)  // 5ms
        }
    }

    @Test("scripted events drive idle → running → completed")
    func happyPath() async throws {
        let tmp = try TempDirectory()
        let file = try makeFile(in: tmp)
        let outputURL = tmp.url.appendingPathComponent("out.jpg")

        let result = ConversionResult(
            id: UUID(),
            source: file.url,
            outcome: .success(outputURL: outputURL, originalBytes: 100, outputBytes: 50)
        )
        let summary = ConversionSummary(
            total: 1,
            successes: [result],
            failures: [],
            cancelled: 0,
            outputDirectory: tmp.url
        )

        let fake = FakeConverter(events: [
            .willStart(file: file),
            .didComplete(result: result, completed: 1, total: 1),
            .didFinish(summary: summary),
        ])

        let vm = ConversionViewModel(converter: fake)
        vm.files = [file]
        vm.settings.outputDirectory = tmp.url

        #expect(vm.phase == .idle)
        vm.start()
        #expect(vm.phase == .running)

        try await waitForPhase(vm, .completed)
        #expect(vm.completed == 1)
        #expect(vm.total == 1)
        #expect(vm.progress == 1.0)
        #expect(vm.summary?.successes.count == 1)
        #expect(vm.currentFilename == nil, "currentFilename clears on .didFinish")
    }

    @Test(".willStart updates currentFilename")
    func willStartUpdatesFilename() async throws {
        let tmp = try TempDirectory()
        let file = try makeFile(in: tmp, name: "photo.png")

        let fake = FakeConverter(events: [
            .willStart(file: file),
        ])

        let vm = ConversionViewModel(converter: fake)
        vm.files = [file]
        vm.settings.outputDirectory = tmp.url
        vm.start()

        // Wait briefly for the willStart event to land.
        let start = Date()
        while vm.currentFilename == nil {
            if Date().timeIntervalSince(start) > 1 { Issue.record("timed out"); break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(vm.currentFilename == "photo.png")
    }
}
```

- [ ] **Step 2: Run**

Run `swift test --filter "ConversionViewModel — phase"` — expect 2/2.
Run twice — VM tests are async so timing-sensitive.

Run `swift test` — expect 69/25 + 1 skipped (+2 tests, +1 suite).

- [ ] **Step 3: Commit**

```bash
git add Tests/IntegrationTests/ConversionViewModelTests.swift
git commit -m "$(cat <<'EOF'
test(vm): phase transitions via FakeConverter

Drive ConversionViewModel through a scripted event sequence and assert
phase moves idle → running → completed, progress reaches 1.0, summary
lands, and currentFilename updates on .willStart and clears on .didFinish.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: VM canStart/cancel/dismiss tests

**Why:** Cover the guard logic and reset paths.

**Files:**
- Modify: `Tests/IntegrationTests/ConversionViewModelTests.swift` (append a new suite)

- [ ] **Step 1: Append the second suite**

```swift
@MainActor
@Suite("ConversionViewModel — canStart, cancel, dismiss")
struct ConversionViewModelGuardTests {
    private func makeFile(in tmp: TempDirectory) throws -> ImageFile {
        let img = SyntheticImage.solid(width: 8, height: 8)
        let data = try PNGEncoder.encode(image: img)
        let url = tmp.url.appendingPathComponent("a.png")
        try data.write(to: url)
        return try #require(ImageFile(url: url))
    }

    @Test("canStart is false when files is empty")
    func canStartNoFiles() throws {
        let vm = ConversionViewModel(converter: FakeConverter())
        vm.settings.outputDirectory = URL(fileURLWithPath: "/tmp")
        #expect(vm.canStart == false)
    }

    @Test("canStart is false when outputDirectory is nil") 
    func canStartNoOutputDir() throws {
        let tmp = try TempDirectory()
        let file = try makeFile(in: tmp)
        let vm = ConversionViewModel(converter: FakeConverter())
        vm.files = [file]
        vm.settings.outputDirectory = nil
        #expect(vm.canStart == false)
    }

    @Test("canStart is true with files and output dir set")
    func canStartReady() throws {
        let tmp = try TempDirectory()
        let file = try makeFile(in: tmp)
        let vm = ConversionViewModel(converter: FakeConverter())
        vm.files = [file]
        vm.settings.outputDirectory = tmp.url
        #expect(vm.canStart == true)
    }

    @Test("dismissCompletion resets state to idle")
    func dismissResets() async throws {
        let tmp = try TempDirectory()
        let file = try makeFile(in: tmp)
        let result = ConversionResult(
            id: UUID(), source: file.url,
            outcome: .success(outputURL: tmp.url.appendingPathComponent("o.jpg"),
                              originalBytes: 1, outputBytes: 1)
        )
        let summary = ConversionSummary(
            total: 1, successes: [result], failures: [], cancelled: 0,
            outputDirectory: tmp.url
        )
        let fake = FakeConverter(events: [
            .didComplete(result: result, completed: 1, total: 1),
            .didFinish(summary: summary),
        ])
        let vm = ConversionViewModel(converter: fake)
        vm.files = [file]
        vm.settings.outputDirectory = tmp.url
        vm.start()

        // Wait for completed phase.
        let start = Date()
        while vm.phase != .completed {
            if Date().timeIntervalSince(start) > 1 { Issue.record("timeout"); return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }

        vm.dismissCompletion()
        #expect(vm.phase == .idle)
        #expect(vm.summary == nil)
        #expect(vm.completed == 0)
        #expect(vm.total == 0)
        #expect(vm.progress == 0)
        #expect(vm.currentFilename == nil)
    }

    @Test("chooseOutputDirectory routes through FakeFileChooser")
    func fileChooserRouting() throws {
        let chooser = FakeFileChooser(directoryToReturn: URL(fileURLWithPath: "/tmp/chosen"))
        let vm = ConversionViewModel(converter: FakeConverter(), fileChooser: chooser)
        vm.chooseOutputDirectory()
        #expect(vm.settings.outputDirectory?.path == "/tmp/chosen")
    }
}
```

- [ ] **Step 2: Run**

Run `swift test --filter "ConversionViewModel — canStart"` — expect 5/5.
Run `swift test` — expect 74/26 + 1 skipped (+5 tests, +1 suite).

- [ ] **Step 3: Commit**

```bash
git add Tests/IntegrationTests/ConversionViewModelTests.swift
git commit -m "$(cat <<'EOF'
test(vm): canStart guards, dismissCompletion reset, FileChooser routing

canStart must be false without files, false without output dir, true
with both. dismissCompletion must reset every progress field. The new
FileChooser injection is verified by routing chooseOutputDirectory
through FakeFileChooser and asserting the chosen URL lands in settings.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

# Section G — Phase 2 sweep

---

### Task 11: TIFF-dictionary fallback for EXIF orientation

**Why:** Phase 2 T13 only reads orientation from the top-level `kCGImagePropertyOrientation` key. ImageIO usually promotes EXIF orientation there, but for some edited files the value lives only inside `kCGImagePropertyTIFFDictionary[kCGImagePropertyTIFFOrientation]`. Add the fallback.

**Files:**
- Modify: `Services/Decoders/ImageIODecoder.swift` (extend orientation read)
- Modify: `Tests/CodecTests/EXIFOrientationTests.swift` (add a fallback test)

- [ ] **Step 1: Add the fallback to `ImageIODecoder.swift`**

In `ImageIODecoder.decode(url:)`, replace this block:

```swift
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientationRaw = props?[kCGImagePropertyOrientation] as? UInt32 ?? 1
```

with:

```swift
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        // Top-level orientation key first, then nested TIFF dict for files that
        // only store it there (some edited JPEGs/HEICs).
        let orientationRaw: UInt32 = {
            if let top = props?[kCGImagePropertyOrientation] as? UInt32 {
                return top
            }
            if let tiff = props?[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
               let nested = tiff[kCGImagePropertyTIFFOrientation] as? UInt32 {
                return nested
            }
            return 1
        }()
```

- [ ] **Step 2: Add a test in `EXIFOrientationTests.swift`**

**Add unconditional imports first.** Currently `Tests/CodecTests/EXIFOrientationTests.swift` imports `Foundation`, `CoreGraphics`, `Testing`, `@testable import ImageCRC`. **Add** these two lines at the top:

```swift
import ImageIO
import UniformTypeIdentifiers
```

Then append the test to the suite:

```swift
    @Test("orientation in nested TIFF dictionary is honoured when top-level is absent")
    func tiffDictFallback() throws {
        // Synthesise a JPEG with the orientation tag stored ONLY in the TIFF
        // dictionary by writing through CGImageDestination with a custom props
        // dict that omits the top-level key.
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let mutableData = NSMutableData()
        let dest = try #require(CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ))
        let tiffDict: [CFString: Any] = [
            kCGImagePropertyTIFFOrientation: 6,
        ]
        let props: [CFString: Any] = [
            kCGImagePropertyTIFFDictionary: tiffDict,
        ]
        CGImageDestinationAddImage(dest, src, props as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let url = tmp.url.appendingPathComponent("tiff-only.jpg")
        try (mutableData as Data).write(to: url)

        // Precondition verification: confirm ImageIO did NOT promote the TIFF
        // orientation to the top level. If it did, this test cannot validate
        // the fallback path — record an issue and skip the assertion.
        let writtenSource = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let writtenProps = CGImageSourceCopyPropertiesAtIndex(writtenSource, 0, nil) as? [CFString: Any]
        let topLevelOrient = writtenProps?[kCGImagePropertyOrientation] as? UInt32
        let nestedOrient = (writtenProps?[kCGImagePropertyTIFFDictionary] as? [CFString: Any])?[kCGImagePropertyTIFFOrientation] as? UInt32

        if topLevelOrient != nil {
            Issue.record("ImageIO promoted TIFF-dict orientation to the top-level key on write; this test cannot validate the fallback path. topLevel=\(topLevelOrient ?? 0), nested=\(nestedOrient ?? 0). Consider an alternative synthesis (manual EXIF byte injection) or accept this test as inactive on this macOS version.")
            return
        }
        #expect(nestedOrient == 6, "precondition: TIFF dict must carry orientation=6")

        let decoded = try ImageIODecoder.decode(url: url)
        #expect(decoded.width == 50, "TIFF-dict orientation=6 must apply via fallback")
        #expect(decoded.height == 100)
    }
```

- [ ] **Step 3: Verify probe + fix together**

Run the test once before the production change to confirm it would fail (probe):

Actually, since both production change and test land in the same commit, just run after both:

Run `swift test --filter EXIF` — expect 5/5.
Run full `swift test` — expect 75/26 + 1 skipped (+1 test).

If ImageIO promotes the TIFF orientation to the top level even when we put it only in the nested dict (it might — the system is helpful here), this test may pass without the fallback being exercised. In that case, add a `print` or use `CGImageSourceCopyPropertiesAtIndex` directly in the test to verify which key the value ended up under, and adjust the synthesis if needed.

- [ ] **Step 4: Commit**

```bash
git add Services/Decoders/ImageIODecoder.swift Tests/CodecTests/EXIFOrientationTests.swift
git commit -m "$(cat <<'EOF'
fix(decoder): fall back to TIFF dict for EXIF orientation

Phase 2 T13 read kCGImagePropertyOrientation only at the top level.
Some edited JPEGs/HEICs store orientation only inside the nested
kCGImagePropertyTIFFDictionary; check there as a secondary lookup
before defaulting to .up.

Adds a probe test that synthesises a JPEG with orientation written
only into the TIFF dict and verifies dim-swap still applies.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Less-common EXIF orientations dim-swap coverage

**Why:** Phase 2 T13 only probed orientations 1, 6, 8 with explicit dim assertions, plus a sentinel-pixel test for 6. Orientations 2 (mirrored), 3 (180°), 4 (mirrored 180°), 5 (mirrored 90° CCW), 7 (mirrored 90° CW) are unprobed. Real cameras don't emit these much, but a regression in their transform branches would ship green. Add at-minimum dim-swap coverage; pixel-level remains a Phase 4 concern.

**Files:**
- Modify: `Tests/CodecTests/EXIFOrientationTests.swift` (append a parameterised test)

- [ ] **Step 1: Append a parameterised test**

```swift
    @Test("less-common orientations preserve or swap dims as expected",
          arguments: [
            (orient: 2, swap: false),  // upMirrored
            (orient: 3, swap: false),  // down (180°)
            (orient: 4, swap: false),  // downMirrored
            (orient: 5, swap: true),   // leftMirrored (90° CCW + flip)
            (orient: 7, swap: true),   // rightMirrored (90° CW + flip)
          ])
    func lessCommonOrientations(orient: Int, swap: Bool) throws {
        let tmp = try TempDirectory()
        let src = SyntheticImage.gradient(width: 100, height: 50)
        let data = SyntheticImage.jpegData(from: src, exifOrientation: orient)
        let url = tmp.url.appendingPathComponent("o\(orient).jpg")
        try data.write(to: url)
        let decoded = try ImageIODecoder.decode(url: url)
        if swap {
            #expect(decoded.width == 50, "orientation=\(orient): expected swap to 50w")
            #expect(decoded.height == 100, "orientation=\(orient): expected swap to 100h")
        } else {
            #expect(decoded.width == 100, "orientation=\(orient): expected no swap")
            #expect(decoded.height == 50)
        }
    }
```

- [ ] **Step 2: Run**

Run `swift test --filter EXIF` — expect 6/6 (was 5/5 + 1 new parameterised case reported as 1 test with 5 sub-cases).
Run `swift test` — expect 76/26 + 1 skipped (+1 test, parameterised).

If any orientation fails, the production transform table for that case is wrong. Investigate `applyOrientation` switch in `ImageIODecoder.swift`; the bug from T13 was inverted-sign rotation, similar may apply to other cases. Don't ship a speculative fix; if a case fails, escalate.

- [ ] **Step 3: Commit**

```bash
git add Tests/CodecTests/EXIFOrientationTests.swift
git commit -m "$(cat <<'EOF'
test(codec): cover dim-swap for less-common EXIF orientations 2/3/4/5/7

T13 explicitly tested orientations 1, 6, 8 with a sentinel-pixel test
for 6. Add at-minimum dim-swap coverage for the five less-common cases
real cameras don't usually emit but edited files might. Pixel-level
geometry of these cases remains a Phase 4 concern.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 Done When

- [ ] `swift test` exits 0 with **76 tests + 1 skipped = 77 reported** across **26 suites** (Phase 2 ended at 61/21 + 1 skipped; Phase 3 adds 15 tests / 5 suites)
- [ ] No SwiftPM warnings beyond pre-existing two
- [ ] `Converter` protocol exists in `Services/Converter.swift`; `ImageConverter` is a `struct` conforming to it
- [ ] `FileChooser` protocol + `AppKitFileChooser` exist in `ViewModels/FileChooser.swift`
- [ ] `ConversionViewModel` injects both `Converter` and `FileChooser` with production defaults; app entry point unchanged
- [ ] `ImageConverter` integration tests cover: 16-file batch all-success, output-dir-nil, unwritable target, mid-batch cancel drain, cancel-before-iteration
- [ ] VM tests cover: phase transitions through scripted events, `currentFilename` update, `canStart` guards (no files / no dir / ready), `dismissCompletion` reset, `FileChooser` routing
- [ ] EXIF orientation reads from nested TIFF dict as fallback
- [ ] Dim-swap coverage for orientations 2, 3, 4, 5, 7
- [ ] User approval to write Phase 4 plan

---

## Pause points

User policy: all phases on `tests/phase-1`, merge to main as one batch later.

Natural pauses within Phase 3 if needed:

- **After Section B (T1–T5):** protocol extractions + test infra in place, no behaviour tests yet. **Caveat:** existing Phase 1+2 tests do NOT cover `ConversionViewModel` or the converter-VM bridge, so a green test bar at this point does NOT prove the production refactor is correct. Required acceptance gate before pausing here:
  1. `swift build -c release` succeeds
  2. `swift test` is green (61/21 + 1 skipped)
  3. Manual smoke (if human available): `./Scripts/make-app.sh && open ./ImageCRC.app`, click "Choose output folder" + "Add files" + drop a file + start conversion. If autonomous, defer the smoke to end of Section F (T10's VM tests provide automated coverage of the bridge).
- **After Section E (T1–T8):** orchestrator fully covered, VM still untested (Section F is its own logical unit)
- **After Section F (T1–T10):** Phases 1–3 functional coverage complete; Section G is sweep cleanup of Phase 2 holes

---

## Self-review

**Spec coverage:** every Phase 3 commitment from the original roadmap (concurrency, cancellation, VM, protocols) plus the two Phase 2 open holes (TIFF-dict EXIF, less-common orientations) has a task. The Phase 2 plan's outline of Phase 3 mentioned 14–18 tasks; this plan is 12 tasks because protocol extractions are folded into 2 tasks (vs separate "define protocol" / "wire VM" / "update app").

**Placeholder scan:** every task has runnable code or commands. Task 11 has a hedge ("if ImageIO promotes the TIFF orientation to the top level even when we put it only in the nested dict, the test may pass without the fallback being exercised") — this is honest about an ImageIO behaviour we can't pre-verify; the executor can investigate and adjust if needed. Not a placeholder, a documented uncertainty.

**Type consistency:** `Converter` protocol has one method `convert(files:settings:) -> AsyncStream<ConversionEvent>` — used by VM in Task 1 and by `FakeConverter` in Task 4. `FileChooser` has `chooseDirectory(initial:) -> URL?` and `chooseFiles(allowedTypes:) -> [URL]` — used by VM in Task 2 and `FakeFileChooser` in Task 5. `ConversionEvent`, `ConversionResult`, `ConversionSummary` referenced verbatim from `Models/`. All signatures verified against current source.

**Cancellation test fragility:** Task 8 is the most timing-sensitive in this plan. The test uses `Task.sleep` to give the orchestrator time to start — 50ms is conservative on Apple Silicon but could flake on slower hardware. If flaky, the executor can either (a) increase the sleep, (b) restructure to wait for first `.didComplete` event before cancelling, or (c) accept a flake budget. Documented in Task 8.

**Deferred decisions:**
- Less-common EXIF orientation pixel correctness — Phase 4 (SSIM/golden snapshots have the right machinery for visual verification)
- pngquant missing-binary deterministic test — still deferred (would need Bundle.main shimming)
- Real-world fixtures with embedded ICC — Phase 4
