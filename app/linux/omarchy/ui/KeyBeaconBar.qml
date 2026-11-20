import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// Bar widget: a keyboard glyph and the active layer's name; a click opens the keyboard's
// details. Settings (shell.json layout entry): showLayer (default true), lowBattery (15).
BarWidget {
    id: root
    moduleName: "dev.totem.keybeacon"

    readonly property var kb: KeyBeaconState
    property bool opened: false
    property bool popoutSwitchClosing: false
    // KeyboardPanel and the bar's one-popup coordinator close the panel through these.
    function close() { opened = false }
    function closeForPopoutSwitch() { popoutSwitchClosing = true; close() }
    readonly property bool lowBattery: kb.lowestBattery !== null && kb.lowestBattery <= setting("lowBattery", 15)

    readonly property string label: {
        if (!kb.connected || !setting("showLayer", true)) return ""
        var parts = []
        if (kb.state.capsLock) parts.push("⇪")
        parts.push(kb.layerName)
        if (lowBattery) parts.push(kb.lowestBattery + "%")
        return parts.join(" ")
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        // nf-md-keyboard / nf-md-keyboard_off
        text: root.kb.connected ? "󰌌" : "󰌐"
        labelText: root.vertical ? "" : root.label
        // The slot is fixed-width; widen it to fit the label, as the power widget does.
        slotSize: Style.bar.iconSlot + (labelText ? labelMetrics.advanceWidth + Style.space(4) + Style.spacing.md : 0)
        tooltipText: ""
        opacity: root.kb.connected ? 1 : 0.5
        useActiveColor: false
        active: root.opened
        onPressed: b => {
            if (b !== Qt.LeftButton) return
            root.popoutSwitchClosing = false
            root.opened = !root.opened
        }
    }

    TextMetrics {
        id: labelMetrics
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        text: button.labelText
    }

    KeyboardPanel {
        id: popup
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.opened
        popoutSwitchClosing: root.popoutSwitchClosing
        contentWidth: Style.space(300)
        contentHeight: popover.implicitHeight
        Popover {
            id: popover
            anchors.left: parent.left
            anchors.right: parent.right
            kb: root.kb
        }
    }
}
