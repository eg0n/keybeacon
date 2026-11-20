# KeyBeacon (eg0n fork)

A keyboard reports its live state (layer, mods, links, battery, WPM, …) to a desktop app over
BLE or USB. This fork adds KBP over USB HID, dongle topology, the Activity payload and layer
name lookups (KBP 1.3), pluggable status screens to the macOS app, and an Omarchy (Linux) bar
widget over USB. Firmware side:
`eg0n/zmk-keybeacon`, branch `feat/dongle-usb`.

## Layout

| Path | What |
|------|------|
| `protocol/` | The KeyBeacon Protocol (KBP), English and Chinese halves; `VERSION`, `CHANGELOG.md` |
| `app/macos/` | Swift package: the menu-bar app (`BleWidget`), its core, screens and preview tool |
| `app/macos/scripts/` | `prospector_assets.py`: generates screen assets from a prospector-zmk-module checkout |
| `app/linux/omarchy/` | Omarchy 4 Quickshell bar widget (QML) and its `kbp-hidraw` helper (Python, hidraw); see its README. QML changes need `omarchy restart shell` |
| `app/windows/` | Windows app (C#); not maintained in this fork |
| `conformance/` | Python checklist tool for keyboards (`pytest conformance/tests`) |
| `packaging/make-app.sh` | Builds `dist/BleWidget.app`, `.zip` and `.dmg` (ad-hoc signed) |
| `specs/`, `.specify/` | Upstream design notes; history, not normative |

## macOS app

Data flows one way:

1. `BLEClient` (CoreBluetooth) and `USBHIDClient` (IOKit HID, usage page `0xFFAA`) read the KBP
   payloads. USB takes precedence while attached (`AppDelegate`).
2. Decoders in `BleWidgetCore` turn payloads into values: `KeyboardStatus` (AA1),
   `ConnectivityStatus` (AA2), `BatteryStatus` (AA3), `LinkSlot` (AA4), `ActivityStatus` (AA5),
   `LayerName` (AA6, looked up per layer after connecting).
3. `FloatingPanel` shows them in a display mode: the built-in full card or compact strip, or a
   screen. For screens it folds every update into one `KeyboardState` (`KeyboardStateStore`).

Targets: `BleWidgetCore` (no AppKit, unit-tested), `BleWidgetScreens` (AppKit, the screens),
`BleWidget` (the app), `ScreenPreview` (`swift run screen-preview`).

### Adding a screen

A screen draws the whole panel from a `KeyboardState`, like a keyboard's status display.

1. Add `app/macos/Sources/BleWidgetScreens/<Name>Screen.swift`: a `public final class` that
   subclasses `NSView` and conforms to `KeyboardScreen`. Copy `OperatorScreen.swift`'s shape.
2. Give it a stable `id` (it is stored as the user's display mode), a `displayName` (shown in the
   menu) and a fixed `size` in points.
3. In `render(_:)`, store the state and set `needsDisplay`; draw in `draw(_:)`. Return `true`
   from `isFlipped` to work in y-down coordinates, as LVGL does.
4. Animate only while `animates` is true; when false (previews), jump to the end state.
5. Fields the keyboard didn't report are `nil` or empty: leave them out rather than inventing
   values. When `connected` is false, draw a disconnected face.
6. Use `ScreenDrawing` for text, fills, outlines and LVGL-style arcs, and `NSColor(hex:)` for
   firmware colours.
7. Add the type to `ScreenRegistry.all`; the Display Mode menu picks it up.
8. A screen in system colours sets `previewAppearances` to `[.aqua, .darkAqua]` for light and dark
   previews. Window-server materials (glass, vibrancy) don't render offscreen: draw a stand-in
   while `animates` is false, as `GlassScreen` does.
9. Check it: `swift run screen-preview <id> /tmp/out` renders it in sample states (typing, Caps
   Lock, a half offline, disconnected) to PNGs; look at them.

Porting a Prospector layout (carrefinho/prospector-zmk-module, `layouts/<name>`): take positions,
sizes and colours from its widgets and `display_colors.h`. Prospector builds run LVGL without a
theme, so containers have no padding and rollers no extra line spacing. Shared pieces live in
`ProspectorShared.swift` (modifier symbols, the waves-and-profile badge); `Tween` and `FrameTimer`
in `ScreenDrawing.swift` drive animations.

Draw text with the firmware's own fonts so screens match the dongle: add the LVGL font file to
`FONTS` in `scripts/prospector_assets.py`, run it (`python3 scripts/prospector_assets.py
<prospector-zmk-module> <lvgl>`; LVGL is `modules/lib/gui/lvgl` in a Zephyr workspace), and draw
with `LVGLFont`, which places glyphs as LVGL labels do (top-aligned, kerned, whole-pixel advances).
Symbol glyphs are in `ProspectorSymbol` and `MaterialIcon`. The script also regenerates
`CrystalFrames.swift`; don't edit its outputs.

### Adding a data field

1. Protocol first: a MINOR change appends bytes or adds an optional characteristic (§9). Write it
   up in both halves of `protocol/README.md`, bump `protocol/VERSION`, add both changelogs.
   `protocol/` must stay self-contained: no paths into the app or firmware.
2. Firmware: `zmk-keybeacon` builds and notifies the payload, on BLE and in `keybeacon_usb.c`.
3. App: parse it in a `BleWidgetCore` type (reject short payloads, ignore unknown tails), carry
   it through both clients, add it to `KeyboardState` and `KeyboardStateStore`, and test it.

## Conventions

- Format with `swift format --in-place --recursive Sources Tests Package.swift` (config in
  `app/macos/.swift-format`); `swift format lint` must be clean. Python: `ruff format`, `ruff check`.
- Block comments stay within about four lines; license headers and wire-format explanations are
  exempt. Say what the code does and why, without spec-tracking IDs.
- XCTest needs Xcode. Without it, `swift build` still works and CI (`.github/workflows/ci.yml`)
  runs `swift test`. Keep logic in `BleWidgetCore` so it stays testable.
- Build the app with `packaging/make-app.sh [version]`; it ad-hoc signs, so first launch needs
  right-click → Open.
