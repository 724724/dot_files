import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root
    signal back()
    signal closeRequested()

    readonly property bool dark: ThemeService.isDark
    // Only count the currently-visible branch — column and confirmOverlay
    // share the same anchor space so summing them leaves a tall empty area
    // below the confirm dialog.
    implicitHeight: confirmOverlay.visible
        ? confirmOverlay.height
        : column.implicitHeight

    // Pending action while the confirmation overlay is up.
    property string pendingAction: ""
    property string pendingLabel: ""
    property var runningApps: []

    // Countdown state — 60 s default, auto-confirms on expiry.
    readonly property int countdownTotal: 60
    property int countdownLeft: 0

    // ── ACTION DEFINITIONS ───────────────────────────────────────────────────
    readonly property var actions: [
        { id: "lock",      label: "Lock",      icon: "󰌾", color: "#0A84FF", needsConfirm: false },
        { id: "logout",    label: "Logout",    icon: "󰍃", color: "#5E5CE6", needsConfirm: true },
        { id: "hibernate", label: "Hibernate", icon: "󰒲", color: "#BF5AF2", needsConfirm: true },
        { id: "reboot",    label: "Reboot",    icon: "󰜉", color: "#FF9F0A", needsConfirm: true },
        { id: "shutdown",  label: "Shutdown",  icon: "󰐥", color: "#FF453A", needsConfirm: true }
    ]

    // ── PROCESSES ────────────────────────────────────────────────────────────
    // setsid -f forks a fresh session and detaches the script before this
    // qs-owned Process object can be torn down by the control-center close.
    // Earlier we tried `systemd-run --user --no-block`, but routing the
    // systemctl calls through a transient user unit caused shutdown/reboot/
    // hibernate to silently no-op (only logout / lock worked). Forking with
    // setsid keeps the script's session intact and lets it complete its
    // graceful-close + systemctl call without parent supervision.
    Process {
        id: actProc
        command: ["true"]
    }
    function _runDetached(cmd) {
        actProc.command = ["sh", "-c",
            "setsid -f bash /home/sejunlee/.config/quickshell/scripts/power.sh "
            + cmd + " </dev/null >/dev/null 2>&1"]
        actProc.running = true
    }

    // Lookup running GUI apps, excluding shell internals. Triggered when an
    // action that needs confirmation is selected.
    Process {
        id: appsProc
        command: ["bash", "-c",
            "hyprctl clients -j 2>/dev/null | jq -r '.[].class' " +
            "| grep -vE '^(foot|dunst|Hyprland|quickshell|qs)$' " +
            "| grep -v '^$' | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: {
                let apps = text.trim().split("\n").filter(s => s.length > 0)
                if (apps.length === 0) {
                    // Nothing running → execute immediately
                    root.executePending()
                } else {
                    root.runningApps = apps
                    root.countdownLeft = root.countdownTotal
                    confirmTick.start()
                }
            }
        }
    }

    Timer {
        id: confirmTick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdownLeft -= 1
            if (root.countdownLeft <= 0) {
                stop()
                root.executePending()
            }
        }
    }

    // ── PUBLIC HANDLERS ──────────────────────────────────────────────────────
    function requestAction(actionId, label, needsConfirm) {
        if (!needsConfirm) {
            // Immediate (e.g., Lock)
            root._runDetached(actionId)
            root.closeRequested()
            return
        }
        root.pendingAction = actionId
        root.pendingLabel = label
        root.runningApps = []
        appsProc.running = true
    }

    function executePending() {
        if (root.pendingAction === "") return
        let action = root.pendingAction
        root._runDetached(action)
        root.pendingAction = ""
        root.pendingLabel = ""
        root.runningApps = []
        confirmTick.stop()
        root.closeRequested()
    }

    function cancelPending() {
        confirmTick.stop()
        root.pendingAction = ""
        root.pendingLabel = ""
        root.runningApps = []
        root.countdownLeft = 0
    }

    // ── LAYOUT ───────────────────────────────────────────────────────────────
    Column {
        id: column
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 10
        visible: root.pendingAction === ""

        CCDetailHeader {
            width: parent.width
            title: "Power"
            onBack: root.back()
        }

        Column {
            width: parent.width
            spacing: 6

            Repeater {
                model: root.actions
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 44
                    radius: 10
                    color: rowMa.containsMouse
                        ? (dark ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.04))
                        : (dark ? Qt.rgba(1,1,1,0.04) : Qt.rgba(0,0,0,0.03))
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Rectangle {
                        id: pwrIcon
                        anchors {
                            left: parent.left
                            leftMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        width: 28; height: 28; radius: 14
                        color: modelData.color
                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            color: "#ffffff"
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 14
                        }
                    }

                    Text {
                        anchors {
                            left: pwrIcon.right
                            leftMargin: 12
                            verticalCenter: parent.verticalCenter
                        }
                        text: modelData.label
                        color: dark ? "#f5f6f8" : "#1c1c1e"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.requestAction(
                            modelData.id, modelData.label, modelData.needsConfirm)
                    }
                }
            }
        }
    }

    // ── CONFIRM OVERLAY ──────────────────────────────────────────────────────
    Item {
        id: confirmOverlay
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: confirmCol.implicitHeight + 16
        visible: root.pendingAction !== ""

        Column {
            id: confirmCol
            anchors { top: parent.top; left: parent.left; right: parent.right }
            spacing: 10

            // Header (back to power list)
            CCDetailHeader {
                width: parent.width
                title: root.pendingLabel + "?"
                onBack: root.cancelPending()
            }

            // Warning panel
            Rectangle {
                width: parent.width
                radius: 12
                color: dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.03)
                border.color: dark ? Qt.rgba(1,1,1,0.08) : Qt.rgba(0,0,0,0.06)
                border.width: 1
                height: warnCol.implicitHeight + 24

                Column {
                    id: warnCol
                    anchors {
                        top: parent.top
                        left: parent.left
                        right: parent.right
                        margins: 12
                    }
                    spacing: 8

                    Row {
                        spacing: 8
                        Rectangle {
                            width: 28; height: 28; radius: 14
                            color: "#FF9F0A"
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                anchors.centerIn: parent
                                text: "󰀦"
                                color: "#ffffff"
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 16
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.runningApps.length + " app"
                                + (root.runningApps.length !== 1 ? "s" : "")
                                + " still running"
                            color: dark ? "#f5f6f8" : "#1c1c1e"
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.runningApps.join(", ")
                        color: dark ? Qt.rgba(1,1,1,0.6) : Qt.rgba(0,0,0,0.55)
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Countdown bar
            Item {
                width: parent.width
                height: 28

                Text {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                    }
                    text: "Auto-" + root.pendingAction + " in " + root.countdownLeft + "s"
                    color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                }

                // Track
                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: 4
                    radius: 2
                    color: dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08)

                    Rectangle {
                        anchors {
                            left: parent.left
                            top: parent.top
                            bottom: parent.bottom
                        }
                        width: parent.width *
                            (root.countdownLeft / Math.max(1, root.countdownTotal))
                        radius: parent.radius
                        color: "#FF9F0A"
                        Behavior on width { NumberAnimation { duration: 950; easing.type: Easing.Linear } }
                    }
                }
            }

            // Buttons
            Row {
                width: parent.width
                spacing: 10

                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 38
                    radius: 10
                    color: cancelMa.containsMouse
                        ? (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08))
                        : (dark ? Qt.rgba(1,1,1,0.07) : Qt.rgba(0,0,0,0.05))
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        color: dark ? "#f5f6f8" : "#1c1c1e"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: cancelMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancelPending()
                    }
                }

                Rectangle {
                    width: (parent.width - 10) / 2
                    height: 38
                    radius: 10
                    color: confirmMa.containsMouse ? "#ff5e58" : "#FF453A"
                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: root.pendingLabel + " Now"
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: confirmMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.executePending()
                    }
                }
            }
        }
    }
}
