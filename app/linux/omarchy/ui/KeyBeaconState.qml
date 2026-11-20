pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The keyboard's state from kbp-hidraw, which prints it whole as one JSON line per change.
// One helper serves every bar (one per monitor); it is restarted if it ever exits.
QtObject {
    id: root

    property var state: ({ connected: false })
    readonly property bool connected: !!state.connected
    readonly property bool permissionDenied: state.error === "permission"

    readonly property var layers: state.layers || []
    readonly property string layerName: state.layerName || ""
    readonly property int mods: state.mods || 0
    readonly property var battery: state.battery || null
    readonly property var halves: state.halves || null
    readonly property var profile: state.profile || null
    readonly property string output: state.output || "unknown"

    // The lowest reported battery: a split's weaker half.
    readonly property var lowestBattery: {
        if (!battery) return null
        var levels = [battery.left, battery.right, battery.overall].filter(v => typeof v === "number")
        return levels.length ? Math.min.apply(null, levels) : null
    }

    readonly property string helper: decodeURIComponent(
        Qt.resolvedUrl("../kbp-hidraw").toString().replace(/^file:\/\//, ""))

    property Process process: Process {
        command: ["python3", root.helper]
        running: true
        stdout: SplitParser {
            onRead: data => {
                try {
                    root.state = JSON.parse(data)
                } catch (e) {
                    console.warn("keybeacon: unreadable helper line:", data)
                }
            }
        }
        onExited: (code, status) => {
            root.state = { connected: false, error: "helper" }
            restart.start()
        }
    }

    property Timer restart: Timer {
        interval: 2000
        onTriggered: root.process.running = true
    }
}
