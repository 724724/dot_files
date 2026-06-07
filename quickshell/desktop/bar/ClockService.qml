pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Popup visibility. The bar ClockWidget lives in this same directory, so it
    // flips this directly (no `qs ipc` subprocess as NotificationWidget needs for the
    // cross-directory nc target); the IpcHandler below mirrors it for external
    // triggers like keybindings.
    property bool popupVisible: false

    // Monitor whose clock pill was tapped, so the popup opens there. Set by
    // ClockWidget just before toggling popupVisible.
    property var targetScreen: null

    // Live clock driving the big time readout. Per-second like the bar's Time
    // singleton — cost is negligible and `now` is valid the moment the popup maps.
    readonly property var now: clock.date
    SystemClock { id: clock; precision: SystemClock.Seconds }

    IpcHandler {
        target: "clock"
        function toggle() { root.popupVisible = !root.popupVisible }
        function show()   { root.popupVisible = true }
        function hide()   { root.popupVisible = false }
    }
}
