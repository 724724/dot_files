import QtQuick
import QtQuick.Controls
import Quickshell.Io

Item {
    id: ed
    property int index: -1
    property int layout: 1
    property string language: "ko"
    property string symbol: "005930"
    property string market: "KRX"
    property string range: "1D"
    property string aiProvider: "none"
    property string analysisProfile: "balanced"
    property string dataMode: "demo"
    property string kisEnvironment: "paper"
    property bool productionTradingEnabled: false
    property var credentialState: ({ keychain: false, kisProd: false, kisPaper: false, kisProdAccount: false, kisPaperAccount: false, openai: false, claude: false, productionTradingEnabled: false })
    property string pendingSecret: ""
    property var pendingField: null
    property string credentialMessage: ""
    property string modelMessage: ""
    property var riskPolicy: ({ productionEnabled: false, maxOrderValueKrw: 1000000, maxDailyBuyValueKrw: 3000000, maxBuyOrdersPerDay: 5, maxPositionPercent: 25 })
    property string pendingRisk: ""
    property bool riskWritePending: false
    property var queuedRiskPatch: ({})
    property var automationPolicy: ({ maxOrderValueKrw: 100000, maxDailyNewExposureKrw: 200000, maxOrdersPerDay: 2, maxPositionPercent: 5, cashReservePercent: 70, maxPositionLossPercent: 3, trailingActivationPercent: 5, trailingStopPercent: 2, maxRiskPerTradePercent: 0.25, volatilityRiskMultiplier: 2, maxSectorExposurePercent: 15, maxCorrelationCoefficient: 0.85, maxPortfolioVar95Percent: 2, maxPortfolioCvar95Percent: 3, maxStressLossPercent: 8, maxSingleDayLossPercent: 5, maxMarketParticipationPercent: 0.1, maxBidAskSpreadBps: 20, maxPriceDriftPercent: 0.5, maxPendingOrderSeconds: 120, maxMarketDataAgeSeconds: 30, maxPlanAgeSeconds: 90, krxCommissionBps: 1.5, krxSellTaxBps: 15, usCommissionBps: 25, usSellFeeBps: 1, assumedSlippageBps: 5, notificationsEnabled: true })
    property string pendingAutomationPolicy: ""
    property bool automationPolicyWritePending: false
    property var queuedAutomationPolicyPatch: ({})
    property string automationPolicyMessage: ""
    property bool backgroundEnabled: false
    property bool backgroundTargetEnabled: false
    property bool backgroundInstalled: false
    property bool backgroundStatusKnown: false
    property bool backgroundBusy: false
    property bool backgroundFailed: false
    property string backgroundAction: "status"
    property string backgroundMessage: "Checking background monitoring…"

    implicitWidth: 440
    implicitHeight: col.implicitHeight

    readonly property bool kisConfigured: kisEnvironment === "prod" ? !!credentialState.kisProd : !!credentialState.kisPaper
    readonly property bool kisAccountConfigured: kisEnvironment === "prod" ? !!credentialState.kisProdAccount : !!credentialState.kisPaperAccount

    onIndexChanged: reload()
    Component.onCompleted: {
        reload()
        refreshCredentialState()
        refreshRiskPolicy()
        refreshAutomationPolicy()
        refreshBackgroundStatus()
    }

    Connections {
        target: StockService
        function onCredentialsChanged() {
            ed.refreshCredentialState()
            ed.refreshModelCatalog(true)
        }
        function onRiskPolicyChanged() { ed.refreshRiskPolicy() }
        function onAutomationPolicyChanged() { ed.refreshAutomationPolicy() }
    }

    Process {
        id: statusProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text || "{}")
                    if (result.status === "ok") {
                        ed.credentialState = result
                        if (ed.credentialMessage === "Checking keychain…") ed.credentialMessage = ""
                        ed.refreshModelCatalog(false)
                    } else {
                        ed.credentialMessage = result.message || "Keychain unavailable"
                    }
                } catch (error) {
                    ed.credentialMessage = "Could not read keychain status"
                }
            }
        }
    }

    Process {
        id: saveProcess
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text || "{}")
                    if (result.status !== "ok") throw new Error(result.message || "Save failed")
                    if (ed.pendingField) ed.pendingField.text = ""
                    ed.credentialMessage = "Saved to the system keychain"
                    StockService.credentialsChanged()
                } catch (error) {
                    ed.credentialMessage = error.message || "Could not save credential"
                }
                ed.pendingField = null
            }
        }
        onStarted: {
            saveProcess.write(ed.pendingSecret + "\n")
            ed.pendingSecret = ""
        }
    }

    Process {
        id: modelProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text || "{}")
                    if (result.status !== "ok") throw new Error(result.message || "Model sync failed")
                    StockService.updateModelCatalog(result)
                    ed.modelMessage = StockService.modelCatalogState()
                } catch (error) {
                    ed.modelMessage = error.message || "Model sync failed"
                }
            }
        }
        onRunningChanged: if (running) ed.modelMessage = "Syncing models…"
    }

    Process {
        id: riskProcess
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text || "{}")
                    if (result.status !== "ok") throw new Error(result.message || "Risk policy unavailable")
                    ed.riskPolicy = result
                    ed.productionTradingEnabled = !!result.productionEnabled
                    ed.save({ productionTradingEnabled: ed.productionTradingEnabled })
                    if (ed.riskWritePending) {
                        ed.credentialMessage = "Risk policy saved"
                        ed.riskWritePending = false
                        StockService.riskPolicyChanged()
                    }
                } catch (error) {
                    ed.credentialMessage = error.message || "Risk policy unavailable"
                    ed.riskWritePending = false
                }
            }
        }
        onStarted: {
            if (ed.pendingRisk !== "") {
                riskProcess.write(ed.pendingRisk + "\n")
                ed.pendingRisk = ""
            }
        }
        onExited: {
            if (Object.keys(ed.queuedRiskPatch).length > 0) {
                let patch = ed.queuedRiskPatch
                ed.queuedRiskPatch = ({})
                ed.updateRiskPolicy(patch)
            }
        }
    }

    Process {
        id: automationPolicyProcess
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text || "{}")
                    if (result.status !== "ok") throw new Error(result.message || "Automation policy unavailable")
                    ed.automationPolicy = result.policy || ({})
                    ed.automationPolicyMessage = ed.automationPolicyWritePending
                        ? "Paper protection settings saved" : ""
                    if (ed.automationPolicyWritePending) StockService.automationPolicyChanged()
                } catch (error) {
                    ed.automationPolicyMessage = error.message || "Automation policy unavailable"
                }
                ed.automationPolicyWritePending = false
            }
        }
        onStarted: {
            if (ed.pendingAutomationPolicy !== "") {
                automationPolicyProcess.write(ed.pendingAutomationPolicy + "\n")
                ed.pendingAutomationPolicy = ""
            }
        }
        onExited: {
            if (Object.keys(ed.queuedAutomationPolicyPatch).length > 0) {
                let patch = ed.queuedAutomationPolicyPatch
                ed.queuedAutomationPolicyPatch = ({})
                ed.updateAutomationPolicy(patch)
            }
        }
    }

    Process {
        id: backgroundProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text || "{}")
                    if (result.status !== "ok") throw new Error(result.message || "Background monitoring unavailable")
                    ed.backgroundEnabled = !!result.enabled
                    ed.backgroundInstalled = !!result.installed
                    ed.backgroundStatusKnown = true
                    ed.backgroundFailed = false
                    if (ed.backgroundAction === "status") ed.backgroundTargetEnabled = ed.backgroundEnabled
                    ed.backgroundMessage = result.message || (ed.backgroundEnabled
                        ? "Runs every minute while enabled"
                        : "Off · no periodic CPU or network wake-ups")
                } catch (error) {
                    ed.backgroundFailed = true
                    ed.backgroundTargetEnabled = ed.backgroundEnabled
                    ed.backgroundMessage = error.message || "Background monitoring unavailable"
                }
            }
        }
        onRunningChanged: ed.backgroundBusy = running
        onExited: {
            if (!ed.backgroundFailed && ed.backgroundStatusKnown
                    && ed.backgroundTargetEnabled !== ed.backgroundEnabled) {
                Qt.callLater(ed.applyBackgroundTarget)
            }
        }
    }

    function reload() {
        if (index === -1) return
        let data = WidgetsService.getData(index)
        layout = Number(data.layout || 1)
        language = data.language === "en" ? "en" : "ko"
        symbol = data.symbol || "005930"
        market = data.market || "KRX"
        range = data.range || "1D"
        aiProvider = data.aiProvider || "none"
        analysisProfile = data.analysisProfile || "balanced"
        dataMode = data.dataMode || "demo"
        kisEnvironment = data.kisEnvironment || "paper"
        productionTradingEnabled = !!data.productionTradingEnabled
    }

    function save(patch) {
        if (index !== -1) WidgetsService.setData(index, patch)
    }

    function t(source, values) { return StockStrings.text(language, source, values) }

    function refreshCredentialState() {
        if (statusProcess.running) return
        credentialMessage = "Checking keychain…"
        statusProcess.command = ["python3", StockService.stockScript, "credentials", "status"]
        statusProcess.running = true
    }

    function storeCredential(key, value, field) {
        if (saveProcess.running || !value || value.trim() === "") return
        pendingSecret = value.trim()
        pendingField = field
        credentialMessage = "Saving securely…"
        saveProcess.command = ["python3", StockService.stockScript, "credentials", "set", key]
        saveProcess.running = true
    }

    function refreshModelCatalog(force) {
        if (modelProcess.running || (!credentialState.openai && !credentialState.claude)) return
        modelProcess.command = ["python3", StockService.stockScript, "models", "both", force ? "force" : "cache"]
        modelProcess.running = true
    }

    function refreshRiskPolicy() {
        if (riskProcess.running) return
        riskWritePending = false
        riskProcess.command = ["python3", StockService.stockScript, "risk", "get"]
        riskProcess.running = true
    }

    function updateRiskPolicy(patch) {
        if (riskProcess.running) {
            queuedRiskPatch = Object.assign({}, queuedRiskPatch, patch)
            return
        }
        riskWritePending = true
        pendingRisk = JSON.stringify(patch)
        credentialMessage = "Saving risk policy…"
        riskProcess.command = ["python3", StockService.stockScript, "risk", "set"]
        riskProcess.running = true
    }

    function refreshAutomationPolicy() {
        if (automationPolicyProcess.running) return
        automationPolicyWritePending = false
        automationPolicyProcess.command = ["python3", StockService.stockScript, "automation", "status"]
        automationPolicyProcess.running = true
    }

    function updateAutomationPolicy(patch) {
        if (automationPolicyProcess.running) {
            queuedAutomationPolicyPatch = Object.assign({}, queuedAutomationPolicyPatch, patch)
            return
        }
        automationPolicyWritePending = true
        automationPolicyMessage = "Saving paper protection settings…"
        pendingAutomationPolicy = JSON.stringify(patch)
        automationPolicyProcess.command = ["python3", StockService.stockScript, "automation", "configure"]
        automationPolicyProcess.running = true
    }

    function refreshBackgroundStatus() {
        if (backgroundProcess.running) return
        backgroundAction = "status"
        backgroundFailed = false
        backgroundProcess.command = ["python3", StockService.stockScript, "background", "status"]
        backgroundProcess.running = true
    }

    function setBackgroundEnabled(enabled) {
        if (!backgroundStatusKnown || !backgroundInstalled) return
        backgroundTargetEnabled = enabled
        backgroundMessage = enabled ? "Starting background monitoring…" : "Stopping background monitoring…"
        if (!backgroundProcess.running) applyBackgroundTarget()
    }

    function applyBackgroundTarget() {
        if (backgroundProcess.running || backgroundTargetEnabled === backgroundEnabled) return
        backgroundAction = backgroundTargetEnabled ? "enable" : "disable"
        backgroundFailed = false
        backgroundProcess.command = ["python3", StockService.stockScript, "background", backgroundAction]
        backgroundProcess.running = true
    }

    Column {
        id: col
        width: parent.width
        spacing: 12

        Row {
            width: parent.width
            height: 24
            Text {
                text: ed.t("Stocks")
                color: "#ffffff"
                font.family: "SF Pro Display"
                font.pixelSize: 20
                font.weight: Font.DemiBold
                font.letterSpacing: -0.35
            }
            Item { width: parent.width - parent.children[0].width - keychainStatus.width; height: 1 }
            StatusBadge {
                id: keychainStatus
                anchors.verticalCenter: parent.verticalCenter
                label: ed.t(ed.credentialState.keychain ? "Keychain Ready" : "Keychain")
                ready: !!ed.credentialState.keychain
            }
        }

        OptionGroup {
            width: parent.width
            title: ed.t("Layout")
            options: [
                { id: "1", label: ed.t("Large") },
                { id: "2", label: "XXL" }
            ]
            selectedId: String(ed.layout)
            onSelected: id => {
                WidgetsService.setStockLayout(ed.index, Number(id))
                ed.reload()
            }
        }

        Column {
            width: parent.width
            spacing: 7
            LabelText { text: ed.t("Symbol") }
            Rectangle {
                width: parent.width
                height: 36
                radius: 10
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: symbolField.activeFocus ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.12)
                border.width: 1
                TextField {
                    id: symbolField
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    text: ed.symbol
                    color: "#ffffff"
                    selectionColor: "#0a84ff"
                    background: null
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                    verticalAlignment: TextInput.AlignVCenter
                    inputMethodHints: Qt.ImhUppercaseOnly
                    onEditingFinished: {
                        let value = text.trim().toUpperCase()
                        if (value === "") value = ed.market === "KRX" ? "005930" : "AAPL"
                        ed.symbol = value
                        text = value
                        ed.save({ symbol: value })
                    }
                }
            }
        }

        Row {
            width: parent.width
            spacing: 16
            OptionGroup {
                width: (parent.width - 16) / 2
                title: ed.t("Market")
                options: StockStrings.options(ed.language, StockService.marketOptions)
                selectedId: ed.market
                onSelected: id => {
                    ed.market = id
                    if (id === "KRX" && !/^\d{6}$/.test(ed.symbol)) ed.symbol = "005930"
                    if (id !== "KRX" && /^\d{6}$/.test(ed.symbol)) ed.symbol = "AAPL"
                    symbolField.text = ed.symbol
                    ed.save({ market: id, symbol: ed.symbol })
                }
            }
            OptionGroup {
                width: (parent.width - 16) / 2
                title: ed.t("Default Range")
                options: StockStrings.options(ed.language, StockService.rangeOptions)
                selectedId: ed.range
                onSelected: id => { ed.range = id; ed.save({ range: id }) }
            }
        }

        Row {
            width: parent.width
            spacing: 16
            OptionGroup {
                width: (parent.width - 16) / 2
                title: ed.t("Data Source")
                options: StockStrings.options(ed.language, StockService.dataModeOptions)
                selectedId: ed.dataMode
                onSelected: id => { ed.dataMode = id; ed.save({ dataMode: id }) }
            }
            OptionGroup {
                width: (parent.width - 16) / 2
                title: ed.t("KIS Environment")
                options: StockStrings.options(ed.language, StockService.kisEnvironmentOptions)
                selectedId: ed.kisEnvironment
                onSelected: id => {
                    ed.kisEnvironment = id
                    liveEnableField.text = ""
                    if (id !== "prod") {
                        ed.productionTradingEnabled = false
                        ed.updateRiskPolicy({ productionEnabled: false })
                    }
                    ed.save({ kisEnvironment: id, productionTradingEnabled: ed.productionTradingEnabled })
                }
            }
        }

        OptionGroup {
            width: parent.width
            title: ed.t("Language")
            options: StockStrings.languageOptions
            selectedId: ed.language
            onSelected: id => {
                ed.language = id
                ed.save({ language: id })
            }
        }

        Rectangle {
            width: parent.width
            height: 72
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.055)
            border.color: Qt.rgba(1, 1, 1, 0.10)
            border.width: 1

            Column {
                anchors.left: parent.left
                anchors.right: backgroundToggle.left
                anchors.leftMargin: 12
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Row {
                    spacing: 7
                    Text {
                        text: ed.t("Background Monitoring")
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: globalLabel.implicitWidth + 12
                        height: 18
                        radius: 6
                        color: Qt.rgba(1, 1, 1, 0.08)
                        Text {
                            id: globalLabel
                            anchors.centerIn: parent
                            text: ed.t("Global")
                            color: Qt.rgba(1, 1, 1, 0.50)
                            font.family: "SF Pro Display"
                            font.pixelSize: 8
                            font.weight: Font.DemiBold
                        }
                    }
                }
                Text {
                    width: parent.width
                    text: ed.t(ed.backgroundMessage)
                    color: ed.backgroundFailed ? "#ff453a" : Qt.rgba(1, 1, 1, 0.52)
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                id: backgroundToggle
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 26
                radius: 13
                color: ed.backgroundTargetEnabled ? "#30d158" : Qt.rgba(1, 1, 1, 0.16)
                opacity: ed.backgroundStatusKnown && ed.backgroundInstalled ? 1 : 0.42
                scale: backgroundToggleArea.pressed ? ThemeService.pressScale : 1
                Behavior on scale { AppleSpring { spring: 22 } }

                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    y: 3
                    x: ed.backgroundTargetEnabled ? parent.width - width - 3 : 3
                    color: "#ffffff"
                    Behavior on x { AppleSpring { spring: 22; epsilon: 0.1 } }
                }

                MouseArea {
                    id: backgroundToggleArea
                    anchors.fill: parent
                    enabled: ed.backgroundStatusKnown && ed.backgroundInstalled
                    cursorShape: Qt.PointingHandCursor
                    onPressed: ed.setBackgroundEnabled(!ed.backgroundTargetEnabled)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: paperProtection.implicitHeight + 20
            radius: 12
            color: Qt.rgba(0.04, 0.52, 1.0, 0.09)
            border.color: Qt.rgba(0.04, 0.52, 1.0, 0.18)
            border.width: 1

            Column {
                id: paperProtection
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
                spacing: 8

                Row {
                    width: parent.width
                    height: 22
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: ed.t("Paper Position Protection")
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Item { width: parent.width - parent.children[0].width - paperOnlyBadge.width; height: 1 }
                    StatusBadge {
                        id: paperOnlyBadge
                        anchors.verticalCenter: parent.verticalCenter
                        label: ed.automationPolicy.executionMode === "live" ? ed.t("Live Armed · Gated")
                            : (ed.automationPolicy.liveConsent === true ? ed.t("Live Consent · Gated") : ed.t("Paper Only · Global"))
                        ready: ed.automationPolicy.executionMode !== "live"
                    }
                }

                Text {
                    width: parent.width
                    text: ed.t("A hard stop protects open positions. New positions are sized from a per-trade loss budget and recent volatility.")
                    color: Qt.rgba(1, 1, 1, 0.58)
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: 10
                    color: Qt.rgba(1, 1, 1, 0.055)
                    border.color: Qt.rgba(1, 1, 1, 0.09)
                    border.width: 1
                    scale: operationalAlertsArea.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 22 } }
                    Column {
                        anchors.left: parent.left
                        anchors.right: operationalAlertsSwitch.left
                        anchors.leftMargin: 11
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: ed.t("Operational Alerts")
                            color: "#ffffff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: ed.t("Paper orders, protective exits, and safety failures")
                            color: Qt.rgba(1, 1, 1, 0.46)
                            font.family: "SF Pro Display"
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        id: operationalAlertsSwitch
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42
                        height: 24
                        radius: 12
                        color: ed.automationPolicy.notificationsEnabled !== false ? "#30d158" : Qt.rgba(1, 1, 1, 0.16)
                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            y: 2
                            x: ed.automationPolicy.notificationsEnabled !== false ? parent.width - width - 2 : 2
                            color: "#ffffff"
                            Behavior on x { AppleSpring { spring: 22 } }
                        }
                    }
                    MouseArea {
                        id: operationalAlertsArea
                        anchors.fill: parent
                        enabled: !automationPolicyProcess.running
                        cursorShape: Qt.PointingHandCursor
                        onPressed: ed.updateAutomationPolicy({
                            notificationsEnabled: ed.automationPolicy.notificationsEnabled === false
                        })
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 48
                    radius: 10
                    color: Qt.rgba(1, 0.27, 0.23, ed.automationPolicy.liveConsent === true ? 0.14 : 0.055)
                    border.color: Qt.rgba(1, 0.27, 0.23, 0.22)
                    border.width: 1
                    scale: liveConsentArea.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 22 } }
                    Column {
                        anchors.left: parent.left
                        anchors.right: liveConsentSwitch.left
                        anchors.leftMargin: 11
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: ed.t("Live Automation Consent")
                            color: "#ffffff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            text: ed.t("Real-money automation can lose capital. Arming still requires every verification gate.")
                            color: Qt.rgba(1, 1, 1, 0.46)
                            font.family: "SF Pro Display"
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        id: liveConsentSwitch
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 42
                        height: 24
                        radius: 12
                        color: ed.automationPolicy.liveConsent === true ? "#ff453a" : Qt.rgba(1, 1, 1, 0.16)
                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            y: 2
                            x: ed.automationPolicy.liveConsent === true ? parent.width - width - 2 : 2
                            color: "#ffffff"
                            Behavior on x { AppleSpring { spring: 22 } }
                        }
                    }
                    MouseArea {
                        id: liveConsentArea
                        anchors.fill: parent
                        enabled: !automationPolicyProcess.running
                        cursorShape: Qt.PointingHandCursor
                        onPressed: ed.updateAutomationPolicy({
                            liveConsent: ed.automationPolicy.liveConsent !== true
                        })
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Auto order limit")
                        policyKey: "maxOrderValueKrw"
                        value: Number(ed.automationPolicy.maxOrderValueKrw || 100000)
                        minimum: 10000
                        maximum: 10000000
                        decimals: 0
                        suffix: "KRW"
                    }
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Daily auto exposure")
                        policyKey: "maxDailyNewExposureKrw"
                        value: Number(ed.automationPolicy.maxDailyNewExposureKrw || 200000)
                        minimum: 10000
                        maximum: 50000000
                        decimals: 0
                        suffix: "KRW"
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 16) / 3
                        label: ed.t("Auto orders per day")
                        policyKey: "maxOrdersPerDay"
                        value: Number(ed.automationPolicy.maxOrdersPerDay || 2)
                        minimum: 1
                        maximum: 20
                        decimals: 0
                        suffix: ed.t("count")
                    }
                    AutomationPercentField {
                        width: (parent.width - 16) / 3
                        label: ed.t("Auto max position")
                        policyKey: "maxPositionPercent"
                        value: Number(ed.automationPolicy.maxPositionPercent || 5)
                        minimum: 1
                        maximum: 25
                        decimals: 0
                    }
                    AutomationPercentField {
                        width: (parent.width - 16) / 3
                        label: ed.t("Cash reserve")
                        policyKey: "cashReservePercent"
                        value: Number(ed.automationPolicy.cashReservePercent || 70)
                        minimum: 20
                        maximum: 95
                        decimals: 0
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 16) / 3
                        label: ed.t("Hard stop")
                        policyKey: "maxPositionLossPercent"
                        value: Number(ed.automationPolicy.maxPositionLossPercent || 3)
                        minimum: 0.5
                        maximum: 15
                    }
                    AutomationPercentField {
                        width: (parent.width - 16) / 3
                        label: ed.t("Trail starts")
                        policyKey: "trailingActivationPercent"
                        value: Number(ed.automationPolicy.trailingActivationPercent || 5)
                        minimum: 1
                        maximum: 30
                    }
                    AutomationPercentField {
                        width: (parent.width - 16) / 3
                        label: ed.t("Peak drop")
                        policyKey: "trailingStopPercent"
                        value: Number(ed.automationPolicy.trailingStopPercent || 2)
                        minimum: 0.5
                        maximum: 15
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Historical VaR 95%")
                        policyKey: "maxPortfolioVar95Percent"
                        value: Number(ed.automationPolicy.maxPortfolioVar95Percent || 2)
                        minimum: 0.25
                        maximum: 10
                        decimals: 2
                    }
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Expected shortfall 95%")
                        policyKey: "maxPortfolioCvar95Percent"
                        value: Number(ed.automationPolicy.maxPortfolioCvar95Percent || 3)
                        minimum: 0.5
                        maximum: 15
                        decimals: 2
                    }
                }

                Text {
                    width: parent.width
                    text: ed.t("Paper transaction cost assumptions")
                    color: Qt.rgba(1, 1, 1, 0.72)
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("KRX commission")
                        policyKey: "krxCommissionBps"
                        value: Number(ed.automationPolicy.krxCommissionBps !== undefined
                            ? ed.automationPolicy.krxCommissionBps : 1.5)
                        minimum: 0
                        maximum: 100
                        decimals: 1
                        suffix: "bp"
                    }
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("KRX sell tax")
                        policyKey: "krxSellTaxBps"
                        value: Number(ed.automationPolicy.krxSellTaxBps !== undefined
                            ? ed.automationPolicy.krxSellTaxBps : 15)
                        minimum: 0
                        maximum: 100
                        decimals: 1
                        suffix: "bp"
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 16) / 3
                        label: ed.t("US commission")
                        policyKey: "usCommissionBps"
                        value: Number(ed.automationPolicy.usCommissionBps !== undefined
                            ? ed.automationPolicy.usCommissionBps : 25)
                        minimum: 0
                        maximum: 100
                        decimals: 1
                        suffix: "bp"
                    }
                    AutomationPercentField {
                        width: (parent.width - 16) / 3
                        label: ed.t("US sell fees")
                        policyKey: "usSellFeeBps"
                        value: Number(ed.automationPolicy.usSellFeeBps !== undefined
                            ? ed.automationPolicy.usSellFeeBps : 1)
                        minimum: 0
                        maximum: 20
                        decimals: 1
                        suffix: "bp"
                    }
                    AutomationPercentField {
                        width: (parent.width - 16) / 3
                        label: ed.t("Slippage")
                        policyKey: "assumedSlippageBps"
                        value: Number(ed.automationPolicy.assumedSlippageBps !== undefined
                            ? ed.automationPolicy.assumedSlippageBps : 5)
                        minimum: 0
                        maximum: 100
                        decimals: 1
                        suffix: "bp"
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Stress loss")
                        policyKey: "maxStressLossPercent"
                        value: Number(ed.automationPolicy.maxStressLossPercent || 8)
                        minimum: 1
                        maximum: 25
                        decimals: 1
                    }
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Single-day loss")
                        policyKey: "maxSingleDayLossPercent"
                        value: Number(ed.automationPolicy.maxSingleDayLossPercent || 5)
                        minimum: 1
                        maximum: 20
                        decimals: 1
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Market data age")
                        policyKey: "maxMarketDataAgeSeconds"
                        value: Number(ed.automationPolicy.maxMarketDataAgeSeconds || 30)
                        minimum: 5
                        maximum: 120
                        decimals: 0
                        suffix: "s"
                    }
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Plan validity")
                        policyKey: "maxPlanAgeSeconds"
                        value: Number(ed.automationPolicy.maxPlanAgeSeconds || 90)
                        minimum: 30
                        maximum: 300
                        decimals: 0
                        suffix: "s"
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Execution drift")
                        policyKey: "maxPriceDriftPercent"
                        value: Number(ed.automationPolicy.maxPriceDriftPercent || 0.5)
                        minimum: 0.1
                        maximum: 3
                        decimals: 1
                    }
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Limit order timeout")
                        policyKey: "maxPendingOrderSeconds"
                        value: Number(ed.automationPolicy.maxPendingOrderSeconds || 120)
                        minimum: 60
                        maximum: 600
                        decimals: 0
                        suffix: "s"
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Market participation")
                        policyKey: "maxMarketParticipationPercent"
                        value: Number(ed.automationPolicy.maxMarketParticipationPercent || 0.1)
                        minimum: 0.01
                        maximum: 1
                        decimals: 2
                    }
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Bid-ask spread")
                        policyKey: "maxBidAskSpreadBps"
                        value: Number(ed.automationPolicy.maxBidAskSpreadBps || 20)
                        minimum: 5
                        maximum: 100
                        decimals: 0
                        suffix: "bp"
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Trade loss budget")
                        policyKey: "maxRiskPerTradePercent"
                        value: Number(ed.automationPolicy.maxRiskPerTradePercent || 0.25)
                        minimum: 0.05
                        maximum: 2
                        decimals: 2
                    }
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Volatility cushion")
                        policyKey: "volatilityRiskMultiplier"
                        value: Number(ed.automationPolicy.volatilityRiskMultiplier || 2)
                        minimum: 1
                        maximum: 5
                        decimals: 1
                        suffix: "×"
                    }
                }

                Row {
                    width: parent.width
                    spacing: 8
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Sector exposure")
                        policyKey: "maxSectorExposurePercent"
                        value: Number(ed.automationPolicy.maxSectorExposurePercent || 15)
                        minimum: 5
                        maximum: 50
                        decimals: 0
                    }
                    AutomationPercentField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Return correlation")
                        policyKey: "maxCorrelationCoefficient"
                        value: Number(ed.automationPolicy.maxCorrelationCoefficient || 0.85)
                        minimum: 0.5
                        maximum: 0.99
                        decimals: 2
                        suffix: "r"
                    }
                }

                Row {
                    width: parent.width
                    height: 28
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - protectionReset.width - 8
                        text: ed.t(ed.automationPolicyMessage)
                        color: ed.automationPolicyMessage.indexOf("unavailable") >= 0
                            ? "#ff453a" : Qt.rgba(1, 1, 1, 0.48)
                        font.family: "SF Pro Display"
                        font.pixelSize: 9
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        id: protectionReset
                        width: 88
                        height: 28
                        radius: 8
                        color: protectionResetHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                        opacity: automationPolicyProcess.running ? 0.42 : 1
                        scale: protectionResetArea.pressed ? ThemeService.pressScale : 1
                        Behavior on scale { AppleSpring { spring: 22 } }
                        Text {
                            anchors.centerIn: parent
                            text: ed.t("Reset Defaults")
                            color: "#ffffff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        HoverHandler { id: protectionResetHover }
                        MouseArea {
                            id: protectionResetArea
                            anchors.fill: parent
                            enabled: !automationPolicyProcess.running
                            cursorShape: Qt.PointingHandCursor
                            onPressed: ed.updateAutomationPolicy({
                                maxOrderValueKrw: 100000,
                                maxDailyNewExposureKrw: 200000,
                                maxOrdersPerDay: 2,
                                maxPositionPercent: 5,
                                cashReservePercent: 70,
                                maxPositionLossPercent: 3,
                                trailingActivationPercent: 5,
                                trailingStopPercent: 2,
                                maxRiskPerTradePercent: 0.25,
                                volatilityRiskMultiplier: 2,
                                maxSectorExposurePercent: 15,
                                maxCorrelationCoefficient: 0.85,
                                maxPortfolioVar95Percent: 2,
                                maxPortfolioCvar95Percent: 3,
                                maxStressLossPercent: 8,
                                maxSingleDayLossPercent: 5,
                                maxMarketParticipationPercent: 0.1,
                                maxBidAskSpreadBps: 20,
                                maxPriceDriftPercent: 0.5,
                                maxPendingOrderSeconds: 120,
                                maxMarketDataAgeSeconds: 30,
                                maxPlanAgeSeconds: 90,
                                krxCommissionBps: 1.5,
                                krxSellTaxBps: 15,
                                usCommissionBps: 25,
                                usSellFeeBps: 1,
                                assumedSlippageBps: 5,
                                notificationsEnabled: true
                            })
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: kisCredentials.height + 20
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.055)
            border.color: Qt.rgba(1, 1, 1, 0.10)
            border.width: 1
            Column {
                id: kisCredentials
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 10
                }
                height: childrenRect.height
                spacing: 8
                Row {
                    width: parent.width
                    Text {
                        text: "KIS · " + ed.t(ed.kisEnvironment === "prod" ? "Production" : "Paper")
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Item { width: parent.width - parent.children[0].width - kisStatus.width; height: 1 }
                    StatusBadge {
                        id: kisStatus
                        label: ed.t(ed.kisConfigured && ed.kisAccountConfigured ? "Trade Ready" : (ed.kisConfigured ? "Quotes Ready" : "Not Saved"))
                        ready: ed.kisConfigured && ed.kisAccountConfigured
                    }
                }
                CredentialField {
                    width: parent.width
                    label: ed.t("App Key")
                    configured: ed.kisConfigured
                    onRequested: (value, field) => ed.storeCredential(
                        ed.kisEnvironment === "prod" ? "kis_prod_app_key" : "kis_paper_app_key", value, field)
                }
                CredentialField {
                    width: parent.width
                    label: ed.t("App Secret")
                    configured: ed.kisConfigured
                    onRequested: (value, field) => ed.storeCredential(
                        ed.kisEnvironment === "prod" ? "kis_prod_app_secret" : "kis_paper_app_secret", value, field)
                }
                CredentialField {
                    width: parent.width
                    label: ed.t("Account Number (8-2)")
                    configured: ed.kisAccountConfigured
                    onRequested: (value, field) => ed.storeCredential(
                        ed.kisEnvironment === "prod" ? "kis_prod_account" : "kis_paper_account", value, field)
                }
            }
        }

        Rectangle {
            visible: ed.kisEnvironment === "prod"
            width: parent.width
            height: visible ? productionControl.implicitHeight + 20 : 0
            radius: 12
            color: Qt.rgba(1, 0.27, 0.23, 0.10)
            border.color: Qt.rgba(1, 0.27, 0.23, 0.24)
            border.width: 1
            Column {
                id: productionControl
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                Row {
                    width: parent.width
                    Text {
                        text: ed.t("Production Orders")
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Item { width: parent.width - parent.children[0].width - productionStatus.width; height: 1 }
                    StatusBadge {
                        id: productionStatus
                        label: ed.t(ed.productionTradingEnabled ? "Enabled" : "Locked")
                        ready: false
                    }
                }
                Text {
                    width: parent.width
                    text: ed.t(ed.productionTradingEnabled
                        ? "Every live order still requires typing LIVE in its confirmation sheet."
                        : "Type ENABLE LIVE to permit production order confirmation screens.")
                    color: Qt.rgba(1, 1, 1, 0.62)
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    wrapMode: Text.WordWrap
                }
                Item {
                    width: parent.width
                    height: 34
                    Rectangle {
                        visible: !ed.productionTradingEnabled
                        width: visible ? parent.width - liveToggleButton.width - 8 : 0
                        height: parent.height
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.08)
                        border.color: liveEnableField.activeFocus ? "#ff453a" : Qt.rgba(1, 1, 1, 0.10)
                        border.width: 1
                        TextField {
                            id: liveEnableField
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            placeholderText: "ENABLE LIVE"
                            placeholderTextColor: Qt.rgba(1, 1, 1, 0.30)
                            color: "#ffffff"
                            selectionColor: "#ff453a"
                            background: null
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            verticalAlignment: TextInput.AlignVCenter
                        }
                    }
                    Rectangle {
                        id: liveToggleButton
                        anchors.right: parent.right
                        width: 88
                        height: parent.height
                        radius: 9
                        color: ed.productionTradingEnabled ? Qt.rgba(1, 1, 1, 0.10)
                            : (liveEnableField.text.trim() === "ENABLE LIVE" ? "#ff453a" : Qt.rgba(1, 1, 1, 0.08))
                        opacity: !riskProcess.running && (ed.productionTradingEnabled || liveEnableField.text.trim() === "ENABLE LIVE") ? 1 : 0.42
                        scale: liveToggleArea.pressed ? ThemeService.pressScale : 1
                        Behavior on scale { AppleSpring { spring: 18 } }
                        Text {
                            anchors.centerIn: parent
                            text: ed.t(riskProcess.running ? "Saving…" : (ed.productionTradingEnabled ? "Lock" : "Enable"))
                            color: "#ffffff"
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: liveToggleArea
                            anchors.fill: parent
                            enabled: !riskProcess.running && (ed.productionTradingEnabled || liveEnableField.text.trim() === "ENABLE LIVE")
                            cursorShape: Qt.PointingHandCursor
                            onPressed: {
                                let enabled = !ed.productionTradingEnabled
                                liveEnableField.text = ""
                                ed.updateRiskPolicy({ productionEnabled: enabled })
                            }
                        }
                    }
                }
                Text {
                    text: ed.t("Risk Guard")
                    color: Qt.rgba(1, 1, 1, 0.72)
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Row {
                    width: parent.width
                    spacing: 8
                    RiskField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Per order · KRW")
                        policyKey: "maxOrderValueKrw"
                        value: ed.riskPolicy.maxOrderValueKrw
                    }
                    RiskField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Daily buys · KRW")
                        policyKey: "maxDailyBuyValueKrw"
                        value: ed.riskPolicy.maxDailyBuyValueKrw
                    }
                }
                Row {
                    width: parent.width
                    spacing: 8
                    RiskField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Buy orders / day")
                        policyKey: "maxBuyOrdersPerDay"
                        value: ed.riskPolicy.maxBuyOrdersPerDay
                        maximum: 1000
                    }
                    RiskField {
                        width: (parent.width - 8) / 2
                        label: ed.t("Max position · %")
                        policyKey: "maxPositionPercent"
                        value: ed.riskPolicy.maxPositionPercent
                        maximum: 100
                    }
                }
            }
        }

        Column {
            width: parent.width
            spacing: 10
            OptionGroup {
                width: parent.width
                title: ed.t("AI Provider")
                options: StockStrings.options(ed.language, StockService.providerOptions)
                selectedId: ed.aiProvider
                onSelected: id => { ed.aiProvider = id; ed.save({ aiProvider: id }) }
            }
            OptionGroup {
                width: parent.width
                title: ed.t("Analysis Quality")
                options: StockStrings.options(ed.language, StockService.analysisProfileOptions)
                selectedId: ed.analysisProfile
                onSelected: id => { ed.analysisProfile = id; ed.save({ analysisProfile: id }) }
            }
        }

        Row {
            width: parent.width
            height: 26
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - syncModelsButton.width - parent.spacing
                text: ed.t(StockService.profileModels(ed.analysisProfile))
                    + (ed.modelMessage !== "" ? "  ·  " + ed.t(ed.modelMessage) : "")
                color: Qt.rgba(1, 1, 1, 0.45)
                font.family: "SF Pro Display"
                font.pixelSize: 10
                elide: Text.ElideRight
            }
            Rectangle {
                id: syncModelsButton
                width: 66
                height: 26
                radius: 8
                color: syncModelsHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08)
                opacity: (ed.credentialState.openai || ed.credentialState.claude) && !modelProcess.running ? 1 : 0.42
                scale: syncModelsArea.pressed ? ThemeService.pressScale : 1
                Behavior on scale { AppleSpring { spring: 18 } }
                Text {
                    anchors.centerIn: parent
                    text: ed.t(modelProcess.running ? "Syncing" : "Refresh")
                    color: "#ffffff"
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                HoverHandler { id: syncModelsHover }
                MouseArea {
                    id: syncModelsArea
                    anchors.fill: parent
                    enabled: (ed.credentialState.openai || ed.credentialState.claude) && !modelProcess.running
                    cursorShape: Qt.PointingHandCursor
                    onPressed: ed.refreshModelCatalog(true)
                }
            }
        }

        Row {
            width: parent.width
            spacing: 10
            CredentialField {
                width: (parent.width - 10) / 2
                label: ed.t("OpenAI API Key")
                configured: !!ed.credentialState.openai
                onRequested: (value, field) => ed.storeCredential("openai_api_key", value, field)
            }
            CredentialField {
                width: (parent.width - 10) / 2
                label: ed.t("Claude API Key")
                configured: !!ed.credentialState.claude
                onRequested: (value, field) => ed.storeCredential("anthropic_api_key", value, field)
            }
        }

        Text {
            visible: ed.credentialMessage !== ""
            width: parent.width
            text: ed.t(ed.credentialMessage)
            color: ed.credentialMessage.indexOf("Could not") >= 0 || ed.credentialMessage.indexOf("unavailable") >= 0
                ? "#ff453a" : Qt.rgba(1, 1, 1, 0.58)
            font.family: "SF Pro Display"
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }

        Rectangle {
            width: parent.width
            height: securityText.implicitHeight + 20
            radius: 11
            color: Qt.rgba(0.04, 0.52, 1.0, 0.12)
            border.color: Qt.rgba(0.04, 0.52, 1.0, 0.24)
            Text {
                id: securityText
                anchors.fill: parent
                anchors.margins: 10
                text: ed.t("Secrets and account numbers stay in GNOME Keyring. AI ranks candidates, while deterministic safety gates authorize every explicitly armed paper or live order.")
                color: Qt.rgba(1, 1, 1, 0.72)
                font.family: "SF Pro Display"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }
    }

    component LabelText: Text {
        color: Qt.rgba(1, 1, 1, 0.55)
        font.family: "SF Pro Display"
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }

    component OptionGroup: Column {
        id: group
        property string title: ""
        property var options: []
        property string selectedId: ""
        signal selected(string id)
        spacing: 7
        LabelText { text: group.title }
        Flow {
            width: parent.width
            spacing: 6
            Repeater {
                model: group.options
                delegate: OptionPill {
                    required property var modelData
                    label: modelData.label
                    selected: group.selectedId === modelData.id
                    onTriggered: group.selected(modelData.id)
                }
            }
        }
    }

    component OptionPill: Rectangle {
        id: pill
        property string label: ""
        property bool selected: false
        signal triggered()
        width: Math.max(58, labelText.implicitWidth + 20)
        height: 29
        radius: 8
        color: selected ? "#0a84ff" : (pillHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.08))
        border.color: selected ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.10)
        border.width: 1
        scale: pillArea.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 18 } }
        Text {
            id: labelText
            anchors.centerIn: parent
            text: pill.label
            color: "#ffffff"
            font.family: "SF Pro Display"
            font.pixelSize: 11
            font.weight: pill.selected ? Font.DemiBold : Font.Normal
        }
        HoverHandler { id: pillHover }
        MouseArea {
            id: pillArea
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: pill.triggered()
        }
    }

    component StatusBadge: Rectangle {
        id: badge
        property string label: ""
        property bool ready: false
        width: statusText.implicitWidth + 18
        height: 21
        radius: 7
        color: ready ? Qt.rgba(0.19, 0.82, 0.35, 0.14) : Qt.rgba(1, 1, 1, 0.07)
        Row {
            anchors.centerIn: parent
            spacing: 5
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 5
                height: 5
                radius: 2.5
                color: badge.ready ? "#30d158" : "#8e8e93"
            }
            Text {
                id: statusText
                anchors.verticalCenter: parent.verticalCenter
                text: badge.label
                color: badge.ready ? "#30d158" : Qt.rgba(1, 1, 1, 0.52)
                font.family: "SF Pro Display"
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }
    }

    component RiskField: Column {
        id: riskField
        property string label: ""
        property string policyKey: ""
        property real value: 0
        property real maximum: 1000000000000
        spacing: 5
        onValueChanged: riskInput.text = String(Math.round(value))
        LabelText { text: riskField.label }
        Rectangle {
            width: parent.width
            height: 32
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.08)
            border.color: riskInput.activeFocus ? "#ff9f0a" : Qt.rgba(1, 1, 1, 0.10)
            border.width: 1
            TextField {
                id: riskInput
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                text: String(Math.round(riskField.value))
                color: "#ffffff"
                selectionColor: "#ff9f0a"
                background: null
                font.family: "SF Pro Display"
                font.pixelSize: 10
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignRight
                validator: DoubleValidator { bottom: 1; top: riskField.maximum; decimals: 0 }
                onEditingFinished: {
                    let next = Math.round(Number(text))
                    if (!isFinite(next) || next < 1) {
                        text = String(Math.round(riskField.value))
                        return
                    }
                    let patch = ({})
                    patch[riskField.policyKey] = next
                    ed.updateRiskPolicy(patch)
                }
            }
        }
    }

    component AutomationPercentField: Column {
        id: automationField
        property string label: ""
        property string policyKey: ""
        property real value: 0
        property real minimum: 0.5
        property real maximum: 30
        property int decimals: 1
        property string suffix: "%"
        spacing: 5
        onValueChanged: automationInput.text = Number(value).toFixed(decimals)
        LabelText { text: automationField.label + " · " + automationField.suffix }
        Rectangle {
            width: parent.width
            height: 32
            radius: 8
            color: Qt.rgba(1, 1, 1, 0.08)
            border.color: automationInput.activeFocus ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.10)
            border.width: 1
            TextField {
                id: automationInput
                anchors.fill: parent
                anchors.leftMargin: 9
                anchors.rightMargin: 9
                text: Number(automationField.value).toFixed(automationField.decimals)
                color: "#ffffff"
                selectionColor: "#0a84ff"
                background: null
                font.family: "SF Pro Display"
                font.pixelSize: 10
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignRight
                validator: DoubleValidator {
                    bottom: automationField.minimum
                    top: automationField.maximum
                    decimals: automationField.decimals
                    notation: DoubleValidator.StandardNotation
                }
                onEditingFinished: {
                    let factor = Math.pow(10, automationField.decimals)
                    let next = Math.round(Number(text) * factor) / factor
                    if (!isFinite(next) || next < automationField.minimum || next > automationField.maximum) {
                        text = Number(automationField.value).toFixed(automationField.decimals)
                        return
                    }
                    text = next.toFixed(automationField.decimals)
                    let patch = ({})
                    patch[automationField.policyKey] = next
                    ed.updateAutomationPolicy(patch)
                }
            }
        }
    }

    component CredentialField: Column {
        id: credential
        height: credentialLabel.implicitHeight + spacing + credentialInput.height
        property string label: ""
        property bool configured: false
        signal requested(string value, var field)
        spacing: 5
        Row {
            id: credentialLabel
            width: parent.width
            LabelText { text: credential.label }
            Item { width: parent.width - parent.children[0].width - savedText.width; height: 1 }
            Text {
                id: savedText
                text: credential.configured ? ed.t("Saved") : ""
                color: "#30d158"
                font.family: "SF Pro Display"
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }
        Rectangle {
            id: credentialInput
            width: parent.width
            height: 34
            radius: 9
            color: Qt.rgba(1, 1, 1, 0.08)
            border.color: secretField.activeFocus ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.10)
            border.width: 1
            TextField {
                id: secretField
                anchors { left: parent.left; right: saveButton.left; top: parent.top; bottom: parent.bottom }
                anchors.leftMargin: 10
                anchors.rightMargin: 6
                placeholderText: ed.t(credential.configured ? "Replace saved value" : "Enter securely")
                placeholderTextColor: Qt.rgba(1, 1, 1, 0.32)
                color: "#ffffff"
                selectionColor: "#0a84ff"
                echoMode: TextInput.Password
                background: null
                font.family: "SF Pro Display"
                font.pixelSize: 11
                verticalAlignment: TextInput.AlignVCenter
                onAccepted: if (text.trim() !== "") credential.requested(text, secretField)
            }
            Rectangle {
                id: saveButton
                anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                anchors.margins: 3
                width: 50
                radius: 7
                color: saveHover.hovered && secretField.text.trim() !== "" ? "#0a84ff" : Qt.rgba(1, 1, 1, 0.09)
                opacity: secretField.text.trim() !== "" ? 1 : 0.45
                scale: saveArea.pressed ? ThemeService.pressScale : 1
                Behavior on scale { AppleSpring { spring: 18 } }
                Text {
                    anchors.centerIn: parent
                    text: ed.t("Save")
                    color: "#ffffff"
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                HoverHandler { id: saveHover }
                MouseArea {
                    id: saveArea
                    anchors.fill: parent
                    enabled: secretField.text.trim() !== ""
                    cursorShape: Qt.PointingHandCursor
                    onPressed: credential.requested(secretField.text, secretField)
                }
            }
        }
    }
}
