// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// KBP 1.3 Activity payload (`AA440AA5-…`, USB report 4): `[wpm, layer_count]`.
public struct ActivityStatus: Equatable {
    /// Words per minute; `nil` when the keyboard computes none (raw 255).
    public let wpm: UInt8?
    /// Layers in the keymap; 0 when unknown.
    public let layerCount: UInt8

    public init(wpm: UInt8?, layerCount: UInt8) {
        self.wpm = wpm
        self.layerCount = layerCount
    }

    /// At least 2 bytes; a longer payload's tail is reserved and ignored.
    public static func parse(from data: Data) -> ActivityStatus? {
        guard data.count >= 2 else { return nil }
        let bytes = [UInt8](data.prefix(2))
        return ActivityStatus(wpm: bytes[0] == 255 ? nil : bytes[0], layerCount: bytes[1])
    }
}
