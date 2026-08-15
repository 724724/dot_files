import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Controls

Item {
    id: root

    // Seeded from parent on Loader.onLoaded — avoids the off-flash while a
    // duplicate nmcli call would otherwise be in flight.
    property bool wifiOn: false
    property string activeSsid: ""
    property string activeNetworkType: "none"
    property bool ethernetAvailable: false

    signal back()
    signal pollRequest()  // ask parent to refresh its own wifiOn/wifiSsid

    readonly property bool dark: ThemeService.isDark
    implicitHeight: column.implicitHeight

    // Network list is owned by the WifiService singleton so the cache survives
    // closing/re-opening the detail panel.
    readonly property var networks: WifiService.networks
    readonly property bool scanning: WifiService.scanning
    readonly property var visibleNetworks: networks.filter(n => !(root.activeNetworkType === "wifi" && n.active))
    readonly property var myNetworks: visibleNetworks.filter(n => WifiService.knownSsids[n.ssid] === true)
    readonly property var otherNetworks: visibleNetworks.filter(n => WifiService.knownSsids[n.ssid] !== true)
    readonly property var groupedNetworkRows: {
        let rows = []
        if (myNetworks.length > 0) {
            rows.push({ section: true, title: "My Networks" })
            rows = rows.concat(myNetworks)
        }
        if (otherNetworks.length > 0) {
            rows.push({ section: true, title: "Other Networks" })
            rows = rows.concat(otherNetworks)
        }
        return rows
    }

    // Inline password prompt state (transient, lives on this panel)
    property string passwordSsid: ""   // expanded password row (after auth fail or secured click)
    property string passwordError: ""

    // Mirror WifiService.pendingSsid for in-row "Connecting…" badge
    readonly property string pendingSsid: WifiService.pendingSsid

    // Pick a 4-bar Wi-Fi glyph based on signal strength. The lock indicator
    // stays separate (rendered to the right of the SSID) so the bars stay
    // visually consistent across secured and open networks.
    function _wifiGlyph(signal) {
        if (signal >= 80) return "󰤨"
        if (signal >= 60) return "󰤥"
        if (signal >= 40) return "󰤢"
        if (signal >= 15) return "󰤟"
        return "󰤯"
    }

    // Context menu for a network. The connected network gets the full set;
    // other (list) networks just get Connect.
    function _wifiMenuItems(net) {
        if (net.active === true) {
            return [
                { label: "Disconnect",
                  action: function() { WifiService.disconnectSsid(net.ssid) } },
                { label: "Edit Connection…",
                  action: function() { WifiService.editConnection(net.ssid) } },
                { label: "Forget Network", danger: true,
                  action: function() { WifiService.forget(net.ssid) } }
            ]
        }
        let items = [
            { label: "Connect",
              action: function() { WifiService.smartConnect(net.ssid, net.security, "") } }
        ]
        // Secured networks: a deterministic way to open the inline password row
        // (handy when a saved password is wrong, or to avoid the agent dialog
        // popping under the overlay).
        if (net.security !== "") {
            items.push({
                label: "Enter Password…",
                action: function() { root.passwordSsid = net.ssid; root.passwordError = "" }
            })
        }
        return items
    }

    // ── PROCESSES ─────────────────────────────────────────────────────────────
    // Inline flip — the swaync helper depended on $SWAYNC_TOGGLE_STATE which
    // we don't pass, so it always ran the off branch. Read the current state
    // and invert it instead.
    Process {
        id: toggleProc
        command: ["bash", "-c",
            "if [ \"$(nmcli radio wifi)\" = enabled ]; then nmcli radio wifi off;" +
            " else nmcli radio wifi on; fi"]
        onRunningChanged: {
            if (!running) {
                root.pollRequest()
                // Re-scan after toggle so newly-on networks populate or off
                // networks clear out.
                WifiService.refresh()
            }
        }
    }

    Process { id: settingsProc; command: ["nm-connection-editor"] }

    // Listen for the connect result from WifiService to drive the password row
    Connections {
        target: WifiService
        function onConnectFinished(ssid, exitCode) {
            if (exitCode === 0) {
                root.passwordSsid = ""
                root.passwordError = ""
                return
            }
            // Connect failed — likely needs a password. Find the network in
            // our list to check if it's secured.
            let net = root.networks.find(n => n.ssid === ssid)
            if (net && net.security !== "") {
                if (root.passwordSsid === ssid) {
                    root.passwordError = "Incorrect password"
                } else {
                    root.passwordSsid = ssid
                    root.passwordError = ""
                }
            }
        }
        function onNetworkStateChanged() {
            root.pollRequest()
        }
    }

    // On entry: show cached results immediately. Auto-refresh only if stale
    // (older than 30 s) or never scanned.
    Component.onCompleted: WifiService.refreshIfStale(30000)

    // Light periodic refresh while panel is open
    Timer {
        interval: 15000
        running: root.visible && root.wifiOn
        repeat: true
        onTriggered: WifiService.refresh()
    }

    // ── LAYOUT ────────────────────────────────────────────────────────────────
    Column {
        id: column
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 8

        CCDetailHeader {
            width: parent.width
            title: "Wi-Fi"
            toggleVisible: true
            toggleChecked: root.wifiOn
            actionIcon: "󰑐"
            actionBusy: root.scanning
            onBack: root.back()
            onToggled: toggleProc.running = true
            onActionClicked: WifiService.refresh()
        }

        // Active connection card
        Rectangle {
            width: parent.width
            height: 48
            radius: 10
            color: ThemeService.tileBg
            visible: root.activeNetworkType === "ethernet"
                || (root.activeNetworkType === "wifi" && root.activeSsid !== "")

            Rectangle {
                id: activeIcon
                anchors {
                    left: parent.left
                    leftMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                width: 28; height: 28; radius: 14
                color: "#0A84FF"
                Text {
                    anchors.centerIn: parent
                    text: root.activeNetworkType === "ethernet" ? "󰈀" : "󰖩"
                    color: "#ffffff"
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 14
                }
            }

            Column {
                anchors {
                    left: activeIcon.right
                    leftMargin: 10
                    verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.activeNetworkType === "ethernet"
                        ? "Ethernet"
                        : root.activeSsid
                    color: ThemeService.textPrimary
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "Connected"
                    color: ThemeService.textSecondary
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                }
            }

            // Right-click anywhere, or click the ⋮ button, for the menu.
            MouseArea {
                id: activeMa
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                enabled: root.activeNetworkType === "wifi"
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    let pt = activeMa.mapToItem(root, mouse.x, mouse.y)
                    ctxMenu.openAt(pt.x, pt.y, root._wifiMenuItems(
                        { ssid: root.activeSsid, active: true, security: "" }))
                }
            }

            CCMenuDots {
                id: wifiKebab
                anchors {
                    right: parent.right
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                visible: root.activeNetworkType === "wifi"
                onClicked: {
                    let pt = wifiKebab.mapToItem(root, wifiKebab.width, wifiKebab.height)
                    ctxMenu.openAt(pt.x, pt.y, root._wifiMenuItems(
                        { ssid: root.activeSsid, active: true, security: "" }))
                }
            }
        }

        Text {
            text: "Scanning…"
            color: ThemeService.textSecondary
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            visible: root.scanning
        }

        // Network list (scrollable, capped height)
        Flickable {
            id: listFlick
            width: parent.width
            height: Math.min(listCol.implicitHeight, 280)
            contentHeight: listCol.implicitHeight
            clip: true
            visible: (root.wifiOn && root.groupedNetworkRows.length > 0)
                || (root.ethernetAvailable && root.activeNetworkType !== "ethernet")
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
                    let max = Math.max(0, listFlick.contentHeight - listFlick.height)
                    listFlick.contentY = Math.max(0, Math.min(max, listFlick.contentY - dy))
                    event.accepted = true
                }
            }

            ScrollBar.vertical: ScrollBar {
                id: wifiBar
                policy: listFlick.contentHeight > listFlick.height
                    ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                contentItem: Rectangle {
                    implicitWidth: 3
                    radius: 1.5
                    color: dark ? "#ffffff" : "#000000"
                    opacity: wifiBar.pressed ? 0.45 : (wifiBar.active ? 0.30 : 0.15)
                    Behavior on opacity { AppleSpring { spring: 13 } }
                }
            }

            Column {
                id: listCol
                width: parent.width
                spacing: 2

                Item {
                    id: ethernetRow
                    width: parent.width
                    height: visible ? 40 : 0
                    visible: root.ethernetAvailable
                        && root.activeNetworkType !== "ethernet"
                    scale: ethernetMa.pressed ? 0.985 : 1
                    Behavior on scale { AppleSpring { spring: 13 } }

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: ethernetMa.containsMouse
                            ? ThemeService.rowBgHover
                            : ThemeService.rowBgHoverClear
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        text: "󰈀"
                        color: dark ? "#0A84FF" : "#007AFF"
                        font.family: "JetBrainsMono Nerd Font Propo"
                        font.pixelSize: 14
                    }

                    Text {
                        anchors {
                            left: parent.left
                            leftMargin: 32
                            verticalCenter: parent.verticalCenter
                        }
                        text: "Use Ethernet"
                        color: ThemeService.textPrimary
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: ethernetMa
                        anchors.fill: parent
                        enabled: !WifiService.routeSwitching
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: WifiService.selectEthernet()
                    }
                }

                Repeater {
                    model: root.wifiOn ? root.groupedNetworkRows : []
                    delegate: Column {
                        id: rowWrap
                        required property var modelData
                        width: listCol.width
                        spacing: 0
                        visible: true

                        readonly property bool section: modelData.section === true
                        readonly property bool expanded: !section && root.passwordSsid === modelData.ssid
                        readonly property bool connecting: !section && root.pendingSsid === modelData.ssid

                        // Eye toggle: reveals the whole password. Always back to
                        // masked when the row reopens, so a stale reveal never
                        // leaks the previous entry.
                        property bool revealPw: false

                        // Grab keyboard focus the moment the password row opens so
                        // the user can type immediately — no extra click needed
                        // (the layer is keyboardFocus: OnDemand, so forcing focus
                        // on the field is what makes the compositor route keys here).
                        onExpandedChanged: {
                            revealPw = false
                            if (expanded) Qt.callLater(pwField.forceActiveFocus)
                        }

                        Item {
                            width: parent.width
                            height: rowWrap.section ? 30 : 0
                            visible: rowWrap.section

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 8
                                    bottom: parent.bottom
                                    bottomMargin: 5
                                }
                                text: rowWrap.modelData.title || ""
                                color: ThemeService.textSecondary
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }

                        // Main row
                        Item {
                            id: networkRow
                            width: parent.width
                            height: rowWrap.section ? 0 : 40
                            visible: !rowWrap.section
                            scale: rowMa.pressed ? 0.985 : 1
                            Behavior on scale { AppleSpring { spring: 13 } }

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: rowWrap.expanded
                                    ? ThemeService.rowBgActive
                                    : (rowMa.containsMouse
                                        ? ThemeService.rowBgHover
                                        : ThemeService.rowBgHoverClear)
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                text: root._wifiGlyph(rowWrap.modelData.signal)
                                color: dark ? "#0A84FF" : "#007AFF"
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 14
                            }

                            Text {
                                anchors {
                                    left: parent.left
                                    leftMargin: 32
                                    right: rightCluster.left
                                    rightMargin: 6
                                    verticalCenter: parent.verticalCenter
                                }
                                text: rowWrap.modelData.ssid || ""
                                color: ThemeService.textPrimary
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }

                            Row {
                                id: rightCluster
                                anchors {
                                    right: parent.right
                                    rightMargin: 8
                                    verticalCenter: parent.verticalCenter
                                }
                                spacing: 6

                                Text {
                                    text: rowWrap.connecting ? "Connecting…" : ""
                                    color: ThemeService.textSecondary
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 10
                                    visible: rowWrap.connecting
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Text {
                                    text: rowWrap.modelData.security !== "" ? "󰌾" : ""
                                    color: ThemeService.textTertiary
                                    font.family: "JetBrainsMono Nerd Font Propo"
                                    font.pixelSize: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    if (mouse.button === Qt.RightButton) {
                                        let pt = rowMa.mapToItem(root, mouse.x, mouse.y)
                                        ctxMenu.openAt(pt.x, pt.y, root._wifiMenuItems(rowWrap.modelData))
                                        return
                                    }
                                    if (rowWrap.expanded) {
                                        // toggle close
                                        root.passwordSsid = ""
                                        root.passwordError = ""
                                    } else {
                                        // Open / saved networks connect straight
                                        // away; a new secured network opens the
                                        // inline password row (the connect-finished
                                        // handler does this on the exit-100 sentinel)
                                        // instead of letting nm-applet pop its own
                                        // dialog under the overlay.
                                        WifiService.smartConnect(
                                            rowWrap.modelData.ssid,
                                            rowWrap.modelData.security, "")
                                    }
                                }
                            }
                        }

                        // Password input row (collapses smoothly)
                        Item {
                            width: parent.width
                            height: !rowWrap.section && rowWrap.expanded ? 56 : 0
                            clip: true
                            Behavior on height { AppleSpring { spring: 11; epsilon: 0.25 } }
                            opacity: rowWrap.expanded ? 1 : 0
                            Behavior on opacity { AppleSpring { spring: 13 } }

                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: 4
                                anchors.bottomMargin: 4
                                radius: 8
                                color: ThemeService.fieldBg
                                border.width: 0

                                TextField {
                                    id: pwField
                                    anchors {
                                        left: parent.left
                                        right: eyeBtn.left
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 10
                                        rightMargin: 2
                                    }
                                    placeholderText: root.passwordError !== ""
                                        ? root.passwordError
                                        : "Password"
                                    placeholderTextColor: root.passwordError !== ""
                                        ? "#FF453A"
                                        : ThemeService.textTertiary
                                    color: ThemeService.textPrimary
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 12
                                    echoMode: rowWrap.revealPw
                                        ? TextInput.Normal
                                        : TextInput.Password
                                    // iOS-style: the character just typed stays
                                    // legible for a beat before it turns into a dot.
                                    passwordMaskDelay: 1200
                                    background: null
                                    selectByMouse: true
                                    onAccepted: WifiService.tryConnect(rowWrap.modelData.ssid, text)
                                    Keys.onEscapePressed: {
                                        root.passwordSsid = ""
                                        root.passwordError = ""
                                    }
                                    Component.onCompleted: if (rowWrap.expanded) forceActiveFocus()
                                }

                                // Reveal toggle, at the right edge of the input area
                                Item {
                                    id: eyeBtn
                                    anchors {
                                        right: connectBtn.left
                                        verticalCenter: parent.verticalCenter
                                        rightMargin: 2
                                    }
                                    width: 26; height: 26
                                    scale: eyeMa.pressed ? ThemeService.pressScale : 1
                                    Behavior on scale { AppleSpring { spring: 13 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: rowWrap.revealPw ? "󰈉" : "󰈈"
                                        color: eyeMa.containsMouse || rowWrap.revealPw
                                            ? ThemeService.textPrimary
                                            : ThemeService.textTertiary
                                        font.family: "JetBrainsMono Nerd Font Propo"
                                        font.pixelSize: 13
                                    }

                                    MouseArea {
                                        id: eyeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            rowWrap.revealPw = !rowWrap.revealPw
                                            // Keep typing where it was — toggling
                                            // echoMode must not steal the caret.
                                            pwField.forceActiveFocus()
                                            pwField.cursorPosition = pwField.text.length
                                        }
                                    }
                                }

                                Rectangle {
                                    id: connectBtn
                                    anchors {
                                        right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        rightMargin: 6
                                    }
                                    width: 64; height: 28; radius: 14
                                    scale: cMa.pressed ? ThemeService.pressScale : 1
                                    Behavior on scale { AppleSpring { spring: 13 } }
                                    color: cMa.containsMouse ? "#1a8cff" : "#0A84FF"

                                    Text {
                                        anchors.centerIn: parent
                                        text: rowWrap.connecting ? "…" : "Connect"
                                        color: "#ffffff"
                                        font.family: "SF Pro Display"
                                        font.pixelSize: 11
                                        font.weight: Font.DemiBold
                                    }

                                    MouseArea {
                                        id: cMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: WifiService.tryConnect(rowWrap.modelData.ssid, pwField.text)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Empty state
        Text {
            visible: root.wifiOn && root.networks.length === 0
                && !(root.ethernetAvailable
                    && root.activeNetworkType !== "ethernet")
            text: root.scanning ? "Searching…" : "No networks found"
            color: ThemeService.textTertiary
            font.family: "SF Pro Display"
            font.pixelSize: 11
            leftPadding: 8
            topPadding: 4
            bottomPadding: 4
        }

        // Wi-Fi Settings link
        Rectangle {
            id: wifiSettingsButton
            width: parent.width
            height: 36
            radius: 8
            scale: settingsMa.pressed ? 0.985 : 1
            Behavior on scale { AppleSpring { spring: 13 } }
            color: settingsMa.containsMouse
                ? ThemeService.rowBgHover
                : ThemeService.rowBgHoverClear

            Text {
                anchors {
                    left: parent.left
                    leftMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                text: "Wi-Fi Settings…"
                color: dark ? "#60b8ff" : "#007AFF"
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.Medium
            }

            MouseArea {
                id: settingsMa
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
