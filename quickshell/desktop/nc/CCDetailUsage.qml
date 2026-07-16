import QtQuick
import Qt5Compat.GraphicalEffects

Item {
    id: root
    signal back()

    readonly property bool dark: ThemeService.isDark
    implicitHeight: column.implicitHeight

    property bool pickerOpen: false
    property string errorMsg: ""

    // Which metric card is expanded ("" = none). Accordion: one at a time, and
    // the service only polls detail data for the expanded key.
    property string expandedKey: ""
    onExpandedKeyChanged: SysUsageService.expandedDetail = expandedKey

    // Poll the heavy stats + rescan asset sets only while this panel is open.
    Component.onCompleted: {
        SysUsageService.detailActive = true
        SysUsageService.rescanSets()
        SysUsageService.refresh()
    }
    Component.onDestruction: {
        SysUsageService.detailActive = false
        SysUsageService.expandedDetail = ""
    }

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
        color: ThemeService.rowBg
        border.color: sel ? "#0A84FF"
                          : ThemeService.separator
        border.width: sel ? 2 : 1
        scale: setMa.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 13 } }

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
            color: ThemeService.textPrimary
                font.family: "SF Pro Display"
                font.pixelSize: 11
                font.weight: chip.sel ? Font.DemiBold : Font.Normal
            }
        }

        MouseArea {
            id: setMa
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
            scale: delMa.pressed ? 0.90 : 1
            Behavior on scale { AppleSpring { spring: 13 } }
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

    // ── Detail-view building blocks ───────────────────────────────────────────

    // "Label: value" line (Network detail etc.)
    component DRow: Item {
        property string label: ""
        property string val: ""
        width: parent ? parent.width : 0
        height: 17
        Text {
            id: dl
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            text: label
            color: ThemeService.textTertiary
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
        Text {
            anchors { left: dl.right; right: parent.right; verticalCenter: parent.verticalCenter; leftMargin: 10 }
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
            text: val
            color: ThemeService.textSecondary
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
    }

    // Name + proportional bar + value (per-core / RAM / disk / GPU-proc lists)
    component BarRow: Item {
        property string label: ""
        property string val: ""
        property real frac: 0            // 0..1, relative to the list max
        property color barColor: "#0A84FF"
        width: parent ? parent.width : 0
        height: 17
        Text {
            id: bl
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
            width: parent.width * 0.38
            elide: Text.ElideRight
            text: label
            color: ThemeService.textSecondary
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
        Text {
            id: bv
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            text: val
            color: ThemeService.textTertiary
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
        Rectangle {
            anchors {
                left: bl.right; right: bv.left; verticalCenter: parent.verticalCenter
                leftMargin: 8; rightMargin: 8
            }
            height: 5; radius: 2.5
            color: ThemeService.separator
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, frac))
                height: parent.height; radius: parent.radius
                color: barColor
                Behavior on width { AppleSpring { spring: 11; epsilon: 0.25 } }
            }
        }
    }

    // Muted hint line ("Sampling…", empty states)
    component Hint: Text {
        width: parent ? parent.width : 0
        color: ThemeService.textTertiary
        font.family: "SF Pro Display"
        font.pixelSize: 11
    }

    // ── A usage metric card (icon + name + model info + value + bar).
    //    Cards with a `key` expand on click into a live detail view; only the
    //    expanded key is polled by SysUsageService. ─────────────────────────────
    component Metric: Rectangle {
        id: card
        property string icon: ""
        property string name: ""
        property string info: ""
        property real pct: -1            // < 0 → no bar (Network)
        property string value: ""
        property color accent: "#0A84FF"
        property string key: ""          // "" → not expandable
        property alias detailData: detailCol.data
        readonly property bool expanded: key !== "" && root.expandedKey === key

        width: column.width
        height: head.height + (expanded ? detailWrap.implicitHeight : 0)
        radius: 12
        color: ThemeService.tileBg
        border.width: 0
        clip: true
        Behavior on height { AppleSpring { spring: 11; epsilon: 0.25 } }
        scale: metricMa.pressed ? 0.985 : 1
        Behavior on scale { AppleSpring { spring: 13 } }

        Item {
            id: head
            width: parent.width
            height: inner.implicitHeight + 22

            MouseArea {
                id: metricMa
                anchors.fill: parent
                enabled: card.key !== ""
                cursorShape: Qt.PointingHandCursor
                onClicked: root.expandedKey = card.expanded ? "" : card.key
            }

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

            Text {
                visible: card.key !== ""
                anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 10 }
                text: "󰅂"
                rotation: card.expanded ? 90 : 0
                Behavior on rotation { AppleSpring { spring: 13; epsilon: 0.25 } }
                color: ThemeService.textTertiary
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 14
            }

            Column {
                id: inner
                anchors {
                    left: ic.right; right: parent.right
                    verticalCenter: parent.verticalCenter
                    leftMargin: 12; rightMargin: card.key !== "" ? 28 : 14
                }
                spacing: 5

                Item {
                    width: parent.width
                    height: nameT.implicitHeight
                    Text {
                        id: nameT
                        anchors.left: parent.left
                        text: name
                        color: ThemeService.textPrimary
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.right: parent.right
                        text: value
                        color: ThemeService.textSecondary
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                    }
                }

                Text {
                    visible: info !== ""
                    width: parent.width
                    text: info
                    color: ThemeService.textTertiary
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: pct >= 0
                    width: parent.width; height: 6; radius: 3
                    color: ThemeService.separator
                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, pct / 100))
                        height: parent.height; radius: parent.radius
                        color: accent
                        Behavior on width { AppleSpring { spring: 11; epsilon: 0.25 } }
                    }
                }
            }
        }

        Item {
            id: detailWrap
            anchors { top: head.bottom; left: parent.left; right: parent.right }
            implicitHeight: detailCol.implicitHeight + 14
            Column {
                id: detailCol
                anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 14; rightMargin: 14 }
                spacing: 6
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
            color: ThemeService.tileBg
            border.width: 0

            Behavior on height { AppleSpring { spring: 11; epsilon: 0.25 } }
            Behavior on opacity { AppleSpring { spring: 13 } }

            Column {
                id: pickerCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                spacing: 10

                Text {
                    text: "RunCat style"
                    color: ThemeService.textSecondary
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
                            ? ThemeService.rowBgHover
                            : ThemeService.rowBg
                        border.width: 0
                        scale: addMa.pressed ? ThemeService.pressScale : 1
                        Behavior on scale { AppleSpring { spring: 13 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 3
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "+"
                                color: ThemeService.textSecondary
                                font.family: "SF Pro Display"
                                font.pixelSize: 24
                                font.weight: Font.Light
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Add"
                                color: ThemeService.textTertiary
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
            key: "cpu"
            icon: "󰻠"; name: "CPU"; accent: "#0A84FF"
            info: SysUsageService.cpuModel
            pct: SysUsageService.cpu
            value: Math.round(SysUsageService.cpu) + "%"
            detailData: [
                Hint {
                    visible: SysUsageService.coreUsages.length === 0
                    text: "Sampling cores…"
                },
                Grid {
                    id: coreGrid
                    width: parent ? parent.width : 0
                    columns: 2; columnSpacing: 16; rowSpacing: 4
                    Repeater {
                        model: SysUsageService.coreUsages
                        BarRow {
                            width: (coreGrid.width - coreGrid.columnSpacing) / 2
                            label: "Core " + index
                            val: Math.round(modelData) + "%"
                            frac: modelData / 100
                            barColor: "#0A84FF"
                        }
                    }
                }
            ]
        }
        Metric {
            visible: SysUsageService.igpuAvailable   // i915 only; hidden on xe
            key: "igpu"
            icon: "󰢮"; name: "iGPU"; accent: "#34C759"
            info: SysUsageService.igpuName
            pct: SysUsageService.igpu
            value: Math.round(SysUsageService.igpu) + "%"
            detailData: [
                DRow { label: "Render / 3D"; val: SysUsageService.igpuRender.toFixed(1) + "%" },
                DRow { label: "Video decode"; val: SysUsageService.igpuVideo.toFixed(1) + "%" },
                DRow { label: "Video enhance"; val: SysUsageService.igpuVideoEnhance.toFixed(1) + "%" },
                DRow { label: "Blitter"; val: SysUsageService.igpuBlitter.toFixed(1) + "%" },
                DRow {
                    label: "GPU clock"
                    val: Math.round(SysUsageService.igpuClock) + " MHz"
                        + (SysUsageService.igpuRequestedClock > 0
                            ? "  (req " + Math.round(SysUsageService.igpuRequestedClock) + ")" : "")
                },
                DRow { label: "Power draw"; val: SysUsageService.igpuPower.toFixed(1) + " W" },
                DRow { label: "RC6 idle"; val: SysUsageService.igpuRc6.toFixed(1) + "%" },
                Hint {
                    visible: SysUsageService.igpuProcs.length === 0
                    text: "No active GPU processes"
                },
                Repeater {
                    model: SysUsageService.igpuProcs
                    BarRow {
                        label: modelData.name + (modelData.pid > 0 ? "  " + modelData.pid : "")
                        val: modelData.busy.toFixed(1) + "% · "
                            + SysUsageService.fmtBytes(modelData.mem)
                        frac: modelData.busy / Math.max(1,
                            (SysUsageService.igpuProcs[0] || {}).busy || 0)
                        barColor: "#34C759"
                    }
                }
            ]
        }
        Metric {
            visible: SysUsageService.dgpuAvailable
            key: "dgpu"
            icon: "󰢮"; name: "dGPU"; accent: "#30D158"
            info: SysUsageService.dgpuName
            pct: SysUsageService.dgpu
            value: Math.round(SysUsageService.dgpu) + "%   "
                 + Math.round(SysUsageService.dgpuTemp) + "°C"
            detailData: [
                BarRow {
                    label: "VRAM"
                    val: Math.round(SysUsageService.dgpuMemUsed) + " / "
                       + Math.round(SysUsageService.dgpuMemTotal) + " MiB"
                    frac: SysUsageService.dgpuMemTotal > 0
                        ? SysUsageService.dgpuMemUsed / SysUsageService.dgpuMemTotal : 0
                    barColor: "#30D158"
                },
                DRow { label: "Power draw"; val: SysUsageService.dgpuPower.toFixed(1) + " W" },
                DRow { label: "GPU clock";  val: Math.round(SysUsageService.dgpuClock) + " MHz" },
                DRow { label: "Perf state"; val: SysUsageService.dgpuPState || "—" },
                Hint {
                    visible: SysUsageService.gpuProcs.length === 0
                    text: "No active GPU processes"
                },
                Repeater {
                    model: SysUsageService.gpuProcs
                    BarRow {
                        label: modelData.name
                        val: Math.round(modelData.mem) + " MiB"
                        frac: modelData.mem / Math.max(1, (SysUsageService.gpuProcs[0] || {}).mem || 0)
                        barColor: "#30D158"
                    }
                }
            ]
        }
        Metric {
            key: "mem"
            icon: "󰍛"; name: "Memory"; accent: "#FF9F0A"
            pct: SysUsageService.memPct
            value: SysUsageService.fmtBytes(SysUsageService.memUsed)
                 + " / " + SysUsageService.fmtBytes(SysUsageService.memTotal)
            detailData: [
                Hint {
                    visible: SysUsageService.memTop.length === 0
                    text: "Sampling processes…"
                },
                Repeater {
                    model: SysUsageService.memTop
                    BarRow {
                        label: modelData.name
                        val: SysUsageService.fmtBytes(modelData.bytes)
                        frac: modelData.bytes / Math.max(1, (SysUsageService.memTop[0] || {}).bytes || 0)
                        barColor: "#FF9F0A"
                    }
                }
            ]
        }
        Metric {
            key: "disk"
            icon: "󰋊"; name: "Disk"; accent: "#BF5AF2"
            info: SysUsageService.diskInfo
            pct: SysUsageService.diskPct
            value: SysUsageService.fmtBytes(SysUsageService.diskUsed)
                 + " / " + SysUsageService.fmtBytes(SysUsageService.diskTotal)
            detailData: [
                Item {
                    width: parent ? parent.width : 0
                    height: 16
                    Text {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        text: "Largest folders in ~"
                        color: ThemeService.textTertiary
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        text: SysUsageService.duScanning ? "Scanning…" : "󰑐"
                        color: ThemeService.textTertiary
                        font.family: SysUsageService.duScanning
                            ? "SF Pro Display" : "JetBrainsMono Nerd Font Propo"
                        font.pixelSize: SysUsageService.duScanning ? 11 : 12
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            enabled: !SysUsageService.duScanning
                            cursorShape: Qt.PointingHandCursor
                            onClicked: SysUsageService.refreshDiskTop(true)
                        }
                    }
                },
                Hint {
                    visible: SysUsageService.diskTop.length === 0 && !SysUsageService.duScanning
                    text: "No scan yet — press 󰑐 to scan"
                },
                Repeater {
                    model: SysUsageService.diskTop
                    BarRow {
                        label: "~/" + modelData.path.split("/").pop()
                        val: SysUsageService.fmtBytes(modelData.bytes)
                        frac: modelData.bytes / Math.max(1, (SysUsageService.diskTop[0] || {}).bytes || 0)
                        barColor: "#BF5AF2"
                    }
                }
            ]
        }
        Metric {
            key: "net"
            icon: "󰛳"; name: "Network"; accent: "#5AC8FA"
            info: SysUsageService.netInterface
            pct: -1
            value: "↓ " + SysUsageService.fmtRate(SysUsageService.netDown)
                 + "    ↑ " + SysUsageService.fmtRate(SysUsageService.netUp)
            detailData: [
                DRow { label: "Interface"; val: SysUsageService.netDetail.iface || "—" },
                DRow { label: "IPv4";      val: SysUsageService.netDetail.ip    || "—" },
                DRow { label: "Gateway";   val: SysUsageService.netDetail.gw    || "—" },
                DRow { label: "DNS";       val: SysUsageService.netDetail.dns   || "—" },
                DRow {
                    visible: !!SysUsageService.netDetail.ssid
                    label: "Wi-Fi"
                    val: (SysUsageService.netDetail.ssid || "")
                       + (SysUsageService.netDetail.signal ? "  (" + SysUsageService.netDetail.signal + "%)" : "")
                },
                DRow {
                    visible: !!SysUsageService.netDetail.rate
                    label: "Link rate"
                    val: SysUsageService.netDetail.rate || ""
                },
                DRow {
                    label: "Since boot"
                    val: "↓ " + SysUsageService.fmtBytes(SysUsageService.netDetail.rx || 0)
                       + "   ↑ " + SysUsageService.fmtBytes(SysUsageService.netDetail.tx || 0)
                }
            ]
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
            color: ThemeService.notificationBg
            border.width: 0

            Column {
                id: errCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                spacing: 10

                Text {
                    text: "Couldn't add style"
                    color: ThemeService.textPrimary
                    font.family: "SF Pro Display"
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: root.errorMsg
                    color: ThemeService.textSecondary
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                }
                Rectangle {
                    id: errorOkButton
                    anchors.right: parent.right
                    width: 64; height: 28; radius: 8
                    color: "#0A84FF"
                    scale: errorOkMa.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 13 } }
                    Text {
                        anchors.centerIn: parent
                        text: "OK"
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: errorOkMa
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.errorMsg = ""
                    }
                }
            }
        }
    }
}
