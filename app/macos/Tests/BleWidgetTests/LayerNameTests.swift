// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import XCTest

@testable import BleWidgetCore

final class LayerNameTests: XCTestCase {

    func testParse_IndexCountAndName() {
        let layer = LayerName.parse(from: Data([4, 10]) + "Nav".data(using: .utf8)!)
        XCTAssertEqual(layer, LayerName(index: 4, layerCount: 10, name: "Nav"))
    }

    func testParse_EmptyName() {
        XCTAssertEqual(LayerName.parse(from: Data([7, 10]))?.name, "")
    }

    func testParse_TooShort() {
        XCTAssertNil(LayerName.parse(from: Data([1])))
    }

    func testParse_DropsACutUTF8Sequence() {
        // "Nä" with the ä's second byte cut off.
        XCTAssertEqual(LayerName.parse(from: Data([0, 2, 0x4E, 0xC3]))?.name, "N")
    }

    func testParse_StopsAtNUL() {
        XCTAssertEqual(LayerName.parse(from: Data([0, 2, 0x41, 0, 0x42]))?.name, "A")
    }
}
