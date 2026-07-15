import QtQuick
import QtQuick.Controls
import Quickshell.Io
import ".." as Bar

Item {
    id: root

    property string mode: ""
    property string presentedMode: "repeat"
    property var currentRepeatDays: []
    property string currentSound: "Radial"
    property var pendingRepeatDays: []
    property string pendingSound: "Radial"
    property color accent: "#007aff"
    property color primaryText: "#1a1a1a"
    property color secondaryText: Qt.rgba(0, 0, 0, 0.55)
    property color hoverFill: Qt.rgba(0, 0, 0, 0.06)
    property color lineColor: Qt.rgba(0, 0, 0, 0.10)
    property string pickedPath: ""
    property string probeOutput: ""
    property string createOutput: ""
    property string errorText: ""
    signal cancelled
    signal repeatSelectionChanged(var days)
    signal soundSelected(string id)
    signal waveformRequested(var sound)
    signal filePickerRequested

    readonly property var repeatOptions: [
        { day: 1, label: "Monday" },
        { day: 2, label: "Tuesday" },
        { day: 3, label: "Wednesday" },
        { day: 4, label: "Thursday" },
        { day: 5, label: "Friday" },
        { day: 6, label: "Saturday" },
        { day: 0, label: "Sunday" }
    ]
    readonly property var builtins: [
        { id: "Radial", label: "Radial", duration: 0, builtin: true },
        { id: "Beacon", label: "Beacon", duration: 0, builtin: true },
        { id: "Chimes", label: "Chimes", duration: 0, builtin: true },
        { id: "Signal", label: "Signal", duration: 0, builtin: true }
    ]
    readonly property var soundItems: builtins.concat(Bar.ClockService.customSounds)
    implicitWidth: 278
    implicitHeight: detailColumn.implicitHeight

    onModeChanged: {
        if (previewProcess.running) previewProcess.running = false
        if (mode !== "") presentedMode = mode
        resetPending()
    }
    onCurrentRepeatDaysChanged: if (mode === "repeat")
        pendingRepeatDays = Array.isArray(currentRepeatDays) ? currentRepeatDays.slice() : []
    onCurrentSoundChanged: if (mode === "sound") pendingSound = currentSound

    function resetPending() {
        pendingRepeatDays = currentRepeatDays ? currentRepeatDays.slice() : []
        pendingSound = currentSound || "Radial"
        errorText = ""
    }

    function repeatSelected(day) {
        return Array.isArray(pendingRepeatDays) && pendingRepeatDays.indexOf(day) >= 0
    }

    function toggleRepeatDay(day) {
        let next = Array.isArray(pendingRepeatDays) ? pendingRepeatDays.slice() : []
        let index = next.indexOf(day)
        if (index >= 0) next.splice(index, 1)
        else next.push(day)
        pendingRepeatDays = next
        repeatSelectionChanged(next)
    }

    function repeatOptionSelected(option) {
        return repeatSelected(option.day)
    }

    function selectRepeatOption(option) {
        toggleRepeatDay(option.day)
    }

    function previewSound(sound) {
        if (!sound) return
        if (previewProcess.running) previewProcess.running = false
        previewProcess.command = Bar.ClockService.soundCommand(sound)
        previewProcess.running = true
    }

    function closeDetail() {
        if (previewProcess.running) previewProcess.running = false
        cancelled()
    }

    function confirmSound() {
        if (previewProcess.running) previewProcess.running = false
        soundSelected(pendingSound)
    }

    function chooseSoundFile() {
        if (probeProcess.running || createProcess.running) return
        if (previewProcess.running) previewProcess.running = false
        errorText = ""
        filePickerRequested()
    }

    function acceptPickedFile(path) {
        if (path) beginProbe(path)
    }

    function beginProbe(path) {
        if (!path) return
        probeOutput = ""
        probeProcess.command = ["python3", Bar.ClockService.soundScript, "probe", path]
        probeProcess.running = true
    }

    function createSound(info) {
        createOutput = ""
        createProcess.command = ["python3", Bar.ClockService.soundScript, "create", info.path,
            "0", String(info.duration), Bar.ClockService.soundDir]
        createProcess.running = true
    }

    Process { id: previewProcess }

    Process {
        id: probeProcess
        stdout: StdioCollector { onStreamFinished: root.probeOutput = text.trim() }
        onExited: {
            try {
                let info = JSON.parse(root.probeOutput || "{}")
                if (!info.ok) {
                    root.errorText = info.error || "Could not read this audio file."
                } else if (Number(info.duration) > 30) {
                    root.waveformRequested(info)
                } else {
                    root.createSound(info)
                }
            } catch (e) {
                root.errorText = "Could not read this audio file."
            }
        }
    }

    Process {
        id: createProcess
        stdout: StdioCollector { onStreamFinished: root.createOutput = text.trim() }
        onExited: {
            try {
                let sound = JSON.parse(root.createOutput || "{}")
                if (!sound.ok) {
                    root.errorText = sound.error || "Could not add this sound."
                    return
                }
                Bar.ClockService.addCustomSound(sound)
                root.pendingSound = sound.id
                root.previewSound(sound.id)
            } catch (e) {
                root.errorText = "Could not add this sound."
            }
        }
    }

    component DetailRow: Rectangle {
        id: row
        property string label: ""
        property string detail: ""
        property bool selected: false
        property bool destructiveAction: false
        signal pressed
        signal removePressed
        width: ListView.view ? ListView.view.width : parent.width
        height: 48
        color: rowHover.hovered ? root.hoverFill : "transparent"
        scale: rowTap.pressed ? Bar.ThemeService.pressScale : 1
        Behavior on scale { Bar.AppleSpring { spring: 20 } }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.right: removeButton.visible ? removeButton.left : check.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: row.label
            color: root.primaryText
            font.family: "SF Pro Display"
            font.pixelSize: 14
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Text {
            id: check
            anchors.right: removeButton.visible ? removeButton.left : parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: row.selected ? "✓" : row.detail
            color: row.selected ? root.accent : root.secondaryText
            font.family: "SF Pro Display"
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Rectangle {
            id: removeButton
            visible: row.destructiveAction
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 30
            radius: 15
            color: removeHover.hovered ? Qt.rgba(1, 0.23, 0.19, 0.12) : "transparent"
            Text {
                anchors.centerIn: parent
                text: "×"
                color: "#ff3b30"
                font.family: "SF Pro Display"
                font.pixelSize: 17
            }
            HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onPressedChanged: if (pressed) row.removePressed() }
        }
        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: rowTap; onPressedChanged: if (pressed) row.pressed() }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineColor }
    }

    Column {
        id: detailColumn
        width: parent.width
        spacing: 10

        Item {
            width: parent.width
            height: 30
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 24
                scale: backTap.pressed ? Bar.ThemeService.pressScale : 1
                Behavior on scale { Bar.AppleSpring { spring: 20 } }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { id: backTap; onPressedChanged: if (pressed) root.closeDetail() }
            }
            Text {
                anchors.centerIn: parent
                text: root.presentedMode === "repeat" ? "Repeat" : "Sound"
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                font.letterSpacing: -0.2
            }
            Text {
                visible: root.presentedMode === "sound"
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "✓"
                color: root.accent
                font.family: "SF Pro Display"
                font.pixelSize: 19
                font.weight: Font.DemiBold
                scale: confirmTap.pressed ? Bar.ThemeService.pressScale : 1
                Behavior on scale { Bar.AppleSpring { spring: 20 } }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    id: confirmTap
                    onPressedChanged: if (pressed) root.confirmSound()
                }
            }
        }

        Rectangle {
            visible: root.presentedMode === "sound"
            width: parent.width
            height: 42
            radius: 12
            color: addHover.hovered ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                                    : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12)
            scale: addTap.pressed ? Bar.ThemeService.pressScale : 1
            Behavior on scale { Bar.AppleSpring { spring: 20 } }
            Text {
                anchors.centerIn: parent
                text: probeProcess.running || createProcess.running ? "Reading Sound…" : "+ Add Sound"
                color: root.accent
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                id: addTap
                enabled: !probeProcess.running && !createProcess.running
                onPressedChanged: if (pressed) root.chooseSoundFile()
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

        Rectangle {
            width: parent.width
            height: root.presentedMode === "repeat" ? Math.min(7, root.repeatOptions.length) * 48
                : Math.min(6, root.soundItems.length) * 48
            radius: 12
            color: "transparent"
            clip: true

            ClockKineticList {
                anchors.fill: parent
                clip: true
                wheelGain: 48
                model: root.presentedMode === "repeat" ? root.repeatOptions : root.soundItems
                ScrollBar.vertical: ScrollBar {
                    policy: (root.presentedMode === "repeat" && root.repeatOptions.length > 7)
                        || (root.presentedMode === "sound" && root.soundItems.length > 6)
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }
                delegate: DetailRow {
                    required property int index
                    required property var modelData
                    label: root.presentedMode === "repeat" ? String(modelData.label) : String(modelData.label || "Sound")
                    detail: root.presentedMode === "sound" && Number(modelData.duration || 0) > 0
                        ? Bar.ClockService.durationLabel(Math.round(modelData.duration)) : ""
                    selected: root.presentedMode === "repeat" ? root.repeatOptionSelected(modelData)
                                                     : modelData.id === root.pendingSound
                    destructiveAction: root.presentedMode === "sound" && modelData.builtin !== true
                    onPressed: {
                        if (root.presentedMode === "repeat") root.selectRepeatOption(modelData)
                        else {
                            root.pendingSound = modelData.id
                            root.previewSound(modelData.id)
                        }
                    }
                    onRemovePressed: {
                        if (root.presentedMode !== "sound" || modelData.builtin === true) return
                        if (previewProcess.running) previewProcess.running = false
                        let customIndex = index - root.builtins.length
                        Bar.ClockService.removeCustomSound(customIndex)
                        if (modelData.id === root.pendingSound) root.pendingSound = "Radial"
                    }
                }
            }
        }
    }
}
