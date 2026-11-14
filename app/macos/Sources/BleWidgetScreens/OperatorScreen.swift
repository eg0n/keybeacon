// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

/// The Prospector dongle's Operator screen (carrefinho/prospector-zmk-module, layouts/operator) at
/// its 280×240 size: modifiers, a 26-bar WPM meter, layer segments, a battery ring per half, output
/// and profiles. Positions, colours, fonts and WPM easing are the firmware's.
public final class OperatorScreen: NSView, KeyboardScreen {
    public static let id = "prospector-operator"
    public static let displayName = "Prospector: Operator"
    public static let size = NSSize(width: 280, height: 240)

    public var animates = true

    private var state = KeyboardState()

    // WPM meter, as in wpm_meter.c: ease towards the target every 33 ms, a peak that holds for
    // 90 frames, then drops a bar every 18.
    private static let barCount = 26
    private static let wpmMax = 120.0
    private var displayedWPM = 0.0
    private var peak = 0
    private var peakHold = 0
    private var peakDecay = 0
    private var meterTimer: Timer?

    public required init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        meterTimer?.invalidate()
    }

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize { Self.size }

    public func render(_ state: KeyboardState) {
        self.state = state
        if animates {
            if meterTimer == nil, abs(targetWPM - displayedWPM) >= 0.5 || peak > activeBars {
                meterTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
                    self?.stepMeter()
                }
            }
        } else {
            displayedWPM = targetWPM
            peak = activeBars
        }
        needsDisplay = true
    }

    private var targetWPM: Double { state.connected ? Double(state.wpm ?? 0) : 0 }

    private var activeBars: Int {
        min(Int(displayedWPM + 0.5) * Self.barCount / Int(Self.wpmMax), Self.barCount)
    }

    private func stepMeter() {
        let diff = targetWPM - displayedWPM
        let atTarget = abs(diff) < 0.5
        displayedWPM = atTarget ? targetWPM : displayedWPM + diff * (diff > 0 ? 0.3 : 0.05)

        let bars = activeBars
        if bars > peak {
            peak = bars
            peakHold = 0
            peakDecay = 0
        } else if peak > bars {
            if peakHold < 90 {
                peakHold += 1
            } else {
                peakDecay += 1
                if peakDecay >= 18 {
                    peak -= 1
                    peakDecay = 0
                }
            }
        }
        needsDisplay = true
        if atTarget && peak <= bars {
            meterTimer?.invalidate()
            meterTimer = nil
        }
    }

    // MARK: - Drawing

    private enum Palette {
        static let modActive = NSColor(hex: 0xB1E5F0)
        static let modInactive = NSColor(hex: 0x3B527C)
        static let modSeparator = NSColor(hex: 0x606060)
        static let modCapsWord = NSColor(hex: 0xFFBF00)
        static let modCapsLock = NSColor(hex: 0xE5484D)
        static let wpmBarActive = NSColor(hex: 0xC2526A)
        static let wpmBarInactive = NSColor(hex: 0x242424)
        static let wpmPeak = NSColor(hex: 0x505050)
        static let layerDotActive = NSColor(hex: 0xE0E0E0)
        static let layerDotInactive = NSColor(hex: 0x575757)
        static let batteryFill = NSColor(hex: 0x54806C)
        static let batteryRing = NSColor(hex: 0x2A4036)
        static let batteryLowFill = NSColor(hex: 0xC08040)
        static let batteryLowRing = NSColor(hex: 0x584028)
        static let batteryOffFill = NSColor(hex: 0x383C42)
        static let batteryOffRing = NSColor(hex: 0x282C30)
        static let usbActive = NSColor(hex: 0xB9B9A7)
        static let usbInactive = NSColor(hex: 0x4F4F40)
        static let bleActive = NSColor(hex: 0x569FA7)
        static let bleInactive = NSColor(hex: 0x353F40)
        static let slotActive = NSColor(hex: 0x7B7D93)
        static let slotInactive = NSColor(hex: 0x353640)
        static let slotEmpty = NSColor(hex: 0x4A4C58)
    }

    public override func draw(_ dirtyRect: NSRect) {
        ScreenDrawing.fill(bounds, radius: 12, .black)
        drawModifiers()
        drawWPMMeter()
        drawLayerSegments()
        drawBatteries()
        drawOutput()
    }

    /// modifier_indicator.c: four Gridnik 20 labels and three 2×24 separators spread across 230×24
    /// at (25, 8).
    /// SHFT is amber during Caps Word, as on the dongle, and red while the host's Caps Lock is on.
    private func drawModifiers() {
        let frame = NSRect(x: 25, y: 8, width: 230, height: 24)
        let mods: [(String, Bool)] = [
            ("CMD", state.commandActive), ("OPT", state.optionActive), ("CTRL", state.controlActive),
            ("SHFT", state.shiftActive),
        ]
        let font = LVGLFont.gridnikMedium20
        let widths = mods.map { font.width($0.0) }
        let gap = (frame.width - widths.reduce(0, +) - 3 * 2) / 6
        var x = frame.minX
        for (i, (title, held)) in mods.enumerated() {
            var color = held ? Palette.modActive : Palette.modInactive
            if title == "SHFT", state.capsLock {
                color = Palette.modCapsLock
            } else if title == "SHFT", state.capsWord {
                color = Palette.modCapsWord
            }
            let y = frame.minY + ((frame.height - font.lineHeight) / 2).rounded(.towardZero)
            font.draw(title, at: NSPoint(x: x, y: y), color)
            x += widths[i] + gap
            if i < mods.count - 1 {
                Palette.modSeparator.setFill()
                NSRect(x: x, y: frame.minY, width: 2, height: frame.height).fill()
                x += 2 + gap
            }
        }
    }

    /// wpm_meter.c: 26 bars, 8 wide with 2 between, centred in 260×90 at (10, 42), the WPM cut
    /// into the top left and the layer name into the bottom right.
    private func drawWPMMeter() {
        let meter = NSRect(x: 10, y: 42, width: 260, height: 90)
        let totalWidth = CGFloat(Self.barCount * 8 + (Self.barCount - 1) * 2)
        let startX = meter.minX + (meter.width - totalWidth) / 2
        let bars = activeBars
        for i in 0..<Self.barCount {
            let bar = NSRect(x: startX + CGFloat(i) * 10, y: meter.minY, width: 8, height: meter.height)
            ScreenDrawing.fill(bar, radius: 1, i < bars ? Palette.wpmBarActive : Palette.wpmBarInactive)
        }
        if peak > bars, peak > 0 {
            let slot = min(peak > bars + 1 ? peak - 1 : bars, Self.barCount - 1)
            let marker = NSRect(x: startX + CGFloat(slot) * 10 + 2, y: meter.minY, width: 4, height: meter.height)
            ScreenDrawing.fill(marker, radius: 1, Palette.wpmPeak)
        }

        // The WPM in FRAC Medium 32, padded 6×4 on black, aligned top-left with a (-7, -9) offset.
        let wpm = "\(Int(displayedWPM + 0.5))"
        let wpmFont = LVGLFont.fracMedium32
        let wpmSize = wpmFont.size(wpm)
        let wpmBox = NSRect(
            x: meter.minX - 7, y: meter.minY - 9, width: wpmSize.width + 12, height: wpmSize.height + 8)
        NSColor.black.setFill()
        wpmBox.fill()
        wpmFont.draw(wpm, at: NSPoint(x: wpmBox.minX + 6, y: wpmBox.minY + 4), Palette.wpmBarActive)

        // The layer name in DINish Expanded Light 36, padded 8 / 7 top / 3 bottom on black,
        // bottom-right with a (9, 7) offset.
        guard state.connected, !state.layerName.isEmpty else { return }
        let name = state.layerName.uppercased()
        let nameFont = LVGLFont.dinishExpandedLight36
        let nameSize = nameFont.size(name)
        let nameBox = NSRect(
            x: meter.maxX + 9 - nameSize.width - 16, y: meter.maxY + 7 - nameSize.height - 10,
            width: nameSize.width + 16, height: nameSize.height + 10)
        NSColor.black.setFill()
        nameBox.fill()
        nameFont.draw(name, at: NSPoint(x: nameBox.minX + 8, y: nameBox.minY + 7), .white)
    }

    /// layer_display.c: one 6-high segment per layer across 260 at (10, 142), 3 between.
    private func drawLayerSegments() {
        guard let count = state.layerCount.map(Int.init), count > 0 else { return }
        let width = (260 - CGFloat(count - 1) * 3) / CGFloat(count)
        for i in 0..<count {
            let active = state.connected && i == Int(state.layerIndex)
            let segment = NSRect(x: 10 + CGFloat(i) * (width + 3), y: 142, width: width, height: 6)
            ScreenDrawing.fill(segment, radius: 2, active ? Palette.layerDotActive : Palette.layerDotInactive)
        }
    }

    /// battery_circles.c, two peripherals: 58×58 rings 66 apart at (11, 172), open over the top-left
    /// quadrant where the level sits in a 25×25 box. 6 wide when the half is online, 2 when not.
    private func drawBatteries() {
        for (i, half) in [state.left, state.right].enumerated() {
            let online = state.connected && half.online == true
            let level = Int(half.battery ?? 0)
            let low = online && half.battery != nil && level < 20
            let ring = low ? Palette.batteryLowRing : (online ? Palette.batteryRing : Palette.batteryOffRing)
            let fill = low ? Palette.batteryLowFill : (online ? Palette.batteryFill : Palette.batteryOffFill)
            let width: CGFloat = online ? 6 : 2
            let origin = NSPoint(x: 11 + CGFloat(i) * 66, y: 172)
            let center = NSPoint(x: origin.x + 29, y: origin.y + 29)

            ScreenDrawing.arc(center: center, radius: 29 - width / 2, from: 270, sweep: 270, width: width, ring)
            if online, level > 0 {
                let sweep = 270 * CGFloat(min(level, 100)) / 100
                ScreenDrawing.arc(center: center, radius: 29 - width / 2, from: 270, sweep: sweep, width: width, fill)
            }

            let box = NSRect(x: origin.x, y: origin.y, width: 25, height: 25)
            ScreenDrawing.fill(box, radius: 2, fill)
            LVGLFont.dinishMedium24.draw(
                online && level > 0 ? "\(level)" : "-", centredIn: box, .black, letterSpace: -1)
        }
    }

    /// output.c: USB and BLE toggles 56×29 at (148, 170), filled when active and outlined when not,
    /// over one 29-high slot per BLE profile, the active one lit. An unpaired profile is an outline,
    /// in the active colour while it waits to pair.
    private func drawOutput() {
        let output = state.connected ? state.output : nil
        drawToggle(
            "USB", NSRect(x: 148, y: 170, width: 56, height: 29), output == .usb, Palette.usbActive,
            Palette.usbInactive)
        drawToggle(
            "BLE", NSRect(x: 206, y: 170, width: 56, height: 29), output == .ble, Palette.bleActive,
            Palette.bleInactive)

        let count = state.profileCount
        guard state.connected, count > 0 else { return }
        let width = (116 - CGFloat(count - 1) * 2) / CGFloat(count)
        for i in 0..<count {
            let slot = NSRect(x: 148 + CGFloat(i) * (width + 2), y: 203, width: width, height: 29)
            let active = i + 1 == state.activeProfile
            let textColor: NSColor
            if state.openProfiles.contains(i + 1) {
                textColor = active ? Palette.slotActive : Palette.slotEmpty
                ScreenDrawing.outline(slot, radius: 6, width: 2, textColor)
            } else {
                ScreenDrawing.fill(slot, radius: 6, active ? Palette.slotActive : Palette.slotInactive)
                textColor = .black
            }
            if count <= 5 {
                LVGLFont.gridnikMedium20.draw("\(i + 1)", centredIn: slot, textColor)
            }
        }
    }

    private func drawToggle(_ title: String, _ rect: NSRect, _ active: Bool, _ on: NSColor, _ off: NSColor) {
        if active {
            ScreenDrawing.fill(rect, radius: 6, on)
        } else {
            ScreenDrawing.outline(rect, radius: 6, width: 2, off)
        }
        LVGLFont.gridnikMedium20.draw(title, centredIn: rect, active ? .black : off)
    }
}
