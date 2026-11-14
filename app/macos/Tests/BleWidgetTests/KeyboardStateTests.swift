// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import XCTest

@testable import BleWidgetCore

final class KeyboardStateTests: XCTestCase {

    private func connectivity(_ bytes: [UInt8]) -> ConnectivityStatus {
        ConnectivityStatus.parse(from: Data(bytes))!
    }

    func testStatus_FillsLayerAndMods() {
        var store = KeyboardStateStore()
        store.apply(KeyboardStatus.parse(Data([4, 0x22]) + "Nav".data(using: .utf8)!)!)
        XCTAssertTrue(store.state.connected)
        XCTAssertEqual(store.state.layerName, "Nav")
        XCTAssertTrue(store.state.shiftActive)
    }

    func testDisconnectedStatus_ResetsEverything() {
        var store = KeyboardStateStore()
        store.apply(ActivityStatus(wpm: 50, layerCount: 10))
        store.apply(KeyboardStatus.disconnected)
        XCTAssertEqual(store.state, KeyboardState())
    }

    func testStatus_LayerNamesOutlastDisconnect() {
        var store = KeyboardStateStore()
        store.apply(KeyboardStatus.parse(Data([4, 0]) + "Nav".data(using: .utf8)!)!)
        store.apply(KeyboardStatus.parse(Data([0, 0]) + "Base".data(using: .utf8)!)!)
        store.apply(KeyboardStatus.disconnected)
        XCTAssertFalse(store.state.connected)
        XCTAssertEqual(store.state.layerNames, [0: "Base", 4: "Nav"])
    }

    func testLayerName_FillsNamesAndSkipsPastTheEnd() {
        var store = KeyboardStateStore()
        store.apply(LayerName.parse(from: Data([2, 10]) + "Tap".data(using: .utf8)!)!)
        store.apply(LayerName.parse(from: Data([3, 10]))!)
        store.apply(LayerName.parse(from: Data([12, 10]) + "Ghost".data(using: .utf8)!)!)
        XCTAssertEqual(store.state.layerNames, [2: "Tap", 3: "L3"])
    }

    func testConnectivity_DongleLinksOutputAndProfiles() {
        var store = KeyboardStateStore()
        // split + link + profile + output; profile 2 of 4; right half online only; USB; 3 and 4 open
        store.apply(connectivity([0x1F, 0x01, 0x02, 0x04, 0x02, 0x01, 0x00, 0b1100]))
        XCTAssertEqual(store.state.left.online, false)
        XCTAssertEqual(store.state.right.online, true)
        XCTAssertEqual(store.state.output, .usb)
        XCTAssertEqual(store.state.activeProfile, 2)
        XCTAssertEqual(store.state.profileCount, 4)
        XCTAssertEqual(store.state.openProfiles, [3, 4])
    }

    func testConnectivity_ActiveOpenProfileWithoutMask() {
        var store = KeyboardStateStore()
        store.apply(connectivity([0x1F, 0x00, 0x81, 0x04, 0x03, 0x01, 0x00]))
        XCTAssertEqual(store.state.openProfiles, [1])
    }

    func testBattery_SplitAndUnavailable() {
        var store = KeyboardStateStore()
        store.apply(BatteryStatus.parse(from: Data([74, 255]), isSplit: true)!)
        XCTAssertEqual(store.state.left.battery, 74)
        XCTAssertNil(store.state.right.battery)
    }

    func testActivity_ZeroLayerCountIsUnknown() {
        var store = KeyboardStateStore()
        store.apply(ActivityStatus(wpm: nil, layerCount: 0, capsWord: true))
        XCTAssertNil(store.state.layerCount)
        XCTAssertNil(store.state.wpm)
        XCTAssertTrue(store.state.capsWord)
    }

    func testDisplayMode_RawValues() {
        XCTAssertEqual(DisplayMode(rawValue: "screen:abc"), .screen("abc"))
        XCTAssertEqual(DisplayMode.screen("abc").rawValue, "screen:abc")
        XCTAssertEqual(DisplayMode(rawValue: "prospector"), .screen("prospector-operator"))
        XCTAssertNil(DisplayMode(rawValue: "nonsense"))
    }
}
