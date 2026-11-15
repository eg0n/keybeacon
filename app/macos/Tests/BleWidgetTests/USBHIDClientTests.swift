// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import XCTest

@testable import BleWidgetCore

final class USBHIDClientTests: XCTestCase {

    // MARK: - Report framing (protocol/README.md §16.3)

    func testPayload_ReportWithID_StripsIDAndLength() {
        var report = [UInt8](repeating: 0, count: 16)
        report[0] = 2
        report[1] = 7
        report.replaceSubrange(2..<9, with: [0x1F, 0x01, 0x82, 0x05, 0x03, 0x02, 0x00])
        let payload = USBHIDClient.payload(fromReport: Data(report), reportID: 2)
        XCTAssertEqual(payload, Data([0x1F, 0x01, 0x82, 0x05, 0x03, 0x02, 0x00]))
    }

    func testPayload_BodyWithoutID_IsAccepted() {
        var body = [UInt8](repeating: 0, count: 15)
        body[0] = 2
        body[1] = 80
        body[2] = 255
        XCTAssertEqual(USBHIDClient.payload(fromReport: Data(body), reportID: 3), Data([80, 255]))
    }

    func testPayload_LengthBeyondReport_ReturnsNil() {
        var report = [UInt8](repeating: 0, count: 16)
        report[0] = 1
        report[1] = 15  // only 14 payload bytes fit
        XCTAssertNil(USBHIDClient.payload(fromReport: Data(report), reportID: 1))
    }

    func testPayload_EmptyReport_ReturnsNil() {
        XCTAssertNil(USBHIDClient.payload(fromReport: Data(), reportID: 1))
    }

    func testPayload_StatusReport_DecodesLayerAndMods() {
        var report = [UInt8](repeating: 0, count: 16)
        report[0] = 1
        report[1] = 5
        report.replaceSubrange(2..<7, with: [0x02, 0x22, 0x53, 0x59, 0x4D])  // SYM, both Shifts
        guard let payload = USBHIDClient.payload(fromReport: Data(report), reportID: 1),
            let status = KeyboardStatus.parse(payload)
        else { return XCTFail("status report must decode") }
        XCTAssertEqual(status.layerName, "SYM")
        XCTAssertTrue(status.shiftActive)
        XCTAssertFalse(status.controlActive)
    }

    // MARK: - Host status over USB

    private func connectivity(profile: UInt8, output: UInt8, capability: UInt8 = 0x1F) -> ConnectivityStatus {
        ConnectivityStatus.parse(from: Data([capability, 0x01, profile, 0x05, 0x03, output, 0x00]))!
    }

    func testHostStatus_UsbOutput_IsInUseHere() {
        XCTAssertEqual(USBHIDClient.hostStatus(for: connectivity(profile: 0x02, output: 1)), .inUseHere)
    }

    func testHostStatus_BleOutput_IsActiveElsewhereOnTheProfile() {
        XCTAssertEqual(
            USBHIDClient.hostStatus(for: connectivity(profile: 0x02, output: 2)),
            .activeElsewhere(slot: 2)
        )
    }

    func testHostStatus_BleOutputOpenProfile_CannotDetermine() {
        XCTAssertEqual(USBHIDClient.hostStatus(for: connectivity(profile: 0x82, output: 2)), .cannotDetermine)
    }

    func testHostStatus_NoOutputCapability_CannotDetermine() {
        XCTAssertEqual(
            USBHIDClient.hostStatus(for: connectivity(profile: 0x02, output: 1, capability: 0x0F)),
            .cannotDetermine
        )
    }

    func testHostStatus_BleLinkInUseHere_OverridesElsewhere() {
        XCTAssertEqual(USBHIDClient.hostStatus(.activeElsewhere(slot: 2), bleLink: .inUseHere), .inUseHere)
    }

    func testHostStatus_BleLinkOnOtherSlot_StaysElsewhere() {
        XCTAssertEqual(
            USBHIDClient.hostStatus(.activeElsewhere(slot: 2), bleLink: .activeElsewhere(slot: 2)),
            .activeElsewhere(slot: 2)
        )
    }

    func testHostStatus_NoBleLink_StaysElsewhere() {
        XCTAssertEqual(USBHIDClient.hostStatus(.activeElsewhere(slot: 2), bleLink: nil), .activeElsewhere(slot: 2))
        XCTAssertEqual(
            USBHIDClient.hostStatus(.activeElsewhere(slot: 2), bleLink: .cannotDetermine),
            .activeElsewhere(slot: 2)
        )
    }

    func testHostStatus_BleLinkNeverOverridesUsbOrUnknown() {
        XCTAssertEqual(USBHIDClient.hostStatus(.inUseHere, bleLink: .activeElsewhere(slot: 1)), .inUseHere)
        XCTAssertEqual(USBHIDClient.hostStatus(.cannotDetermine, bleLink: .inUseHere), .cannotDetermine)
    }

    // MARK: - Identity

    func testStableUUID_IsDeterministicPerKey() {
        XCTAssertEqual(
            USBHIDClient.stableUUID(for: "usb:7504:24926:abc"),
            USBHIDClient.stableUUID(for: "usb:7504:24926:abc"))
        XCTAssertNotEqual(
            USBHIDClient.stableUUID(for: "usb:7504:24926:abc"),
            USBHIDClient.stableUUID(for: "usb:7504:24926:abd"))
    }
}
