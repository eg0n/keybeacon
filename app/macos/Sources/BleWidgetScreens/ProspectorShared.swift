// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore

/// One modifier slot as the Prospector layouts draw it, with the module's defaults: Mac symbols
/// (glyphs in its Symbols fonts) in GACS order, inactive ones dimmed. Shift turns filled during
/// Caps Word, as on the dongle; Caps Lock (which the dongle doesn't show) swaps in the Caps Lock key.
struct ProspectorModifier {
    enum Look {
        case idle, held, capsLock
    }

    let symbol: String
    let look: Look

    static let capsLockColor = NSColor(hex: 0xE5484D)

    static func all(_ state: KeyboardState) -> [ProspectorModifier] {
        let on = state.connected
        func slot(_ symbol: String, _ held: Bool) -> ProspectorModifier {
            ProspectorModifier(symbol: symbol, look: on && held ? .held : .idle)
        }
        let shift: ProspectorModifier
        if on, state.capsLock {
            shift = ProspectorModifier(symbol: ProspectorSymbol.capsLock, look: .capsLock)
        } else if on, state.capsWord {
            shift = ProspectorModifier(symbol: ProspectorSymbol.shiftFilled, look: .held)
        } else {
            shift = slot(ProspectorSymbol.shift, state.shiftActive)
        }
        return [
            slot(ProspectorSymbol.command, state.commandActive), slot(ProspectorSymbol.option, state.optionActive),
            slot(ProspectorSymbol.control, state.controlActive), shift,
        ]
    }

    func color(held: NSColor, idle: NSColor) -> NSColor {
        switch look {
        case .idle: return idle
        case .held: return held
        case .capsLock: return Self.capsLockColor
        }
    }
}

/// The output widget the Classic, Field and Radii layouts share (their output.c): a waves symbol
/// and the BLE profile number, shown while BLE is the output and for 3 s after the output or profile
/// changes. Like the firmware, it numbers profiles from 0.
final class ProfileBadge {
    enum Look {
        /// Connected, and BLE is the output.
        case sending
        case connected
        /// Bonded but not connected: the symbol breathes.
        case searching
        case unpaired
    }

    var animates = true
    /// Called when the badge appears, hides or breathes, to redraw.
    var onChange: (() -> Void)?

    private var state = KeyboardState()
    private var lastOutput: ConnectivityStatus.OutputEndpoint?
    private var lastProfile: Int?
    private var hideAt: Date?
    private var shown = false
    private let timer = FrameTimer()

    var visible: Bool { shown }

    func update(_ state: KeyboardState) {
        self.state = state
        let output = state.connected ? state.output : nil
        let profile = state.connected ? state.activeProfile : nil
        // A change while connected shows the badge; (re)connecting doesn't.
        if animates, lastOutput != nil, output != nil, output != lastOutput || profile != lastProfile {
            hideAt = Date().addingTimeInterval(3)
        }
        lastOutput = output
        lastProfile = profile
        refresh()
    }

    private func refresh() {
        let now = Date()
        if let hideAt, now >= hideAt {
            self.hideAt = nil
        }
        shown = state.connected && state.activeProfile != nil && (state.output == .ble || hideAt != nil)
        guard animates, shown, hideAt != nil || look == .searching else { return timer.stop() }
        timer.start(every: 1.0 / 30) { [weak self] in
            guard let self else { return false }
            let wasShown = self.shown
            self.refresh()
            if wasShown || self.shown {
                self.onChange?()
            }
            return self.timer.isRunning
        }
    }

    var look: Look {
        guard let profile = state.activeProfile else { return .unpaired }
        let open = state.openProfiles.contains(profile)
        // KBP reports the link of the active output only; on USB, take a bonded profile as connected.
        let linked = !open && (state.output == .ble ? state.hostConnected == true : true)
        if linked {
            return state.output == .ble ? .sending : .connected
        }
        return open ? .unpaired : .searching
    }

    var number: String { "\(max((state.activeProfile ?? 1) - 1, 0))" }

    var numberColor: NSColor { look == .sending ? .white : NSColor(hex: 0xA0A0A0) }

    /// Draws the waves symbol in its 30×30 label at `rect`: Symbols Bold 26 and 2 lower while
    /// sending, Regular 28 otherwise, as in output.c.
    func drawWaves(in rect: NSRect) {
        let look = self.look
        let color: NSColor
        switch look {
        case .sending: color = NSColor(hex: 0x00FFFF)
        case .connected: color = NSColor(hex: 0x63C0C0)
        case .searching: color = NSColor(hex: 0xD0D0D0)
        case .unpaired: color = NSColor(hex: 0x454545)
        }
        let sending = look == .sending
        let font = sending ? LVGLFont.symbolsBold26 : LVGLFont.symbolsRegular28
        font.draw(
            ProspectorSymbol.wavesUp, centredAcross: rect.offsetBy(dx: 0, dy: sending ? 2 : 0), color,
            alpha: look == .searching ? breath : 1)
    }

    /// The searching symbol's opacity: 155 to 255 and back each second, eased.
    private var breath: CGFloat {
        guard animates else { return 1 }
        let phase = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
        let t = phase < 0.5 ? phase * 2 : (1 - phase) * 2
        let eased = t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t)
        return (155 + 100 * eased) / 255
    }
}
