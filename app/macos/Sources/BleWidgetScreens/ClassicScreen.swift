// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

/// The Prospector dongle's Classic screen (carrefinho/prospector-zmk-module, layouts/classic) at
/// 280×240: a layer roller, a column of modifiers, a battery bar per half and the BLE profile.
/// The roller shows neighbouring layers once their names have been seen (KBP reports only the
/// active one).
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

    public override func draw(_ dirtyRect: NSRect) {
        ScreenDrawing.fill(bounds, radius: 12, .black)
        drawRoller()
        drawModifiers()
        drawBatteries()
        if badge.visible {
            drawBadge()
        }
    }

    /// layer_roller.c: an infinite 224×140 roller left-centred 20 up, one 52-high line per layer (no
    /// theme, so no line spacing), the selected one in FRAC Regular and white, the rest Thin and
    /// grey, with 40-high fades at the top and bottom.
    private func drawRoller() {
        guard state.connected else { return }
        let frame = NSRect(x: 0, y: 30, width: 224, height: 140)
        let count = max(
            Int(state.layerCount ?? 0), Int(state.layerNames.keys.max() ?? 0) + 1, Int(state.layerIndex) + 1)
        let position = roller.value()
        let pitch = LVGLFont.fracRegular48.lineHeight
        let selectedBand = NSRect(
            x: frame.minX, y: frame.minY + ((frame.height - pitch) / 2).rounded(.down), width: frame.width,
            height: pitch)

        func drawRows(_ font: LVGLFont, _ color: NSColor) {
            let base = Int(position.rounded(.down))
            for offset in -2...3 {
                let index = ((base + offset) % count + count) % count
                guard let name = state.layerNames[UInt8(index)] else { continue }
                let top = selectedBand.minY + (CGFloat(base + offset) - CGFloat(position)) * pitch
                font.draw(name, centredAcross: NSRect(x: frame.minX, y: top, width: frame.width, height: pitch), color)
            }
        }

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: frame).addClip()
        drawRows(.fracThin48, NSColor(hex: 0x909090))
        NSBezierPath(rect: selectedBand).setClip()
        NSColor.black.setFill()
        selectedBand.fill()
        drawRows(.fracRegular48, .white)
        NSGraphicsContext.restoreGraphicsState()

        let fade = NSGradient(starting: .black, ending: NSColor.black.withAlphaComponent(0))
        fade?.draw(in: NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: 40), angle: 90)
        fade?.draw(in: NSRect(x: frame.minX, y: frame.maxY - 40, width: frame.width, height: 40), angle: -90)
    }

    /// modifier_indicator.c: Symbols Semibold 32 in a column, 8 between and centred on its widest,
    /// right-centred 8 in and 12 up.
    private func drawModifiers() {
        let font = LVGLFont.symbolsSemibold32
        let modifiers = ProspectorModifier.all(state)
        let width = modifiers.map { font.width($0.symbol) }.max() ?? 0
        let height = CGFloat(modifiers.count) * font.lineHeight + CGFloat(modifiers.count - 1) * 8
        let column = NSRect(
            x: 280 - 8 - width, y: ((240 - height) / 2).rounded(.down) - 12, width: width, height: height)
        for (i, modifier) in modifiers.enumerated() {
            let row = NSRect(
                x: column.minX, y: column.minY + CGFloat(i) * (font.lineHeight + 8), width: width,
                height: font.lineHeight)
            let color = modifier.color(held: NSColor(hex: 0x00FFE5), idle: NSColor(hex: 0x101010))
            font.draw(modifier.symbol, centredIn: row, color)
        }
    }

    /// battery_bar.c: a 4-high bar and the level per half, spread across the bottom 48 with 16
    /// either side and 12 between; amber under 20 %, a red bar and a cross while a half is offline.
    private func drawBatteries() {
        let width = CGFloat(batteryWidth.value())
        let each = ((width - 32 - 12) / 2).rounded(.down)
        for (i, half) in [state.left, state.right].enumerated() {
            let box = NSRect(x: 16 + CGFloat(i) * (each + 12), y: 192, width: each, height: 36)
            let bar = NSRect(x: box.minX, y: box.maxY - 4, width: each, height: 4)
            guard state.connected, half.online == true else {
                ScreenDrawing.fill(bar, radius: 1, NSColor(hex: 0x9E2121))
                LVGLFont.montserrat20.draw("\u{F00D}", centredIn: box, NSColor(hex: 0xE63030))
                continue
            }
            let level = Int(half.battery ?? 0)
            let low = half.battery != nil && level < 20
            ScreenDrawing.fill(bar, radius: 1, NSColor(hex: low ? 0x6E4E07 : 0x202020))
            if level > 0 {
                var filled = bar
                filled.size.width = (each * CGFloat(min(level, 100)) / 100).rounded()
                let gradient =
                    low
                    ? NSGradient(starting: NSColor(hex: 0xD3900F), ending: NSColor(hex: 0xE8AC11))
                    : NSGradient(starting: NSColor(hex: 0x909090), ending: NSColor(hex: 0xF0F0F0))
                gradient?.draw(in: NSBezierPath(roundedRect: filled, xRadius: 1, yRadius: 1), angle: 0)
            }
            let text = half.battery.map { "\($0)" } ?? "-"
            LVGLFont.gridnikMedium20.draw(text, centredIn: box, low ? NSColor(hex: 0xFFB802) : .white)
        }
    }

    /// output.c: 50×30 in the bottom-right corner (14 in, 9 up); the waves in a 30×30 label 1 up,
    /// the number in Gridnik 24 right-centred 1 down.
    private func drawBadge() {
        let frame = NSRect(x: 216, y: 201, width: 50, height: 30)
        badge.drawWaves(in: NSRect(x: frame.minX, y: frame.minY - 1, width: 30, height: 30))
        let font = LVGLFont.gridnikMedium24
        let size = font.size(badge.number)
        let origin = NSPoint(x: frame.maxX - size.width, y: frame.minY + ((30 - size.height) / 2).rounded(.down) + 1)
        font.draw(badge.number, at: origin, badge.numberColor)
    }
}
