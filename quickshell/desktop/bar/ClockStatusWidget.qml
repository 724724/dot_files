import QtQuick
import QtQuick.Layouts

// Running timers at a glance, sitting just right of the media pill.
//
// Shows the stopwatch, any running countdown timers, and any running Pomodoro
// focus session — each as an icon + live time. Alarms are deliberately excluded:
// they aren't "running", they just wait for a wall-clock time.
//
// Clicking any entry opens the clock popup on that tool's page.
PillContainer {
    id: root

    clickable: hasEntries
    pressed: statusTap.pressed
    implicitHeight: 33
    property var screen: null

    // Page indices in ClockToolsView: 1 = Stopwatch, 3 = Timer, 4 = Pomodoro.
    readonly property var entries: {
        let out = []
        if (ClockService.stopwatchRunning)
            out.push({ glyph: "󰔛",
                       text: ClockService.durationLabel(ClockService.stopwatchSeconds),
                       page: 1, accent: false })
        let timers = ClockService.timers
        for (let i = 0; i < timers.length; i++) {
            if (!timers[i] || !timers[i].running) continue
            out.push({ glyph: "󰔟",
                       text: ClockService.durationLabel(timers[i].remaining),
                       page: 3, accent: false })
        }
        let pomos = ClockService.pomodoros
        for (let j = 0; j < pomos.length; j++) {
            let p = pomos[j]
            if (!p || !p.running) continue
            out.push({ glyph: "󰈸",
                       text: ClockService.durationLabel(p.remaining),
                       page: 4, accent: p.phase === "break" })
        }
        return out
    }

    readonly property bool hasEntries: entries.length > 0
    readonly property real targetWidth: hasEntries ? row.implicitWidth + 20 : 0
    visible: opacity > 0.002
    opacity: hasEntries ? 1 : 0
    clip: true
    implicitWidth: targetWidth
    Behavior on opacity { AppleSpring { spring: 18 } }
    Behavior on implicitWidth { AppleSpring { spring: 18; epsilon: 0.1 } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 10

        Repeater {
            model: root.entries

            delegate: RowLayout {
                required property var modelData
                spacing: 5

                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: modelData.glyph
                    // Break phases go green, matching the Pomodoro list rows.
                    color: modelData.accent ? "#30d158" : ThemeService.fg
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 12
                }
                Text {
                    Layout.alignment: Qt.AlignVCenter
                    text: modelData.text
                    color: modelData.accent ? "#30d158" : ThemeService.fg
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    font.letterSpacing: 0.08
                    font.features: { "tnum": 1 }
                }
            }
        }
    }

    TapHandler {
        id: statusTap
        enabled: root.hasEntries
        onTapped: {
            if (root.entries.length > 0)
                ClockService.requestedPage = root.entries[0].page
            ClockService.popupAnchorX = 0
            ClockService.targetScreen = root.screen
            ClockService.popupSource = "clock"
            ClockService.popupVisible = true
        }
    }
}
