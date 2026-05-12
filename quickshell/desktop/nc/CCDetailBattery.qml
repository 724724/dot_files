import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root
    signal back()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: column.implicitHeight

    Component.onCompleted: BatteryService.refresh()

    Column {
        id: column
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 10

        CCDetailHeader {
            width: parent.width
            title: "Battery"
            onBack: root.back()
        }

        // Battery status card
        Rectangle {
            width: parent.width
            height: 84
            radius: 12
            color: dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.04)

            Rectangle {
                id: batBg
                anchors {
                    left: parent.left
                    leftMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                width: 36; height: 36; radius: 18
                color: BatteryService.charging
                    ? "#34C759"
                    : (BatteryService.level <= 20 ? "#FF453A" : "#0A84FF")

                Text {
                    anchors.centerIn: parent
                    text: BatteryService.charging ? "󰂄" : "󰁹"
                    color: "#ffffff"
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 16
                }
            }

            Column {
                anchors {
                    left: batBg.right
                    leftMargin: 12
                    verticalCenter: parent.verticalCenter
                }
                spacing: 1
                Text {
                    text: BatteryService.level + "%"
                    color: dark ? "#f5f6f8" : "#1c1c1e"
                    font.family: "SF Pro Display"
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                Text {
                    text: BatteryService.status
                    color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                }
            }
        }

        Text {
            text: "Power Mode"
            color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Column {
            width: parent.width
            spacing: 6

            Repeater {
                model: [
                    { id: "performance", label: "Performance",  desc: "Highest perf, more heat & fan",  icon: "󰓅" },
                    { id: "balanced",    label: "Balanced",     desc: "Default — adaptive",            icon: "󰾅" },
                    { id: "power-saver", label: "Power Saver",  desc: "Longer battery life",            icon: "󰌪" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 56
                    radius: 10
                    readonly property bool selected: BatteryService.mode === modelData.id

                    color: selected
                        ? (dark ? Qt.rgba(10/255, 132/255, 255/255, 0.18) : Qt.rgba(0, 122/255, 255/255, 0.10))
                        : (rowMa.containsMouse
                            ? (dark ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.04))
                            : (dark ? Qt.rgba(1,1,1,0.04) : Qt.rgba(0,0,0,0.03)))
                    border.color: selected ? "#0A84FF" : "transparent"
                    border.width: selected ? 1.5 : 0
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Rectangle {
                        id: pIcon
                        anchors {
                            left: parent.left
                            leftMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        width: 32; height: 32; radius: 16
                        color: parent.selected
                            ? "#0A84FF"
                            : (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08))
                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            color: parent.parent.selected ? "#ffffff" : (dark ? "#f0f3f6" : "#1c1c1e")
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 16
                        }
                    }

                    Column {
                        anchors {
                            left: pIcon.right
                            leftMargin: 12
                            right: check.left
                            rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: 1

                        Text {
                            text: modelData.label
                            color: dark ? "#f5f6f8" : "#1c1c1e"
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            text: modelData.desc
                            color: dark ? Qt.rgba(1,1,1,0.5) : Qt.rgba(0,0,0,0.50)
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }

                    Text {
                        id: check
                        anchors {
                            right: parent.right
                            rightMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        text: parent.selected ? "󰄬" : ""
                        color: "#0A84FF"
                        font.family: "JetBrainsMono Nerd Font Propo"
                        font.pixelSize: 16
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: BatteryService.setMode(modelData.id)
                    }
                }
            }
        }
    }
}
