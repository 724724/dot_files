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

    function relationClassLabel(item) {
        switch (String((item || {}).relationClass || "")) {
        case "company": return root.t((item || {}).materialEvent ? "Company event" : "Company context");
        case "product": return root.t("Product");
        case "supply_chain": return root.t("Supply chain");
        case "competitor": return root.t("Competitor");
        case "regulation": return root.t("Regulation");
        case "macro": return root.t("Macro");
        case "industry": return root.t("Industry");
        default: return root.t((item || {}).relationType === "theme" ? "Industry" : "Company");
        }
    }

    function behaviorLevel(value) {
        let level = String(value || "low");
        return root.t(level.charAt(0).toUpperCase() + level.slice(1));
    }

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
            text: root.t("AI Scenario Report")
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
                let result = root.t("%1 · %2", [
                    root.snapshot.name || root.symbol,
                    root.analysisResult.horizon || root.t("1–5 trading days")
                ])
                if (context.label)
                    result += root.t(" · %1 · %2 sessions", [root.t(context.label), Number(context.sampleCount || 0)])
                return result
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
                        title: root.t("SCENARIO")
                        value: root.stanceLabel(root.analysisResult.stance)
                        valueColor: root.analysisResult.stance === "bullish" ? root.positiveColor
                            : (root.analysisResult.stance === "bearish" ? root.negativeColor : "#0a84ff")
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("CONFIDENCE")
                        value: Number(root.analysisResult.rawConfidence || root.analysisResult.confidence)
                            !== Number(root.analysisResult.confidence)
                            ? root.t("%1% · raw %2%", [
                                Number(root.analysisResult.confidence || 0),
                                Number(root.analysisResult.rawConfidence || 0)
                            ])
                            : Number(root.analysisResult.confidence || 0) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("UP / FLAT / DOWN")
                        value: Number(root.analysisResult.upProbability || 0) + " / "
                            + Number(root.analysisResult.flatProbability || 0) + " / "
                            + Number(root.analysisResult.downProbability || 0)
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("SOURCES")
                        value: root.t("%1 news · %2 sources", [
                            Number(root.analysisResult.newsCount || 0),
                            Number((root.analysisResult.newsContext || {}).sourceCount || 0)
                        ])
                    }
                }

                ReportSection {
                    visible: Number((root.analysisResult.behaviorContext || {}).version || 0) > 0
                    width: parent.width
                    title: root.t("Market Psychology & Risk")
                    body: {
                        let behavior = root.analysisResult.behaviorContext || ({})
                        let attention = behavior.attention || ({})
                        let crowding = behavior.crowding || ({})
                        let overreaction = behavior.overreaction || ({})
                        let negativity = behavior.negativity || ({})
                        let disagreement = behavior.disagreement || ({})
                        let confidence = Number(behavior.evidenceConfidence || behavior.confidence || 0)
                        let adjusted = Number(behavior.riskAdjustedEvidenceConfidence || confidence)
                        let message = root.t("Evidence %1/100 · risk-adjusted %2/100 · risk penalty %3/100", [
                            confidence, adjusted, Number(behavior.riskPenalty || 0)
                        ])
                        message += "\n" + root.t("Attention %1/100 (%2) · crowding %3/100 (%4) · negativity %5/100 (%6)", [
                            Number(attention.score || 0), sheet.behaviorLevel(attention.level),
                            Number(crowding.score || 0), sheet.behaviorLevel(crowding.level),
                            Number(negativity.score || 0), sheet.behaviorLevel(negativity.level)
                        ])
                        message += "\n" + root.t("Overreaction %1/100 · disagreement %2/100 · risk signals are not trade directions.", [
                            Number(overreaction.score || 0), Number(disagreement.score || 0)
                        ])
                        return message
                    }
                    accent: Number((root.analysisResult.behaviorContext || {}).riskPenalty || 0) >= 70
                        ? root.negativeColor : (Number((root.analysisResult.behaviorContext || {}).riskPenalty || 0) >= 40
                        ? "#ff9f0a" : "#bf5af2")
                }

                ReportSection {
                    width: parent.width
                    title: root.t("Summary")
                    body: root.analysisResult.summary || root.t("No summary available.")
                    accent: "#0a84ff"
                }

                ReportSection {
                    visible: root.analysisResult.providerStatus !== undefined
                    width: parent.width
                    title: root.t("Provider Status")
                    body: {
                        let status = root.analysisResult.providerStatus || ({})
                        let effective = status.effective || []
                        let completed = []
                        for (let i = 0; i < effective.length; ++i)
                            completed.push(root.t(StockService.providerLabel(effective[i])))
                        let message = root.t("Completed · %1", [
                            completed.length > 0 ? completed.join(" + ") : root.t("Unknown")
                        ])
                        let failures = status.failures || []
                        for (let j = 0; j < failures.length; ++j) {
                            let failure = failures[j]
                            message += "  |  " + root.t("%1 unavailable · %2", [
                                root.t(StockService.providerLabel(failure.provider)), root.t(failure.message)
                            ])
                        }
                        return message
                    }
                    accent: (root.analysisResult.providerStatus || {}).degraded
                        ? "#ff9f0a" : root.positiveColor
                }

                ReportSection {
                    visible: Number((root.analysisResult.analysisUsage || {}).calls || 0) > 0
                    width: parent.width
                    title: root.t("Token Usage")
                    body: {
                        let usage = root.analysisResult.analysisUsage || ({})
                        let message = root.t("%1 API calls · input %2 · output %3 · total %4", [
                            Number(usage.calls || 0),
                            root.formatTokenCount(usage.billableInputTokens),
                            root.formatTokenCount(usage.outputTokens),
                            root.formatTokenCount(usage.totalTokens)
                        ])
                        if (Number(usage.cachedInputTokens || 0) > 0)
                            message += root.t(" · cached %1", [root.formatTokenCount(usage.cachedInputTokens)])
                        if (Number(usage.reasoningTokens || 0) > 0)
                            message += root.t(" · reasoning %1", [root.formatTokenCount(usage.reasoningTokens)])
                        return message
                    }
                    accent: "#64d2ff"
                }

                ReportSection {
                    width: parent.width
                    title: root.t("Historical Confidence Calibration")
                    body: {
                        let calibration = root.analysisResult.calibrationAdjustment || ({})
                        if (calibration.status === "applied")
                            return root.t("Adjusted %1% → %2% using %3 qualified predictions · hit %4% · Brier %5", [
                                calibration.rawConfidence,
                                calibration.adjustedConfidence,
                                calibration.qualified,
                                Number(calibration.qualifiedHitRate || 0).toFixed(1),
                                Number(calibration.qualifiedBrierScore || 0).toFixed(3)
                            ])
                        if (calibration.status === "validated")
                            return root.t("No reduction required · %1 qualified predictions · hit %2%", [
                                calibration.qualified,
                                Number(calibration.qualifiedHitRate || 0).toFixed(1)
                            ])
                        return root.t("Not applied · %1 of %2 required resolved qualified predictions", [
                            Number(calibration.qualified || 0),
                            Number(calibration.minimumSamples || 5)
                        ])
                    }
                    accent: (root.analysisResult.calibrationAdjustment || {}).status === "applied"
                        ? "#ff9f0a" : ((root.analysisResult.calibrationAdjustment || {}).status === "validated"
                        ? root.positiveColor : root.secondaryColor)
                }

                ReportSection {
                    width: parent.width
                    title: root.t("Ensemble Agreement")
                    body: {
                        let agreement = root.analysisResult.ensembleAgreement || ({})
                        if (agreement.status === "single_model")
                            return root.t("Single provider · cross-model agreement is unavailable")
                        let label = agreement.status === "high" ? root.t("High")
                            : (agreement.status === "mixed" ? root.t("Mixed") : root.t("Low"))
                        let message = root.t("%1 agreement · score %2/100 · probability disagreement %3pp · confidence %4% → %5%", [
                            label,
                            Number(agreement.agreementScore || 0),
                            Number(agreement.probabilityDisagreement || 0).toFixed(1),
                            Number(agreement.originalConfidence || 0),
                            Number(agreement.adjustedConfidence || 0)
                        ])
                        if (agreement.directConflict) message += root.t(" · bullish/bearish conflict")
                        return message
                    }
                    accent: (root.analysisResult.ensembleAgreement || {}).status === "high"
                        ? root.positiveColor : ((root.analysisResult.ensembleAgreement || {}).status === "low"
                        ? root.negativeColor : ((root.analysisResult.ensembleAgreement || {}).status === "mixed"
                        ? "#ff9f0a" : root.secondaryColor))
                }

                ReportSection {
                    width: parent.width
                    title: root.t("Historical Model Weighting")
                    body: {
                        let weighting = root.analysisResult.modelWeighting || ({})
                        let models = weighting.models || []
                        if (models.length === 0)
                            return root.t("No model performance history is available.")
                        let parts = []
                        for (let i = 0; i < models.length; ++i) {
                            let model = models[i]
                            let part = root.t("%1 %2% · n%3", [
                                model.model,
                                Number(model.share || 0).toFixed(1),
                                Number(model.qualified || 0)
                            ])
                            if (model.qualified > 0)
                                part += root.t(" · hit %1%", [Number(model.qualifiedHitRate || 0).toFixed(1)])
                            parts.push(part)
                        }
                        let prefix = weighting.status === "applied" ? root.t("Applied")
                            : (weighting.status === "equal" ? root.t("Equal weights")
                            : (weighting.status === "single_model" ? root.t("Single model") : root.t("Not applied")))
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
                        title: root.t("Chart Signal")
                        body: root.analysisResult.chartSignal || root.t("No chart signal available.")
                        accent: root.movementColor
                    }
                    ReportSection {
                        width: (parent.width - 12) / 2
                        title: root.t("News Signal")
                        body: root.analysisResult.newsSignal || root.t("No news signal available.")
                        accent: "#bf5af2"
                    }
                }

                ReportSection {
                    width: parent.width
                    title: root.t("News Evidence Quality")
                    body: {
                        let context = root.analysisResult.newsContext || ({})
                        let status = context.status === "usable" ? root.t("Usable")
                            : (context.status === "limited" ? root.t("Limited") : root.t("Insufficient"))
                        let message = root.t("%1 · evidence quality %2/100 · source quality %3/100 · %4 verified company events", [
                            status,
                            Number(context.qualityScore || 0),
                            Number(context.sourceQualityScore || 0),
                            Number(context.verifiedDirectCount || 0)
                        ])
                        message += "\n" + root.t("%1 independent events · %2 sources · %3 syndicated copies · %4 within 24h · median age %5h", [
                            Number(context.independentEventCount || context.headlineCount || 0),
                            Number(context.sourceCount || 0),
                            Number(context.syndicatedCopyCount || 0),
                            Number(context.recent24h || 0),
                            Number(context.medianAgeHours || 0).toFixed(1)
                        ])
                        message += " · " + (context.cacheSource === "stock-news-widget"
                            ? root.t("Shared news cache") : root.t("Remote news"))
                        return message
                    }
                    accent: (root.analysisResult.newsContext || {}).status === "usable"
                        ? root.positiveColor : ((root.analysisResult.newsContext || {}).status === "limited"
                        ? "#ff9f0a" : root.secondaryColor)
                }

                Text {
                    text: root.t("Chart Metrics")
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
                        title: root.t("20D RETURN")
                        value: StockService.signed((root.analysisResult.features || {}).periodReturnPct, 2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("MA SPREAD")
                        value: StockService.signed((root.analysisResult.features || {}).maSpreadPct, 2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("20D ANN VOL")
                        value: Number((root.analysisResult.features || {}).sampleVolatilityPct || 0).toFixed(2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("RSI 14")
                        value: Number((root.analysisResult.features || {}).rsi14 || 0).toFixed(1)
                    }
                }

                Row {
                    width: parent.width
                    spacing: 10
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("60D RETURN")
                        value: StockService.signed((root.analysisResult.features || {}).return60dPct, 2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("PRICE / MA60")
                        value: StockService.signed((root.analysisResult.features || {}).priceVsMa60Pct, 2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("60D DRAWDOWN")
                        value: Number((root.analysisResult.features || {}).maxDrawdown60dPct || 0).toFixed(2) + "%"
                        valueColor: root.negativeColor
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("TREND REGIME")
                        value: root.stanceLabel((root.analysisResult.features || {}).trendRegime)
                    }
                }

                Text {
                    text: root.t("Walk-forward Evidence")
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
                        title: root.t("HIT RATE")
                        value: Number((root.analysisResult.evidence || {}).hitRate || 0) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("SAMPLES")
                        value: Number((root.analysisResult.evidence || {}).sampleCount || 0).toString()
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("TEST RETURN")
                        value: StockService.signed((root.analysisResult.evidence || {}).strategyReturnPct, 2) + "%"
                    }
                    ReportMetric {
                        width: (parent.width - 30) / 4
                        title: root.t("MAX DRAWDOWN")
                        value: "-" + Math.abs(Number((root.analysisResult.evidence || {}).maxDrawdownPct || 0)).toFixed(2) + "%"
                        valueColor: root.negativeColor
                    }
                }

                Row {
                    width: parent.width
                    spacing: 12
                    ReportList {
                        width: (parent.width - 12) / 2
                        title: root.t("Catalysts")
                        entries: root.analysisResult.catalysts || []
                        accent: root.positiveColor
                        emptyText: root.t("No catalysts identified.")
                    }
                    ReportList {
                        width: (parent.width - 12) / 2
                        title: root.t("Risks")
                        entries: root.analysisResult.risks || []
                        accent: root.negativeColor
                        emptyText: root.t("No risks identified.")
                    }
                }

                Column {
                    width: parent.width
                    spacing: 6
                    Text {
                        text: root.t("Recent News Evidence")
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
                                        text: modelData.title || root.t("Untitled")
                                        color: root.foregroundColor
                                        font.family: "SF Pro Display"
                                        font.pixelSize: 10
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: parent.width
                                        text: sheet.relationClassLabel(modelData)
                                            + " · " + (modelData.source || root.t("Unknown source"))
                                            + (root.analysisTime(modelData.publishedAt) !== "" ? " · " + root.analysisTime(modelData.publishedAt) : "")
                                            + (((modelData.duplicateSources || []).length > 1)
                                                ? " · " + root.t("%1 reporting sources", [(modelData.duplicateSources || []).length]) : "")
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
                        text: root.t("No recent headlines were available.")
                        color: root.secondaryColor
                        font.family: "SF Pro Display"
                        font.pixelSize: 10
                    }
                }

                Text {
                    width: parent.width
                    text: root.t("%1  Models: %2", [
                        root.analysisMessage ? root.t(root.analysisMessage) : root.t("AI scenario only; not investment advice or an order signal."),
                        (root.analysisResult.models || []).join(" · ") || root.t("Unknown")
                    ])
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
