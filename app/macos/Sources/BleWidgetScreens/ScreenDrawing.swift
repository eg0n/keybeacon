// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit

/// Small drawing helpers for screens, which draw in a flipped view (y down, like LVGL).
public enum ScreenDrawing {
    public static func text(_ string: String, _ font: NSFont, _ color: NSColor, kern: CGFloat = 0)
        -> NSAttributedString
    {
        NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    }

    /// Draws `text` centred in `rect`.
    public static func draw(_ text: NSAttributedString, centredIn rect: NSRect) {
        let size = text.size()
        text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
    }

    /// Draws an SF Symbol in `color`, centred in `rect`; `alpha` fades it.
    public static func symbol(
        _ name: String, size: CGFloat, weight: NSFont.Weight = .regular, _ color: NSColor, centredIn rect: NSRect,
        alpha: CGFloat = 1
    ) {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard
            let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
        else { return }
        let size = image.size
        let target = NSRect(
            x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: alpha, respectFlipped: true, hints: nil)
    }

    public static func fill(_ rect: NSRect, radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    /// A rounded outline drawn inside `rect`.
    public static func outline(_ rect: NSRect, radius: CGFloat, width: CGFloat, _ color: NSColor) {
        let inset = width / 2
        let path = NSBezierPath(
            roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: radius - inset, yRadius: radius - inset)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    /// An arc with round caps; angles in degrees, clockwise from 3 o'clock as in LVGL.
    public static func arc(
        center: NSPoint, radius: CGFloat, from start: CGFloat, sweep: CGFloat, width: CGFloat, _ color: NSColor
    ) {
        guard sweep > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        let toRadians = CGFloat.pi / 180
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.addArc(
            center: center, radius: radius, startAngle: start * toRadians, endAngle: (start + sweep) * toRadians,
            clockwise: false)
        context.strokePath()
        context.restoreGState()
    }
}

/// A value easing from one number to another over time, like an LVGL animation.
public struct Tween {
    public enum Curve {
        case linear, easeOut, easeInOut
    }

    private var from: Double
    public private(set) var target: Double
    private var start = Date.distantPast
    private var duration: TimeInterval = 0
    private var curve = Curve.linear

    public init(_ value: Double) {
        from = value
        target = value
    }

    public mutating func animate(to value: Double, over duration: TimeInterval, _ curve: Curve, now: Date = Date()) {
        from = self.value(at: now)
        target = value
        start = now
        self.duration = duration
        self.curve = curve
    }

    public mutating func jump(to value: Double) {
        from = value
        target = value
        duration = 0
    }

    public func isRunning(at now: Date = Date()) -> Bool {
        duration > 0 && now.timeIntervalSince(start) < duration
    }

    public func value(at now: Date = Date()) -> Double {
        guard isRunning(at: now) else { return target }
        let t = max(0, now.timeIntervalSince(start) / duration)
        let eased: Double
        switch curve {
        case .linear: eased = t
        case .easeOut: eased = 1 - (1 - t) * (1 - t)
        case .easeInOut: eased = t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t)
        }
        return from + (target - from) * eased
    }
}

/// A repeating timer for a screen's animations; `tick` returns false to stop it.
public final class FrameTimer {
    private var timer: Timer?
    public private(set) var interval: TimeInterval = 0

    public init() {}

    deinit {
        timer?.invalidate()
    }

    public var isRunning: Bool { timer != nil }

    public func start(every interval: TimeInterval, _ tick: @escaping () -> Bool) {
        if timer != nil, interval == self.interval { return }
        stop()
        self.interval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            if !tick() {
                timer.invalidate()
                self?.timer = nil
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }
}

extension NSColor {
    /// An sRGB colour from 0xRRGGBB, as in LVGL's lv_color_hex.
    public convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
