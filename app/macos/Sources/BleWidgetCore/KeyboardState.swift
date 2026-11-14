// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// Everything known about the keyboard, as one value for screens to draw from. Fields a keyboard
/// doesn't report stay `nil` (or empty), so a screen can leave them out.
public struct KeyboardState: Equatable {
    public struct Half: Equatable {
        /// The half's link to the central; `nil` when the keyboard doesn't report links.
        public var online: Bool?
        /// Battery percent, 0–100; `nil` when unknown.
        public var battery: UInt8?

        public init(online: Bool? = nil, battery: UInt8? = nil) {
            self.online = online
            self.battery = battery
        }
    }

    public var connected = false
    public var layerIndex: UInt8 = 0
    /// The keymap's name for the layer, or "L<index>" when it has none.
    public var layerName = ""
    /// Every layer name seen so far, by index: KBP reports only the active layer's, so screens that
    /// show other layers learn them as they come up.
    public var layerNames: [UInt8: String] = [:]
    /// Held modifiers, in the HID modifier byte's layout (KBP §4.1).
    public var mods: UInt8 = 0
    public var layerCount: UInt8?
    public var wpm: UInt8?
    public var capsWord = false
    public var capsLock = false

    public var isSplit = false
    public var left = Half()
    public var right = Half()
    /// A unibody keyboard's battery percent.
    public var battery: UInt8?

    public var output: ConnectivityStatus.OutputEndpoint?
    /// Whether the active BLE profile's host is connected.
    public var hostConnected: Bool?
    /// The active BLE profile, 1-based; `nil` when not reported.
    public var activeProfile: Int?
    public var profileCount = 0
    /// Profiles (1-based) with no bonded host.
    public var openProfiles: Set<Int> = []
    public var hostStatus: LocalHostStatus?

    public init() {}

    public var shiftActive: Bool { mods & 0x22 != 0 }
    public var controlActive: Bool { mods & 0x11 != 0 }
    public var optionActive: Bool { mods & 0x44 != 0 }
    public var commandActive: Bool { mods & 0x88 != 0 }
}

/// Folds each decoded payload into a `KeyboardState`, the way the panel receives them.
public struct KeyboardStateStore {
    public private(set) var state = KeyboardState()

    public init() {}

    /// Forgets everything but the layer names, which belong to the keymap and outlast a disconnect.
    public mutating func reset() {
        let names = state.layerNames
        state = KeyboardState()
        state.layerNames = names
    }

    public mutating func apply(_ status: KeyboardStatus) {
        guard status.connected else { return reset() }
        state.connected = true
        state.layerIndex = status.layerIndex
        state.layerName = status.layerName
        state.layerNames[status.layerIndex] = status.layerName
        state.mods = status.mods
    }

    public mutating func apply(_ connectivity: ConnectivityStatus) {
        let capability = connectivity.capability
        state.isSplit = capability.isSplit
        if capability.isSplit, capability.hasSplitLink {
            state.left.online = connectivity.splitFlags.leftOnline
            state.right.online = connectivity.splitFlags.rightOnline
        }
        if capability.hasHostConnection {
            state.hostConnected = connectivity.link.connected
        }
        state.output = capability.hasOutputEndpoint ? connectivity.output : nil
        if capability.hasProfile, connectivity.profile.index > 0 {
            let profile = connectivity.profile
            state.activeProfile = Int(min(profile.index, max(profile.maxSlots, 1)))
            state.profileCount = Int(profile.maxSlots)
            var open = Set<Int>()
            if let mask = connectivity.openProfiles {
                for slot in 1...8 where mask & (1 << (slot - 1)) != 0 {
                    open.insert(slot)
                }
            }
            if profile.isOpen {
                open.insert(Int(profile.index))
            }
            state.openProfiles = open
        }
    }

    public mutating func apply(_ battery: BatteryStatus) {
        func percent(_ reading: BatteryStatus.BatteryReading) -> UInt8? {
            if case .percent(let value) = reading { return value }
            return nil
        }
        switch battery.kind {
        case .overall(let reading):
            state.battery = percent(reading)
        case .split(let left, let right):
            state.left.battery = percent(left)
            state.right.battery = percent(right)
        }
    }

    public mutating func apply(_ activity: ActivityStatus) {
        state.wpm = activity.wpm
        state.layerCount = activity.layerCount > 0 ? activity.layerCount : nil
        state.capsWord = activity.capsWord
        state.capsLock = activity.capsLock
    }

    public mutating func apply(hostStatus: LocalHostStatus?) {
        state.hostStatus = hostStatus
    }
}
