import QtQuick
import ".." as Bar

Item {
    id: root

    property string mode: ""
    property bool dark: false
    property color accent: "#007aff"
    property color primaryText: "#1a1a1a"
    property color secondaryText: Qt.rgba(0, 0, 0, 0.55)
    property color surface: Qt.rgba(0, 0, 0, 0.05)
    property color lineColor: Qt.rgba(0, 0, 0, 0.10)
    property int alarmHour: 7
    property int alarmMinute: 0
    property bool alarmPm: false
    property var repeatDays: []
    property string selectedSound: "Radial"
    property bool snooze: true
    property int timerHours: 0
    property int timerMinutes: 5
    property int timerSeconds: 0
    property int focusMinutes: 25
    property int breakMinutes: 5
    property int focusRounds: 4
    signal cancelled
    signal saved
    signal detailRequested(string mode)

    readonly property string title: mode === "alarm" ? "Add Alarm"
        : mode === "timer" ? "Add Timer" : "Add Pomodoro"
    implicitWidth: 310
    implicitHeight: editorColumn.implicitHeight

    onModeChanged: reset()

    function reset() {
        let now = new Date()
        let nextMinutes = Math.floor(now.getMinutes() / 5) * 5 + 5
        let nextHour = now.getHours() + (nextMinutes >= 60 ? 1 : 0)
        alarmHour = nextHour % 12 || 12
        alarmMinute = nextMinutes % 60
        alarmPm = nextHour % 24 >= 12
        repeatDays = []
        selectedSound = "Radial"
        snooze = true
        timerHours = 0
        timerMinutes = 5
        timerSeconds = 0
        focusMinutes = 25
        breakMinutes = 5
        focusRounds = 4
        labelInput.text = mode === "pomodoro" ? "Focus" : (mode === "alarm" ? "Alarm" : "Timer")
    }

    function commit() {
        if (mode === "alarm") {
            let hour = alarmHour % 12 + (alarmPm ? 12 : 0)
            Bar.ClockService.addAlarm(hour, alarmMinute, labelInput.text, repeatLabel(), repeatDays,
                selectedSound, snooze)
        } else if (mode === "timer") {
            Bar.ClockService.addTimer(timerHours * 3600 + timerMinutes * 60 + timerSeconds,
                labelInput.text, selectedSound)
        } else {
            Bar.ClockService.addPomodoro(labelInput.text, focusMinutes, breakMinutes, focusRounds)
        }
        saved()
    }

    function hasDay(day) {
        return Array.isArray(repeatDays) && repeatDays.indexOf(day) >= 0
    }

    function repeatLabel() {
        let days = Array.isArray(repeatDays) ? repeatDays : []
        if (days.length === 0) return "Once"
        if (days.length === 7) return "Every Day"
        if (days.length === 5 && hasDay(1) && hasDay(2) && hasDay(3) && hasDay(4) && hasDay(5))
            return "Weekdays"
        if (days.length === 2 && hasDay(0) && hasDay(6)) return "Weekends"
        return "Custom"
    }

    component HeaderAction: Text {
        id: action
        property bool enabled: true
        signal pressed
        color: enabled ? root.accent : root.secondaryText
        opacity: enabled ? 1 : 0.45
        font.family: "SF Pro Display"
        font.pixelSize: 14
        font.weight: Font.DemiBold
        scale: actionTap.pressed ? Bar.ThemeService.pressScale : 1
        Behavior on scale { Bar.AppleSpring { spring: 20 } }
        HoverHandler { cursorShape: Qt.PointingHandCursor; enabled: action.enabled }
        TapHandler {
            id: actionTap
            enabled: action.enabled
            onPressedChanged: if (pressed) action.pressed()
        }
    }

    component Stepper: Item {
        id: stepper
        property int value: 0
        property int minimum: 0
        property int maximum: 59
        property int step: 1
        property string suffix: ""
        signal changed(int value)
        width: 76
        height: 92
        onValueChanged: if (!stepperInput.activeFocus)
            stepperInput.text = String(stepper.value).padStart(2, "0")

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            text: "⌃"
            color: upHover.hovered ? root.primaryText : root.secondaryText
            font.family: "SF Pro Display"
            font.pixelSize: 16
            HoverHandler { id: upHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onPressedChanged: if (pressed) {
                    let next = stepper.value + stepper.step
                    if (next > stepper.maximum) next = stepper.minimum
                    stepper.changed(next)
                }
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 42
            radius: 12
            color: root.surface
            TextInput {
                id: stepperInput
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: stepper.suffix === "" ? 8 : 20
                anchors.verticalCenter: parent.verticalCenter
                text: String(stepper.value).padStart(2, "0")
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 22
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                inputMethodHints: Qt.ImhDigitsOnly
                selectByMouse: true
                validator: IntValidator { bottom: stepper.minimum; top: stepper.maximum }
                onActiveFocusChanged: {
                    if (activeFocus) selectAll()
                    else commitValue()
                }
                onAccepted: {
                    commitValue()
                    focus = false
                }
                function commitValue() {
                    let parsed = parseInt(text)
                    if (isNaN(parsed)) parsed = stepper.value
                    parsed = Math.max(stepper.minimum, Math.min(stepper.maximum, parsed))
                    stepper.changed(parsed)
                    text = String(parsed).padStart(2, "0")
                }
            }
            Text {
                visible: stepper.suffix !== ""
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: stepper.suffix
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 15
                font.weight: Font.Medium
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: "⌄"
            color: downHover.hovered ? root.primaryText : root.secondaryText
            font.family: "SF Pro Display"
            font.pixelSize: 16
            HoverHandler { id: downHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onPressedChanged: if (pressed) {
                    let next = stepper.value - stepper.step
                    if (next < stepper.minimum) next = stepper.maximum
                    stepper.changed(next)
                }
            }
        }
    }

    component SettingsRow: Rectangle {
        id: settingsRow
        property string label: ""
        property string value: ""
        signal pressed
        width: parent ? parent.width : 0
        height: 46
        color: rowHover.hovered ? root.surface : "transparent"
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: settingsRow.label
            color: root.primaryText
            font.family: "SF Pro Display"
            font.pixelSize: 14
            font.weight: Font.Medium
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: settingsRow.value
            color: root.secondaryText
            font.family: "SF Pro Display"
            font.pixelSize: 14
        }
        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onPressedChanged: if (pressed) settingsRow.pressed() }
    }

    Column {
        id: editorColumn
        width: parent.width
        spacing: 12

        Item {
            width: parent.width
            height: 30
            HeaderAction {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Cancel"
                onPressed: root.cancelled()
            }
            Text {
                anchors.centerIn: parent
                text: root.title
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                font.letterSpacing: -0.2
            }
            HeaderAction {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Save"
                enabled: root.mode !== "timer" || root.timerHours + root.timerMinutes + root.timerSeconds > 0
                onPressed: root.commit()
            }
        }

        Row {
            visible: root.mode === "alarm"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Stepper { value: root.alarmHour; minimum: 1; maximum: 12; onChanged: value => root.alarmHour = value }
            Stepper { value: root.alarmMinute; step: 1; onChanged: value => root.alarmMinute = value }
            Rectangle {
                width: 76
                height: 42
                radius: 12
                anchors.verticalCenter: parent.verticalCenter
                color: root.surface
                Text {
                    anchors.centerIn: parent
                    text: root.alarmPm ? "PM" : "AM"
                    color: root.primaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 20
                    font.weight: Font.Medium
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onPressedChanged: if (pressed) root.alarmPm = !root.alarmPm }
            }
        }

        Row {
            visible: root.mode === "timer"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Stepper { value: root.timerHours; maximum: 23; suffix: "h"; onChanged: value => root.timerHours = value }
            Stepper { value: root.timerMinutes; suffix: "m"; onChanged: value => root.timerMinutes = value }
            Stepper { value: root.timerSeconds; suffix: "s"; onChanged: value => root.timerSeconds = value }
        }

        Column {
            visible: root.mode === "pomodoro"
            width: parent.width
            spacing: 6
            Text {
                text: "FOCUS · BREAK · ROUNDS"
                color: root.secondaryText
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Stepper { value: root.focusMinutes; minimum: 1; maximum: 90; suffix: "m"; onChanged: value => root.focusMinutes = value }
                Stepper { value: root.breakMinutes; minimum: 1; maximum: 30; suffix: "m"; onChanged: value => root.breakMinutes = value }
                Stepper { value: root.focusRounds; minimum: 1; maximum: 12; suffix: "×"; onChanged: value => root.focusRounds = value }
            }
        }

        Rectangle {
            width: parent.width
            height: 48
            radius: 12
            color: root.surface
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "Label"
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            TextInput {
                id: labelInput
                anchors.left: parent.left
                anchors.leftMargin: 78
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: TextInput.AlignRight
                color: root.secondaryText
                selectionColor: root.accent
                font.family: "SF Pro Display"
                font.pixelSize: 14
                maximumLength: 32
            }
        }

        Rectangle {
            visible: root.mode === "alarm"
            width: parent.width
            height: alarmSettings.implicitHeight
            radius: 12
            color: root.surface
            clip: true
            Column {
                id: alarmSettings
                width: parent.width
                SettingsRow {
                    label: "Repeat"
                    value: root.repeatLabel() + "  ›"
                    onPressed: root.detailRequested("repeat")
                }
                Rectangle { width: parent.width; height: 1; color: root.lineColor }
                SettingsRow {
                    label: "Sound"
                    value: Bar.ClockService.soundLabel(root.selectedSound) + "  ›"
                    onPressed: root.detailRequested("sound")
                }
                Rectangle { width: parent.width; height: 1; color: root.lineColor }
                SettingsRow {
                    label: "Snooze"
                    value: root.snooze ? "On" : "Off"
                    onPressed: root.snooze = !root.snooze
                }
            }
        }

        Rectangle {
            visible: root.mode === "timer"
            width: parent.width
            height: 46
            radius: 12
            color: root.surface
            clip: true
            SettingsRow {
                label: "Sound"
                value: Bar.ClockService.soundLabel(root.selectedSound) + "  ›"
                onPressed: root.detailRequested("sound")
            }
        }
    }
}
