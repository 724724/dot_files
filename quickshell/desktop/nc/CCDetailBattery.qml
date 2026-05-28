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

        // Extra breathing room between the Battery Level graph and the
        // usage-by-app section below.
        Item { width: parent.width; height: 6 }

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

            readonly property int rowH: 52
            readonly property int maxVisibleRows: 6
            readonly property int appCount: ScreenTimeService.ranked.length

            // Cap the card at 6 rows; past that the list scrolls internally so
            // the control-center window height stays fixed.
            height: (appCount === 0
                ? emptyLabel.implicitHeight
                : Math.min(appCount, maxVisibleRows) * rowH) + 12

            // Bars are relative to the heaviest user (ranked[0]).
            readonly property int maxSecs: appCount > 0
                ? ScreenTimeService.ranked[0].seconds : 1

            // Snug width for the time column, measured from the widest label
            // (the top app's — it has the longest duration). A snug, right-
            // aligned column keeps the bar↔time gap small while letting the
            // time sit flush to a right margin that matches the left, so the
            // whole row is centered rather than hugging the left edge.
            TextMetrics {
                id: timeMetrics
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                text: appsCard.appCount > 0
                    ? ScreenTimeService.fmt(ScreenTimeService.ranked[0].seconds)
                    : "00m"
            }
            readonly property int timeColW: Math.ceil(timeMetrics.advanceWidth) + 2

            Text {
                id: emptyLabel
                visible: appsCard.appCount === 0
                anchors {
                    top: parent.top; left: parent.left; right: parent.right
                    leftMargin: 12; rightMargin: 12; topMargin: 6
                }
                horizontalAlignment: Text.AlignHCenter
                topPadding: 10; bottomPadding: 10
                text: "No usage tracked yet — collecting…"
                color: dark ? Qt.rgba(1,1,1,0.45) : Qt.rgba(0,0,0,0.45)
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }

            ListView {
                id: appsList
                visible: appsCard.appCount > 0
                anchors {
                    top: parent.top; left: parent.left; right: parent.right
                    leftMargin: 12; rightMargin: 12; topMargin: 6
                }
                // Viewport caps at 6 rows; the rest scrolls.
                height: Math.min(count, appsCard.maxVisibleRows) * appsCard.rowH
                clip: true
                model: ScreenTimeService.ranked
                spacing: 0
                // Only grab scroll/flick gestures when there's overflow.
                interactive: count > appsCard.maxVisibleRows
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick

                delegate: Item {
                        required property var modelData
                        required property int index
                        width: appsList.width
                        height: appsCard.rowH

                        // Icon on the left, vertically centered over both lines.
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

                        // Time, right-aligned and flush to the right margin (which
                        // matches the icon's left margin → the row reads centered).
                        // Its column is sized snugly to the widest label so the
                        // bar reaches close to it, and every row's bar matches.
                        Text {
                            id: timeLabel
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: appsCard.timeColW
                            horizontalAlignment: Text.AlignRight
                            text: ScreenTimeService.fmt(modelData.seconds)
                            color: dark ? "#f5f6f8" : "#1c1c1e"
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }

                        // Middle column: name on top, usage bar below. The bar runs
                        // from just right of the icon to just before the time, so
                        // it's long and identical on every row.
                        Column {
                            anchors {
                                left: appIcon.right; leftMargin: 12
                                right: timeLabel.left; rightMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            spacing: 6

                            // Name and bar are 3px narrower than the column and
                            // centered (1.5px each side) so they shrink evenly and
                            // stay aligned with each other.
                            Text {
                                width: parent.width - 3
                                x: (parent.width - width) / 2
                                text: ScreenTimeService.displayName(modelData.cls)
                                elide: Text.ElideRight
                                color: dark ? "#f5f6f8" : "#1c1c1e"
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                            Rectangle {
                                width: parent.width - 3
                                x: (parent.width - width) / 2
                                height: 5; radius: 2.5
                                color: dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08)
                                Rectangle {
                                    height: parent.height; radius: parent.radius
                                    width: parent.width * modelData.seconds / Math.max(1, appsCard.maxSecs)
                                    color: dark ? "#0A84FF" : "#007AFF"
                                    Behavior on width { NumberAnimation { duration: 200 } }
                                }
                            }
                        }

                        // Hairline divider between rows (skipped after the last).
                        Rectangle {
                            visible: index < appsList.count - 1
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 1
                            color: dark ? Qt.rgba(1,1,1,0.07) : Qt.rgba(0,0,0,0.06)
                        }
                    }
            }
        }
    }
}
