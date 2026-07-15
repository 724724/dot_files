import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "kinetic.js" as Kinetic

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

    // Set from shell.qml = BarState.contentTop (gap centralized there). The
    // panel rises with the bar when hidden; height grows to keep the bottom edge
    // fixed. Animated so the toggle slides rather than jumps.
    property int barContentTop: 53
    property real topInset: barContentTop
    Behavior on topInset { AppleSpring { spring: 13; epsilon: 0.25 } }

    component StackPeek: Item {
        id: peek
        property color fill: "transparent"
        property real cornerRadius: 12
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            y: -peek.cornerRadius
            height: peek.height + peek.cornerRadius
            radius: peek.cornerRadius
            color: peek.fill
            antialiasing: true
        }
    }

    readonly property int cardHeight: {
        if (win.detail !== "") {
            let d = win.detail, h = ccHeader.implicitHeight + 28
            if (d === "wifi"       && detailWifi.item)       h = detailWifi.item.implicitHeight + 28
            else if (d === "bluetooth"  && detailBt.item)    h = detailBt.item.implicitHeight + 28
            else if (d === "usage"      && detailUsage.item)      h = detailUsage.item.implicitHeight + 28
            else if (d === "battery"    && detailBattery.item)    h = detailBattery.item.implicitHeight + 28
            else if (d === "power"      && detailPower.item)      h = detailPower.item.implicitHeight + 28
            else if (d === "dnd"        && detailDnd.item)         h = detailDnd.item.implicitHeight + 28
            else if (d === "screentime" && detailScreenTime.item)  h = detailScreenTime.item.implicitHeight + 28
            return Math.max(180, Math.min(h, screenH - topInset - bottomGap))
        }
        // Main view: fit the Control Center widgets exactly. Notifications now
        // live in their own transparent module below this card.
        return Math.min(ccHeader.implicitHeight + 28, screenH - topInset - bottomGap)
    }

    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    readonly property bool shown: NcServer.controlCenterVisible
    property bool _surfaceVisible: false
    visible: _surfaceVisible
    mask: shown ? null : closedRegion
    Region { id: closedRegion }

    WlrLayershell.namespace: "qs-cc"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand so the inline Wi-Fi password TextField can receive keyboard
    // focus when clicked, while not stealing focus from regular apps when
    // nothing in the panel is focused.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property bool dark: ThemeService.isDark

    property string detail: ""

    // "Turn off Optimized Battery Charging?" confirmation modal. Reset whenever
    // the detail page changes so it never lingers behind another panel.
    property bool batteryConfirm: false
    onDetailChanged: batteryConfirm = false

    // Display dropdown (Dark Mode / Night Shift) — the round button at the right
    // end of the brightness slider expands the Display tile downward to reveal it.
    property bool displayMenuOpen: false

    // Sound dropdown (output-device picker) — same expand-downward behaviour on
    // the Sound tile's round button.
    property bool soundMenuOpen: false
    property bool inlineResizeActive: false

    function finishInlineResize() {
        Qt.callLater(() => {
            if (!displayHeightMotion.running && !soundHeightMotion.running)
                win.inlineResizeActive = false
        })
    }

    // Kick the screen-time tracker at shell startup. The singleton is lazy, so
    // without this it wouldn't begin counting until the Battery detail is first
    // opened — touching a property here forces it to instantiate now.
    Component.onCompleted: {
        void ScreenTimeService.day
        if (shown) _surfaceVisible = true
    }

    Connections {
        target: NcServer
        function onControlCenterVisibleChanged() {
            if (NcServer.controlCenterVisible) {
                win._surfaceVisible = true
                Qt.callLater(() => escScope.forceActiveFocus())
            } else {
            detail = ""
            displayMenuOpen = false
            soundMenuOpen = false
            stackColumn.expandedGroups = ({})
            }
        }
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
        running: win.shown
        repeat: true
        triggeredOnStart: true
        onTriggered: { wifiPoll.running = true; btPoll.running = true }
    }

    // Esc-to-dismiss. The FocusScope spans the whole overlay and holds keyboard
    // focus while open; the inline Wi-Fi field can
    // still take focus on click, and an unhandled Esc bubbles back up to here.
    FocusScope {
        id: escScope
        anchors.fill: parent
        focus: true
        opacity: win.shown ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 13 } }
        onOpacityChanged: if (!win.shown && opacity <= 0.002) win._surfaceVisible = false
        Keys.onEscapePressed: NcServer.controlCenterVisible = false

        // Click anywhere outside the card dismisses the panel.
        MouseArea {
            anchors.fill: parent
            enabled: win.shown
            onPressed: NcServer.controlCenterVisible = false
        }

        Rectangle {
        id: card
        width: 440
        height: win.cardHeight
        Behavior on height {
            enabled: !win.inlineResizeActive
            AppleSpring { spring: 18; epsilon: 0.25 }
        }
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: win.topInset
        anchors.rightMargin: 10
        radius: 18
        color: ThemeService.bg
        border.color: ThemeService.stroke
        border.width: 1
        clip: true
        scale: win.shown ? 1 : 0.97
        transformOrigin: Item.TopRight
        Behavior on scale { AppleSpring { spring: 13 } }

        // Absorb clicks that land on the card but not on an interactive widget,
        // so they don't fall through to the dismiss-on-outside MouseArea behind
        // the card. Declared first → lowest in the card's stacking order, so the
        // toggles, sliders, buttons and notification list still receive their
        // clicks; only "empty" clicks reach here and get swallowed. The panel
        // then closes only on Esc or a click truly outside the card.
        MouseArea {
            anchors.fill: parent
        }

        // ── DETAIL ────────────────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            anchors.margins: 14
            visible: opacity > 0.002
            opacity: win.detail !== "" ? 1 : 0
            Behavior on opacity { AppleSpring { spring: 18 } }

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
                id: detailUsage
                anchors.fill: parent
                active: win.detail === "usage"
                visible: active
                sourceComponent: CCDetailUsage { onBack: win.detail = "" }
            }
            Loader {
                id: detailBattery
                anchors.fill: parent
                active: win.detail === "battery"
                visible: active
                sourceComponent: CCDetailBattery {
                    onBack: win.detail = ""
                    onRequestDisableConfirm: win.batteryConfirm = true
                }
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
            Loader {
                id: detailDnd
                anchors.fill: parent
                active: win.detail === "dnd"
                visible: active
                sourceComponent: CCDetailDnd { onBack: win.detail = "" }
            }
            Loader {
                id: detailScreenTime
                anchors.fill: parent
                active: win.detail === "screentime"
                visible: active
                sourceComponent: CCDetailScreenTime { onBack: win.detail = "" }
            }
        }

        // ── MAIN ──────────────────────────────────────────────────────────────
        // Just the Control Center widgets now; the card sizes to fit them.
        // Notifications live in the separate transparent module below.
        Item {
            id: mainArea
            anchors.fill: parent
            anchors.margins: 14
            visible: opacity > 0.002
            opacity: win.detail === "" ? 1 : 0
            Behavior on opacity { AppleSpring { spring: 18 } }

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
                            // Centered vertically so the leftover space splits
                            // evenly top/bottom (top row and bottom row get the
                            // same padding) instead of all collecting under the
                            // last row.
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
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
                                icon: "󰄛"
                                label: "Usage"
                                sublabel: ""
                                active: SysUsageService.runcatEnabled
                                onIconClicked: SysUsageService.toggleRuncat()
                                onBodyClicked: win.detail = "usage"
                            }
                        }
                    }

                    // 2×2 tile grid: DND + Screen Time on top, Battery + Power
                    // below. Each row fills half the column height so all four
                    // tiles match the connectivity panel's overall height.
                    ColumnLayout {
                        Layout.preferredWidth: mainArea.columnW
                        Layout.preferredHeight: 178
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8

                            CCMiniTile {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.fillHeight: true
                                icon: "󰂛"
                                label: "Disturb"
                                active: NcServer.dnd
                                showChevron: true
                                // Icon flips DND instantly; the rest of the tile
                                // (and the chevron) drills into the duration menu.
                                iconToggle: true
                                onIconClicked: NcServer.toggleDnd()
                                onClicked: win.detail = "dnd"
                            }

                            CCMiniTile {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.fillHeight: true
                                icon: "󰍹"
                                iconBg: "#0A84FF"
                                label: "Screen Time"
                                showChevron: true
                                onClicked: win.detail = "screentime"
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: 8

                            CCMiniTile {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.fillHeight: true
                                icon: BatteryService.charging ? "󰂄" : "󰁹"
                                iconBg: BatteryService.charging ? "#34C759"
                                      : (BatteryService.level <= 20 ? "#FF453A" : "#0A84FF")
                                label: "Battery"
                                onClicked: win.detail = "battery"
                            }

                            CCMiniTile {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                Layout.fillHeight: true
                                icon: "󰐥"
                                iconBg: "#FF453A"
                                label: "Power"
                                onClicked: win.detail = "power"
                            }
                        }
                    }
                }

                // ── DISPLAY ───────────────────────────────────────────────────
                // The tile expands downward when the dropdown button is tapped,
                // revealing the Dark Mode / Night Shift toggles inline (no popup).
                CCPanel {
                    id: displayPanel
                    clip: true
                    Layout.fillWidth: true
                    Layout.preferredHeight: (win.displayMenuOpen
                        ? brightnessSlider.implicitHeight + 18 + displayToggles.implicitHeight
                        : brightnessSlider.implicitHeight) + 28
                    Behavior on Layout.preferredHeight {
                        AppleSpring {
                            id: displayHeightMotion
                            spring: 18
                            epsilon: 0.25
                            onRunningChanged: if (!running) win.finishInlineResize()
                        }
                    }

                    CCSlider {
                        id: brightnessSlider
                        anchors {
                            left: parent.left
                            right: displayMenuBtn.left
                            rightMargin: 12
                            top: parent.top
                        }
                        height: implicitHeight
                        label: "Display"
                        icon: "󰃞"
                        value: BrightnessService.pct
                        onMoved: v => BrightnessService.setPct(v)
                    }

                    // Round dropdown button — same height as the slider track and
                    // pinned to its exact vertical position. Toggles the inline menu.
                    Rectangle {
                        id: displayMenuBtn
                        width: brightnessSlider.trackHeight
                        height: brightnessSlider.trackHeight
                        radius: height / 2
                        anchors {
                            right: parent.right
                            top: brightnessSlider.top
                            topMargin: brightnessSlider.trackTop
                        }
                        color: menuBtnMa.containsMouse || win.displayMenuOpen
                            ? (dark ? Qt.rgba(1,1,1,0.20) : Qt.rgba(0,0,0,0.12))
                            : (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.06))
                        border.width: 1
                        border.color: dark ? Qt.rgba(1,1,1,0.12) : Qt.rgba(0,0,0,0.10)
                        scale: menuBtnMa.pressed ? ThemeService.pressScale : 1
                        Behavior on scale { AppleSpring { spring: 13 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰅀"
                            color: dark ? "#e6ebf2" : "#3a3a3c"
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 13
                            rotation: win.displayMenuOpen ? 180 : 0
                            Behavior on rotation { AppleSpring { spring: 13; epsilon: 0.25 } }
                        }

                        MouseArea {
                            id: menuBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: {
                                win.inlineResizeActive = true
                                win.displayMenuOpen = !win.displayMenuOpen
                            }
                        }
                    }

                    // Hidden toggles, revealed as the tile grows. Clipped by the
                    // panel while collapsed; disabled so they can't catch clicks.
                    Row {
                        id: displayToggles
                        anchors {
                            top: brightnessSlider.bottom
                            topMargin: 18
                            horizontalCenter: parent.horizontalCenter
                        }
                        spacing: 28
                        opacity: win.displayMenuOpen ? 1 : 0
                        enabled: win.displayMenuOpen
                        Behavior on opacity { AppleSpring { spring: 13 } }

                        CCDisplayToggle {
                            icon: "󰔎"
                            label: "Dark Mode"
                            active: ThemeService.isDark
                            onClicked: ThemeService.toggle()
                        }
                        CCDisplayToggle {
                            icon: "󰃠"
                            label: "Night Shift"
                            active: NightShiftService.active
                            onClicked: NightShiftService.toggle()
                        }
                    }
                }

                // ── SOUND ─────────────────────────────────────────────────────
                // Expands downward to reveal the output-device picker.
                CCPanel {
                    id: soundPanel
                    clip: true
                    Layout.fillWidth: true
                    Layout.preferredHeight: (win.soundMenuOpen
                        ? soundSlider.implicitHeight + 14 + soundMenu.implicitHeight
                        : soundSlider.implicitHeight) + 28
                    Behavior on Layout.preferredHeight {
                        AppleSpring {
                            id: soundHeightMotion
                            spring: 18
                            epsilon: 0.25
                            onRunningChanged: if (!running) win.finishInlineResize()
                        }
                    }

                    CCSlider {
                        id: soundSlider
                        anchors {
                            left: parent.left
                            right: soundMenuBtn.left
                            rightMargin: 12
                            top: parent.top
                        }
                        height: implicitHeight
                        label: "Sound"
                        icon: AudioService.muted ? "󰝟"
                            : (AudioService.vol < 33 ? "󰕿"
                                                     : (AudioService.vol < 66 ? "󰖀" : "󰕾"))
                        value: AudioService.vol
                        onMoved: v => AudioService.setVolume(v)
                    }

                    // Round dropdown button — same height as the slider track and
                    // pinned to its exact vertical position. Toggles the output menu.
                    Rectangle {
                        id: soundMenuBtn
                        width: soundSlider.trackHeight
                        height: soundSlider.trackHeight
                        radius: height / 2
                        anchors {
                            right: parent.right
                            top: soundSlider.top
                            topMargin: soundSlider.trackTop
                        }
                        color: soundMenuBtnMa.containsMouse || win.soundMenuOpen
                            ? (dark ? Qt.rgba(1,1,1,0.20) : Qt.rgba(0,0,0,0.12))
                            : (dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.06))
                        border.width: 1
                        border.color: dark ? Qt.rgba(1,1,1,0.12) : Qt.rgba(0,0,0,0.10)
                        scale: soundMenuBtnMa.pressed ? ThemeService.pressScale : 1
                        Behavior on scale { AppleSpring { spring: 13 } }

                        Text {
                            anchors.centerIn: parent
                            text: "󰅀"
                            color: dark ? "#e6ebf2" : "#3a3a3c"
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 13
                            rotation: win.soundMenuOpen ? 180 : 0
                            Behavior on rotation { AppleSpring { spring: 13; epsilon: 0.25 } }
                        }

                        MouseArea {
                            id: soundMenuBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPressed: {
                                win.inlineResizeActive = true
                                if (!win.soundMenuOpen) AudioService.refreshDevices()
                                win.soundMenuOpen = !win.soundMenuOpen
                            }
                        }
                    }

                    // Output + Input device lists and Sound Preferences, revealed
                    // as the tile grows. Clipped by the panel while collapsed;
                    // disabled so the rows can't catch clicks.
                    Column {
                        id: soundMenu
                        anchors {
                            top: soundSlider.bottom
                            topMargin: 12
                            left: parent.left
                            right: parent.right
                        }
                        spacing: 2
                        opacity: win.soundMenuOpen ? 1 : 0
                        enabled: win.soundMenuOpen
                        Behavior on opacity { AppleSpring { spring: 13 } }

                        // ── Output ──────────────────────────────────────────────
                        Text {
                            text: "Output"
                            color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.45)
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            bottomPadding: 4
                        }

                        Repeater {
                            model: AudioService.sinks
                            CCOutputRow {
                                width: soundMenu.width
                                label: AudioService.deviceLabel(modelData.name, modelData.description)
                                active: modelData.name === AudioService.defaultSink
                                icon: {
                                    let s = (label + " " + (modelData.name || "")).toLowerCase()
                                    if (s.includes("bluez") || s.includes("headphone")
                                        || s.includes("headset") || s.includes("airpod")) return "󰋋"
                                    if (s.includes("hdmi") || s.includes("display") || s.includes("monitor")) return "󰍹"
                                    return "󰓃"
                                }
                                onClicked: AudioService.setSink(modelData.name)
                            }
                        }

                        // divider
                        Item {
                            width: soundMenu.width
                            height: 13
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width; height: 1
                                color: dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08)
                            }
                        }

                        // ── Input ───────────────────────────────────────────────
                        Text {
                            text: "Input"
                            color: dark ? Qt.rgba(1,1,1,0.55) : Qt.rgba(0,0,0,0.45)
                            font.family: "SF Pro Display"
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            bottomPadding: 4
                        }

                        Repeater {
                            model: AudioService.sources
                            CCOutputRow {
                                width: soundMenu.width
                                label: AudioService.deviceLabel(modelData.name, modelData.description)
                                active: modelData.name === AudioService.defaultSource
                                icon: {
                                    let s = (label + " " + (modelData.name || "")).toLowerCase()
                                    if (s.includes("bluez") || s.includes("headphone")
                                        || s.includes("headset") || s.includes("airpod")) return "󰋋"
                                    return "󰍬"
                                }
                                onClicked: AudioService.setSource(modelData.name)
                            }
                        }

                        // divider
                        Item {
                            width: soundMenu.width
                            height: 13
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width; height: 1
                                color: dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08)
                            }
                        }

                        // ── Sound Preferences… → pavucontrol ────────────────────
                        Item {
                            width: soundMenu.width
                            height: 34

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: -6
                                anchors.rightMargin: -6
                                radius: 8
                                color: prefsMa.containsMouse
                                    ? (dark ? Qt.rgba(1,1,1,0.06) : Qt.rgba(0,0,0,0.04))
                                    : "transparent"
                                scale: prefsMa.pressed ? 0.985 : 1
                                Behavior on scale { AppleSpring { spring: 13 } }
                            }

                            Text {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                text: "Sound Preferences…"
                                color: dark ? "#f5f6f8" : "#1c1c1e"
                                font.family: "SF Pro Display"
                                font.pixelSize: 14
                            }

                            MouseArea {
                                id: prefsMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    AudioService.openMixer()
                                    NcServer.controlCenterVisible = false
                                }
                            }
                        }
                    }
                }

                // ── NOW PLAYING ───────────────────────────────────────────────
                CCPanel {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    contentPadding: 10
                    CCMediaPanel { anchors.fill: parent }
                }
            }
        }
        }

        // ── NOTIFICATIONS — separate, transparent module below the Control
        // Center so the cards float macOS-style instead of sitting on a panel.
        Item {
            id: notifModule
            visible: NcServer.count > 0 && win.detail === ""
            // Slightly narrower than the CC card, centered under it.
            width: card.width - 12
            anchors {
                top: card.bottom
                topMargin: 28
                horizontalCenter: card.horizontalCenter
                bottom: parent.bottom
                bottomMargin: win.bottomGap
            }

            // Clear All lives in its own row beneath the scroller, so it stays
            // fully opaque — the fade only ever touches the cards above it.
            readonly property int clearAllH: 30
            readonly property int clearAllGap: 6
            readonly property real listMax: height - clearAllH - clearAllGap

            // Scroll-fade bookkeeping. scrollFrac is 0 at the top, 1 at the
            // bottom; it drives a crossfade between the bottom and top fades so
            // the dark edge follows whichever side still hides content.
            readonly property bool overflowing: scroll.contentHeight > scroll.height + 1
            readonly property real scrollFrac: overflowing
                ? Math.max(0, Math.min(1, scroll.contentY / (scroll.contentHeight - scroll.height)))
                : 0

            Flickable {
                id: scroll
                anchors { top: parent.top; left: parent.left; right: parent.right }
                // Hug the content when short so the fade rides the last card;
                // cap at the available height and scroll once the list grows.
                height: Math.min(stackColumn.implicitHeight, notifModule.listMax)
                contentHeight: stackColumn.implicitHeight
                clip: true

                // interactive=true is required for Flickable to even *see*
                // wheel events (its wheelEvent handler short-circuits when
                // interactive is false). Drag-to-scroll is therefore on, but
                // wheel + touchpad work consistently.
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

                // Kinetic scroll: touchpad swipes glide with momentum, mouse
                // wheel is one crisp step per notch (shared kinetic.js — same
                // feel as the emoji picker and other scroll areas).
                property var _ks: ({})
                WheelHandler {
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        scrollGlide.stop()
                        event.accepted = true
                        if (Kinetic.onWheel(scroll, event, scroll._ks, { gain: 100 }))
                            scrollEnd.restart()
                    }
                }
                Timer {
                    id: scrollEnd
                    interval: 70
                    onTriggered: {
                        let g = Kinetic.fling(scroll, scroll._ks, {})
                        if (g) { scrollGlide.to = g.to; scrollGlide.restart() }
                    }
                }
                SpringAnimation {
                    id: scrollGlide
                    target: scroll
                    property: "contentY"
                    spring: 13
                    damping: ThemeService.momentumDamping
                    epsilon: 0.25
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
                        Behavior on opacity { AppleSpring { spring: 13 } }
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
                            readonly property int peekStep: 7
                            readonly property int peekH: 7
                            readonly property int peekJoinOverlap: 1

                            // Top card lives at y=4 so the count badge at top
                            // (rendered at y=0) doesn't get clipped by Flickable.
                            readonly property int topPad: 4

                            // Height: collapsed shows top + peek edges; expanded
                            // stacks all cards vertically.
                            height: expanded
                                ? (topCard.y + topCard.implicitHeight
                                    + (notifs.length > 1 ? expandedCol.implicitHeight + 8 : 0))
                                : (topCard.y + topCard.implicitHeight
                                    + extra * peekStep - (extra > 0 ? peekJoinOverlap : 0))
                            Behavior on height { AppleSpring { spring: 18; epsilon: 0.25 } }

                            StackPeek {
                                visible: !stackDelegate.expanded && stackDelegate.extra >= 2
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 40
                                height: stackDelegate.peekH
                                y: topCard.y + topCard.implicitHeight
                                    + stackDelegate.peekStep - stackDelegate.peekJoinOverlap
                                fill: ThemeService.notificationStackBg2
                                z: 0
                            }

                            StackPeek {
                                visible: !stackDelegate.expanded && stackDelegate.extra >= 1
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: parent.width - 22
                                height: stackDelegate.peekH
                                y: topCard.y + topCard.implicitHeight
                                    - stackDelegate.peekJoinOverlap
                                fill: ThemeService.notificationStackBg1
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
                                fadeActive: notifModule.overflowing
                                fadeViewportH: scroll.height
                                fadeScrollFrac: notifModule.scrollFrac
                                fadeViewportY: stackDelegate.y + topCard.y - scroll.contentY
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
                                Behavior on opacity { AppleSpring { spring: 13 } }

                                Repeater {
                                    model: stackDelegate.expanded
                                        ? stackDelegate.notifs.slice(1)
                                        : []
                                    delegate: NotificationCard {
                                        id: expCard
                                        required property var modelData
                                        notification: modelData
                                        inControlCenter: true
                                        width: expandedCol.width
                                        fadeActive: notifModule.overflowing
                                        fadeViewportH: scroll.height
                                        fadeScrollFrac: notifModule.scrollFrac
                                        fadeViewportY: stackDelegate.y + expandedCol.y
                                            + expCard.y - scroll.contentY
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
                                scale: badgeMa.pressed ? ThemeService.pressScale : 1
                                Behavior on scale { AppleSpring { spring: 13 } }

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
                                    id: badgeMa
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

            // (Scroll fade is applied per-card inside NotificationCard so the
            // gaps between cards stay transparent — see its fade* properties,
            // wired from the card sites above.)

            // ── CLEAR ALL — its own row below the scroller, so the fade never
            // touches it and it stays fully opaque / always reachable.
            Item {
                id: clearAllRow
                anchors {
                    top: scroll.bottom
                    topMargin: notifModule.clearAllGap
                    left: parent.left
                    right: parent.right
                }
                height: notifModule.clearAllH

                Rectangle {
                    id: clearAllButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: clearAllLabel.implicitWidth + 24
                    height: 28
                    radius: 14
                    color: clearAllMa.containsMouse
                        ? ThemeService.tileBgHover
                        : ThemeService.tileBg
                    border.width: 0
                    scale: clearAllMa.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 13 } }

                    Text {
                        id: clearAllLabel
                        anchors.centerIn: parent
                        text: "Clear All"
                        color: dark ? "#ff6b6b" : "#FF3B30"
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: clearAllMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: NcServer.dismissAll()
                    }
                }
            }
        }

        // ── Optimized Battery Charging: turn-off confirmation (modal) ─────────
        Item {
            anchors.fill: card
            visible: win.batteryConfirm
            z: 1000

            component DlgBtn: Rectangle {
                id: db
                property string label: ""
                property bool primary: false
                signal activated()
                width: parent ? parent.width : 0
                height: 34
                radius: 9
                color: db.primary
                    ? (dbMa.containsMouse ? "#0A74E0" : "#0A84FF")
                    : (dbMa.containsMouse ? (win.dark ? Qt.rgba(1,1,1,0.16) : Qt.rgba(0,0,0,0.10))
                                          : (win.dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.06)))
                scale: dbMa.pressed ? ThemeService.pressScale : 1
                Behavior on scale { AppleSpring { spring: 13 } }
                Text {
                    anchors.centerIn: parent
                    text: db.label
                    color: db.primary ? "#ffffff" : (win.dark ? "#f5f6f8" : "#1c1c1e")
                    font.family: "SF Pro Display"; font.pixelSize: 12
                    font.weight: db.primary ? Font.DemiBold : Font.Medium
                }
                MouseArea {
                    id: dbMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: db.activated()
                }
            }

            // Dim + tap-outside-to-cancel.
            Rectangle {
                anchors.fill: parent
                radius: card.radius
                color: Qt.rgba(0, 0, 0, win.dark ? 0.45 : 0.28)
                MouseArea { anchors.fill: parent; onPressed: win.batteryConfirm = false }
            }

            Rectangle {
                id: confirmBox
                anchors.centerIn: parent
                width: Math.min(300, card.width - 48)
                radius: 16
                color: win.dark ? "#2c2c2e" : "#ffffff"
                border.color: win.dark ? Qt.rgba(1,1,1,0.10) : Qt.rgba(0,0,0,0.08)
                border.width: 1
                implicitHeight: confirmCol.implicitHeight + 36
                MouseArea { anchors.fill: parent }   // swallow clicks on the box

                Column {
                    id: confirmCol
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18 }
                    spacing: 12

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: ""   // nf-fa-warning
                        color: "#FFCC00"
                        font.family: "JetBrainsMono Nerd Font Propo"
                        font.pixelSize: 34
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "Optimized Battery Charging\nhelps reduce battery aging"
                        color: win.dark ? "#f5f6f8" : "#1c1c1e"
                        font.family: "SF Pro Display"; font.pixelSize: 13; font.weight: Font.Bold
                        wrapMode: Text.WordWrap
                        lineHeight: 1.2
                    }

                    Column {
                        width: parent.width
                        spacing: 8
                        topPadding: 4
                        DlgBtn {
                            label: "Turn Off Until Tomorrow"; primary: true
                            onActivated: { BatteryService.snoozeOptimized(); win.batteryConfirm = false }
                        }
                        DlgBtn {
                            label: "Turn Off"
                            onActivated: { BatteryService.disableOptimized(); win.batteryConfirm = false }
                        }
                        DlgBtn {
                            label: "Cancel"
                            onActivated: win.batteryConfirm = false
                        }
                    }
                }
            }
        }
    }
}
