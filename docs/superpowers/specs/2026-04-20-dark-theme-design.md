# Dark-mode support and appearance toggle

## Problem

`ContentView.swift:12` paints the window background with hardcoded `Color.white.ignoresSafeArea()`. In macOS dark mode the system switches default text colors (`.primary`, `.secondary`, etc.) to near-white, so text disappears against the still-white background. The rest of the codebase already uses semantic colors (`.primary`, `.secondary`, `.accentColor`) — fixing the one hardcoded surface is sufficient for automatic adaptation.

Additionally, the user wants a per-app appearance override so the app can be forced to light or dark independently of the system.

## Goals

1. Window chrome and content adapt correctly to macOS dark mode.
2. Three-way appearance toggle: System / Light / Dark, persisted across launches.
3. Toggle reachable from the header of the main window (picker menu with SF Symbol icon).

## Non-goals

- Custom accent colors.
- Theming of thumbnails' image content.
- Syncing appearance to iCloud / cross-device.
- Live preview of the opposite theme.

## Design

### Model

New file `Models/AppAppearance.swift`:

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

`colorScheme == nil` means "let SwiftUI inherit from the environment", which follows the system setting.

### Storage

`@AppStorage("appAppearance")` declared on `ImageCRCApp`, default `.system`. `@AppStorage` needs `RawRepresentable` with a primitive raw value — `String` works. The stored value survives app restarts via `UserDefaults`.

### Wiring

`ImageCRCApp` passes the binding to `ContentView`. `ContentView` applies `.preferredColorScheme(appearance.colorScheme)` on its root `ZStack`. Window background switches from `Color.white` to `Color(nsColor: .windowBackgroundColor)` — this is the same color macOS uses for regular windows and adapts to light/dark automatically.

### Picker UI

New file `Views/AppearancePicker.swift`:

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

Placed inside `ContentView.header`, after the `Spacer()`:

```swift
private var header: some View {
    HStack {
        VStack(alignment: .leading, spacing: 2) {
            Text("ImageCRC").font(.title2.bold())
            Text("Bulk image optimizer & converter")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Spacer()
        AppearancePicker(appearance: $appearance)
    }
}
```

### Thumbnail border (adaptive)

`Views/AsyncThumbnailView.swift:29` currently uses `Color.black.opacity(0.08)` for the thumbnail outline. Replace with `Color.primary.opacity(0.08)` so the hairline remains visible (as light-on-dark) in dark mode.

### Deliberately unchanged

- `ProgressOverlayView.swift:12,43` — `Color.black.opacity(0.45)` scrim and `0.35` shadow are overlays that should stay dark in both themes (standard modal dimming).
- `SettingsPanelView.swift:192` — `Color.white` text inside a `.accentColor`-filled selected chip; must stay white regardless of theme for contrast against the accent fill.

## Affected files

| File | Change |
|------|--------|
| `Models/AppAppearance.swift` | new file |
| `Views/AppearancePicker.swift` | new file |
| `App/ImageCRCApp.swift` | add `@AppStorage("appAppearance")`, pass into `ContentView` |
| `Views/ContentView.swift` | accept `appearance` binding; `Color.white` → `Color(nsColor: .windowBackgroundColor)`; mount `AppearancePicker` in header; apply `.preferredColorScheme` |
| `Views/AsyncThumbnailView.swift` | `Color.black.opacity(0.08)` → `Color.primary.opacity(0.08)` |

`Package.swift` and `project.yml` do not need updating — `Models/` and `Views/` are already listed as source roots.

## Verification

- Build with `./Scripts/make-app.sh` and launch `./ImageCRC.app`.
- With system theme = light: app looks unchanged from today.
- With system theme = dark, appearance = System: window, text, drop zone, file list, settings panel, completion sheet all render legibly.
- Toggle through Light / Dark while the system is in the opposite theme — the app follows the override, system setting is unaffected.
- Quit and relaunch — the selected appearance persists.
- Progress overlay remains a dark scrim in both themes.
- Selected format chip text stays white on accent fill in both themes.
