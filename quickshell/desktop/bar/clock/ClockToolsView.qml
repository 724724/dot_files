import QtQuick
import QtQuick.Controls
import ".." as Bar

Item {
    id: root

    property int page: 0
    property bool dark: false
    property color accent: "#007aff"
    property color primaryText: "#1a1a1a"
    property color secondaryText: Qt.rgba(0, 0, 0, 0.55)
    property color hoverFill: Qt.rgba(0, 0, 0, 0.06)
    property color lineColor: Qt.rgba(0, 0, 0, 0.10)
    signal pageRequested(int value)
    signal editorRequested(string mode)

    readonly property var titles: ["Clock", "Stopwatch", "Alarm", "Timer", "Pomodoro"]
    readonly property real bodyHeight: page === 0 ? 100
        : page === 1 ? (Bar.ClockService.stopwatchLaps.length === 0 ? 96
            : 102 + Math.min(5, Bar.ClockService.stopwatchLaps.length) * 34)
        : page === 2 ? (Bar.ClockService.alarms.length === 0 ? 32
            : 50 + Math.min(5, Bar.ClockService.alarms.length) * 58)
        : page === 3 ? (Bar.ClockService.timers.length === 0 ? 32
            : 50 + Math.min(5, Bar.ClockService.timers.length) * 58)
        : (Bar.ClockService.pomodoros.length === 0 ? 32
            : 50 + Math.min(5, Bar.ClockService.pomodoros.length) * 64)

    implicitWidth: 294
    implicitHeight: header.height + 10 + bodyViewport.height

    function movePage(delta) {
        let next = (page + delta + titles.length) % titles.length
        pageRequested(next)
    }

    component CircleButton: Rectangle {
        id: button
        property string glyph: ""
        property bool enabled: true
        signal pressed
        width: 30
        height: 30
        radius: 15
        opacity: enabled ? 1 : 0.35
        color: buttonHover.hovered ? root.hoverFill : "transparent"
        scale: buttonTap.pressed ? Bar.ThemeService.pressScale : 1
        Behavior on scale { Bar.AppleSpring { spring: 20 } }
        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: root.primaryText
            font.family: "SF Pro Display"
            font.pixelSize: 20
            font.weight: Font.Medium
        }
        HoverHandler { id: buttonHover; enabled: button.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: buttonTap
            enabled: button.enabled
            onPressedChanged: if (pressed) button.pressed()
        }
    }

    component PillButton: Rectangle {
        id: pill
        property string label: ""
        property bool filled: false
        property bool enabled: true
        signal pressed
        height: 32
        width: pillText.implicitWidth + 24
        radius: 16
        opacity: enabled ? 1 : 0.38
        color: filled ? root.accent : (pillHover.hovered ? root.hoverFill : "transparent")
        border.width: filled ? 0 : 1
        border.color: root.lineColor
        scale: pillTap.pressed ? Bar.ThemeService.pressScale : 1
        Behavior on scale { Bar.AppleSpring { spring: 20 } }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            color: pill.filled ? "#ffffff" : root.primaryText
            font.family: "SF Pro Display"
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        HoverHandler { id: pillHover; enabled: pill.enabled; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: pillTap
            enabled: pill.enabled
            onPressedChanged: if (pressed) pill.pressed()
        }
    }

    Item {
        id: header
        width: parent.width
        height: 32

        CircleButton {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: "‹"
            onPressed: root.movePage(-1)
        }

        Text {
            anchors.centerIn: parent
            text: root.titles[root.page]
            color: root.primaryText
            font.family: "SF Pro Display"
            font.pixelSize: 17
            font.weight: Font.DemiBold
            font.letterSpacing: -0.2
        }

        CircleButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "›"
            onPressed: root.movePage(1)
        }
    }

    Item {
        id: bodyViewport
        anchors.top: header.bottom
        anchors.topMargin: 10
        width: parent.width
        height: root.bodyHeight
        clip: true

        Row {
            id: pages
            x: -root.page * bodyViewport.width
            height: bodyViewport.height
            Behavior on x { Bar.AppleSpring { spring: 30; damping: Bar.ThemeService.momentumDamping; epsilon: 0.1 } }

            Item {
                width: bodyViewport.width
                height: bodyViewport.height

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    spacing: 6
                    Text {
                        id: clockTime
                        text: Qt.formatDateTime(Bar.ClockService.now, "HH:mm")
                        color: root.primaryText
                        font.family: "SF Pro Display"
                        font.pixelSize: 50
                        font.weight: Font.Light
                        font.letterSpacing: -1.1
                        lineHeightMode: Text.ProportionalHeight
                        lineHeight: 0.94
                    }
                    Text {
                        anchors.baseline: clockTime.baseline
                        text: Qt.formatDateTime(Bar.ClockService.now, "ss")
                        color: root.accent
                        font.family: "SF Pro Display"
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.35
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    text: Qt.formatDateTime(Bar.ClockService.now, "dddd, d MMMM yyyy")
                    color: root.secondaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
            }

            Item {
                width: bodyViewport.width
                height: bodyViewport.height

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: Bar.ClockService.durationLabelMs(Bar.ClockService.stopwatchElapsedMs)
                    color: root.primaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 42
                    font.weight: Font.Light
                    font.letterSpacing: -0.8
                    font.features: { "tnum": 1 }
                }

                Row {
                    id: stopwatchActions
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 56
                    spacing: 8
                    PillButton {
                        label: Bar.ClockService.stopwatchRunning ? "Pause" : "Start"
                        filled: true
                        onPressed: Bar.ClockService.toggleStopwatch()
                    }
                    PillButton {
                        label: Bar.ClockService.stopwatchRunning ? "Lap" : "Reset"
                        enabled: Bar.ClockService.stopwatchRunning || Bar.ClockService.stopwatchElapsedMs > 0
                        onPressed: {
                            if (Bar.ClockService.stopwatchRunning) Bar.ClockService.addLap()
                            else Bar.ClockService.resetStopwatch()
                        }
                    }
                }

                ClockKineticList {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: stopwatchActions.bottom
                    anchors.topMargin: 10
                    height: Math.min(5, Bar.ClockService.stopwatchLaps.length) * 34
                    visible: Bar.ClockService.stopwatchLaps.length > 0
                    wheelGain: 34
                    clip: true
                    model: Bar.ClockService.stopwatchLaps
                    boundsBehavior: Flickable.DragAndOvershootBounds
                    rebound: Transition { SpringAnimation { properties: "x,y"; spring: 22; damping: 0.8; epsilon: 0.2 } }
                    delegate: Item {
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        height: 34
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Lap " + (Bar.ClockService.stopwatchLaps.length - index)
                            color: root.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: Bar.ClockService.durationLabelMs(modelData)
                            color: root.primaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }
                    }
                }
            }

            Item {
                width: bodyViewport.width
                height: bodyViewport.height
                PillButton {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    label: "+ Add Alarm"
                    filled: true
                    onPressed: root.editorRequested("alarm")
                }
                ClockKineticList {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 42
                    height: Math.min(5, Bar.ClockService.alarms.length) * 58
                    visible: Bar.ClockService.alarms.length > 0
                    wheelGain: 58
                    clip: true
                    model: Bar.ClockService.alarms
                    boundsBehavior: Flickable.DragAndOvershootBounds
                    rebound: Transition { SpringAnimation { properties: "x,y"; spring: 22; damping: 0.8; epsilon: 0.2 } }
                    ScrollBar.vertical: ScrollBar { policy: Bar.ClockService.alarms.length > 5 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                    delegate: Item {
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        height: 58
                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.topMargin: 7
                            text: Bar.ClockService.alarmTimeLabel(modelData)
                            color: modelData.enabled ? root.primaryText : root.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 19
                            font.weight: Font.Medium
                            font.letterSpacing: -0.2
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 7
                            text: (modelData.label || "Alarm") + " · " + (modelData.repeat || "Once")
                            color: root.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                        }
                        PillButton {
                            anchors.right: deleteAlarm.left
                            anchors.rightMargin: 5
                            anchors.verticalCenter: parent.verticalCenter
                            label: modelData.enabled ? "On" : "Off"
                            filled: modelData.enabled
                            onPressed: Bar.ClockService.toggleAlarm(index)
                        }
                        CircleButton {
                            id: deleteAlarm
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "×"
                            onPressed: Bar.ClockService.removeAlarm(index)
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineColor }
                    }
                }
            }

            Item {
                width: bodyViewport.width
                height: bodyViewport.height
                PillButton {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    label: "+ Add Timer"
                    filled: true
                    onPressed: root.editorRequested("timer")
                }
                ClockKineticList {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 42
                    height: Math.min(5, Bar.ClockService.timers.length) * 58
                    visible: Bar.ClockService.timers.length > 0
                    wheelGain: 58
                    clip: true
                    model: Bar.ClockService.timers
                    boundsBehavior: Flickable.DragAndOvershootBounds
                    rebound: Transition { SpringAnimation { properties: "x,y"; spring: 22; damping: 0.8; epsilon: 0.2 } }
                    ScrollBar.vertical: ScrollBar { policy: Bar.ClockService.timers.length > 5 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                    delegate: Item {
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        height: 58
                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.topMargin: 7
                            text: Bar.ClockService.durationLabel(modelData.remaining)
                            color: modelData.finished ? "#ff9f0a" : root.primaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 19
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 7
                            text: modelData.label || "Timer"
                            color: root.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                        }
                        PillButton {
                            anchors.right: resetTimer.left
                            anchors.rightMargin: 5
                            anchors.verticalCenter: parent.verticalCenter
                            label: modelData.running ? "Pause" : "Start"
                            filled: modelData.running
                            onPressed: Bar.ClockService.toggleTimer(index)
                        }
                        CircleButton {
                            id: resetTimer
                            anchors.right: deleteTimer.left
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "↺"
                            onPressed: Bar.ClockService.resetTimer(index)
                        }
                        CircleButton {
                            id: deleteTimer
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "×"
                            onPressed: Bar.ClockService.removeTimer(index)
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineColor }
                    }
                }
            }

            Item {
                width: bodyViewport.width
                height: bodyViewport.height
                PillButton {
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    label: "+ Add Focus"
                    filled: true
                    onPressed: root.editorRequested("pomodoro")
                }
                ClockKineticList {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 42
                    height: Math.min(5, Bar.ClockService.pomodoros.length) * 64
                    visible: Bar.ClockService.pomodoros.length > 0
                    wheelGain: 64
                    clip: true
                    model: Bar.ClockService.pomodoros
                    boundsBehavior: Flickable.DragAndOvershootBounds
                    rebound: Transition { SpringAnimation { properties: "x,y"; spring: 22; damping: 0.8; epsilon: 0.2 } }
                    ScrollBar.vertical: ScrollBar { policy: Bar.ClockService.pomodoros.length > 5 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff }
                    delegate: Item {
                        required property int index
                        required property var modelData
                        width: ListView.view.width
                        height: 64
                        Text {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.topMargin: 7
                            text: Bar.ClockService.durationLabel(modelData.remaining)
                            color: modelData.phase === "break" ? "#30d158" : root.primaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 18
                            font.weight: Font.Medium
                            font.features: { "tnum": 1 }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            text: (modelData.label || "Focus") + " · "
                                + (modelData.phase === "break" ? "Break" : "Focus") + " · "
                                + modelData.currentRound + "/" + modelData.rounds
                            color: root.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                        }
                        PillButton {
                            anchors.right: resetPomo.left
                            anchors.rightMargin: 5
                            anchors.verticalCenter: parent.verticalCenter
                            label: modelData.running ? "Pause" : "Start"
                            filled: modelData.running
                            onPressed: Bar.ClockService.togglePomodoro(index)
                        }
                        CircleButton {
                            id: resetPomo
                            anchors.right: deletePomo.left
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "↺"
                            onPressed: Bar.ClockService.resetPomodoro(index)
                        }
                        CircleButton {
                            id: deletePomo
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "×"
                            onPressed: Bar.ClockService.removePomodoro(index)
                        }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: root.lineColor }
                    }
                }
            }
        }
    }
}
