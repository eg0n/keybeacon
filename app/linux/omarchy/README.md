# KeyBeacon for Omarchy

A bar widget for [Omarchy](https://omarchy.org) 4's Quickshell bar that shows a KeyBeacon
keyboard plugged in over USB (a ZMK keyboard or dongle running `zmk-keybeacon` with
`CONFIG_ZMK_KEYBEACON_USB`): the active layer's name in the bar, and on click its layers, each
half's battery, the profiles, held modifiers, Caps Lock / Caps Word and WPM.

## Install

On the Omarchy machine, from this folder:

```sh
./install.sh
```

It copies the plugin to `~/.config/omarchy/plugins/dev.totem.keybeacon`, enables it on the
right of the bar, and (asking for your password once) installs a udev rule so you can read the
keyboard's KeyBeacon interface. Rerun it to update, then `omarchy restart shell`: the shell
keeps already-loaded plugin QML until it restarts. `./install.sh --uninstall` removes it all.

In `~/.config/omarchy/shell.json`, the widget's layout entry takes `showLayer` (default `true`)
and `lowBattery` (the level, default `15`, at which the bar shows the battery).

## How it works

- `kbp-hidraw` (standard-library Python) finds the hidraw node whose report descriptor starts
  with KeyBeacon's usage page (`0xFFAA`), reads KBP over USB HID (`protocol/README.md` §16–17)
  and prints the whole state as one JSON line per change. It rescans every 2 s while nothing is
  plugged in.
- `ui/KeyBeaconState.qml` runs it once for every bar; `ui/KeyBeaconBar.qml` is the widget and
  `ui/Popover.qml` its panel.
- `udev/70-keybeacon.rules` tags only a node that `udev/keybeacon-hidraw-match` recognises as
  KeyBeacon's for the logged-in user (`uaccess`). The keyboard's own HID interface, which
  carries keystrokes, stays root-only.

Bluetooth isn't supported yet: a keyboard reached over Bluetooth needs BlueZ's GATT API instead.

## Tests

```sh
python3 -m unittest discover -s tests
```
