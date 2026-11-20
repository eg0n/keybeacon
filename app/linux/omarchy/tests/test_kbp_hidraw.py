# Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
# SPDX-License-Identifier: MIT
"""Tests for kbp-hidraw's decoders and device discovery: python3 -m unittest discover tests"""

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
_loader = importlib.machinery.SourceFileLoader("kbp_hidraw", os.path.join(HERE, "..", "kbp-hidraw"))
_spec = importlib.util.spec_from_loader("kbp_hidraw", _loader)
kbp = importlib.util.module_from_spec(_spec)
_loader.exec_module(kbp)


def report(report_id, data, with_id=True):
    body = bytes([len(data)]) + bytes(data)
    body += bytes(kbp.REPORT_LEN - 1 - len(body))
    return (bytes([report_id]) if with_id else b"") + body


class PayloadTest(unittest.TestCase):
    def test_with_and_without_report_id(self):
        self.assertEqual(kbp.payload(report(2, [1, 2, 3]), 2), b"\x01\x02\x03")
        self.assertEqual(kbp.payload(report(2, [1, 2, 3], with_id=False), 2), b"\x01\x02\x03")

    def test_length_past_the_body_is_rejected(self):
        self.assertIsNone(kbp.payload(bytes([4, 20, 1]), 4))
        self.assertIsNone(kbp.payload(b"", 4))


class DecoderTest(unittest.TestCase):
    def test_status(self):
        self.assertEqual(
            kbp.parse_status(b"\x02\x22NAV"), {"layer": 2, "layerName": "NAV", "mods": 0x22}
        )
        self.assertEqual(kbp.parse_status(b"\x03\x00")["layerName"], "L3")
        self.assertIsNone(kbp.parse_status(b"\x01"))

    def test_connectivity_dongle(self):
        # Split dongle: host, profile 2 of 4, both halves, BLE output, profiles 3 and 4 open.
        got = kbp.parse_connectivity(bytes([0x1F, 0x01, 0x02, 4, 0x03, 2, 0, 0b1100]))
        self.assertEqual(
            got,
            {
                "split": True,
                "output": "ble",
                "hostConnected": True,
                "profile": {"index": 2, "open": False, "slots": 4},
                "halves": {"left": True, "right": True},
                "openProfiles": 0b1100,
            },
        )

    def test_connectivity_seven_bytes_and_clamped_profile(self):
        got = kbp.parse_connectivity(bytes([0x04, 0, 0x89, 4, 0, 0, 0]))
        self.assertEqual(got["profile"], {"index": 4, "open": True, "slots": 4})
        self.assertNotIn("openProfiles", got)
        self.assertEqual(got["output"], "unknown")
        self.assertIsNone(kbp.parse_connectivity(bytes(6)))

    def test_battery(self):
        self.assertEqual(kbp.parse_battery(bytes([80, 255]), True), {"left": 80, "right": None})
        self.assertEqual(kbp.parse_battery(bytes([150]), False), {"overall": None})
        self.assertIsNone(kbp.parse_battery(bytes([80]), True))

    def test_activity(self):
        self.assertEqual(
            kbp.parse_activity(bytes([42, 7, 0x03])),
            {"wpm": 42, "layerCount": 7, "capsWord": True, "capsLock": True},
        )
        self.assertEqual(kbp.parse_activity(bytes([255, 7]))["wpm"], None)
        self.assertIsNone(kbp.parse_activity(bytes([1])))

    def test_layer_name(self):
        self.assertEqual(kbp.parse_layer_name(b"\x01\x07NAV\x00\x00"), (1, "NAV"))
        # A name cut inside a UTF-8 sequence loses that sequence.
        self.assertEqual(kbp.parse_layer_name(b"\x00\x07ab\xe2\x82"), (0, "ab"))
        self.assertIsNone(kbp.parse_layer_name(b"\x00"))


