import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic

Item {
    id: comparisonView
    required property var root
    anchors.leftMargin: 22
    anchors.rightMargin: 22
    anchors.topMargin: 12
    anchors.bottomMargin: 14
    visible: root.quantTab === "compare"

    Row {
        id: comparisonControls
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 36
        spacing: 10
        Rectangle {
            id: comparisonCostPicker
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
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - comparisonCostPicker.width - runComparisonButton.width - parent.spacing * 2
            text: root.t("Same adjusted closes · same execution costs")
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 9
            elide: Text.ElideRight
        }
        Rectangle {
            id: runComparisonButton
            width: 128
            height: parent.height
            radius: 10
            color: runComparisonHover.hovered ? "#2997ff" : "#0a84ff"
            opacity: root.comparisonBusy ? 0.52 : 1
            scale: runComparisonArea.pressed ? ThemeService.pressScale : 1
            Behavior on opacity { AppleSpring { spring: 22 } }
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: root.comparisonBusy ? root.t("Comparing…") : root.t("Compare Strategies")
                color: "white"
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            HoverHandler { id: runComparisonHover }
            MouseArea {
                id: runComparisonArea
                anchors.fill: parent
                enabled: !root.comparisonBusy
                cursorShape: Qt.PointingHandCursor
                onPressed: root.runComparison()
            }
        }
    }

    Text {
        id: comparisonStatus
        anchors { left: parent.left; right: parent.right; top: comparisonControls.bottom }
        anchors.topMargin: 6
        height: 15
        text: root.comparisonError !== "" ? root.t(root.comparisonError)
            : (root.comparisonBusy ? root.t("Running identical full-sample and walk-forward tests…")
            : (root.comparisonResult.status === "ok"
            ? root.t("%1—%2 · %3 sessions · ranking is OOS-weighted", [
                root.backtestDate(root.comparisonResult.from),
                root.backtestDate(root.comparisonResult.to),
                root.comparisonResult.sampleCount
            ])
            : root.t("Compare all strategies under one data window and execution profile.")))
        color: root.comparisonError !== "" ? root.negativeColor : root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 9
        elide: Text.ElideRight
    }

    Row {
        id: comparisonSummary
        anchors { left: parent.left; right: parent.right; top: comparisonStatus.bottom }
        anchors.topMargin: 8
        height: 58
        spacing: 8
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("BEST OOS BALANCE")
            value: root.comparisonResult.status === "ok" ? root.t(root.comparisonResult.bestLabel) : "—"
            valueColor: "#0a84ff"
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("ROBUSTNESS")
            value: root.comparisonResult.status === "ok" ? Number(root.comparisonResult.bestScore || 0) + "/100" : "—"
            valueColor: Number(root.comparisonResult.bestScore || 0) >= 70 ? root.positiveColor : "#ff9f0a"
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("HIGH OVERFIT RISK")
            value: root.comparisonResult.status === "ok" ? Number(root.comparisonResult.highRiskCount || 0).toString() : "—"
            valueColor: Number(root.comparisonResult.highRiskCount || 0) > 0 ? root.negativeColor : root.positiveColor
        }
        ReportMetric {
            width: (parent.width - 24) / 4
            title: root.t("STRATEGIES")
            value: root.comparisonResult.status === "ok" ? Number((root.comparisonResult.items || []).length).toString() : "—"
        }
    }

    Column {
        id: comparisonList
        anchors { left: parent.left; right: parent.right; top: comparisonSummary.bottom }
        anchors.topMargin: 9
        spacing: 7
        Repeater {
            model: root.comparisonResult.items || []
            delegate: Rectangle {
                id: comparisonCard
                required property var modelData
                width: comparisonList.width
                height: 92
                radius: 12
                color: root.raisedColor
                border.color: modelData.rank === 1 ? Qt.rgba(0.04, 0.52, 1, 0.58) : root.separatorColor
                border.width: 1

                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: 4
                    radius: 2
                    color: modelData.rank === 1 ? "#0a84ff" : root.comparisonRiskColor(modelData.overfitRisk)
                }
                Text {
                    anchors { left: parent.left; top: parent.top }
                    anchors.leftMargin: 14
                    anchors.topMargin: 11
                    width: 20
                    text: "#" + modelData.rank
                    color: modelData.rank === 1 ? "#0a84ff" : root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors { left: parent.left; top: parent.top }
                    anchors.leftMargin: 42
                    anchors.topMargin: 9
                    width: 180
                    text: root.t(modelData.label)
                    color: root.foregroundColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    font.letterSpacing: -0.1
                    elide: Text.ElideRight
                }
                Text {
                    anchors { left: parent.left; top: parent.top }
                    anchors.leftMargin: 42
                    anchors.topMargin: 29
                    width: parent.width - 208
                    text: (modelData.overfitReasons || []).map(reason => root.t(reason)).join(" · ")
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 8
                    elide: Text.ElideRight
                }
                Rectangle {
                    id: comparisonRiskPill
                    anchors { right: useStrategyButton.left; top: parent.top }
                    anchors.rightMargin: 8
                    anchors.topMargin: 9
                    width: 104
                    height: 26
                    radius: 9
                    color: modelData.overfitRisk === "low" ? Qt.rgba(0.19, 0.82, 0.35, 0.15)
                        : (modelData.overfitRisk === "high" ? Qt.rgba(1, 0.27, 0.23, 0.15) : Qt.rgba(1, 0.62, 0.04, 0.15))
                    Text {
                        anchors.centerIn: parent
                        text: root.t(root.comparisonRiskLabel(modelData.overfitRisk))
                        color: root.comparisonRiskColor(modelData.overfitRisk)
                        font.family: "SF Pro Display"
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                    }
                }
                Rectangle {
                    id: useStrategyButton
                    anchors { right: parent.right; top: parent.top }
                    anchors.rightMargin: 10
                    anchors.topMargin: 9
                    width: 52
                    height: 26
                    radius: 9
                    color: useStrategyHover.hovered ? Qt.rgba(0.04, 0.52, 1, 0.22) : root.separatorColor
                    scale: useStrategyArea.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 22 } }
                    Text {
                        anchors.centerIn: parent
                        text: root.t("Inspect")
                        color: "#0a84ff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 8
                        font.weight: Font.DemiBold
                    }
                    HoverHandler { id: useStrategyHover }
                    MouseArea {
                        id: useStrategyArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onPressed: root.inspectComparisonStrategy(modelData.strategy)
                    }
                }
                Row {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    anchors.leftMargin: 42
                    anchors.rightMargin: 10
                    anchors.bottomMargin: 8
                    height: 34
                    ComparisonValue {
                        width: parent.width / 7
                        title: root.t("OOS")
                        value: StockService.signed(modelData.oosReturnPct, 2) + "%"
                        valueColor: Number(modelData.oosReturnPct) >= 0 ? root.positiveColor : root.negativeColor
                    }
                    ComparisonValue {
                        width: parent.width / 7
                        title: root.t("EXCESS")
                        value: StockService.signed(modelData.oosExcessReturnPct, 2) + "%"
                        valueColor: Number(modelData.oosExcessReturnPct) >= 0 ? root.positiveColor : root.negativeColor
                    }
                    ComparisonValue {
                        width: parent.width / 7
                        title: root.t("FOLDS")
                        value: modelData.foldWins + "/" + modelData.foldCount
                    }
                    ComparisonValue {
                        width: parent.width / 7
                        title: root.t("OOS MDD")
                        value: Number(modelData.oosMaxDrawdownPct).toFixed(1) + "%"
                        valueColor: root.negativeColor
                    }
                    ComparisonValue {
                        width: parent.width / 7
                        title: root.t("P/L FACTOR")
                        value: Number(modelData.profitFactor).toFixed(2)
                    }
                    ComparisonValue {
                        width: parent.width / 7
                        title: root.t("HIT RATE")
                        value: Number(modelData.hitRate).toFixed(1) + "%"
                    }
                    ComparisonValue {
                        width: parent.width / 7
                        title: root.t("SWITCH/YR")
                        value: Number(modelData.turnoverAnnualized).toFixed(1)
                    }
                }
            }
        }
    }

    Text {
        anchors.centerIn: parent
        visible: !root.comparisonBusy && (root.comparisonResult.items || []).length === 0
        text: root.comparisonError !== "" ? root.t("Could not complete the comparison.")
            : root.t("Run one identical test across all strategies.")
        color: root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 10
    }

    Text {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 30
        text: root.comparisonResult.status === "ok"
            ? root.t("%1 %2", [
                root.t(root.comparisonResult.methodology || ""),
                root.t(root.comparisonResult.disclaimer || "")
            ])
            : root.t("Robustness is a transparent heuristic, not an expected-return forecast.")
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
    component ComparisonValue: Column {
        property string title: ""
        property string value: ""
        property color valueColor: root.foregroundColor
        spacing: 2
        Text {
            width: parent.width
            text: parent.title
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 7
            font.weight: Font.DemiBold
            font.letterSpacing: 0.25
            elide: Text.ElideRight
        }
        Text {
            width: parent.width
            text: parent.value
            color: parent.valueColor
            font.family: "SF Pro Display"
            font.pixelSize: 9
            font.weight: Font.DemiBold
            elide: Text.ElideRight
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
