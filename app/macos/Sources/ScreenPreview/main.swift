// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

// Renders every registered screen, or the one named, in a few sample states to PNGs:
//   swift run screen-preview [screen-id] [output-dir]
// Each file is <screen-id>-<sample>.png, at 2x.

import AppKit
import BleWidgetCore
import BleWidgetScreens

func sample(_ edit: (inout KeyboardState) -> Void) -> KeyboardState {
    var state = KeyboardState()
    state.connected = true
    state.layerIndex = 0
    state.layerName = "Base"
    state.layerCount = 10
    state.wpm = 0
    state.isSplit = true
    state.left = .init(online: true, battery: 74)
    state.right = .init(online: true, battery: 77)
    state.output = .usb
    state.hostConnected = true
    state.activeProfile = 1
    state.profileCount = 4
    state.openProfiles = [3, 4]
    state.hostStatus = .inUseHere
    edit(&state)
    return state
}

let samples: [(String, KeyboardState)] = [
    (
        "typing",
        sample {
            $0.layerIndex = 4
            $0.layerName = "Nav"
            $0.mods = 0x0A  // Left Shift + Left GUI
            $0.wpm = 63
            $0.capsWord = true
        }
    ),
    ("idle-capslock", sample { $0.capsLock = true }),
    (
        "half-offline",
        sample {
            $0.right = .init(online: false, battery: 77)
            $0.left.battery = 15
            $0.output = .ble
            $0.activeProfile = 2
        }
    ),
    ("disconnected", KeyboardState()),
]

let arguments = Array(CommandLine.arguments.dropFirst())
let only = arguments.first.flatMap { $0.hasPrefix("/") || $0.hasPrefix(".") ? nil : $0 }
let outputDir = URL(fileURLWithPath: arguments.last(where: { $0.hasPrefix("/") || $0.hasPrefix(".") }) ?? ".")
let screens = ScreenRegistry.all.filter { only == nil || $0.id == only }
guard !screens.isEmpty else {
    FileHandle.standardError.write(
        "no screen \(only ?? ""); have: \(ScreenRegistry.all.map { $0.id })\n".data(using: .utf8)!)
    exit(1)
}

_ = NSApplication.shared
for type in screens {
    for (name, state) in samples {
        let view = type.init()
        view.animates = false
        view.frame = NSRect(origin: .zero, size: type.size)
        view.render(state)
        let scale: CGFloat = 2
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(type.size.width * scale),
                pixelsHigh: Int(type.size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { continue }
        rep.size = type.size
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = outputDir.appendingPathComponent("\(type.id)-\(name).png")
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        print(url.path)
    }
}
