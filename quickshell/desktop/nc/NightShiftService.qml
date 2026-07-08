pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Night Shift via hyprsunset. hyprsunset (v0.3.x) has NO way to query whether the
// warm filter is active — `hyprctl hyprsunset temperature` returns the configured
// value even when `identity` (off) is in effect — so on/off can't be probed.
//
// Instead a tiny state file is the shared source of truth: this service AND the
// SUPER+SHIFT brightness keybinds both write it, and we poll it so the nc toggle
// reflects Night Shift no matter how it was changed. The file lives in
// XDG_RUNTIME_DIR so it resets to "off" each login (matching hyprsunset's neutral
// startup from autostart).
Singleton {
    id: root
    property int temperature: 4500   // matches the keybind's warm value
    readonly property string stateFile: Quickshell.env("XDG_RUNTIME_DIR") + "/qs-nightshift"
    property bool active: false

    function enable() {
        Quickshell.execDetached(["bash", "-c",
            "hyprctl hyprsunset temperature " + root.temperature
            + "; printf on > '" + root.stateFile + "'"])
        root.active = true   // optimistic; the poll confirms
    }
    function disable() {
        Quickshell.execDetached(["bash", "-c",
            "hyprctl hyprsunset identity; printf off > '" + root.stateFile + "'"])
        root.active = false
    }
    function toggle() {
        if (root.active) root.disable()
        else root.enable()
    }

    // Watch the state file (inotify via FileView) so external toggles (the
    // keybinds) sync instantly — replaces the old 1s `cat` polling loop that
    // spawned a process every second. A missing file reads as empty → off.
    FileView {
        id: stateView
        path: root.stateFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.active = (text().trim() === "on")
        onLoadFailed: root.active = false
    }

    // Slow backstop: some writers replace the file in ways a watch can miss.
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: stateView.reload()
    }
}
