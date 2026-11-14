// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

/// The Prospector dongle's Field screen (carrefinho/prospector-zmk-module, layouts/field) at
/// 280×240: an 8×6 grid of short lines that flow with typing speed, with the layer name, the
/// batteries, the modifiers and the BLE profile set into it. The animation constants and timing
/// are line_segments.c's, with its defaults (70 WPM reference, 30 s fade, 300 s settle).
public final class FieldScreen: NSView, KeyboardScreen {
    public static let id = "prospector-field"
    public static let displayName = "Prospector: Field"
    public static let size = NSSize(width: 280, height: 240)

    public var animates = true {
        didSet { badge.animates = animates }
    }

    private var state = KeyboardState()
    private let badge = ProfileBadge()
    private let timer = FrameTimer()
    private var lines = FlowLines()

    public required init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        badge.onChange = { [weak self] in self?.needsDisplay = true }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize { Self.size }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            timer.stop()
        } else {
            scheduleFrames()
        }
    }

    public func render(_ state: KeyboardState) {
        self.state = state
        badge.update(state)
        let wpm = state.connected ? Int(state.wpm ?? 0) : 0
        if animates {
            lines.setWPM(wpm, now: Date())
            scheduleFrames()
        } else {
            // A still: as if typing at this speed for four seconds.
            lines = FlowLines()
            let start = Date()
            for frame in 0..<120 {
                lines.setWPM(wpm, now: start)
                lines.step(now: start.addingTimeInterval(Double(frame) / 30))
            }
        }
        needsDisplay = true
    }

    /// line_segments.c: 30 Hz while typing, 15 Hz while the lines settle, 2 Hz when idle.
    private func scheduleFrames() {
        guard animates, window != nil else { return }
        timer.start(every: lines.frameInterval(now: Date())) { [weak self] in
            guard let self else { return false }
            let now = Date()
            self.lines.step(now: now)
            self.needsDisplay = true
            if self.lines.frameInterval(now: now) != self.timer.interval {
                DispatchQueue.main.async { self.scheduleFrames() }
            }
            return true
        }
    }

    // MARK: - Drawing

    /// The grid's top-left on screen: 274×206, centred.
    private static let origin = NSPoint(x: 3, y: 17)

    public override func draw(_ dirtyRect: NSRect) {
        ScreenDrawing.fill(bounds, radius: 12, .black)

        // layer_label.c and battery_label.c: FRAC Regular 36 top-left at (9, 14) and FRAC Regular 30
        // (letter spacing -1) bottom-left 9 in, 20 up.
        let layer = state.connected ? state.layerName : ""
        let battery = batteryText
        let layerFont = LVGLFont.fracRegular36
        let batteryFont = LVGLFont.fracRegular30
        layerFont.draw(layer, at: NSPoint(x: 9, y: 14), .white)
        batteryFont.draw(battery, at: NSPoint(x: 9, y: 220 - batteryFont.lineHeight), .white, letterSpace: -1)

        // Cells under the labels, the modifiers (column 7, rows 2-5) and the profile stay empty.
        var excluded = Set<Int>()
        for col in 0..<Self.coveredColumns(layerFont.width(layer)) { excluded.insert(col) }
        for col in 0..<Self.coveredColumns(batteryFont.width(battery, letterSpace: -1)) {
            excluded.insert(5 * 8 + col)
        }
        for row in 2...5 { excluded.insert(row * 8 + 7) }
        if badge.visible {
            excluded.formUnion([8, 9])
        }
        drawLines(excluding: excluded)
        drawModifiers()
        if badge.visible {
            drawBadge()
        }
    }

    /// "74/77", with "-" for a half that is offline.
    private var batteryText: String {
        [state.left, state.right].map { half in
            state.connected && half.online == true ? "\(half.battery ?? 0)" : "-"
        }.joined(separator: "/")
    }

    /// Columns a label from x = 6 (grid coordinates) covers, as width_to_columns does.
    private static func coveredColumns(_ width: CGFloat) -> Int {
        let right = 6 + width
        return (0..<8).first { right <= CGFloat(FlowLines.centre(of: $0) - 17) } ?? 8
    }

    private func drawLines(excluding excluded: Set<Int>) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setLineWidth(2)
        context.setLineCap(.butt)
        for row in 0..<6 {
            for col in 0..<8 where !excluded.contains(row * 8 + col) {
                let (dx, dy, opacity) = lines.segment(col: col, row: row)
                let cx = Self.origin.x + CGFloat(FlowLines.centre(of: col))
                let cy = Self.origin.y + CGFloat(FlowLines.centre(of: row))
                context.setStrokeColor(NSColor.white.withAlphaComponent(opacity).cgColor)
                context.move(to: CGPoint(x: cx - dx, y: cy - dy))
                context.addLine(to: CGPoint(x: cx + dx, y: cy + dy))
                context.strokePath()
            }
        }
        context.restoreGState()
    }

    /// modifier_indicator.c: one Symbols Regular 28 glyph centred in each grid cell of column 7,
    /// rows 2-5.
    private func drawModifiers() {
        for (i, modifier) in ProspectorModifier.all(state).enumerated() {
            let cx = Self.origin.x + CGFloat(FlowLines.centre(of: 7))
            let cy = Self.origin.y + CGFloat(FlowLines.centre(of: 2 + i))
            let cell = NSRect(x: cx - 17, y: cy - 17, width: 34, height: 34)
            let color = modifier.color(held: .white, idle: NSColor(hex: 0x404040))
            LVGLFont.symbolsRegular28.draw(modifier.symbol, centredIn: cell, color)
        }
    }

    /// output.c: 68×34 on black at (4, 52); the waves in a 30×30 label at (8, 3), the number in
    /// Gridnik 26 right-centred 5 in and 4 down.
    private func drawBadge() {
        let frame = NSRect(x: 4, y: 52, width: 68, height: 34)
        NSColor.black.setFill()
        frame.fill()
        badge.drawWaves(in: NSRect(x: frame.minX + 8, y: frame.minY + 3, width: 30, height: 30))
        let font = LVGLFont.gridnikMedium26
        let size = font.size(badge.number)
        let origin = NSPoint(
            x: frame.maxX - 5 - size.width, y: frame.minY + ((frame.height - size.height) / 2).rounded(.down) + 4)
        font.draw(badge.number, at: origin, badge.numberColor)
    }
}

