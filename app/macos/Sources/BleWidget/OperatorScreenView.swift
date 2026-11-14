// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

/// The Prospector dongle's "Operator" status screen (carrefinho/prospector-zmk-module,
/// layouts/operator), redrawn at its 280×240 resolution from KBP data: the modifier row, a
/// 26-bar WPM meter with the WPM and layer name cut into it, one segment per layer, a battery
/// ring per half, and the output and profile slots. Positions, colours and the WPM easing are
/// the firmware's; its fonts (Foundry Gridnik, FRAC, DINish) are stood in for by SF.
final class OperatorScreenView: NSView {
    static let screenSize = NSSize(width: 280, height: 240)

    override var isFlipped: Bool { true }

    // MARK: - State

    private var connected = false
    private var layerIndex = 0
    private var layerName = ""
    private var mods: [Bool] = [false, false, false, false] // CMD OPT CTRL SHFT
    private var layerCount = 0
    private var capsWord = false
    private var capsLock = false
    private var halves: [(online: Bool, level: Int?)] = [(false, nil), (false, nil)]
    private var outputIsUSB: Bool?
    private var profileIndex = 0 // 1-based; 0 = unknown
    private var profileCount = 0
    private var activeProfileOpen = false
    private var openProfiles: UInt8? // bit n = profile n+1 has no bonded host

    // WPM meter, as in wpm_meter.c: ease towards the target every 33 ms, a peak that holds for
    // 90 frames, then drops a bar every 18.
    private static let barCount = 26
    private static let wpmMax = 120.0
    private var targetWPM = 0.0
    private var displayedWPM = 0.0
    private var peak = 0
    private var peakHold = 0
    private var peakDecay = 0
    private var meterTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    deinit {
        meterTimer?.invalidate()
    }

    override var intrinsicContentSize: NSSize { Self.screenSize }

    // MARK: - Updates

    func update(status: KeyboardStatus) {
        connected = status.connected
        layerIndex = Int(status.layerIndex)
        layerName = status.connected ? status.layerName.uppercased() : ""
        mods = [status.commandActive, status.optionActive, status.controlActive, status.shiftActive]
        if !status.connected {
            halves = [(false, nil), (false, nil)]
            outputIsUSB = nil
            setWPM(0)
        }
        needsDisplay = true
    }

    func update(connectivity: ConnectivityStatus) {
        let capability = connectivity.capability
        if capability.isSplit, capability.hasSplitLink {
            halves[0].online = connectivity.splitFlags.leftOnline
            halves[1].online = connectivity.splitFlags.rightOnline
        }
        if capability.hasOutputEndpoint {
            switch connectivity.output {
            case .usb: outputIsUSB = true
            case .ble: outputIsUSB = false
            default: outputIsUSB = nil
            }
        }
        if capability.hasProfile {
            profileIndex = Int(connectivity.profile.index)
            profileCount = Int(connectivity.profile.maxSlots)
            activeProfileOpen = connectivity.profile.isOpen
            openProfiles = connectivity.openProfiles
        }
        needsDisplay = true
    }

    func update(battery: BatteryStatus) {
        func level(_ reading: BatteryStatus.BatteryReading) -> Int? {
            if case .percent(let value) = reading { return Int(value) }
            return nil
        }
        switch battery.kind {
        case .split(let left, let right):
            halves[0].level = level(left)
            halves[1].level = level(right)
        case .overall(let reading):
            halves[0].level = level(reading)
        }
        needsDisplay = true
    }

    func update(activity: ActivityStatus) {
        layerCount = Int(activity.layerCount)
        capsWord = activity.capsWord
        capsLock = activity.capsLock
        setWPM(Double(activity.wpm ?? 0))
        needsDisplay = true
    }

