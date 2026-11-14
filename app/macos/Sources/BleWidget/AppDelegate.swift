// Copyright (c) 2026 The TOTEM ZMK Contributors
// SPDX-License-Identifier: MIT

import AppKit
import BleWidgetCore
import BleWidgetScreens

final class AppDelegate: NSObject, NSApplicationDelegate, BLEClientDelegate {
    private var statusItem: NSStatusItem!
    private var panel: FloatingPanel!
    private let client = BLEClient()
    // A keyboard on USB (KBP over USB HID) takes precedence over BLE while attached.
    private let usbClient = USBHIDClient()
    private var usbActive = false
    private var state: BLEConnectionState = .connecting
    private var activeKeyboard: CompatibleKeyboard?
    private var candidates: [CompatibleKeyboard] = []
    private var unsupportedKeyboards: [CompatibleKeyboard] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        AppSettings().migrateIfNeeded()

        // Resolve the persisted language preference once, before any UI string
        // is built (FR-002 / FR-004).
        L10n.currentLanguage = AppSettings().resolvedLanguage

        panel = FloatingPanel()
        if AppSettings().panelVisible {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }

        statusItem = NSStatusBar.system.statusItem(
            withLength: NSStatusItem.variableLength
        )
        updateMenuBarIcon()
        buildMenu()