/// line_segments.c's model: each line's angle follows a noise field as typing speeds up ("flow"),
/// its opacity rises with "intensity", and both decay once typing stops.
private struct FlowLines {
    static func centre(of index: Int) -> Int { 18 + index * 34 }

    private static let wpmReference = 70.0
    private static let intensityDecay = 30.0
    private static let flowDecay = 300.0

    private var time = 0.0
    private var wobbleTime = 0.0
    private var flow = 0.0
    private var flowAtStop = 0.0
    private var intensity = 0.0
    private var intensityAtStop = 0.0
    private var wpm = 0
    private var lastKeypress = Date.distantPast
    private var started = false
    private var angles = [Double](repeating: -Double.pi / 4, count: 48)
    private var degrees = [Int](repeating: 0, count: 48)
    private var lengths = [Double](repeating: 0.5, count: 48)
    private var opacities = [Double](repeating: 0.3, count: 48)

    mutating func setWPM(_ wpm: Int, now: Date) {
        guard wpm <= 300 else { return }
        self.wpm = wpm
        if wpm > 0 {
            lastKeypress = now
            started = true
        }
    }

    func frameInterval(now: Date) -> TimeInterval {
        if wpm > 0 { return 0.033 }
        return started && now.timeIntervalSince(lastKeypress) < Self.flowDecay ? 0.066 : 0.5
    }

    /// The firmware's decay_param_t: rise fast while typing, fall slowly, then fade out linearly.
    private func decayed(_ current: Double, _ atStop: inout Double, idle: Double, decay: Double) -> Double {
        let target: Double
        if wpm > 0 {
            target = min(1, Double(wpm) / 60)
            atStop = current
        } else if idle < decay {
            target = atStop * (1 - idle / decay)
        } else {
            target = 0
        }
        let rate = wpm > 0 ? (target > current ? 0.15 : 0.005) : 0.02
        return current + (target - current) * rate
    }

    private static func noise(_ x: Double, _ y: Double, _ t: Double) -> Double {
        let n1 = sin(x * 0.007 + t * 0.15) * cos(y * 0.008 - t * 0.12)
        let n2 = sin(y * 0.006 + t * 0.1 + x * 0.005)
        return (n1 + n2 * 0.7) / 1.7
    }

    /// One lines_update() frame.
    mutating func step(now: Date) {
        let delta = 1.0 / 30
        let idle = now.timeIntervalSince(lastKeypress)
        if wpm > 0 || idle < Self.intensityDecay / 10 {
            time += (0.004 + Double(wpm) / Self.wpmReference * 0.072) * delta * 60
        }
        wobbleTime += 0.05 * delta * 60
        flow = decayed(flow, &flowAtStop, idle: idle, decay: Self.flowDecay)
        intensity = decayed(intensity, &intensityAtStop, idle: idle, decay: Self.intensityDecay)

        for row in 0..<6 {
            for col in 0..<8 {
                let i = row * 8 + col
                let cx = Double(Self.centre(of: col))
                let cy = Double(Self.centre(of: row))
                let target = -Double.pi / 4 + Self.noise(cx, cy, time) * Double.pi * 1.5 * flow
                angles[i] += (target - angles[i]) * 0.15
                let wobble = sin(wobbleTime * 0.5 + Double(col) * 0.3 + Double(row) * 0.2) * 0.5
                degrees[i] = Int((angles[i] + wobble) * 180 / Double.pi)

                let breath = sin(time * 0.3 + Double(col) * 0.5 + Double(row) * 0.4) * 0.15
                lengths[i] = min(max(0.5 + flow * 0.5 + breath * flow, 0.5), 1)

                var variation = Self.noise(cx * 0.5, cy * 0.5, time * 0.2)
                variation = (variation + 1) * 0.5
                let opacity = 0.3 + intensity * 0.5 + variation * 0.3 * intensity - 0.15 * intensity
                opacities[i] = min(max(opacity, 0.15), 0.7)
            }
        }
    }

    /// A line's half-extent and opacity, from line_endpoints.h's 2° table of 14-long vectors.
    func segment(col: Int, row: Int) -> (CGFloat, CGFloat, CGFloat) {
        let i = row * 8 + col
        let step = ((degrees[i] % 360 + 360) % 360) / 2 * 2
        let radians = Double(step) * Double.pi / 180
        let dx = (14 * cos(radians)).rounded() * lengths[i]
        let dy = (14 * sin(radians)).rounded() * lengths[i]
        return (CGFloat(Int(dx)), CGFloat(Int(dy)), CGFloat((opacities[i] * 255).rounded(.down) / 255))
    }
}
