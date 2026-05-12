pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // Windows in MRU order: focused first, then most recently used.
    property var windows: []

    function refresh() { listProc.running = true }

    function focusByAddress(addr) {
        if (!addr) return
        // Use the wrapper script so the cursor is also moved onto the focused
        // window — without that, `follow_mouse = 1` causes the focus to be
        // stolen back by whichever window happens to sit under the cursor.
        focusProc.command = ["/home/sejunlee/.config/hypr/scripts/focus-window.sh", addr]
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
                if (!line) return
                try {
                    let arr = JSON.parse(line)
                    if (Array.isArray(arr)) root.windows = arr
                } catch(e) {}
            }
        }
    }

    Process { id: focusProc; command: ["true"] }

    // Keep the windows list warm so Super+Tab opens with data ready (the
    // hyprctl + jq subprocess takes ~80–150ms; refreshing on-demand makes
    // the switcher appear empty for the first press).
    Component.onCompleted: refresh()

    // Frequent poll keeps focusHistoryID-based MRU close to current state. The
    // shell's openOrAdvance() also kicks an explicit refresh on every open;
    // this poll is a defensive backstop for edge cases (apps closed/created
    // outside of focus events).
    Timer {
        interval: 300
        running: true
        repeat: true
        onTriggered: if (!listProc.running) listProc.running = true
    }
}
