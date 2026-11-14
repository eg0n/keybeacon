// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

/// The Prospector dongle's Radii screen (carrefinho/prospector-zmk-module, layouts/radii) at
/// 280×240, in its default blue theme: a layer wheel and name on the left panel, modifiers, the BLE
/// profile and a battery ring per half on the right. SF Compressed stands in for its PPF font.
public final class RadiiScreen: NSView, KeyboardScreen {
    public static let id = "prospector-radii"
    public static let displayName = "Prospector: Radii"
    public static let size = NSSize(width: 280, height: 240)

    public var animates = true {
        didSet { badge.animates = animates }
    }

    private var state = KeyboardState()
    private let badge = ProfileBadge()
    /// The wheel's rotation in degrees.
    private var wheel = Tween(0)
    /// The modifier panel's top: 0, or 30 while the profile shows above it.
    private var panelTop = Tween(0)
    private let timer = FrameTimer()

    public required init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        badge.onChange = { [weak self] in self?.layout(animated: true) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize { Self.size }

    public func render(_ state: KeyboardState) {
        let layerChanged = state.layerIndex != self.state.layerIndex || state.layerCount != self.state.layerCount
        self.state = state
        badge.update(state)

        // layer_indicator.c: turn the current layer's tick to the top, the short way round, in 150 ms.
        var target = -Double(state.layerIndex) * 360 / Double(layerCount)
        let current = wheel.value()
        while target - current > 180 { target -= 360 }
        while target - current < -180 { target += 360 }
        if animates, layerChanged {
            wheel.animate(to: target, over: 0.15, .easeInOut)
        } else if !animates || !wheel.isRunning() {
            wheel.jump(to: target)
        }
        layout(animated: animates)
    }

    private var layerCount: Int { max(Int(state.layerCount ?? 0), Int(state.layerIndex) + 1, 1) }

    /// modifier_indicator.c: the panel shrinks from 178 to 148 high in 150 ms while the profile shows.
    private func layout(animated: Bool) {
        let top: Double = badge.visible ? 30 : 0
        if animated, top != panelTop.target {
            panelTop.animate(to: top, over: 0.15, .easeOut)
        } else if !animated {
            panelTop.jump(to: top)
        }
        if animates, wheel.isRunning() || panelTop.isRunning() {
            timer.start(every: 1.0 / 60) { [weak self] in
                guard let self else { return false }
                self.needsDisplay = true
                return self.wheel.isRunning() || self.panelTop.isRunning()
            }
        }
        needsDisplay = true
    }

    // MARK: - Drawing

    /// prospector_adapter.overlay's prospector_blue_theme.
    private enum Theme {
        static let leftPanel = NSColor(hex: 0xACB9D3)
        static let modPanel = NSColor(hex: 0x1448AA)
        static let batteryPanel = NSColor(hex: 0xE2FF61)
        static let arcBackground = NSColor(hex: 0xA8BF41)
        static let arcIndicator = NSColor(hex: 0x576610)
        static let wheel = NSColor.black
        static let layerText = NSColor.black
        static let modActive = NSColor(hex: 0x61E7FF)
        static let modInactive = NSColor(hex: 0x0C2B65)
    }

    private enum Fonts {
        /// PPF Narrow Thin 64.
        static let ppfNarrowThin: NSFont = {
            if #available(macOS 13.0, *) {
                return .systemFont(ofSize: 58, weight: .ultraLight, width: .compressed)
            }
            return .systemFont(ofSize: 52, weight: .ultraLight)
        }()
        /// The Symbols font's digits, semibold 28.
        static let profile = NSFont.systemFont(ofSize: 23, weight: .semibold)
    }

    public override func draw(_ dirtyRect: NSRect) {
        ScreenDrawing.fill(bounds, radius: 12, .black)
        drawLeftPanel()
        drawModifiers()
        if badge.visible {
            drawBadge()
        }
        drawBatteries()
    }

