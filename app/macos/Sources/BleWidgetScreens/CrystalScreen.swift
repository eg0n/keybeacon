// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

/// The Crystal screen (eg0n/prospector-zmk-module, layouts/crystal, from zmk-dongle-screen) at
/// 280×240: WPM top left, output top right, modifiers left, the turning crystal right, batteries
/// bottom left and the layer bottom right, in the firmware's own Pixel Operator and Material fonts.
public final class CrystalScreen: NSView, KeyboardScreen {
    public static let id = "prospector-crystal"
    public static let displayName = "Prospector: Crystal"
    public static let size = NSSize(width: 280, height: 240)

    public var animates = true {
        didSet {
            if !animates { timer.stop() }
        }
    }

    private var state = KeyboardState()
    private let timer = FrameTimer()
    private var frameIndex = 0

    public required init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize { Self.size }

    /// One 16-frame turn takes 4.8 s (CONFIG_PROSPECTOR_CRYSTAL_ANIMATION_MS), always running.
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard animates, window != nil else { return timer.stop() }
        timer.start(every: 4.8 / 16) { [weak self] in
            guard let self else { return false }
            self.frameIndex = (self.frameIndex + 1) % Self.frames.count
            self.setNeedsDisplay(Self.crystalRect)
            return true
        }
    }

    public func render(_ state: KeyboardState) {
        self.state = state
        needsDisplay = true
    }

    // MARK: - Drawing

    private enum Colors {
        static let dim = NSColor(hex: 0x202020)
        static let green = NSColor(hex: 0x00CC80)
        static let yellow = NSColor(hex: 0xCCCC80)
        static let magenta = NSColor(hex: 0xCC0080)
    }

    private static let text = LVGLFont.pixelOperatorMono32
    private static let icons = LVGLFont.material32

    /// The 69×69 canvas right-centred 35 in and raised 15.
    private static let crystalRect = NSRect(x: 176, y: 70, width: 69, height: 69)

    private static let frames: [NSImage] = CrystalFrames.base64.compactMap { encoded in
        guard let bits = Data(base64Encoded: encoded) else { return nil }
        let (w, h) = (CrystalFrames.width, CrystalFrames.height)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: w * 4, bitsPerPixel: 32),
            let pixels = rep.bitmapData
        else { return nil }
        // Inverted, the default: set bits are white on black.
        for y in 0..<h {
            for x in 0..<w {
                let lit = bits[y * CrystalFrames.stride + x / 8] & (0x80 >> (x % 8)) != 0
                let value: UInt8 = lit ? 255 : 0
                let p = pixels + (y * w + x) * 4
                (p[0], p[1], p[2], p[3]) = (value, value, value, 255)
            }
        }
        let image = NSImage(size: NSSize(width: w, height: h))
        image.addRepresentation(rep)
        return image
    }

    public override func draw(_ dirtyRect: NSRect) {
        ScreenDrawing.fill(bounds, radius: 12, .black)
        drawWPM()
        drawConnection()
        drawModifiers()
        drawCrystal()
        drawBatteries()
        drawLayer()
    }

    /// A label in a grid cell: centred across it, from its top, with the screen's letter spacing of
    /// 1. Icons sit 8 lower to make up for the Material font's metrics (lv_font_conv issue 132).
    private func label(_ string: String, _ color: NSColor = .white, in cell: NSRect, icon: Bool = false) {
        let font = icon ? Self.icons : Self.text
        font.draw(string, centredAcross: cell.offsetBy(dx: 0, dy: icon ? 8 : 0), color, letterSpace: 1)
    }

    private static func cell(_ x: CGFloat, _ y: CGFloat, width: CGFloat = 45, height: CGFloat = 30) -> NSRect {
        NSRect(x: x, y: y, width: width, height: height)
    }

    /// wpm.c: two 45×30 cells at (25, 20), a keyboard and the WPM.
    private func drawWPM() {
        label(MaterialIcon.keyboardAlt, in: Self.cell(25, 20), icon: true)
        label(state.connected ? state.wpm.map { "\($0)" } ?? "" : "", in: Self.cell(70, 20))
    }

    /// connection.c: two 45×30 cells top right (25 in): the profile, from 0, then the output; green
    /// when connected, yellow for an unpaired profile, dim otherwise.
    private func drawConnection() {
        let number = Self.cell(165, 20)
        let icon = Self.cell(210, 20)
        switch state.connected ? state.output : nil {
        case .usb:
            label("0", Colors.dim, in: number)
            label(MaterialIcon.usb, Colors.green, in: icon, icon: true)
        case .ble:
            let profile = state.activeProfile ?? 1
            label("\(profile - 1)", in: number)
            if state.openProfiles.contains(profile) {
                label(MaterialIcon.androidWifi3BarQuestion, Colors.yellow, in: icon, icon: true)
            } else if state.hostConnected == true {
                label(MaterialIcon.androidWifi3Bar, Colors.green, in: icon, icon: true)
            } else {
                label(MaterialIcon.androidWifi3BarOff, Colors.dim, in: icon, icon: true)
            }
        default:
            label("-", Colors.dim, in: number)
            label(MaterialIcon.bluetoothDisabled, Colors.dim, in: icon, icon: true)
        }
    }

    /// modifiers.c: a 3×2 grid of 30-square cells at (20, 80), Shift and Control over Option and
    /// Command, with Caps Lock down the third column: green for Caps Word, magenta for Caps Lock.
    private func drawModifiers() {
        let on = state.connected
        func lit(_ active: Bool) -> NSColor { on && active ? .white : Colors.dim }
        func draw(_ icon: String, _ color: NSColor, _ col: CGFloat, _ row: CGFloat) {
            Self.icons.draw(
                icon, centredAcross: Self.cell(20 + col * 30, 80 + row * 30, width: 30), color, letterSpace: 1)
        }
        draw(MaterialIcon.shift, lit(state.shiftActive), 0, 0)
        draw(MaterialIcon.keyboardControlKey, lit(state.controlActive), 1, 0)
        draw(MaterialIcon.keyboardOptionKey, lit(state.optionActive), 0, 1)
        draw(MaterialIcon.keyboardCommandKey, lit(state.commandActive), 1, 1)
        // Spans both rows, 10 lower.
        let caps = on && state.capsWord ? Colors.green : on && state.capsLock ? Colors.magenta : Colors.dim
        draw(MaterialIcon.keyboardCapslock, caps, 2, 10.0 / 30)
    }

    private func drawCrystal() {
        let image = Self.frames[animates ? frameIndex : 0]
        let rect = Self.crystalRect
        let target = NSRect(x: rect.midX - 34, y: rect.minY, width: 68, height: 69)
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// battery.c: a row per half at (20, 160), a battery in eight steps coloured by level (magenta,
    /// yellow, green), then the percent; a dim question mark while unknown or offline.
    private func drawBatteries() {
        for (row, half) in [state.left, state.right].enumerated() {
            let y = 160 + CGFloat(row) * 30
            let level = state.connected && half.online == true ? Int(half.battery ?? 0) : 0
            let (icon, color): (String, NSColor)
            switch level {
            case 0: (icon, color) = (MaterialIcon.batteryAndroidFrameQuestion, Colors.dim)
            case ..<13: (icon, color) = (MaterialIcon.batteryAndroid0, Colors.magenta)
            case ..<25: (icon, color) = (MaterialIcon.batteryAndroidFrame1, Colors.magenta)
            case ..<38: (icon, color) = (MaterialIcon.batteryAndroidFrame2, Colors.yellow)
            case ..<50: (icon, color) = (MaterialIcon.batteryAndroidFrame3, Colors.yellow)
            case ..<63: (icon, color) = (MaterialIcon.batteryAndroidFrame4, Colors.green)
            case ..<75: (icon, color) = (MaterialIcon.batteryAndroidFrame5, Colors.green)
            case ..<88: (icon, color) = (MaterialIcon.batteryAndroidFrame6, Colors.green)
            default: (icon, color) = (MaterialIcon.batteryAndroidFrameFull, Colors.green)
            }
            label(icon, color, in: Self.cell(20, y), icon: true)
            label("\(level)", in: Self.cell(65, y))
        }
    }

    /// layer.c: the layer name, uppercase and cut to ten characters, centred in 120×30 bottom right.
    private func drawLayer() {
        guard state.connected else { return }
        label(String(state.layerName.uppercased().prefix(10)), in: Self.cell(155, 175, width: 120))
    }
}
