pragma Singleton
import Quickshell
import QtQuick
import "../dock" as Dock

// The dock already owns the shared Hyprland client snapshot. Derive the Magic
// indicator from it instead of spawning another hyprctl+jq process on every
// window event and on a periodic backstop.
Singleton {
    id: root

    readonly property bool hasMagic: {
        let byClass = Dock.DockService.clientsByClass || {}
        let classes = Object.keys(byClass)
        for (let i = 0; i < classes.length; i++) {
            let windows = byClass[classes[i]] || []
            for (let j = 0; j < windows.length; j++)
                if ((windows[j].ws || "") === "special:magic") return true
        }
        return false
    }
}
