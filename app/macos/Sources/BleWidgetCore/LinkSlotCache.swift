// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// The last Link-slot (`AA4`) read on the current connection, and when. AA4 has no notify, so a
/// changed slot shows only on a re-read; `reset()` on disconnect keeps a stale "in use here" from
/// outliving a re-pair. Matches the Windows `LinkSlotCache`.
public struct LinkSlotCache: Equatable {

    /// The most recently read Link-slot, or `nil` if never read this session.
    public private(set) var slot: LinkSlot?

    /// Wall-clock instant the current `slot` was last (re-)read, or `nil`.
    public private(set) var learnedAt: Date?

    public init() {}

    /// Records a read; `nil` (a failed read) keeps the slot learned before. True only when a known slot
    /// changed, not on the first read, so `hostlink.read_back_slot` logs real changes.
    @discardableResult
    public mutating func learn(_ newSlot: LinkSlot?, at now: Date) -> Bool {
        guard let newSlot else { return false }
        let hadPrevious = slot != nil
        let previousSlot = slot?.slot
        slot = newSlot
        learnedAt = now
        return hadPrevious && previousSlot != newSlot.slot
    }

    /// Forget the learned slot (connection dropped / keyboard switched).
    public mutating func reset() {
        slot = nil
        learnedAt = nil
    }
}
