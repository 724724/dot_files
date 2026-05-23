pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import QtQuick

Singleton {
    id: root

    property bool controlCenterVisible: false
    property bool dnd: false

    // server.trackedNotifications is an UntypedObjectModel — convert to a JS
    // array (newest first) so .filter / .length / etc. work in bindings.
    function _toArray(m) {
        let out = []
        if (!m) return out
        let v = m.values
        if (!v) return out
        // Reverse iteration: newest tracked notifications go to the top of
        // the stack instead of the bottom.
        for (let i = v.length - 1; i >= 0; --i) out.push(v[i])
        return out
    }

    // Bumped from onNotification so additions trigger re-evaluation. For
    // removals we also read the model's .count Q_PROPERTY in the binding,
    // which provides intrinsic reactivity without needing a Connections.
    property int _revision: 0

    readonly property var notifications: {
        let m = server.trackedNotifications
        let _ = m ? m.count : 0   // dependency on count for add/remove reactivity
        let __ = root._revision    // belt-and-braces fallback
        return _toArray(m)
    }
    readonly property int count: notifications ? notifications.length : 0

    // id → Date.now() arrival timestamp, used for live "now / 2m / 1h" labels.
    // Persisted to disk (see timeStore) so the labels survive a config reload
    // or restart instead of every card snapping back to "now".
    property var receivedAt: ({})

    // Restore arrival times before any card binds relativeTime(). Notifications
    // themselves come back via NotificationServer.keepOnReload, but their ids
    // stay stable, so the persisted id→timestamp map lines straight back up.
    Component.onCompleted: root._loadReceivedAt()

    FileView {
        id: timeStore
        path: Quickshell.stateDir + "/nc-received-at.json"
        blockLoading: true   // synchronous read so data is ready in onCompleted
        printErrors: false   // a missing file on first run is expected
    }

    function _loadReceivedAt() {
        let raw = timeStore.text()
        if (!raw) return
        try {
            let parsed = JSON.parse(raw)
            if (parsed && typeof parsed === "object") root.receivedAt = parsed
        } catch (e) { /* empty or corrupt file — start fresh */ }
    }

    function _persistReceivedAt() {
        timeStore.setText(JSON.stringify(root.receivedAt))
    }

    // Drop timestamps whose notifications are gone so the file stays bounded.
    // Guarded on count so a transient empty model never wipes live entries.
    function _pruneReceivedAt() {
        if (root.count === 0) return
        let live = ({})
        for (let i = 0; i < notifications.length; ++i) live[notifications[i].id] = true
        let next = ({})
        let changed = false
        for (let k in root.receivedAt) {
            if (live[k]) next[k] = root.receivedAt[k]
            else changed = true
        }
        if (changed) {
            root.receivedAt = next
            root._persistReceivedAt()
        }
    }

    // Ticked every 30 s so timestamp bindings refresh without polling per card
    property int _tick: 0
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            root._tick++
            root._pruneReceivedAt()
        }
    }

    function relativeTime(id) {
        let _ = root._tick   // dependency
        let t = receivedAt[id]
        if (!t) return "now"
        let diff = (Date.now() - t) / 1000
        if (diff < 60)    return "now"
        if (diff < 3600)  return Math.floor(diff / 60) + "m"
        if (diff < 86400) return Math.floor(diff / 3600) + "h"
        return Math.floor(diff / 86400) + "d"
    }

    // id → true once the popup phase finished
    property var popupSeen: ({})
    readonly property var popupActive: notifications.filter(n => !popupSeen[n.id])

    // Group by appName — array order is newest-first per _toArray reverse.
    function groupedByApp() {
        let groups = []
        let seen = {}
        for (let i = 0; i < notifications.length; ++i) {
            let n = notifications[i]
            let key = n.appName || "?"
            if (key in seen) {
                groups[seen[key]].notifs.push(n)
            } else {
                seen[key] = groups.length
                groups.push({ appName: key, notifs: [n] })
            }
        }
        return groups
    }

    function markPopupSeen(id) {
        let copy = Object.assign({}, popupSeen)
        copy[id] = true
        popupSeen = copy
    }

    function dismissAll() {
        for (let i = notifications.length - 1; i >= 0; i--)
            notifications[i].dismiss()
        popupSeen = ({})
        receivedAt = ({})
        _persistReceivedAt()
    }

    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        bodySupported: true
        imageSupported: true

        onNotification: n => {
            if (root.dnd && n.urgency !== NotificationUrgency.Critical) {
                n.expire()
                return
            }
            n.tracked = true
            // A config reload re-emits kept notifications (keepOnReload) with
            // lastGeneration === true. Their arrival time is already restored
            // from disk by _loadReceivedAt — stamping Date.now() here is what
            // reset every card to "now". Only stamp genuinely new arrivals;
            // those always have lastGeneration === false (including after a
            // full process restart, where stale ids must be re-stamped).
            if (!n.lastGeneration) {
                let copy = Object.assign({}, root.receivedAt)
                copy[n.id] = Date.now()
                root.receivedAt = copy
                root._persistReceivedAt()
            }
            root._revision++
        }
    }

    IpcHandler {
        target: "nc"
        function toggle() { root.controlCenterVisible = !root.controlCenterVisible }
        function dnd() { root.dnd = !root.dnd }
        function getstate(): string {
            return JSON.stringify({ count: root.count, dnd: root.dnd })
        }
    }

    // Kill any existing swaync to take over org.freedesktop.Notifications
    Process {
        command: ["bash", "-c", "killall swaync 2>/dev/null; systemctl --user stop swaync.service 2>/dev/null; true"]
        running: true
    }
}
