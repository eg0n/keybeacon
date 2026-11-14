// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit

/// A bitmap font from the firmware's LVGL font files (lv_font_fmt_txt), drawn glyph by glyph so
/// text looks as it does on the dongle; scripts/prospector_assets.py generates the data. Layout
/// follows LVGL's: a line's baseline sits `lineHeight - baseLine` below its top, each advance
/// (with kerning against the next character) rounds to whole pixels, and `letterSpace` goes
/// between characters.
final class LVGLFont {
    private struct Glyph {
        let bitmapIndex: Int
        /// In 1/16 px.
        let advance: Int
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
    /// Kerning in 1/16 px, by left and right code point.
    private var kerning: [UInt64: Int] = [:]
    private var images: [String: CGImage] = [:]

    /// `bitmap`, `glyphs` and `kerning` are raw DEFLATE, base64 encoded.
    init(bpp: Int, lineHeight: Int, baseLine: Int, bitmap: String, glyphs table: String, kerning pairs: String) {
        func unpack(_ string: String) -> [UInt8] {
            guard let data = Data(base64Encoded: string), !data.isEmpty,
                let inflated = try? (data as NSData).decompressed(using: .zlib)
            else { return [] }
            return Array(inflated as Data)
        }
        func int(_ bytes: [UInt8], _ offset: Int, _ size: Int) -> Int {
            let raw = bytes[offset..<offset + size].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let shift = 64 - size * 8
            return Int(Int64(bitPattern: raw << shift) >> shift)
        }

        self.bpp = bpp
        self.lineHeight = CGFloat(lineHeight)
        self.baseLine = CGFloat(baseLine)
        self.bitmap = unpack(bitmap)
        let entries = unpack(table)
        for entry in stride(from: 0, to: entries.count - 27, by: 28) {
            glyphs[UInt32(int(entries, entry, 4))] = Glyph(
                bitmapIndex: int(entries, entry + 4, 4), advance: int(entries, entry + 8, 4),
                width: int(entries, entry + 12, 4), height: int(entries, entry + 16, 4),
                offsetX: int(entries, entry + 20, 4), offsetY: int(entries, entry + 24, 4))
        }
        let kerns = unpack(pairs)
        for entry in stride(from: 0, to: kerns.count - 9, by: 10) {
            let key = UInt64(int(kerns, entry, 4)) << 32 | UInt64(int(kerns, entry + 4, 4))
            kerning[key] = int(kerns, entry + 8, 2)
        }
    }

    /// Each drawable character with the pen offset it starts at.
    private func layout(_ text: String, letterSpace: CGFloat) -> (glyphs: [(UInt32, Glyph, CGFloat)], width: CGFloat) {
        let scalars = text.unicodeScalars.map(\.value).filter { glyphs[$0] != nil }
        var placed: [(UInt32, Glyph, CGFloat)] = []
        var x: CGFloat = 0
        for (i, code) in scalars.enumerated() {
            let glyph = glyphs[code]!
            let next = i + 1 < scalars.count ? scalars[i + 1] : 0
            let kern = kerning[UInt64(code) << 32 | UInt64(next)] ?? 0
            placed.append((code, glyph, x))
            x += CGFloat((glyph.advance + kern + 8) >> 4) + letterSpace
        }
        return (placed, max(x - (placed.isEmpty ? 0 : letterSpace), 0))
    }

    func width(_ text: String, letterSpace: CGFloat = 0) -> CGFloat {
        layout(text, letterSpace: letterSpace).width
    }

    /// The label's size: its text's width by one line.
    func size(_ text: String, letterSpace: CGFloat = 0) -> NSSize {
        NSSize(width: width(text, letterSpace: letterSpace), height: lineHeight)
    }

    /// Splits `text` into lines no wider than `width`, like an LV_LABEL_LONG_WRAP label: at spaces,
    /// and inside a word that doesn't fit on a line of its own.
    func wrap(_ text: String, width: CGFloat, letterSpace: CGFloat = 0) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
            let joined = line.isEmpty ? word : line + " " + word
            if self.width(joined, letterSpace: letterSpace) <= width {
                line = joined
                continue
            }
            if !line.isEmpty {
                lines.append(line)
            }
            line = ""
            for character in word {
                if !line.isEmpty, self.width(line + String(character), letterSpace: letterSpace) > width {
                    lines.append(line)
                    line = ""
                }
                line.append(character)
            }
        }
        if !line.isEmpty {
            lines.append(line)
        }
        return lines
    }

    /// Draws `text` with its line's top-left at `origin`, in a flipped view.
    func draw(_ text: String, at origin: NSPoint, _ color: NSColor, letterSpace: CGFloat = 0, alpha: CGFloat = 1) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let baseline = origin.y + lineHeight - baseLine
        context.saveGState()
        context.interpolationQuality = .none
        context.setAlpha(alpha)
        for (code, glyph, x) in layout(text, letterSpace: letterSpace).glyphs {
            guard let image = image(code, glyph, color) else { continue }
            let top = baseline - CGFloat(glyph.height + glyph.offsetY)
            let left = origin.x + x + CGFloat(glyph.offsetX)
            // Images draw bottom-up; flip each into the view's y-down space.
            context.saveGState()
            context.translateBy(x: left, y: top + CGFloat(glyph.height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: glyph.width, height: glyph.height))
            context.restoreGState()
        }
        context.restoreGState()
    }

    /// Like an LVGL label of `rect`'s size with centred text: across the middle, from the top.
    func draw(
        _ text: String, centredAcross rect: NSRect, _ color: NSColor, letterSpace: CGFloat = 0, alpha: CGFloat = 1
    ) {
        let width = self.width(text, letterSpace: letterSpace)
        let x = rect.minX + ((rect.width - width) / 2).rounded(.down)
        draw(text, at: NSPoint(x: x, y: rect.minY), color, letterSpace: letterSpace, alpha: alpha)
    }

    /// Like a content-sized LVGL label aligned LV_ALIGN_CENTER in `rect`.
    func draw(_ text: String, centredIn rect: NSRect, _ color: NSColor, letterSpace: CGFloat = 0, alpha: CGFloat = 1) {
        let size = self.size(text, letterSpace: letterSpace)
        let origin = NSPoint(
            x: rect.minX + ((rect.width - size.width) / 2).rounded(.down),
            y: rect.minY + ((rect.height - size.height) / 2).rounded(.down))
        draw(text, at: origin, color, letterSpace: letterSpace, alpha: alpha)
    }

    /// The glyph's coverage as an image in `color`, cached per colour.
    private func image(_ codePoint: UInt32, _ glyph: Glyph, _ color: NSColor) -> CGImage? {
        guard glyph.width > 0, glyph.height > 0, let rgb = color.usingColorSpace(.sRGB) else { return nil }
        let key = "\(codePoint)/\(rgb.redComponent)/\(rgb.greenComponent)/\(rgb.blueComponent)"
        if let cached = images[key] { return cached }

        let mask = (1 << bpp) - 1
        var pixels = [UInt8](repeating: 0, count: glyph.width * glyph.height * 4)
        for i in 0..<glyph.width * glyph.height {
            let bit = glyph.bitmapIndex * 8 + i * bpp
            guard bit / 8 < bitmap.count else { break }
            let value = Int(bitmap[bit / 8]) >> (8 - bpp - bit % 8) & mask
            let alpha = CGFloat(value) / CGFloat(mask)
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
