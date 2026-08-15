pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string backendScript: Quickshell.shellDir + "/../scripts/capture-tool.sh"
    readonly property string windowBackendScript: Quickshell.shellDir + "/../scripts/capture-windows.sh"

    property bool toolbarOpen: false
    property bool toolbarVisible: false
    property bool optionsOpen: false
    property bool folderPickerOpen: false
    property string mode: "window"
    property string toolbarMode: "window"
    property var targetScreen: null
    property string targetScreenName: ""

    property real selectionX: 0
    property real selectionY: 0
    property real selectionWidth: 0
    property real selectionHeight: 0
    property bool selectionValid: false
    property string selectedWindowAddress: ""
    property var windowClients: []
    property string hoveredWindowAddress: ""
    property bool toolbarHovered: false

    // Portion history is independent from the transient target used by Window
    // and Entire Screen. Keep one entry per output so either Shift+Super+4 or
    // the Selected Portion button in Shift+Super+5 restores the exact same box.
    property var portionSelections: ({})

    // File destinations deliberately mirror the compact macOS menu. A custom
    // directory is a single replaceable slot rather than an accumulating list.
    property string saveMode: "documents"
    property string customDirectory: ""
    property int timerSeconds: 0
    property bool rememberSelection: true
    property bool showPointer: false
    property bool microphone: false
    property bool desktopAudio: true

    // Stored as normalized card-centre coordinates so a dragged toolbar keeps a
    // sensible position when the target output has a different resolution.
    property bool toolbarPositionStored: false
    property real toolbarAnchorX: 0.5
    property real toolbarAnchorY: 0.9

    property bool recorderAvailable: false
    property string recorderBackend: ""
    property string recorderProblem: ""
    readonly property bool recording: recorder.running
    property double recordingStartedAt: 0
    property int elapsedSeconds: 0
    property string recordingPath: ""
    property bool stopRequested: false

    property string pendingAction: ""
    property string pendingCaptureMode: ""
    property int countdownRemaining: 0
    readonly property bool countingDown: pendingAction !== "" && countdownRemaining > 0
    readonly property bool recordMode: mode.indexOf("record-") === 0
    readonly property string baseMode: mode === "record-screen" ? "screen"
        : mode === "record-window" ? "window"
        : mode === "record-portion" ? "portion" : mode
    readonly property bool overlayActive: toolbarOpen && !recording
    readonly property bool quickPortionMode: overlayActive && !toolbarVisible
        && baseMode === "portion"
    readonly property string primaryButtonText: {
        if (recording) return "Stop"
        if (countingDown) return String(countdownRemaining)
        if (recordMode && !recorderAvailable)
            return recorderProblem === "missing-shared-library" ? "Update System" : "Install Recorder"
        return recordMode ? "Record" : "Capture"
    }

    signal selectionResetRequested(string screenName)

    function _screenForName(name) {
        const screens = Quickshell.screens
        for (let i = 0; i < screens.length; i++)
            if (screens[i].name === name) return screens[i]
        return null
    }

    function setTargetScreen(screen) {
        if (!screen) return
        const nextName = String(screen.name || "")
        if (root.targetScreenName !== "" && root.targetScreenName !== nextName) {
            root.selectionValid = false
            root.selectedWindowAddress = ""
        }
        root.targetScreen = screen
        root.targetScreenName = nextName
    }

    function setMode(nextMode) {
        const allowed = ["screen", "window", "portion",
            "record-screen", "record-window", "record-portion"]
        if (allowed.indexOf(nextMode) < 0 || root.recording) return
        root.mode = nextMode
        root.toolbarMode = nextMode
        if (root.recordMode && root.saveMode === "clipboard") root.saveMode = "documents"
        root.optionsOpen = false
        root.folderPickerOpen = false
        root.selectedWindowAddress = ""
        root.hoveredWindowAddress = ""
        root.selectionValid = false
        if (root.targetScreenName !== "")
            root.selectionResetRequested(root.targetScreenName)
        if (root.baseMode === "window") root.refreshWindows()
        root._persist()
    }

    function show() {
        const focused = Hyprland.focusedMonitor
        const focusedScreen = focused ? root._screenForName(String(focused.name || "")) : null
        if (focusedScreen) root.setTargetScreen(focusedScreen)
        else if (!root.targetScreen && Quickshell.screens.length > 0)
            root.setTargetScreen(Quickshell.screens[0])
        root.mode = root.toolbarMode
        if (root.recordMode && root.saveMode === "clipboard")
            root.saveMode = "documents"
        root.pendingAction = ""
        root.pendingCaptureMode = ""
        root.countdownRemaining = 0
        root.optionsOpen = false
        root.folderPickerOpen = false
        root.toolbarVisible = true
        root.toolbarOpen = true
        availability.running = true
        root.refreshWindows()
    }

    function showPortion() {
        const focused = Hyprland.focusedMonitor
        const focusedScreen = focused ? root._screenForName(String(focused.name || "")) : null
        if (focusedScreen) root.setTargetScreen(focusedScreen)
        else if (!root.targetScreen && Quickshell.screens.length > 0)
            root.setTargetScreen(Quickshell.screens[0])

        root.pendingAction = ""
        root.pendingCaptureMode = ""
        root.countdownRemaining = 0
        countdown.stop()
        unmapDelay.stop()
        root.optionsOpen = false
        root.folderPickerOpen = false
        root.toolbarVisible = false
        root.mode = "portion"
        root.selectedWindowAddress = ""
        root.hoveredWindowAddress = ""
        root.toolbarOpen = true
        root.selectionResetRequested(root.targetScreenName)
        root._persist()
    }

    function captureScreen() {
        if (root.recording || screenshot.running) return
        const focused = Hyprland.focusedMonitor
        const focusedScreen = focused ? root._screenForName(String(focused.name || "")) : null
        if (focusedScreen) root.setTargetScreen(focusedScreen)
        else if (!root.targetScreen && Quickshell.screens.length > 0)
            root.setTargetScreen(Quickshell.screens[0])
        if (!root.targetScreen || root.targetScreenName === "") return

        countdown.stop()
        unmapDelay.stop()
        root.pendingAction = "screenshot"
        root.pendingCaptureMode = "screen"
        root.countdownRemaining = 0
        root.toolbarVisible = false
        root.toolbarOpen = false
        root.optionsOpen = false
        root.folderPickerOpen = false
        // Give a previously visible capture surface one frame to disappear.
        unmapDelay.restart()
    }

    function hide() {
        if (root.recording) {
            root.toolbarOpen = false
            root.toolbarVisible = false
            root.optionsOpen = false
            root.folderPickerOpen = false
            return
        }
        root.pendingAction = ""
        root.pendingCaptureMode = ""
        root.countdownRemaining = 0
        countdown.stop()
        unmapDelay.stop()
        root.toolbarOpen = false
        root.toolbarVisible = false
        root.toolbarHovered = false
        root.optionsOpen = false
        root.folderPickerOpen = false
    }

    function toggle() {
        if (root.toolbarOpen && root.toolbarVisible) root.hide()
        else root.show()
    }

    function setToolbarPosition(left, top, screenWidth, screenHeight,
            toolbarWidth, toolbarHeight) {
        const sw = Number(screenWidth), sh = Number(screenHeight)
        if (!(sw > 0) || !(sh > 0)) return
        root.toolbarAnchorX = Math.max(0, Math.min(1,
            (Number(left) + Number(toolbarWidth) / 2) / sw))
        root.toolbarAnchorY = Math.max(0, Math.min(1,
            (Number(top) + Number(toolbarHeight) / 2) / sh))
        root.toolbarPositionStored = true
        root._persist()
    }

    function updateSelection(screen, x, y, width, height) {
        if (!screen) return
        root.setTargetScreen(screen)
        const w = Math.max(0, Math.round(Number(width)))
        const h = Math.max(0, Math.round(Number(height)))
        root.selectionX = Math.round(Number(screen.x) + Number(x))
        root.selectionY = Math.round(Number(screen.y) + Number(y))
        root.selectionWidth = w
        root.selectionHeight = h
        root.selectionValid = isFinite(root.selectionX) && isFinite(root.selectionY)
            && w >= 8 && h >= 8
        root.selectedWindowAddress = ""
        if (root.baseMode === "portion" && root.selectionValid) {
            const saved = Object.assign({}, root.portionSelections)
            saved[String(screen.name || "")] = {
                x: root.selectionX,
                y: root.selectionY,
                width: root.selectionWidth,
                height: root.selectionHeight
            }
            root.portionSelections = saved
            root._persist()
        }
    }

    function portionSelectionForScreen(screenName) {
        if (!root.rememberSelection) return null
        const value = root.portionSelections[String(screenName || "")]
        if (!value) return null
        const x = Number(value.x), y = Number(value.y)
        const w = Number(value.width), h = Number(value.height)
        if (!isFinite(x) || !isFinite(y) || !isFinite(w) || !isFinite(h)
                || w < 8 || h < 8) return null
        return { x: x, y: y, width: w, height: h }
    }

    function setRememberSelection(value) {
        root.rememberSelection = value === true
        if (!root.rememberSelection) root.portionSelections = ({})
        root._persist()
    }

    function selectWindow(screen, win) {
        if (!screen || !win || !Array.isArray(win.at) || !Array.isArray(win.size)) return
        root.setTargetScreen(screen)
        root.selectionX = Math.round(Number(win.at[0]))
        root.selectionY = Math.round(Number(win.at[1]))
        root.selectionWidth = Math.round(Number(win.size[0]))
        root.selectionHeight = Math.round(Number(win.size[1]))
        root.selectionValid = root.selectionWidth >= 8 && root.selectionHeight >= 8
        root.selectedWindowAddress = String(win.address || "")
    }

    function _canRunSelection() {
        if (root.baseMode === "screen") return root.targetScreenName !== ""
        return root.selectionValid
    }

    function trigger() {
        if (root.recording) {
            root.stopRecording()
            return
        }
        if (screenshot.running || root.countingDown) return
        if (root.recordMode && !root.recorderAvailable) {
            if (root.recorderProblem === "missing-shared-library")
                Quickshell.execDetached(["notify-send", "-a", "Screenshot",
                    "System update required",
                    "Run sudo pacman -Syu, reboot, then try recording again."])
            else
                Quickshell.execDetached(["notify-send", "-a", "Screenshot",
                    "Screen recording is unavailable",
                    "Install it with: sudo pacman -Syu --needed gpu-screen-recorder"])
            return
        }
        if (!root._canRunSelection()) {
            Quickshell.execDetached(["notify-send", "-a", "Screenshot",
                "Choose a target first",
                root.baseMode === "window" ? "Select a window to continue."
                                           : "Drag to select an area."])
            return
        }
        if (root.rememberSelection) root._persist()
        root.pendingAction = root.recordMode ? "record" : "screenshot"
        root.pendingCaptureMode = root.baseMode
        root.countdownRemaining = root.timerSeconds
        root.optionsOpen = false
        root.folderPickerOpen = false
        if (root.countdownRemaining > 0) countdown.start()
        else root._unmapAndRun()
    }

    function _unmapAndRun() {
        countdown.stop()
        root.countdownRemaining = 0
        root.toolbarOpen = false
        root.toolbarVisible = false
        root.optionsOpen = false
        root.folderPickerOpen = false
        unmapDelay.restart()
    }

    function _command(action, path, captureMode) {
        const screen = String(root.targetScreenName || "")
        const resolvedMode = String(captureMode || root.baseMode)
        return [root.backendScript, action, resolvedMode, screen,
            String(Math.round(root.selectionX)), String(Math.round(root.selectionY)),
            String(Math.round(root.selectionWidth)), String(Math.round(root.selectionHeight)),
            root.showPointer ? "1" : "0", root.saveMode,
            root.microphone ? "1" : "0", root.desktopAudio ? "1" : "0",
            path || "", resolvedMode === "window" ? root.selectedWindowAddress : ""]
    }

    function _validDirectory(path) {
        path = String(path || "")
        return path.length > 0 && path.length <= 4096 && path[0] === "/"
            && path.indexOf("\u0000") < 0 && path.indexOf("\n") < 0
            && path.indexOf("\r") < 0
    }

    function fileUrlToPath(url) {
        let value = String(url || "")
        if (value.indexOf("file://localhost/") === 0)
            value = value.slice("file://localhost".length)
        else if (value.indexOf("file://") === 0)
            value = value.slice("file://".length)
        else
            return ""
        try { value = decodeURIComponent(value) } catch (e) { return "" }
        return root._validDirectory(value) ? value : ""
    }

    function directoryFileUrl(path) {
        path = root._validDirectory(path) ? String(path) : Quickshell.env("HOME")
        return "file://" + path.split("/").map(function(part) {
            return encodeURIComponent(part)
        }).join("/")
    }

    function directoryLabel(path) {
        path = String(path || "").replace(/\/+$/, "")
        if (path === "") return "/"
        const slash = path.lastIndexOf("/")
        return slash >= 0 ? path.slice(slash + 1) : path
    }

    function setCustomDirectory(path) {
        path = String(path || "")
        if (!root._validDirectory(path)) return false
        root.customDirectory = path.replace(/\/+$/, "") || "/"
        root.saveMode = "custom"
        root._persist()
        return true
    }

    function _recordPath() {
        let dir = Quickshell.env("HOME") + "/Documents"
        if (root.saveMode === "desktop") dir = Quickshell.env("HOME") + "/Desktop"
        else if (root.saveMode === "custom" && root._validDirectory(root.customDirectory))
            dir = root.customDirectory
        const stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd 'at' HH.mm.ss")
        return dir + "/Screen Recording " + stamp + ".mkv"
    }

    function _runPending() {
        const action = root.pendingAction
        const captureMode = root.pendingCaptureMode
        root.pendingAction = ""
        root.pendingCaptureMode = ""
        if (action === "screenshot") {
            const destination = root.saveMode === "custom" ? root.customDirectory : ""
            screenshot.command = root._command("screenshot", destination, captureMode)
            screenshot.running = true
        } else if (action === "record") {
            root.recordingPath = root._recordPath()
            root.recordingStartedAt = Date.now()
            root.elapsedSeconds = 0
            root.stopRequested = false
            recorder.command = root._command("record", root.recordingPath, captureMode)
            recorder.running = true
        }
    }

    function stopRecording() {
        if (!recorder.running || root.stopRequested) return
        root.stopRequested = true
        recorder.signal(2)
    }

    function setSaveMode(value) {
        if (["desktop", "documents", "clipboard", "custom"].indexOf(value) < 0) return
        if (value === "custom" && !root._validDirectory(root.customDirectory)) return
        if (root.recordMode && value === "clipboard") return
        root.saveMode = value
        root._persist()
    }

    function setTimerSeconds(value) {
        value = Number(value)
        if ([0, 5, 10].indexOf(value) < 0) return
        root.timerSeconds = value
        root._persist()
    }

    function refreshWindows() {
        if (!windowScan.running) windowScan.running = true
    }

    function reportWindowHover(win) {
        root.hoveredWindowAddress = win ? String(win.address || "") : ""
    }

    function _persist() {
        optionsStore.setText(JSON.stringify({
            mode: root.toolbarMode,
            saveMode: root.saveMode,
            customDirectory: root.customDirectory,
            timerSeconds: root.timerSeconds,
            rememberSelection: root.rememberSelection,
            showPointer: root.showPointer,
            microphone: root.microphone,
            desktopAudio: root.desktopAudio,
            toolbarPosition: root.toolbarPositionStored ? {
                x: root.toolbarAnchorX,
                y: root.toolbarAnchorY
            } : null,
            portionSelections: root.rememberSelection ? root.portionSelections : ({})
        }))
    }

    function _load() {
        try {
            const data = JSON.parse(optionsStore.text() || "{}")
            if (["screen", "window", "portion", "record-screen", "record-window",
                 "record-portion"].indexOf(data.mode) >= 0) {
                root.toolbarMode = data.mode
                root.mode = data.mode
            }
            const loadedDirectory = String(data.customDirectory || "")
            if (root._validDirectory(loadedDirectory))
                root.customDirectory = loadedDirectory.replace(/\/+$/, "") || "/"
            const loadedMode = data.saveMode === "media" ? "documents" : data.saveMode
            if (["desktop", "documents", "clipboard", "custom"].indexOf(loadedMode) >= 0) {
                root.saveMode = loadedMode === "custom" && root.customDirectory === ""
                    ? "documents" : loadedMode
            }
            if (root.recordMode && root.saveMode === "clipboard")
                root.saveMode = "documents"
            if ([0, 5, 10].indexOf(Number(data.timerSeconds)) >= 0)
                root.timerSeconds = Number(data.timerSeconds)
            root.rememberSelection = data.rememberSelection !== false
            root.showPointer = data.showPointer === true
            root.microphone = data.microphone === true
            root.desktopAudio = data.desktopAudio !== false
            if (data.toolbarPosition) {
                const toolbarX = Number(data.toolbarPosition.x)
                const toolbarY = Number(data.toolbarPosition.y)
                if (isFinite(toolbarX) && isFinite(toolbarY)
                        && toolbarX >= 0 && toolbarX <= 1
                        && toolbarY >= 0 && toolbarY <= 1) {
                    root.toolbarAnchorX = toolbarX
                    root.toolbarAnchorY = toolbarY
                    root.toolbarPositionStored = true
                }
            }
            if (root.rememberSelection) {
                const loadedSelections = ({})
                const rawSelections = data.portionSelections || ({})
                const names = Object.keys(rawSelections)
                for (let i = 0; i < names.length; i++) {
                    const name = String(names[i] || "")
                    const value = rawSelections[name] || ({})
                    const x = Number(value.x), y = Number(value.y)
                    const w = Number(value.width), h = Number(value.height)
                    if (/^[A-Za-z0-9._-]{1,64}$/.test(name)
                            && isFinite(x) && isFinite(y) && isFinite(w) && isFinite(h)
                            && w >= 8 && h >= 8) {
                        loadedSelections[name] = {
                            x: Math.round(x), y: Math.round(y),
                            width: Math.round(w), height: Math.round(h)
                        }
                    }
                }
                // Migrate the old shared slot only when its saved mode proves
                // that the geometry came from a Portion capture, not a window.
                if (Object.keys(loadedSelections).length === 0 && data.selection
                        && (data.mode === "portion" || data.mode === "record-portion")) {
                    const oldName = String(data.selection.screen || "")
                    const oldX = Number(data.selection.x), oldY = Number(data.selection.y)
                    const oldW = Number(data.selection.width), oldH = Number(data.selection.height)
                    if (/^[A-Za-z0-9._-]{1,64}$/.test(oldName)
                            && isFinite(oldX) && isFinite(oldY)
                            && isFinite(oldW) && isFinite(oldH)
                            && oldW >= 8 && oldH >= 8) {
                        loadedSelections[oldName] = {
                            x: Math.round(oldX), y: Math.round(oldY),
                            width: Math.round(oldW), height: Math.round(oldH)
                        }
                    }
                }
                root.portionSelections = loadedSelections
            }
        } catch (e) {}
    }

    GlobalShortcut {
        appid: "capture"
        name: "toggle"
        description: "Screenshot and screen recording controls"
        onPressed: root.toggle()
    }

    GlobalShortcut {
        appid: "capture"
        name: "screen"
        description: "Capture the focused screen with saved Screenshot settings"
        onPressed: root.captureScreen()
    }

    GlobalShortcut {
        appid: "capture"
        name: "portion"
        description: "Open Selected Portion without the toolbar"
        onPressed: root.showPortion()
    }

    IpcHandler {
        target: "capture"

        function show() { root.show() }
        function hide() { root.hide() }
        function toggle() { root.toggle() }
        function screen() { root.captureScreen() }
        function portion() { root.showPortion() }
        function stop() { root.stopRecording() }
        function status(): string {
            return JSON.stringify({
                open: root.toolbarOpen,
                toolbar: root.toolbarVisible,
                mode: root.mode,
                toolbarMode: root.toolbarMode,
                recording: root.recording,
                elapsed: root.elapsedSeconds,
                backend: root.recorderBackend,
                recorderProblem: root.recorderProblem,
                overlay: root.overlayActive,
                options: root.optionsOpen,
                folderPicker: root.folderPickerOpen,
                targetScreen: root.targetScreenName,
                windows: root.windowClients.length,
                hovered: root.hoveredWindowAddress !== "",
                toolbarHovered: root.toolbarHovered
            })
        }
    }

    FileView {
        id: optionsStore
        path: Quickshell.stateDir + "/capture-options.json"
        blockLoading: true
        printErrors: false
    }

    Process {
        id: availability
        command: [root.backendScript, "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text)
                    root.recorderAvailable = data.recorder === true
                    root.recorderBackend = String(data.backend || "")
                    root.recorderProblem = String(data.problem || "")
                } catch (e) {
                    root.recorderAvailable = false
                    root.recorderBackend = ""
                    root.recorderProblem = "check-failed"
                }
            }
        }
    }

    Process {
        id: windowScan
        command: [root.windowBackendScript]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text || "[]")
                    root.windowClients = Array.isArray(data) ? data : []
                } catch (e) {
                    root.windowClients = []
                }
            }
        }
    }

    Timer {
        id: windowRefreshDebounce
        interval: 24
        onTriggered: root.refreshWindows()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (root.toolbarOpen && root.baseMode === "window")
                windowRefreshDebounce.restart()
        }
    }

    Process {
        id: screenshot
        command: ["/usr/bin/true"]
        stderr: StdioCollector { id: screenshotError }
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                let detail = screenshotError.text.trim()
                detail = detail.replace(/^capture-tool:\s*/, "")
                if (detail.length > 240) detail = detail.slice(0, 237) + "..."
                Quickshell.execDetached(["notify-send", "-a", "Screenshot",
                    "Screenshot failed", detail || "The capture backend returned an error."])
            }
        }
    }

    Process {
        id: recorder
        command: ["/usr/bin/true"]
        onExited: function(exitCode) {
            const ranLongEnough = root.recordingStartedAt > 0
                && Date.now() - root.recordingStartedAt >= 350
            const wasStopped = root.stopRequested
            root.stopRequested = false
            root.elapsedSeconds = 0
            root.recordingStartedAt = 0
            if (ranLongEnough && wasStopped) {
                Quickshell.execDetached(["notify-send", "-a", "Screenshot",
                    "Screen recording saved", root.recordingPath])
            } else if (exitCode !== 0) {
                Quickshell.execDetached(["notify-send", "-a", "Screenshot",
                    "Screen recording failed",
                    root.recorderProblem === "missing-shared-library"
                        ? "Run sudo pacman -Syu, reboot, then try again."
                        : root.recorderAvailable ? "GPU Screen Recorder returned an error."
                                                 : "Install gpu-screen-recorder first."])
            }
        }
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdownRemaining--
            if (root.countdownRemaining <= 0) root._unmapAndRun()
        }
    }

    Timer {
        id: unmapDelay
        interval: 180
        onTriggered: root._runPending()
    }

    Timer {
        interval: 250
        repeat: true
        running: root.recording
        onTriggered: root.elapsedSeconds = Math.max(0,
            Math.floor((Date.now() - root.recordingStartedAt) / 1000))
    }

    Component.onCompleted: {
        root._load()
        availability.running = true
    }
}
