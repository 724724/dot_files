pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property var resolved: ({})
    property var pending: ({})
    property var queue: []
    property var _active: null
    property bool _resolverReady: false
    readonly property int resolverRevision: 6

    function key(iconName, desktopId, appClass, themeRevision) {
        return (iconName || "") + "\u001f" + (desktopId || "") + "\u001f"
            + (appClass || "") + "\u001f" + (themeRevision || 0)
            + "\u001f" + root.resolverRevision
    }

    function sourceFor(iconName, desktopId, appClass, themeRevision) {
        return root.resolved[root.key(iconName, desktopId, appClass, themeRevision)] || ""
    }

    function request(iconName, desktopId, appClass, themeRevision, priority) {
        let k = root.key(iconName, desktopId, appClass, themeRevision)
        if (root.resolved[k] !== undefined || root.pending[k]) return
        let nextPending = Object.assign({}, root.pending)
        nextPending[k] = true
        root.pending = nextPending
        let request = {
            key: k,
            iconName: iconName || "",
            desktopId: desktopId || "",
            appClass: appClass || "",
            themeRevision: themeRevision || 0,
            priority: priority || 0
        }
        let insertAt = root.queue.length
        for (let i = 0; i < root.queue.length; i++) {
            if (request.priority > (root.queue[i].priority || 0)) {
                insertAt = i
                break
            }
        }
        root.queue = root.queue.slice(0, insertAt).concat(
            [request], root.queue.slice(insertAt))
        root._startNext()
    }

    function _startNext() {
        if (!root._resolverReady || root._active || root.queue.length === 0) return
        root._active = root.queue[0]
        root.queue = root.queue.slice(1)
        resolver.write(JSON.stringify(root._active) + "\n")
    }

    function _finish(data) {
        if (!root._active) return
        let response = ({})
        try { response = JSON.parse(data) } catch (error) { response = ({}) }
        if (response.key !== root._active.key) return
        // The resolver also returns a direct-file generic icon when the named
        // icon is unavailable. An empty result is safer than falling back to
        // image://icon and re-entering the provider this service is isolating.
        let value = response.value || ""
        let nextResolved = Object.assign({}, root.resolved)
        nextResolved[root._active.key] = value
        root.resolved = nextResolved
        let nextPending = Object.assign({}, root.pending)
        delete nextPending[root._active.key]
        root.pending = nextPending
        root._active = null
        Qt.callLater(root._startNext)
    }

    Process {
        id: resolver
        command: [Quickshell.env("HOME")
            + "/.config/quickshell/scripts/resolve-app-icon.py", "--server"]
        stdinEnabled: true
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root._finish(data)
        }
        onStarted: {
            root._resolverReady = true
            root._startNext()
        }
        onExited: {
            root._resolverReady = false
            if (root._active) {
                root.queue = [root._active].concat(root.queue)
                root._active = null
            }
            restartTimer.restart()
        }
    }

    Timer {
        id: restartTimer
        interval: 100
        onTriggered: if (!resolver.running) resolver.running = true
    }
}
