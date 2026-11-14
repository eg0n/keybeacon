// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import XCTest
@testable import BleWidgetCore

final class ActivityStatusTests: XCTestCase {

    func testParse_WpmAndLayerCount() {
        XCTAssertEqual(ActivityStatus.parse(from: Data([63, 10])), ActivityStatus(wpm: 63, layerCount: 10))
    }

    func testParse_255IsNoWpm() {
        XCTAssertEqual(ActivityStatus.parse(from: Data([255, 10]))?.wpm, nil)
    }

    func testParse_ShortPayload_ReturnsNil() {
        XCTAssertNil(ActivityStatus.parse(from: Data([63])))
    }

    func testParse_TailIsIgnored() {
        XCTAssertEqual(ActivityStatus.parse(from: Data([0, 3, 0xAA, 0xBB])), ActivityStatus(wpm: 0, layerCount: 3))
    }
}
