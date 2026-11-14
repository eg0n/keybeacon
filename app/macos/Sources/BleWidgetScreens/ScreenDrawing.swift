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

extension NSColor {
    /// An sRGB colour from 0xRRGGBB, as in LVGL's lv_color_hex.
    public convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
