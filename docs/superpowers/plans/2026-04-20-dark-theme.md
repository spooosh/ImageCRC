# Dark Theme Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix broken dark-mode rendering (hardcoded white window background) and add a three-way System/Light/Dark appearance toggle in the header, persisted across launches.

**Architecture:** New `AppAppearance` enum stored via `@AppStorage` on the `App` root, passed as a `Binding` into `ContentView`. `ContentView` applies `.preferredColorScheme(appearance.colorScheme)` and renders a `Menu`-based `AppearancePicker` in its header. Window background switched from `Color.white` to `Color(nsColor: .windowBackgroundColor)`. One adaptive tweak to the thumbnail hairline.

**Tech Stack:** Swift 5.10, SwiftUI, macOS 14, `@AppStorage` / `@Observable`.

**Spec:** `docs/superpowers/specs/2026-04-20-dark-theme-design.md`

**Testing note:** the project has no test suite landed yet (per `CLAUDE.md`). Verification is manual via `./Scripts/make-app.sh` + `open ./ImageCRC.app` with the system theme toggled in System Settings → Appearance.

---

### Task 1: Add `AppAppearance` model

**Files:**
- Create: `Models/AppAppearance.swift`

- [ ] **Step 1: Create the model file**

```swift
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    var sfSymbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon.fill"
        }
    }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Models/AppAppearance.swift
git commit -m "feat(appearance): add AppAppearance enum for theme selection"
```

---

### Task 2: Add `AppearancePicker` view

**Files:**
- Create: `Views/AppearancePicker.swift`

- [ ] **Step 1: Create the picker view**

```swift
import SwiftUI

struct AppearancePicker: View {
    @Binding var appearance: AppAppearance

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { mode in
                    Label(mode.label, systemImage: mode.sfSymbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: appearance.sfSymbol)
                .imageScale(.large)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Appearance")
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Views/AppearancePicker.swift
git commit -m "feat(appearance): add AppearancePicker menu control"
```

---

### Task 3: Wire `@AppStorage` in `ImageCRCApp`

**Files:**
- Modify: `App/ImageCRCApp.swift`

- [ ] **Step 1: Replace file contents**

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
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

- [ ] **Step 2: Expect build to fail (ContentView signature mismatch — fixed in Task 4)**

Run: `swift build`
Expected: error about `ContentView` initializer — this is fine; next task adds the parameter.

---

### Task 4: Apply appearance in `ContentView` and fix background

**Files:**
- Modify: `Views/ContentView.swift`

- [ ] **Step 1: Add the binding, swap background, mount the picker, apply colorScheme**

Full replacement file contents:

```swift
import SwiftUI

struct ContentView: View {
    @Bindable var viewModel: ConversionViewModel
    @Binding var appearance: AppAppearance

    @FocusState private var focusedField: SettingsPanelView.Field?

    private static let rightPanelWidth: CGFloat = 420

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            HStack(spacing: 0) {
                leftColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                rightPanel
                    .frame(width: Self.rightPanelWidth)
                    .frame(maxHeight: .infinity)
            }

            if viewModel.phase == .running {
                ProgressOverlayView(
                    progress: viewModel.progress,
                    completed: viewModel.completed,
                    total: viewModel.total,
                    currentFilename: viewModel.currentFilename,
                    onCancel: { viewModel.cancel() }
                )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = nil }
        .animation(.easeInOut(duration: 0.25), value: viewModel.phase)
        .animation(.easeInOut(duration: 0.25), value: viewModel.files.count)
        .preferredColorScheme(appearance.colorScheme)
        .sheet(isPresented: completionBinding) {
            if let summary = viewModel.summary {
                CompletionSheetView(summary: summary) {
                    viewModel.dismissCompletion()
                }
            }
        }
    }

    // MARK: - Left column

    private var leftColumn: some View {
        VStack(spacing: 16) {
            header

            DropZoneView(
                hasFiles: !viewModel.files.isEmpty,
                onAdd: { viewModel.addURLs($0) },
                onBrowse: { viewModel.browseForFiles() }
            )

            if !viewModel.files.isEmpty {
                FileListView(
                    files: viewModel.files,
                    onRemove: { viewModel.remove($0) },
                    onClear: { viewModel.clearFiles() }
                )
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(24)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("ImageCRC")
                    .font(.title2.bold())
                Text("Bulk image optimizer & converter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AppearancePicker(appearance: $appearance)
        }
    }

    // MARK: - Right panel

    private var rightPanel: some View {
        VStack(spacing: 16) {
            SettingsPanelView(
                settings: $viewModel.settings,
                onChooseFolder: { viewModel.chooseOutputDirectory() },
                focus: $focusedField
            )

            Spacer(minLength: 0)

            actionBar
        }
        .padding(24)
    }

    private var actionBar: some View {
        Button {
            viewModel.start()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                Text(startButtonLabel)
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!viewModel.canStart)
        .pointingHandCursor()
    }

    private var startButtonLabel: String {
        switch viewModel.files.count {
        case 0: return "Convert"
        case 1: return "Convert 1 image"
        case let n: return "Convert \(n) images"
        }
    }

    private var completionBinding: Binding<Bool> {
        Binding(
            get: { viewModel.phase == .completed && viewModel.summary != nil },
            set: { newValue in
                if !newValue { viewModel.dismissCompletion() }
            }
        )
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add App/ImageCRCApp.swift Views/ContentView.swift
git commit -m "feat(appearance): apply preferredColorScheme and adaptive window background"
```

---

### Task 5: Make thumbnail outline adaptive

**Files:**
- Modify: `Views/AsyncThumbnailView.swift:29`

- [ ] **Step 1: Swap the color**

Find the line:
```swift
.stroke(Color.black.opacity(0.08), lineWidth: 0.5)
```

Replace with:
```swift
.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Views/AsyncThumbnailView.swift
git commit -m "fix(thumbnail): use adaptive primary color for outline"
```

---

### Task 6: Manual verification

- [ ] **Step 1: Build the app bundle**

Run: `./Scripts/make-app.sh`
Expected: produces `./ImageCRC.app` without errors.

- [ ] **Step 2: Launch and inspect**

Run: `open ./ImageCRC.app`

Check in order:

1. **System = Light, Appearance = System** — app renders as it did before the change (white-ish window, dark text, visible drop zone, visible file list, visible settings labels).
2. **Flip system to Dark via System Settings → Appearance, Appearance = System** — app window turns dark; all text, icons, dividers, drop zone border, settings labels, quality slider ticks, format chips remain legible.
3. **Appearance menu in header** — click the sun/moon/half-circle icon; menu appears with three options with icons and checkmark on the current one.
4. **Appearance = Light (system still Dark)** — app window stays light regardless of system.
5. **Appearance = Dark (system = Light)** — app window stays dark regardless of system.
6. **Progress overlay** — drag in any image, convert, watch the progress overlay; scrim should still be dark, text on card should be legible in both themes.
7. **Completion sheet** — sheet renders legibly in both themes.
8. **Persistence** — pick Dark, quit (`Cmd-Q`), relaunch → still Dark.

- [ ] **Step 3: Revert system appearance if you changed it for testing**

---

### Done criteria

- [ ] All six tasks complete, five commits on `main`.
- [ ] Manual verification list in Task 6 all ticked.
- [ ] No hardcoded `Color.white` or `Color.black` (outside intentional overlay/scrim/chip-on-accent) remain.
