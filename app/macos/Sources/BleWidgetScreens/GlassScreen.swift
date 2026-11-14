// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

/// A macOS-style widget: everything the Prospector screens show, on Liquid Glass (a vibrant
/// material before macOS 26) in system fonts, symbols and colours, light or dark with the system.
/// The layer and its place among the layers, held modifiers and Caps Word / Caps Lock, typing
/// speed with its recent history, each half's battery and link, the output, host and profiles.
public final class GlassScreen: NSView, KeyboardScreen {
    public static let id = "glass"
    public static let displayName = "Glass Widget"
    public static let size = NSSize(width: 344, height: 204)
    public static let previewAppearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    public var animates = true {
        didSet { buildHierarchy() }
    }

    private let face = GlassFace(frame: NSRect(origin: .zero, size: GlassScreen.size))
    private var background: NSView?
    private let sampler = FrameTimer()
    private var state = KeyboardState()

    public required init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        buildHierarchy()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var intrinsicContentSize: NSSize { Self.size }

    /// Glass behind the face in the app; previews, which can't capture window-server materials,
    /// get the face alone, drawing a stand-in.
    private func buildHierarchy() {
        background?.removeFromSuperview()
        face.removeFromSuperview()
        background = nil
        face.simulatesGlass = !animates
        face.autoresizingMask = [.width, .height]
        guard animates else {
            face.frame = bounds
            addSubview(face)
            return
        }
        let glass: NSView
        if #available(macOS 26.0, *) {
            let view = NSGlassEffectView(frame: bounds)
            view.cornerRadius = GlassFace.cornerRadius
            view.contentView = face
            glass = view
        } else {
            let view = NSVisualEffectView(frame: bounds)
            view.material = .popover
            view.blendingMode = .behindWindow
            view.state = .active
            view.wantsLayer = true
            view.layer?.cornerRadius = GlassFace.cornerRadius
            view.layer?.masksToBounds = true
            face.frame = view.bounds
            view.addSubview(face)
            glass = view
        }
        glass.autoresizingMask = [.width, .height]
        addSubview(glass)
        background = glass
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard animates, window != nil else { return sampler.stop() }
        // One WPM sample a second for the sparkline, 40 seconds' worth.
        sampler.start(every: 1) { [weak self] in
            guard let self else { return false }
            self.face.history.append(self.state.connected ? Double(self.state.wpm ?? 0) : 0)
            self.face.history = Array(self.face.history.suffix(40))
            self.face.needsDisplay = true
            return true
        }
    }

    public func render(_ state: KeyboardState) {
        self.state = state
        face.state = state
        if !animates {
            // A plausible last 40 seconds ending at the current speed.
            let wpm = Double(state.wpm ?? 0)
            face.history = (0..<40).map { i in
                let t = Double(i)
                return wpm * min(1, t / 12) * (0.7 + 0.3 * sin(t * 0.5)) + (i == 39 ? wpm * 0.1 : 0)
            }
        }
        face.needsDisplay = true
    }
}

/// The widget's content, drawn over whatever glass is behind it.
private final class GlassFace: NSView {
    static let cornerRadius: CGFloat = 24

    var state = KeyboardState()
    var history: [Double] = []
    var simulatesGlass = false

