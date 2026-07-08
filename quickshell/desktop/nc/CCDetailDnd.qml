import QtQuick

Item {
    id: root
    signal back()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: column.implicitHeight

    // Duration presets shown as a list. `mode` is persisted on NcServer so the
    // active row stays highlighted across reopens; `icon` uses the same Nerd
    // Font family as the rest of the control center.
    readonly property var options: [
        { mode: "1h",       icon: "󰔛", label: "For 1 Hour" },
        { mode: "evening",  icon: "󰖛", label: "Until This Evening" },
        { mode: "tomorrow", icon: "󰖜", label: "Until Tomorrow" },
        { mode: "always",   icon: "󰂛", label: "Always On" }
    ]

    // Resolve a preset to its epoch-ms deadline (0 = indefinite). Evening rolls
    // to tomorrow once 18:00 has already passed so the deadline is never stale.
    function targetFor(mode) {
        if (mode === "1h") return Date.now() + 3600000
        if (mode === "evening") {
            let d = new Date(); d.setHours(18, 0, 0, 0)
            if (d.getTime() <= Date.now()) d.setTime(d.getTime() + 86400000)
            return d.getTime()
        }
        if (mode === "tomorrow") {
            let d = new Date(); d.setDate(d.getDate() + 1); d.setHours(8, 0, 0, 0)
            return d.getTime()
        }
        return 0   // "always"
    }

    Column {
        id: column
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 8

        CCDetailHeader {
            width: parent.width
            title: "Do Not Disturb"
            toggleVisible: true
            toggleChecked: NcServer.dnd
            onBack: root.back()
            onToggled: NcServer.dnd ? NcServer.disableDnd()
                                    : NcServer.enableDnd(0, "always")
        }

        Text {
            text: "Turn On For"
            color: ThemeService.textSecondary
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }

        Repeater {
            model: root.options

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool isActive: NcServer.dnd && NcServer.dndMode === modelData.mode

                width: column.width
                height: 48
                radius: 12
                color: isActive
                    ? ThemeService.rowBgActive
                    : rowMa.containsMouse
                        ? ThemeService.rowBgHover
                        : ThemeService.rowBg
                Behavior on color { ColorAnimation { duration: 120 } }

                Row {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10
                    }
                    spacing: 12

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30; height: 30; radius: 15
                        color: row.isActive
                            ? "#0A84FF"
                            : ThemeService.subtleTileBg
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: row.modelData.icon
                            color: row.isActive ? "#ffffff" : (dark ? "#e0e8f0" : "#3a3a3c")
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 15
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.modelData.label
                        color: ThemeService.textPrimary
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: row.isActive ? Font.DemiBold : Font.Normal
                    }
                }

                // Checkmark on the active preset.
                Text {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 14
                    }
                    visible: row.isActive
                    text: "󰄬"
                    color: "#0A84FF"
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 16
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        NcServer.enableDnd(root.targetFor(row.modelData.mode), row.modelData.mode)
                        root.back()
                    }
                }
            }
        }
    }
}
