pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

Singleton {
    id: root

    // Windows in MRU order: focused first, then most recently used.
    property var windows: []
    // Signature of the last published list, so identical polls don't reassign
    // `windows` (a fresh array would re-trigger every binding downstream).
    property string _sig: ""

    function refresh() { listProc.running = true }

    function focusByAddress(addr) {
        if (!addr) return
        // Use the wrapper script so the cursor is also moved onto the focused
        // window — without that, `follow_mouse = 1` causes the focus to be
        // stolen back by whichever window happens to sit under the cursor.
        focusProc.command = [Quickshell.shellDir + "/../scripts/switcher-focus-window.sh", addr]
        focusProc.running = true
    }

    Process {
        id: listProc
        // Sort by focusHistoryID asc → MRU (0 = currently focused).
        // Skip windows with no class (xwayland helpers) and pinned/hidden helpers.
        command: ["bash", "-c",
            "hyprctl clients -j | jq -c '" +
            "[.[] | select(.class != \"\" and (.class | ascii_downcase | test(\"^xwaylandvideobridge|^xembedsniproxy\") | not))] | " +
            "sort_by(.focusHistoryID) | " +
            "map({address, class, title, workspaceId: .workspace.id, workspaceName: .workspace.name, focusHistoryID})'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let line = text.trim()
                if (!line || line === root._sig) return
                try {
                    let arr = JSON.parse(line)
                    if (Array.isArray(arr)) { root._sig = line; root.windows = arr }
                } catch(e) {}
            }
        }
    }

    Process { id: focusProc; command: ["true"] }

    // Keep the windows list warm so Super+Tab opens with data ready (the
    // hyprctl + jq subprocess takes ~80–150ms; refreshing on-demand makes
    // the switcher appear empty for the first press).
    Component.onCompleted: refresh()

    // Event-driven instead of the old 300ms blind poll (which spawned
    // bash+hyprctl+jq ~3×/sec forever and hit the compositor's IPC each time):
    // any Hyprland event that can affect the MRU list schedules one debounced
    // refresh. openOrAdvance() still kicks an explicit refresh on every open.
    Connections {
        target: Hyprland
        function onRawEvent(event) { debounce.restart() }
    }
    Timer { id: debounce; interval: 48; onTriggered: root.refresh() }

    // Slow defensive backstop in case an event is ever missed.
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: if (!listProc.running) listProc.running = true
    }
}
