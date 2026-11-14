// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// Whether the keyboard is in use on this computer, from this connection's Link-slot (`AA4`) and
/// the Connectivity snapshot (`AA2`). Distinct from the transport state: it answers "here or
/// elsewhere", which only a per-connection read can.
public enum LocalHostStatus: Equatable {
    /// The keyboard's active profile maps to *this* connection's slot.
    case inUseHere
    /// The keyboard is active on another host. `slot` is the keyboard's active
    /// profile slot (1-based), displayed as "P{slot}".
    case activeElsewhere(slot: UInt8)
    /// The keyboard is outputting over USB (not this BLE link).
    case onUsb
    /// Not enough positive confirmation to classify: old firmware without
    /// `AA4`, an open/unassigned active profile, or the firmware could not
    /// resolve this connection to a slot.
    case cannotDetermine
    /// The BLE link is down.
    case disconnected
}

/// Derives `LocalHostStatus`, as the Windows `DeriveLocalHostStatus` does. Priority: disconnected >
/// on USB > in use here / active elsewhere > can't tell, and never "here" or "elsewhere" without
/// confirmation. `nil` inputs are fields not read yet; `hasAA4` is whether the keyboard has AA4.
public func deriveLocalHostStatus(
    hasAA4: Bool,
    connected: Bool,
    capability: CapabilityMatrix?,
    activeProfile: ConnectivityStatus.Profile?,
    localSlot: LinkSlot?,
    output: ConnectivityStatus.OutputEndpoint?
) -> LocalHostStatus {
    // 1. disconnected — highest priority (FR-009).
    guard connected else { return .disconnected }

    // 2. on-usb — the keyboard is typing over USB, not this BLE link.
    if let capability, capability.hasOutputEndpoint, let output, output == .usb {
        return .onUsb
    }

    // 3. no AA4 (old firmware) → never fabricate in-use/elsewhere (C-L2, FR-008).
    guard hasAA4 else { return .cannotDetermine }

    // 4. active profile unknown / open / no profile capability.
    guard let capability, capability.hasProfile,
        let activeProfile, activeProfile.index != 0, !activeProfile.isOpen
    else { return .cannotDetermine }

    // 5. firmware could not resolve this connection to a slot.
    guard let localSlot, localSlot.slot != 0 else { return .cannotDetermine }

    // 6. compare the keyboard's active profile to this connection's slot.
    if activeProfile.index == localSlot.slot {
        return .inUseHere
    }
    return .activeElsewhere(slot: activeProfile.index)
}
