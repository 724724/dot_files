import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

Item {
    id: root

    // Seeded from parent on Loader.onLoaded
    property bool btOn: false

    signal back()
    signal pollRequest()  // ask parent to refresh its own btOn

    readonly property bool dark: ThemeService.isDark
    implicitHeight: column.implicitHeight

    // Devices: [{mac, name, paired, connected}]
    property var devices: []
    property bool scanning: false

    // MAC of the device currently being (dis)connected/paired — shows a spinner
    // in place of its status until the action settles and the list refreshes.
    property string busyMac: ""

    // ── PROCESSES ─────────────────────────────────────────────────────────────
    // Inline flip — the swaync helper required $SWAYNC_TOGGLE_STATE, which
    // we don't pass, so it always powered off.
    Process {
        id: toggleProc
        command: ["bash", "-c",
            "if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes';" +
            " then bluetoothctl power off >/dev/null 2>&1;" +
            " else bluetoothctl power on  >/dev/null 2>&1; fi"]
        onRunningChanged: {
            if (!running) {
                root.pollRequest()
                listProc.running = true
            }
        }
    }

    Process { id: settingsProc; command: ["blueman-manager"] }

    Process { id: actProc; command: ["true"]
        onRunningChanged: if (!running) listProc.running = true
    }

    // 30-sec discovery scan. bluetoothctl --timeout exits after the duration.
    Process {
        id: scanProc
        command: ["bash", "-c", "bluetoothctl --timeout 30 scan on >/dev/null 2>&1"]
        onRunningChanged: if (!running) root.scanning = false
    }

    // Keep paired devices visible. Unpaired discovery results are exposed only
    // during an explicit scan and noisy BlueZ RSSI pseudo-devices are ignored.
    Process {
        id: listProc
        command: ["bash", "-c",
            "all=$(timeout 0.5 bluetoothctl devices 2>/dev/null);" +
            "paired=$(timeout 0.5 bluetoothctl devices Paired 2>/dev/null" +
            " | awk '$1 == \"Device\" {print $2}');" +
            "echo \"$all\" | while read -r line; do " +
            "  [ -z \"$line\" ] && continue;" +
            "  case \"$line\" in Device\\ *) ;; *) continue ;; esac;" +
            "  mac=$(echo \"$line\" | awk '{print $2}');" +
            "  name=$(echo \"$line\" | cut -d' ' -f3-);" +
            "  p=no; c=no;" +
            "  if printf '%s\\n' \"$paired\" | grep -Fxq \"$mac\"; then p=yes; fi;" +
            "  dev_path=/org/bluez/hci0/dev_${mac//:/_};" +
            "  if [ \"$p\" = yes ] && busctl --system get-property org.bluez \"$dev_path\"" +
            "     org.bluez.Device1 Connected 2>/dev/null | grep -q '^b true$'; then c=yes; fi;" +
            "  echo \"$p|$c|$mac|$name\";" +
            "done"]
        stdout: StdioCollector {
            onStreamFinished: {
                let arr = []
                for (let line of text.trim().split("\n")) {
                    if (!line) continue
                    let p = line.split("|")
                    if (p.length < 4) continue
                    let mac = p[2].trim()
                    let name = p.slice(3).join("|").trim()
                    let paired = p[0] === "yes"
                    let connected = p[1] === "yes"
                    let invalidName = name === ""
                        || /\bRSSI\s*:/i.test(name)
                        || name.toUpperCase() === mac.toUpperCase()
                        || name.toUpperCase().startsWith(mac.toUpperCase() + " ")
                    if (invalidName || (!paired && !root.scanning)) continue
                    arr.push({
                        paired: paired,
                        connected: connected,
                        mac: mac,
                        name: name
                    })
                }
                arr.sort((a,b) =>
                    (b.connected - a.connected) ||
                    (b.paired - a.paired) ||
                    a.name.localeCompare(b.name))
                root.devices = arr
                // Clear the spinner only once the triggering action has finished
                // (actProc idle) — periodic/scan refreshes mustn't cut it short.
                if (!actProc.running) root.busyMac = ""
            }
        }
    }

    function startScan() {
        if (root.scanning) return
        root.scanning = true
        scanProc.running = true
        // Poll the device list more aggressively while scanning
        scanRefreshTimer.start()
    }

    function deviceClicked(d) {
        if (root.busyMac !== "") return   // ignore taps while one is in flight
        root.busyMac = d.mac
        let cmd
        if (d.connected) {
            cmd = "bluetoothctl disconnect " + d.mac
        } else if (d.paired) {
            cmd = "bluetoothctl connect " + d.mac
        } else {
            // Pair, trust, then connect — typical for a fresh device
            cmd = "bluetoothctl pair " + d.mac +
                "; bluetoothctl trust " + d.mac +
                "; bluetoothctl connect " + d.mac
        }
        actProc.command = ["bash", "-c", cmd]
        actProc.running = true
    }

    // Unpair/forget a device entirely ("Remove Device").
    function removeDevice(d) {
        if (root.busyMac !== "") return
        root.busyMac = d.mac
        actProc.command = ["bash", "-c",
            "bluetoothctl disconnect " + d.mac + " >/dev/null 2>&1;" +
            "bluetoothctl remove " + d.mac + " >/dev/null 2>&1"]
        actProc.running = true
    }

    // Right-click context menu for a device row.
    function _btMenuItems(d) {
        let items = []
        if (d.paired || d.connected) {
            items.push({
                label: d.connected ? "Disconnect" : "Connect",
                action: function() { root.deviceClicked(d) }
            })
        }
        items.push({
            label: "Bluetooth Settings…",
            action: function() { settingsProc.running = true }
        })
        items.push({
            label: "Remove Device",
            danger: true,
            action: function() { root.removeDevice(d) }
        })
        return items
    }

    Timer {
        id: scanRefreshTimer
        interval: 1500
        repeat: true
        running: root.scanning
        onTriggered: listProc.running = true
        onRunningChanged: if (!running) listProc.running = true
    }

    Component.onCompleted: listProc.running = true

    // Light periodic refresh while open. Paused mid-action so reassigning the
    // device list doesn't rebuild the row and reset its spinner.
    Timer {
        interval: 5000
        running: root.visible && !root.scanning && root.busyMac === ""
        repeat: true
        onTriggered: listProc.running = true
    }

    // ── LAYOUT ────────────────────────────────────────────────────────────────
    Column {
        id: column
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 8

        CCDetailHeader {
            width: parent.width
            title: "Bluetooth"
            toggleVisible: true
            toggleChecked: root.btOn
            actionIcon: "󰐕"
            actionBusy: root.scanning
            onBack: root.back()
            onToggled: toggleProc.running = true
            onActionClicked: root.startScan()
        }

        Text {
            text: root.scanning ? "Scanning…" : "Devices"
            color: ThemeService.textSecondary
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            visible: root.btOn
        }

        Flickable {
            id: btFlick
            width: parent.width
            height: Math.min(dCol.implicitHeight, 280)
            contentHeight: dCol.implicitHeight
            clip: true
            visible: root.btOn && root.devices.length > 0
            interactive: contentHeight > height
            boundsBehavior: Flickable.DragAndOvershootBounds
            boundsMovement: Flickable.FollowBoundsBehavior
            flickDeceleration: 6000
            maximumFlickVelocity: 6000
            rebound: Transition {
                SpringAnimation {
                    properties: "x,y"
                    spring: 13
                    damping: ThemeService.momentumDamping
                    epsilon: 0.25
                }
            }

            WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function(event) {
                    let dy = event.pixelDelta.y !== 0
                        ? event.pixelDelta.y * 8
                        : (event.angleDelta.y / 120) * 180
                    let max = Math.max(0, btFlick.contentHeight - btFlick.height)
                    btFlick.contentY = Math.max(0, Math.min(max, btFlick.contentY - dy))
                    event.accepted = true
                }
            }

            ScrollBar.vertical: ScrollBar {
                id: btBar
                policy: btFlick.contentHeight > btFlick.height
                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitWidth: 3
                    radius: 1.5
                    color: dark ? "#ffffff" : "#000000"
                    opacity: btBar.pressed ? 0.45 : (btBar.active ? 0.30 : 0.15)
                    Behavior on opacity { AppleSpring { spring: 13 } }
                }
            }

            Column {
                id: dCol
                width: parent.width
                spacing: 0

                Repeater {
                    model: root.btOn ? root.devices : []
                    delegate: Item {
                        id: deviceRow
                        required property var modelData
                        width: dCol.width
                        height: 42
                        scale: dRowMa.pressed ? 0.985 : 1
                        Behavior on scale { AppleSpring { spring: 13 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: 6
                            color: dRowMa.containsMouse
                                ? ThemeService.rowBgHover
                                : ThemeService.rowBgHoverClear
                        }

                        Rectangle {
                            id: dot
                            anchors {
                                left: parent.left
                                leftMargin: 12
                                verticalCenter: parent.verticalCenter
                            }
                            width: 8; height: 8; radius: 4
                            color: modelData.connected
                                ? "#34C759"
                                : (modelData.paired
                                    ? "#0A84FF"
                                    : ThemeService.textTertiary)
                        }

                        Text {
                            anchors {
                                left: dot.right
                                leftMargin: 10
                                right: stat.left
                                rightMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            text: modelData.name
                            color: ThemeService.textPrimary
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }

                        Text {
                            id: stat
                            anchors {
                                right: parent.right
                                rightMargin: (modelData.paired || modelData.connected) ? 36 : 12
                                verticalCenter: parent.verticalCenter
                            }
                            visible: root.busyMac !== modelData.mac
                            text: modelData.connected
                                ? "Connected"
                                : (modelData.paired ? "Paired" : "Tap to pair")
                            color: ThemeService.textSecondary
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                        }

                        // Spinner shown in place of the status while this device
                        // is (dis)connecting / pairing.
                        Item {
                            id: spinner
                            anchors {
                                right: parent.right
                                rightMargin: (modelData.paired || modelData.connected) ? 36 : 12
                                verticalCenter: parent.verticalCenter
                            }
                            width: 14; height: 14
                            visible: root.busyMac === modelData.mac

                            Canvas {
                                id: spinCv
                                anchors.fill: parent
                                onPaint: {
                                    let ctx = getContext("2d")
                                    ctx.reset()
                                    let c = width / 2
                                    ctx.lineWidth = 2
                                    ctx.lineCap = "round"
                                    ctx.strokeStyle = dark ? "rgba(255,255,255,0.75)"
                                                           : "rgba(0,0,0,0.55)"
                                    ctx.beginPath()
                                    ctx.arc(c, c, c - 1.5, 0, Math.PI * 1.4)
                                    ctx.stroke()
                                }
                            }

                            RotationAnimator {
                                target: spinner
                                running: spinner.visible
                                from: 0; to: 360
                                duration: 800
                                loops: Animation.Infinite
                            }
                        }

                        MouseArea {
                            id: dRowMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton) {
                                    // Menu only for paired/connected devices.
                                    if (!(modelData.paired || modelData.connected)) return
                                    let pt = dRowMa.mapToItem(root, mouse.x, mouse.y)
                                    ctxMenu.openAt(pt.x, pt.y, root._btMenuItems(modelData))
                                    return
                                }
                                root.deviceClicked(modelData)
                            }
                        }

                        // ⋮ kebab — paired/connected devices only (declared after
                        // dRowMa so it sits above the row's click area).
                        CCMenuDots {
                            id: btKebab
                            visible: modelData.paired || modelData.connected
                            width: visible ? 24 : 0
                            anchors {
                                right: parent.right
                                rightMargin: 6
                                verticalCenter: parent.verticalCenter
                            }
                            onClicked: {
                                let pt = btKebab.mapToItem(root, btKebab.width, btKebab.height)
                                ctxMenu.openAt(pt.x, pt.y, root._btMenuItems(modelData))
                            }
                        }
                    }
                }
            }
        }

        // Empty state
        Text {
            visible: root.btOn && root.devices.length === 0
            text: root.scanning ? "Searching for devices…" : "No devices. Tap + to scan."
            color: ThemeService.textTertiary
            font.family: "SF Pro Display"
            font.pixelSize: 11
            leftPadding: 8
            topPadding: 4
            bottomPadding: 4
        }

        Rectangle {
            id: bluetoothSettingsButton
            width: parent.width
            height: 36
            radius: 8
            scale: bSetMa.pressed ? 0.985 : 1
            Behavior on scale { AppleSpring { spring: 13 } }
            color: bSetMa.containsMouse
                ? ThemeService.rowBgHover
                : ThemeService.rowBgHoverClear

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                text: "Bluetooth Settings…"
                color: dark ? "#60b8ff" : "#007AFF"
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            MouseArea {
                id: bSetMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: settingsProc.running = true
            }
        }
    }

    // Right-click context menu overlay (fills the panel, renders above the list).
    CCContextMenu { id: ctxMenu }
}
