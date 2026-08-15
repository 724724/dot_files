import QtQuick
import QtQuick.Controls
import ".."

Item {
    id: tradePanel
    required property var root
    readonly property int quantity: Math.max(1, parseInt(quantityField.text || "1") || 1)
    readonly property real orderPrice: root.orderType === "market"
        ? Number(root.snapshot.price)
        : Math.max(0, Number(limitField.text))
    function syncLimitPrice(value) {
        if (root.orderType === "limit" && limitField.text === "")
            limitField.text = value
    }

    function triggerPrimaryAction() {
        if (root.dataMode !== "kis") {
            root.openAutopilot()
            return
        }
        root.setTradingMode("automatic")
        root.prepareAutomaticAutopilotSelection()
        if (root.autopilotRunning) {
            root.stopAutopilot()
        } else if (root.autopilotNeedsRetry() && !root.autopilotHardStop()) {
            root.retryAutopilot()
        } else if (root.autopilotHalted || root.autopilotBlockingReason() !== ""
                || !root.autopilotCanStart) {
            root.openAutopilot()
        } else {
            root.startAutopilot(false, true)
        }
    }

    opacity: root.selectedTab === "trade" ? 1 : 0
    visible: opacity > 0.002
    enabled: root.selectedTab === "trade"
    Behavior on opacity { AppleSpring { spring: 18 } }

    Row {
        id: tradeFields
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 68
        spacing: 10
        visible: opacity > 0.002
        enabled: !root.autoTradingMode
        opacity: root.autoTradingMode ? 0 : 1
        Behavior on opacity { AppleSpring { spring: 22 } }

        InputBlock {
            width: 128
            title: root.t("SIDE")
            contentItem: Rectangle {
                anchors.fill: parent
                color: "transparent"
                Row {
                    anchors.fill: parent
                    SideChoice {
                        width: parent.width / 2
                        height: parent.height
                        label: root.t("Buy")
                        selected: root.orderSide === "buy"
                        accent: root.positiveColor
                        onTriggered: root.orderSide = "buy"
                    }
                    SideChoice {
                        width: parent.width / 2
                        height: parent.height
                        label: root.t("Sell")
                        selected: root.orderSide === "sell"
                        accent: root.negativeColor
                        onTriggered: root.orderSide = "sell"
                    }
                }
            }
        }

        InputBlock {
            width: 112
            title: root.t("QUANTITY")
            contentItem: TextField {
                id: quantityField
                anchors.fill: parent
                text: "1"
                color: root.foregroundColor
                selectionColor: "#0a84ff"
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                font.family: "SF Pro Display"
                font.pixelSize: 13
                validator: IntValidator { bottom: 1; top: 999999 }
                background: null
            }
        }

        InputBlock {
            width: 128
            title: root.t("ORDER TYPE")
            contentItem: Rectangle {
                anchors.fill: parent
                color: "transparent"
                Row {
                    anchors.fill: parent
                    TypeChoice {
                        width: parent.width / 2
                        height: parent.height
                        label: root.t("Market Order")
                        selected: root.orderType === "market"
                        enabled: root.market === "KRX"
                        opacity: enabled ? 1 : 0.35
                        onTriggered: root.orderType = "market"
                    }
                    TypeChoice {
                        width: parent.width / 2
                        height: parent.height
                        label: root.t("Limit")
                        selected: root.orderType === "limit"
                        onTriggered: {
                            root.orderType = "limit"
                            if (limitField.text === "") limitField.text = StockService.price(root.snapshot.price, root.snapshot.currency)
                        }
                    }
                }
            }
        }

        InputBlock {
            width: 130
            title: root.t("LIMIT PRICE")
            enabled: root.orderType === "limit"
            opacity: enabled ? 1 : 0.42
            Behavior on opacity { AppleSpring { spring: 18 } }
            contentItem: TextField {
                id: limitField
                anchors.fill: parent
                color: root.foregroundColor
                selectionColor: "#0a84ff"
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                font.family: "SF Pro Display"
                font.pixelSize: 13
                validator: DoubleValidator { bottom: 0; decimals: 2 }
                background: null
                onEditingFinished: root.scheduleAccount()
            }
        }
    }

    Rectangle {
        id: autoFields
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 68
        radius: 12
        color: root.raisedColor
        border.color: root.separatorColor
        border.width: 1
        visible: opacity > 0.002
        enabled: root.autoTradingMode
        opacity: root.autoTradingMode ? 1 : 0
        scale: autoFieldsArea.pressed ? ThemeService.pressScale : 1
        Behavior on opacity { AppleSpring { spring: 22 } }
        Behavior on scale { AppleSpring { spring: 18 } }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34
            radius: 10
            color: Qt.rgba(0.04, 0.52, 1, root.dark ? 0.18 : 0.11)
            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: root.autopilotPhaseColor()
            }
        }

        Column {
            anchors.left: parent.left
            anchors.leftMargin: 60
            anchors.right: phaseColumn.left
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text {
                width: parent.width
                text: root.t("Trading Candidates")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 13
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.t("%1 selected", [Number(root.autopilotState.selectedCount || 0)])
                    + " · " + root.t(root.autopilotState.automaticSelection !== false
                        ? "AI Candidate Selection" : "Manual Candidate Selection")
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
        }

        Column {
            id: phaseColumn
            anchors.right: chevron.left
            anchors.rightMargin: 9
            anchors.verticalCenter: parent.verticalCenter
            width: 126
            spacing: 3
            Text {
                width: parent.width
                text: root.autopilotPhaseLabel()
                color: root.autopilotPhaseColor()
                font.family: "SF Pro Display"
                font.pixelSize: 11
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: root.t("Auto Trading Settings")
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 9
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }

        Text {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: 15
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 24
        }

        MouseArea {
            id: autoFieldsArea
            anchors.fill: parent
            enabled: parent.enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: root.openAutopilot()
        }
    }

    Row {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 44
        spacing: 12
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - reviewButton.width - parent.spacing
            spacing: 2
            Text {
                text: root.dataMode === "kis"
                    ? root.t(root.liveAutopilotContext ? "KIS LIVE AUTO" : "KIS PAPER AUTO")
                    : root.t("AUTOMATIC TRADING")
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 9
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
            }
            Text {
                text: root.dataMode === "kis" ? root.autopilotPhaseLabel()
                    : root.t("Connect KIS to start")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                font.letterSpacing: -0.25
            }
            Text {
                visible: true
                text: root.dataMode !== "kis"
                    ? root.t("Select KIS Live as the data source in Settings.")
                    : (root.autopilotBlockingReason() !== "" ? root.autopilotBlockingReason()
                        : root.autopilotStatusDetail())
                color: root.autopilotBlockingReason() !== ""
                    ? root.negativeColor : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                elide: Text.ElideRight
                width: parent.width
            }
        }
        Rectangle {
            id: reviewButton
            readonly property bool actionReady: !root.autopilotBusy
                && !root.autopilotEmergencyBusy
            width: 172
            height: 40
            radius: 11
            color: root.autopilotHardStop() ? root.negativeColor
                : (root.autopilotRunning ? "#ff9f0a"
                    : (root.autopilotNeedsRetry() && !root.autopilotHalted ? "#ff9f0a"
                    : (root.liveAutopilotContext ? root.negativeColor : "#0a84ff")))
            opacity: actionReady ? 1 : 0.42
            scale: reviewArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 18 } }
            Text {
                anchors.centerIn: parent
                text: root.autopilotHardStop() ? root.t("Review Safety Halt")
                    : (root.autopilotHalted ? root.t(root.liveAutopilotContext
                        ? "Start Live Auto Trading" : "Start Automatic Trading")
                    : (root.autopilotNeedsRetry() ? root.t("Try Again")
                    : (root.autopilotRunning
                        ? root.t(root.autopilotState.environment === "prod"
                            ? "Stop Live Auto Trading" : "Stop Automatic Trading")
                        : (root.autopilotBusy ? root.t("Starting…")
                            : (root.dataMode !== "kis"
                                ? root.t("Set Up Automatic Trading")
                                : root.t(root.liveAutopilotContext
                                    ? "Start Live Auto Trading" : "Start Automatic Trading"))))))
                color: "#ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: reviewArea
                anchors.fill: parent
                enabled: reviewButton.actionReady
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onPressed: tradePanel.triggerPrimaryAction()
            }
        }
    }

    component InputBlock: Column {
        property string title: ""
        property alias contentItem: fieldHost.data
        spacing: 5
        Text {
            text: parent.title
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 0.35
        }
        Rectangle {
            id: fieldHost
            width: parent.width
            height: 36
            radius: 9
            color: root.raisedColor
            border.color: root.separatorColor
            border.width: 1
            clip: true
        }
    }

    component SideChoice: Item {
        id: sideChoice
        property string label: ""
        property bool selected: false
        property color accent: root.positiveColor
        signal triggered()
        scale: sideArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 7
            color: sideChoice.selected ? sideChoice.accent : "transparent"
        }
        Text {
            anchors.centerIn: parent
            text: sideChoice.label
            color: sideChoice.selected ? "#ffffff" : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: sideArea
            anchors.fill: parent
            enabled: sideChoice.enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: sideChoice.triggered()
        }
    }

    component TypeChoice: Item {
        id: typeChoice
        property string label: ""
        property bool selected: false
        signal triggered()
        scale: typeArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 7
            color: typeChoice.selected ? (root.dark ? "#4a4a4d" : "#ffffff") : "transparent"
        }
        Text {
            anchors.centerIn: parent
            text: typeChoice.label
            color: typeChoice.selected ? root.foregroundColor : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: typeChoice.selected ? Font.DemiBold : Font.Medium
        }
        MouseArea {
            id: typeArea
            anchors.fill: parent
            enabled: typeChoice.enabled
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: typeChoice.triggered()
        }
    }
}
