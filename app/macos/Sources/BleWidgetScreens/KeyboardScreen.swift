// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

/// A display mode that draws the whole panel itself, like a keyboard's status screen. To add one,
/// write a `KeyboardScreen` and list it in `ScreenRegistry.all`; see CLAUDE.md.
public protocol KeyboardScreen: NSView {
    /// Stable and unique: it is stored as the chosen display mode.
    static var id: String { get }
    /// The name in the Display Mode menu.
    static var displayName: String { get }
    /// The panel's size, in points, while this screen shows.
    static var size: NSSize { get }

    init()

    /// Called with the latest state whenever anything changes; redraw from it.
    func render(_ state: KeyboardState)

    /// Show changes at once instead of animating them, for previews.
    var animates: Bool { get set }

    /// The appearances `screen-preview` renders it in; a screen in system colours lists both.
    static var previewAppearances: [NSAppearance.Name] { get }
}

extension KeyboardScreen {
    public static var previewAppearances: [NSAppearance.Name] { [.darkAqua] }
}

public enum ScreenRegistry {
    /// Every screen, in Display Mode menu order.
    public static let all: [KeyboardScreen.Type] = [
        OperatorScreen.self,
        ClassicScreen.self,
        RadiiScreen.self,
        FieldScreen.self,
        CrystalScreen.self,
        GlassScreen.self,
    ]

    public static func screen(id: String) -> KeyboardScreen.Type? {
        all.first { $0.id == id }
    }
}
