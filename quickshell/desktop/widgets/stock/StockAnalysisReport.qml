import QtQuick
import QtQuick.Controls
import ".."
import "../kinetic.js" as Kinetic

Item {
    id: sheet
    required property var root
    anchors.fill: parent
    visible: root.analysisReportVisible || analysisReport.opacity > 0.002
    z: 100

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.42)
        opacity: root.analysisReportVisible ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 22 } }
    }
    MouseArea {
        anchors.fill: parent
        enabled: root.analysisReportVisible
        onPressed: root.analysisReportVisible = false
    }
    Rectangle {
        id: analysisReport
        anchors.fill: parent
        anchors.margins: 14
        radius: 17
        color: root.dark ? "#242426" : "#ffffff"
        border.color: root.separatorColor
        border.width: 1
        opacity: root.analysisReportVisible ? 1 : 0
        scale: root.analysisReportVisible ? 1 : 0.965
        transformOrigin: Item.BottomRight
        Behavior on opacity { AppleSpring { spring: 22 } }
        Behavior on scale { AppleSpring { spring: 22 } }
        MouseArea { anchors.fill: parent }

        Text {
            id: reportTitle
            anchors { left: parent.left; top: parent.top }
            anchors.leftMargin: 22
            anchors.topMargin: 18
            text: "AI Scenario Report"
            color: root.foregroundColor
            font.family: "SF Pro Display"
            font.pixelSize: 20
            font.weight: Font.DemiBold
            font.letterSpacing: -0.35
        }
        Text {
            anchors { left: parent.left; top: reportTitle.bottom }
            anchors.leftMargin: 22
            anchors.topMargin: 3
            width: parent.width - 88
            text: {
                let context = root.analysisResult.analysisContext || ({})
                return (root.snapshot.name || root.symbol) + " · "
                    + (root.analysisResult.horizon || "1–5 trading days")
                    + (context.label ? " · " + context.label + " · " + Number(context.sampleCount || 0) + " sessions" : "")
                    + (root.analysisTime(root.analysisResult.generatedAt) !== ""
                        ? " · " + root.analysisTime(root.analysisResult.generatedAt) : "")
            }
            color: root.secondaryColor
            font.family: "SF Pro Display"
            font.pixelSize: 11
            elide: Text.ElideRight
        }
        Rectangle {
            anchors { right: parent.right; top: parent.top }
            anchors.rightMargin: 14
            anchors.topMargin: 14
            width: 32
            height: 32
            radius: 10
            color: closeReportHover.hovered ? root.raisedColor : root.separatorColor
            scale: closeReportArea.pressed ? ThemeService.pressScale : 1
            Behavior on scale { AppleSpring { spring: 22 } }
            Text {
                anchors.centerIn: parent
                text: "✕"
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
            }
            HoverHandler { id: closeReportHover }
            MouseArea {
                id: closeReportArea
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: root.analysisReportVisible = false
            }
        }

        Flickable {
            id: reportScroll
            anchors { left: parent.left; right: parent.right; top: parent.top; bottom: parent.bottom }
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            anchors.topMargin: 72
            anchors.bottomMargin: 10
            clip: true
            contentWidth: width
            contentHeight: reportColumn.implicitHeight + 24
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
                    reportGlide.stop()
                    if (Kinetic.onWheel(reportScroll, event, reportScroll._ks, { gain: 84 }))
                        reportEndTimer.restart()
                }
            }
            Timer {
                id: reportEndTimer
                interval: 48
                onTriggered: {
                    let glide = Kinetic.fling(reportScroll, reportScroll._ks, {})
                    if (glide) {
                        reportGlide.from = glide.from
                        reportGlide.to = glide.to
                        reportGlide.restart()
                    }
                }
            }
            SpringAnimation {
                id: reportGlide
                target: reportScroll
                property: "contentY"
                spring: 18
                damping: ThemeService.momentumDamping
                epsilon: 0.25
            }

            Column {
                id: reportColumn
                x: 16
                y: 10
                width: reportScroll.width - 32
                spacing: 12

                Row {
                    width: parent.width
                    height: 58
                    spacing: 10
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "SCENARIO"
                        value: root.stanceLabel(root.analysisResult.stance)
                        valueColor: root.analysisResult.stance === "bullish" ? root.positiveColor
                            : (root.analysisResult.stance === "bearish" ? root.negativeColor : "#0a84ff")
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "CONFIDENCE"
                        value: Number(root.analysisResult.rawConfidence || root.analysisResult.confidence)
                            !== Number(root.analysisResult.confidence)
                            ? Number(root.analysisResult.confidence || 0) + "% · raw "
                                + Number(root.analysisResult.rawConfidence || 0) + "%"
                            : Number(root.analysisResult.confidence || 0) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "UP / FLAT / DOWN"
                        value: Number(root.analysisResult.upProbability || 0) + " / "
                            + Number(root.analysisResult.flatProbability || 0) + " / "
                            + Number(root.analysisResult.downProbability || 0)
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "SOURCES"
                        value: Number(root.analysisResult.newsCount || 0) + " news · "
                            + Number((root.analysisResult.newsContext || {}).sourceCount || 0) + " src"
                    }
                }

                ReportSection {
                    width: parent.width
                    title: "Summary"
                    body: root.analysisResult.summary || "No summary available."
                    accent: "#0a84ff"
                }

                ReportSection {
                    visible: root.analysisResult.providerStatus !== undefined
                    width: parent.width
                    title: "Provider Status"
                    body: {
                        let status = root.analysisResult.providerStatus || ({})
                        let effective = status.effective || []
                        let completed = []
                        for (let i = 0; i < effective.length; ++i)
                            completed.push(StockService.providerLabel(effective[i]))
                        let message = "Completed · " + (completed.length > 0 ? completed.join(" + ") : "Unknown")
                        let failures = status.failures || []
                        for (let j = 0; j < failures.length; ++j) {
                            let failure = failures[j]
                            message += "  |  " + StockService.providerLabel(failure.provider)
                                + " unavailable · " + failure.message
                        }
                        return message
                    }
                    accent: (root.analysisResult.providerStatus || {}).degraded
                        ? "#ff9f0a" : root.positiveColor
                }

                ReportSection {
                    visible: Number((root.analysisResult.analysisUsage || {}).calls || 0) > 0
                    width: parent.width
                    title: "Token Usage"
                    body: {
                        let usage = root.analysisResult.analysisUsage || ({})
                        return Number(usage.calls || 0) + " API call"
                            + (Number(usage.calls || 0) === 1 ? "" : "s")
                            + " · input " + root.formatTokenCount(usage.billableInputTokens)
                            + " · output " + root.formatTokenCount(usage.outputTokens)
                            + " · total " + root.formatTokenCount(usage.totalTokens)
                            + (Number(usage.cachedInputTokens || 0) > 0
                                ? " · cached " + root.formatTokenCount(usage.cachedInputTokens) : "")
                            + (Number(usage.reasoningTokens || 0) > 0
                                ? " · reasoning " + root.formatTokenCount(usage.reasoningTokens) : "")
                    }
                    accent: "#64d2ff"
                }

                ReportSection {
                    width: parent.width
                    title: "Historical Confidence Calibration"
                    body: {
                        let calibration = root.analysisResult.calibrationAdjustment || ({})
                        if (calibration.status === "applied")
                            return "Adjusted " + calibration.rawConfidence + "% → "
                                + calibration.adjustedConfidence + "% using " + calibration.qualified
                                + " qualified predictions · hit " + Number(calibration.qualifiedHitRate || 0).toFixed(1)
                                + "% · Brier " + Number(calibration.qualifiedBrierScore || 0).toFixed(3)
                        if (calibration.status === "validated")
                            return "No reduction required · " + calibration.qualified
                                + " qualified predictions · hit "
                                + Number(calibration.qualifiedHitRate || 0).toFixed(1) + "%"
                        return "Not applied · " + Number(calibration.qualified || 0)
                            + " of " + Number(calibration.minimumSamples || 5)
                            + " required resolved qualified predictions"
                    }
                    accent: (root.analysisResult.calibrationAdjustment || {}).status === "applied"
                        ? "#ff9f0a" : ((root.analysisResult.calibrationAdjustment || {}).status === "validated"
                        ? root.positiveColor : root.secondaryColor)
                }

                ReportSection {
                    width: parent.width
                    title: "Ensemble Agreement"
                    body: {
                        let agreement = root.analysisResult.ensembleAgreement || ({})
                        if (agreement.status === "single_model")
                            return "Single provider · cross-model agreement is unavailable"
                        let label = agreement.status === "high" ? "High"
                            : (agreement.status === "mixed" ? "Mixed" : "Low")
                        return label + " agreement · score " + Number(agreement.agreementScore || 0)
                            + "/100 · probability disagreement "
                            + Number(agreement.probabilityDisagreement || 0).toFixed(1) + "pp · confidence "
                            + Number(agreement.originalConfidence || 0) + "% → "
                            + Number(agreement.adjustedConfidence || 0) + "%"
                            + (agreement.directConflict ? " · bullish/bearish conflict" : "")
                    }
                    accent: (root.analysisResult.ensembleAgreement || {}).status === "high"
                        ? root.positiveColor : ((root.analysisResult.ensembleAgreement || {}).status === "low"
                        ? root.negativeColor : ((root.analysisResult.ensembleAgreement || {}).status === "mixed"
                        ? "#ff9f0a" : root.secondaryColor))
                }

                ReportSection {
                    width: parent.width
                    title: "Historical Model Weighting"
                    body: {
                        let weighting = root.analysisResult.modelWeighting || ({})
                        let models = weighting.models || []
                        if (models.length === 0)
                            return "No model performance history is available."
                        let parts = []
                        for (let i = 0; i < models.length; ++i) {
                            let model = models[i]
                            parts.push(model.model + " " + Number(model.share || 0).toFixed(1)
                                + "% · n" + Number(model.qualified || 0)
                                + (model.qualified > 0 ? " · hit "
                                    + Number(model.qualifiedHitRate || 0).toFixed(1) + "%" : ""))
                        }
                        let prefix = weighting.status === "applied" ? "Applied"
                            : (weighting.status === "equal" ? "Equal weights"
                            : (weighting.status === "single_model" ? "Single model" : "Not applied"))
                        return prefix + " · " + parts.join("  |  ")
                    }
                    accent: (root.analysisResult.modelWeighting || {}).status === "applied"
                        ? "#0a84ff" : ((root.analysisResult.modelWeighting || {}).status === "limited"
                        ? "#ff9f0a" : root.secondaryColor)
                }

                Row {
                    width: parent.width
                    spacing: 12
                    ReportSection {
                        width: (parent.width - 12) / 2
                        title: "Chart Signal"
                        body: root.analysisResult.chartSignal || "No chart signal available."
                        accent: root.movementColor
                    }
                    ReportSection {
                        width: (parent.width - 12) / 2
                        title: "News Signal"
                        body: root.analysisResult.newsSignal || "No news signal available."
                        accent: "#bf5af2"
                    }
                }

                ReportSection {
                    width: parent.width
                    title: "News Evidence Quality"
                    body: {
                        let context = root.analysisResult.newsContext || ({})
                        let status = context.status === "usable" ? "Usable"
                            : (context.status === "limited" ? "Limited" : "Insufficient")
                        return status + " · quality " + Number(context.qualityScore || 0) + "/100 · "
                            + Number(context.headlineCount || 0) + " unique headlines · "
                            + Number(context.sourceCount || 0) + " sources · "
                            + Number(context.recent24h || 0) + " within 24h · median age "
                            + Number(context.medianAgeHours || 0).toFixed(1) + "h"
                    }
                    accent: (root.analysisResult.newsContext || {}).status === "usable"
                        ? root.positiveColor : ((root.analysisResult.newsContext || {}).status === "limited"
                        ? "#ff9f0a" : root.secondaryColor)
                }

                Text {
                    text: "Chart Metrics"
                    color: root.foregroundColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Row {
                    width: parent.width
                    spacing: 10
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "20D RETURN"
                        value: StockService.signed((root.analysisResult.features || {}).periodReturnPct, 2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "MA SPREAD"
                        value: StockService.signed((root.analysisResult.features || {}).maSpreadPct, 2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "20D ANN VOL"
                        value: Number((root.analysisResult.features || {}).sampleVolatilityPct || 0).toFixed(2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "RSI 14"
                        value: Number((root.analysisResult.features || {}).rsi14 || 0).toFixed(1)
                    }
                }

                Row {
                    width: parent.width
                    spacing: 10
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "60D RETURN"
                        value: StockService.signed((root.analysisResult.features || {}).return60dPct, 2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "PRICE / MA60"
                        value: StockService.signed((root.analysisResult.features || {}).priceVsMa60Pct, 2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "60D DRAWDOWN"
                        value: Number((root.analysisResult.features || {}).maxDrawdown60dPct || 0).toFixed(2) + "%"
                        valueColor: root.negativeColor
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "TREND REGIME"
                        value: root.stanceLabel((root.analysisResult.features || {}).trendRegime)
                    }
                }

                Text {
                    text: "Walk-forward Evidence"
                    color: root.foregroundColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Row {
                    width: parent.width
                    spacing: 10
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "HIT RATE"
                        value: Number((root.analysisResult.evidence || {}).hitRate || 0) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "SAMPLES"
                        value: Number((root.analysisResult.evidence || {}).sampleCount || 0).toString()
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "TEST RETURN"
                        value: StockService.signed((root.analysisResult.evidence || {}).strategyReturnPct, 2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: "MAX DRAWDOWN"
                        value: "-" + Math.abs(Number((root.analysisResult.evidence || {}).maxDrawdownPct || 0)).toFixed(2) + "%"
                        valueColor: root.negativeColor
                    }
                }

                Row {
                    width: parent.width
                    spacing: 12
                    ReportList {
                        width: (parent.width - 12) / 2
                        title: "Catalysts"
                        entries: root.analysisResult.catalysts || []
                        accent: root.positiveColor
                        emptyText: "No catalysts identified."
                    }
                    ReportList {
                        width: (parent.width - 12) / 2
                        title: "Risks"
                        entries: root.analysisResult.risks || []
                        accent: root.negativeColor
                        emptyText: "No risks identified."
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    Text {
                        text: "Recent News Evidence"
                        color: root.foregroundColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Repeater {
                        model: root.analysisResult.news || []
                        delegate: Rectangle {
                            required property var modelData
                            width: reportColumn.width
                            height: 42
                            radius: 10
                            color: root.raisedColor
                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 11
                                anchors.rightMargin: 11
                                spacing: 10
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 5
                                    height: 5
                                    radius: 2.5
                                    color: "#bf5af2"
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - 15
                                    spacing: 1
                                    Text {
                                        width: parent.width
                                        text: modelData.title || "Untitled"
                                        color: root.foregroundColor
                                        font.family: "SF Pro Display"
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: (modelData.source || "Unknown source")
                                            + (root.analysisTime(modelData.publishedAt) !== "" ? " · " + root.analysisTime(modelData.publishedAt) : "")
                                        color: root.secondaryColor
                                        font.family: "SF Pro Display"
                                        font.pixelSize: 9
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        visible: (root.analysisResult.news || []).length === 0
                        text: "No recent headlines were available."
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                    }
                }

                Text {
                    width: parent.width
                    text: (root.analysisMessage || "AI scenario only; not investment advice or an order signal.")
                        + "  Models: " + ((root.analysisResult.models || []).join(" · ") || "Unknown")
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 9
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                }
            }
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; top: reportScroll.top }
            height: 18
            visible: reportScroll.contentY > 1
            gradient: Gradient {
                GradientStop { position: 0.0; color: analysisReport.color }
                GradientStop { position: 1.0; color: "transparent" }
            }
            opacity: Math.min(1, reportScroll.contentY / 14)
            Behavior on opacity { AppleSpring { spring: 22 } }
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

    component ReportSection: Rectangle {
        id: reportSection
        property string title: ""
        property string body: ""
        property color accent: "#0a84ff"
        height: sectionColumn.implicitHeight + 20
        radius: 11
        color: root.raisedColor
        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 9
            Rectangle {
                width: 3
                height: parent.height
                radius: 1.5
                color: reportSection.accent
            }
            Column {
                id: sectionColumn
                width: parent.width - 12
                spacing: 4
                Text {
                    text: reportSection.title
                    color: root.foregroundColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: reportSection.body
                    color: root.secondaryColor
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                    lineHeight: 1.25
                }
            }
        }
    }

    component ReportList: Rectangle {
        id: reportList
        property string title: ""
        property var entries: []
        property color accent: "#0a84ff"
        property string emptyText: ""
        height: listColumn.implicitHeight + 20
        radius: 11
        color: root.raisedColor
        Column {
            id: listColumn
            anchors.fill: parent
            anchors.margins: 10
            spacing: 5
            Text {
                text: reportList.title
                color: root.foregroundColor
                font.family: "SF Pro Display"
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
            Repeater {
                model: reportList.entries
                delegate: Row {
                    required property var modelData
                    width: listColumn.width
                    spacing: 7
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        width: 5
                        height: 5
                        radius: 2.5
                        color: reportList.accent
                    }
                    Text {
                        width: parent.width - 12
                        text: String(modelData)
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                        lineHeight: 1.2
                    }
                }
            }
            Text {
                visible: reportList.entries.length === 0
                width: parent.width
                text: reportList.emptyText
                color: root.secondaryColor
                font.family: "SF Pro Display"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
            }
        }
    }
}
