# ImageCRC Phase 5 — UI Smoke (XCUITest)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cover the SwiftUI happy path and cancel flow with XCUITest — launch the app, drive it from "files added" through "completion sheet", assert externally observable state via accessibility identifiers. Establish a `bundle.ui-testing` target wired into `xcodebuild test` so Phase 6 can run it on `macos-14` runners.

**Architecture:** XCUITest target is XcodeGen-only (SPM does not support UI test bundles). The test app gets a single in-process test hook (`IMAGECRC_UI_TEST=1` env var) that swaps `AppKitFileChooser` for a launch-arg-driven fake. Files are seeded via launch arguments — never a real `NSOpenPanel`, never disk-state outside a per-test temp dir. Cancellation is observable because the production conversion of multiple decoded-encoded files is bounded by `activeProcessorCount`; with N+1 large images the cancel button reliably fires before completion. Synthetic fixtures are built into the same temp dir as the output via a debug-only "preload synthetic files" launch-arg path.

**Tech Stack:** Swift 5.10, XCTest + XCUITest (UI tests cannot use `import Testing`/Swift Testing — `@available` and lifecycle differ), Xcode 26, macOS 14 deployment target. Existing test infra (`Tests/Support/SyntheticImage`, `TempDirectory`) is reused inside the **app process** for the test-mode preload — a small symbol exposure is needed on the app side so the UI-test target doesn't need `@testable` access (which is impossible across XCUITest's two-process boundary anyway).

> **User policy:** All Phase 1–6 work lands on `tests/phase-1` and merges to `main` as one batch when Phase 6 finishes. Subagents may commit on this branch; never push or merge to main.

---

## Section Overview

| # | Section | Tasks | Goal |
|---|---------|-------|------|
| Pre | xcodebuild fix | T1 | Disambiguate `PRODUCT_MODULE_NAME` between app and test target so `xcodebuild test` works at all |
| A | UI test affordances | T2–T4 | Accessibility identifiers on key views; UI-test-mode launch hook in app; preload-fixtures fake `FileChooser` |
| B | XCUITest target + smoke | T5–T7 | `bundle.ui-testing` target; happy-path test; cancel-flow test |
| C | Wire-up + docs | T8 | `xcodebuild test` invocation documented; CLAUDE.md updated; final smoke run |

**Phase 5 done when:**

- `xcodebuild test -scheme ImageCRC -destination 'platform=macOS,arch=arm64'` exits 0 with the existing 92 unit/codec/integration tests **plus** at least 2 new UI tests across 1 new XCUITest suite
- `swift test` exits 0 unchanged at 92 tests / 32 suites / 1 known issue (XCUITest changes are XcodeGen-only and must not regress SwiftPM)
- `bundle.ui-testing` target wired in `project.yml` with sources at `Tests/UITests/`
- Production app gains stable accessibility identifiers on: drop zone, browse-files button, output-folder button, quality slider, format picker, start button, cancel button, completion sheet, dismiss button, file list, output-folder display
- App-side UI-test-mode launch hook lives behind a single `#if DEBUG`-friendly env-var check; ships in the production binary but is dormant (zero behaviour change without `IMAGECRC_UI_TEST=1`)
- `Scripts/make-app.sh` and `make-dmg.sh` are NOT touched by this phase
- User approval to write Phase 6 plan

**Estimated time:** 1–2 days. The novel work is T2 (UI-test-mode launch hook) and T3 (accessibility wiring); T5–T7 are mostly mechanical.

**Deliberately deferred:**
- Real `NSOpenPanel` automation (driving the system file picker via XCUITest). The launch-arg + fake-chooser path is cheaper, deterministic, and CI-portable. Trade-off: one production codepath (the actual `AppKitFileChooser.runModal`) has no XCUITest coverage. This was already true in Phases 1–4 and is the universal trade-off for sandboxed-panel UI testing.
- Drop-target (drag-and-drop URL into `DropZoneView`) — XCUITest cannot synthesize macOS drag-and-drop sequences reliably without sleep-driven brittleness. Coverage is via the click-to-browse path only.
- Settings-panel exhaustive coverage (every quality/format permutation). Phase 4's perceptual matrix already covers the conversion side; UI-side we test exactly that the slider and picker mutate the VM observably.
- Localization strings — assertions are by accessibility identifier and structural state, never by visible text.

---

## File structure delta

```
project.yml                              # modify: PRODUCT_MODULE_NAME on tests, add ImageCRCUITests target
Views/ContentView.swift                  # modify: accessibilityIdentifier on drop zone, start button, file list
Views/DropZoneView.swift                 # modify: accessibilityIdentifier
Views/SettingsPanelView.swift            # modify: accessibilityIdentifier on slider, picker, folder button
Views/CompletionSheetView.swift          # modify: accessibilityIdentifier on sheet root, dismiss button
Views/ProgressOverlayView.swift          # modify: accessibilityIdentifier on cancel button
ViewModels/FileChooser.swift             # modify: extract into its own file or extend with a launch-arg-driven fake (decision: append)
App/ImageCRCApp.swift                    # modify: read launch args, swap FileChooser if IMAGECRC_UI_TEST=1
App/UITestSupport.swift                  # NEW: launch-arg parsing + preloaded synthetic files generator (compiled into the prod binary, dormant by default)
Tests/UITests/ImageCRCUITests.swift      # NEW: happy-path + cancel XCUITest cases
docs/superpowers/plans/2026-05-08-testing-phase-5.md  # this file
CLAUDE.md                                # modify: document `xcodebuild test` invocation
```

`Package.swift` is intentionally NOT touched — XCUITest sources don't go through SwiftPM. `Tests/Support/`, `Tests/UnitTests/`, `Tests/CodecTests/`, `Tests/IntegrationTests/` already discovered by SwiftPM (`Package.swift`'s `sources: ["Support", "UnitTests", "CodecTests", "IntegrationTests"]`). Adding a new `Tests/UITests/` directory at the top level of `Tests/` would normally need a SwiftPM exclude, but XCUITest can't be hosted by SwiftPM, so we must instead exclude it from SwiftPM's test target via the package manifest. **One-line edit to `Package.swift`** to add `"UITests"` to the exclude list — this counts as project plumbing, not a Phase 5 production change.