    override var isFlipped: Bool { true }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }

    // MARK: Type and colour

    private static func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    private static let caption = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let small = NSFont.systemFont(ofSize: 11, weight: .medium)
    private static let body = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let title = rounded(30, .bold)
    private static let figure = rounded(26, .bold)

    private var accent: NSColor { .controlAccentColor }
    private var tileFill: NSColor { NSColor.labelColor.withAlphaComponent(isDark ? 0.08 : 0.06) }

    private func text(_ string: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
        ScreenDrawing.text(string, font, color)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        if simulatesGlass {
            drawSimulatedGlass()
        }
        drawLayer()
        drawModifiers()
        let tileWidth: CGFloat = 98
        drawSpeed(in: NSRect(x: 16, y: 98, width: tileWidth, height: 90))
        drawBatteries(in: NSRect(x: 16 + tileWidth + 9, y: 98, width: tileWidth, height: 90))
        drawConnection(in: NSRect(x: 16 + 2 * (tileWidth + 9), y: 98, width: tileWidth, height: 90))
    }

    /// A stand-in for Liquid Glass in previews: a wallpaper seen through frost, lit along the top.
    private func drawSimulatedGlass() {
        let shape = NSBezierPath(roundedRect: bounds, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        let wallpaper =
            isDark
            ? NSGradient(colors: [NSColor(hex: 0x1B2A55), NSColor(hex: 0x3A2160), NSColor(hex: 0x5A2A3A)])
            : NSGradient(colors: [NSColor(hex: 0x8EC5FC), NSColor(hex: 0xC3A5F5), NSColor(hex: 0xF9C7A5)])
        wallpaper?.draw(in: bounds, angle: -35)
        (isDark ? NSColor.black.withAlphaComponent(0.42) : NSColor.white.withAlphaComponent(0.55)).setFill()
        bounds.fill()
        let sheen = NSGradient(starting: NSColor.white.withAlphaComponent(isDark ? 0.10 : 0.35), ending: .clear)
        sheen?.draw(in: NSRect(x: 0, y: 0, width: bounds.width, height: 60), angle: 90)
        NSGraphicsContext.restoreGraphicsState()

        let rim = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius - 0.5,
            yRadius: Self.cornerRadius - 0.5)
        rim.lineWidth = 1
        NSColor.white.withAlphaComponent(isDark ? 0.18 : 0.6).setStroke()
        rim.stroke()
    }

    /// Top left: where in the keymap, the layer's name, and a dot per layer.
    private func drawLayer() {
        guard state.connected else {
            text("Keyboard", Self.caption, .secondaryLabelColor).draw(at: NSPoint(x: 16, y: 14))
            ScreenDrawing.symbol(
                "keyboard.badge.ellipsis", size: 22, weight: .medium, .tertiaryLabelColor,
                centredIn: NSRect(x: 16, y: 32, width: 30, height: 36))
            text("No Keyboard", Self.rounded(20, .bold), .secondaryLabelColor).draw(at: NSPoint(x: 50, y: 38))
            return
        }
        let count = Int(state.layerCount ?? 0)
        let caption = count > 0 ? "Layer \(Int(state.layerIndex) + 1) of \(count)" : "Layer \(state.layerIndex)"
        text(caption, Self.caption, .secondaryLabelColor).draw(at: NSPoint(x: 16, y: 14))

        let name = NSMutableAttributedString(attributedString: text(state.layerName, Self.title, .labelColor))
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        name.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: name.length))
        name.draw(in: NSRect(x: 16, y: 28, width: 166, height: 40))

        guard count > 0 else { return }
        let gap: CGFloat = count > 12 ? 3 : 5
        let dot = min(6, (166 - CGFloat(count - 1) * gap) / CGFloat(count))
        for i in 0..<count {
            let rect = NSRect(x: 16 + CGFloat(i) * (dot + gap), y: 76, width: dot, height: dot)
            let active = i == Int(state.layerIndex)
            ScreenDrawing.fill(rect, radius: dot / 2, active ? accent : .quaternaryLabelColor)
        }
    }

    /// Top right: a keycap per modifier, lit while held, and a capsule for Caps Word or Caps Lock.
    private func drawModifiers() {
        text("Modifiers", Self.caption, .secondaryLabelColor).draw(at: NSPoint(x: 190, y: 14))
        let on = state.connected
        let keys: [(String, Bool)] = [
            ("command", state.commandActive), ("option", state.optionActive),
            ("control", state.controlActive),
            (on && state.capsLock ? "capslock.fill" : on && state.capsWord ? "shift.fill" : "shift", state.shiftActive),
        ]
        for (i, (symbol, held)) in keys.enumerated() {
            let key = NSRect(x: 190 + CGFloat(i) * 36, y: 32, width: 30, height: 30)
            let lit = on && held
            var tint = accent
            if i == 3, on, state.capsLock {
                tint = .systemRed
            } else if i == 3, on, state.capsWord {
                tint = .systemOrange
            }
            let emphasised = lit || (i == 3 && on && (state.capsLock || state.capsWord))
            ScreenDrawing.fill(key, radius: 8, emphasised ? tint : tileFill)
            if !emphasised {
                ScreenDrawing.outline(key, radius: 8, width: 1, NSColor.labelColor.withAlphaComponent(0.08))
            }
            ScreenDrawing.symbol(
                symbol, size: 14, weight: .semibold, emphasised ? .white : .secondaryLabelColor, centredIn: key)
        }

        guard on, state.capsLock || state.capsWord else { return }
        let label = state.capsLock ? "Caps Lock" : "Caps Word"
        let color: NSColor = state.capsLock ? .systemRed : .systemOrange
        let words = text(label, Self.small, color)
        let width = words.size().width + 16
        let capsule = NSRect(x: 190 + 138 - width, y: 70, width: width, height: 18)
        ScreenDrawing.fill(capsule, radius: 9, color.withAlphaComponent(0.18))
        ScreenDrawing.draw(words, centredIn: capsule)
    }

    private func drawTile(_ rect: NSRect, caption: String, symbol: String? = nil) {
        ScreenDrawing.fill(rect, radius: 14, tileFill)
        var x = rect.minX + 10
        if let symbol {
            ScreenDrawing.symbol(
                symbol, size: 10, weight: .semibold, .secondaryLabelColor,
                centredIn: NSRect(x: x, y: rect.minY + 8, width: 13, height: 14))
            x += 16
        }
        text(caption, Self.caption, .secondaryLabelColor).draw(at: NSPoint(x: x, y: rect.minY + 8))
    }

    /// Words per minute, with the last 40 seconds as a sparkline.
    private func drawSpeed(in rect: NSRect) {
        drawTile(rect, caption: "Speed", symbol: "speedometer")
        let wpm = state.connected ? state.wpm.map { "\($0)" } ?? "—" : "—"
        let number = text(wpm, Self.figure, state.connected ? .labelColor : .tertiaryLabelColor)
        number.draw(at: NSPoint(x: rect.minX + 10, y: rect.minY + 22))
        text("wpm", Self.small, .secondaryLabelColor).draw(
            at: NSPoint(x: rect.minX + 14 + number.size().width, y: rect.minY + 35))

        let chart = NSRect(x: rect.minX + 10, y: rect.maxY - 30, width: rect.width - 20, height: 22)
        guard state.connected, history.count > 1 else { return }
        let peak = max(history.max() ?? 0, 30)
        let points = history.enumerated().map { i, value in
            NSPoint(
                x: chart.minX + chart.width * CGFloat(i) / CGFloat(history.count - 1),
                y: chart.maxY - chart.height * CGFloat(value / peak))
        }
        let line = NSBezierPath()
        line.move(to: points[0])
        for point in points.dropFirst() {
            line.line(to: point)
        }
        let area = line.copy() as! NSBezierPath
        area.line(to: NSPoint(x: chart.maxX, y: chart.maxY))
        area.line(to: NSPoint(x: chart.minX, y: chart.maxY))
        area.close()
        NSGradient(starting: accent.withAlphaComponent(0.35), ending: accent.withAlphaComponent(0))?
            .draw(in: area, angle: 90)
        line.lineWidth = 1.5
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        accent.setStroke()
        line.stroke()
    }

    /// A ring per half like the Batteries widget: green, orange at 20 % and below, red at 10 %;
    /// an empty grey ring while the half is offline.
    private func drawBatteries(in rect: NSRect) {
        drawTile(rect, caption: "Battery", symbol: "battery.75percent")
        for (i, (half, side)) in [(state.left, "L"), (state.right, "R")].enumerated() {
            let centre = NSPoint(x: rect.minX + 27 + CGFloat(i) * 44, y: rect.minY + 49)
            let online = state.connected && half.online == true
            ScreenDrawing.arc(
                center: centre, radius: 15, from: 0, sweep: 360, width: 4, NSColor.labelColor.withAlphaComponent(0.1))
            var caption = online ? "—" : "Off"
            if online, let level = half.battery {
                let color: NSColor = level <= 10 ? .systemRed : level <= 20 ? .systemOrange : .systemGreen
                ScreenDrawing.arc(
                    center: centre, radius: 15, from: 270, sweep: 360 * CGFloat(min(level, 100)) / 100, width: 4,
                    color)
                caption = "\(level)%"
            }
            let letter = text(side, Self.rounded(12, .bold), online ? .labelColor : .tertiaryLabelColor)
            ScreenDrawing.draw(letter, centredIn: NSRect(x: centre.x - 15, y: centre.y - 15, width: 30, height: 30))
            let label = text(caption, Self.small, online ? .secondaryLabelColor : .tertiaryLabelColor)
            ScreenDrawing.draw(label, centredIn: NSRect(x: centre.x - 22, y: rect.maxY - 20, width: 44, height: 14))
        }
    }

    /// The output, which computer it's typing to, and the BLE profiles (filled when paired, dashed
    /// when empty, accent for the active one).
    private func drawConnection(in rect: NSRect) {
        let output = state.connected ? state.output : nil
        switch output {
        case .usb: drawTile(rect, caption: "USB", symbol: "cable.connector")
        case .ble: drawTile(rect, caption: "Bluetooth", symbol: "antenna.radiowaves.left.and.right")
        default: drawTile(rect, caption: "Output", symbol: "arrow.up.right")
        }

        let (host, color) = hostDescription
        ScreenDrawing.fill(NSRect(x: rect.minX + 10, y: rect.minY + 33, width: 7, height: 7), radius: 3.5, color)
        let hostText = NSMutableAttributedString(attributedString: text(host, Self.body, .labelColor))
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        hostText.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: hostText.length))
        hostText.draw(in: NSRect(x: rect.minX + 22, y: rect.minY + 27, width: rect.width - 30, height: 18))

        let count = state.connected ? state.profileCount : 0
        guard count > 0 else { return }
        let gap: CGFloat = 4
        let size = min(17, (rect.width - 20 - CGFloat(count - 1) * gap) / CGFloat(count))
        for i in 0..<count {
            let slot = i + 1
            let circle = NSRect(
                x: rect.minX + 10 + CGFloat(i) * (size + gap), y: rect.maxY - 10 - size, width: size, height: size)
            let active = slot == state.activeProfile
            let open = state.openProfiles.contains(slot)
            let numberColor: NSColor
            if open {
                let ring = NSBezierPath(ovalIn: circle.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                ring.setLineDash([2.5, 2], count: 2, phase: 0)
                (active ? accent : NSColor.tertiaryLabelColor).setStroke()
                ring.stroke()
                numberColor = active ? accent : .tertiaryLabelColor
            } else {
                ScreenDrawing.fill(
                    circle, radius: size / 2, active ? accent : NSColor.labelColor.withAlphaComponent(0.12))
                numberColor = active ? .white : .secondaryLabelColor
            }
            if size >= 14 {
                ScreenDrawing.draw(text("\(slot)", Self.rounded(10, .bold), numberColor), centredIn: circle)
            }
        }
    }

    private var hostDescription: (String, NSColor) {
        guard state.connected else { return ("Offline", .tertiaryLabelColor) }
        switch state.hostStatus {
        case .inUseHere: return ("This Mac", .systemGreen)
        case .activeElsewhere: return ("Other device", .systemOrange)
        case .onUsb: return ("On USB", .systemBlue)
        case .disconnected: return ("Searching", .systemGray)
        case .cannotDetermine, nil:
            return state.hostConnected == false ? ("Searching", .systemGray) : ("Connected", .systemGreen)
        }
    }
}
