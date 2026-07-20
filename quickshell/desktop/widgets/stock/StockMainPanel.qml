import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic
import "." as Stock

Item {
    id: lowerPanel
    required property var root
    readonly property int quantity: tradePanel.quantity
    readonly property real orderPrice: tradePanel.orderPrice
    readonly property string liveConfirmation: orderReview.confirmation
    readonly property string cancelConfirmation: ordersPanel.cancelConfirmation

    function syncLimitPrice(value) {
        tradePanel.syncLimitPrice(value)
    }

    function clearLiveConfirmation() {
        orderReview.clearConfirmation()
    }

    function clearCancelConfirmation() {
        ordersPanel.clearCancelConfirmation()
    }

    Rectangle {
        id: tabBar
        anchors.left: parent.left
        anchors.top: parent.top
        width: 188
        height: 34
        radius: 10
        color: root.dark ? "#2c2c2e" : "#e9e9ee"
        Rectangle {
            x: root.selectedTab === "trade" ? 3 : parent.width / 2
            y: 3
            width: parent.width / 2 - 3
            height: parent.height - 6
            radius: 8
            color: root.dark ? "#4a4a4d" : "#ffffff"
            Behavior on x { AppleSpring { spring: 18 } }
        }
        TabChoice {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width / 2
            label: root.t("Trade")
            selected: root.selectedTab === "trade"
            onTriggered: root.selectedTab = "trade"
        }
        TabChoice {
            anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
            width: parent.width / 2
            label: root.t("AI Insight")
            selected: root.selectedTab === "ai"
            onTriggered: root.selectedTab = "ai"
        }
    }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: tabBar.verticalCenter
        width: parent.width - tabBar.width - 16
        height: 30
        spacing: portfolioButton.visible ? 8 : 0
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - portfolioButton.width - ordersButton.width
                - (portfolioButton.visible ? parent.spacing * 2 : 0)
            text: root.selectedTab === "trade" ? (root.dataMode === "kis"
                ? (root.kisEnvironment === "prod" && !root.productionTradingEnabled ? root.t("KIS Production · Orders locked")
                : (root.accountState.status === "ok"
                    ? (root.orderSide === "buy" ? root.t("Buyable %1 · %2", [root.accountState.buyingQuantity,
                        StockService.money(root.accountState.buyingPower, "KRW")])
                        : root.t("Sellable %1 shares", [root.accountState.sellableQuantity]))
                    : root.orderStatusText()))
                : root.t("Buying power %1", [StockService.money(root.snapshot.buyingPower, root.snapshot.currency)]))
                : root.t(StockService.providerLabel(root.aiProvider)) + " · "
                  + root.t(StockService.profileLabel(root.analysisProfile))
                  + (root.analysisResult.cached ? " · " + root.t("Cached") : "")
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
        }
        Rectangle {
            id: portfolioButton
            visible: root.selectedTab === "trade" && root.dataMode === "kis"
            width: visible ? 82 : 0
            height: 28
            radius: 9
            color: portfolioHover.hovered ? root.raisedColor : root.separatorColor
            opacity: root.tradingConfigured ? 1 : 0.42
            scale: portfolioArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 18 } }
            Text {
                anchors.centerIn: parent
                text: root.t("Portfolio")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            HoverHandler { id: portfolioHover }
            MouseArea {
                id: portfolioArea
                anchors.fill: parent
                enabled: root.tradingConfigured
                cursorShape: Qt.PointingHandCursor
                onPressed: root.openPortfolio()
            }
        }
        Rectangle {
            id: ordersButton
            visible: root.selectedTab === "trade" && root.dataMode === "kis"
            width: visible ? 76 : 0
            height: 28
            radius: 9
            color: ordersHover.hovered ? root.raisedColor : root.separatorColor
            opacity: root.tradingConfigured ? 1 : 0.42
            scale: ordersArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 18 } }
            Text {
                anchors.centerIn: parent
                text: root.pendingOrderCount > 0
                    ? root.t("Orders · %1", [root.pendingOrderCount]) : root.t("Orders")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            HoverHandler { id: ordersHover }
            MouseArea {
                id: ordersArea
                anchors.fill: parent
                enabled: root.tradingConfigured
                cursorShape: Qt.PointingHandCursor
                onPressed: root.openOrders()
            }
        }
    }

    Stock.StockTradePanel {
        id: tradePanel
        root: lowerPanel.root
        anchors { left: parent.left; right: parent.right; top: tabBar.bottom; bottom: parent.bottom }
        anchors.topMargin: 14
    }

    Stock.StockAnalysisPanel {
        root: lowerPanel.root
        anchors { left: parent.left; right: parent.right; top: tabBar.bottom; bottom: parent.bottom }
        anchors.topMargin: 14
    }

    Stock.StockPortfolioSheet {
        root: lowerPanel.root
    }

    Stock.StockOrderReview {
        id: orderReview
        root: lowerPanel.root
    }

    Stock.StockOrdersSheet {
        id: ordersPanel
        root: lowerPanel.root
    }
    component TabChoice: Item {
        id: tabChoice
        property string label: ""
        property bool selected: false
        signal triggered()
        scale: tabArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            anchors.centerIn: parent
            text: tabChoice.label
            color: tabChoice.selected ? root.foregroundColor : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: tabChoice.selected ? Font.DemiBold : Font.Medium
        }
        MouseArea {
            id: tabArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: tabChoice.triggered()
        }
    }


}
