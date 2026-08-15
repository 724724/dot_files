import QtQuick
import ".."

Item {
    id: aiPanel
    required property var root
    opacity: root.selectedTab === "ai" ? 1 : 0
    visible: opacity > 0.002
    enabled: root.selectedTab === "ai"
    Behavior on opacity { AppleSpring { spring: 18 } }

    Row {
        id: insightRow
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 64
        spacing: 10
        InsightCard {
            width: (parent.width - 20) / 3
            icon: root.analysisResult.stance === "bullish" ? "↗" : (root.analysisResult.stance === "bearish" ? "↘" : "→")
            title: root.t("Scenario")
            detail: root.stanceLabel(root.analysisResult.stance)
            ready: root.analysisResult.status === "ok"
        }
        InsightCard {
            width: (parent.width - 20) / 3
            icon: "◎"
            title: root.t("Confidence")
            detail: root.analysisResult.status === "ok"
                ? (Number(root.analysisResult.rawConfidence || root.analysisResult.confidence)
                    !== Number(root.analysisResult.confidence)
                    ? root.t("%1% · raw %2%", [root.analysisResult.confidence, root.analysisResult.rawConfidence])
                    : root.t("%1% · %2 news · %3 sources", [
                        root.analysisResult.confidence,
                        root.analysisResult.newsCount,
                        Number((root.analysisResult.newsContext || {}).sourceCount || 0)
                    ]))
                : root.t("Not analyzed")
            ready: root.analysisResult.status === "ok"
        }
        InsightCard {
            width: (parent.width - 20) / 3
            icon: "⌁"
            title: root.t("Walk-forward")
            detail: root.analysisResult.status === "ok" && root.analysisResult.evidence
                ? (root.analysisResult.evidence.status === "insufficient" ? root.t("Need more data")
                : root.t("%1% · %2 samples", [
                    root.analysisResult.evidence.hitRate,
                    root.analysisResult.evidence.sampleCount
                ]))
                : root.t("Local evidence")
            ready: root.analysisResult.status === "ok" && root.analysisResult.evidence
                && root.analysisResult.evidence.status === "usable"
        }
    }

    Rectangle {
        id: probabilityBar
        anchors { left: parent.left; right: parent.right; top: insightRow.bottom }
        anchors.topMargin: 8
        height: 7
        radius: 3.5
        clip: true
        color: root.separatorColor
        opacity: root.analysisResult.status === "ok" ? 1 : 0.35
        Behavior on opacity { AppleSpring { spring: 18 } }
        Row {
            anchors.fill: parent
            Rectangle { width: parent.width * Number(root.analysisResult.upProbability || 0) / 100; height: parent.height; color: root.positiveColor }
            Rectangle { width: parent.width * Number(root.analysisResult.flatProbability || 0) / 100; height: parent.height; color: "#0a84ff" }
            Rectangle { width: parent.width * Number(root.analysisResult.downProbability || 0) / 100; height: parent.height; color: root.negativeColor }
        }
    }

    Text {
        anchors { left: parent.left; right: parent.right; top: probabilityBar.bottom; bottom: analysisActions.top }
        anchors.topMargin: 7
        anchors.bottomMargin: 4
        text: root.analysisError !== "" ? root.t(root.analysisError)
            : (root.analysisBusy ? "최근 뉴스와 차트 지표를 분석하고 있습니다…"
            : (root.analysisResult.status === "ok" ? root.analysisResult.summary
            : (root.aiConfigured ? root.t("Run analysis to build a 1–5 trading day probability scenario.")
            : root.t("Save an OpenAI or Claude API key in Settings."))))
        color: root.analysisError !== "" ? root.negativeColor : root.secondaryColor
        font.family: "SF Pro Display"
        font.pixelSize: 11
        wrapMode: Text.WordWrap
        elide: Text.ElideRight
        maximumLineCount: 2
    }

    Row {
        id: analysisActions
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 44
        spacing: 12
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - historyButton.width - detailsButton.width - analyzeButton.width - parent.spacing * 3
            text: {
                if (root.analysisResult.status !== "ok")
                    return root.t("Standalone analysis does not place orders.")
                let value = root.t("Up %1% · Flat %2% · Down %3%", [
                    root.analysisResult.upProbability,
                    root.analysisResult.flatProbability,
                    root.analysisResult.downProbability
                ])
                if ((root.analysisResult.forecast || {}).id) value += root.t(" · Journaled")
                if ((root.analysisResult.calibrationAdjustment || {}).status === "applied") value += root.t(" · Calibrated")
                if ((root.analysisResult.modelWeighting || {}).status === "applied") value += root.t(" · Weighted ensemble")
                if ((root.analysisResult.ensembleAgreement || {}).status === "low") value += root.t(" · Model conflict")
                if ((root.analysisResult.providerStatus || {}).degraded) value += root.t(" · Partial provider result")
                if ((root.analysisResult.qualityGate || {}).confidenceStatus === "low_confidence"
                        || (root.analysisResult.qualityGate || {}).status === "low_confidence")
                    value += root.t(" · Low confidence")
                return value
            }
            color: (root.analysisResult.providerStatus || {}).degraded ? "#ff9f0a" : root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 10
            elide: Text.ElideRight
        }
        Rectangle {
            id: historyButton
            width: 82
            height: 40
            radius: 11
            color: historyHover.hovered ? root.raisedColor : root.separatorColor
            scale: historyArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: root.t("Quant Lab")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            HoverHandler { id: historyHover }
            MouseArea {
                id: historyArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.openForecasts()
            }
        }
        Rectangle {
            id: detailsButton
            width: 82
            height: 40
            radius: 11
            color: detailsHover.hovered ? root.raisedColor : root.separatorColor
            opacity: root.analysisResult.status === "ok" ? 1 : 0.42
            scale: detailsArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: root.t("Details")
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
            HoverHandler { id: detailsHover }
            MouseArea {
                id: detailsArea
                anchors.fill: parent
                enabled: root.analysisResult.status === "ok"
                cursorShape: Qt.PointingHandCursor
                onPressed: {
                    root.analysisReportVisible = true
                    root.forceActiveFocus()
                }
            }
        }
        Rectangle {
            id: analyzeButton
            width: 132
            height: 40
            radius: 11
            color: "#0a84ff"
            opacity: root.aiConfigured && !root.analysisBusy ? 1 : 0.42
            scale: analyzeArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 18 } }
            Text {
                anchors.centerIn: parent
                text: root.analysisBusy ? root.t("Analyzing…")
                    : (root.analysisResult.status === "ok" ? root.t("Refresh") : root.t("Run Analysis"))
                color: "#ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            MouseArea {
                id: analyzeArea
                anchors.fill: parent
                enabled: root.aiConfigured && !root.analysisBusy
                cursorShape: Qt.PointingHandCursor
                onPressed: root.runAnalysis()
            }
        }
    }

    component InsightCard: Rectangle {
        property string icon: ""
        property string title: ""
        property string detail: ""
        property bool ready: false
        height: 64
        radius: 11
        color: root.raisedColor
        border.color: root.separatorColor
        border.width: 1
        Row {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: parent.parent.icon
                color: parent.parent.ready ? "#0a84ff" : root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 20
                font.weight: Font.Medium
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 34
                spacing: 3
                Text {
                    text: parent.parent.parent.title
                    color: root.foregroundColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: parent.parent.parent.detail
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }
        }
    }
}