    private func setWPM(_ wpm: Double) {
        targetWPM = wpm
        if meterTimer == nil {
            meterTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
                self?.stepMeter()
            }
        }
    }

    private var activeBars: Int {
        let bars = Int(displayedWPM + 0.5) * Self.barCount / Int(Self.wpmMax)
        return min(bars, Self.barCount)
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
        static let layerText = NSColor.white
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

    private enum Fonts {
        /// Foundry Gridnik Medium 20.
        static let gridnik = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        /// FRAC Medium 32.
        static let frac = NSFont.monospacedDigitSystemFont(ofSize: 30, weight: .medium)
        /// DINish Expanded Light 36.
        static let dinishExpandedLight: NSFont = {
            if #available(macOS 13.0, *) {
                return .systemFont(ofSize: 29, weight: .light, width: .expanded)
            }
            return .systemFont(ofSize: 30, weight: .light)
        }()
        /// DINish Medium 24.
        static let dinishMedium = NSFont.monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12).fill()
        drawModifiers()
        drawWPMMeter()
        drawLayerSegments()
        drawBatteries()
        drawOutput()
    }

    /// modifier_indicator.c: four labels and three 2×24 separators spread across 230×24 at (25, 8).
    /// SHFT is amber during Caps Word, as on the dongle, and red while the host's Caps Lock is on.
    private func drawModifiers() {
        let frame = NSRect(x: 25, y: 8, width: 230, height: 24)
        let titles = ["CMD", "OPT", "CTRL", "SHFT"]
        let widths = titles.map { text($0, Fonts.gridnik, .white).size().width }
        let gap = (frame.width - widths.reduce(0, +) - 3 * 2) / 6
        var x = frame.minX
        for (i, title) in titles.enumerated() {
            var color = mods[i] ? Palette.modActive : Palette.modInactive
            if i == 3, capsLock {
                color = Palette.modCapsLock
            } else if i == 3, capsWord {
                color = Palette.modCapsWord
            }
            let label = text(title, Fonts.gridnik, color)
            label.draw(at: NSPoint(x: x, y: frame.midY - label.size().height / 2))
            x += widths[i] + gap
            if i < 3 {
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
            (i < bars ? Palette.wpmBarActive : Palette.wpmBarInactive).setFill()
            NSBezierPath(roundedRect: NSRect(x: startX + CGFloat(i) * 10, y: meter.minY, width: 8, height: meter.height),
                         xRadius: 1, yRadius: 1).fill()
        }
        if peak > bars, peak > 0 {
            let slot = min(peak > bars + 1 ? peak - 1 : bars, Self.barCount - 1)
            Palette.wpmPeak.setFill()
            NSBezierPath(roundedRect: NSRect(x: startX + CGFloat(slot) * 10 + 2, y: meter.minY, width: 4, height: meter.height),
                         xRadius: 1, yRadius: 1).fill()
        }

        // The WPM, padded 6×4 on black, aligned top-left with a (-7, -9) offset.
        let wpm = text("\(Int(displayedWPM + 0.5))", Fonts.frac, Palette.wpmBarActive)
        let wpmSize = wpm.size()
        let wpmBox = NSRect(x: meter.minX - 7, y: meter.minY - 9, width: wpmSize.width + 12, height: wpmSize.height + 8)
        NSColor.black.setFill()
        wpmBox.fill()
        wpm.draw(at: NSPoint(x: wpmBox.minX + 6, y: wpmBox.minY + 4))

        // The layer name, padded 8 / 7 top / 3 bottom on black, bottom-right with a (9, 7) offset.
        guard !layerName.isEmpty else { return }
        let name = text(layerName, Fonts.dinishExpandedLight, Palette.layerText)
        let nameSize = name.size()
        let nameBox = NSRect(x: meter.maxX + 9 - nameSize.width - 16, y: meter.maxY + 7 - nameSize.height - 10,
                             width: nameSize.width + 16, height: nameSize.height + 10)
        NSColor.black.setFill()
        nameBox.fill()
        name.draw(at: NSPoint(x: nameBox.minX + 8, y: nameBox.minY + 7))
    }

    /// layer_display.c: one 6-high segment per layer across 260 at (10, 142), 3 between.
    private func drawLayerSegments() {
        let count = layerCount > 0 ? layerCount : 0
        guard count > 0 else { return }
        let width = (260 - CGFloat(count - 1) * 3) / CGFloat(count)
        for i in 0..<count {
            (connected && i == layerIndex ? Palette.layerDotActive : Palette.layerDotInactive).setFill()
            NSBezierPath(roundedRect: NSRect(x: 10 + CGFloat(i) * (width + 3), y: 142, width: width, height: 6),
                         xRadius: 2, yRadius: 2).fill()
        }
    }

    /// battery_circles.c, two peripherals: 58×58 rings 66 apart at (11, 172), open over the top-left
    /// quadrant where the level sits in a 25×25 box. 6 wide when the half is online, 2 when not.
    private func drawBatteries() {
        for (i, half) in halves.enumerated() {
            let origin = NSPoint(x: 11 + CGFloat(i) * 66, y: 172)
            let level = half.level ?? 0
            let low = half.online && half.level != nil && level < 20
            let ring = low ? Palette.batteryLowRing : (half.online ? Palette.batteryRing : Palette.batteryOffRing)
            let fill = low ? Palette.batteryLowFill : (half.online ? Palette.batteryFill : Palette.batteryOffFill)
            let width: CGFloat = half.online ? 6 : 2
            let center = NSPoint(x: origin.x + 29, y: origin.y + 29)
            let radius = 29 - width / 2

            // LVGL angles run clockwise from 3 o'clock, as do these in a flipped view.
            strokeArc(center: center, radius: radius, from: 270, sweep: 270, width: width, color: ring)
            if half.online, level > 0 {
                strokeArc(center: center, radius: radius, from: 270, sweep: 270 * CGFloat(min(level, 100)) / 100,
                          width: width, color: fill)
            }

            let box = NSRect(x: origin.x, y: origin.y, width: 25, height: 25)
            fill.setFill()
            NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2).fill()
            let label = text(half.online && level > 0 ? "\(level)" : "-", Fonts.dinishMedium, .black, kern: -1)
            let size = label.size()
            label.draw(at: NSPoint(x: box.midX - size.width / 2, y: box.midY - size.height / 2))
        }
    }

    private func strokeArc(center: NSPoint, radius: CGFloat, from start: CGFloat, sweep: CGFloat,
                           width: CGFloat, color: NSColor) {
        guard sweep > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let toRadians = CGFloat.pi / 180
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.addArc(center: center, radius: radius, startAngle: start * toRadians,
                       endAngle: (start + sweep) * toRadians, clockwise: false)
        context.strokePath()
        context.restoreGState()
    }

    /// output.c: USB and BLE toggles 56×29 at (148, 170), filled when active and outlined when not,
    /// over one 29-high slot per BLE profile, the active profile's lit. A profile with no host
    /// bonded is an outline instead, in the active colour while it waits to pair.
    private func drawOutput() {
        drawToggle("USB", rect: NSRect(x: 148, y: 170, width: 56, height: 29), active: outputIsUSB == true,
                   on: Palette.usbActive, off: Palette.usbInactive)
        drawToggle("BLE", rect: NSRect(x: 206, y: 170, width: 56, height: 29), active: outputIsUSB == false,
                   on: Palette.bleActive, off: Palette.bleInactive)

        guard profileCount > 0 else { return }
        let width = (116 - CGFloat(profileCount - 1) * 2) / CGFloat(profileCount)
        for i in 0..<profileCount {
            let rect = NSRect(x: 148 + CGFloat(i) * (width + 2), y: 203, width: width, height: 29)
            let active = i + 1 == profileIndex
            let open = (openProfiles.map { $0 & (1 << i) != 0 } ?? false) || (active && activeProfileOpen)
            let textColor: NSColor
            if open {
                let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
                outline.lineWidth = 2
                textColor = active ? Palette.slotActive : Palette.slotEmpty
                textColor.setStroke()
                outline.stroke()
            } else {
                (active ? Palette.slotActive : Palette.slotInactive).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
                textColor = .black
            }
            if profileCount <= 5 {
                let label = text("\(i + 1)", Fonts.gridnik, textColor)
                let size = label.size()
                label.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            }
        }
    }

    private func drawToggle(_ title: String, rect: NSRect, active: Bool, on: NSColor, off: NSColor) {
        let label = text(title, Fonts.gridnik, active ? .black : off)
        if active {
            on.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        } else {
            let outline = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
            outline.lineWidth = 2
            off.setStroke()
            outline.stroke()
        }
        let size = label.size()
        label.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    private func text(_ string: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
