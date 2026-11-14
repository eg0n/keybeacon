// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit

/// A bitmap font from the firmware's LVGL font files (lv_font_fmt_txt), drawn glyph by glyph so
/// text looks as it does on the dongle; scripts/prospector_assets.py generates the data. Placement
/// follows LVGL: a line's baseline sits `lineHeight - baseLine` below its top, pens advance in
/// whole pixels and `letterSpace` goes between characters.
final class LVGLFont {
    private struct Glyph {
        let bitmapIndex: Int
        let advance: CGFloat
        let width: Int
        let height: Int
        let offsetX: Int
        let offsetY: Int
    }

    let lineHeight: CGFloat
    private let baseLine: CGFloat
    private let bpp: Int
    private let bitmap: [UInt8]
    private var glyphs: [UInt32: Glyph] = [:]
    private var images: [String: CGImage] = [:]

    init(bpp: Int, lineHeight: Int, baseLine: Int, bitmap: String, glyphs table: String) {
        self.bpp = bpp
        self.lineHeight = CGFloat(lineHeight)
        self.baseLine = CGFloat(baseLine)
        self.bitmap = Array(Data(base64Encoded: bitmap) ?? Data())
        let entries = Array(Data(base64Encoded: table) ?? Data())
        func int32(_ offset: Int) -> Int {
            Int(Int32(bitPattern: entries[offset..<offset + 4].reversed().reduce(0) { $0 << 8 | UInt32($1) }))
        }
        for entry in stride(from: 0, to: entries.count - 27, by: 28) {
            glyphs[UInt32(int32(entry))] = Glyph(
                bitmapIndex: int32(entry + 4), advance: CGFloat((int32(entry + 8) + 8) >> 4),
                width: int32(entry + 12), height: int32(entry + 16), offsetX: int32(entry + 20),
                offsetY: int32(entry + 24))
        }
    }

    func width(_ text: String, letterSpace: CGFloat = 0) -> CGFloat {
        let advances = text.unicodeScalars.compactMap { glyphs[$0.value]?.advance }
        return advances.reduce(0, +) + letterSpace * CGFloat(max(advances.count - 1, 0))
    }

    /// Draws `text` with its line's top-left at `origin`, in a flipped view.
    func draw(_ text: String, at origin: NSPoint, _ color: NSColor, letterSpace: CGFloat = 0) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let baseline = origin.y + lineHeight - baseLine
        var x = origin.x
        context.saveGState()
        context.interpolationQuality = .none
        for scalar in text.unicodeScalars {
            guard let glyph = glyphs[scalar.value] else { continue }
            if let image = image(scalar.value, glyph, color) {
                let top = baseline - CGFloat(glyph.height + glyph.offsetY)
                let rect = CGRect(
                    x: x + CGFloat(glyph.offsetX), y: top, width: CGFloat(glyph.width), height: CGFloat(glyph.height))
                // Images draw bottom-up; flip each into the view's y-down space.
                context.saveGState()
                context.translateBy(x: 0, y: rect.maxY)
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
                context.restoreGState()
            }
            x += glyph.advance + letterSpace
        }
        context.restoreGState()
    }

    /// Draws `text` like an LVGL label of `rect`'s size with centred text: across the middle, from
    /// the top.
    func draw(_ text: String, centredAcross rect: NSRect, _ color: NSColor, letterSpace: CGFloat = 0) {
        let width = self.width(text, letterSpace: letterSpace)
        draw(
            text, at: NSPoint(x: rect.minX + ((rect.width - width) / 2).rounded(.down), y: rect.minY), color,
            letterSpace: letterSpace)
    }

    /// The glyph's coverage as an image in `color`, cached per colour.
    private func image(_ codePoint: UInt32, _ glyph: Glyph, _ color: NSColor) -> CGImage? {
        guard glyph.width > 0, glyph.height > 0, let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let key = "\(codePoint)/\(rgb.redComponent)/\(rgb.greenComponent)/\(rgb.blueComponent)"
        if let cached = images[key] { return cached }

        let levels = CGFloat((1 << bpp) - 1)
        var pixels = [UInt8](repeating: 0, count: glyph.width * glyph.height * 4)
        for i in 0..<glyph.width * glyph.height {
            let bit = glyph.bitmapIndex * 8 + i * bpp
            guard bit / 8 < bitmap.count else { break }
            let value = Int(bitmap[bit / 8]) >> (8 - bpp - bit % 8) & ((1 << bpp) - 1)
            let alpha = CGFloat(value) / levels
            // Premultiplied RGBA.
            pixels[i * 4] = UInt8(rgb.redComponent * alpha * 255)
            pixels[i * 4 + 1] = UInt8(rgb.greenComponent * alpha * 255)
            pixels[i * 4 + 2] = UInt8(rgb.blueComponent * alpha * 255)
            pixels[i * 4 + 3] = UInt8(alpha * 255)
        }
        guard
            let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: glyph.width, height: glyph.height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: glyph.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        images[key] = image
        return image
    }
}
