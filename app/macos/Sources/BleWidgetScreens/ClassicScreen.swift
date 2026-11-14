// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

/// The Prospector dongle's Classic screen (carrefinho/prospector-zmk-module, layouts/classic) at
/// 280×240: a layer roller, a column of modifiers, a battery bar per half and the BLE profile.
/// The roller shows neighbouring layers once their names have been seen (KBP reports only the
/// active one). SF stands in for the FRAC and Gridnik fonts.
public final class ClassicScreen: NSView, KeyboardScreen {
    public static let id = "prospector-classic"
    public static let displayName = "Prospector: Classic"
    public static let size = NSSize(width: 280, height: 240)

    public var animates = true {
        didSet { badge.animates = animates }
    }

    private var state = KeyboardState()
    private let badge = ProfileBadge()
    private var roller = Tween(0)
    private var batteryWidth = Tween(280)
    private let timer = FrameTimer()

    public required init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        badge.onChange = { [weak self] in self?.badgeChanged() }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    public override var isFlipped: Bool { true }
    public override var intrinsicContentSize: NSSize { Self.size }

    public func render(_ state: KeyboardState) {
        let layerChanged = state.layerIndex != self.state.layerIndex
        self.state = state
        badge.update(state)
        if animates, layerChanged {
            roller.animate(to: Double(state.layerIndex), over: 0.1, .easeOut)
        } else if !animates || !roller.isRunning() {
            roller.jump(to: Double(state.layerIndex))
        }
        badgeChanged()
    }

    /// battery_bar.c narrows from 280 to 227 over 200 ms while the profile shows.
    private func badgeChanged() {
        let width: Double = badge.visible ? 227 : 280
        if animates, width != batteryWidth.target {
            batteryWidth.animate(to: width, over: 0.2, .easeOut)
        } else if !animates {
            batteryWidth.jump(to: width)
        }
        if animates, roller.isRunning() || batteryWidth.isRunning() {
            timer.start(every: 1.0 / 60) { [weak self] in
                guard let self else { return false }
                self.needsDisplay = true
                return self.roller.isRunning() || self.batteryWidth.isRunning()
            }
        }
        needsDisplay = true
    }

    // MARK: - Drawing

    private enum Fonts {
        /// FRAC Regular 48 and Thin 48.
        static let fracRegular = NSFont.systemFont(ofSize: 44, weight: .regular)
        static let fracThin = NSFont.systemFont(ofSize: 44, weight: .thin)
        /// Foundry Gridnik Medium 20 and 24.
        static let gridnik20 = NSFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        static let gridnik24 = NSFont.monospacedSystemFont(ofSize: 19, weight: .medium)
    }

    public override func draw(_ dirtyRect: NSRect) {
        ScreenDrawing.fill(bounds, radius: 12, .black)
        drawRoller()
        drawModifiers()
        drawBatteries()
        if badge.visible {
            drawBadge()
        }
    }

