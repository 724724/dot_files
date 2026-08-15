import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic
import "." as Stock

Item {
    id: sheet
    required property var root
    anchors.fill: parent
    visible: root.forecastVisible || forecastPanel.opacity > 0.002
    z: 130

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.42)
        opacity: root.forecastVisible ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 22 } }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.forecastVisible
        onPressed: root.closeForecasts()
    }
    Rectangle {
        id: forecastPanel
        anchors.fill: parent
        anchors.margins: 14
        radius: 17
        color: root.dark ? "#242426" : "#ffffff"
        border.color: root.separatorColor
        border.width: 1
        opacity: root.forecastVisible ? 1 : 0
        scale: root.forecastVisible ? 1 : 0.965
        transformOrigin: Item.BottomRight
        Behavior on opacity { AppleSpring { spring: 22 } }
        Behavior on scale { AppleSpring { spring: 22 } }
        MouseArea { anchors.fill: parent }

        Text {
            id: forecastTitle
            anchors { left: parent.left; top: parent.top }
            anchors.leftMargin: 22
            anchors.topMargin: 18
            text: root.t("Quant Lab")
            color: root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            font.letterSpacing: -0.35
        }
        Text {
            anchors { left: parent.left; top: forecastTitle.bottom }
            anchors.leftMargin: 22
            anchors.topMargin: 3
            text: root.quantTab === "forecasts"
                ? root.t("%1 · 5 trading-day checks · local journal", [root.snapshot.name || root.symbol])
                : (root.quantTab === "backtest"
                ? root.t("%1 · daily close simulation · no look-ahead", [root.snapshot.name || root.symbol])
                : (root.quantTab === "compare"
                ? root.t("%1 · identical data and costs · OOS ranking", [root.snapshot.name || root.symbol])
                : (root.quantTab === "ai_eval"
                ? root.t("%1 · model calibration · confidence quality gate", [root.snapshot.name || root.symbol])
                : (root.quantTab === "usage"
                ? root.t("30-day API token usage ledger · prompts and responses are never stored")
                : (root.quantTab === "automation"
                ? (root.automationState.policy && root.automationState.policy.executionMode === "live"
                    ? root.t("KIS live execution · expiring authorization · serial reconciliation")
                    : (root.automationState.policy && root.automationState.policy.executionMode === "paper"
                    ? root.t("KIS paper execution · serial reconciliation")
                    : root.t("Paper-only · capital preservation gates · no broker execution"))
                    )
                : root.t("Watchlist · completed daily closes · local technical ranking"))))))
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
        }
        Rectangle {
            id: refreshForecastButton
            anchors { right: closeForecastButton.left; top: parent.top }
            anchors.rightMargin: 8
            anchors.topMargin: 14
            width: 72
            height: 32
            radius: 10
            visible: root.quantTab === "forecasts" || root.quantTab === "ai_eval" || root.quantTab === "usage"
                || root.quantTab === "screener" || root.quantTab === "automation"
            color: refreshForecastHover.hovered ? root.raisedColor : root.separatorColor
            opacity: (root.quantTab === "automation" ? root.automationBusy
                : (root.quantTab === "screener" ? root.screenerBusy
                : (root.quantTab === "usage" ? root.aiUsageBusy
                : (root.quantTab === "ai_eval" ? root.aiValidationBusy : root.forecastRunning)))) ? 0.46 : 1
            scale: refreshForecastArea.pressed ? ThemeService.pressScale : 1
            Behavior on opacity { AppleSpring { spring: 22 } }
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: (root.quantTab === "automation" ? root.automationBusy
                    : (root.quantTab === "screener" ? root.screenerBusy
                    : (root.quantTab === "usage" ? root.aiUsageBusy
                    : (root.quantTab === "ai_eval" ? root.aiValidationBusy : root.forecastRunning))))
                    ? root.t("Updating…") : root.t("Refresh")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            HoverHandler { id: refreshForecastHover }
            MouseArea {
                id: refreshForecastArea
                anchors.fill: parent
                enabled: !(root.quantTab === "automation" ? root.automationBusy
                    : (root.quantTab === "screener" ? root.screenerBusy
                    : (root.quantTab === "usage" ? root.aiUsageBusy
                    : (root.quantTab === "ai_eval" ? root.aiValidationBusy : root.forecastRunning))))
                cursorShape: Qt.PointingHandCursor
                onPressed: root.quantTab === "automation" ? root.refreshAutomation()
                    : (root.quantTab === "screener" ? root.refreshScreener()
                    : (root.quantTab === "usage" ? root.refreshAiUsage()
                    : (root.quantTab === "ai_eval" ? root.refreshAiValidation() : root.refreshForecasts(true))))
            }
        }
        Rectangle {
            id: closeForecastButton
            anchors { right: parent.right; top: parent.top }
            anchors.rightMargin: 14
            anchors.topMargin: 14
            width: 32
            height: 32
            radius: 10
            color: closeForecastHover.hovered ? root.raisedColor : root.separatorColor
            scale: closeForecastArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
            HoverHandler { id: closeForecastHover }
            MouseArea {
                id: closeForecastArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.closeForecasts()
            }
        }

        Rectangle {
            id: quantTabs
            anchors { left: parent.left; top: parent.top }
            anchors.leftMargin: 22
            anchors.topMargin: 70
            width: Math.min(620, parent.width - 44)
            height: 32
            radius: 10
            color: root.dark ? "#38383b" : "#e9e9ed"
            Row {
                anchors.fill: parent
                QuantChoice {
                    width: parent.width / 7
                    height: parent.height
                    label: root.t("Forecasts")
                    selected: root.quantTab === "forecasts"
                    onChosen: root.chooseQuantTab("forecasts")
                }
                QuantChoice {
                    width: parent.width / 7
                    height: parent.height
                    label: root.t("Backtest")
                    selected: root.quantTab === "backtest"
                    onChosen: root.chooseQuantTab("backtest")
                }
                QuantChoice {
                    width: parent.width / 7
                    height: parent.height
                    label: root.t("Compare")
                    selected: root.quantTab === "compare"
                    onChosen: root.chooseQuantTab("compare")
                }
                QuantChoice {
                    width: parent.width / 7
                    height: parent.height
                    label: root.t("AI Eval")
                    selected: root.quantTab === "ai_eval"
                    onChosen: root.chooseQuantTab("ai_eval")
                }
                QuantChoice {
                    width: parent.width / 7
                    height: parent.height
                    label: root.t("Usage")
                    selected: root.quantTab === "usage"
                    onChosen: root.chooseQuantTab("usage")
                }
                QuantChoice {
                    width: parent.width / 7
                    height: parent.height
                    label: root.t("Screener")
                    selected: root.quantTab === "screener"
                    onChosen: root.chooseQuantTab("screener")
                }
                QuantChoice {
                    width: parent.width / 7
                    height: parent.height
                    label: root.t("Automation")
                    selected: root.quantTab === "automation"
                    onChosen: root.chooseQuantTab("automation")
                }
            }
        }

        Row {
            id: forecastSummary
            anchors { left: parent.left; right: parent.right; top: quantTabs.bottom }
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 12
            height: 58
            spacing: 10
            visible: root.quantTab === "forecasts"
            ReportMetric {
                width: (parent.width - 30) / 4
                title: root.t("QUALIFIED HIT")
                value: Number((root.forecastState.stats || {}).qualifiedHitRate || 0).toFixed(1) + "%"
                valueColor: Number((root.forecastState.stats || {}).qualifiedResolved || 0) > 0 ? root.positiveColor : root.secondaryColor
            }
            ReportMetric {
                width: (parent.width - 30) / 4
                title: root.t("QUALIFIED / RESOLVED")
                value: Number((root.forecastState.stats || {}).qualifiedResolved || 0) + " / "
                    + Number((root.forecastState.stats || {}).resolved || 0)
            }
            ReportMetric {
                width: (parent.width - 30) / 4
                title: root.t("OPEN")
                value: Number((root.forecastState.stats || {}).open || 0).toString()
                valueColor: "#0a84ff"
            }
            ReportMetric {
                width: (parent.width - 30) / 4
                title: root.t("BRIER · LOWER BETTER")
                value: Number((root.forecastState.stats || {}).brierScore || 0).toFixed(3)
            }
        }

        ListView {
            id: forecastList
            anchors { left: parent.left; right: parent.right; top: forecastSummary.bottom; bottom: forecastFootnote.top }
            anchors.leftMargin: 18
            anchors.rightMargin: 18
            anchors.topMargin: 12
            anchors.bottomMargin: 8
            visible: root.quantTab === "forecasts"
            clip: true
            spacing: 6
            model: root.forecastState.items || []
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
                onWheel: event => {
                    forecastGlide.stop()
                    if (Kinetic.onWheel(forecastList, event, forecastList._ks, { gain: 78 })) forecastEndTimer.restart()
                }
            }
            Timer {
                id: forecastEndTimer
                interval: 48
                onTriggered: {
                    let glide = Kinetic.fling(forecastList, forecastList._ks, {})
                    if (glide) {
                        forecastGlide.from = glide.from
                        forecastGlide.to = glide.to
                        forecastGlide.restart()
                    }
                }
            }
            SpringAnimation {
                id: forecastGlide
                target: forecastList
                property: "contentY"
                spring: 18
                damping: ThemeService.momentumDamping
                epsilon: 0.25
            }
            delegate: Rectangle {
                required property var modelData
                width: forecastList.width
                height: 72
                radius: 12
                color: root.raisedColor
                border.color: root.separatorColor
                border.width: 1

                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: 4
                    radius: 2
                    color: root.forecastStatusColor(modelData)
                }
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 15
                    anchors.verticalCenter: parent.verticalCenter
                    width: 174
                    spacing: 3
                    Text {
                        width: parent.width
                        text: root.analysisTime(modelData.generatedAt)
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.t("%1 · %2%3", [
                            modelData.provider || "AI",
                            modelData.profile || "",
                            Number(modelData.confidence || 0) < 60 ? root.t(" · low confidence") : ""
                        ])
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }
                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 205
                    anchors.verticalCenter: parent.verticalCenter
                    width: 120
                    spacing: 3
                    Text {
                        width: parent.width
                        text: root.stanceLabel(modelData.stance) + " · " + Number(modelData.confidence || 0) + "%"
                        color: modelData.stance === "bullish" ? root.positiveColor
                            : (modelData.stance === "bearish" ? root.negativeColor : "#0a84ff")
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: Number(modelData.upProbability || 0) + " / "
                            + Number(modelData.flatProbability || 0) + " / " + Number(modelData.downProbability || 0)
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                }
                Column {
                    anchors.right: forecastStatusPill.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 142
                    spacing: 3
                    Text {
                        width: parent.width
                        text: StockService.money(modelData.entryPrice, modelData.currency) + " → "
                            + StockService.money(modelData.lastPrice, modelData.currency)
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: root.t("%1% · check %2", [
                            StockService.signed(root.forecastReturn(modelData), 2),
                            root.forecastTargetLabel(modelData)
                        ])
                        color: root.forecastReturn(modelData) >= 0 ? root.positiveColor : root.negativeColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 8
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideLeft
                    }
                }
                Rectangle {
                    id: forecastStatusPill
                    anchors.right: deleteForecastButton.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 68
                    height: 28
                    radius: 9
                    color: modelData.status !== "resolved" ? Qt.rgba(0.04, 0.52, 1, 0.16)
                        : (modelData.correct === true ? Qt.rgba(0.19, 0.82, 0.35, 0.16) : Qt.rgba(1, 0.27, 0.23, 0.16))
                    Text {
                        anchors.centerIn: parent
                        text: root.forecastStatusLabel(modelData)
                        color: root.forecastStatusColor(modelData)
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    id: deleteForecastButton
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: 9
                    color: deleteForecastHover.hovered ? Qt.rgba(1, 0.27, 0.23, 0.18) : root.separatorColor
                    opacity: deleteForecastProcess.running ? 0.46 : 1
                    scale: deleteForecastArea.pressed ? ThemeService.pressScale : 1
                    Behavior on opacity { AppleSpring { spring: 22 } }
                    Behavior on scale { AppleSpring { spring: 22 } }
                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        color: root.negativeColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 15
                        font.weight: Font.Medium
                    }
                    HoverHandler { id: deleteForecastHover }
                    MouseArea {
                        id: deleteForecastArea
                        anchors.fill: parent
                        enabled: !deleteForecastProcess.running
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.deleteForecast(modelData.id)
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                visible: forecastList.count === 0
                width: parent.width - 40
                text: root.forecastError !== "" ? root.t(root.forecastError)
                    : (root.forecastRunning ? root.t("Loading forecast journal…")
                    : root.t("Run a fresh AI analysis to start measuring forecasts."))
                color: root.forecastError !== "" ? root.negativeColor : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }

        Text {
            id: forecastFootnote
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.bottomMargin: 13
            height: 15
            visible: root.quantTab === "forecasts"
            text: root.forecastError !== "" ? root.t(root.forecastError)
                : root.t("Measured with a ±1% neutral band. Below 60% confidence remains journaled but is excluded from qualified metrics.")
            color: root.forecastError !== "" ? root.negativeColor : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 9
            elide: Text.ElideRight
        }

        Stock.StockBacktestView {
            root: sheet.root
            anchors { left: parent.left; right: parent.right; top: quantTabs.bottom; bottom: parent.bottom }
        }

        Stock.StockComparisonView {
            root: sheet.root
            anchors { left: parent.left; right: parent.right; top: quantTabs.bottom; bottom: parent.bottom }
        }

        Stock.StockAiValidationView {
            root: sheet.root
            anchors { left: parent.left; right: parent.right; top: quantTabs.bottom; bottom: parent.bottom }
        }

        Stock.StockAiUsageView {
            root: sheet.root
            anchors { left: parent.left; right: parent.right; top: quantTabs.bottom; bottom: parent.bottom }
        }

        Stock.StockScreenerView {
            root: sheet.root
            anchors { left: parent.left; right: parent.right; top: quantTabs.bottom; bottom: parent.bottom }
        }

        Stock.StockAutomationView {
            root: sheet.root
            anchors { left: parent.left; right: parent.right; top: quantTabs.bottom; bottom: parent.bottom }
        }
    }

    component QuantChoice: Item {
        id: quantChoice
        property string label: ""
        property bool selected: false
        signal chosen()
        scale: quantChoiceArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 22 } }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 8
            color: quantChoice.selected ? (root.dark ? "#505055" : "#ffffff")
                : (quantChoiceHover.hovered ? root.separatorColor : "transparent")
        }
        Text {
            anchors.centerIn: parent
            text: quantChoice.label
            color: quantChoice.selected ? root.foregroundColor : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 9
            font.weight: quantChoice.selected ? Font.DemiBold : Font.Medium
        }
        HoverHandler { id: quantChoiceHover }
        MouseArea {
            id: quantChoiceArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: quantChoice.chosen()
        }
    }





    component ReportMetric: Rectangle {
        property string title: ""
        property string value: ""
        property color valueColor: root.foregroundColor
        height: 58
        radius: 11
        color: root.raisedColor
        Column {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4
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
                color: parent.parent.valueColor
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
                font.letterSpacing: -0.1
                elide: Text.ElideRight
            }
        }
    }
}
