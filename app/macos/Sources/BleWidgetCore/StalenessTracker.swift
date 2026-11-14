// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation

/// Per-field staleness of KBP 1.1 values: live while the last notify is within the window (3 s),
/// stale after, when the UI shows the last value as such. Takes timestamps rather than reading a
/// clock and runs no timer, so it tests easily; callers serialise access on the main queue.
public final class StalenessTracker {

    /// How long since the last notify counts as "stale".
    public let stalenessWindow: TimeInterval

    private var lastNotify: [String: TimeInterval] = [:]
    /// Fields explicitly forced stale (e.g., BLE disconnect event). Reset by
    /// a subsequent `recordNotify`.
    private var forcedStale: Set<String> = []

    public init(stalenessWindow: TimeInterval = 3.0) {
        self.stalenessWindow = stalenessWindow
    }

    /// Records a notify for `fieldKey` at monotonic time `at` and clears forced staleness. An older `at`
    /// than already recorded is ignored, so a clock glitch can't make a field stale.
    public func recordNotify(fieldKey: String, at: TimeInterval) {
        if let existing = lastNotify[fieldKey], existing > at {
            // Keep the newer timestamp; still clear forced-stale.
        } else {
            lastNotify[fieldKey] = at
        }
        forcedStale.remove(fieldKey)
    }

    /// Return `true` when `fieldKey` has been forced stale, or when
    /// `now - lastNotify[fieldKey] >= stalenessWindow`. A field that has never
    /// been recorded is treated as **stale** (there is no live reading yet).
    public func isStale(fieldKey: String, now: TimeInterval) -> Bool {
        if forcedStale.contains(fieldKey) { return true }
        guard let last = lastNotify[fieldKey] else { return true }
        return (now - last) >= stalenessWindow
    }

    /// Immediately mark **every** field stale. Called on BLE disconnect so the
    /// UI does not keep showing live values after the link is gone.
    public func forceStaleAll() {
        forcedStale.formUnion(lastNotify.keys)
    }

    /// Immediately mark one field stale (rare — most paths use `forceStaleAll`
    /// on disconnect and `recordNotify` to recover a single field).
    public func forceStale(fieldKey: String) {
        forcedStale.insert(fieldKey)
    }

    /// Return the recorded last-notify timestamp for a field (for diagnostics
    /// / UI "updated hh:mm:ss" labels), or `nil` if never recorded.
    public func lastNotifyAt(fieldKey: String) -> TimeInterval? {
        lastNotify[fieldKey]
    }

    /// All field keys currently tracked. For diagnostics only.
    public var trackedFieldKeys: [String] {
        Array(lastNotify.keys).sorted()
    }

    /// Forget all state. Used only by tests.
    public func reset() {
        lastNotify.removeAll()
        forcedStale.removeAll()
    }
}
