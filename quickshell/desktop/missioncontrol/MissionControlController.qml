import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import "../dock" as Dock

// Mission Control owns one global transition transaction shared by every output.
// The layer surfaces remain mapped until progress reaches zero, so cancel, focus
// zoom and rapid reversals all continue from the current presentation frame.
Scope {
    id: scope

    property bool requestedOpen: false
    property bool _surfaceVisible: false
    property bool _openPending: false
    property int _openRevision: 0

    property string exitKind: ""
    property string selectedAddress: ""
    property int selectedWorkspace: -1
    // Once a reverse transition begins, keep the compositor's real windows
    // occluded until an exact endpoint. Otherwise the backdrop alpha follows
    // progress down and the real windows appear underneath their moving proxies.
    property bool _holdBackdrop: false

    property bool _gestureActive: false
    property bool _gestureAccepted: false
    property real _gestureOriginTarget: 0
    property real _gestureLastTime: 0
    property real _gestureVelocity: 0
    readonly property real _gestureDistance: 420

    readonly property bool reducedMotion: ThemeService.reducedMotion
    readonly property real overviewProgress: Math.max(0, Math.min(1, motion.value))
    readonly property real spatialProgress: reducedMotion && _surfaceVisible
        ? 1 : overviewProgress
    readonly property bool overviewInteractive: requestedOpen
        && overviewProgress >= 0.985 && !motion.running && !_gestureActive

    MotionProgress {
        id: motion
        reducedMotion: scope.reducedMotion
        response: 0.30
        dampingRatio: 1.0
        onSettled: value => scope._onMotionSettled(value)
    }

    // The unpinned Dock participates in this same presentation transaction.
    // At progress zero it is already outside the screen, so clearing the
    // overview boolean cannot start a late, second hide animation.
    Binding {
        target: Dock.DockService
        property: "overviewProgress"
        value: scope._surfaceVisible ? scope.overviewProgress : 0
    }

    // MissionControlWindow keeps its transparent surface mapped below the Dock.
    // One display frame lets live captures attach before the reveal starts.
    Timer {
        id: presentTimer
        interval: 18
        onTriggered: {
            if (!scope._surfaceVisible || !scope.requestedOpen) return
            if (!scope._gestureActive)
                motion.settleTo(1, motion.velocity)
        }
    }

    // A malformed/failed geometry poll must never leave Mission Control stuck
    // pending forever. The startup/event cache is sufficient as a fallback.
    Timer {
        id: snapshotWatchdog
        interval: 420
        onTriggered: {
            if (!scope._openPending) return
            scope._openPending = false
            if (!scope.requestedOpen) return
            scope._surfaceVisible = true
            scope._setOverviewServices(true)
            presentTimer.restart()
            MCService.refresh()
        }
    }

    function _clearExit() {
        scope.exitKind = ""
        scope.selectedAddress = ""
        scope.selectedWorkspace = -1
    }

    function _setOverviewServices(active) {
        MCService.open = active
        Dock.DockService.overviewScreen = ""
        Dock.DockService.overviewOpen = active && scope._surfaceVisible
    }

    function requestShow(fromGesture) {
        scope.requestedOpen = true
        scope._clearExit()

        // A brand-new presentation may use the existing progressive reveal to
        // avoid covering captures before their first frame. A close→open
        // reversal deliberately keeps the latch, so it cannot alpha-jump.
        if (!scope._surfaceVisible && !scope._openPending)
            scope._holdBackdrop = false

        if (scope._surfaceVisible) {
            scope._setOverviewServices(true)
            if (!fromGesture && !scope._gestureActive)
                motion.settleTo(1, motion.velocity)
            return
        }
        if (scope._openPending) return

        scope._openPending = true
        if (!fromGesture) motion.snapTo(0)
        scope._openRevision = MCService.refreshForOpen()
        scope._setOverviewServices(true)
        snapshotWatchdog.restart()
    }

    function requestHide(kind, initialVelocity) {
        scope.requestedOpen = false
        scope.exitKind = kind || "cancel"
        presentTimer.stop()

        if (scope._surfaceVisible)
            scope._holdBackdrop = true

        if (scope._openPending && !scope._surfaceVisible) {
            scope._openPending = false
            snapshotWatchdog.stop()
            motion.snapTo(0)
            scope._setOverviewServices(false)
            scope._holdBackdrop = false
            scope._clearExit()
            return
        }
        if (!scope._surfaceVisible) {
            scope._setOverviewServices(false)
            scope._holdBackdrop = false
            scope._clearExit()
            return
        }
        motion.settleTo(0, Number.isFinite(Number(initialVelocity))
            ? Number(initialVelocity) : motion.velocity)
    }

    function requestToggle() {
        if (scope.requestedOpen || scope._openPending
                || (scope._surfaceVisible && motion.targetValue > 0.5))
            scope.requestHide("cancel")
        else
            scope.requestShow(false)
    }

    function requestWindow(address) {
        if (!address || !scope._surfaceVisible) return
        scope.exitKind = "window"
        scope.selectedAddress = address
        scope.selectedWorkspace = -1
        // Raise the real target under the still-opaque overlay. The selected
        // preview already owns the top visual z, so endpoint cross-fade cannot
        // expose a one-frame old compositor stack.
        MCService.focusWindow(address)
        scope.requestHide("window")
    }

    function requestWorkspace(wsId) {
        if (wsId < 1 || !scope._surfaceVisible) return
        scope.exitKind = "workspace"
        scope.selectedAddress = ""
        scope.selectedWorkspace = wsId
        // Commit the selected Space first, while the overlay still covers the
        // compositor transition. The overview then closes over the new desktop;
        // waiting until unmap made the click feel backwards (close, then move).
        MCService.focusWorkspace(wsId)
        scope.requestHide("workspace")
    }

    function _onMotionSettled(value) {
        if (value > 0.5 || scope.requestedOpen) {
            // A reversed close retains full coverage until the overview has
            // completely reopened; clearing at an intermediate value would
            // reveal the compositor stack for one frame.
            if (value >= 0.999 && scope.requestedOpen)
                scope._holdBackdrop = false
            return
        }
        scope._surfaceVisible = false
        scope._setOverviewServices(false)
        scope._holdBackdrop = false
        scope._clearExit()
    }

    function _gestureStart(timeMs) {
        scope._gestureActive = true
        scope._gestureAccepted = scope._surfaceVisible || scope.requestedOpen
        scope._gestureOriginTarget = (scope.requestedOpen
            || motion.targetValue >= 0.5) ? 1 : 0
        scope._gestureLastTime = Number(timeMs) || 0
        scope._gestureVelocity = motion.velocity
        if (scope._gestureAccepted) motion.stop()
    }

    function _gestureUpdate(deltaY, timeMs) {
        let delta = Number(deltaY)
        let timestamp = Number(timeMs)
        if (!Number.isFinite(delta) || !Number.isFinite(timestamp)) return
        if (!scope._gestureActive) scope._gestureStart(timestamp)

        let dt = scope._gestureLastTime > 0
            ? Math.max(0.001, Math.min(0.08, (timestamp - scope._gestureLastTime) / 1000))
            : 1 / 60
        scope._gestureLastTime = timestamp

        // Up is negative in Hyprland; overview progress grows upward.
        let progressDelta = -delta / scope._gestureDistance
        // Direct downward manipulation is already a close presentation before
        // the release target is known. Latch on its first negative frame.
        if (scope._surfaceVisible && progressDelta < 0)
            scope._holdBackdrop = true
        if (!scope._gestureAccepted) {
            if (progressDelta <= 0) return
            scope._gestureAccepted = true
            scope._gestureOriginTarget = 0
            scope.requestShow(true)
            motion.stop()
        }

        let instantaneous = progressDelta / dt
        scope._gestureVelocity = scope._gestureVelocity * 0.35 + instantaneous * 0.65
        motion.track(motion.value + progressDelta, scope._gestureVelocity)
    }

    function _project(value, velocity) {
        // Apple's exponential deceleration projection with d=0.998. Velocity is
        // normalised units/s, so the result is in normalised progress units.
        let deceleration = 0.998
        return value + (velocity / 1000) * deceleration / (1 - deceleration)
    }

    function _gestureFinish(cancelled, timeMs) {
        if (!scope._gestureActive) return
        let accepted = scope._gestureAccepted
        let origin = scope._gestureOriginTarget
        let velocity = scope._gestureVelocity
        let finishTime = Number(timeMs)
        if (Number.isFinite(finishTime) && scope._gestureLastTime > 0) {
            let idleSeconds = Math.max(0,
                (finishTime - scope._gestureLastTime) / 1000)
            velocity = idleSeconds >= 0.08 ? 0
                : velocity * Math.exp(-idleSeconds / 0.045)
        }
        scope._gestureActive = false
        scope._gestureAccepted = false
        scope._gestureLastTime = 0
        scope._gestureVelocity = 0
        if (!accepted) return

        let projected = scope._project(motion.value, velocity)
        let target = cancelled ? origin : (projected >= 0.5 ? 1 : 0)
        if (target >= 1) {
            scope.requestedOpen = true
            scope._clearExit()
            if (scope._surfaceVisible)
                motion.settleTo(1, velocity)
            // If the fresh snapshot is still pending, keep the finger-linked
            // presentation value; presentTimer will settle after the map.
        } else {
            scope.requestHide("cancel", velocity)
        }
    }

    function _handleGestureEvent(data) {
        let parts = String(data || "").split("|")
        if (parts.length < 2 || parts[0] !== "qs-mc-gesture") return
        if (parts[1] === "start")
            scope._gestureStart(parts[2])
        else if (parts[1] === "update" && parts.length >= 4)
            scope._gestureUpdate(parts[2], parts[3])
        else if (parts[1] === "finish")
            scope._gestureFinish(parts[2] === "1" || parts[2] === "true",
                parts[3])
    }

    GlobalShortcut {
        appid: "mc"
        name: "toggle"
        description: "Mission Control: toggle"
        onPressed: scope.requestToggle()
    }

    Connections {
        target: MCService
        function onSnapshotRevisionChanged() {
            if (!scope._openPending
                    || MCService.snapshotRevision < scope._openRevision) return
            scope._openPending = false
            snapshotWatchdog.stop()
            if (!scope.requestedOpen) {
                scope._setOverviewServices(false)
                return
            }

            scope._surfaceVisible = true
            // The overview surface was mapped before DockWindow at shell startup,
            // so enabling Dock overview state never needs a stacking re-map.
            scope._setOverviewServices(true)
            presentTimer.restart()
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event && event.name === "custom")
                scope._handleGestureEvent(event.data)
        }
    }

    IpcHandler {
        target: "mc"
        function status(): string {
            return JSON.stringify({
                requestedOpen: scope.requestedOpen,
                active: scope._surfaceVisible,
                pending: scope._openPending,
                progress: scope.overviewProgress,
                target: motion.targetValue,
                gestureActive: scope._gestureActive,
                exitKind: scope.exitKind,
                holdBackdrop: scope._holdBackdrop
            })
        }
        function show()   { scope.requestShow(false) }
        function hide()   { scope.requestHide("cancel") }
        function toggle() { scope.requestToggle() }
    }

    Variants {
        model: Quickshell.screens
        MissionControlWindow {
            active: scope._surfaceVisible
            overviewProgress: scope.overviewProgress
            spatialProgress: scope.spatialProgress
            transitionRunning: motion.running || scope._gestureActive
            overviewInteractive: scope.overviewInteractive
            reducedMotion: scope.reducedMotion
            exitKind: scope.exitKind
            selectedAddress: scope.selectedAddress
            holdBackdrop: scope._holdBackdrop

            onCancelRequested: scope.requestHide("cancel")
            onWindowRequested: address => scope.requestWindow(address)
            onWorkspaceRequested: wsId => scope.requestWorkspace(wsId)
        }
    }
}