class KeyboardTest(unittest.TestCase):
    def test_battery_waits_for_connectivity(self):
        kb = kbp.Keyboard("/dev/hidraw2", "TOTEM")
        kb.apply(kbp.BATTERY, bytes([80, 90]))
        self.assertNotIn("battery", kb.state)
        kb.apply(kbp.CONNECTIVITY, bytes([0x09, 0, 0, 0, 0x01, 0, 0]))
        kb.apply(kbp.BATTERY, bytes([80, 90]))
        self.assertEqual(kb.state["battery"], {"left": 80, "right": 90})
        self.assertEqual(kb.state["halves"], {"left": True, "right": False})

    def test_bad_payloads_change_nothing(self):
        kb = kbp.Keyboard("/dev/hidraw2", "TOTEM")
        before = dict(kb.state)
        kb.apply(kbp.STATUS, None)
        kb.apply(kbp.STATUS, b"\x01")
        kb.apply(9, b"\x01\x02")
        self.assertEqual(kb.state, before)


DEV = "/org/bluez/hci0/dev_E1_C5_9D_47_45_5B"
AA2 = bytes([0x1F, 0, 0x82, 4, 3, 1, 0, 14])


def bluez(connected=True, aa4=True):
    """BlueZ's GetManagedObjects as busctl --json=short gives it: variants are {type, data}."""

    def char(uuid):
        return {"org.bluez.GattCharacteristic1": {"UUID": {"type": "s", "data": uuid}}}

    objects = {
        DEV: {"org.bluez.Device1": {"Connected": {"type": "b", "data": connected}}},
        DEV + "/service0032/char0036": char(kbp.AA2_UUID),
    }
    if aa4:
        objects[DEV + "/service0032/char003c"] = char(kbp.AA4_UUID)
    return objects


class ThisProfileTest(unittest.TestCase):
    def reader(self, aa2=AA2, aa4=b"\x01"):
        values = {DEV + "/service0032/char0036": aa2, DEV + "/service0032/char003c": aa4}
        return lambda path: values.get(path)

    def test_matching_keyboard_gives_its_slot(self):
        self.assertEqual(kbp.find_this_profile(bluez(), self.reader(), AA2), 1)

    def test_another_keyboard_or_a_stale_read_gives_none(self):
        other = bytes([0x1F, 0, 0x81, 4, 3, 2, 0, 12])
        self.assertIsNone(kbp.find_this_profile(bluez(), self.reader(aa2=other), AA2))

    def test_disconnected_unresolved_or_old_firmware_gives_none(self):
        self.assertIsNone(kbp.find_this_profile(bluez(connected=False), self.reader(), AA2))
        self.assertIsNone(kbp.find_this_profile(bluez(), self.reader(aa4=b"\x00"), AA2))
        self.assertIsNone(kbp.find_this_profile(bluez(aa4=False), self.reader(), AA2))
        self.assertIsNone(kbp.find_this_profile({}, self.reader(), AA2))

    def test_keyboard_state(self):
        kb = kbp.Keyboard("/dev/hidraw2", "TOTEM")
        kb.refresh_this_profile(bluez(), self.reader())
        self.assertNotIn("thisProfile", kb.state)  # no AA2 from USB yet
        kb.apply(kbp.CONNECTIVITY, AA2)
        kb.refresh_this_profile(bluez(), self.reader())
        self.assertEqual(kb.state["thisProfile"], 1)
        kb.refresh_this_profile(bluez(connected=False), self.reader())
        self.assertNotIn("thisProfile", kb.state)


class FindDeviceTest(unittest.TestCase):
    def make(self, root, node, descriptor, name):
        base = os.path.join(root, node, "device")
        os.makedirs(base)
        with open(os.path.join(base, "report_descriptor"), "wb") as f:
            f.write(descriptor)
        with open(os.path.join(base, "uevent"), "w") as f:
            f.write(f"DRIVER=hid-generic\nHID_NAME={name}\n")

    def test_finds_only_the_kbp_interface(self):
        with tempfile.TemporaryDirectory() as root:
            self.make(root, "hidraw1", b"\x05\x01\x09\x06\xa1\x01", "ZMK Project TOTEM")
            self.make(root, "hidraw2", b"\x06\xaa\xff\x09\x44\xa1\x01", "ZMK Project TOTEM")
            self.assertEqual(kbp.find_device(root), ("/dev/hidraw2", "ZMK Project TOTEM"))

    def test_none_without_one(self):
        with tempfile.TemporaryDirectory() as root:
            self.make(root, "hidraw0", b"\x05\x01\x09\x02", "touchpad")
            self.assertIsNone(kbp.find_device(root))
            self.assertIsNone(kbp.find_device(os.path.join(root, "missing")))


if __name__ == "__main__":
    unittest.main()
