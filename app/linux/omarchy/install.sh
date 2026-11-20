#!/bin/sh
# Copyright (c) 2026 The TOTEM ZMK Contributors / KeyBeacon Contributors
# SPDX-License-Identifier: MIT
#
# Installs the KeyBeacon bar widget for Omarchy 4: the plugin into ~/.config/omarchy/plugins,
# and (with sudo, once) the udev rule that lets you read a keyboard's KBP interface. Rerun it
# to update. --no-udev skips the rule; --uninstall removes everything it installed.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
id=dev.totem.keybeacon
plugin_dir=${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins/$id
match=/usr/local/libexec/keybeacon-hidraw-match
rule=/etc/udev/rules.d/70-keybeacon.rules
udev=1

for arg in "$@"; do
    case $arg in
        --no-udev) udev=0 ;;
        --uninstall)
            omarchy plugin disable "$id" 2>/dev/null || true
            rm -rf "$plugin_dir"
            sudo rm -f "$rule" "$match"
            sudo udevadm control --reload
            echo "Removed $id and its udev rule."
            exit 0
            ;;
        *) echo "usage: $0 [--no-udev | --uninstall]" >&2; exit 2 ;;
    esac
done

# The plugin: its manifest, QML and helper, without the tests.
rm -rf "$plugin_dir"
mkdir -p "$plugin_dir"
cp -R "$here/manifest.json" "$here/ui" "$here/kbp-hidraw" "$plugin_dir/"
chmod +x "$plugin_dir/kbp-hidraw"
omarchy plugin validate "$plugin_dir"

if [ "$udev" = 1 ]; then
    sudo install -D -m 0755 "$here/udev/keybeacon-hidraw-match" "$match"
    sudo install -D -m 0644 "$here/udev/70-keybeacon.rules" "$rule"
    sudo udevadm control --reload
    # Apply it to a keyboard that is already plugged in.
    sudo udevadm trigger --subsystem-match=hidraw --action=change
fi

omarchy-shell shell rescanPlugins
if ! omarchy plugin list | grep -q "$id.*enabled"; then
    omarchy plugin enable "$id" right
fi
echo "Installed $id. Its bar widget sits on the right; drag it to move it."
