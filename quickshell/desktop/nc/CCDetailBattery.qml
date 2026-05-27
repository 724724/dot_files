import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root
    signal back()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: column.implicitHeight

    Component.onCompleted: BatteryService.refresh()

    // Power-mode metadata (label / description / icon per profile).
    readonly property var modes: [
        { id: "performance", label: "Performance", desc: "Highest performance — more heat & fan", icon: "󰓅" },
        { id: "balanced",    label: "Balanced",    desc: "Default — adaptive balance",           icon: "󰾅" },
        { id: "power-saver", label: "Power Saver",  desc: "Longer battery life",                  icon: "󰌪" }
    ]
    function modeDesc() {
        for (var i = 0; i < modes.length; i++)
            if (modes[i].id === BatteryService.mode) return modes[i].desc
        return ""
    }

    Column {
        id: column
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 10

        CCDetailHeader {
            width: parent.width
            title: "Battery"
            onBack: root.back()
        }

        // ── Combined: charging status + power mode ───────────────────────────
        Rectangle {
            width: parent.width
            radius: 12
            color: dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.04)
            height: combinedCol.implicitHeight + 28

            Column {
                id: combinedCol
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                spacing: 14

                // Status row
                Row {
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        id: batBg
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40; height: 40; radius: 20
                        color: BatteryService.charging
                            ? "#34C759"
                            : (BatteryService.level <= 20 ? "#FF453A" : "#0A84FF")
                        Text {
                            anchors.centerIn: parent
                            text: BatteryService.charging ? "󰂄" : "󰁹"
                            color: "#ffffff"
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 18
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            text: BatteryService.level + "%"
                            color: dark ? "#f5f6f8" : "#1c1c1e"
                            font.family: "SF Pro Display"
                            font.pixelSize: 20
                            font.weight: Font.Bold
                        }
                        Text {
                            text: BatteryService.status !== ""
                                ? BatteryService.status
                                : (BatteryService.charging ? "Charging" : "Not charging")
                            color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                        }
                    }
                }

                // Divider
                Rectangle {
                    width: parent.width; height: 1
                    color: dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.07)
                }

                Text {
                    text: "Power Mode"
                    color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                // Segmented power-mode control
                Row {
                    id: seg
                    width: parent.width
                    height: 42
                    spacing: 6

                    Repeater {
                        model: root.modes
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool sel: BatteryService.mode === modelData.id
                            width: (seg.width - 12) / 3      // two 6px gaps
                            height: seg.height
                            radius: 9
                            color: sel
                                ? (dark ? Qt.rgba(10/255,132/255,255/255,0.20) : Qt.rgba(0,122/255,255/255,0.12))
                                : (segMa.containsMouse
                                    ? (dark ? Qt.rgba(1,1,1,0.07) : Qt.rgba(0,0,0,0.05))
                                    : (dark ? Qt.rgba(1,1,1,0.04) : Qt.rgba(0,0,0,0.03)))
                            border.color: sel ? "#0A84FF" : "transparent"
                            border.width: sel ? 1.5 : 0
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 5
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.icon
                                    color: parent.parent.sel ? "#0A84FF" : (dark ? "#f0f3f6" : "#1c1c1e")
                                    font.family: "JetBrainsMono Nerd Font Propo"
                                    font.pixelSize: 15
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: parent.parent.sel ? "#0A84FF" : (dark ? "#f0f3f6" : "#1c1c1e")
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 11
                                    font.weight: parent.parent.sel ? Font.DemiBold : Font.Medium
                                }
                            }

                            MouseArea {
                                id: segMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: BatteryService.setMode(modelData.id)
                            }
                        }
                    }
                }

                // Description of the selected mode
                Text {
                    width: parent.width
                    text: root.modeDesc()
                    color: dark ? Qt.rgba(1,1,1,0.45) : Qt.rgba(0,0,0,0.45)
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ── 24h battery-level graph ──────────────────────────────────────────
        Rectangle {
            width: parent.width
            radius: 12
            color: dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.04)
            height: graphCol.implicitHeight + 28

            Column {
                id: graphCol
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                spacing: 12

                Text {
                    text: "Battery Level · Today"
                    color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                BatteryUsageGraph { width: parent.width }
            }
        }

        // ── Usage by app (screen time) ───────────────────────────────────────
        Item {
            width: parent.width
            height: 16
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "Battery Usage by App"
                color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                font.family: "SF Pro Display"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: ScreenTimeService.totalSeconds > 0
                    ? "Screen time " + ScreenTimeService.fmt(ScreenTimeService.totalSeconds)
                    : ""
                color: dark ? Qt.rgba(1,1,1,0.40) : Qt.rgba(0,0,0,0.40)
                font.family: "SF Pro Display"
                font.pixelSize: 10
            }
        }

        Rectangle {
            id: appsCard
            width: parent.width
            radius: 12
            color: dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.04)
            height: appsCol.implicitHeight + 20

            // Top 6 apps; bars are relative to the heaviest user.
            readonly property var topApps: ScreenTimeService.ranked.slice(0, 6)
            readonly property int maxSecs: ScreenTimeService.ranked.length > 0
                ? ScreenTimeService.ranked[0].seconds : 1

            Column {
                id: appsCol
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 10 }
                spacing: 4

                Text {
                    visible: ScreenTimeService.ranked.length === 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 10; bottomPadding: 10
                    text: "No usage tracked yet — collecting…"
                    color: dark ? Qt.rgba(1,1,1,0.45) : Qt.rgba(0,0,0,0.45)
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                }

                Repeater {
                    model: appsCard.topApps
                    delegate: Item {
                        required property var modelData
                        width: appsCol.width
                        height: 46

                        Image {
                            id: appIcon
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: 28; height: 28
                            sourceSize.width: 56; sourceSize.height: 56
                            fillMode: Image.PreserveAspectFit
                            smooth: true; mipmap: true; asynchronous: true
                            source: "image://icon/" + ScreenTimeService.iconNameFor(modelData.cls)
                            onStatusChanged: if (status === Image.Error)
                                source = "image://icon/application-x-executable"
                        }

                        Text {
                            id: timeLabel
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            text: ScreenTimeService.fmt(modelData.seconds)
                            color: dark ? "#f5f6f8" : "#1c1c1e"
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        Column {
                            anchors {
                                left: appIcon.right; leftMargin: 10
                                right: timeLabel.left; rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 6

                            Text {
                                width: parent.width
                                text: ScreenTimeService.displayName(modelData.cls)
                                elide: Text.ElideRight
                                color: dark ? "#f5f6f8" : "#1c1c1e"
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            Rectangle {
                                width: parent.width; height: 4; radius: 2
                                color: dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08)
                                Rectangle {
                                    height: parent.height; radius: parent.radius
                                    width: parent.width * modelData.seconds / Math.max(1, appsCard.maxSecs)
                                    color: "#34C759"
                                    Behavior on width { NumberAnimation { duration: 200 } }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
