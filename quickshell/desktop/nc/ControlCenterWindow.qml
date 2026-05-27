import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

PanelWindow {
    id: win

    // Full-screen overlay so clicks outside the card can be caught to dismiss
    // it. The card itself is positioned top-right inside escScope below.
    anchors { top: true; bottom: true; left: true; right: true }

    // Tall by default — extend toward the bottom of the screen so the
    // notification list has room. Detail panels shrink to fit their own
    // content so empty space doesn't appear under e.g. the Appearance picker.
    readonly property real screenH:
        screen ? screen.height
        : (Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 1080)

    // Bottom buffer so the dock doesn't fight with the panel surface.
    readonly property int bottomGap: 60

    readonly property int cardHeight: {
        if (win.detail !== "") {
            let d = win.detail, h = 600
            if (d === "wifi"       && detailWifi.item)       h = detailWifi.item.implicitHeight + 28
            else if (d === "bluetooth"  && detailBt.item)    h = detailBt.item.implicitHeight + 28
            else if (d === "appearance" && detailAppearance.item) h = detailAppearance.item.implicitHeight + 28
            else if (d === "battery"    && detailBattery.item)    h = detailBattery.item.implicitHeight + 28
            else if (d === "power"      && detailPower.item)      h = detailPower.item.implicitHeight + 28
            return Math.max(180, Math.min(h, screenH - 50 - bottomGap))
        }
        // Main view: extend down toward the bottom of the screen so the
        // fixed CC header has plenty of room and notifications get a real
        // scroll area underneath.
        return Math.max(420, screenH - 50 - bottomGap)
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    visible: NcServer.controlCenterVisible

    WlrLayershell.namespace: "qs-cc"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand so the inline Wi-Fi password TextField can receive keyboard
    // focus when clicked, while not stealing focus from regular apps when
    // nothing in the panel is focused.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property bool dark: ThemeService.isDark

    property string detail: ""
    onVisibleChanged: {
        if (!visible) detail = ""
        // Grab keyboard focus so Esc is delivered (layer keyboardFocus is
        // OnDemand and only acquires the keyboard when an item is focused).
        else escScope.forceActiveFocus()
    }

    // Connectivity pollers
    property bool wifiOn: false
    property string wifiSsid: ""
    property bool btOn: false

    // Toggle from row-icon click (left-half of the connectivity row). These
    // intentionally bypass the swaync helpers because those expected an env
    // var ($SWAYNC_TOGGLE_STATE) that we don't set.
    Process {
        id: wifiToggle
        command: ["bash", "-c",
            "if [ \"$(nmcli radio wifi)\" = enabled ]; then nmcli radio wifi off;" +
            " else nmcli radio wifi on; fi"]
        onRunningChanged: if (!running) wifiPoll.running = true
    }
    Process {
        id: btToggle
        command: ["bash", "-c",
            "if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes';" +
            " then bluetoothctl power off >/dev/null 2>&1;" +
            " else bluetoothctl power on  >/dev/null 2>&1; fi"]
        onRunningChanged: if (!running) btPoll.running = true
    }
    Process {
        id: themeToggle
        command: ["bash", "/home/sejunlee/.config/quickshell/scripts/toggle-theme.sh"]
    }

    Process {
        id: wifiPoll
        command: ["bash", "-c",
            "if [ \"$(nmcli radio wifi)\" = enabled ]; then" +
            "  ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | awk -F: '$1==\"yes\"{print $2; exit}');" +
            "  echo \"on|$ssid\";" +
            "else echo \"off|\"; fi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = text.trim().split("|")
                win.wifiOn = parts[0] === "on"
                win.wifiSsid = parts[1] || ""
            }
        }
    }

    Process {
        id: btPoll
        command: ["bash", "-c",
            "if bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'; then echo on; else echo off; fi"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: win.btOn = text.trim() === "on"
        }
    }

    Timer {
        interval: 4000
        running: win.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: { wifiPoll.running = true; btPoll.running = true }
    }

    // Esc-to-dismiss. The FocusScope spans the whole overlay and holds keyboard
    // focus while open (forced in onVisibleChanged); the inline Wi-Fi field can
    // still take focus on click, and an unhandled Esc bubbles back up to here.
    FocusScope {
        id: escScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: NcServer.controlCenterVisible = false

        // Click anywhere outside the card dismisses the panel.
        MouseArea {
            anchors.fill: parent
            onClicked: NcServer.controlCenterVisible = false
        }

        Rectangle {
        id: card
        width: 440
        height: win.cardHeight
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 50
        anchors.rightMargin: 10
        radius: 18
        color: dark ? Qt.rgba(28/255, 28/255, 32/255, 0.92)
                    : Qt.rgba(245/255, 245/255, 247/255, 0.92)
        border.color: dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08)
        border.width: 1
        Behavior on color { ColorAnimation { duration: 200 } }

        // ── DETAIL ────────────────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            anchors.margins: 14
            visible: win.detail !== ""
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 140 } }

            Loader {
                id: detailWifi
                anchors.fill: parent
                active: win.detail === "wifi"
                visible: active
                // Live-bound so toggling Wi-Fi externally updates the detail
                // header, and there is no off-flash on entry.
                sourceComponent: CCDetailWifi {
                    wifiOn: win.wifiOn
                    activeSsid: win.wifiSsid
                    onBack: win.detail = ""
                    onPollRequest: wifiPoll.running = true
                }
            }
            Loader {
                id: detailBt
                anchors.fill: parent
                active: win.detail === "bluetooth"
                visible: active
                sourceComponent: CCDetailBluetooth {
                    btOn: win.btOn
                    onBack: win.detail = ""
                    onPollRequest: btPoll.running = true
                }
            }
            Loader {
                id: detailAppearance
                anchors.fill: parent
                active: win.detail === "appearance"
                visible: active
                sourceComponent: CCDetailAppearance { onBack: win.detail = "" }
            }
            Loader {
                id: detailBattery
                anchors.fill: parent
                active: win.detail === "battery"
                visible: active
                sourceComponent: CCDetailBattery { onBack: win.detail = "" }
            }
            Loader {
                id: detailPower
                anchors.fill: parent
                active: win.detail === "power"
                visible: active
                sourceComponent: CCDetailPower {
                    onBack: win.detail = ""
                    onCloseRequested: NcServer.controlCenterVisible = false
                }
            }
        }

        // ── MAIN ──────────────────────────────────────────────────────────────
        // The CC widgets stay pinned at the top and only the notification
        // stacks below them scroll. Splitting into a separate fixed Column
        // and a notification-only Flickable means dragging through 30 alerts
        // never hides the toggles/sliders/media controls.
        Item {
            id: mainArea
            anchors.fill: parent
            anchors.margins: 14
            visible: win.detail === ""

            readonly property real columnW: (width - 10) / 2

            // ── FIXED CC HEADER ─────────────────────────────────────────────
            ColumnLayout {
                id: ccHeader
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                }
                spacing: 10

                // ── ROW 1: connectivity + DND/battery/power ──────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    CCPanel {
                        Layout.preferredWidth: mainArea.columnW
                        Layout.preferredHeight: 178
                        contentPadding: 10

                        Column {
                            anchors.fill: parent
                            spacing: 4

                            CCConnectivityRow {
                                width: parent.width
                                icon: "󰖩"
                                label: "Wi-Fi"
                                sublabel: win.wifiOn ? (win.wifiSsid || "On") : "Off"
                                active: win.wifiOn
                                onIconClicked: { wifiToggle.running = true; wifiPoll.running = true }
                                onBodyClicked: win.detail = "wifi"
                            }
                            CCConnectivityRow {
                                width: parent.width
                                icon: "󰂯"
                                label: "Bluetooth"
                                sublabel: win.btOn ? "On" : "Off"
                                active: win.btOn
                                onIconClicked: { btToggle.running = true; btPoll.running = true }
                                onBodyClicked: win.detail = "bluetooth"
                            }
                            CCConnectivityRow {
                                width: parent.width
                                icon: ThemeService.isDark ? "󰖔" : "󰖙"
                                label: "Appearance"
                                sublabel: ThemeService.isDark ? "Dark" : "Light"
                                active: ThemeService.isDark
                                onIconClicked: themeToggle.running = true
                                onBodyClicked: win.detail = "appearance"
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.preferredWidth: mainArea.columnW
                        Layout.preferredHeight: 178
                        spacing: 8

                        CCBigToggle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 90
                            icon: "󰂛"
                            label: "Do Not Disturb"
                            sublabel: NcServer.dnd ? "On" : "Off"
                            active: NcServer.dnd
                            onClicked: NcServer.dnd = !NcServer.dnd
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 80
                            spacing: 8

                            CCMiniTile {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.preferredHeight: 80
                                icon: BatteryService.charging ? "󰂄" : "󰁹"
                                iconBg: BatteryService.charging ? "#34C759"
                                      : (BatteryService.level <= 20 ? "#FF453A" : "#0A84FF")
                                label: "Battery"
                                sublabel: BatteryService.level + "%  ·  "
                                    + (BatteryService.mode === "performance" ? "Perf"
                                        : BatteryService.mode === "power-saver" ? "Saver" : "Bal")
                                onClicked: win.detail = "battery"
                            }

                            CCMiniTile {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.preferredHeight: 80
                                icon: "󰐥"
                                iconBg: "#FF453A"
                                label: "Power"
                                sublabel: "Lock · Logout · ⏻"
                                onClicked: win.detail = "power"
                            }
                        }
                    }
                }

                // ── DISPLAY ───────────────────────────────────────────────────
                CCPanel {
                    Layout.fillWidth: true
                    Layout.preferredHeight: brightnessSlider.implicitHeight + 28
                    CCSlider {
                        id: brightnessSlider
                        anchors.fill: parent
                        label: "Display"
                        icon: "󰃞"
                        value: BrightnessService.pct
                        onMoved: v => BrightnessService.setPct(v)
                    }
                }

                // ── SOUND ─────────────────────────────────────────────────────
                CCPanel {
                    Layout.fillWidth: true
                    Layout.preferredHeight: soundSlider.implicitHeight + 28
                    CCSlider {
                        id: soundSlider
                        anchors.fill: parent
                        label: "Sound"
                        icon: AudioService.muted ? "󰝟"
                            : (AudioService.vol < 33 ? "󰕿"
                                                     : (AudioService.vol < 66 ? "󰖀" : "󰕾"))
                        value: AudioService.vol
                        onMoved: v => AudioService.setVolume(v)
                    }
                }

                // ── NOW PLAYING ───────────────────────────────────────────────
                CCPanel {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    contentPadding: 10
                    CCMediaPanel { anchors.fill: parent }
                }

                // ── NOTIFICATIONS HEADER ──────────────────────────────────────
                Item { Layout.preferredHeight: 4; Layout.fillWidth: true }

                RowLayout {
                    Layout.fillWidth: true
                    visible: NcServer.count > 0

                    Text {
                        text: "Notifications"
                        color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.55)
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "Clear All"
                        color: dark ? "#60b8ff" : "#007AFF"
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NcServer.dismissAll()
                        }
                    }
                }
            }

            // ── SCROLLABLE NOTIFICATIONS ─────────────────────────────────────
            Flickable {
                id: scroll
                anchors {
                    top: ccHeader.bottom
                    topMargin: 8
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                }
                contentHeight: stackColumn.implicitHeight
                    + (NcServer.count === 0 ? emptyState.height : 0)
                clip: true
                // interactive=true is required for Flickable to even *see*
                // wheel events (its wheelEvent handler short-circuits when
                // interactive is false). Drag-to-scroll is therefore on, but
                // wheel + touchpad work consistently.
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 6000
                maximumFlickVelocity: 6000

                // Mouse wheel: ~150px per notch. Touchpad: pixelDelta * 6 so
                // a quick two-finger swipe covers a real list, not 30 pixels.
                WheelHandler {
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: function(event) {
                        let dy = event.pixelDelta.y !== 0
                            ? event.pixelDelta.y * 8
                            : (event.angleDelta.y / 120) * 180
                        let max = Math.max(0, scroll.contentHeight - scroll.height)
                        scroll.contentY = Math.max(0, Math.min(max, scroll.contentY - dy))
                        event.accepted = true
                    }
                }

                // Animate mouse-wheel hops; touchpad events go through
                // Flickable directly so this Behavior shouldn't fight them.
                Behavior on contentY {
                    enabled: !scroll.dragging && !scroll.flicking
                    NumberAnimation { duration: 90; easing.type: Easing.OutCubic }
                }

                ScrollBar.vertical: ScrollBar {
                    id: vBar
                    policy: scroll.contentHeight > scroll.height
                        ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    contentItem: Rectangle {
                        implicitWidth: 4
                        radius: 2
                        color: dark ? "#ffffff" : "#000000"
                        opacity: vBar.pressed ? 0.45 : (vBar.active ? 0.30 : 0.15)
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                }

                // Empty state — centered at top of scroll area when no notifications.
                Item {
                    id: emptyState
                    width: scroll.width
                    height: 32
                    visible: NcServer.count === 0

                    Text {
                        anchors.centerIn: parent
                        text: "No Notifications"
                        color: dark ? Qt.rgba(1,1,1,0.35) : Qt.rgba(0,0,0,0.35)
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                    }
                }

                // ── NOTIFICATION STACKS (group-by-app, expand/collapse) ──────
                Column {
                    id: stackColumn
                    width: scroll.width
                    spacing: 12
                    visible: NcServer.count > 0

                    // Track expansion per appName so dismissing a card (which
                    // recomputes groupedByApp() and rebuilds delegates) doesn't
                    // reset the stack back to collapsed.
                    property var expandedGroups: ({})
                    function setExpanded(appName, value) {
                        let copy = Object.assign({}, expandedGroups)
                        copy[appName] = value
                        expandedGroups = copy
                    }

                    Repeater {
                        model: NcServer.groupedByApp()
                        delegate: Item {
                            id: stackDelegate
                            required property var modelData
                            width: stackColumn.width

                            readonly property var notifs: modelData.notifs
                            readonly property int extra: Math.min(2, notifs.length - 1)
                            readonly property string appKey: modelData.appName || "?"
                            readonly property bool expanded:
                                stackColumn.expandedGroups[appKey] === true

                            // Top card lives at y=4 so the count badge at top
                            // (rendered at y=0) doesn't get clipped by Flickable.
                            readonly property int topPad: 4

                            // Height: collapsed shows top + peek edges; expanded
                            // stacks all cards vertically.
                            height: expanded
                                ? (topPad + topCard.implicitHeight
                                    + (notifs.length > 1 ? expandedCol.implicitHeight + 8 : 0))
                                : (topPad + topCard.implicitHeight + extra * 6)
                            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                            // Peek card 2
                            Rectangle {
                                visible: !stackDelegate.expanded && stackDelegate.extra >= 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 24
                                height: 18
                                y: stackDelegate.topPad + topCard.implicitHeight - 4
                                radius: 14
                                color: dark ? Qt.rgba(48/255, 48/255, 52/255, 0.92)
                                            : Qt.rgba(248/255, 248/255, 250/255, 0.94)
                                border.color: dark ? Qt.rgba(1,1,1,0.05) : Qt.rgba(0,0,0,0.05)
                                border.width: 1
                                z: 0
                            }

                            // Peek card 1
                            Rectangle {
                                visible: !stackDelegate.expanded && stackDelegate.extra >= 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 12
                                height: 18
                                y: stackDelegate.topPad + topCard.implicitHeight - 10
                                radius: 14
                                color: dark ? Qt.rgba(52/255, 52/255, 58/255, 0.94)
                                            : Qt.rgba(252/255, 252/255, 254/255, 0.96)
                                border.color: dark ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.06)
                                border.width: 1
                                z: 1
                            }

                            // Top (most recent) card
                            NotificationCard {
                                id: topCard
                                notification: stackDelegate.notifs[0]
                                inControlCenter: true
                                width: parent.width
                                y: stackDelegate.topPad
                                z: 2
                                // Collapsed group → × clears the whole app.
                                // Expanded, or a lone notification → × removes
                                // just this card (null falls back to dismiss()).
                                closeAction:
                                    (!stackDelegate.expanded && stackDelegate.notifs.length > 1)
                                        ? (function() { NcServer.dismissGroup(stackDelegate.appKey) })
                                        : null
                            }

                            // Expanded list — rest of the group below the top
                            Column {
                                id: expandedCol
                                anchors {
                                    top: topCard.bottom
                                    topMargin: 8
                                    left: parent.left
                                    right: parent.right
                                }
                                spacing: 8
                                visible: stackDelegate.expanded
                                opacity: stackDelegate.expanded ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: 160 } }

                                Repeater {
                                    model: stackDelegate.expanded
                                        ? stackDelegate.notifs.slice(1)
                                        : []
                                    delegate: NotificationCard {
                                        required property var modelData
                                        notification: modelData
                                        inControlCenter: true
                                        width: expandedCol.width
                                    }
                                }
                            }

                            // Stack badge — circular, top-left corner. Shows
                            // count when collapsed, chevron-up when expanded.
                            Rectangle {
                                id: stackBadge
                                visible: stackDelegate.notifs.length > 1
                                anchors {
                                    left: parent.left
                                    top: parent.top
                                    leftMargin: 4
                                    topMargin: 0
                                }
                                width: 22; height: 22; radius: 11
                                color: stackDelegate.expanded ? "#0A84FF" : "#FF453A"
                                z: 100
                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: stackDelegate.expanded
                                        ? "󰅃"
                                        : stackDelegate.notifs.length
                                    color: "#ffffff"
                                    font.family: stackDelegate.expanded
                                        ? "JetBrainsMono Nerd Font Propo"
                                        : "SF Pro Display"
                                    font.pixelSize: stackDelegate.expanded ? 12 : 11
                                    font.weight: Font.Bold
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -3
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: stackColumn.setExpanded(
                                        stackDelegate.appKey,
                                        !stackDelegate.expanded)
                                }
                            }

                            // Click anywhere on the collapsed stack to expand.
                            // TapHandler is cooperative so child MouseAreas
                            // (× button, action pills) still take their clicks
                            // first and this only fires for empty-card taps.
                            TapHandler {
                                enabled: !stackDelegate.expanded
                                    && stackDelegate.notifs.length > 1
                                onTapped: stackColumn.setExpanded(stackDelegate.appKey, true)
                            }
                        }
                    }
                }
            }
        }
        }
    }
}