    /// status_screen.c and layer_indicator.c: a 172×240 panel; at (14, 20) the 48×48 wheel, one
    /// tick per layer from radius 12 to 20, then 12 below it the name, uppercase, wrapped at 148.
    private func drawLeftPanel() {
        ScreenDrawing.fill(NSRect(x: 0, y: 0, width: 172, height: 240), radius: 24, Theme.leftPanel)
        guard state.connected else { return }

        let centre = NSPoint(x: 14 + 24, y: 20 + 24)
        let path = NSBezierPath()
        let rotation = wheel.value()
        for i in 0..<layerCount {
            let angle = (Double(i) * 360 / Double(layerCount) - 90 + rotation) * Double.pi / 180
            path.move(to: NSPoint(x: centre.x + 12 * cos(angle), y: centre.y + 12 * sin(angle)))
            path.line(to: NSPoint(x: centre.x + 20 * cos(angle), y: centre.y + 20 * sin(angle)))
        }
        path.lineWidth = 4
        path.lineCapStyle = .round
        Theme.wheel.setStroke()
        path.stroke()

        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineHeightMultiple = 0.85
        let name = NSAttributedString(
            string: state.layerName.uppercased(),
            attributes: [.font: Fonts.ppfNarrowThin, .foregroundColor: Theme.layerText, .paragraphStyle: style])
        name.draw(with: NSRect(x: 14, y: 80, width: 148, height: 150), options: [.usesLineFragmentOrigin])
    }

    /// modifier_indicator.c: a 108-wide panel ending at y 178, symbols two by two at (14, 27),
    /// (50, 27), (14, 64) and (50, 64) from its top.
    private func drawModifiers() {
        let top = CGFloat(panelTop.value())
        ScreenDrawing.fill(NSRect(x: 172, y: top, width: 108, height: 178 - top), radius: 24, Theme.modPanel)
        let positions: [(CGFloat, CGFloat)] = [(14, 27), (50, 27), (14, 64), (50, 64)]
        for (modifier, (x, y)) in zip(ProspectorModifier.all(state), positions) {
            let cell = NSRect(x: 172 + x, y: top + y, width: 34, height: 33)
            let color = modifier.color(held: Theme.modActive, idle: Theme.modInactive)
            ScreenDrawing.symbol(modifier.symbol, size: 27, weight: .semibold, color, centredIn: cell)
        }
    }

    /// output.c: 108×30 top right; the waves at (19, -1) and the number at (54, 1), 30×30 each.
    private func drawBadge() {
        badge.drawWaves(in: NSRect(x: 172 + 19, y: -1, width: 30, height: 30), size: 23)
        let number = ScreenDrawing.text(badge.number, Fonts.profile, badge.numberColor)
        ScreenDrawing.draw(number, centredIn: NSRect(x: 172 + 54, y: 1, width: 30, height: 30))
    }

    /// battery_circles.c, two peripherals: a 108×62 panel at (172, 178) with 30-wide rings 6 thick,
    /// 19 in and 10 apart, filling clockwise from the top; empty while a half is offline.
    private func drawBatteries() {
        ScreenDrawing.fill(NSRect(x: 172, y: 178, width: 108, height: 62), radius: 24, Theme.batteryPanel)
        for (i, half) in [state.left, state.right].enumerated() {
            let centre = NSPoint(x: 172 + 19 + CGFloat(i) * 40 + 15, y: 178 + 16 + 15)
            ScreenDrawing.arc(center: centre, radius: 12, from: 0, sweep: 360, width: 6, Theme.arcBackground)
            let level = state.connected && half.online == true ? Int(half.battery ?? 0) : 0
            if level > 0 {
                let sweep = 360 * CGFloat(min(level, 100)) / 100
                ScreenDrawing.arc(center: centre, radius: 12, from: 270, sweep: sweep, width: 6, Theme.arcIndicator)
            }
        }
    }
}
