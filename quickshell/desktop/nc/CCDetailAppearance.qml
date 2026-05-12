import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root
    signal back()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: column.implicitHeight

    Process {
        id: setLight
        command: ["bash", "-c",
            "gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita';" +
            "gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'"]
    }
    Process {
        id: setDark
        command: ["bash", "-c",
            "gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark';" +
            "gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'"]
    }

    Column {
        id: column
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 8

        CCDetailHeader {
            width: parent.width
            title: "Appearance"
            onBack: root.back()
        }

        Text {
            text: "Theme"
            color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Row {
            width: parent.width
            spacing: 12

            // Light option
            Rectangle {
                width: (parent.width - 12) / 2
                height: 90
                radius: 12
                color: dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.03)
                border.color: !dark
                    ? "#0A84FF"
                    : (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08))
                border.width: !dark ? 2 : 1

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 36; height: 36; radius: 18
                        color: "#ffffff"
                        border.color: Qt.rgba(0,0,0,0.10); border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "󰖙"
                            color: "#1c1c1e"
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 18
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Light"
                        color: dark ? "#f5f6f8" : "#1c1c1e"
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: setLight.running = true
                }
            }

            // Dark option
            Rectangle {
                width: (parent.width - 12) / 2
                height: 90
                radius: 12
                color: dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.03)
                border.color: dark
                    ? "#0A84FF"
                    : (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08))
                border.width: dark ? 2 : 1

                Column {
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 36; height: 36; radius: 18
                        color: "#1c1c1e"
                        border.color: Qt.rgba(1,1,1,0.10); border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: "󰖔"
                            color: "#f5f6f8"
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 18
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Dark"
                        color: dark ? "#f5f6f8" : "#1c1c1e"
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: setDark.running = true
                }
            }
        }
    }
}
