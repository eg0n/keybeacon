// Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
// SPDX-License-Identifier: MIT

import Foundation
import IOKit.hid

public protocol USBHIDClientDelegate: AnyObject {
    func usbClient(_ client: USBHIDClient, didAttach keyboard: CompatibleKeyboard, minor: KBPMinor)
    func usbClientDidDetach(_ client: USBHIDClient)
    func usbClient(_ client: USBHIDClient, didUpdate status: KeyboardStatus)
    func usbClient(_ client: USBHIDClient, didUpdateConnectivity status: ConnectivityStatus)
    func usbClient(_ client: USBHIDClient, didUpdateBattery status: BatteryStatus)
    func usbClient(_ client: USBHIDClient, didUpdateHostStatus status: LocalHostStatus?)
}

/// KBP over USB HID (protocol/README.md §16): the AA1–AA3 payloads on a vendor-defined HID
/// interface, one report ID per characteristic. Feature reports are READs, input reports NOTIFYs.
/// A vendor-defined interface needs no Input Monitoring permission.
public final class USBHIDClient {
    public static let usagePage = 0xFFAA
    public static let usage = 0x44

    public enum Report: UInt8 {
        case status = 1        // AA1
        case connectivity = 2  // AA2
        case battery = 3       // AA3
    }

    /// Report ID plus 15 bytes: the payload's length, the payload, then zeros.
    public static let reportLength = 16

