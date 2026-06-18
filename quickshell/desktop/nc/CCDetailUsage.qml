import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: root
    signal back()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: column.implicitHeight

    property bool pickerOpen: false
    property string errorMsg: ""

    // Poll the heavy stats + rescan asset sets only while this panel is open.
    Component.onCompleted: {
        SysUsageService.detailActive = true
        SysUsageService.rescanSets()
        SysUsageService.refresh()
    }
    Component.onDestruction: SysUsageService.detailActive = false

    // ── RunCat style chip (preview + name) ───────────────────────────────────
    component SetChip: Rectangle {
        id: chip
        property string setName: ""
        property var frames: []
        readonly property bool sel: setName === SysUsageService.runcatSet
        readonly property bool builtin: SysUsageService.isBuiltin(setName)
        readonly property bool colored: !!SysUsageService.runcatColoredMap[setName]
        readonly property string f0: (frames && frames.length > 0) ? frames[0] : ""
        readonly property string url: f0 === "" ? ""
            : SysUsageService.assetsUrl + "/" + setName + "/" + f0

        width: 72; height: 62
        radius: 10
        color: root.dark ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.04)
        border.color: sel ? "#0A84FF"
                          : (root.dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08))
        border.width: sel ? 2 : 1

        Column {
            anchors.centerIn: parent
            width: parent.width - 8
            spacing: 5
            Item {
                width: 34; height: 24
                anchors.horizontalCenter: parent.horizontalCenter
                Image {
                    id: pv
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    sourceSize.width: 68; sourceSize.height: 48
                    visible: chip.colored          // colourful → shown as-is
                    source: chip.url
                }
                ColorOverlay {
                    anchors.fill: pv; source: pv
                    color: root.dark ? "#e8eaed" : "#1c1c1e"
                    visible: !chip.colored         // silhouette → tinted
                }
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: chip.setName
                color: root.dark ? "#f5f6f8" : "#1c1c1e"
                font.family: "SF Pro Display"
                font.pixelSize: 11
                font.weight: chip.sel ? Font.DemiBold : Font.Normal
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: SysUsageService.setRuncatSet(chip.setName)
        }

        // Remove button (user-added sets only) — red dot at the top-left.
        Rectangle {
            visible: !chip.builtin
            anchors { left: parent.left; top: parent.top; leftMargin: 3; topMargin: 3 }
            width: 17; height: 17; radius: 9
            color: delMa.containsMouse ? "#ff4d4d" : "#ff5f57"
            border.color: Qt.rgba(0,0,0,0.18); border.width: 1
            z: 2
            Text {
                anchors.centerIn: parent
                text: "−"
                color: "#ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.Bold
            }
            MouseArea {
                id: delMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: SysUsageService.removeSet(chip.setName)
            }
        }
    }

    // ── A usage metric card (icon + name + model info + value + bar) ──────────
    component Metric: Rectangle {
        property string icon: ""
        property string name: ""
        property string info: ""
        property real pct: -1            // < 0 → no bar (Network)
        property string value: ""
        property color accent: "#0A84FF"

        width: column.width
        height: inner.implicitHeight + 22
        radius: 12
        color: root.dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.03)
        border.color: root.dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.06)
        border.width: 1

        Rectangle {
            id: ic
            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 }
            width: 34; height: 34; radius: 17
            color: accent
            Text {
                anchors.centerIn: parent
                text: icon
                color: "#ffffff"
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 16
            }
        }

        Column {
            id: inner
            anchors {
                left: ic.right; right: parent.right
                verticalCenter: parent.verticalCenter
                leftMargin: 12; rightMargin: 14
            }
            spacing: 5

            Item {
                width: parent.width
                height: nameT.implicitHeight
                Text {
                    id: nameT
                    anchors.left: parent.left
                    text: name
                    color: root.dark ? "#f5f6f8" : "#1c1c1e"
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.right: parent.right
                    text: value
                    color: root.dark ? Qt.rgba(1,1,1,0.6) : Qt.rgba(0,0,0,0.55)
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                }
            }

            Text {
                visible: info !== ""
                width: parent.width
                text: info
                color: root.dark ? Qt.rgba(1,1,1,0.42) : Qt.rgba(0,0,0,0.42)
                font.family: "SF Pro Display"
                font.pixelSize: 11
                elide: Text.ElideRight
            }

            Rectangle {
                visible: pct >= 0
                width: parent.width; height: 6; radius: 3
                color: root.dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08)
                Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, pct / 100))
                    height: parent.height; radius: parent.radius
                    color: accent
                    Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    Column {
        id: column
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 10

        CCDetailHeader {
            width: parent.width
            title: "Usage"
            actionIcon: "󰒓"   // gear → RunCat style picker
            onBack: root.back()
            onActionClicked: {
                root.pickerOpen = !root.pickerOpen
                if (root.pickerOpen) SysUsageService.rescanSets()
            }
        }

        // ── RunCat style picker (animated open/close) ─────────────────────────
        Rectangle {
            width: parent.width
            clip: true
            // Keep the item in the layout while collapsing so the height/opacity
            // animations have time to play; drop it only once fully closed.
            visible: height > 0
            height: root.pickerOpen ? pickerCol.implicitHeight + 24 : 0
            opacity: root.pickerOpen ? 1 : 0
            radius: 12
            color: root.dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.03)
            border.color: root.dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.06)
            border.width: 1

            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

            Column {
                id: pickerCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 10

                Text {
                    text: "RunCat style"
                    color: root.dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Grid {
                    id: styleGrid
                    width: parent.width
                    columns: 5
                    spacing: 8
                    readonly property real cellW: (width - spacing * (columns - 1)) / columns

                    Repeater {
                        model: SysUsageService.runcatSetNames
                        SetChip {
                            width: styleGrid.cellW
                            setName: modelData
                            frames: SysUsageService.runcatFramesMap[modelData]
                        }
                    }

                    // ＋ Add a style by picking a folder (validated by the service).
                    Rectangle {
                        id: addChip
                        width: styleGrid.cellW; height: 62; radius: 10
                        color: addMa.containsMouse
                            ? (root.dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.06))
                            : (root.dark ? Qt.rgba(1,1,1,0.04) : Qt.rgba(0,0,0,0.02))
                        border.color: root.dark ? Qt.rgba(1,1,1,0.14) : Qt.rgba(0,0,0,0.12)
                        border.width: 1
                        Behavior on color { ColorAnimation { duration: 100 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 3
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "+"
                                color: root.dark ? Qt.rgba(1,1,1,0.7) : Qt.rgba(0,0,0,0.55)
                                font.family: "SF Pro Display"
                                font.pixelSize: 24
                                font.weight: Font.Light
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Add"
                                color: root.dark ? Qt.rgba(1,1,1,0.5) : Qt.rgba(0,0,0,0.45)
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: addMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SysUsageService.addSet()
                        }
                    }
                }
            }
        }

        Metric {
            icon: "󰻠"; name: "CPU"; accent: "#0A84FF"
            info: SysUsageService.cpuModel
            pct: SysUsageService.cpu
            value: Math.round(SysUsageService.cpu) + "%"
        }
        Metric {
            visible: SysUsageService.igpuAvailable   // i915 only; hidden on xe
            icon: "󰢮"; name: "iGPU"; accent: "#34C759"
            info: SysUsageService.igpuName
            pct: SysUsageService.igpu
            value: Math.round(SysUsageService.igpu) + "%"
        }
        Metric {
            icon: "󰢮"; name: "GPU"; accent: "#30D158"
            info: SysUsageService.dgpuName
            pct: SysUsageService.dgpu
            value: Math.round(SysUsageService.dgpu) + "%   "
                 + Math.round(SysUsageService.dgpuTemp) + "°C"
        }
        Metric {
            icon: "󰍛"; name: "Memory"; accent: "#FF9F0A"
            pct: SysUsageService.memPct
            value: SysUsageService.fmtBytes(SysUsageService.memUsed)
                 + " / " + SysUsageService.fmtBytes(SysUsageService.memTotal)
        }
        Metric {
            icon: "󰋊"; name: "Disk"; accent: "#BF5AF2"
            info: SysUsageService.diskInfo
            pct: SysUsageService.diskPct
            value: SysUsageService.fmtBytes(SysUsageService.diskUsed)
                 + " / " + SysUsageService.fmtBytes(SysUsageService.diskTotal)
        }
        Metric {
            icon: "󰛳"; name: "Network"; accent: "#5AC8FA"
            info: SysUsageService.netInterface
            pct: -1
            value: "↓ " + SysUsageService.fmtRate(SysUsageService.netDown)
                 + "    ↑ " + SysUsageService.fmtRate(SysUsageService.netUp)
        }
    }

    // Add-folder outcome: select the new style on success, show an error otherwise.
    Connections {
        target: SysUsageService
        function onAddResult(ok, message) {
            if (ok) { root.pickerOpen = true; root.errorMsg = "" }
            else root.errorMsg = message
        }
    }

    // ── Error dialog ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        z: 100
        visible: root.errorMsg !== ""
        color: Qt.rgba(0, 0, 0, 0.30)

        MouseArea { anchors.fill: parent }   // swallow clicks behind the dialog

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 36, 300)
            height: errCol.implicitHeight + 28
            radius: 14
            color: root.dark ? "#2c2c30" : "#ffffff"
            border.color: root.dark ? Qt.rgba(1,1,1,0.12) : Qt.rgba(0,0,0,0.12)
            border.width: 1

            Column {
                id: errCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                Text {
                    text: "Couldn't add style"
                    color: root.dark ? "#f5f6f8" : "#1c1c1e"
                    font.family: "SF Pro Display"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.errorMsg
                    color: root.dark ? Qt.rgba(1,1,1,0.6) : Qt.rgba(0,0,0,0.6)
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                }
                Rectangle {
                    anchors.right: parent.right
                    width: 64; height: 28; radius: 8
                    color: "#0A84FF"
                    Text {
                        anchors.centerIn: parent
                        text: "OK"
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.errorMsg = ""
                    }
                }
            }
        }
    }
}
