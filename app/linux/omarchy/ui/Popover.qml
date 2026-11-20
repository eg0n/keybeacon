import QtQuick
import qs.Ui
import qs.Commons
import qs.Commons as Commons

// The keyboard's details: where it types, its layers, batteries, profiles and modifiers.
Column {
    id: root

    required property var kb
    readonly property var st: kb.state
    readonly property color fg: Commons.Color.popups.text
    readonly property color dim: Qt.darker(fg, 1.6)
    readonly property color accent: Commons.Color.accent

    spacing: Style.spacing.rowGap

    function keyboardName() {
        return (st.name || "Keyboard").replace(/^ZMK Project /, "")
    }

    function whereTyping() {
        if (kb.output === "usb") return "USB · typing here"
        if (kb.output === "ble") {
            var n = kb.profile ? kb.profile.index : 0
            return "Bluetooth" + (n ? " · profile " + n : "")
        }
        return "Connected"
    }

    function percent(v) {
        return typeof v === "number" ? v + "%" : "—"
    }

    PanelHero {
        iconComponent: Component {
            Text {
                text: root.kb.connected ? "󰌌" : "󰌐"
                color: root.fg
                font.family: Style.font.family
                font.pixelSize: Style.font.display
            }
        }
        title: root.kb.connected ? root.keyboardName() : "No keyboard"
        meta: {
            if (root.kb.connected) return root.whereTyping()
            if (root.kb.permissionDenied) return "No access to " + root.st.device + ": run install.sh"
            if (root.st.error === "helper") return "kbp-hidraw stopped; restarting"
            return "Plug in a KeyBeacon keyboard or dongle"
        }
    }

    // Layers: every name the keyboard reported, the active one highlighted.
    PanelSectionHeader {
        visible: root.kb.connected
        text: "LAYER"
    }
    Flow {
        visible: root.kb.connected
        width: root.width
        spacing: Style.spacing.sm
        Repeater {
            model: root.kb.layers.length ? root.kb.layers : [root.kb.layerName]
            delegate: Rectangle {
                required property var modelData
                required property int index
                readonly property bool current: root.kb.layers.length ? index === root.st.layer : true
                width: name.implicitWidth + Style.spacing.controlPaddingX * 2
                height: Style.spacing.controlHeight - Style.spacing.md
                radius: Style.spacing.xs
                color: current ? Style.selectedFillFor(root.fg, root.accent) : "transparent"
                border.width: current ? 0 : 1
                border.color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.2)
                Text {
                    id: name
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: modelData || ("L" + index)
                    color: parent.current ? root.accent : root.dim
                    font.family: Style.font.family
                    font.pixelSize: Style.font.bodySmall
                    font.bold: parent.current
                }
            }
        }
    }

    // Batteries: each half's, or the keyboard's one level; a half that is offline says so.
    PanelSectionHeader {
        visible: root.kb.connected && !!root.kb.battery
        text: "BATTERY"
    }
    Row {
        visible: root.kb.connected && !!root.kb.battery
        spacing: Style.spacing.huge
        Repeater {
            model: {
                var b = root.kb.battery
                if (!b) return []
                if ("overall" in b) return [{ side: "", level: b.overall, online: true, charging: root.st.charging && root.st.charging.left }]
                var h = root.kb.halves
                var c = root.st.charging || {}
                return [
                    { side: "Left", level: b.left, online: !h || h.left, charging: c.left },
                    { side: "Right", level: b.right, online: !h || h.right, charging: c.right }
                ]
            }
            delegate: Text {
                required property var modelData
                textFormat: Text.PlainText
                text: (modelData.side ? modelData.side + " " : "")
                    + (modelData.online ? root.percent(modelData.level) : "offline")
                    + (modelData.charging ? " 󱐋" : "")
                color: modelData.online && typeof modelData.level === "number" && modelData.level <= 15
                    ? Commons.Color.urgent : (modelData.online ? root.fg : root.dim)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
        }
    }

    // Profiles: the active one filled; outlined if paired, dimmed if it has no host yet.
    PanelSectionHeader {
        visible: root.kb.connected && !!root.kb.profile
        text: "PROFILES"
    }
    Row {
        visible: root.kb.connected && !!root.kb.profile
        spacing: Style.spacing.lg
        Repeater {
            model: root.kb.profile ? root.kb.profile.slots : 0
            delegate: Rectangle {
                required property int index
                readonly property bool active: index + 1 === root.kb.profile.index
                readonly property bool open: typeof root.st.openProfiles === "number"
                    ? !!(root.st.openProfiles & (1 << index)) : (active && root.kb.profile.open)
                width: Style.space(12)
                height: width
                radius: width / 2
                color: active && root.kb.output === "ble" ? root.accent : "transparent"
                border.width: Math.max(1, Style.space(1.5))
                border.color: active ? root.accent : (open ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.25) : root.fg)
            }
        }
    }

    // Modifiers held, Caps Lock / Caps Word, and typing speed.
    PanelSectionHeader {
        visible: root.kb.connected
        text: "INPUT"
    }
    Row {
        visible: root.kb.connected
        spacing: Style.spacing.lg
        Repeater {
            // Report bits: left and right of each modifier.
            model: [
                { label: "Shift", mask: 0x22 }, { label: "Ctrl", mask: 0x11 },
                { label: "Alt", mask: 0x44 }, { label: "Super", mask: 0x88 }
            ]
            delegate: Text {
                required property var modelData
                textFormat: Text.PlainText
                text: modelData.label
                color: root.kb.mods & modelData.mask ? root.accent : root.dim
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                font.bold: !!(root.kb.mods & modelData.mask)
            }
        }
    }
    Text {
        visible: root.kb.connected && text !== ""
        textFormat: Text.PlainText
        text: {
            var parts = []
            if (root.st.capsLock) parts.push("Caps Lock")
            if (root.st.capsWord) parts.push("Caps Word")
            if (root.st.wpm > 0) parts.push(root.st.wpm + " WPM")
            return parts.join(" · ")
        }
        color: root.fg
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }
}
