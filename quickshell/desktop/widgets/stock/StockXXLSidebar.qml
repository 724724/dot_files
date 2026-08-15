import ".."
import QtQuick

Item {
    id: sidebar

    required property var root
    readonly property var quotedItems: (root.watchlistState || {
    }).items || []
    readonly property var displayItems: quotedItems.length > 0 ? quotedItems : root.watchlist

    Row {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        Item {
            id: dashboardPane

            width: Math.round((parent.width - parent.spacing) * 0.42)
            height: parent.height

            Column {
                anchors.fill: parent
                spacing: 10

                Row {
                    width: parent.width
                    height: 26

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.t("Dashboard")
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        font.letterSpacing: -0.3
                    }

                    Item {
                        width: parent.width - parent.children[0].width - statusPill.width
                        height: 1
                    }

                    Rectangle {
                        id: statusPill

                        property bool expanded: false

                        anchors.verticalCenter: parent.verticalCenter
                        width: expanded ? marketChoices.width + 8 : statusLabel.implicitWidth + 18
                        height: 24
                        radius: 8
                        clip: true
                        color: statusPillHover.hovered || statusPill.expanded ? root.raisedColor : root.separatorColor
                        scale: statusPillArea.pressed ? ThemeService.pressScale : 1
                        Behavior on scale { AppleSpring { spring: 22 } }
                        Behavior on width { AppleSpring { spring: 22 } }

                        Timer {
                            id: marketPickerTimeout
                            interval: 5000
                            onTriggered: statusPill.expanded = false
                        }

                        Text {
                            id: statusLabel

                            anchors.centerIn: parent
                            visible: opacity > 0.02
                            opacity: statusPill.expanded ? 0 : 1
                            Behavior on opacity { AppleSpring { spring: 22 } }
                            text: root.t(StockService.marketLabel(root.market)) + " ›"
                            color: root.foregroundColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }

                        HoverHandler { id: statusPillHover }
                        MouseArea {
                            id: statusPillArea
                            anchors.fill: parent
                            visible: !statusPill.expanded
                            cursorShape: Qt.PointingHandCursor
                            onPressed: {
                                statusPill.expanded = true
                                marketPickerTimeout.restart()
                            }
                        }

                        Row {
                            id: marketChoices

                            anchors.centerIn: parent
                            spacing: 2
                            visible: opacity > 0.02
                            opacity: statusPill.expanded ? 1 : 0
                            Behavior on opacity { AppleSpring { spring: 22 } }

                            Repeater {
                                model: StockService.marketOptions
                                delegate: Rectangle {
                                    id: marketChoice

                                    required property var modelData
                                    readonly property bool selected: root.market === modelData.id

                                    width: marketChoiceLabel.implicitWidth + 14
                                    height: 20
                                    radius: 6
                                    color: selected ? (root.dark ? "#4a4a4d" : "#ffffff") : "transparent"

                                    Text {
                                        id: marketChoiceLabel

                                        anchors.centerIn: parent
                                        text: root.t(marketChoice.modelData.label)
                                        color: marketChoice.selected ? root.foregroundColor : root.secondaryColor
                                        font.family: "SF Pro Display"
                                        font.pixelSize: 9
                                        font.weight: marketChoice.selected ? Font.DemiBold : Font.Medium
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onPressed: {
                                            statusPill.expanded = false
                                            marketPickerTimeout.stop()
                                            root.selectMarket(marketChoice.modelData.id)
                                        }
                                    }
                                }
                            }
                        }

                    }

                }

                Rectangle {
                    width: parent.width
                    height: 124
                    radius: 13
                    color: accountHover.hovered ? Qt.lighter(root.raisedColor, root.dark ? 1.08 : 1.01) : root.raisedColor
                    border.color: root.separatorColor
                    border.width: 1
                    scale: accountArea.pressed ? ThemeService.pressScale : 1

                    Text {
                        anchors.leftMargin: 13
                        anchors.topMargin: 11
                        text: root.t("Portfolio")
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold

                        anchors {
                            left: parent.left
                            top: parent.top
                        }

                    }

                    Text {
                        anchors.rightMargin: 13
                        anchors.topMargin: 12
                        text: root.accountState.status === "ok" ? root.t("%1 holdings", [(root.accountState.holdings || []).length]) : root.t(root.dataMode === "kis" ? "Account unavailable" : "Demo")
                        color: root.accountError !== "" ? root.negativeColor : root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 9

                        anchors {
                            right: parent.right
                            top: parent.top
                        }

                    }

                    Grid {
                        anchors.leftMargin: 13
                        anchors.rightMargin: 13
                        anchors.bottomMargin: 12
                        columns: 2
                        columnSpacing: 12
                        rowSpacing: 8

                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }

                        Stat {
                            title: root.t("TOTAL")
                            value: root.accountState.status === "ok" ? StockService.money(root.accountState.totalEvaluation, root.accountState.currency || "KRW") : "—"
                        }

                        Stat {
                            title: root.t("CASH")
                            value: root.accountState.status === "ok" ? StockService.money(root.accountState.cash, root.accountState.currency || "KRW") : "—"
                        }

                        Stat {
                            title: root.t("BUYABLE")
                            value: root.accountState.status === "ok" ? StockService.money(root.accountState.buyingPower, root.accountState.currency || "KRW") : "—"
                        }

                        Stat {
                            title: root.t("P/L")
                            value: root.accountState.status === "ok" ? StockService.signedMoney(root.accountState.profitLoss, "KRW") : "—"
                            valueColor: Number(root.accountState.profitLoss || 0) >= 0 ? root.positiveColor : root.negativeColor
                        }

                    }

                    HoverHandler {
                        id: accountHover
                    }

                    MouseArea {
                        id: accountArea

                        anchors.fill: parent
                        enabled: root.dataMode === "kis" && root.tradingConfigured
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onPressed: root.openPortfolio()
                    }

                    Behavior on scale {
                        AppleSpring {
                            spring: 22
                        }

                    }

                }

                Rectangle {
                    width: parent.width
                    height: 286
                    radius: 13
                    color: root.raisedColor
                    border.color: root.separatorColor
                    border.width: 1

                    Text {
                        anchors.leftMargin: 13
                        anchors.topMargin: 11
                        text: root.t("Watchlist")
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold

                        anchors {
                            left: parent.left
                            top: parent.top
                        }

                    }

                    Rectangle {
                        anchors.rightMargin: 9
                        anchors.topMargin: 7
                        width: 54
                        height: 28
                        radius: 9
                        color: watchAllHover.hovered ? root.separatorColor : "transparent"
                        scale: watchAllArea.pressed ? ThemeService.pressScale : 1

                        anchors {
                            right: parent.right
                            top: parent.top
                        }

                        Text {
                            anchors.centerIn: parent
                            text: root.t("View All")
                            color: "#0a84ff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 9
                            font.weight: Font.DemiBold
                        }

                        HoverHandler {
                            id: watchAllHover
                        }

                        MouseArea {
                            id: watchAllArea

                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressed: root.openWatchlist()
                        }

                        Behavior on scale {
                            AppleSpring {
                                spring: 22
                            }

                        }

                    }

                    Column {
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: 42
                        anchors.bottomMargin: 8
                        spacing: 2

                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            bottom: parent.bottom
                        }

                        Repeater {
                            model: sidebar.displayItems.slice(0, 5)

                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: modelData.symbol === root.symbol && (modelData.market || "KRX") === root.market

                                width: parent.width
                                height: 44
                                radius: 9
                                color: selected ? root.separatorColor : (watchRowHover.hovered ? Qt.rgba(0.5, 0.5, 0.55, root.dark ? 0.13 : 0.08) : "transparent")
                                scale: watchRowArea.pressed ? ThemeService.pressScale : 1

                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 132
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        text: modelData.name || modelData.symbol
                                        color: root.foregroundColor
                                        font.family: "SF Pro Display"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: (modelData.market || "KRX") + " · " + modelData.symbol
                                        color: root.secondaryColor
                                        font.family: "SF Pro Display"
                                        font.pixelSize: 8
                                    }

                                }

                                Column {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 104
                                    spacing: 1

                                    Text {
                                        width: parent.width
                                        text: modelData.price !== undefined ? StockService.money(modelData.price, modelData.currency || (modelData.market === "KRX" ? "KRW" : "USD")) : "—"
                                        color: root.foregroundColor
                                        font.family: "SF Pro Display"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                        horizontalAlignment: Text.AlignRight
                                    }

                                    Text {
                                        width: parent.width
                                        text: modelData.changePct !== undefined ? StockService.signed(modelData.changePct, 2) + "%" : root.t("Updating…")
                                        color: modelData.changePct === undefined ? root.secondaryColor : (Number(modelData.changePct || 0) >= 0 ? root.positiveColor : root.negativeColor)
                                        font.family: "SF Pro Display"
                                        font.pixelSize: 8
                                        horizontalAlignment: Text.AlignRight
                                    }

                                }

                                HoverHandler {
                                    id: watchRowHover
                                }

                                MouseArea {
                                    id: watchRowArea

                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: root.selectInstrument(modelData.symbol, modelData.market || "KRX")
                                }

                                Behavior on scale {
                                    AppleSpring {
                                        spring: 22
                                    }

                                }

                            }

                        }

                        Text {
                            visible: sidebar.displayItems.length === 0
                            width: parent.width
                            height: parent.height
                            text: root.watchlistBusy ? root.t("Loading watchlist…") : root.t("Add the current symbol to start a watchlist.")
                            color: root.secondaryColor
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            wrapMode: Text.WordWrap
                        }

                    }

                }

                Rectangle {
                    width: parent.width
                    height: parent.height - y
                    radius: 13
                    color: aiHover.hovered ? Qt.lighter(root.raisedColor, root.dark ? 1.08 : 1.01) : root.raisedColor
                    border.color: root.separatorColor
                    border.width: 1
                    scale: aiArea.pressed ? ThemeService.pressScale : 1

                    Text {
                        anchors.leftMargin: 13
                        anchors.topMargin: 11
                        text: root.t("AI Insight")
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 12
                        font.weight: Font.DemiBold

                        anchors {
                            left: parent.left
                            top: parent.top
                        }

                    }

                    Text {
                        anchors.rightMargin: 13
                        anchors.topMargin: 11
                        text: root.analysisResult.status === "ok" ? root.t("%1%", [Number(root.analysisResult.confidence || 0)]) : root.t("Not analyzed")
                        color: root.analysisResult.status === "ok" ? "#0a84ff" : root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold

                        anchors {
                            right: parent.right
                            top: parent.top
                        }

                    }

                    Text {
                        anchors.leftMargin: 13
                        anchors.rightMargin: 13
                        anchors.topMargin: 39
                        text: root.analysisResult.status === "ok" ? root.stanceLabel(root.analysisResult.stance) + " · " + root.t("Up %1% · Flat %2% · Down %3%", [root.analysisResult.upProbability, root.analysisResult.flatProbability, root.analysisResult.downProbability]) : root.t("Run analysis to build a 1–5 trading day probability scenario.")
                        color: root.analysisResult.stance === "bullish" ? root.positiveColor : (root.analysisResult.stance === "bearish" ? root.negativeColor : root.secondaryColor)
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        elide: Text.ElideRight

                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                        }

                    }

                    Text {
                        anchors.leftMargin: 13
                        anchors.rightMargin: 13
                        anchors.topMargin: 62
                        anchors.bottomMargin: 11
                        text: root.analysisResult.status === "ok" ? root.analysisResult.summary : root.t("Standalone analysis does not place orders.")
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                        elide: Text.ElideRight
                        maximumLineCount: 3

                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            bottom: parent.bottom
                        }

                    }

                    HoverHandler {
                        id: aiHover
                    }

                    MouseArea {
                        id: aiArea

                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.selectedTab = "ai"
                    }

                    Behavior on scale {
                        AppleSpring {
                            spring: 22
                        }

                    }

                }

            }

        }

        StockNewsPanel {
            root: sidebar.root
            width: parent.width - dashboardPane.width - parent.spacing
            height: parent.height
        }

    }

    component Stat: Column {
        property string title: ""
        property string value: ""
        property color valueColor: root.foregroundColor

        width: (parent.width - parent.columnSpacing) / 2
        spacing: 1

        Text {
            text: parent.title
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 8
            font.weight: Font.DemiBold
            font.letterSpacing: 0.25
        }

        Text {
            width: parent.width
            text: parent.value
            color: parent.valueColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

    }

}