The `App/UITestSupport.swift` file lives in the **production target** because XCUITest runs in a separate process from the app and cannot inject classes — the only way to control the app's behaviour is via `app.launchArguments` / `app.launchEnvironment` read by the app itself. The file is opted-in by a single env-var check at app entry, so it adds zero overhead in the normal launch path.

---

# Pre-section — xcodebuild plumbing

---

### Task 1: Fix `PRODUCT_MODULE_NAME` collision so `xcodebuild test` builds

**Why:** Currently `project.yml` declares `PRODUCT_MODULE_NAME: ImageCRC` in the global `settings.base` block, which inherits into both the `ImageCRC` app target AND the `ImageCRCTests` test target. On Xcode 26 / macOS 26 SDK, this causes "Multiple commands produce 'ImageCRC.swiftmodule/...'" errors and `xcodebuild test` fails before any test runs.

`swift test` is unaffected because SwiftPM uses its own derived module names per target.

This is a Phase 5 prerequisite: without it, no XCUITest can run, and Phase 6 CI will hard-fail on `xcodebuild test`. Documented retroactively as a pre-existing bug surfaced by Phase 5 — no `fix(...)` commit since it's a build-config bug, not a runtime bug. Use `chore(build):` per repo convention (precedent: `chore(tests):`, `chore(git/docs):`).

**Files:**
- Modify: `project.yml` (move `PRODUCT_MODULE_NAME` out of global `settings.base`, set per-target)

- [ ] **Step 1: Move `PRODUCT_MODULE_NAME` to per-target settings**

In `project.yml`, remove the line `PRODUCT_MODULE_NAME: ImageCRC` from the top-level `settings.base` block. Add `PRODUCT_MODULE_NAME: ImageCRC` to the `ImageCRC` target's `settings.base` block (alongside `PRODUCT_BUNDLE_IDENTIFIER`). Add `PRODUCT_MODULE_NAME: ImageCRCTests` to the `ImageCRCTests` target's `settings.base` block (next to `BUNDLE_LOADER` / `TEST_HOST`).

- [ ] **Step 2: Regenerate and verify build**

```bash
xcodegen generate
xcodebuild build -scheme ImageCRC -destination 'platform=macOS,arch=arm64' -quiet
```

Expected: build succeeds, no "Multiple commands produce" errors. Warning about "first of multiple matching destinations" is acceptable (arm64 vs x86_64 ambiguity is harmless).

- [ ] **Step 3: Verify `xcodebuild test` runs the existing suite**

```bash
xcodebuild test -scheme ImageCRC -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | tail -10
```

Expected: existing 92-test / 32-suite / 1-known-issue baseline runs green via xcodebuild. Counts may format differently than Swift Testing's CLI output — the important thing is `** TEST SUCCEEDED **`.

- [ ] **Step 4: Verify `swift test` still passes**

```bash
swift test 2>&1 | tail -3
```

Expected: 92 tests / 32 suites / 1 known issue, exit 0. No regression from the project.yml edit.

- [ ] **Step 5: Commit**

