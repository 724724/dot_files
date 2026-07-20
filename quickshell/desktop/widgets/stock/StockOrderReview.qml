import QtQuick
import QtQuick.Controls
import ".."

Rectangle {
    id: reviewPanel
    required property var root
    readonly property string confirmation: liveConfirmField.text.trim()

    function clearConfirmation() {
        liveConfirmField.text = ""
    }

    anchors.fill: parent
    anchors.topMargin: -4
    visible: opacity > 0.002
    opacity: root.reviewVisible ? 1 : 0
    scale: root.reviewVisible ? 1 : 0.96
    radius: 14
    color: root.dark ? "#2c2c2e" : "#ffffff"
    border.color: root.separatorColor
    border.width: 1
    z: 20
    Behavior on opacity { AppleSpring { spring: 18 } }
    Behavior on scale { AppleSpring { spring: 18 } }
    MouseArea { anchors.fill: parent }

    Column {
        anchors { left: parent.left; right: parent.right; top: parent.top }
        anchors.margins: 18
        spacing: 6
        Text {
            text: root.demoOrderReady ? root.t("Review Local Preview")
                : (root.kisEnvironment === "prod" ? root.t("Review Production Order")
                    : root.t("Review KIS Paper Order"))
            color: root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 16
            font.weight: Font.DemiBold
            font.letterSpacing: -0.2
        }
        Text {
            text: root.reviewOrder.side === "buy"
                ? root.t("Buy %1 %2 at %3", [Number(root.reviewOrder.quantity || 0),
                    root.reviewOrder.symbol || root.symbol,
                    root.reviewOrder.orderType === "market" ? root.t("market price")
                        : StockService.money(root.reviewOrder.price, root.reviewOrder.currency || root.snapshot.currency)])
                : root.t("Sell %1 %2 at %3", [Number(root.reviewOrder.quantity || 0),
                    root.reviewOrder.symbol || root.symbol,
                    root.reviewOrder.orderType === "market" ? root.t("market price")
                        : StockService.money(root.reviewOrder.price, root.reviewOrder.currency || root.snapshot.currency)])
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 12
        }
        Text {
            width: parent.width
            text: root.preflightStatusText()
            color: root.orderError !== "" || root.preflightError !== "" ? root.negativeColor
                : (root.preflightReady ? root.positiveColor : root.secondaryColor)
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        Row {
            width: parent.width
            height: 42
            spacing: 8
            PreflightMetric {
                width: (parent.width - 16) / 3
                title: root.t("ESTIMATED")
                value: StockService.money((root.preflightState.risk || {}).estimatedNotional
                    || root.reviewOrder.estimatedTotal, root.reviewOrder.currency || root.snapshot.currency)
            }
            PreflightMetric {
                width: (parent.width - 16) / 3
                title: root.t("AVAILABLE")
                value: root.t("%1 shares", [Number(root.preflightState.availableQuantity || 0)])
            }
            PreflightMetric {
                width: (parent.width - 16) / 3
                title: root.t("POSITION AFTER")
                value: Number((root.preflightState.risk || {}).projectedPositionPercent || 0).toFixed(2) + "%"
            }
        }
        Rectangle {
            visible: root.kisEnvironment === "prod" && !root.demoOrderReady
            width: 190
            height: visible ? 30 : 0
            radius: 8
            color: root.dark ? "#3a3a3c" : "#f1f1f4"
            border.color: liveConfirmField.activeFocus ? root.negativeColor : root.separatorColor
            border.width: 1
            TextField {
                id: liveConfirmField
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                placeholderText: "LIVE"
                placeholderTextColor: root.secondaryColor
                color: root.foregroundColor
                selectionColor: root.negativeColor
                background: null
                font.family: "SF Pro Display"
                font.pixelSize: 11
                verticalAlignment: TextInput.AlignVCenter
            }
        }
    }

    Row {
        anchors { right: parent.right; bottom: parent.bottom }
        anchors.margins: 16
        spacing: 8
        SheetButton {
            label: root.t("Cancel")
            filled: false
            enabled: !root.orderRunning
            onTriggered: {
                root.closeOrderReview()
            }
        }
        SheetButton {
            label: root.orderRunning ? root.t("Submitting…") : (root.demoOrderReady ? root.t("Confirm Preview")
                : (root.kisEnvironment === "prod" ? root.t("Place Live Order") : root.t("Confirm Paper")))
            filled: true
            destructive: root.kisEnvironment === "prod" && !root.demoOrderReady
            enabled: !root.orderRunning && root.preflightReady
                && (root.demoOrderReady || root.kisEnvironment !== "prod" || liveConfirmField.text.trim() === "LIVE")
            onTriggered: root.submitOrder()
        }
    }

    component PreflightMetric: Rectangle {
        property string title: ""
        property string value: ""
        height: 42
        radius: 9
        color: root.dark ? "#3a3a3c" : "#f1f1f4"
        Column {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 2
            Text {
                width: parent.width
                text: parent.parent.title
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 8
                font.weight: Font.DemiBold
                font.letterSpacing: 0.35
                elide: Text.ElideRight
            }
            Text {
                width: parent.width
                text: parent.parent.value
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }
    }

    component SheetButton: Rectangle {
        id: sheetButton
        property string label: ""
        property bool filled: false
        property bool destructive: false
        signal triggered()
        width: filled ? 126 : 76
        height: 34
        radius: 9
        color: destructive ? root.negativeColor : (filled ? "#0a84ff" : root.separatorColor)
        opacity: enabled ? 1 : 0.48
        Behavior on opacity { AppleSpring { spring: 18 } }
        scale: sheetArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            anchors.centerIn: parent
            text: sheetButton.label
            color: sheetButton.filled || sheetButton.destructive ? "#ffffff" : root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: sheetArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onReleased: if (containsMouse) sheetButton.triggered()
        }
    }
}
