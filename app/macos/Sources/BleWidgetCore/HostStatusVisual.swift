// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// Platform-neutral colour for the per-link host status, mapped to `NSColor` or a Windows brush by
/// the UI. The full card and the compact strip both use this one mapping.
public enum HostStatusColor: Equatable {
    case green  // in use on this computer
    case orange  // keyboard active on another computer
    case blue  // keyboard on USB (not this BLE link)
    case gray  // cannot determine
    case red  // disconnected
}

/// Colour and shape for a `LocalHostStatus`; the shape tells states apart without colour (WCAG
/// 1.4.1). Matches the Windows `HostStatusVisual` and the spec 005 host-status-visual contract.
public struct HostStatusVisual: Equatable {

    /// Abstract palette entry (mapped to a real colour by the UI layer).
    public let color: HostStatusColor

    /// A single-glyph shape symbol, drawn alongside the colour for redundancy:
    /// filled ● (in-use), half ◐ (elsewhere), diamond ◆ (USB), hollow ○
    /// (cannot-determine), cross ✕ (disconnected).
    public let symbol: String

    public init(color: HostStatusColor, symbol: String) {
        self.color = color
        self.symbol = symbol
    }
}

/// Green in use here, orange active elsewhere, blue on USB, gray can't tell, red disconnected (an
/// alarm, unlike gray's "unknown").
public func hostStatusVisual(for status: LocalHostStatus) -> HostStatusVisual {
    switch status {
    case .inUseHere:
        return HostStatusVisual(color: .green, symbol: "●")
    case .activeElsewhere:
        return HostStatusVisual(color: .orange, symbol: "◐")
    case .onUsb:
        return HostStatusVisual(color: .blue, symbol: "◆")
    case .cannotDetermine:
        return HostStatusVisual(color: .gray, symbol: "○")
    case .disconnected:
        return HostStatusVisual(color: .red, symbol: "✕")
    }
}
