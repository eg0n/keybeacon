// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// KBP 1.3 Layer Name payload (`AA440AA6-…`, USB feature report 5): `[layer_index, layer_count,
/// name...]` for the layer the host last selected by writing its index. The name is UTF-8 and
/// empty when the keymap gives the layer none (or the index is past the last layer).
public struct LayerName: Equatable {
    public let index: UInt8
    public let layerCount: UInt8
    public let name: String

    public init(index: UInt8, layerCount: UInt8, name: String) {
        self.index = index
        self.layerCount = layerCount
        self.name = name
    }

    /// At least 2 bytes; a name cut inside a UTF-8 sequence loses that sequence.
    public static func parse(from data: Data) -> LayerName? {
        guard data.count >= 2 else { return nil }
        let bytes = [UInt8](data)
        var nameBytes = Array(bytes.dropFirst(2))
        if let nul = nameBytes.firstIndex(of: 0) {
            nameBytes = Array(nameBytes[..<nul])
        }
        while !nameBytes.isEmpty, String(bytes: nameBytes, encoding: .utf8) == nil {
            nameBytes.removeLast()
        }
        return LayerName(
            index: bytes[0], layerCount: bytes[1], name: String(bytes: nameBytes, encoding: .utf8) ?? "")
    }
}
