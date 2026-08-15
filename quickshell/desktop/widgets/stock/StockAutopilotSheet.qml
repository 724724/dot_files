import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic

Item {
    id: sheet
    required property var root
    anchors.fill: parent
    visible: root.autopilotVisible || panel.opacity > 0.002
    z: 150

    property bool advancedVisible: false
    readonly property var state: root.autopilotState || ({})
    readonly property var candidates: state.candidates || []
    readonly property var sectorPulse: state.sectorPulse || []
    readonly property var policy: root.automationState.policy || ({})
    readonly property var audit: root.automationState.audit || ({})
    readonly property var background: root.automationState.background || ({})
    readonly property bool automaticSelection: state.automaticSelection !== false
    readonly property bool automationEnabled: state.enabled === true
    readonly property bool controlsBusy: root.autopilotBusy || root.autopilotEmergencyBusy
        || root.automationBusy
    readonly property string operationDetail: root.autopilotStatusDetail()
    readonly property string failedGateDetail: root.autopilotFailedGateText(8)
    readonly property string hotSectors: sectorPulse.slice(0, 3).map(function(item) {
        return String(item.id || "").replace(/-/g, " ")
    }).join(" · ")

    Connections {
        target: root
        function onAutopilotVisibleChanged() {
            if (root.autopilotVisible) sheet.advancedVisible = false
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.44)
        opacity: root.autopilotVisible ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 22 } }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.autopilotVisible
        onPressed: root.closeAutopilot()
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        anchors.margins: 14
        radius: 18
        color: root.dark ? "#242426" : "#ffffff"
        border.color: root.separatorColor
        border.width: 1
        opacity: root.autopilotVisible ? 1 : 0
        scale: root.autopilotVisible ? 1 : 0.97
        transformOrigin: Item.BottomRight
        Behavior on opacity { AppleSpring { spring: 22 } }
        Behavior on scale { AppleSpring { spring: 22 } }
        MouseArea { anchors.fill: parent }

        Item {
            id: simplePage
            anchors.fill: parent
            opacity: sheet.advancedVisible ? 0 : 1
            x: sheet.advancedVisible ? -16 : 0
            enabled: !sheet.advancedVisible && root.autopilotVisible
            visible: opacity > 0.002
            Behavior on opacity { AppleSpring { spring: 24 } }
            Behavior on x { AppleSpring { spring: 22 } }

            Text {
                id: simpleTitle
                anchors { left: parent.left; top: parent.top }
                anchors.leftMargin: 26
                anchors.topMargin: 22
                text: root.t("Automatic Trading")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 22
                font.weight: Font.DemiBold
                font.letterSpacing: -0.4
            }

            Text {
                anchors { left: simpleTitle.left; top: simpleTitle.bottom }
                anchors.topMargin: 3
                text: root.t(root.liveAutopilotContext ? "KIS Production" : "KIS Paper")
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }

            ActionButton {
                anchors { right: simpleClose.left; top: parent.top }
                anchors.rightMargin: 8
                anchors.topMargin: 17
                width: 84
                height: 34
                label: root.t("Details")
                accent: root.foregroundColor
                onTriggered: sheet.advancedVisible = true
            }

            ActionButton {
                id: simpleClose
                anchors { right: parent.right; top: parent.top }
                anchors.rightMargin: 17
                anchors.topMargin: 17
                width: 34
                height: 34
                label: "✕"
                accent: root.secondaryColor
                onTriggered: root.closeAutopilot()
            }

            Column {
                id: simpleContent
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.leftMargin: 26
                anchors.rightMargin: 26
                anchors.topMargin: 78
                spacing: 14

                Rectangle {
                    width: parent.width
                    height: 148
                    radius: 16
                    color: root.raisedColor

                    Rectangle {
                        anchors { left: parent.left; top: parent.top }
                        anchors.leftMargin: 18
                        anchors.topMargin: 18
                        width: 10
                        height: 10
                        radius: 5
                        color: root.autopilotPhaseColor()
                    }

                    Text {
                        anchors { left: parent.left; top: parent.top }
                        anchors.leftMargin: 36
                        anchors.topMargin: 14
                        text: sheet.automationEnabled
                            ? root.t("Automatic trading is on") : root.t("Automatic trading is off")
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.2
                    }

                    ActionButton {
                        id: mainAction
                        anchors { right: parent.right; top: parent.top }
                        anchors.rightMargin: 18
                        anchors.topMargin: 14
                        width: 142
                        height: 38
                        label: root.autopilotHardStop() ? root.t("Review Safety Halt")
                            : (sheet.automationEnabled ? root.t("Stop Automatic Trading")
                            : (root.autopilotNeedsRetry() ? root.t("Try Again")
                            : root.t(root.liveAutopilotContext
                                ? "Start Live Auto Trading" : "Start Automatic Trading")))
                        accent: root.autopilotHardStop() ? root.negativeColor
                            : (sheet.automationEnabled ? "#ff9f0a"
                            : (root.liveAutopilotContext ? root.negativeColor : "#0a84ff"))
                        filled: true
                        enabled: !sheet.controlsBusy
                        onTriggered: {
                            if (root.autopilotHardStop()) sheet.advancedVisible = true
                            else if (sheet.automationEnabled) root.stopAutopilot()
                            else if (root.autopilotNeedsRetry()) root.retryAutopilot()
                            else root.startAutopilot(false, true)
                        }
                    }

                    Text {
                        anchors { left: parent.left; right: refreshButton.left; top: parent.top }
                        anchors.leftMargin: 18
                        anchors.rightMargin: 18
                        anchors.topMargin: 57
                        height: 66
                        text: root.autopilotSimpleStatus()
                        color: root.autopilotNeedsRetry() ? "#ff9f0a" : root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        lineHeight: 1.18
                        wrapMode: Text.WordWrap
                        verticalAlignment: Text.AlignVCenter
                    }

                    ActionButton {
                        id: refreshButton
                        anchors { right: parent.right; bottom: parent.bottom }
                        anchors.rightMargin: 18
                        anchors.bottomMargin: 16
                        width: root.autopilotNeedsRetry() ? 106 : 124
                        height: 36
                        label: sheet.controlsBusy ? root.t("Checking…")
                            : root.t(root.autopilotNeedsRetry() ? "Try Again" : "Refresh Now")
                        accent: root.autopilotNeedsRetry() ? "#ff9f0a" : "#0a84ff"
                        filled: root.autopilotNeedsRetry()
                        enabled: !sheet.controlsBusy
                        onTriggered: {
                            if (root.autopilotNeedsRetry()) root.retryAutopilot()
                            else root.refreshAutopilotNow()
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 90
                    spacing: 10

                    MetricCard {
                        width: (parent.width - 20) / 3
                        label: root.t("Holdings")
                        value: root.autopilotHoldingText()
                    }
                    MetricCard {
                        width: (parent.width - 20) / 3
                        label: root.t("Today's P&L")
                        value: root.autopilotTodayProfitText()
                        valueColor: {
                            let text = root.autopilotTodayProfitText()
                            if (text === "—") return root.secondaryColor
                            return text.charAt(0) === "-" ? root.negativeColor : root.positiveColor
                        }
                    }
                    MetricCard {
                        width: (parent.width - 20) / 3
                        label: root.t("Next Check")
                        value: root.autopilotNextCheckText()
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 54
                    radius: 13
                    color: Qt.rgba(0.04, 0.52, 1, root.dark ? 0.10 : 0.07)

                    Text {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        text: sheet.automaticSelection
                            ? root.t("News, trends, stock selection, buying, and loss protection run automatically.")
                            : root.t("You choose the stocks; monitoring, buying, and loss protection run automatically.")
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        Item {
            id: advancedPage
            anchors.fill: parent
            opacity: sheet.advancedVisible ? 1 : 0
            x: sheet.advancedVisible ? 0 : 18
            enabled: sheet.advancedVisible && root.autopilotVisible
            visible: opacity > 0.002
            Behavior on opacity { AppleSpring { spring: 24 } }
            Behavior on x { AppleSpring { spring: 22 } }

            ActionButton {
                id: backButton
                anchors { left: parent.left; top: parent.top }
                anchors.leftMargin: 17
                anchors.topMargin: 17
                width: 34
                height: 34
                label: "‹"
                accent: root.foregroundColor
                onTriggered: sheet.advancedVisible = false
            }

            Text {
                anchors { left: backButton.right; verticalCenter: backButton.verticalCenter }
                anchors.leftMargin: 10
                text: root.t("Automatic Trading Details")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 19
                font.weight: Font.DemiBold
                font.letterSpacing: -0.3
            }

            ActionButton {
                id: advancedClose
                anchors { right: parent.right; top: parent.top }
                anchors.rightMargin: 17
                anchors.topMargin: 17
                width: 34
                height: 34
                label: "✕"
                accent: root.secondaryColor
                onTriggered: root.closeAutopilot()
            }

            Rectangle {
                id: selectionCard
                anchors { left: parent.left; right: parent.right; top: parent.top }
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                anchors.topMargin: 64
                height: 76
                radius: 14
                color: root.raisedColor

                Column {
                    anchors { left: parent.left; right: automaticSwitch.left; verticalCenter: parent.verticalCenter }
                    anchors.leftMargin: 16
                    anchors.rightMargin: 14
                    spacing: 4
                    Text {
                        text: root.t("Automatic Stock Selection")
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Text {
                        width: parent.width
                        text: sheet.automaticSelection
                            ? root.t("AI picks stocks after checking news, trends, and risk.")
                            : root.t("Select stocks directly from the list below.")
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                }

                Rectangle {
                    id: automaticSwitch
                    anchors.right: emergencyButton.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    height: 28
                    radius: 14
                    color: sheet.automaticSelection ? root.positiveColor : root.separatorColor
                    opacity: enabled ? 1 : 0.42
                    enabled: !sheet.controlsBusy
                    scale: automaticSwitchArea.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 20 } }

                    Rectangle {
                        width: 22
                        height: 22
                        radius: 11
                        y: 3
                        x: sheet.automaticSelection ? parent.width - width - 3 : 3
                        color: "#ffffff"
                        Behavior on x { AppleSpring { spring: 20; epsilon: 0.1 } }
                    }

                    MouseArea {
                        id: automaticSwitchArea
                        anchors.fill: parent
                        enabled: parent.enabled
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPressed: root.setAutopilotAutomaticSelection(!sheet.automaticSelection)
                    }
                }

                ActionButton {
                    id: emergencyButton
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    anchors.rightMargin: 14
                    width: 108
                    height: 38
                    label: root.autopilotEmergencyBusy ? root.t("Stopping") : root.t("Emergency Stop")
                    accent: root.negativeColor
                    filled: sheet.automationEnabled
                    enabled: (sheet.automationEnabled || root.autopilotAction === "autopilot-start")
                        && !root.autopilotEmergencyBusy
                    onTriggered: root.emergencyStopAutopilot()
                }
            }

            Row {
                id: advancedContent
                anchors { left: parent.left; right: parent.right; top: selectionCard.bottom; bottom: advancedFooter.top }
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                anchors.topMargin: 12
                anchors.bottomMargin: 10
                spacing: 10

                Rectangle {
                    width: (parent.width - parent.spacing) * 0.64
                    height: parent.height
                    radius: 13
                    color: root.raisedColor

                    Text {
                        id: candidateTitle
                        anchors { left: parent.left; top: parent.top }
                        anchors.leftMargin: 14
                        anchors.topMargin: 12
                        text: root.t("Candidate Stocks")
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    ActionButton {
                        anchors { right: parent.right; verticalCenter: candidateTitle.verticalCenter }
                        anchors.rightMargin: 12
                        width: 96
                        height: 28
                        label: root.autopilotAction === "autopilot-scan"
                            ? root.t("Checking…") : root.t("Check Now")
                        accent: "#0a84ff"
                        enabled: !sheet.controlsBusy && root.autopilotCanScan && !root.autopilotRunning
                        onTriggered: root.discoverAutopilotCandidates()
                    }

                    ListView {
                        id: candidateList
                        anchors { left: parent.left; right: parent.right; top: candidateTitle.bottom; bottom: parent.bottom }
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        anchors.topMargin: 10
                        anchors.bottomMargin: 10
                        clip: true
                        spacing: 6
                        model: sheet.candidates
                        boundsBehavior: Flickable.DragAndOvershootBounds
                        boundsMovement: Flickable.FollowBoundsBehavior
                        flickDeceleration: 6000
                        maximumFlickVelocity: 6000
                        rebound: Transition {
                            SpringAnimation {
                                properties: "x,y"
                                spring: 18
                                damping: ThemeService.momentumDamping
                                epsilon: 0.25
                            }
                        }
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        property var kineticState: ({})

                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: function(event) {
                                candidateGlide.stop()
                                if (Kinetic.onWheel(candidateList, event, candidateList.kineticState, { gain: 76 }))
                                    candidateEndTimer.restart()
                            }
                        }

                        Timer {
                            id: candidateEndTimer
                            interval: 48
                            onTriggered: {
                                let glide = Kinetic.fling(candidateList, candidateList.kineticState, {})
                                if (!glide) return
                                candidateGlide.from = glide.from
                                candidateGlide.to = glide.to
                                candidateGlide.restart()
                            }
                        }

                        SpringAnimation {
                            id: candidateGlide
                            target: candidateList
                            property: "contentY"
                            spring: 18
                            damping: ThemeService.momentumDamping
                            epsilon: 0.25
                        }

                        delegate: Rectangle {
                            id: candidateCard
                            required property var modelData
                            readonly property bool chosen: !!modelData.selected
                            readonly property bool selectable: !sheet.controlsBusy
                            width: candidateList.width
                            height: 72
                            radius: 11
                            color: chosen
                                ? Qt.rgba(0.04, 0.52, 1, root.dark ? 0.16 : 0.10)
                                : (candidateHover.hovered
                                    ? (root.dark ? "#353538" : "#f0f0f4") : root.backgroundColor)
                            scale: candidateTap.pressed ? ThemeService.pressScale : 1
                            Behavior on scale { AppleSpring { spring: 20 } }

                            Rectangle {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                                anchors.leftMargin: 12
                                width: 22
                                height: 22
                                radius: 7
                                color: candidateCard.chosen ? "#0a84ff" : "transparent"
                                border.color: candidateCard.chosen ? "#0a84ff" : root.secondaryColor
                                border.width: 1
                                Text {
                                    anchors.centerIn: parent
                                    text: candidateCard.chosen ? "✓" : ""
                                    color: "#ffffff"
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 12
                                    font.weight: Font.Bold
                                }
                            }

                            Column {
                                anchors { left: parent.left; right: scoreText.left; verticalCenter: parent.verticalCenter }
                                anchors.leftMargin: 46
                                anchors.rightMargin: 12
                                spacing: 3
                                Text {
                                    width: parent.width
                                    text: modelData.name || modelData.symbol
                                    color: root.foregroundColor
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.market + " · " + modelData.symbol + " · "
                                        + StockService.signed(modelData.changePct, 2) + "%"
                                    color: root.secondaryColor
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 9
                                    elide: Text.ElideRight
                                }
                            }

                            Text {
                                id: scoreText
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                anchors.rightMargin: 12
                                width: 116
                                text: root.t("AI %1% · Score %2", [
                                    Number(modelData.aiConfidence || 0),
                                    Number(modelData.recommendationScore || 0)
                                ])
                                color: modelData.recommended ? root.positiveColor : root.secondaryColor
                                font.family: "SF Pro Display"
                                font.pixelSize: 9
                                font.weight: Font.DemiBold
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideLeft
                            }

                            HoverHandler { id: candidateHover }
                            TapHandler {
                                id: candidateTap
                                enabled: candidateCard.selectable
                                onTapped: root.toggleAutopilotCandidate(candidateCard.modelData.key)
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: candidateList.count === 0
                            width: parent.width - 36
                            text: root.autopilotBusy
                                ? root.t("Checking news, trends, and candidates…")
                                : root.t("Press Check Now to find candidate stocks.")
                            color: root.secondaryColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                Rectangle {
                    width: parent.width - (parent.width - parent.spacing) * 0.64 - parent.spacing
                    height: parent.height
                    radius: 13
                    color: root.raisedColor

                    Text {
                        id: detailTitle
                        anchors { left: parent.left; top: parent.top }
                        anchors.leftMargin: 14
                        anchors.topMargin: 12
                        text: root.t("Status Details")
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Flickable {
                        id: detailScroll
                        anchors { left: parent.left; right: parent.right; top: detailTitle.bottom; bottom: safetyButton.top }
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 10
                        anchors.bottomMargin: 9
                        contentWidth: width
                        contentHeight: detailColumn.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        Column {
                            id: detailColumn
                            width: detailScroll.width
                            spacing: 8

                            DetailRow {
                                label: root.t("State")
                                value: root.autopilotPhaseLabel()
                                valueColor: root.autopilotPhaseColor()
                            }
                            DetailRow {
                                label: root.t("Stock Selection")
                                value: sheet.automaticSelection ? root.t("Automatic")
                                    : root.t("%1 selected", [Number(sheet.state.selectedCount || 0)])
                            }
                            DetailRow {
                                label: root.t("Last Check")
                                value: root.autopilotTime(sheet.state.lastScanAt)
                            }
                            DetailRow {
                                label: root.t("Leading Sectors")
                                value: sheet.hotSectors !== "" ? sheet.hotSectors : root.t("Checking…")
                            }
                            DetailRow {
                                label: root.t("Background Check")
                                value: sheet.background.enabled ? root.t("On") : root.t("Off")
                                valueColor: sheet.background.enabled ? root.positiveColor : "#ff9f0a"
                            }

                            Rectangle {
                                width: parent.width
                                height: detailText.implicitHeight + 22
                                radius: 10
                                color: root.backgroundColor
                                Text {
                                    id: detailText
                                    anchors.fill: parent
                                    anchors.margins: 11
                                    text: sheet.operationDetail !== ""
                                        ? sheet.operationDetail : root.autopilotSimpleStatus()
                                    color: root.foregroundColor
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                    wrapMode: Text.WordWrap
                                }
                            }

                            Text {
                                width: parent.width
                                visible: sheet.failedGateDetail !== ""
                                text: root.t("Checks holding this trade · %1", [sheet.failedGateDetail])
                                color: "#ff9f0a"
                                font.family: "SF Pro Display"
                                font.pixelSize: 9
                                wrapMode: Text.WordWrap
                            }

                            DetailRow {
                                label: root.t("Loss Limit")
                                value: Number(sheet.policy.maxPositionLossPercent || 3).toFixed(1) + "%"
                            }
                            DetailRow {
                                label: root.t("Risk Per Trade")
                                value: Number(sheet.policy.maxRiskPerTradePercent || 0.25).toFixed(2) + "%"
                            }
                            DetailRow {
                                label: root.t("System Check")
                                value: sheet.audit.healthy === false ? root.t("Needs attention")
                                    : (sheet.audit.healthy === true ? root.t("Good") : root.t("Checking…"))
                                valueColor: sheet.audit.healthy === false ? "#ff9f0a"
                                    : (sheet.audit.healthy === true ? root.positiveColor : root.secondaryColor)
                            }
                        }
                    }

                    ActionButton {
                        id: safetyButton
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.bottomMargin: 11
                        height: 34
                        label: root.t("Safety & Limits")
                        accent: root.foregroundColor
                        onTriggered: {
                            root.closeAutopilot()
                            root.quantTab = "automation"
                            root.openForecasts()
                        }
                    }
                }
            }

            Item {
                id: advancedFooter
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                anchors.leftMargin: 22
                anchors.rightMargin: 22
                anchors.bottomMargin: 9
                height: 22

                Text {
                    anchors.fill: parent
                    text: root.t(root.liveAutopilotContext
                        ? "Real orders can lose money. Every order is checked before it is sent."
                        : "Paper results can differ from real trading. Returns are not guaranteed.")
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 9
                    elide: Text.ElideRight
                }
            }
        }
    }

    component MetricCard: Rectangle {
        property string label: ""
        property string value: "—"
        property color valueColor: root.foregroundColor
        height: 90
        radius: 14
        color: root.raisedColor

        Text {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 14
            text: parent.label
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: Font.Medium
            elide: Text.ElideRight
        }

        Text {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.bottomMargin: 14
            text: parent.value
            color: parent.valueColor
            font.family: "SF Pro Display"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            font.letterSpacing: -0.2
            elide: Text.ElideRight
        }
    }

    component DetailRow: Item {
        property string label: ""
        property string value: "—"
        property color valueColor: root.foregroundColor
        width: parent ? parent.width : 0
        height: 28

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 9
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width * 0.58
            text: parent.value
            color: parent.valueColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
        }
    }

    component ActionButton: Rectangle {
        id: actionButton
        property string label: ""
        property color accent: "#0a84ff"
        property bool filled: false
        signal triggered()
        height: 32
        radius: 10
        color: filled ? accent
            : (actionHover.hovered ? Qt.rgba(accent.r, accent.g, accent.b, 0.16) : root.separatorColor)
        opacity: enabled ? 1 : 0.38
        scale: actionArea.pressed ? ThemeService.pressScale : 1
        Behavior on opacity { AppleSpring { spring: 20 } }
        Behavior on scale { AppleSpring { spring: 20 } }

        Text {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            text: actionButton.label
            color: actionButton.filled ? "#ffffff" : actionButton.accent
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        HoverHandler { id: actionHover }
        MouseArea {
            id: actionArea
            anchors.fill: parent
            enabled: actionButton.enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: actionButton.triggered()
        }
    }
}
