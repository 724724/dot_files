import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic

Rectangle {
    id: ordersPanel
    required property var root
    readonly property string cancelConfirmation: cancelLiveConfirmField.text.trim()

    function clearCancelConfirmation() {
        cancelLiveConfirmField.text = ""
    }
    anchors.fill: parent
    anchors.topMargin: -4
    visible: opacity > 0.002
    opacity: root.ordersVisible ? 1 : 0
    scale: root.ordersVisible ? 1 : 0.96
    radius: 14
    color: root.dark ? "#2c2c2e" : "#ffffff"
    border.color: root.separatorColor
    border.width: 1
    z: 30
    Behavior on opacity { AppleSpring { spring: 18 } }
    Behavior on scale { AppleSpring { spring: 18 } }
    MouseArea { anchors.fill: parent }

    Item {
        anchors.fill: parent
        visible: opacity > 0.002
        opacity: root.cancelReviewVisible ? 0 : 1
        enabled: !root.cancelReviewVisible
        Behavior on opacity { AppleSpring { spring: 18 } }

        Text {
            id: ordersTitle
            anchors { left: parent.left; top: parent.top }
            anchors.leftMargin: 16
            anchors.topMargin: 12
            text: root.kisEnvironment === "paper" ? root.t("Paper Orders") : root.t("Production Orders")
            color: root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            font.letterSpacing: -0.2
        }
        Text {
            anchors.left: ordersTitle.right
            anchors.leftMargin: 8
            anchors.verticalCenter: ordersTitle.verticalCenter
            text: root.orderHistoryBusy ? root.t("Updating…")
                : root.t("%1 cancelable", [root.pendingOrderCount])
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
        }
        Rectangle {
            anchors.right: closeOrdersButton.left
            anchors.rightMargin: 8
            anchors.verticalCenter: closeOrdersButton.verticalCenter
            width: 72
            height: 28
            radius: 9
            color: activityButtonHover.hovered ? root.raisedColor : root.separatorColor
            scale: activityButtonArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: root.t("Activity")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            HoverHandler { id: activityButtonHover }
            MouseArea {
                id: activityButtonArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.openActivity()
            }
        }
        Rectangle {
            id: closeOrdersButton
            anchors { right: parent.right; top: parent.top }
            anchors.rightMargin: 10
            anchors.topMargin: 8
            width: 30
            height: 30
            radius: 9
            color: closeOrdersHover.hovered ? root.raisedColor : root.separatorColor
            scale: closeOrdersArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 18 } }
            Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
            HoverHandler { id: closeOrdersHover }
            MouseArea {
                id: closeOrdersArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.closeOrders()
            }
        }

        Column {
            anchors { left: parent.left; right: parent.right; top: ordersTitle.bottom; bottom: parent.bottom }
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            anchors.topMargin: 8
            anchors.bottomMargin: 10
            spacing: 6

            Repeater {
                model: root.orderHistory.slice(0, 2)
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 44
                    radius: 10
                    color: root.dark ? "#3a3a3c" : "#f1f1f4"
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 7
                        spacing: 9
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 42
                            height: 24
                            radius: 7
                            color: modelData.side === "buy" ? root.positiveColor : root.negativeColor
                            Text {
                                anchors.centerIn: parent
                                text: modelData.side === "buy" ? root.t("Buy") : root.t("Sell")
                                color: "#ffffff"
                                font.family: "SF Pro Display"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 42 - 9 - 118 - 9 - 64 - 9
                            spacing: 1
                            Text {
                                width: parent.width
                                text: (modelData.name || modelData.symbol) + "  ·  " + modelData.filledQuantity + "/" + modelData.quantity
                                color: root.foregroundColor
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: "#" + modelData.orderNumber + (Number(modelData.price) > 0 ? "  ·  "
                                    + StockService.money(modelData.price, modelData.currency || root.snapshot.currency || "KRW") : "")
                                color: root.secondaryColor
                                font.family: "SF Pro Display"
                                font.pixelSize: 9
                                elide: Text.ElideRight
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 118
                            text: root.t(root.orderStateLabel(modelData.state))
                            color: modelData.canCancel ? "#0a84ff" : root.secondaryColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 64
                            height: 28
                            radius: 8
                            color: cancelOrderHover.hovered && modelData.canCancel ? Qt.rgba(1, 0.27, 0.23, 0.20) : root.separatorColor
                            opacity: modelData.canCancel && (root.kisEnvironment === "paper" || root.productionTradingEnabled) ? 1 : 0.38
                            scale: cancelOrderArea.pressed ? ThemeService.pressScale : 1
                            Behavior on scale { AppleSpring { spring: 18 } }
                            Text {
                                anchors.centerIn: parent
                                text: root.t("Cancel")
                                color: modelData.canCancel ? root.negativeColor : root.secondaryColor
                                font.family: "SF Pro Display"
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                            }
                            HoverHandler { id: cancelOrderHover }
                            MouseArea {
                                id: cancelOrderArea
                                anchors.fill: parent
                                enabled: modelData.canCancel && (root.kisEnvironment === "paper" || root.productionTradingEnabled)
                                cursorShape: Qt.PointingHandCursor
                                onPressed: root.requestCancel(modelData)
                            }
                        }
                    }
                }
            }

            Text {
                visible: root.orderHistory.length === 0 || root.orderHistoryError !== ""
                width: parent.width
                text: root.orderHistoryError !== "" ? root.t(root.orderHistoryError)
                    : (root.orderHistoryBusy ? root.t("Loading recent orders…")
                        : root.t("No recent orders for this symbol."))
                color: root.orderHistoryError !== "" ? root.negativeColor : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Item {
        anchors.fill: parent
        visible: opacity > 0.002
        opacity: root.cancelReviewVisible ? 1 : 0
        enabled: root.cancelReviewVisible
        Behavior on opacity { AppleSpring { spring: 18 } }
        Column {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            anchors.margins: 18
            spacing: 6
            Text {
                text: root.t("Cancel Remaining Order")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 16
                font.weight: Font.DemiBold
                font.letterSpacing: -0.2
            }
            Text {
                text: root.cancelTarget.side === "sell"
                    ? root.t("Sell %1 %2", [Number(root.cancelTarget.cancelQuantity || 0),
                        root.cancelTarget.name || root.cancelTarget.symbol || ""])
                    : root.t("Buy %1 %2", [Number(root.cancelTarget.cancelQuantity || 0),
                        root.cancelTarget.name || root.cancelTarget.symbol || ""])
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 12
            }
            Text {
                text: root.orderHistoryError !== "" ? root.t(root.orderHistoryError)
                    : (root.kisEnvironment === "prod"
                        ? root.t("Type LIVE to cancel the unfilled quantity in your production account.")
                        : root.t("Only the unfilled quantity will be canceled in your KIS mock account."))
                color: root.orderHistoryError !== "" ? root.negativeColor : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
            Rectangle {
                visible: root.kisEnvironment === "prod"
                width: 190
                height: visible ? 30 : 0
                radius: 8
                color: root.dark ? "#3a3a3c" : "#f1f1f4"
                border.color: cancelLiveConfirmField.activeFocus ? root.negativeColor : root.separatorColor
                border.width: 1
                TextField {
                    id: cancelLiveConfirmField
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
                label: root.t("Keep Order")
                filled: false
                enabled: !root.cancelRunning
                onTriggered: {
                    root.cancelReviewVisible = false
                    root.orderHistoryError = ""
                    cancelLiveConfirmField.text = ""
                }
            }
            SheetButton {
                label: root.cancelRunning ? root.t("Canceling…") : root.t("Cancel Remaining")
                filled: true
                destructive: true
                enabled: !root.cancelRunning && (root.kisEnvironment !== "prod" || cancelLiveConfirmField.text.trim() === "LIVE")
                onTriggered: root.confirmCancel()
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