    /// layer_roller.c: an infinite 224×140 roller left-centred 20 up, rows 52 apart (no theme, so no
    /// line spacing), the selected one in FRAC Regular and white, the rest Thin and grey, with
    /// 40-high fades at the top and bottom.
    private func drawRoller() {
        guard state.connected else { return }
        let frame = NSRect(x: 0, y: 30, width: 224, height: 140)
        let count = max(
            Int(state.layerCount ?? 0), Int(state.layerNames.keys.max() ?? 0) + 1, Int(state.layerIndex) + 1)
        let position = roller.value()
        let pitch: CGFloat = 52
        let selectedBand = NSRect(x: frame.minX, y: frame.midY - 26, width: frame.width, height: 52)

        func drawRows(_ font: NSFont, _ color: NSColor) {
            let base = Int(position.rounded(.down))
            for offset in -2...3 {
                let index = ((base + offset) % count + count) % count
                guard let name = state.layerNames[UInt8(index)] else { continue }
                let y = frame.midY + (CGFloat(base + offset) - CGFloat(position)) * pitch
                let row = NSRect(x: frame.minX, y: y - pitch / 2, width: frame.width, height: pitch)
                ScreenDrawing.draw(ScreenDrawing.text(name, font, color), centredIn: row)
            }
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: frame).addClip()
        drawRows(Fonts.fracThin, NSColor(hex: 0x909090))
        NSBezierPath(rect: selectedBand).setClip()
        NSColor.black.setFill()
        selectedBand.fill()
        drawRows(Fonts.fracRegular, .white)
        NSGraphicsContext.restoreGraphicsState()

        let fade = NSGradient(starting: .black, ending: NSColor.black.withAlphaComponent(0))
        fade?.draw(in: NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: 40), angle: 90)
        fade?.draw(in: NSRect(x: frame.minX, y: frame.maxY - 40, width: frame.width, height: 40), angle: -90)
    }

    /// modifier_indicator.c: Mac symbols in a column 8 apart, right-centred 8 in and 12 up.
    private func drawModifiers() {
        for (i, modifier) in ProspectorModifier.all(state).enumerated() {
            let cell = NSRect(x: 238, y: 30 + CGFloat(i) * 41, width: 34, height: 33)
            let color = modifier.color(held: NSColor(hex: 0x00FFE5), idle: NSColor(hex: 0x101010))
            ScreenDrawing.symbol(modifier.symbol, size: 27, weight: .semibold, color, centredIn: cell)
        }
    }

    /// battery_bar.c: a 4-high bar and the level per half, spread across the bottom 48 with 16
    /// either side and 12 between; amber under 20 %, a red bar and a cross while a half is offline.
    private func drawBatteries() {
        let width = CGFloat(batteryWidth.value())
        let each = (width - 32 - 12) / 2
        for (i, half) in [state.left, state.right].enumerated() {
            let box = NSRect(x: 16 + CGFloat(i) * (each + 12), y: 192, width: each, height: 36)
            let bar = NSRect(x: box.minX, y: box.maxY - 4, width: each, height: 4)
            guard state.connected, half.online == true else {
                ScreenDrawing.fill(bar, radius: 1, NSColor(hex: 0x9E2121))
                ScreenDrawing.symbol("xmark", size: 11, weight: .bold, NSColor(hex: 0xE63030), centredIn: box)
                continue
            }
            let level = Int(half.battery ?? 0)
            let low = half.battery != nil && level < 20
            ScreenDrawing.fill(bar, radius: 1, NSColor(hex: low ? 0x6E4E07 : 0x202020))
            if level > 0 {
                var filled = bar
                filled.size.width = each * CGFloat(min(level, 100)) / 100
                let gradient =
                    low
                    ? NSGradient(starting: NSColor(hex: 0xD3900F), ending: NSColor(hex: 0xE8AC11))
                    : NSGradient(starting: NSColor(hex: 0x909090), ending: NSColor(hex: 0xF0F0F0))
                gradient?.draw(in: NSBezierPath(roundedRect: filled, xRadius: 1, yRadius: 1), angle: 0)
            }
            let text = half.battery.map { "\($0)" } ?? "-"
            let color = low ? NSColor(hex: 0xFFB802) : .white
            ScreenDrawing.draw(ScreenDrawing.text(text, Fonts.gridnik20, color), centredIn: box)
        }
    }

    /// output.c: 50×30 in the bottom-right corner (14 in, 9 up); the waves left, the number right.
    private func drawBadge() {
        let frame = NSRect(x: 216, y: 201, width: 50, height: 30)
        badge.drawWaves(in: NSRect(x: frame.minX, y: frame.minY - 1, width: 30, height: 30), size: 23)
        let number = ScreenDrawing.text(badge.number, Fonts.gridnik24, badge.numberColor)
        let size = number.size()
        number.draw(at: NSPoint(x: frame.maxX - size.width, y: frame.midY - size.height / 2 + 1))
    }
}
