# Resize — Settings Section and Processing Pipeline

**Status:** Approved · **Date:** 2026-04-18

## 1. Purpose

Add an optional resize step to the conversion pipeline and expose it in the Settings panel as a new section "Resize", placed between "Quality" and "Output format".

## 2. Parameters

| Param | Type | Default | Notes |
|---|---|---|---|
| `mode` | `fit \| fill` | `fit` | `fit` = preserve aspect, image fits inside W×H; `fill` = preserve aspect, image covers W×H with centered crop |
| `width` | `Int?` (≥1) | `nil` | Pixels. `nil` = auto from aspect ratio |
| `height` | `Int?` (≥1) | `nil` | Pixels. `nil` = auto from aspect ratio |
| `enlarge` | `Bool` | `false` | If `false`, never upscale beyond source |

**Off state:** resize is inactive iff both `width` and `height` are `nil`. No explicit toggle.

## 3. Algorithm

Inputs: source `W_s × H_s`, `mode`, `W_t`, `H_t`, `enlarge`.

1. If `width == nil && height == nil` → return source image unchanged (pipeline skips resize).
2. Compute scale:
   - **Both dims given:** `s_x = W_t/W_s`, `s_y = H_t/H_s`.
     - `fit` → `scale = min(s_x, s_y)` (no crop).
     - `fill` → `scale = max(s_x, s_y)` (crop overflow after scaling).
   - **Only one dim given:** `scale = W_t/W_s` or `H_t/H_s`. `mode` is irrelevant (no bounding box → no crop).
3. If `enlarge == false` → `scale = min(scale, 1.0)`.
4. Intermediate size `W_i × H_i = round(W_s * scale) × round(H_s * scale)`, each clamped to ≥1.
5. Output size:
   - `fit` or single-dim case → `W_i × H_i`.
   - `fill` with both dims → `min(W_i, W_t) × min(H_i, H_t)`, centered crop from the scaled image.
     - Edge: when `enlarge=false` and `W_i < W_t` or `H_i < H_t`, output is smaller than `W_t × H_t` — best-effort, no upscale.

## 4. Color Space / Bit Depth

Resize passes the image through `CGContext.draw(...)`.

- **Color space:** preserve source's color space if it is RGB-based (e.g., sRGB, Display P3). Fall back to sRGB for CMYK/Gray/unknown.
- **Bit depth:** always 8-bit per component, RGBA premultiplied. Downstream encoders (JPEG/WebP/AVIF, pngquant PNG) are effectively 8-bit so no extra fidelity is lost vs. the current pipeline.
- **Interpolation:** `.high`.

When resize is inactive the pipeline is unchanged — no `CGContext` pass, no normalization.

## 5. Integration

**Model** (`Models/ResizeSettings.swift`, new):

```swift
struct ResizeSettings: Hashable, Sendable {
    enum Mode: String, Hashable, Sendable, CaseIterable, Identifiable {
        case fit, fill
        var id: String { rawValue }
        var displayName: String { self == .fit ? "Fit" : "Fill" }
    }
    var mode: Mode = .fit
    var width: Int? = nil
    var height: Int? = nil
    var enlarge: Bool = false

    var isActive: Bool { width != nil || height != nil }
}
```

`ConversionSettings` gains `var resize: ResizeSettings = .init()`.

**Service** (`Services/ImageResizer.swift`, new):

```swift
enum ImageResizer {
    static func resize(_ image: CGImage, settings: ResizeSettings) -> CGImage
}
```

Pure synchronous function. Returns the input image unchanged when `!settings.isActive` or when `CGContext` creation fails.

**Pipeline** (`Services/ImageConverter.swift`): `run(...)` extracts a `resize` snapshot and passes it to `processOne`, which calls `ImageResizer.resize(decoded, settings: resize)` between decode and encode. `Task.isCancelled` checks stay at existing boundaries.

## 6. UI

`Views/SettingsPanelView.swift` gets a new section between "Quality" and "Output format":

- Title: `Label("Resize", systemImage: "aspectratio")`
- Segmented picker: `Fit` | `Fill`
- Row: two `TextField`s side-by-side — "Width" and "Height", placeholder `auto`, numeric-only input, suffix `px`
- Row: `Toggle("Allow enlargement", isOn: $settings.resize.enlarge)`

Empty string in a dimension field → `nil` in the model. Non-numeric input is filtered. Values `< 1` are rejected (kept at previous valid value or `nil`).

## 7. Out of Scope

- Per-section on/off toggles for Quality/Resize (will be added as a separate UX pass covering the whole panel).
- DPI-aware resize, percentage mode, `contain`/`stretch` modes.
- Preserving 16-bit color depth end-to-end.
- Automated tests (no test target is currently wired up; verification is manual via the running app).