    public weak var delegate: USBHIDClientDelegate?
    public private(set) var activeKeyboard: CompatibleKeyboard?

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: USBHIDClient.reportLength)
    private var capability: CapabilityMatrix?
    private var latestConnectivity: ConnectivityStatus?

    public init() {}

    deinit {
        stop()
        inputBuffer.deallocate()
    }

    public func start() {
        stop()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: USBHIDClient.usagePage,
            kIOHIDDeviceUsageKey: USBHIDClient.usage,
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<USBHIDClient>.fromOpaque(context).takeUnretainedValue().attach(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<USBHIDClient>.fromOpaque(context).takeUnretainedValue().detach(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
    }

    public func stop() {
        if device != nil {
            device = nil
            activeKeyboard = nil
            delegate?.usbClientDidDetach(self)
        }
        if let manager {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        manager = nil
    }

    // MARK: - Device lifecycle

    private func attach(_ device: IOHIDDevice) {
        guard self.device == nil else { return } // one keyboard at a time
        self.device = device
        capability = nil
        latestConnectivity = nil

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(
            device, inputBuffer, USBHIDClient.reportLength,
            { context, _, _, _, reportID, report, length in
                guard let context else { return }
                let data = Data(bytes: report, count: length)
                Unmanaged<USBHIDClient>.fromOpaque(context).takeUnretainedValue()
                    .handle(reportID: UInt8(truncatingIfNeeded: reportID), report: data)
            }, context)

        // AA2 first, so the battery payload's length can be checked against is_split.
        let connectivity = readFeature(.connectivity)
        let battery = readFeature(.battery)
        let status = readFeature(.status)
        let minor: KBPMinor = connectivity != nil ? .onePointOne(hasBattery: battery != nil) : .onePointZero

        let keyboard = CompatibleKeyboard(
            identifier: USBHIDClient.identifier(for: device),
            name: USBHIDClient.stringProperty(device, kIOHIDProductKey),
            state: .connected,
            isCompatible: true
        )
        activeKeyboard = keyboard
        delegate?.usbClient(self, didAttach: keyboard, minor: minor)
        if let connectivity { handle(.connectivity, payload: connectivity) }
        if let battery { handle(.battery, payload: battery) }
        if let status { handle(.status, payload: status) }
    }

    private func detach(_ device: IOHIDDevice) {
        guard let current = self.device, CFEqual(current, device) else { return }
        self.device = nil
        activeKeyboard = nil
        capability = nil
        latestConnectivity = nil
        delegate?.usbClientDidDetach(self)
    }

    private func readFeature(_ report: Report) -> Data? {
        guard let device else { return nil }
        var buffer = [UInt8](repeating: 0, count: USBHIDClient.reportLength)
        var length = CFIndex(buffer.count)
        let result = IOHIDDeviceGetReport(
            device, kIOHIDReportTypeFeature, CFIndex(report.rawValue), &buffer, &length
        )
        guard result == kIOReturnSuccess else { return nil }
        return USBHIDClient.payload(fromReport: Data(buffer.prefix(length)), reportID: report.rawValue)
    }

    // MARK: - Reports

    private func handle(reportID: UInt8, report: Data) {
        guard let kind = Report(rawValue: reportID),
              let payload = USBHIDClient.payload(fromReport: report, reportID: reportID)
        else { return }
        handle(kind, payload: payload)
    }

    private func handle(_ kind: Report, payload: Data) {
        switch kind {
        case .status:
            guard let status = KeyboardStatus.parse(payload) else { return }
            delegate?.usbClient(self, didUpdate: status)
        case .connectivity:
            guard let status = ConnectivityStatus.parse(from: payload) else {
                DiagnosticsLogger.connection.connectivityShortPayload(length: payload.count)
                return
            }
            capability = status.capability
            latestConnectivity = status
            delegate?.usbClient(self, didUpdateConnectivity: status)
            delegate?.usbClient(self, didUpdateHostStatus: USBHIDClient.hostStatus(for: status))
        case .battery:
            let isSplit = capability?.isSplit ?? (payload.count == 2)
            guard let status = BatteryStatus.parse(from: payload, isSplit: isSplit) else {
                DiagnosticsLogger.battery.lengthMismatch(
                    expected: isSplit ? 2 : 1, got: payload.count, isSplit: isSplit
                )
                return
            }
            delegate?.usbClient(self, didUpdateBattery: status)
        }
    }

    /// The payload in a KBP report, which may or may not still carry its report ID byte.
    public static func payload(fromReport report: Data, reportID: UInt8) -> Data? {
        var body = report
        if body.count == reportLength, body.first == reportID {
            body = body.dropFirst()
        }
        guard let length = body.first, Int(length) <= body.count - 1 else { return nil }
        return Data(body.dropFirst().prefix(Int(length)))
    }

    /// The keyboard is plugged into this Mac, so USB output is typing here. BLE output goes to
    /// the active profile's host, which this Mac on USB can't tell apart from another computer
    /// unless it is that profile; the profile slot is shown as elsewhere.
    public static func hostStatus(for connectivity: ConnectivityStatus) -> LocalHostStatus {
        let capability = connectivity.capability
        guard capability.hasOutputEndpoint else { return .cannotDetermine }
        switch connectivity.output {
        case .usb:
            return .inUseHere
        case .ble:
            let profile = connectivity.profile
            guard capability.hasProfile, profile.index != 0, !profile.isOpen else {
                return .cannotDetermine
            }
            return .activeElsewhere(slot: profile.index)
        default:
            return .cannotDetermine
        }
    }

    // MARK: - Identity

    private static func stringProperty(_ device: IOHIDDevice, _ key: String) -> String? {
        IOHIDDeviceGetProperty(device, key as CFString) as? String
    }

    private static func intProperty(_ device: IOHIDDevice, _ key: String) -> Int {
        (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0
    }

    /// A stable identifier from the USB vendor, product and serial number (or location).
    static func identifier(for device: IOHIDDevice) -> UUID {
        let serial = stringProperty(device, kIOHIDSerialNumberKey)
            ?? String(intProperty(device, kIOHIDLocationIDKey))
        let key = "usb:\(intProperty(device, kIOHIDVendorIDKey)):\(intProperty(device, kIOHIDProductIDKey)):\(serial)"
        return stableUUID(for: key)
    }

    static func stableUUID(for key: String) -> UUID {
        // Two FNV-1a 64-bit hashes with different offsets fill the 16 bytes.
        func fnv(_ offset: UInt64) -> UInt64 {
            var hash = offset
            for byte in key.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
            return hash
        }
        let a = fnv(0xcbf29ce484222325), b = fnv(0x84222325cbf29ce4)
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: a >> (8 * UInt64(i)))
            bytes[8 + i] = UInt8(truncatingIfNeeded: b >> (8 * UInt64(i)))
        }
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
