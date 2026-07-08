import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root
    signal back()
    // Raised when the user flips Optimized Battery Charging off — the parent
    // shows a confirmation dialog (Turn Off / Until Tomorrow / Cancel).
    signal requestDisableConfirm()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: column.implicitHeight

    // "main" = battery overview · "health" = Battery Health details sub-page.
    property string view: "main"

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

    // Condition explanation shown on the details page.
    readonly property string conditionDesc: BatteryService.healthCondition === "Normal"
        ? "The battery is functioning normally."
        : "The battery's ability to hold charge is less than when it was new, or "
          + "the battery isn't functioning normally. You can safely continue to "
          + "use it, and if the lowered charging capacity is affecting your "
          + "experience, you can get service."

    Column {
        id: column
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 10

        CCDetailHeader {
            width: parent.width
            title: root.view === "health" ? "Battery Health" : "Battery"
            onBack: {
                if (root.view === "health") root.view = "main"
                else root.back()
            }
        }

        // ══════════════════════════ MAIN VIEW ═══════════════════════════════
        // ── Combined: charging status + power mode ───────────────────────────
        Rectangle {
            visible: root.view === "main"
            width: parent.width
            radius: 12
            color: ThemeService.tileBg
            height: combinedCol.implicitHeight + 28

            Column {
                id: combinedCol
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                spacing: 14

                // Status row
                Item {
                    width: parent.width
                    height: 40

                    Rectangle {
                        id: batBg
                        anchors.left: parent.left
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
                        anchors.left: batBg.right
                        anchors.leftMargin: 12
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

                    // Live power, right-aligned with the percentage. While
                    // charging shows the charge rate (with a bolt); on battery
                    // it shows the laptop's current draw.
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        visible: BatteryService.power > 0

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: BatteryService.charging
                            text: "󱐋"
                            color: "#34C759"
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 13
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: BatteryService.power.toFixed(1) + " W"
                            color: BatteryService.charging
                                ? "#34C759"
                                : (dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55))
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
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
                                ? (dark ? Qt.rgba(10/255,132/255,255/255,0.24) : Qt.rgba(0,122/255,255/255,0.18))
                                : (segMa.containsMouse
                                    ? ThemeService.subtleTileBgHover
                                    : ThemeService.subtleTileBg)
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

        // ── Battery Health row → opens the details sub-page ──────────────────
        Rectangle {
            visible: root.view === "main"
            width: parent.width
            height: 52
            radius: 12
            color: ThemeService.tileBg

            Text {
                anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                text: "Battery Health"
                color: dark ? "#f5f6f8" : "#1c1c1e"
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.Medium
            }

            Row {
                anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: BatteryService.healthCondition
                    color: dark ? Qt.rgba(1,1,1,0.5) : Qt.rgba(0,0,0,0.5)
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                }
                // Only the ⓘ button opens the details — the row itself isn't clickable.
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26; height: 26; radius: 13
                    color: infoMa.containsMouse
                        ? ThemeService.subtleTileBgHover
                        : ThemeService.subtleTileBgHoverClear
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent
                        text: "󰋽"   // circled-info
                        color: "#0A84FF"
                        font.family: "JetBrainsMono Nerd Font Propo"
                        font.pixelSize: 16
                    }
                    MouseArea {
                        id: infoMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.view = "health"
                    }
                }
            }
        }

        // ── 24h battery-level graph ──────────────────────────────────────────
        Rectangle {
            visible: root.view === "main"
            width: parent.width
            radius: 12
            color: ThemeService.tileBg
            height: graphCol.implicitHeight + 28

            Column {
                id: graphCol
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                spacing: 12

                Text {
                    text: "Battery Level"
                    color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                BatteryUsageGraph { width: parent.width }
            }
        }

        // ════════════════════ BATTERY HEALTH DETAILS ════════════════════════
        // Condition + Maximum Capacity
        Rectangle {
            visible: root.view === "health"
            width: parent.width
            radius: 12
            color: ThemeService.tileBg
            height: condCol.implicitHeight + 28

            Column {
                id: condCol
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                spacing: 6

                Item {
                    width: parent.width
                    height: 20
                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "Battery Condition"
                        color: dark ? "#f5f6f8" : "#1c1c1e"
                        font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.Medium
                    }
                    Text {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: BatteryService.healthCondition
                        color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                        font.family: "SF Pro Display"; font.pixelSize: 14
                    }
                }
                Text {
                    width: parent.width
                    text: root.conditionDesc
                    color: dark ? Qt.rgba(1,1,1,0.45) : Qt.rgba(0,0,0,0.45)
                    font.family: "SF Pro Display"; font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    lineHeight: 1.15
                }

                Rectangle {
                    width: parent.width; height: 1
                    color: dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.07)
                    anchors.topMargin: 6
                }

                Item {
                    width: parent.width
                    height: 20
                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "Maximum Capacity"
                        color: dark ? "#f5f6f8" : "#1c1c1e"
                        font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.Medium
                    }
                    Text {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: BatteryService.maxCapacity > 0 ? BatteryService.maxCapacity + "%" : "—"
                        color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                        font.family: "SF Pro Display"; font.pixelSize: 14
                    }
                }
                Text {
                    width: parent.width
                    text: "This is a measure of battery capacity relative to when it was "
                        + "new. Lower capacity may result in fewer hours of usage between charges."
                    color: dark ? Qt.rgba(1,1,1,0.45) : Qt.rgba(0,0,0,0.45)
                    font.family: "SF Pro Display"; font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    lineHeight: 1.15
                }

                Text {
                    width: parent.width
                    text: "Cycle count: " + BatteryService.cycleCount
                    color: dark ? Qt.rgba(1,1,1,0.35) : Qt.rgba(0,0,0,0.35)
                    font.family: "SF Pro Display"; font.pixelSize: 10
                    topPadding: 2
                }
            }
        }

        // Optimized Battery Charging toggle
        Rectangle {
            visible: root.view === "health"
            width: parent.width
            radius: 12
            color: ThemeService.tileBg
            height: optCol.implicitHeight + 28

            Column {
                id: optCol
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 14 }
                spacing: 6

                Item {
                    width: parent.width
                    height: 26
                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "Optimized Battery Charging"
                        color: dark ? "#f5f6f8" : "#1c1c1e"
                        font.family: "SF Pro Display"; font.pixelSize: 14; font.weight: Font.Medium
                    }
                    CCSwitch {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        checked: BatteryService.optimizedEnabled
                        // Turning on applies the cap immediately; turning off asks
                        // for confirmation first (the switch stays on until then).
                        onToggled: {
                            if (BatteryService.optimizedEnabled) root.requestDisableConfirm()
                            else BatteryService.enableOptimized()
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: "When on, charging is capped to slow battery aging. "
                        + "Set the limit below; turn off to allow charging to 100%."
                    color: dark ? Qt.rgba(1,1,1,0.45) : Qt.rgba(0,0,0,0.45)
                    font.family: "SF Pro Display"; font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    lineHeight: 1.15
                }

                // ── Charge-limit slider — only while optimization is on ──────
                Column {
                    width: parent.width
                    spacing: 8
                    visible: BatteryService.optimizedEnabled
                    topPadding: 4

                    Text {
                        text: "Your battery will charge to " + BatteryService.chargeLimitPref + "%."
                        color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                        font.family: "SF Pro Display"; font.pixelSize: 11; font.weight: Font.DemiBold
                    }

                    Item {
                        id: limitSlider
                        width: parent.width
                        height: 40

                        readonly property var stops: [80, 85, 90, 95, 100]
                        readonly property int knobD: 18
                        readonly property real frac: (Math.max(80, Math.min(100, BatteryService.chargeLimitPref)) - 80) / 20
                        // Centre of the knob at the current value, and at a given stop.
                        function cx(f) { return strack.x + limitSlider.knobD / 2 + f * (strack.width - limitSlider.knobD) }

                        Rectangle {
                            id: strack
                            anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 5 }
                            height: 6; radius: 3
                            color: dark ? Qt.rgba(1,1,1,0.14) : Qt.rgba(0,0,0,0.12)
                        }
                        // Filled portion up to the knob.
                        Rectangle {
                            anchors.verticalCenter: strack.verticalCenter
                            x: strack.x; height: strack.height; radius: 3
                            width: Math.max(0, limitSlider.cx(limitSlider.frac) - strack.x)
                            color: "#0A84FF"
                        }
                        // Stop ticks.
                        Repeater {
                            model: limitSlider.stops
                            delegate: Rectangle {
                                required property var modelData
                                width: 2; height: 2; radius: 1
                                color: dark ? Qt.rgba(1,1,1,0.30) : Qt.rgba(0,0,0,0.25)
                                x: limitSlider.cx((modelData - 80) / 20) - 1
                                anchors.verticalCenter: strack.verticalCenter
                            }
                        }
                        // Knob.
                        Rectangle {
                            width: limitSlider.knobD; height: limitSlider.knobD; radius: limitSlider.knobD / 2
                            anchors.verticalCenter: strack.verticalCenter
                            x: limitSlider.cx(limitSlider.frac) - limitSlider.knobD / 2
                            color: "#ffffff"
                            border.color: Qt.rgba(0,0,0,0.18); border.width: 1
                            Behavior on x { NumberAnimation { duration: 80 } }
                        }
                        // Stop labels.
                        Repeater {
                            model: limitSlider.stops
                            delegate: Text {
                                required property var modelData
                                text: modelData + "%"
                                color: BatteryService.chargeLimitPref === modelData
                                    ? "#0A84FF" : (dark ? Qt.rgba(1,1,1,0.40) : Qt.rgba(0,0,0,0.40))
                                font.family: "SF Pro Display"; font.pixelSize: 9
                                font.weight: BatteryService.chargeLimitPref === modelData ? Font.DemiBold : Font.Normal
                                y: strack.y + 14
                                x: limitSlider.cx((modelData - 80) / 20) - implicitWidth / 2
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true
                            function pick(mx) {
                                let ratio = Math.max(0, Math.min(1, (mx - strack.x - limitSlider.knobD / 2) / (strack.width - limitSlider.knobD)))
                                BatteryService.setChargeTarget(80 + Math.round(ratio * 20 / 5) * 5)
                            }
                            onPressed: pick(mouseX)
                            onPositionChanged: if (pressed) pick(mouseX)
                        }
                    }
                }
            }
        }
    }
}
