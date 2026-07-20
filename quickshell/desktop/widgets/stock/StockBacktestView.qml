import QtQuick
import QtQuick.Controls
import ".."

Item {
    id: backtestView
    required property var root
    anchors.leftMargin: 22
    anchors.rightMargin: 22
    anchors.topMargin: 12
    anchors.bottomMargin: 14
    visible: root.quantTab === "backtest"

    Row {
        id: backtestControls
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 36
        spacing: 10
        Rectangle {
            id: strategyPicker
            width: Math.max(240, parent.width - costPicker.width - runBacktestButton.width - parent.spacing * 2)
            height: parent.height
            radius: 10
            color: root.dark ? "#38383b" : "#e9e9ed"
            Row {
                anchors.fill: parent
                QuantChoice {
                    width: parent.width / 3
                    height: parent.height
                    label: root.t("Trend")
                    selected: root.backtestStrategy === "trend"
                    onChosen: { root.backtestStrategy = "trend"; root.resetBacktest() }
                }
                QuantChoice {
                    width: parent.width / 3
                    height: parent.height
                    label: root.t("Momentum")
                    selected: root.backtestStrategy === "momentum"
                    onChosen: { root.backtestStrategy = "momentum"; root.resetBacktest() }
                }
                QuantChoice {
                    width: parent.width / 3
                    height: parent.height
                    label: root.t("RSI")
                    selected: root.backtestStrategy === "mean_reversion"
                    onChosen: { root.backtestStrategy = "mean_reversion"; root.resetBacktest() }
                }
            }
        }
        Rectangle {
            id: costPicker
            width: 180
            height: parent.height
            radius: 10
            color: root.dark ? "#38383b" : "#e9e9ed"
            Row {
                anchors.fill: parent
                QuantChoice {
                    width: parent.width / 3
                    height: parent.height
                    label: root.t("Ideal")
                    selected: root.backtestCostProfile === "ideal"
                    onChosen: { root.backtestCostProfile = "ideal"; root.resetBacktest(); root.resetComparison() }
                }
                QuantChoice {
                    width: parent.width / 3
                    height: parent.height
                    label: root.t("Base")
                    selected: root.backtestCostProfile === "base"
                    onChosen: { root.backtestCostProfile = "base"; root.resetBacktest(); root.resetComparison() }
                }
                QuantChoice {
                    width: parent.width / 3
                    height: parent.height
                    label: root.t("Stress")
                    selected: root.backtestCostProfile === "stress"
                    onChosen: { root.backtestCostProfile = "stress"; root.resetBacktest(); root.resetComparison() }
                }
            }
        }
        Rectangle {
            id: runBacktestButton
            width: 108
            height: parent.height
            radius: 10
            color: runBacktestHover.hovered ? "#2997ff" : "#0a84ff"
            opacity: root.backtestBusy ? 0.52 : 1
            scale: runBacktestArea.pressed ? ThemeService.pressScale : 1
            Behavior on opacity { AppleSpring { spring: 22 } }
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: root.backtestBusy ? root.t("Running…") : root.t("Run Backtest")
                color: "white"
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            HoverHandler { id: runBacktestHover }
            MouseArea {
                id: runBacktestArea
                anchors.fill: parent
                enabled: !root.backtestBusy
                cursorShape: Qt.PointingHandCursor
                onPressed: root.runBacktest()
            }
        }
    }

    Text {
        id: backtestStatus
        anchors { left: parent.left; right: parent.right; top: backtestControls.bottom }
        anchors.topMargin: 6
        height: 15
        text: root.backtestError !== "" ? root.t(root.backtestError)
            : (root.backtestBusy ? root.t("Loading daily closes and simulating next-session returns…")
            : (root.backtestResult.status === "ok"
            ? root.t("%1 · %2—%3 · %4 sessions · %5/%6/%7 bps commission/slippage/tax", [
                root.t(root.backtestResult.strategyLabel),
                root.backtestDate(root.backtestResult.from),
                root.backtestDate(root.backtestResult.to),
                root.backtestResult.sampleCount,
                Number((root.backtestResult.costs || {}).commissionBps || 0).toFixed(1),
                Number((root.backtestResult.costs || {}).slippageBps || 0).toFixed(0),
                Number((root.backtestResult.costs || {}).sellTaxBps || 0).toFixed(0)
            ])
            : root.t("Choose a strategy and execution profile. Base includes commission, slippage, and sell tax.")))
        color: root.backtestError !== "" ? root.negativeColor : root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    Row {
        id: backtestMetricsTop
        anchors { left: parent.left; right: parent.right; top: backtestStatus.bottom }
        anchors.topMargin: 8
        height: 58
        spacing: 8
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("STRATEGY")
            value: root.backtestResult.status === "ok" ? StockService.signed(root.backtestResult.strategyReturnPct || 0, 2) + "%" : "—"
            valueColor: Number(root.backtestResult.strategyReturnPct || 0) >= 0 ? root.positiveColor : root.negativeColor
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("BUY & HOLD")
            value: root.backtestResult.status === "ok" ? StockService.signed(root.backtestResult.benchmarkReturnPct || 0, 2) + "%" : "—"
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("EXCESS")
            value: root.backtestResult.status === "ok" ? StockService.signed(root.backtestResult.excessReturnPct || 0, 2) + "%" : "—"
            valueColor: Number(root.backtestResult.excessReturnPct || 0) >= 0 ? root.positiveColor : root.negativeColor
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("MAX DRAWDOWN")
            value: root.backtestResult.status === "ok" ? Number(root.backtestResult.maxDrawdownPct || 0).toFixed(2) + "%" : "—"
            valueColor: Number(root.backtestResult.maxDrawdownPct || 0) < 0 ? root.negativeColor : root.secondaryColor
        }
    }

    Row {
        id: backtestMetricsBottom
        anchors { left: parent.left; right: parent.right; top: backtestMetricsTop.bottom }
        anchors.topMargin: 8
        height: 58
        spacing: 8
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("WF OOS RETURN")
            value: root.backtestResult.status === "ok" ? StockService.signed((root.backtestResult.walkForward || {}).oosReturnPct || 0, 2) + "%" : "—"
            valueColor: Number((root.backtestResult.walkForward || {}).oosReturnPct || 0) >= 0 ? root.positiveColor : root.negativeColor
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("WF OOS EXCESS")
            value: root.backtestResult.status === "ok" ? StockService.signed((root.backtestResult.walkForward || {}).excessReturnPct || 0, 2) + "%" : "—"
            valueColor: Number((root.backtestResult.walkForward || {}).excessReturnPct || 0) >= 0 ? root.positiveColor : root.negativeColor
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("FOLD WINS")
            value: root.backtestResult.status === "ok" ? Number((root.backtestResult.walkForward || {}).outperformedFolds || 0) + "/"
                + Number((root.backtestResult.walkForward || {}).foldCount || 0) : "—"
            valueColor: root.walkForwardColor()
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("WF SHARPE")
            value: root.backtestResult.status === "ok" ? Number((root.backtestResult.walkForward || {}).sharpe || 0).toFixed(2) : "—"
        }
    }

    Rectangle {
        id: backtestChart
        anchors { left: parent.left; right: parent.right; top: backtestMetricsBottom.bottom; bottom: backtestMethodology.top }
        anchors.topMargin: 10
        anchors.bottomMargin: 8
        radius: 12
        color: root.raisedColor
        border.color: root.separatorColor
        border.width: 1
        clip: true

        Row {
            anchors { left: parent.left; top: parent.top }
            anchors.leftMargin: 13
            anchors.topMargin: 9
            height: 12
            spacing: 16
            Row {
                spacing: 5
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 12; height: 2; radius: 1; color: "#0a84ff" }
                Text { text: root.t("Strategy"); color: root.secondaryColor; font.family: "SF Pro Display"; font.pixelSize: 8 }
            }
            Row {
                spacing: 5
                Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 12; height: 2; radius: 1; color: root.secondaryColor }
                Text { text: root.t("Buy & Hold"); color: root.secondaryColor; font.family: "SF Pro Display"; font.pixelSize: 8 }
            }
        }

        Text {
            anchors { right: parent.right; top: parent.top }
            anchors.rightMargin: 13
            anchors.topMargin: 8
            text: root.backtestResult.status === "ok" ? root.t("Walk-forward · %1", [
                root.t((root.backtestResult.walkForward || {}).statusLabel || "")
            ]) : ""
            color: root.walkForwardColor()
            font.family: "SF Pro Display"
            font.pixelSize: 9
            font.weight: Font.DemiBold
        }

        Canvas {
            id: backtestCanvas
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.topMargin: 27
            anchors.bottomMargin: 12
            property var series: root.backtestResult.equity || []
            onSeriesChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                let ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                if (series.length < 2 || width <= 0 || height <= 0) return
                let minimum = 100
                let maximum = 100
                for (let index = 0; index < series.length; index++) {
                    minimum = Math.min(minimum, Number(series[index].strategy), Number(series[index].benchmark))
                    maximum = Math.max(maximum, Number(series[index].strategy), Number(series[index].benchmark))
                }
                let padding = Math.max(1, (maximum - minimum) * 0.1)
                minimum -= padding
                maximum += padding
                let xFor = index => index / (series.length - 1) * width
                let yFor = value => height - (Number(value) - minimum) / Math.max(0.001, maximum - minimum) * height
                ctx.strokeStyle = root.separatorColor
                ctx.lineWidth = 1
                ctx.beginPath()
                ctx.moveTo(0, yFor(100))
                ctx.lineTo(width, yFor(100))
                ctx.stroke()
                let drawLine = (key, color, lineWidth) => {
                    ctx.strokeStyle = color
                    ctx.lineWidth = lineWidth
                    ctx.lineJoin = "round"
                    ctx.lineCap = "round"
                    ctx.beginPath()
                    for (let index = 0; index < series.length; index++) {
                        let x = xFor(index)
                        let y = yFor(series[index][key])
                        if (index === 0) ctx.moveTo(x, y)
                        else ctx.lineTo(x, y)
                    }
                    ctx.stroke()
                }
                drawLine("benchmark", root.secondaryColor, 1.25)
                drawLine("strategy", "#0a84ff", 2)
            }
        }

        Text {
            anchors.centerIn: parent
            visible: !root.backtestBusy && root.backtestResult.status !== "ok"
            text: root.backtestError !== "" ? root.t("Could not complete the simulation.")
                : root.t("Run a strategy to compare normalized equity curves.")
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
        }
    }

    Text {
        id: backtestMethodology
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 30
        text: root.backtestResult.status === "ok"
            ? root.t("%1 %2 %3", [
                root.t((root.backtestResult.walkForward || {}).methodology || ""),
                root.t(root.backtestResult.methodology || ""),
                root.t(root.backtestResult.disclaimer || "")
            ])
            : root.t("Walk-forward uses prior sessions for selection and freezes parameters out-of-sample. It never triggers an order.")
        color: root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 8
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
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
