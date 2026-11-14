// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// KBP 1.3 Activity payload (`AA440AA5-…`, USB report 4): `[wpm, layer_count, flags]`, the
/// flags byte optional (bit 0 Caps Word, bit 1 the host's Caps Lock LED).
public struct ActivityStatus: Equatable {
    /// Words per minute; `nil` when the keyboard computes none (raw 255).
    public let wpm: UInt8?
    /// Layers in the keymap; 0 when unknown.
    public let layerCount: UInt8
    public let capsWord: Bool
    public let capsLock: Bool

    public init(wpm: UInt8?, layerCount: UInt8, capsWord: Bool = false, capsLock: Bool = false) {
        self.wpm = wpm
        self.layerCount = layerCount
        self.capsWord = capsWord
        self.capsLock = capsLock
    }

    /// At least 2 bytes; a longer payload's tail is reserved and ignored.
    public static func parse(from data: Data) -> ActivityStatus? {
        guard data.count >= 2 else { return nil }
        let bytes = [UInt8](data.prefix(3))
        let flags = bytes.count > 2 ? bytes[2] : 0
        return ActivityStatus(
            wpm: bytes[0] == 255 ? nil : bytes[0], layerCount: bytes[1],
            capsWord: flags & 0x01 != 0, capsLock: flags & 0x02 != 0
        )
    }
}