        client.delegate = self
        client.start()
        usbClient.delegate = self
        usbClient.start()
    }

    private func buildMenu() {
        let menu = NSMenu()
        let headerTitle: String
        if let active = activeKeyboard {
            headerTitle = active.displayName
        } else if !unsupportedKeyboards.isEmpty {
            headerTitle = L10n.text("Header_Unsupported")
        } else {
            headerTitle = L10n.text("Header_NoKeyboard")
        }
        let header = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if activeKeyboard == nil, !unsupportedKeyboards.isEmpty {
            let names = unsupportedKeyboards.map { $0.displayName }.joined(separator: ", ")
            let info = NSMenuItem(
                title: L10n.format("Info_UnsupportedNames", names),
                action: nil, keyEquivalent: ""
            )
            info.isEnabled = false
            menu.addItem(info)
        }
        menu.addItem(.separator())

        let chooser = NSMenuItem(title: L10n.text("Menu_Keyboard"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if candidates.isEmpty {
            let none = NSMenuItem(title: L10n.text("Menu_NoKeyboards"), action: nil, keyEquivalent: "")
            none.isEnabled = false
            submenu.addItem(none)
        } else {
            for keyboard in candidates {
                let item = NSMenuItem(
                    title: keyboard.displayName,
                    action: #selector(selectKeyboard(_:)), keyEquivalent: ""
                )
                item.target = self
                item.representedObject = keyboard.identifier
                item.state = keyboard.identifier == activeKeyboard?.identifier ? .on : .off
                submenu.addItem(item)
            }
        }
        chooser.submenu = submenu
        menu.addItem(chooser)
        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(title: L10n.text("Menu_Reconnect"), action: #selector(reconnect), keyEquivalent: "r")
        )

        menu.addItem(.separator())
        // "Display mode" submenu: the full card, the compact strip, then every registered screen.
        let modeChooser = NSMenuItem(title: L10n.text("Menu_DisplayMode"), action: nil, keyEquivalent: "")
        let modeSubmenu = NSMenu()
        let currentMode = panel.displayMode
        let screens = ScreenRegistry.all.map { (DisplayMode.screen($0.id), $0.displayName) }
        for (mode, title) in DisplayMode.builtIn.map({ ($0, $0.displayName) }) + screens {
            let item = NSMenuItem(
                title: title,
                action: #selector(setDisplayMode(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            item.state = (currentMode == mode) ? .on : .off
            modeSubmenu.addItem(item)
        }
        modeChooser.submenu = modeSubmenu
        menu.addItem(modeChooser)
        menu.addItem(panelMenuItem())
        // "Language" submenu — 跟随系统 / 中文 / English (FR-005 / FR-012).
        let languageChooser = NSMenuItem(title: L10n.text("Menu_Language"), action: nil, keyEquivalent: "")
        let languageSubmenu = NSMenu()
        let currentPreference = AppSettings().languagePreference
        for preference in LanguagePreference.allCases {
            let item = NSMenuItem(
                title: preference.displayName,
                action: #selector(setLanguage(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preference.rawValue
            item.state = (currentPreference == preference) ? .on : .off
            languageSubmenu.addItem(item)
        }
        languageChooser.submenu = languageSubmenu
        menu.addItem(languageChooser)

        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(title: L10n.text("Menu_Quit"), action: #selector(quit), keyEquivalent: "q")
        )
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    private func updateMenuBarIcon() {
        let symbol: String
        let fallback: String
        switch state {
        case .connected:
            symbol = "keyboard"
            fallback = "⌨︎"
        case .connecting:
            symbol = "keyboard.badge.ellipsis"
            fallback = "⌨…"
        case .notConnected:
            symbol = "keyboard.slash"
            fallback = "⌨✕"
        case .unavailable:
            symbol = "bolt.slash"
            fallback = "⚡︎✕"
        }
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            button.image = image
            button.title = ""
        } else {
            button.image = nil
            button.title = fallback
        }
    }

    @objc private func reconnect() {
        client.start()
        usbClient.start()
    }

    /// The panel's settings, in sections: whether it shows, which layer it sits in (above windows
    /// or on the desktop), where (anywhere, or pinned to a corner), and whether it takes clicks.
    private func panelMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        func header(_ key: String) -> NSMenuItem {
            if #available(macOS 14.0, *) {
                return .sectionHeader(title: L10n.text(key))
            }
            let item = NSMenuItem(title: L10n.text(key), action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        }
        func choice(_ key: String, _ action: Selector, _ value: Any?, on: Bool) -> NSMenuItem {
            let item = NSMenuItem(title: L10n.text(key), action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = on ? .on : .off
            return item
        }

        submenu.addItem(choice("Menu_ShowPanel", #selector(togglePanelVisible), nil, on: AppSettings().panelVisible))

        submenu.addItem(.separator())
        submenu.addItem(header("Menu_Layer"))
        submenu.addItem(choice("Menu_AboveWindows", #selector(setOnDesktop(_:)), false, on: !panel.isOnDesktop))
        submenu.addItem(choice("Menu_OnDesktop", #selector(setOnDesktop(_:)), true, on: panel.isOnDesktop))

        // A pinned panel stays in its corner of whichever screen it is on.
        submenu.addItem(.separator())
        submenu.addItem(header("Menu_Position"))
        let pinned = panel.pinnedCorner
        submenu.addItem(choice("Menu_PinOff", #selector(setPinOff), nil, on: pinned == nil))
        for corner in PinnedCorner.allCases {
            let item = choice("Menu_PinOff", #selector(setPinCorner(_:)), corner.rawValue, on: pinned == corner)
            item.title = corner.displayName
            submenu.addItem(item)
        }

        submenu.addItem(.separator())
        let lock = choice("Menu_Lock", #selector(toggleLock), nil, on: panel.isLocked)
        lock.keyEquivalent = "l"
        submenu.addItem(lock)

        let item = NSMenuItem(title: L10n.text("Menu_Panel"), action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }

    @objc private func toggleLock() {
        panel.isLocked.toggle()
        buildMenu()
    }

    @objc private func setOnDesktop(_ sender: NSMenuItem) {
        guard let onDesktop = sender.representedObject as? Bool else { return }
        panel.isOnDesktop = onDesktop
        buildMenu()
    }

    @objc private func togglePanelVisible() {
        let settings = AppSettings()
        let next = !settings.panelVisible
        settings.panelVisible = next
        if next {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
        buildMenu()
    }

    @objc private func setPinOff() {
        panel.pinnedCorner = nil
        buildMenu()
    }

    @objc private func setPinCorner(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let corner = PinnedCorner(rawValue: raw)
        else { return }
        panel.pinnedCorner = corner
        buildMenu()
    }

    @objc private func setDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let mode = DisplayMode(rawValue: raw)
        else { return }
        panel.displayMode = mode
        buildMenu()
    }

    /// Persist the language preference and rebuild every visible surface
    /// immediately — no restart (FR-003 / FR-011).
    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let pref = LanguagePreference(rawValue: raw)
        else { return }
        let settings = AppSettings()
        settings.languagePreference = pref
        L10n.currentLanguage = settings.resolvedLanguage
        panel.applyLanguage()
        buildMenu()
    }

    @objc private func selectKeyboard(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        client.select(id)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func bleClient(_ client: BLEClient, didUpdate status: KeyboardStatus) {
        guard !usbActive else { return }
        panel.update(status)
    }

    func bleClient(_ client: BLEClient, didChangeState newState: BLEConnectionState) {
        guard !usbActive else { return }
        state = newState
        updateMenuBarIcon()
        if newState != .connected {
            panel.update(.disconnected)
            panel.markConnectivityStaleOnDisconnect()
        }
    }

    func bleClient(_ client: BLEClient, didChangeActiveKeyboard keyboard: CompatibleKeyboard?) {
        guard !usbActive else { return }
        activeKeyboard = keyboard
        if keyboard != nil { unsupportedKeyboards = [] }
        statusItem.button?.toolTip = keyboard?.displayName
        buildMenu()
    }

    func bleClient(_ client: BLEClient, didUpdateCandidates keyboards: [CompatibleKeyboard]) {
        candidates = keyboards
        if !keyboards.isEmpty { unsupportedKeyboards = [] }
        buildMenu()
    }

    func bleClient(_ client: BLEClient, didDetectUnsupported keyboards: [CompatibleKeyboard]) {
        unsupportedKeyboards = keyboards
        statusItem.button?.toolTip = L10n.text("Tip_Unsupported")
        buildMenu()
    }

    func bleClient(_ client: BLEClient, didDetermineKBPMinor minor: KBPMinor) {
        guard !usbActive else { return }
        applyMinor(minor)
    }

    // IV-X1 / U-5: hide the entire 1.1 card when the keyboard is KBP 1.0.
    private func applyMinor(_ minor: KBPMinor) {
        switch minor {
        case .onePointZero, .unknown:
            panel.setConnectivityCardVisible(false)
        case .onePointOne:
            panel.setConnectivityCardVisible(true)
        }
    }

    func bleClient(_ client: BLEClient, didUpdateConnectivity status: ConnectivityStatus) {
        guard !usbActive else { return }
        panel.update(connectivity: status)
    }

    func bleClient(_ client: BLEClient, didUpdateBattery status: BatteryStatus) {
        guard !usbActive else { return }
        panel.update(battery: status)
    }

    func bleClient(_ client: BLEClient, didUpdateHostStatus status: LocalHostStatus?) {
        guard !usbActive else { return }
        panel.update(hostStatus: status)
    }

    func bleClient(_ client: BLEClient, didUpdateActivity status: ActivityStatus) {
        guard !usbActive else { return }
        panel.update(activity: status)
    }

    func bleClient(_ client: BLEClient, didReadLayerName layer: LayerName) {
        guard !usbActive else { return }
        panel.update(layerName: layer)
    }
}

extension AppDelegate: USBHIDClientDelegate {
    func usbClient(_ client: USBHIDClient, didAttach keyboard: CompatibleKeyboard, minor: KBPMinor) {
        usbActive = true
        state = .connected
        updateMenuBarIcon()
        activeKeyboard = keyboard
        unsupportedKeyboards = []
        statusItem.button?.toolTip = keyboard.displayName
        applyMinor(minor)
        buildMenu()
    }

    func usbClientDidDetach(_ client: USBHIDClient) {
        usbActive = false
        state = .notConnected
        updateMenuBarIcon()
        activeKeyboard = nil
        statusItem.button?.toolTip = nil
        panel.update(.disconnected)
        panel.markConnectivityStaleOnDisconnect()
        panel.update(hostStatus: nil)
        buildMenu()
        // Back to BLE, which re-reports whatever it is connected to.
        self.client.start()
    }

    func usbClient(_ client: USBHIDClient, didUpdate status: KeyboardStatus) {
        panel.update(status)
    }

    func usbClient(_ client: USBHIDClient, didUpdateConnectivity status: ConnectivityStatus) {
        panel.update(connectivity: status)
    }

    func usbClient(_ client: USBHIDClient, didUpdateBattery status: BatteryStatus) {
        panel.update(battery: status)
    }

    func usbClient(_ client: USBHIDClient, didUpdateHostStatus status: LocalHostStatus?) {
        panel.update(hostStatus: status)
    }

    func usbClient(_ client: USBHIDClient, didUpdateActivity status: ActivityStatus) {
        panel.update(activity: status)
    }

    func usbClient(_ client: USBHIDClient, didReadLayerName layer: LayerName) {
        panel.update(layerName: layer)
    }
}