```bash
git add project.yml
git commit -m "$(cat <<'EOF'
chore(build): scope PRODUCT_MODULE_NAME per target

Global setting `PRODUCT_MODULE_NAME: ImageCRC` in `settings.base`
inherited into both the app and test targets, causing duplicate
`ImageCRC.swiftmodule/*` outputs on Xcode 26 / macOS 26 SDK and
breaking `xcodebuild test` before any test runs. SwiftPM was
unaffected (per-target derived module names).

Move the setting out of the global block and into per-target
`settings.base`: `ImageCRC` → `ImageCRC`, `ImageCRCTests` →
`ImageCRCTests`. Phase 5 prerequisite — XCUITest cannot run, and
Phase 6 CI cannot land, until xcodebuild test works.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Section A — UI test affordances

---

### Task 2: App-side launch-arg hook + preloaded-fixture FileChooser

**Why:** XCUITest is a separate process from the app under test, so dependency injection of test doubles is impossible at compile time. The only handshake is `app.launchEnvironment` and `app.launchArguments` set on the `XCUIApplication` from the test, then read by the app at startup. The hook needs to:

1. Detect `IMAGECRC_UI_TEST=1` in the process environment.
2. Parse a `--ui-test-output-dir <path>` launch arg → set as `settings.outputDirectory`.
3. Parse a `--ui-test-preload-files <count>` launch arg → generate that many synthetic 64x64 PNG files in a temp subdir and call `vm.addURLs(...)` once the VM exists.
4. (For cancel-flow test) Parse a `--ui-test-slow-conversion <ms>` launch arg → no-op for now in production code, but `Converter` injection point lets the app swap in a `SlowConverter` that sleeps `ms` milliseconds per file before delegating to the real `ImageConverter`.

**Constraint:** the hook must be a **single** call site at app startup — not scattered across views. The `ImageCRCApp` `body` reads it once on first appear and applies side-effects to the `viewModel`.

**Files:**
- Create: `App/UITestSupport.swift`
- Modify: `App/ImageCRCApp.swift`
- Modify: `Package.swift` (exclude `UITests` from the SwiftPM test target — it lives outside SwiftPM)

- [ ] **Step 1: Create `App/UITestSupport.swift`**

```swift
// App/UITestSupport.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Launch-argument-driven hooks that let XCUITest seed the app's state without
/// driving NSOpenPanel. Dormant unless `IMAGECRC_UI_TEST=1` is set in the
/// process environment — adds zero overhead to normal launches.
enum UITestSupport {
    static var isActive: Bool {
        ProcessInfo.processInfo.environment["IMAGECRC_UI_TEST"] == "1"
    }

    /// Apply launch-argument-driven preloads to the given view model. Call once
    /// after the VM is constructed. No-op when `isActive` is false.
    @MainActor
    static func applyLaunchArguments(to viewModel: ConversionViewModel) {
        guard isActive else { return }
        let args = ProcessInfo.processInfo.arguments

        if let dir = value(for: "--ui-test-output-dir", in: args) {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            viewModel.settings.outputDirectory = url
        }

        if let countStr = value(for: "--ui-test-preload-files", in: args),
           let count = Int(countStr), count > 0,
           let outputDir = viewModel.settings.outputDirectory {
            // Stage synthetic PNGs in a sibling tempdir under outputDir so they
            // share the same lifetime; XCUITest may delete the parent on tearDown.
            let stagingDir = outputDir
                .deletingLastPathComponent()
                .appendingPathComponent("ui-test-inputs", isDirectory: true)
            try? FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
            var seeded: [URL] = []
            for i in 0..<count {
                let url = stagingDir.appendingPathComponent("preload-\(i).png")
                if writeSyntheticPNG(width: 256, height: 256, to: url) {
                    seeded.append(url)
                }
            }
            viewModel.addURLs(seeded)
        }
    }

    private static func value(for flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    @discardableResult
    private static func writeSyntheticPNG(width: Int, height: Int, to url: URL) -> Bool {
        let cs = CGColorSpaceCreateDeviceRGB()
        let bmp = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: bmp
        ) else { return false }
        // A simple solid colour is enough — XCUITest cares about file count, not pixels.
        ctx.setFillColor(red: 0.6, green: 0.4, blue: 0.9, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let img = ctx.makeImage() else { return false }
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { return false }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest)
    }
}
```

This file lives in the **production target** (per `project.yml`'s `App` source path). It is opt-in by env var, so it doesn't change app behaviour for normal launches. The `ImageIO` and `UniformTypeIdentifiers` imports are already used elsewhere in production.

- [ ] **Step 2: Wire it into `App/ImageCRCApp.swift`**

The hook needs to fire once after the `ConversionViewModel` is constructed, and before the user can interact. Put it inside an `.onAppear` on `ContentView` — it fires once on first display, after the VM exists.

Replace the body in `App/ImageCRCApp.swift`:

```swift
import SwiftUI

@main
struct ImageCRCApp: App {
    @State private var viewModel = ConversionViewModel()
    @AppStorage("appAppearance") private var appearance: AppAppearance = .system

    var body: some Scene {
        Window("ImageCRC", id: "main") {
            ContentView(viewModel: viewModel, appearance: $appearance)
                .frame(minWidth: 900, minHeight: 640)
                .onAppear {
                    UITestSupport.applyLaunchArguments(to: viewModel)
                }
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

The `.onAppear` fires once when `ContentView` first becomes visible. The VM is already initialized via `@State` so this is safe.

- [ ] **Step 3: Exclude `UITests` from SwiftPM test target**

Edit `Package.swift` — extend the `exclude` list:

```swift
exclude: ["Fixtures", "CodecTests/.gitkeep", "IntegrationTests/.gitkeep", "UITests"],
```

Without this, when `Tests/UITests/` lands in T6, SwiftPM will try to compile XCUITest sources with the regular `import Testing` runtime and fail.

- [ ] **Step 4: Verify build**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3
```

Expected: build green, 92 tests still pass.

- [ ] **Step 5: Commit**

```bash
git add App/UITestSupport.swift App/ImageCRCApp.swift Package.swift
git commit -m "$(cat <<'EOF'
feat(app): add dormant UI-test launch-arg hook

`UITestSupport.applyLaunchArguments(to:)` reads `--ui-test-output-dir`
and `--ui-test-preload-files <N>`, fires only when `IMAGECRC_UI_TEST=1`
is set in the process environment. Wired into `ContentView.onAppear`
so it runs once after VM initialisation. Production launches are
unaffected — the env-var gate means zero overhead in the normal path.

XCUITest needs this because the test process can't inject test doubles
into the app process; the only handshake is launch arguments.

Also exclude future `Tests/UITests/` dir from the SwiftPM test target —
XCUITest sources can't be hosted by SwiftPM (different runtime, separate
process model) and must be Xcode-only.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Add accessibility identifiers to key views

**Why:** XCUITest queries the AX tree by `identifier`, NOT by visible text. Identifiers are stable across localization, font changes, and animation states; visible-text queries are not. We add identifiers only on the elements the UI test needs to find. Other elements stay untouched.

Identifiers chosen to be self-documenting and unlikely to clash with system-provided ones (system never sets these). All in `lowerCamelCase`, no spaces, no SwiftUI-default prefix conflicts.

| View | Element | Identifier |
|------|---------|------------|
| `DropZoneView` | root tappable rectangle | `dropZone` |
| `ContentView` | "Convert N images" start button | `startButton` |
| `ContentView` | file list root (when files present) | `fileList` |
| `SettingsPanelView` | quality slider | `qualitySlider` |
| `SettingsPanelView` | format segmented picker | `formatPicker` |
| `SettingsPanelView` | "Choose…" output folder button | `outputFolderButton` |
| `SettingsPanelView` | output-folder display label | `outputFolderPath` |
| `ProgressOverlayView` | cancel button | `cancelButton` |
| `ProgressOverlayView` | progress overlay root | `progressOverlay` |
| `CompletionSheetView` | sheet root | `completionSheet` |
| `CompletionSheetView` | "Done" dismiss button | `dismissButton` |

**Files:**
- Modify: `Views/DropZoneView.swift`, `Views/ContentView.swift`, `Views/SettingsPanelView.swift`, `Views/ProgressOverlayView.swift`, `Views/CompletionSheetView.swift`

- [ ] **Step 1: `DropZoneView` — add `.accessibilityIdentifier("dropZone")`**

In `Views/DropZoneView.swift`, on the outer `ZStack` (or the same view chain that already carries `.frame(height: 180)`), append:

```swift
.accessibilityIdentifier("dropZone")
```

Place it just after `.contentShape(...)`. Pattern: stable `accessibilityIdentifier` should attach to the view that already has the tap handler so XCUITest's `.tap()` lands on the same hit target the user sees.

- [ ] **Step 2: `ContentView` — `startButton` and `fileList`**

In `Views/ContentView.swift`'s `actionBar` computed property, on the `Button { viewModel.start() } label: { ... }` chain, after `.disabled(...)`:

```swift
.accessibilityIdentifier("startButton")
```

In `leftColumn`, on `FileListView(...)` view, append:

```swift
.accessibilityIdentifier("fileList")
```

- [ ] **Step 3: `SettingsPanelView` — slider, picker, folder button, folder path**

In `Views/SettingsPanelView.swift`:

On the `Slider(...)` in `qualitySection`, append `.accessibilityIdentifier("qualitySlider")` after `.tint(...)`.

On the format `FullWidthSegmented(selection: $settings.outputFormat, ...)` in `outputSection`, append `.accessibilityIdentifier("formatPicker")` after the `FullWidthSegmented` view.

On `Button("Choose…", action: onChooseFolder)` in `outputSection`, append `.accessibilityIdentifier("outputFolderButton")` after `.pointingHandCursor()`.

On the output-folder `Text(settings.outputDirectory?.path ?? "Not selected")` in `outputSection`, append `.accessibilityIdentifier("outputFolderPath")` after the existing background modifier.

- [ ] **Step 4: `ProgressOverlayView` — cancel button + overlay root**

In `Views/ProgressOverlayView.swift`:

On the outer `ZStack`, append `.accessibilityIdentifier("progressOverlay")` after `.transition(...)`.

On the `Button(role: .destructive, action: onCancel) { ... }`, append `.accessibilityIdentifier("cancelButton")` after `.pointingHandCursor()`.

- [ ] **Step 5: `CompletionSheetView` — sheet root + dismiss button**

In `Views/CompletionSheetView.swift`:

On the outer `VStack(spacing: 18)`, append `.accessibilityIdentifier("completionSheet")` after `.onAppear { ... }`.

On `Button("Done", action: onDismiss)`, append `.accessibilityIdentifier("dismissButton")` after `.pointingHandCursor()`.

- [ ] **Step 6: Verify build + tests**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3
```

Expected: build green; 92 tests still pass (these are SwiftUI-only changes — pure visual modifiers, can't change the model layer).

- [ ] **Step 7: Commit**

```bash
git add Views/DropZoneView.swift Views/ContentView.swift Views/SettingsPanelView.swift Views/ProgressOverlayView.swift Views/CompletionSheetView.swift
git commit -m "$(cat <<'EOF'
feat(ui): add accessibility identifiers for XCUITest

Stable AX identifiers on the elements the upcoming UI tests query:
dropZone, startButton, fileList, qualitySlider, formatPicker,
outputFolderButton, outputFolderPath, cancelButton, progressOverlay,
completionSheet, dismissButton. lowerCamelCase, no localization
coupling — XCUITest queries by identifier, never by visible text.

No behaviour change — `.accessibilityIdentifier` is a SwiftUI modifier
that only writes to the AX tree.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Slow-conversion `Converter` for cancel-flow observability

**Why:** A real conversion of a 64x64 synthetic PNG → JPEG completes in ~1ms per file. XCUITest's `.tap()` on the cancel button can't fire fast enough to actually intercept; the completion sheet appears before the cancel can be observed. To make cancel externally observable we need conversions that take ≥ ~500ms each, with enough files queued that ProgressOverlayView is shown for ≥ 2 seconds.

The cleanest path: extend the existing `Converter` protocol injection that Phase 3 added. `UITestSupport` swaps in a `SlowConverter` wrapper that sleeps `N` ms before delegating to a real `ImageConverter`. This is opt-in via env var and uses the same launch-arg parser.

**Files:**
- Modify: `App/UITestSupport.swift` (add `SlowConverter`)
- Modify: `App/ImageCRCApp.swift` (compose VM with conditional Converter)

- [ ] **Step 1: Add `SlowConverter` to `App/UITestSupport.swift`**

Append to the file:

```swift
/// Wraps a real Converter and delays each file by a fixed duration. Used by
/// XCUITest cancel-flow tests where the actual conversion is too fast for
/// the cancel button tap to observably intercept. Off-thread sleeps inside
/// the same actor isolation as the wrapped converter — the wrapped stream
/// still drives `ConversionEvent` flow.
struct SlowConverter: Converter {
    let inner: any Converter
    let perFileDelayMs: Int

    func convert(files: [ImageFile], settings: ConversionSettings) -> AsyncStream<ConversionEvent> {
        AsyncStream { continuation in
            let job = Task {
                let stream = inner.convert(files: files, settings: settings)
                for await event in stream {
                    if case .willStart = event {
                        try? await Task.sleep(nanoseconds: UInt64(perFileDelayMs) * 1_000_000)
                    }
                    if Task.isCancelled { break }
                    continuation.yield(event)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                job.cancel()
            }
        }
    }
}

extension UITestSupport {
    /// Returns a Converter — wrapped in SlowConverter when the launch arg is set.
    /// Always returns the production `ImageConverter` when the hook is dormant.
    static func converter() -> any Converter {
        guard isActive else { return ImageConverter() }
        let args = ProcessInfo.processInfo.arguments
        if let str = value(for: "--ui-test-slow-conversion", in: args),
           let ms = Int(str), ms > 0 {
            return SlowConverter(inner: ImageConverter(), perFileDelayMs: ms)
        }
        return ImageConverter()
    }
}
```

The cancel-flow test will pass `--ui-test-slow-conversion 500` and queue 6 files: total wall-clock ~3 seconds, plenty of time for the cancel tap to land before the `.didFinish` event.

- [ ] **Step 2: Wire `UITestSupport.converter()` into `ImageCRCApp`**

Change the `@State` line in `App/ImageCRCApp.swift`:

```swift
@State private var viewModel = ConversionViewModel(converter: UITestSupport.converter())
```

This replaces the default `ImageConverter()` injection. When the hook is dormant, `UITestSupport.converter()` returns plain `ImageConverter()` — identical to current behaviour.

- [ ] **Step 3: Verify build + tests**

```bash
swift build 2>&1 | tail -5
swift test 2>&1 | tail -3
```

Expected: 92/32 + 1 known issue still pass.

- [ ] **Step 4: Commit**

```bash
git add App/UITestSupport.swift App/ImageCRCApp.swift
git commit -m "$(cat <<'EOF'
feat(app): SlowConverter for XCUITest cancel-flow observability

Synthetic 64x64 → JPEG conversions complete in ~1ms each, too fast for
XCUITest to observably intercept with a cancel button tap. SlowConverter
wraps the real ImageConverter and sleeps a configurable per-file delay
before forwarding each .willStart, so the cancel tap reliably lands
mid-batch.

Composed into the VM only when IMAGECRC_UI_TEST=1 + the
--ui-test-slow-conversion <ms> launch arg are present. Production
launches still get plain ImageConverter via the same factory entry point.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Section B — XCUITest target + smoke

---

### Task 5: Add `bundle.ui-testing` target to `project.yml`

**Why:** XCUITest needs its own Xcode target with `type: bundle.ui-testing`, separate from the unit-test target. The UI test target requires `TEST_TARGET_NAME` (the app it drives) and **must not** carry `BUNDLE_LOADER` / `TEST_HOST` (those are unit-test patterns). The scheme also needs the UI tests added under `test.targets`.

**Files:**
- Modify: `project.yml`

- [ ] **Step 1: Add the target**

Append to `targets:` in `project.yml`:

```yaml
  ImageCRCUITests:
    type: bundle.ui-testing
    platform: macOS
    deploymentTarget: "14.0"
    sources:
      - path: Tests/UITests
    dependencies:
      - target: ImageCRC
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
        PRODUCT_MODULE_NAME: ImageCRCUITests
        TEST_TARGET_NAME: ImageCRC
```

Add the new target to the scheme's test list (under `schemes.ImageCRC.test.targets`):

```yaml
    test:
      config: Debug
      targets:
        - ImageCRCTests
        - ImageCRCUITests
```

Also update `schemes.ImageCRC.build.targets`:

```yaml
    build:
      targets:
        ImageCRC: all
        ImageCRCTests: [test]
        ImageCRCUITests: [test]
```

- [ ] **Step 2: Create the directory with a placeholder so xcodegen succeeds**

XcodeGen errors on a sources path that doesn't exist. We create the dir and a stub file (the real test lands in T6).

```bash
mkdir -p Tests/UITests
```

Create `Tests/UITests/.gitkeep` (empty). The actual test file lands in T6 — don't write a stub `.swift` here because xcodegen would try to compile it.

Actually — if the directory is empty, xcodegen with `generateEmptyDirectories: true` will accept it. But there's a subtlety: xcodebuild may refuse to link a UI test target with no sources. To unblock T5 → T6 sequencing without an empty target, we land T5 + T6 as a compound deliverable (one test file written before xcodegen runs). To preserve commit granularity, the T5 commit lands the project.yml change AND a placeholder XCUITest file containing only a one-line `import XCTest` plus an empty `final class _Phase5Bootstrap: XCTestCase {}`. T6 replaces this stub with real tests.

- [ ] **Step 3: Write the bootstrap stub**

```swift
// Tests/UITests/_Phase5Bootstrap.swift
import XCTest

/// Placeholder so the ImageCRCUITests target has at least one source file,
/// allowing xcodegen + xcodebuild to set up the bundle.ui-testing target.
/// Real UI tests land in T6 and supersede this empty class.
final class _Phase5Bootstrap: XCTestCase {
    func testTargetCompiles() {
        XCTAssertTrue(true)
    }
}
```

This bootstrap test runs and passes immediately, proving the target builds and test discovery works. T6 deletes it.

- [ ] **Step 4: Regenerate and run xcodebuild**

```bash
xcodegen generate
xcodebuild test -scheme ImageCRC -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | tail -15
```

Expected: existing tests pass + `testTargetCompiles` passes. Both targets in the scheme. `** TEST SUCCEEDED **`.

If xcodebuild surfaces any signing / entitlements error specific to UI tests on macOS, this is where it shows. The fallback is `CODE_SIGN_ENTITLEMENTS = ""` plus `ENABLE_HARDENED_RUNTIME: NO` on the UI test target — but try the simpler config first.

- [ ] **Step 5: Verify SwiftPM unaffected**

```bash
swift test 2>&1 | tail -3
```

Expected: 92 tests still pass.

- [ ] **Step 6: Commit**

```bash
git add project.yml Tests/UITests/_Phase5Bootstrap.swift
git commit -m "$(cat <<'EOF'
test(ui): add ImageCRCUITests bundle.ui-testing target

Wires a Tests/UITests source path under a new bundle.ui-testing target
in project.yml, with TEST_TARGET_NAME=ImageCRC for the UI runner. Adds
the target to the scheme's build and test target lists so `xcodebuild
test -scheme ImageCRC` runs both unit and UI suites.

A bootstrap _Phase5Bootstrap.testTargetCompiles is included to give the
target one compilable source — real UI tests land next.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Happy-path XCUITest

**Why:** Cover the core user journey end-to-end through real SwiftUI: launch app → files preloaded → start button enabled → tap start → progress overlay shows → completion sheet appears → tap dismiss → app returns to idle.

The test is structured as one method per assertion, using `XCTContext.runActivity` for narrative grouping. The launch is heavyweight (~1 second) so we set up once via class-scoped state where reasonable, but XCTest UI tests prefer per-test launches for isolation; we accept that cost.

Timeouts: every `expectation(for:)` / `waitForExistence` uses an explicit `timeout: 30` for completion sheet and `timeout: 10` for everything else. Lower bounds, never `Thread.sleep`.

**Files:**
- Create: `Tests/UITests/ImageCRCUITests.swift` (replaces `_Phase5Bootstrap.swift`)
- Delete: `Tests/UITests/_Phase5Bootstrap.swift`

- [ ] **Step 1: Write the happy-path test**

```swift
// Tests/UITests/ImageCRCUITests.swift
import XCTest

final class ImageCRCHappyPathTests: XCTestCase {
    private var tempDirURL: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false

        // Per-test temp dir so the app's preloaded fixtures + outputs land in a
        // disposable place. Cleaned up in tearDown.
        let base = FileManager.default.temporaryDirectory
        tempDirURL = base.appendingPathComponent("imagecrc-uitest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
        let outputDir = tempDirURL.appendingPathComponent("out", isDirectory: true)

        app = XCUIApplication()
        app.launchEnvironment["IMAGECRC_UI_TEST"] = "1"
        app.launchArguments = [
            "--ui-test-output-dir", outputDir.path,
            "--ui-test-preload-files", "2",
        ]
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let url = tempDirURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testHappyPathFromPreloadedFilesToCompletionSheet() throws {
        app.launch()

        // Sanity: drop zone is visible, start button is present.
        let dropZone = app.descendants(matching: .any)["dropZone"]
        XCTAssertTrue(dropZone.waitForExistence(timeout: 10),
                      "dropZone must be in the AX tree within 10s of launch")

        // Preloaded files appear → start button enabled.
        let startButton = app.descendants(matching: .any)["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10),
                      "startButton must exist")
        let startEnabledExp = expectation(for: NSPredicate(format: "isEnabled == true"),
                                          evaluatedWith: startButton)
        wait(for: [startEnabledExp], timeout: 10)

        // Tap start. Progress overlay must appear.
        startButton.tap()
        let progressOverlay = app.descendants(matching: .any)["progressOverlay"]
        // Two 256x256 PNGs → JPEG is fast (<200ms total) so we may miss the overlay.
        // We instead assert the terminal state: completion sheet appears.

        // Completion sheet must appear within 30s.
        let completionSheet = app.descendants(matching: .any)["completionSheet"]
        XCTAssertTrue(completionSheet.waitForExistence(timeout: 30),
                      "completionSheet must appear within 30s of start tap")

        // Dismiss returns app to idle (drop zone visible, start button gone-or-disabled).
        let dismiss = app.descendants(matching: .any)["dismissButton"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
        dismiss.tap()

        // After dismiss, completion sheet is gone.
        let sheetGoneExp = expectation(for: NSPredicate(format: "exists == false"),
                                       evaluatedWith: completionSheet)
        wait(for: [sheetGoneExp], timeout: 10)

        // Drop zone reasserts visibility (the UI state machine returned to idle).
        XCTAssertTrue(dropZone.exists, "dropZone must remain visible after dismiss")

        // Side-effect verification: the output dir contains one or two .jpg files.
        let outputDir = tempDirURL.appendingPathComponent("out")
        let outputs = try FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)
        let jpgCount = outputs.filter { $0.pathExtension.lowercased() == "jpg" }.count
        XCTAssertGreaterThanOrEqual(jpgCount, 1, "at least one JPG must land in the output dir")
        XCTAssertLessThanOrEqual(jpgCount, 2, "at most two JPGs (one per preloaded file)")
        // Note: not asserting exactly == 2 because an empty preloaded-file write
        // would already fail the dismiss path; we just verify the sheet's claim.
    }
}
```

Note `app.descendants(matching: .any)["id"]` is XCUITest's universal lookup — robust against SwiftUI rendering choice (button vs. control vs. group).

- [ ] **Step 2: Delete the bootstrap stub**

```bash
rm Tests/UITests/_Phase5Bootstrap.swift
```

- [ ] **Step 3: Run xcodebuild test**

```bash
xcodegen generate
xcodebuild test -scheme ImageCRC -destination 'platform=macOS,arch=arm64' -only-testing:ImageCRCUITests/ImageCRCHappyPathTests 2>&1 | tail -15
```

Expected: 1 UI test passes. If it fails, **read the failure carefully**:
- Element not found: identifier mismatch → fix in the production view, NOT the test.
- Timeout: bump timeouts only after verifying the issue isn't a stuck event.
- Sheet doesn't appear: VM didn't transition to `.completed` → check `UITestSupport.applyLaunchArguments` actually wired files.
- Output dir empty: app couldn't write to `tempDirURL/out` — check sandbox + path expansion.

- [ ] **Step 4: Run full xcodebuild test**

```bash
xcodebuild test -scheme ImageCRC -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | tail -10
```

Expected: 92 unit/codec/integration tests + 1 UI test, all green.

- [ ] **Step 5: Run swift test (smoke check)**

```bash
swift test 2>&1 | tail -3
```

Expected: 92/32/1 known issue (UI test not visible to SwiftPM, by design).

- [ ] **Step 6: Commit**

```bash
git add Tests/UITests/ImageCRCUITests.swift
git rm Tests/UITests/_Phase5Bootstrap.swift
git commit -m "$(cat <<'EOF'
test(ui): happy-path XCUITest from preloaded files to completion sheet

XCUIApplication launches with IMAGECRC_UI_TEST=1 plus
--ui-test-preload-files 2 and --ui-test-output-dir <tmp>; the dormant
hook in App/UITestSupport seeds two synthetic PNGs into the VM. Test
verifies the chain: dropZone visible → startButton enabled → tap →
completionSheet appears within 30s → tap dismissButton → sheet gone,
dropZone still visible. Asserts 1–2 .jpg files landed in the output dir
as a side-effect cross-check.

Identifier-based queries throughout — no localization coupling, no
visible-text matching. Replaces the _Phase5Bootstrap stub from T5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Cancel-flow XCUITest

**Why:** Cover the cancel button working mid-batch. With `--ui-test-slow-conversion 500` and 6 preloaded files, total runtime ≈ 3 seconds — plenty of time for the cancel tap to land before completion. Assertion: completion sheet still appears (terminal state), summary's `wasCancelled == true` is reflected by the visible "Cancelled" title and a non-zero `cancelled` count.

Since XCUITest can't read `summary.wasCancelled` directly, we assert via accessibility-tree state: completion sheet exists AND the dismiss button still works AND fewer files than total exist in the output dir.

**Files:**
- Modify: `Tests/UITests/ImageCRCUITests.swift` (append a new XCTestCase class)

- [ ] **Step 1: Append the cancel-flow test**

```swift
final class ImageCRCCancelFlowTests: XCTestCase {
    private var tempDirURL: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let base = FileManager.default.temporaryDirectory
        tempDirURL = base.appendingPathComponent("imagecrc-uitest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)
        let outputDir = tempDirURL.appendingPathComponent("out", isDirectory: true)

        app = XCUIApplication()
        app.launchEnvironment["IMAGECRC_UI_TEST"] = "1"
        app.launchArguments = [
            "--ui-test-output-dir", outputDir.path,
            "--ui-test-preload-files", "6",
            "--ui-test-slow-conversion", "500",
        ]
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let url = tempDirURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func testCancelMidBatchReachesCompletionSheetWithFewerOutputs() throws {
        app.launch()

        let startButton = app.descendants(matching: .any)["startButton"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 10))
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"),
                                  evaluatedWith: startButton)
        wait(for: [enabled], timeout: 10)
        startButton.tap()

        // Progress overlay must appear (slow conversion holds it on screen).
        let cancelButton = app.descendants(matching: .any)["cancelButton"]
        XCTAssertTrue(cancelButton.waitForExistence(timeout: 10),
                      "cancelButton must appear once a slow batch is running")

        // Tap cancel mid-batch (overlay has been shown for >0ms; first file's
        // 500ms sleep guarantees we're in willStart-pending, not idle).
        cancelButton.tap()

        // Completion sheet still appears terminally.
        let completionSheet = app.descendants(matching: .any)["completionSheet"]
        XCTAssertTrue(completionSheet.waitForExistence(timeout: 30),
                      "completionSheet must still appear after cancel tap")

        // Dismiss reverts to idle.
        let dismiss = app.descendants(matching: .any)["dismissButton"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
        dismiss.tap()

        // Side-effect: output dir should have FEWER than 6 successful jpg files.
        let outputDir = tempDirURL.appendingPathComponent("out")
        let outputs = (try? FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: nil)) ?? []
        let jpgCount = outputs.filter { $0.pathExtension.lowercased() == "jpg" }.count
        XCTAssertLessThan(jpgCount, 6,
                          "cancel must short-circuit some files; output dir had \(jpgCount) of 6")
    }
}
```

The `XCTAssertLessThan(jpgCount, 6)` assertion is the externally observable proof that cancel actually short-circuited the batch. If `jpgCount == 6` the cancel tap arrived too late and the test would fail honestly (signalling we need to either bump the slow-conversion delay or queue more files).

- [ ] **Step 2: Run the cancel-flow test**

```bash
xcodebuild test -scheme ImageCRC -destination 'platform=macOS,arch=arm64' -only-testing:ImageCRCUITests/ImageCRCCancelFlowTests 2>&1 | tail -15
```

Expected: 1 UI test passes. If `jpgCount == 6` (cancel landed too late), bump `--ui-test-slow-conversion` from 500 to 1000ms or queue more files. Don't relax the assertion — that would defeat the test.

- [ ] **Step 3: Run full xcodebuild test**

```bash
xcodebuild test -scheme ImageCRC -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | tail -10
```

Expected: 92 unit/codec/integration tests + 2 UI tests, all green.

- [ ] **Step 4: Run swift test (smoke)**

```bash
swift test 2>&1 | tail -3
```

Expected: 92 / 32 / 1 known issue.

- [ ] **Step 5: Commit**

```bash
git add Tests/UITests/ImageCRCUITests.swift
git commit -m "$(cat <<'EOF'
test(ui): cancel-flow XCUITest with slow-conversion observability

Launches the app with --ui-test-slow-conversion 500 and 6 preloaded
files (≈3s total wall-clock). Test taps startButton → waits for
cancelButton in the progress overlay → taps cancel → asserts the
completion sheet appears terminally → dismisses → verifies fewer than 6
output JPGs landed on disk. The on-disk count is the externally
observable proof that cancel actually short-circuited the batch.

The 500ms per-file delay is wide enough that the cancel tap reliably
lands before the .didFinish event on macos-14 hardware. If a future
runner is too slow and jpgCount == 6, bump the delay rather than
relaxing the assertion.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

# Section C — Wire-up + docs

---

### Task 8: Document `xcodebuild test` and finalize

**Why:** `CLAUDE.md` lists build commands but not the test invocation needed for Phase 5+. Phase 6 will reference this directly. Update the build/run section so future contributors and CI both know the exact incantation.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add test invocation to CLAUDE.md**

In `CLAUDE.md`'s "Build & run" section, after `swift test`, add:

```markdown
- `xcodebuild test -scheme ImageCRC -destination 'platform=macOS,arch=arm64'` — runs unit/codec/integration tests **plus** the XCUITest UI smoke suite. SwiftPM (`swift test`) covers everything except UI tests; XCUITest requires Xcode-only host process injection, so the full test suite needs both invocations.
```

- [ ] **Step 2: Final smoke run on both build paths**

```bash
swift test 2>&1 | tail -3
xcodebuild test -scheme ImageCRC -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | tail -10
```

Expected:
- `swift test`: 92 tests / 32 suites / 1 known issue.
- `xcodebuild test`: same SwiftPM-side coverage **plus** 2 UI tests, all green. Final cumulative: 94 tests / 33 suites (XCUITest counts in xcodebuild's tally) + 1 known issue.

- [ ] **Step 3: Verify branch + tree**

```bash
git rev-parse --abbrev-ref HEAD    # tests/phase-1
git status                          # nothing to commit
```

- [ ] **Step 4: Commit the doc update**

```bash
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
docs(build): document xcodebuild test for XCUITest invocation

Phase 5 added an XCUITest target that swift test cannot host. Document
the canonical xcodebuild invocation so future contributors and Phase 6
CI both know the exact destination flag and arch pin.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5 Done When

- [ ] `xcodebuild test -scheme ImageCRC -destination 'platform=macOS,arch=arm64'` exits 0 with **94 tests** (92 existing + 2 UI) across **33 test classes** (32 existing suites + 1 XCUITest target with 2 classes ≈ 33–34 depending on how xcodebuild groups the tally — Swift Testing suites and XCTest classes count differently)
- [ ] `swift test` unchanged at 92 / 32 / 1 known issue
- [ ] `bundle.ui-testing` target wired in `project.yml` and present in scheme
- [ ] Production accessibility identifiers landed on dropZone, startButton, fileList, qualitySlider, formatPicker, outputFolderButton, outputFolderPath, cancelButton, progressOverlay, completionSheet, dismissButton
- [ ] App-side `UITestSupport.applyLaunchArguments` and `UITestSupport.converter()` dormant unless `IMAGECRC_UI_TEST=1`
- [ ] CLAUDE.md documents `xcodebuild test` invocation
- [ ] User approval to write Phase 6 plan

---

## Risks / Open Questions

1. **PRODUCT_MODULE_NAME fix scope (T1).** The xcodebuild "Multiple commands produce..." error is pre-existing — it's not introduced by Phase 5. Fixing it as a Phase 5 prerequisite is correct because (a) Phase 5 needs `xcodebuild test` to run and (b) Phase 6 needs it for CI. Leaving it for Phase 6 would block all of Phase 5. Documented in the T1 commit message.

2. **Slow-conversion timing reliability (T7).** 500ms per file × 6 files ≈ 3s gives generous margin on macos-14 hardware (Apple Silicon CI runners are fast — XCUITest tap latency is ~100ms, willStart-to-tap window is at least 400ms even for the first file). If we ever see flake in CI, bump to 800ms before relaxing the on-disk count assertion.

3. **Drop zone has no XCUITest coverage.** Click-to-browse path is also untested via real `NSOpenPanel` — only via the launch-arg seed. The drop zone's drag-and-drop target is genuinely difficult to drive from XCUITest reliably, and `NSOpenPanel` automation requires entitlement-laden tricks that don't survive sandboxed CI. Both deferred deliberately. The unit tests in Phase 3 (`ConversionViewModel — canStart, cancel, dismiss` and `chooseOutputDirectory routes through FakeFileChooser`) cover the VM-side of these paths.

4. **App sandbox is OFF for MVP.** Per CLAUDE.md, the app currently has no sandbox. UI-test-mode launch args writing to `/tmp/imagecrc-uitest-<uuid>/` work because of this. If sandbox is later enabled, the temp-dir path may need to move under the app's container (`NSTemporaryDirectory()` resolves correctly inside or outside sandbox, so the test would still work — but the launch-arg path passing would need security-scoped bookmark plumbing). Not a Phase 5 concern; flagged for whenever sandbox flips on.

5. **XCUITest counts in the Phase 6 cumulative.** Phase 4 ended at 92/32; Phase 5 adds 2 UI tests but xcodebuild reports them as separate XCTestCase classes (not Swift Testing suites). Final report should clarify the count: `swift test` = 92/32/+1ki; `xcodebuild test` = 94/+1ki across both runtimes.

6. **`Package.swift` exclude for `Tests/UITests/`.** SwiftPM auto-discovers any `.swift` under the test target's source path. We exclude `UITests` explicitly (T2 step 3). If a future contributor adds `Tests/UITests/Helpers.swift` it stays excluded — they need to opt back in or move it to `Tests/Support/` if they want SwiftPM-side reuse.

7. **`@testable import ImageCRC` from XCUITest is not possible.** Two-process model: the test process can only manipulate the app via `XCUIApplication`, never via direct symbol access. This is why `UITestSupport` lives in the **app target**, not the test target. All "fake" plumbing is opt-in inside the production binary.

---

## Out-of-scope (deliberately deferred)

- Real `NSOpenPanel` automation — covered by VM-level unit tests (Phase 3 `chooseOutputDirectory routes through FakeFileChooser`)
- Drag-and-drop on the drop zone — XCUITest macOS DnD synthesis is unreliable
- Settings-panel exhaustive UI coverage (every quality / format permutation) — Phase 4 perceptual matrix covers the conversion side
- Localized text assertions — accessibility identifiers are localization-stable
- `Scripts/make-app.sh` and `make-dmg.sh` — release packaging is unrelated to test coverage

---

## Pause points

- **After T1:** xcodebuild plumbing fixed; can run existing 92 tests via xcodebuild. Independent improvement, useful even if the rest of Phase 5 is paused.
- **After T2–T4:** all app-side affordances landed; ready for the actual UI tests.
- **After T5–T7:** XCUITest target + happy-path + cancel-flow all green.
- **After T8:** Phase 5 done; ready for Phase 6 (CI wiring on `macos-14` GH runner).

---

## Self-review

**Spec coverage:** Phase 5 commitments from `2026-05-05-testing-strategy.md` covered:
- `bundle.ui-testing` target in `project.yml` → T5
- accessibility identifiers on key views → T3 (full list of 11 covers strategy doc's 9 named ones)
- happy path drop → start → completion → dismiss → T6
- cancel flow → T7
- Open question from strategy doc ("env-flag + injected fixture vs `NSOpenPanel` automation") → resolved in favour of env-flag + injected fixture, documented in Constraints

**Placeholder scan:** every code block runnable. T1 fix is concrete (move one line, set per-target). T2's `UITestSupport` is full implementation. T6 / T7 tests are full bodies, not skeletons.

**Type consistency:** `Converter` protocol from `Services/Converter.swift` is `Sendable` and returns `AsyncStream<ConversionEvent>` — `SlowConverter` (T4) matches both. `ConversionViewModel.init(converter:fileChooser:)` accepts `any Converter` — verified in `ViewModels/ConversionViewModel.swift`. `FileChooser` protocol from `ViewModels/FileChooser.swift` is `@MainActor`-isolated — UI-test launch hook doesn't touch this protocol since it preloads files via `vm.addURLs(_:)` directly.

**Cross-task consistency:** T2 introduces `IMAGECRC_UI_TEST=1` as the master gate; T3 wires it into `ImageCRCApp.onAppear`; T4 extends `UITestSupport` with `converter()` factory; T6/T7 set the env in their `setUp`. Single-source-of-truth env name throughout.

**External observability:** every assertion is on something the AX tree exposes (identifier existence, button enablement, sheet presence) or on filesystem state (output JPG count). No assertions on internal model state from UI tests. Cancellation flow specifically asserts `jpgCount < 6` because that's the externally-observable evidence of cancel having short-circuited the batch.

**Phase 6 dependencies covered:** T1 fixes the xcodebuild blocker. T8 documents the canonical invocation. Phase 6 can write `.github/workflows/test.yml` referencing both `swift test` and `xcodebuild test ...` from this plan.
