import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic

Rectangle {
    required property var root
    id: portfolioPanel
    anchors.fill: parent
    anchors.topMargin: -4
    visible: opacity > 0.002
    opacity: root.portfolioVisible ? 1 : 0
    scale: root.portfolioVisible ? 1 : 0.96
    radius: 14
    color: root.dark ? "#2c2c2e" : "#ffffff"
    border.color: root.separatorColor
    border.width: 1
    z: 30
    Behavior on opacity { AppleSpring { spring: 18 } }
    Behavior on scale { AppleSpring { spring: 18 } }
    MouseArea { anchors.fill: parent }

    Text {
        id: portfolioTitle
        anchors { left: parent.left; top: parent.top }
        anchors.leftMargin: 16
        anchors.topMargin: 12
        text: root.kisEnvironment === "paper" ? root.t("Paper Portfolio") : root.t("Production Portfolio")
        color: root.foregroundColor
        font.family: "SF Pro Display"
        font.pixelSize: 15
        font.weight: Font.DemiBold
        font.letterSpacing: -0.2
    }
    Text {
        anchors.left: portfolioTitle.right
        anchors.leftMargin: 8
        anchors.verticalCenter: portfolioTitle.verticalCenter
        text: root.accountBusy ? root.t("Updating…")
            : root.t("%1 holdings", [(root.accountState.holdings || []).length])
        color: root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 10
    }
    Rectangle {
        anchors { right: parent.right; top: parent.top }
        anchors.rightMargin: 10
        anchors.topMargin: 8
        width: 30
        height: 30
        radius: 9
        color: closePortfolioHover.hovered ? root.raisedColor : root.separatorColor
        scale: closePortfolioArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            anchors.centerIn: parent
            text: "✕"
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
        HoverHandler { id: closePortfolioHover }
        MouseArea {
            id: closePortfolioArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: root.closePortfolio()
        }
    }

    Row {
        id: portfolioSummary
        anchors { left: parent.left; right: parent.right; top: portfolioTitle.bottom }
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        anchors.topMargin: 8
        height: 42
        spacing: 12
        PortfolioMetric {
            width: (parent.width - 36) / 4
            title: root.t("TOTAL")
            value: StockService.money(root.accountState.totalEvaluation, root.accountState.currency || "KRW")
        }
        PortfolioMetric {
            width: (parent.width - 36) / 4
            title: root.t("CASH")
            value: StockService.money(root.accountState.cash, root.accountState.currency || "KRW")
        }
        PortfolioMetric {
            width: (parent.width - 36) / 4
            title: root.t("STOCKS")
            value: StockService.money(root.accountState.stockEvaluation, root.accountState.currency || "KRW")
        }
        PortfolioMetric {
            width: (parent.width - 36) / 4
            title: root.t("P&L")
            value: StockService.signedMoney(root.accountState.profitLoss, root.accountState.currency || "KRW")
            valueColor: Number(root.accountState.profitLoss || 0) >= 0 ? root.positiveColor : root.negativeColor
        }
    }

    ListView {
        id: holdingsList
        anchors { left: parent.left; right: parent.right; top: portfolioSummary.bottom; bottom: parent.bottom }
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 5
        anchors.bottomMargin: 9
        clip: true
        spacing: 2
        model: root.accountState.holdings || []
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
        property var _ks: ({})
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                portfolioGlide.stop()
                if (Kinetic.onWheel(holdingsList, event, holdingsList._ks, { gain: 72 }))
                    portfolioEndTimer.restart()
            }
        }
        Timer {
            id: portfolioEndTimer
            interval: 48
            onTriggered: {
                let glide = Kinetic.fling(holdingsList, holdingsList._ks, {})
                if (glide) {
                    portfolioGlide.from = glide.from
                    portfolioGlide.to = glide.to
                    portfolioGlide.restart()
                }
            }
        }
        SpringAnimation {
            id: portfolioGlide
            target: holdingsList
            property: "contentY"
            spring: 18
            damping: ThemeService.momentumDamping
            epsilon: 0.25
        }
        delegate: Rectangle {
            required property var modelData
            width: holdingsList.width
            height: 44
            radius: 10
            color: holdingHover.hovered ? root.raisedColor : "transparent"
            scale: holdingArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 18 } }
            Row {
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                spacing: 10
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 112 - 108 - 20
                    spacing: 1
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
                        text: root.t("%1 · %2 shares · Avg %3", [(modelData.market || root.market) + " · " + modelData.symbol, modelData.quantity,
                            StockService.money(modelData.averagePrice, modelData.currency || root.accountState.currency || "KRW")])
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 112
                    text: StockService.money(modelData.evaluation, modelData.currency || root.accountState.currency || "KRW")
                    color: root.foregroundColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    horizontalAlignment: Text.AlignRight
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 108
                    spacing: 1
                    Text {
                        anchors.right: parent.right
                        text: StockService.signedMoney(modelData.profitLoss, modelData.currency || root.accountState.currency || "KRW")
                        color: Number(modelData.profitLoss || 0) >= 0 ? root.positiveColor : root.negativeColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.right: parent.right
                        text: StockService.signed(modelData.profitRate, 2) + "%"
                        color: Number(modelData.profitLoss || 0) >= 0 ? root.positiveColor : root.negativeColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                    }
                }
            }
            HoverHandler { id: holdingHover }
            MouseArea {
                id: holdingArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.selectHolding(modelData)
            }
        }
        Text {
            anchors.centerIn: parent
            visible: holdingsList.count === 0
            text: root.accountError !== "" ? root.t(root.accountError)
                : (root.accountBusy ? root.t("Loading portfolio…") : root.t("No holdings in this account."))
            color: root.accountError !== "" ? root.negativeColor : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
    }

    component PortfolioMetric: Column {
        property string title: ""
        property string value: ""
        property color valueColor: root.foregroundColor
        spacing: 2
        Text {
            text: parent.title
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 0.35
        }
        Text {
            width: parent.width
            text: parent.value
            color: parent.valueColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }
}
