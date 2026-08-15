import QtQuick
import Quickshell.Io
import ".." as Bar

Item {
    id: root

    property var soundInfo: ({})
    property real selectionStart: 0
    property real selectionEnd: 30
    property string createOutput: ""
    property string errorText: ""
    property color accent: "#007aff"
    property color primaryText: "#1a1a1a"
    property color secondaryText: Qt.rgba(0, 0, 0, 0.55)
    property color surface: Qt.rgba(0, 0, 0, 0.05)
    property color lineColor: Qt.rgba(0, 0, 0, 0.10)
    property bool active: true
    property string activeHandle: ""
    signal cancelled
    signal created(var sound)

    readonly property real duration: Math.max(0.5, Number(soundInfo.duration || 0.5))
    readonly property real maxSelection: 30
    readonly property real selectedDuration: Math.max(0, selectionEnd - selectionStart)
    readonly property real handleInset: 7
    implicitWidth: 410
    implicitHeight: editorColumn.implicitHeight
    focus: active
    activeFocusOnTab: true

    onSoundInfoChanged: scheduleSelectionReset()
    onSelectionStartChanged: stopPreview()
    onSelectionEndChanged: stopPreview()
    onActiveChanged: {
        if (active) scheduleSelectionReset()
        else {
            stopPreview()
            activeHandle = ""
        }
    }
    onActiveFocusChanged: if (!activeFocus) activeHandle = ""
    Component.onCompleted: scheduleSelectionReset()
    Keys.onLeftPressed: event => {
        nudgeSelection(-1)
        event.accepted = true
    }
    Keys.onRightPressed: event => {
        nudgeSelection(1)
        event.accepted = true
    }

    function scheduleSelectionReset() {
        stopPreview()
        Qt.callLater(root.resetSelection)
    }

    function resetSelection() {
        selectionStart = 0
        selectionEnd = Math.min(maxSelection, duration)
        activeHandle = ""
        waveform.requestPaint()
    }

    function graphXForTime(value) {
        let ratio = Math.max(0, Math.min(1, value / duration))
        return handleInset + ratio * Math.max(1, graph.width - handleInset * 2)
    }

    function nudgeSelection(direction) {
        stopPreview()
        if (activeHandle === "start") {
            let lower = Math.max(0, selectionEnd - maxSelection)
            let upper = selectionEnd - 0.5
            selectionStart = Math.max(lower, Math.min(upper, selectionStart + direction))
            return
        }
        if (activeHandle === "end") {
            let lower = selectionStart + 0.5
            let upper = Math.min(duration, selectionStart + maxSelection)
            selectionEnd = Math.max(lower, Math.min(upper, selectionEnd + direction))
            return
        }
        let span = selectionEnd - selectionStart
        let nextStart = Math.max(0, Math.min(duration - span, selectionStart + direction))
        selectionStart = nextStart
        selectionEnd = nextStart + span
    }

    function timeLabel(value) {
        value = Math.max(0, value)
        let minutes = Math.floor(value / 60)
        let seconds = Math.floor(value % 60)
        let tenths = Math.floor((value - Math.floor(value)) * 10)
        return minutes + ":" + String(seconds).padStart(2, "0") + "." + tenths
    }

    function saveSelection() {
        if (createProcess.running) return
        createOutput = ""
        errorText = ""
        createProcess.command = ["python3", Bar.ClockService.soundScript, "create", soundInfo.path,
            String(selectionStart), String(selectionEnd), Bar.ClockService.soundDir]
        createProcess.running = true
    }

    function stopPreview() {
        if (previewProcess.running) previewProcess.running = false
    }

    function togglePreview() {
        if (previewProcess.running) {
            previewProcess.running = false
            return
        }
        let path = String(soundInfo.path || "")
        if (path === "" || selectedDuration <= 0) return
        previewProcess.command = ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet",
            "-ss", String(selectionStart), "-t", String(selectedDuration), path]
        previewProcess.running = true
    }

    Process { id: previewProcess }

    Process {
        id: createProcess
        stdout: StdioCollector { onStreamFinished: root.createOutput = text.trim() }
        onExited: {
            try {
                let sound = JSON.parse(root.createOutput || "{}")
                if (!sound.ok) {
                    root.errorText = sound.error || "Could not create this sound."
                    return
                }
                Bar.ClockService.addCustomSound(sound)
                root.created(sound)
            } catch (e) {
                root.errorText = "Could not create this sound."
            }
        }
    }

    Column {
        id: editorColumn
        width: parent.width
        spacing: 12

        Item {
            width: parent.width
            height: 30
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Cancel"
                color: root.accent
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                scale: cancelTap.pressed ? Bar.ThemeService.pressScale : 1
                Behavior on scale { Bar.AppleSpring { spring: 20 } }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { id: cancelTap; onTapped: root.cancelled() }
            }
            Text {
                anchors.centerIn: parent
                text: "Trim Sound"
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                font.letterSpacing: -0.2
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: createProcess.running ? "Saving…" : "Add"
                color: root.accent
                opacity: createProcess.running ? 0.45 : 1
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                scale: saveTap.pressed ? Bar.ThemeService.pressScale : 1
                Behavior on scale { Bar.AppleSpring { spring: 20 } }
                HoverHandler { cursorShape: Qt.PointingHandCursor; enabled: !createProcess.running }
                TapHandler {
                    id: saveTap
                    enabled: !createProcess.running
                    onTapped: root.saveSelection()
                }
            }
        }

        Text {
            width: parent.width
            text: String(root.soundInfo.label || "Sound")
            color: root.primaryText
            font.family: "SF Pro Display"
            font.pixelSize: 14
            font.weight: Font.DemiBold
            elide: Text.ElideMiddle
        }

        Text {
            width: parent.width
            text: "Drag the start and end markers · maximum 30 seconds"
            color: root.secondaryText
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }

        Rectangle {
            id: graph
            width: parent.width
            height: 128
            radius: 14
            color: root.surface
            clip: true

            Canvas {
                id: waveform
                anchors.fill: parent
                anchors.margins: 10
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    let ctx = getContext("2d")
                    ctx.reset()
                    let peaks = root.soundInfo.peaks || []
                    if (peaks.length === 0) return
                    let center = height / 2
                    let step = width / peaks.length
                    ctx.fillStyle = root.secondaryText
                    for (let i = 0; i < peaks.length; i++) {
                        let barHeight = Math.max(2, Number(peaks[i]) * (height - 12))
                        ctx.fillRect(i * step, center - barHeight / 2, Math.max(1, step - 1), barHeight)
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: startHandle.x + startHandle.width / 2
                color: Qt.rgba(0, 0, 0, 0.38)
            }
            Rectangle {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width - endHandle.x - endHandle.width / 2
                color: Qt.rgba(0, 0, 0, 0.38)
            }
            Rectangle {
                x: startHandle.x + startHandle.width / 2
                width: Math.max(0, endHandle.x - startHandle.x)
                height: parent.height
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
            }

            Rectangle {
                id: startHandle
                readonly property bool selected: root.activeHandle === "start"
                x: root.graphXForTime(root.selectionStart) - width / 2
                width: 3
                height: graph.height
                color: selected ? root.accent : "#ffffff"
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 5
                    width: 13
                    height: 13
                    radius: 6.5
                    color: startHandle.color
                    border.width: startHandle.selected ? 0 : 1
                    border.color: Qt.rgba(0, 0, 0, 0.18)
                }
            }
            Rectangle {
                id: endHandle
                readonly property bool selected: root.activeHandle === "end"
                x: root.graphXForTime(root.selectionEnd) - width / 2
                width: 3
                height: graph.height
                color: selected ? root.accent : "#ffffff"
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 5
                    width: 13
                    height: 13
                    radius: 6.5
                    color: endHandle.color
                    border.width: endHandle.selected ? 0 : 1
                    border.color: Qt.rgba(0, 0, 0, 0.18)
                }
            }

            MouseArea {
                id: trimDrag
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pressed && dragMode === "range" ? Qt.ClosedHandCursor : Qt.SizeHorCursor
                property string dragMode: ""
                property real pressX: 0
                property real originStart: 0
                property real originEnd: 0
                onPressed: mouse => {
                    root.forceActiveFocus(Qt.MouseFocusReason)
                    let startCenter = startHandle.x + startHandle.width / 2
                    let endCenter = endHandle.x + endHandle.width / 2
                    let startDistance = Math.abs(mouse.x - startCenter)
                    let endDistance = Math.abs(mouse.x - endCenter)
                    if (startDistance <= 14) dragMode = "start"
                    else if (endDistance <= 14) dragMode = "end"
                    else if (mouse.x > startCenter && mouse.x < endCenter) dragMode = "range"
                    else dragMode = startDistance <= endDistance ? "start" : "end"
                    root.activeHandle = dragMode === "range" ? "" : dragMode
                    pressX = mouse.x
                    originStart = root.selectionStart
                    originEnd = root.selectionEnd
                }
                onPositionChanged: mouse => {
                    if (pressed) updateSelection(mouse.x)
                }
                onReleased: dragMode = ""
                onCanceled: dragMode = ""
                function updateSelection(pointerX) {
                    let trackWidth = Math.max(1, width - root.handleInset * 2)
                    let delta = (pointerX - pressX) / trackWidth * root.duration
                    if (dragMode === "range") {
                        let span = originEnd - originStart
                        let nextStart = Math.max(0, Math.min(root.duration - span, originStart + delta))
                        root.selectionStart = nextStart
                        root.selectionEnd = nextStart + span
                        return
                    }
                    if (dragMode === "start") {
                        let lower = Math.max(0, root.selectionEnd - root.maxSelection)
                        let upper = root.selectionEnd - 0.5
                        root.selectionStart = Math.max(lower, Math.min(originStart + delta, upper))
                    } else {
                        let lower = root.selectionStart + 0.5
                        let upper = Math.min(root.duration, root.selectionStart + root.maxSelection)
                        root.selectionEnd = Math.min(upper, Math.max(originEnd + delta, lower))
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 20
            Text {
                anchors.left: parent.left
                text: root.timeLabel(root.selectionStart)
                color: root.secondaryText
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
            Row {
                anchors.centerIn: parent
                spacing: 7

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    height: 26
                    radius: 13
                    color: playHover.hovered
                        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22)
                        : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
                    scale: playTap.pressed ? Bar.ThemeService.pressScale : 1
                    Behavior on scale { Bar.AppleSpring { spring: 24 } }

                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: previewProcess.running ? 0 : 1
                        text: previewProcess.running ? "■" : "▶"
                        color: root.accent
                        font.family: "SF Pro Display"
                        font.pixelSize: previewProcess.running ? 10 : 11
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { id: playHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        id: playTap
                        onTapped: root.togglePreview()
                    }
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.timeLabel(root.selectedDuration)
                    color: root.accent
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
            Text {
                anchors.right: parent.right
                text: root.timeLabel(root.selectionEnd)
                color: root.secondaryText
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
        }

        Text {
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText
            color: "#ff453a"
            font.family: "SF Pro Display"
            font.pixelSize: 11
            wrapMode: Text.Wrap
        }
    }
}
