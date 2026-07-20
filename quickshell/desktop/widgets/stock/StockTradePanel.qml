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
    opacity: root.selectedTab === "trade" ? 1 : 0
    visible: opacity > 0.002
    enabled: root.selectedTab === "trade"
    Behavior on opacity { AppleSpring { spring: 18 } }

    Row {
        id: tradeFields
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 68
        spacing: 10

        InputBlock {
            width: 128
            title: root.t("SIDE")
            contentItem: Rectangle {
                color: "transparent"
                Row {
                    anchors.fill: parent
                    SideChoice {
                        width: parent.width / 2
                        label: root.t("Buy")
                        selected: root.orderSide === "buy"
                        accent: root.positiveColor
                        onTriggered: root.orderSide = "buy"
                    }
                    SideChoice {
                        width: parent.width / 2
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
                color: "transparent"
                Row {
                    anchors.fill: parent
                    TypeChoice {
                        width: parent.width / 2
                        label: root.t("Market Order")
                        selected: root.orderType === "market"
                        onTriggered: root.orderType = "market"
                    }
                    TypeChoice {
                        width: parent.width / 2
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

    Row {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 44
        spacing: 12
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - reviewButton.width - parent.spacing
            spacing: 2
            Text {
                text: root.t("ESTIMATED TOTAL")
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 9
                font.weight: Font.DemiBold
                font.letterSpacing: 0.4
            }
            Text {
                text: StockService.money(root.estimatedTotal, root.snapshot.currency)
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                font.letterSpacing: -0.25
            }
            Text {
                visible: root.orderMessage !== "" || root.orderError !== "" || !root.canReviewOrder
                text: root.orderError !== "" ? root.t(root.orderError)
                    : (root.orderMessage !== "" ? root.t(root.orderMessage) : root.orderStatusText())
                color: root.orderError !== "" || !root.quantityAvailable ? root.negativeColor : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                elide: Text.ElideRight
                width: parent.width
            }
        }
        Rectangle {
            id: reviewButton
            width: 172
            height: 40
            radius: 11
            color: root.orderSide === "buy" ? root.positiveColor : root.negativeColor
            opacity: root.canReviewOrder ? 1 : 0.42
            scale: reviewArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 18 } }
            Text {
                anchors.centerIn: parent
                text: root.dataMode === "kis" ? (root.kisEnvironment === "paper" ? root.t("Review KIS Paper")
                    : (root.productionTradingEnabled ? root.t("Review Live Order") : root.t("Production Locked")))
                    : root.t("Review Preview")
                color: "#ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: reviewArea
                anchors.fill: parent
                enabled: root.canReviewOrder
                cursorShape: Qt.PointingHandCursor
                onPressed: root.openOrderReview()
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
            cursorShape: Qt.PointingHandCursor
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
            cursorShape: Qt.PointingHandCursor
            onPressed: typeChoice.triggered()
        }
    }
}
