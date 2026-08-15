import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "kinetic.js" as Kinetic
import "stock" as Stock

Item {
    id: root
    property var frame
    readonly property var config: frame ? frame.dataObj : ({})
    readonly property int widgetLayout: Number(config.layout || 1)
    readonly property bool xxlLayout: widgetLayout === 2
    readonly property string language: config.language === "en" ? "en" : "ko"
    property string symbol: config.symbol || "005930"
    property string market: config.market || "KRX"
    property string chartRange: config.range || "1D"
    readonly property string aiProvider: config.aiProvider || "none"
    readonly property string analysisProfile: config.analysisProfile || "balanced"
    readonly property string dataMode: config.dataMode || "demo"
    readonly property string kisEnvironment: config.kisEnvironment || "paper"
    readonly property int automaticTradingUiVersion: 1
    property bool automaticTradingUiMigrated: false
    property string tradingMode: dataMode === "kis"
        && Number(config.automaticTradingUiVersion || 0) < automaticTradingUiVersion
        ? "automatic" : (config.tradingMode === "automatic" ? "automatic" : "manual")
    property bool automationTargetEnabled: config.automationTargetEnabled === true
    property var watchlist: Array.isArray(config.watchlist) ? config.watchlist.slice() : [
        { symbol: "005930", market: "KRX" },
        { symbol: "000660", market: "KRX" },
        { symbol: "035420", market: "KRX" }
    ]
    property var priceAlerts: Array.isArray(config.priceAlerts) ? config.priceAlerts.slice(0, 16) : []
    readonly property string alertSourceId: (WidgetsService.activeBoardKey || "board")
        + ":" + (frame ? frame.wid : "stock")
    readonly property bool productionTradingEnabled: !!config.productionTradingEnabled && !!credentialState.productionTradingEnabled
    readonly property bool active: frame && frame.winRef ? frame.winRef.show : true
    readonly property bool sessionLockPassive: Quickshell.env("QS_LOCK_MODE") === "1"
    readonly property bool dark: ThemeService.isDark
    readonly property color backgroundColor: dark ? "#1c1c1e" : "#f7f7f9"
    readonly property color foregroundColor: dark ? "#f5f5f7" : "#111114"
    readonly property color secondaryColor: dark ? "#98989d" : "#6e6e73"
    readonly property color separatorColor: dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color raisedColor: dark ? "#2c2c2e" : "#ffffff"
    readonly property color positiveColor: "#30d158"
    readonly property color negativeColor: "#ff453a"
    readonly property color movementColor: Number(snapshot.change) >= 0 ? positiveColor : negativeColor
    property color cardColor: backgroundColor
    property bool lightCard: !dark
    property var snapshot: ({
        name: symbol,
        symbol: symbol,
        market: market,
        currency: market === "KRX" ? "KRW" : "USD",
        price: 0,
        change: 0,
        changePct: 0,
        high: 0,
        low: 0,
        volume: 0,
        buyingPower: market === "KRX" ? 10000000 : 10000,
        points: []
    })
    property bool loading: false
    property bool pendingFetch: false
    property string errorText: ""
    property string selectedTab: "trade"
    property string orderSide: "buy"
    property string orderType: "market"
    property bool reviewVisible: false
    property string orderMessage: ""
    property string orderError: ""
    property string pendingOrder: ""
    property var reviewOrder: ({})
    property var preflightState: ({})
    property string preflightError: ""
    property string pendingPreflight: ""
    property string preflightToken: ""
    property bool preflightQueued: false
    property bool ordersVisible: false
    property bool portfolioVisible: false
    property bool activityVisible: false
    property string activityFilter: "all"
    property var activityState: ({ activity: [], counts: {} })
    property string activityError: ""
    property bool activityQueued: false
    property bool activityBusy: false
    property bool watchlistVisible: false
    property var watchlistState: ({ items: [] })
    property string watchlistError: ""
    property string pendingWatchlist: ""
    property bool watchlistQueued: false
    property string watchSearchText: ""
    property var watchSearchResults: []
    property string watchSearchError: ""
    property bool watchSearchQueued: false
    property string pendingAlertEvaluation: ""
    property bool alertEvaluationQueued: false
    property bool alertsVisible: false
    property string alertDraftSymbol: symbol
    property string alertDraftMarket: market
    property real alertDraftPrice: Number(snapshot.price || 0)
    property string alertDirection: "above"
    property string alertTargetText: ""
    property string alertEditorError: ""
    property bool cancelReviewVisible: false
    property var orderHistory: []
    property int pendingOrderCount: 0
    property bool orderHistoryBusy: false
    property string orderHistoryError: ""
    property var cancelTarget: ({})
    property string pendingCancel: ""
    property var accountState: ({})
    property bool accountBusy: false
    property bool pendingAccount: false
    property string accountError: ""
    property string analysisMessage: ""
    property var analysisResult: ({})
    property bool analysisBusy: false
    property string analysisError: ""
    property string pendingAnalysis: ""
    property bool analysisReportVisible: false
    property bool forecastVisible: false
    property string quantTab: "forecasts"
    property var forecastState: ({ items: [], stats: {} })
    property string forecastError: ""
    property string pendingForecastInput: ""
    property bool forecastQueued: false
    property string backtestStrategy: config.backtestStrategy || "trend"
    property string backtestCostProfile: "base"
    property var backtestResult: ({})
    property string backtestError: ""
    property bool backtestBusy: false
    property var comparisonResult: ({ items: [] })
    property string comparisonError: ""
    property bool comparisonBusy: false
    property var aiValidationResult: ({ models: [], calibration: [], signals: {} })
    property string aiValidationError: ""
    property bool aiValidationBusy: false
    property bool aiValidationQueued: false
    property int validationConfidenceFloor: 60
    property var aiUsageState: ({ summary: {}, models: [], recent: [] })
    property string aiUsageError: ""
    property bool aiUsageBusy: false
    property var screenerState: ({ items: [], counts: {} })
    property string screenerError: ""
    property bool screenerBusy: false
    property string pendingScreener: ""
    property bool screenerQueued: false
    property var automationState: ({ policy: {}, history: { counts: {} }, guarantees: {} })
    property var automationPlan: ({})
    property var automationExecution: ({})
    property string automationError: ""
    property string pendingAutomation: ""
    property bool automationBusy: false
    property bool automationRefreshQueued: false
    property bool autopilotVisible: false
    property var autopilotState: ({
        status: "ok",
        kind: "autopilot",
        enabled: false,
        environment: "paper",
        automaticSelection: true,
        selectedKeys: [],
        selectedCount: 0,
        candidates: [],
        phase: "idle",
        lastScanAt: 0,
        lastError: "",
        paperOnly: true,
        noLossGuaranteed: false
    })
    property string autopilotError: ""
    property string pendingAutopilot: ""
    property string pendingAutopilotEmergency: ""
    property string autopilotAction: ""
    property bool autopilotBusy: false
    property bool autopilotEmergencyBusy: false
    property bool autopilotRefreshQueued: false
    property bool autopilotRefreshAutomationQueued: false
    property bool liveAutopilotReviewVisible: false
    property bool realtimeConnected: false
    property string realtimeStatus: ""
    property int hoverIndex: -1
    property var credentialState: ({ kisProd: false, kisPaper: false, kisProdAccount: false, kisPaperAccount: false, openai: false, claude: false, productionTradingEnabled: false })
    readonly property var points: snapshot.points || []
    readonly property bool kisConfigured: kisEnvironment === "prod" ? !!credentialState.kisProd : !!credentialState.kisPaper
    readonly property bool kisAccountConfigured: kisEnvironment === "prod" ? !!credentialState.kisProdAccount : !!credentialState.kisPaperAccount
    readonly property bool tradingConfigured: kisConfigured && kisAccountConfigured
    readonly property bool paperOrderReady: dataMode === "kis" && kisEnvironment === "paper"
        && tradingConfigured && accountState.status === "ok"
    readonly property bool productionOrderReady: dataMode === "kis" && kisEnvironment === "prod"
        && productionTradingEnabled && tradingConfigured && accountState.status === "ok"
    readonly property bool demoOrderReady: dataMode === "demo"
    readonly property bool shouldStream: active && dataMode === "kis" && market === "KRX" && kisConfigured
    readonly property bool aiConfigured: aiProvider === "openai" ? !!credentialState.openai
        : (aiProvider === "claude" ? !!credentialState.claude
        : (aiProvider === "both" ? !!credentialState.openai && !!credentialState.claude : false))
    readonly property int quantity: mainPanel.quantity
    readonly property real orderPrice: mainPanel.orderPrice
    readonly property real estimatedTotal: quantity * orderPrice
    readonly property bool quantityAvailable: demoOrderReady || ((paperOrderReady || productionOrderReady) && (orderSide === "buy"
        ? quantity <= Number(accountState.buyingQuantity || 0)
        : quantity <= Number(accountState.sellableQuantity || 0)))
    readonly property bool canReviewOrder: manualOrderAllowed
        && orderPrice > 0 && quantityAvailable && !backend.order.running
    readonly property bool preflightReady: demoOrderReady || (preflightState.status === "ok" && !backend.preflight.running)
    readonly property bool orderRunning: backend.order.running
    readonly property bool preflightRunning: backend.preflight.running
    readonly property bool cancelRunning: backend.cancel.running
    readonly property bool forecastRunning: backend.forecast.running
    readonly property bool currentWatched: watchlist.some(item => item.symbol === symbol && item.market === market)
    readonly property int enabledAlertCount: priceAlerts.filter(alert => alert.enabled !== false).length
    readonly property bool alertPollingReady: dataMode === "demo" || kisConfigured
    readonly property bool watchlistBusy: backend.watchlist.running
    readonly property bool watchSearchBusy: backend.watchSearch.running
    readonly property bool autopilotRunning: !!autopilotState.enabled && autopilotState.phase === "running"
    readonly property var automationScheduler: automationState.scheduler || ({})
    readonly property var automationLastRun: automationScheduler.lastRun || ({})
    readonly property bool autopilotHalted: autopilotState.phase === "safety_halted"
        || !!(automationState.policy || {}).halted
    readonly property bool autopilotStatusPolling: active && dataMode === "kis"
        && (autoTradingMode || autopilotVisible || autopilotRunning)
    readonly property var liveReadiness: automationState.liveReadiness || ({})
    readonly property string autopilotEnvironment: autopilotRunning
        ? (autopilotState.environment === "prod" ? "prod" : "paper")
        : (kisEnvironment === "prod" ? "prod" : "paper")
    readonly property bool liveAutopilotContext: autopilotEnvironment === "prod"
    readonly property bool liveAutopilotEligible: !!liveReadiness.productionAutomationEligible
    readonly property bool autopilotCanScan: dataMode === "kis"
        && tradingConfigured && aiConfigured && !autopilotBusy && !autopilotEmergencyBusy
    readonly property bool autopilotCanStart: autopilotCanScan
        && (!autopilotHalted || String((automationState.policy || {}).haltClass
            || autopilotState.haltClass || "") === "manual")
        && (autopilotState.environment !== autopilotEnvironment
            || autopilotState.automaticSelection !== false
            || !autopilotState.lastError)
        && (!liveAutopilotContext || (productionTradingEnabled && liveAutopilotEligible))
        && (autopilotState.environment !== autopilotEnvironment
            || autopilotState.automaticSelection !== false
            || Number(autopilotState.selectedCount || 0) > 0)
    readonly property bool autoTradingMode: autopilotRunning
        || (tradingMode === "automatic" && dataMode === "kis")
    readonly property bool manualOrderAllowed: !autoTradingMode
        && !autopilotRunning
        && autopilotAction !== "autopilot-start"
        && !autopilotEmergencyBusy

    function t(source, values) { return StockStrings.text(language, source, values) }

    function syncConfigState() {
        if (!frame) return
        let data = frame.dataObj || ({})
        let nextSymbol = data.symbol || "005930"
        let nextMarket = data.market || "KRX"
        let nextWatchlist = Array.isArray(data.watchlist) ? data.watchlist.slice() : [
            { symbol: "005930", market: "KRX" },
            { symbol: "000660", market: "KRX" },
            { symbol: "035420", market: "KRX" }
        ]
        let nextAlerts = Array.isArray(data.priceAlerts) ? data.priceAlerts.slice(0, 16) : []
        if (symbol !== nextSymbol) symbol = nextSymbol
        if (market !== nextMarket) market = nextMarket
        if (JSON.stringify(watchlist) !== JSON.stringify(nextWatchlist)) watchlist = nextWatchlist
        if (JSON.stringify(priceAlerts) !== JSON.stringify(nextAlerts)) priceAlerts = nextAlerts
        let migrateAutomaticUi = dataMode === "kis"
            && Number(data.automaticTradingUiVersion || 0) < automaticTradingUiVersion
        tradingMode = migrateAutomaticUi || data.tradingMode === "automatic" ? "automatic" : "manual"
        if (migrateAutomaticUi && !automaticTradingUiMigrated && frame) {
            automaticTradingUiMigrated = true
            frame.save({
                tradingMode: "automatic",
                automaticTradingUiVersion: automaticTradingUiVersion
            })
        }
        automationTargetEnabled = data.automationTargetEnabled === true
    }

    function setTradingMode(nextMode) {
        let next = nextMode === "automatic" ? "automatic" : "manual"
        if (next === "automatic" && dataMode !== "kis") return
        if (next === "manual" && (autopilotRunning || autopilotAction === "autopilot-start")) return
        if (tradingMode === next) return
        tradingMode = next
        reviewVisible = false
        reviewOrder = ({})
        preflightState = ({})
        preflightError = ""
        preflightQueued = false
        if (frame) frame.save({ tradingMode: next })
    }

    function selectInstrument(nextSymbol, nextMarket) {
        if (!nextSymbol || !frame) return
        symbol = String(nextSymbol).trim().toUpperCase()
        market = String(nextMarket || "KRX").trim().toUpperCase()
        snapshot = {
            status: "loading",
            mode: dataMode,
            environment: kisEnvironment,
            symbol: symbol,
            market: market,
            name: symbol,
            currency: market === "KRX" ? "KRW" : "USD",
            price: 0,
            previousClose: 0,
            change: 0,
            changePct: 0,
            high: 0,
            low: 0,
            volume: 0,
            buyingPower: 0,
            points: []
        }
        frame.save({ symbol: symbol, market: market })
    }

    Connections {
        target: root.frame
        function onPayloadChanged() { root.syncConfigState() }
    }

    Connections {
        target: StockService
        function onAutomationPolicyChanged() {
            if (root.forecastVisible && root.quantTab === "automation") root.refreshAutomation()
            root.refreshAutopilot()
        }
    }

    Connections {
        target: backend.autopilot
        function onRunningChanged() {
            if (backend.autopilot.running || !root.autopilotRefreshAutomationQueued) return
            root.autopilotRefreshAutomationQueued = false
            root.refreshAutomation()
        }
    }

    onSymbolChanged: { resetAnalysis(); resetBacktest(); resetComparison(); resetAiValidation(); closeForecasts(); scheduleFetch(); scheduleRealtime(); ordersVisible = false; portfolioVisible = false }
    onMarketChanged: {
        if (market !== "KRX") orderType = "limit"
        resetAnalysis(); resetBacktest(); resetComparison(); resetAiValidation(); closeForecasts(); scheduleFetch(); scheduleRealtime()
    }
    onDataModeChanged: {
        resetBacktest()
        resetComparison()
        resetScreener()
        scheduleFetch()
        scheduleRealtime()
        liveAutopilotReviewVisible = false
        ordersVisible = false
        portfolioVisible = false
        if (watchlistVisible || enabledAlertCount > 0 || xxlLayout) refreshWatchlist()
        if (forecastVisible && quantTab === "screener") refreshScreener()
    }
    onKisEnvironmentChanged: {
        resetBacktest()
        resetComparison()
        resetScreener()
        scheduleFetch()
        scheduleRealtime()
        liveAutopilotReviewVisible = false
        ordersVisible = false
        portfolioVisible = false
        if (watchlistVisible || enabledAlertCount > 0 || xxlLayout) refreshWatchlist()
        if (forecastVisible && quantTab === "screener") refreshScreener()
    }
    onWatchlistChanged: {
        resetScreener()
        if (watchlistVisible || enabledAlertCount > 0 || xxlLayout) refreshWatchlist()
        if (forecastVisible && quantTab === "screener") refreshScreener()
    }
    onKisConfiguredChanged: {
        scheduleRealtime()
        if (enabledAlertCount > 0 && alertPollingReady) Qt.callLater(root.refreshWatchlist)
    }
    onProductionTradingEnabledChanged: {
        reviewVisible = false
        preflightState = ({})
        cancelReviewVisible = false
    }
    onOrderTypeChanged: scheduleAccount()
    onAiProviderChanged: resetAnalysis()
    onAnalysisProfileChanged: resetAnalysis()
    onLanguageChanged: resetAnalysis()
    onSelectedTabChanged: if (selectedTab !== "ai") { analysisReportVisible = false; closeForecasts() }
    onChartRangeChanged: {
        resetAnalysis()
        if (frame && frame.dataObj && frame.dataObj.range !== chartRange) frame.save({ range: chartRange })
        scheduleFetch()
    }
    onActiveChanged: {
        if (active) {
            scheduleFetch()
            scheduleRealtime()
            refreshAutopilot()
            if (autoTradingMode) refreshAutomation()
            if (enabledAlertCount > 0 || xxlLayout) refreshWatchlist()
        } else {
            stopRealtime()
        }
    }
    Keys.onEscapePressed: event => {
        if (liveAutopilotReviewVisible) {
            closeLiveAutopilotReview()
            event.accepted = true
        } else if (autopilotVisible) {
            closeAutopilot()
            event.accepted = true
        } else if (forecastVisible) {
            closeForecasts()
            event.accepted = true
        } else if (alertsVisible) {
            closeAlerts()
            event.accepted = true
        } else if (watchlistVisible) {
            closeWatchlist()
            event.accepted = true
        } else if (activityVisible) {
            closeActivity()
            event.accepted = true
        } else if (analysisReportVisible) {
            analysisReportVisible = false
            event.accepted = true
        }
    }
    onSnapshotChanged: marketOverview.requestPaint()
    onWidthChanged: marketOverview.requestPaint()
    onXxlLayoutChanged: {
        marketOverview.requestPaint()
        if (xxlLayout && active) {
            Qt.callLater(root.refreshWatchlist)
            root.scheduleAccount()
        }
    }
    Component.onCompleted: {
        if (sessionLockPassive)
            return
        syncConfigState()
        refreshCredentialState()
        scheduleFetch()
        scheduleRealtime()
        refreshAutopilot()
        refreshAutomation()
        if ((enabledAlertCount > 0 || xxlLayout) && alertPollingReady) Qt.callLater(root.refreshWatchlist)
    }

    Stock.StockProcesses {
        id: backend
        root: root
    }

    function scheduleFetch() {
        if (active) backend.fetchDelay.restart()
    }

    function scheduleAccount() {
        accountState = ({})
        accountError = ""
        pendingAccount = false
        if (active && dataMode === "kis" && tradingConfigured) {
            pendingAccount = true
            if (!backend.account.running) backend.accountDelay.restart()
        }
    }

    function refreshAccount() {
        if (!active || dataMode !== "kis" || !tradingConfigured || backend.account.running) return
        pendingAccount = false
        backend.account.command = ["python3", StockService.stockScript, "account", kisEnvironment, symbol,
            String(orderPrice), orderType, market]
        backend.account.running = true
    }

    function refreshOrderHistory() {
        if (dataMode !== "kis" || !tradingConfigured || backend.orderHistory.running) return
        backend.orderHistory.command = ["python3", StockService.stockScript, "orders", kisEnvironment, symbol, market]
        backend.orderHistory.running = true
    }

    function openOrders() {
        if (dataMode !== "kis" || !tradingConfigured) return
        portfolioVisible = false
        ordersVisible = true
        cancelReviewVisible = false
        orderHistoryError = ""
        refreshOrderHistory()
    }

    function closeOrders() {
        if (backend.cancel.running) return
        ordersVisible = false
        cancelReviewVisible = false
        cancelTarget = ({})
        mainPanel.clearCancelConfirmation()
    }

    function openActivity() {
        activityVisible = true
        activityError = ""
        activityQueued = false
        forceActiveFocus()
        refreshActivity()
    }

    function closeActivity() {
        activityVisible = false
        activityQueued = false
    }

    function refreshActivity() {
        if (backend.activity.running) {
            activityQueued = true
            return
        }
        let reconcileEnvironment = dataMode === "kis" && tradingConfigured ? kisEnvironment : "none"
        backend.activity.command = ["python3", StockService.stockScript, "activity", activityFilter, "50",
            reconcileEnvironment]
        backend.activity.running = true
    }

    function chooseActivityFilter(value) {
        if (activityFilter === value) return
        activityFilter = value
        refreshActivity()
    }

    function activityDisplayStatus(event) {
        if (event && event.brokerState) return event.brokerState
        if (event && event.reconciliation === "unmatched") return "uncertain"
        if (event && event.reconciliation === "pending") return "submitted"
        return event ? event.status : "submitting"
    }

    function activityStatusLabel(event) {
        let value = activityDisplayStatus(event)
        if (value === "filled" || value === "partial" || value === "pending" || value === "canceled"
                || value === "rejected" || value === "submitted") return orderStateLabel(value)
        if (value === "accepted") return t("Accepted")
        if (value === "failed") return t("Failed")
        if (value === "uncertain") return t("Verify")
        return t("Submitting")
    }

    function activityStatusColor(event) {
        let value = typeof event === "string" ? event : activityDisplayStatus(event)
        if (value === "filled") return positiveColor
        if (value === "partial" || value === "pending" || value === "submitted") return "#0a84ff"
        if (value === "canceled") return secondaryColor
        if (value === "rejected") return negativeColor
        if (value === "accepted") return positiveColor
        if (value === "failed") return negativeColor
        if (value === "uncertain") return "#ff9f0a"
        return "#0a84ff"
    }

    function activityTitle(event) {
        if (event.action === "cancel") return t("Cancel order #%1", [event.originalOrderNumber || t("Unknown")])
        let side = t(event.side === "sell" ? "Sell" : "Buy")
        return t("%1 %2 shares of %3", [side, Number(event.quantity || 0), event.symbol || t("Unknown")])
    }

    function activityDetail(event) {
        if (event.reconciliation === "matched") {
            let orderNumber = event.orderNumber || event.originalOrderNumber || t("Unknown")
            if (Number(event.quantity || 0) > 0)
                return t("Broker order #%1 · %2/%3 filled", [orderNumber,
                    Number(event.filledQuantity || 0), Number(event.quantity || 0)])
            return t("Broker order #%1 · reconciled", [orderNumber])
        }
        if (event.reconciliation === "unmatched") return t("Final broker state is unknown; verify with KIS.")
        if (event.reconciliation === "pending") return t("Waiting for KIS confirmation")
        if (event.message) return t(event.message)
        if (event.orderNumber) return t("Broker order #%1", [event.orderNumber])
        if (event.action === "order" && Number(event.estimatedNotional || 0) > 0)
            return t("Estimated %1", [StockService.money(event.estimatedNotional, event.currency || "KRW")])
        return t(event.status === "uncertain" ? "Final broker state is unknown; verify with KIS." : "Local audit event")
    }

    function activityReconciliationLabel() {
        let state = activityState.reconciliation || {}
        if (state.status === "ok") return t("Matched with KIS · updated %1", [analysisTime(state.updatedAt)])
        if (state.status === "error") return t("KIS reconciliation unavailable · local audit shown")
        return t("Local audit trail · not a substitute for your KIS broker statement")
    }

    function openPortfolio() {
        if (dataMode !== "kis" || !tradingConfigured) return
        ordersVisible = false
        cancelReviewVisible = false
        portfolioVisible = true
        if (!backend.account.running) refreshAccount()
    }

    function closePortfolio() {
        portfolioVisible = false
    }

    function selectHolding(holding) {
        if (!holding || !holding.symbol || !frame) return
        closePortfolio()
        selectInstrument(holding.symbol, holding.market || market)
    }

    function openWatchlist() {
        watchlistVisible = true
        watchlistError = ""
        watchlistQueued = false
        watchSearchText = ""
        watchSearchResults = []
        watchSearchError = ""
        watchSearchQueued = false
        forceActiveFocus()
        refreshWatchlist()
    }

    function closeWatchlist() {
        watchlistVisible = false
        watchlistQueued = false
        watchSearchText = ""
        watchSearchResults = []
        watchSearchError = ""
        watchSearchQueued = false
    }

    function refreshWatchlist() {
        if ((!watchlistVisible && enabledAlertCount === 0 && !xxlLayout) || !alertPollingReady) return
        if (backend.watchlist.running) {
            watchlistQueued = true
            return
        }
        if (watchlist.length === 0) {
            watchlistState = ({ status: "ok", items: [] })
            return
        }
        pendingWatchlist = JSON.stringify(watchlist)
        backend.watchlist.command = ["python3", StockService.stockScript, "watchlist", dataMode, kisEnvironment]
        backend.watchlist.running = true
    }

    function saveWatchlist(next) {
        if (!frame) return
        watchlist = next.slice()
        frame.save({ watchlist: watchlist })
    }

    function searchWatchlist(value) {
        watchSearchText = value
        watchSearchError = ""
        watchlistError = ""
        if (value.trim() === "") {
            watchSearchResults = []
            watchSearchQueued = false
            return
        }
        if (backend.watchSearch.running) {
            watchSearchQueued = true
            return
        }
        backend.watchSearch.command = ["python3", StockService.stockScript, "search", value.trim(), "8", "ALL"]
        backend.watchSearch.running = true
    }

    function addSearchResult(item) {
        if (!item || !item.symbol || !frame) return
        if (watchlist.some(entry => entry.symbol === item.symbol && entry.market === item.market)) {
            watchSearchError = "Already in your watchlist."
            return
        }
        saveWatchlist(watchlist.concat([{ symbol: item.symbol, market: item.market }]))
        watchSearchText = ""
        watchSearchResults = []
        watchSearchError = ""
        forceActiveFocus()
    }

    function toggleCurrentWatch() {
        let next = watchlist.slice()
        let index = next.findIndex(item => item.symbol === symbol && item.market === market)
        if (index >= 0) {
            next.splice(index, 1)
        } else {
            next.push({ symbol: symbol, market: market })
        }
        saveWatchlist(next)
    }

    function removeWatchItem(item) {
        if (alertCountFor(item) > 0) {
            watchlistError = "Remove this symbol's price alerts first."
            return
        }
        let next = watchlist.filter(entry => !(entry.symbol === item.symbol && entry.market === item.market))
        saveWatchlist(next)
    }

    function selectWatchItem(item) {
        if (!item || !item.symbol || !frame) return
        closeWatchlist()
        selectInstrument(item.symbol, item.market || "KRX")
    }

    function alertCountFor(item) {
        if (!item) return 0
        return priceAlerts.filter(alert => alert.symbol === item.symbol && alert.market === (item.market || "KRX")).length
    }

    function openAlerts(item) {
        let source = item && item.symbol ? item : snapshot
        alertDraftSymbol = source.symbol || symbol
        alertDraftMarket = source.market || market
        alertDraftPrice = Number(source.price || (source.symbol === symbol ? snapshot.price : 0))
        alertDirection = "above"
        alertEditorError = ""
        alertTargetText = ""
        closeWatchlist()
        alertsVisible = true
        forceActiveFocus()
    }

    function closeAlerts() {
        alertsVisible = false
        alertEditorError = ""
        alertTargetText = ""
    }

    function savePriceAlerts(next, watchlistPatch) {
        if (!frame) return
        priceAlerts = next.slice(0, 16)
        let patch = { priceAlerts: priceAlerts }
        if (watchlistPatch) {
            watchlist = watchlistPatch.slice()
            patch.watchlist = watchlist
        }
        frame.save(patch)
    }

    function addPriceAlert() {
        let target = Number(alertTargetText.trim().replace(/,/g, ""))
        if (!isFinite(target) || target <= 0) {
            alertEditorError = "Enter a valid target price."
            return
        }
        if (priceAlerts.length >= 16) {
            alertEditorError = "Price alerts are limited to 16."
            return
        }
        let watched = watchlist.slice()
        if (!watched.some(item => item.symbol === alertDraftSymbol && item.market === alertDraftMarket)) {
            watched.push({ symbol: alertDraftSymbol, market: alertDraftMarket })
        }
        let duplicate = priceAlerts.some(alert => alert.symbol === alertDraftSymbol
            && alert.market === alertDraftMarket && alert.direction === alertDirection
            && Math.abs(Number(alert.target) - target) < 0.000001)
        if (duplicate) {
            alertEditorError = "That price alert already exists."
            return
        }
        let next = priceAlerts.slice()
        let alreadyCrossed = alertDraftPrice > 0 && (alertDirection === "below"
            ? alertDraftPrice <= target : alertDraftPrice >= target)
        next.push({
            id: Date.now().toString(36) + "-" + Math.floor(Math.random() * 1679616).toString(36),
            symbol: alertDraftSymbol,
            market: alertDraftMarket,
            direction: alertDirection,
            target: target,
            enabled: true,
            armed: !alreadyCrossed,
            lastTriggeredAt: 0,
            stateRevision: Date.now()
        })
        savePriceAlerts(next, watched)
        alertEditorError = ""
        alertTargetText = ""
        Qt.callLater(root.refreshWatchlist)
    }

    function togglePriceAlert(id) {
        let next = priceAlerts.map(alert => {
            if (alert.id !== id) return alert
            let enabled = alert.enabled === false
            return Object.assign({}, alert, {
                enabled: enabled,
                armed: enabled ? true : alert.armed !== false,
                stateRevision: Date.now()
            })
        })
        savePriceAlerts(next)
        if (next.some(alert => alert.id === id && alert.enabled !== false)) Qt.callLater(root.refreshWatchlist)
    }

    function removePriceAlert(id) {
        savePriceAlerts(priceAlerts.filter(alert => alert.id !== id))
    }

    function alertDirectionLabel(direction) {
        return t(direction === "below" ? "Falls below" : "Rises above")
    }

    function alertCurrency(alert) {
        return alert.market === "KRX" ? "KRW" : "USD"
    }

    function evaluatePriceAlerts(items) {
        if (priceAlerts.length === 0 || items.length === 0) return
        pendingAlertEvaluation = JSON.stringify({
            sourceId: alertSourceId,
            mode: dataMode,
            environment: kisEnvironment,
            alerts: priceAlerts,
            quotes: items
        })
        if (backend.alertEvaluation.running) {
            alertEvaluationQueued = true
            return
        }
        backend.alertEvaluation.command = ["python3", StockService.stockScript, "alerts", "evaluate"]
        backend.alertEvaluation.running = true
    }

    function applyAlertRuntimeStates(states) {
        if (!Array.isArray(states) || states.length === 0) return
        let byId = ({})
        for (let i = 0; i < states.length; i++) byId[states[i].id] = states[i]
        let changed = false
        let next = priceAlerts.map(alert => {
            let state = byId[alert.id]
            if (!state) return alert
            let armed = state.armed !== false
            let triggeredAt = Number(state.lastTriggeredAt || 0)
            if (armed === (alert.armed !== false) && triggeredAt === Number(alert.lastTriggeredAt || 0)) return alert
            changed = true
            return Object.assign({}, alert, { armed: armed, lastTriggeredAt: triggeredAt })
        })
        if (changed) savePriceAlerts(next)
    }

    function requestCancel(order) {
        if (!order.canCancel || backend.cancel.running) return
        if (kisEnvironment === "prod" && !productionTradingEnabled) return
        cancelTarget = order
        cancelReviewVisible = true
        orderHistoryError = ""
        mainPanel.clearCancelConfirmation()
    }

    function confirmCancel() {
        if (!cancelTarget.orderNumber || backend.cancel.running) return
        if (kisEnvironment === "prod" && (!productionTradingEnabled || mainPanel.cancelConfirmation !== "LIVE")) return
        pendingCancel = JSON.stringify({
            orderNumber: cancelTarget.orderNumber,
            symbol: cancelTarget.symbol || symbol,
            market: cancelTarget.market || market,
            confirmation: kisEnvironment === "prod" ? mainPanel.cancelConfirmation : ""
        })
        backend.cancel.command = ["python3", StockService.stockScript, "cancel", kisEnvironment]
        backend.cancel.running = true
    }

    function orderStateLabel(state) {
        if (state === "filled") return t("Filled")
        if (state === "partial") return t("Partially filled")
        if (state === "pending") return t("Pending")
        if (state === "canceled") return t("Canceled")
        if (state === "rejected") return t("Rejected")
        return t("Submitted")
    }

    function fetchSnapshot() {
        if (!active) return
        if (backend.quote.running) {
            pendingFetch = true
            return
        }
        backend.quote.command = ["python3", StockService.stockScript, "snapshot", symbol, market,
            chartRange, dataMode, kisEnvironment]
        backend.quote.running = true
    }

    function refreshCredentialState() {
        if (backend.credentialStatus.running) return
        backend.credentialStatus.command = ["python3", StockService.stockScript, "credentials", "status"]
        backend.credentialStatus.running = true
    }

    function scheduleRealtime() {
        backend.realtimeReconnect.stop()
        stopRealtime()
        if (shouldStream) backend.realtimeReconnect.restart()
    }

    function startRealtime() {
        if (!shouldStream) return
        if (backend.realtime.running) {
            backend.realtimeReconnect.restart()
            return
        }
        realtimeStatus = "Connecting"
        backend.realtime.command = ["python3", StockService.stockScript, "stream", symbol, kisEnvironment]
        backend.realtime.running = true
    }

    function stopRealtime() {
        realtimeConnected = false
        if (backend.realtime.running) {
            backend.realtime.signal(15)
        }
    }

    function applyRealtime(line) {
        try {
            let event = JSON.parse(line || "{}")
            if (event.status === "connecting") {
                realtimeStatus = "Connecting"
                return
            }
            if (event.status === "connected") {
                realtimeConnected = true
                realtimeStatus = "Live"
                return
            }
            if (event.status === "error") {
                realtimeConnected = false
                realtimeStatus = event.message || "Stream error"
                return
            }
            if (event.status !== "tick") return
            realtimeConnected = true
            realtimeStatus = "Live"
            let nextPoints = (snapshot.points || []).slice()
            if (chartRange === "30M" || chartRange === "1D") {
                let point = { t: Number(event.time) || Math.floor(Date.now() / 1000), v: Number(event.price) }
                if (nextPoints.length > 0 && point.t - Number(nextPoints[nextPoints.length - 1].t) < 60)
                    nextPoints[nextPoints.length - 1] = point
                else
                    nextPoints.push(point)
                let pointLimit = chartRange === "30M" ? 30 : 120
                if (nextPoints.length > pointLimit) nextPoints = nextPoints.slice(nextPoints.length - pointLimit)
            }
            snapshot = Object.assign({}, snapshot, {
                mode: "kis",
                price: Number(event.price),
                change: Number(event.change),
                changePct: Number(event.changePct),
                high: Number(event.high),
                low: Number(event.low),
                volume: Number(event.volume),
                bid: Number(event.bid),
                ask: Number(event.ask),
                points: nextPoints,
                updatedAt: Number(event.time)
            })
        } catch (error) {
            realtimeStatus = "Stream parse error"
        }
    }

    function runAnalysis() {
        if (!aiConfigured || backend.analysis.running) return
        analysisError = ""
        analysisMessage = ""
        let payload = Object.assign({}, snapshot, { chartRange: chartRange, language: language })
        let refreshMode = analysisResult.status === "ok" ? "force" : "cache"
        pendingAnalysis = JSON.stringify(payload)
        backend.analysis.command = ["python3", StockService.stockScript, "analyze", aiProvider,
            analysisProfile, refreshMode]
        backend.analysis.running = true
    }

    function resetAnalysis() {
        analysisResult = ({})
        analysisError = ""
        analysisMessage = ""
        analysisReportVisible = false
    }

    function openForecasts() {
        analysisReportVisible = false
        forecastVisible = true
        forecastError = ""
        forceActiveFocus()
        if (quantTab === "forecasts") refreshForecasts(true)
        else if (quantTab === "ai_eval") refreshAiValidation()
        else if (quantTab === "usage") refreshAiUsage()
        else if (quantTab === "screener") refreshScreener()
        else if (quantTab === "automation") refreshAutomation()
    }

    function closeForecasts() {
        forecastVisible = false
        forecastQueued = false
        screenerQueued = false
    }

    function refreshForecasts(evaluate) {
        if (backend.forecast.running) {
            forecastQueued = true
            return
        }
        forecastError = ""
        if (evaluate && Number(snapshot.price || 0) > 0) {
            pendingForecastInput = JSON.stringify({
                symbol: symbol,
                market: market,
                mode: dataMode,
                environment: kisEnvironment,
                price: Number(snapshot.price),
                updatedAt: Number(snapshot.updatedAt || 0)
            })
            backend.forecast.command = ["python3", StockService.stockScript, "forecasts", "evaluate"]
        } else {
            pendingForecastInput = ""
            backend.forecast.command = ["python3", StockService.stockScript, "forecasts", "list", symbol, "50"]
        }
        backend.forecast.running = true
    }

    function deleteForecast(id) {
        if (!id || backend.deleteForecast.running) return
        forecastError = ""
        backend.deleteForecast.command = ["python3", StockService.stockScript, "forecasts", "delete", id]
        backend.deleteForecast.running = true
    }

    function chooseQuantTab(value) {
        quantTab = value
        if (value === "forecasts") refreshForecasts(true)
        else if (value === "ai_eval") refreshAiValidation()
        else if (value === "usage") refreshAiUsage()
        else if (value === "screener") refreshScreener()
        else if (value === "automation") refreshAutomation()
    }

    function resetBacktest() {
        backtestResult = ({})
        backtestError = ""
    }

    function resetComparison() {
        comparisonResult = ({ items: [] })
        comparisonError = ""
    }

    function resetAiValidation() {
        aiValidationResult = ({ models: [], calibration: [], signals: {} })
        aiValidationError = ""
        aiValidationQueued = false
    }

    function refreshAiValidation() {
        if (backend.aiValidation.running) {
            aiValidationQueued = true
            return
        }
        aiValidationError = ""
        backend.aiValidation.command = ["python3", StockService.stockScript, "validate-ai", symbol,
            String(validationConfidenceFloor), "200"]
        backend.aiValidation.running = true
    }

    function refreshAiUsage() {
        if (backend.aiUsage.running) return
        aiUsageError = ""
        backend.aiUsage.command = ["python3", StockService.stockScript, "ai-usage", "30", "100"]
        backend.aiUsage.running = true
    }

    function resetScreener() {
        screenerState = ({ items: [], counts: {} })
        screenerError = ""
        screenerQueued = false
    }

    function refreshScreener() {
        if (backend.screener.running) {
            screenerQueued = true
            return
        }
        screenerError = ""
        if (watchlist.length === 0) {
            screenerState = ({ status: "ok", items: [], counts: { screened: 0, total: 0, bullish: 0, neutral: 0, bearish: 0 } })
            return
        }
        pendingScreener = JSON.stringify(watchlist)
        backend.screener.command = ["python3", StockService.stockScript, "screen", dataMode, kisEnvironment]
        backend.screener.running = true
    }

    function refreshAutomation() {
        if (backend.automation.running) {
            automationRefreshQueued = true
            return
        }
        automationError = ""
        pendingAutomation = ""
        backend.automation.command = ["python3", StockService.stockScript, "automation", "status"]
        backend.automation.running = true
    }

    function openAutopilot() {
        autopilotVisible = true
        autopilotError = ""
        forceActiveFocus()
        refreshAutopilot()
        refreshAutomation()
    }

    function closeAutopilot() {
        autopilotVisible = false
    }

    function openLiveAutopilotReview() {
        if (!autopilotCanStart || !liveAutopilotContext || autopilotRunning) return
        liveAutopilotReviewVisible = true
        forceActiveFocus()
        refreshAutomation()
    }

    function closeLiveAutopilotReview() {
        if (autopilotAction === "autopilot-start") return
        liveAutopilotReviewVisible = false
    }

    function runAutopilotAction(action, payload) {
        if (backend.autopilot.running) {
            if (action === "autopilot-status") autopilotRefreshQueued = true
            return
        }
        autopilotError = ""
        autopilotAction = action
        pendingAutopilot = JSON.stringify(payload || {})
        backend.autopilot.command = ["python3", StockService.stockScript, "automation", action]
        backend.autopilot.running = true
    }

    function refreshAutopilot() {
        runAutopilotAction("autopilot-status", {})
    }

    function refreshAutopilotNow() {
        autopilotError = ""
        autopilotRefreshAutomationQueued = true
        runAutopilotAction("autopilot-refresh", {
            environment: autopilotEnvironment,
            aiProvider: aiProvider,
            analysisProfile: analysisProfile,
            language: language,
            strategy: backtestStrategy,
            automaticSelection: autopilotState.automaticSelection !== false,
            universe: watchlist
        })
        scheduleAccount()
    }

    function retryAutopilot() {
        if (autopilotBusy || autopilotEmergencyBusy || automationBusy) return
        autopilotError = ""
        if (autopilotHalted
                && String((automationState.policy || {}).haltClass
                    || autopilotState.haltClass || "") === "manual") {
            startAutopilot(false, true)
            return
        }
        refreshAutopilotNow()
    }

    function discoverAutopilotCandidates() {
        runAutopilotAction("autopilot-scan", {
            environment: kisEnvironment,
            aiProvider: aiProvider,
            analysisProfile: analysisProfile,
            language: language,
            strategy: backtestStrategy,
            automaticSelection: autopilotState.automaticSelection !== false,
            universe: watchlist
        })
    }

    function setAutopilotAutomaticSelection(enabled) {
        if (autopilotBusy) return
        autopilotState = Object.assign({}, autopilotState, { automaticSelection: enabled })
        runAutopilotAction("autopilot-configure", { automaticSelection: enabled })
    }

    function prepareAutomaticAutopilotSelection() {
        if (autopilotState.automaticSelection === false)
            autopilotState = Object.assign({}, autopilotState, { automaticSelection: true })
    }

    function toggleAutopilotCandidate(key) {
        if (!key || autopilotBusy) return
        let selected = Array.isArray(autopilotState.selectedKeys) ? autopilotState.selectedKeys.slice() : []
        let index = selected.indexOf(key)
        if (index >= 0) selected.splice(index, 1)
        else selected.push(key)
        let candidates = (autopilotState.candidates || []).map(candidate =>
            Object.assign({}, candidate, { selected: selected.indexOf(candidate.key) >= 0 }))
        autopilotState = Object.assign({}, autopilotState, {
            automaticSelection: false,
            selectedKeys: selected,
            selectedCount: selected.length,
            candidates: candidates
        })
        runAutopilotAction("autopilot-configure", {
            automaticSelection: false,
            selectedKeys: selected
        })
    }

    function startAutopilot(liveConfirmed, forceAutomaticSelection) {
        let useAutomaticSelection = forceAutomaticSelection === true
            || autopilotState.automaticSelection !== false
        if (forceAutomaticSelection === true) prepareAutomaticAutopilotSelection()
        if (!autopilotCanStart || autopilotRunning) return
        if (liveAutopilotContext && liveConfirmed !== true) {
            openLiveAutopilotReview()
            return
        }
        liveAutopilotReviewVisible = false
        runAutopilotAction("autopilot-start", {
            confirmation: liveAutopilotContext
                ? "START KIS LIVE AUTOPILOT" : "START KIS PAPER AUTOPILOT",
            environment: liveAutopilotContext ? "prod" : "paper",
            aiProvider: aiProvider,
            analysisProfile: analysisProfile,
            language: language,
            strategy: backtestStrategy,
            automaticSelection: useAutomaticSelection,
            universe: watchlist
        })
    }

    function stopAutopilot() {
        if (autopilotBusy || !autopilotState.enabled) return
        runAutopilotAction("autopilot-stop", {
            confirmation: autopilotState.environment === "prod"
                ? "STOP KIS LIVE AUTOPILOT" : "STOP KIS PAPER AUTOPILOT"
        })
    }

    function emergencyStopAutopilot() {
        if (backend.autopilotEmergency.running) return
        autopilotError = ""
        pendingAutopilotEmergency = JSON.stringify({
            confirmation: "EMERGENCY STOP AI AUTOPILOT"
        })
        backend.autopilotEmergency.command = [
            "python3", StockService.stockScript, "automation", "autopilot-emergency-stop"
        ]
        backend.autopilotEmergency.running = true
    }

    function autopilotPhaseLabel() {
        if (autopilotEmergencyBusy) return t("Stopping")
        if (autopilotBusy && (autopilotAction === "autopilot-scan"
                || autopilotAction === "autopilot-start")) return t("Analyzing…")
        if (autopilotBusy && autopilotAction === "autopilot-stop") return t("Stopping")
        let schedulerState = autopilotSchedulerState()
        if (schedulerState === "exit_only_protection") return t("Capital Protection")
        if (autopilotHalted || ["halted", "audit_failure", "accounting_failure",
                "live_session_revoked"].indexOf(schedulerState) >= 0) return t("Paused for Safety")
        if (schedulerState === "waiting_reconciliation") return t("Verifying Order")
        if (schedulerState === "waiting_accounting") return t("Verifying Holdings")
        if (schedulerState === "operator_action") return t("Action Required")
        if (schedulerState === "market_closed") return t("Waiting for Market")
        if (schedulerState === "no_target" || schedulerState === "researching"
                || (autopilotRunning && autopilotState.automaticSelection !== false
                    && Number(autopilotState.selectedCount || 0) === 0))
            return t("Finding Candidates")
        if (schedulerState === "protection_error"
                || schedulerState === "protection_retrying") return t("Retrying Protection")
        if (schedulerState === "session_error" || schedulerState === "error"
                || schedulerState === "retrying")
            return t("Retrying")
        if (schedulerState === "protective_exit_ready"
                || schedulerState === "protective_exit_executed")
            return t("Protective Exit")
        if (schedulerState === "auto_executed") return t("Order Submitted")
        if (schedulerState === "observed" || schedulerState === "throttled")
            return t("Monitoring")
        if (autopilotRunning) return t("Running")
        if (autopilotState.phase === "ready") return t("Ready")
        if (autopilotState.phase === "stopped") return t("Stopped")
        if (autopilotState.phase === "error") return t("Error")
        return t("Idle")
    }

    function autopilotPhaseColor() {
        let schedulerState = autopilotSchedulerState()
        if (schedulerState === "exit_only_protection") return "#ff9f0a"
        if (autopilotHalted || autopilotState.phase === "error" || autopilotError !== ""
                || ["halted", "audit_failure", "accounting_failure",
                    "live_session_revoked"].indexOf(schedulerState) >= 0)
            return negativeColor
        if (schedulerState === "protection_error"
                || schedulerState === "protection_retrying"
                || schedulerState === "session_error"
                || schedulerState === "retrying"
                || schedulerState === "waiting_accounting"
                || schedulerState === "operator_action"
                || schedulerState === "error") return "#ff9f0a"
        if (autopilotRunning && schedulerState !== "market_closed") return positiveColor
        if (autopilotBusy || autopilotState.phase === "ready") return "#0a84ff"
        return secondaryColor
    }

    function autopilotSchedulerState() {
        let policy = automationState.policy || ({})
        if (!autopilotRunning && !autopilotHalted
                && !(policy.enabled && policy.autopilotEnabled)) return ""
        return String(automationLastRun.state || "")
    }

    function autopilotSchedulerStateLabel() {
        let labels = {
            waiting_reconciliation: "Order verification",
            waiting_accounting: "Broker position reconciliation",
            operator_action: "Operator action required",
            exit_only_protection: "Exit-only capital protection",
            market_closed: "Market wait",
            throttled: "Scheduled monitoring",
            no_target: "Candidate search",
            researching: "Candidate search",
            observed: "Analysis complete",
            protection_error: "Protective monitoring retry",
            protection_retrying: "Protective monitoring retry",
            session_error: "Market connection retry",
            retrying: "Automatic check retry",
            error: "Automatic check retry",
            halted: "Safety halt",
            audit_failure: "Audit safety halt",
            accounting_failure: "Account safety halt",
            live_session_revoked: "Live session revoked",
            protective_exit_ready: "Protective sell recheck",
            protective_exit_executed: "Protective sell verification",
            auto_executed: "Order verification",
            disabled: "Disabled",
            paused: "Paused"
        }
        let state = autopilotSchedulerState()
        return t(labels[state] || (state !== "" ? "Checking" : "Idle"))
    }

    function autopilotNeedsRetry() {
        let state = autopilotSchedulerState()
        let manualHalt = autopilotHalted
            && String((automationState.policy || {}).haltClass
                || autopilotState.haltClass || "") === "manual"
        return manualHalt || autopilotError !== ""
            || autopilotState.phase === "error"
            || ["session_error", "retrying", "error", "protection_error",
                "protection_retrying"].indexOf(state) >= 0
    }

    function autopilotHardStop() {
        return autopilotHalted
            && String((automationState.policy || {}).haltClass
                || autopilotState.haltClass || "") !== "manual"
    }

    function autopilotSimpleStatus() {
        if (autopilotEmergencyBusy || (autopilotBusy && autopilotAction === "autopilot-stop"))
            return t("Turning automatic trading off…")
        if (autopilotBusy && autopilotAction === "autopilot-start")
            return t("Starting automatic trading…")
        if (autopilotBusy && autopilotAction === "autopilot-scan")
            return t("Checking news, trends, and candidates…")
        let state = autopilotSchedulerState()
        if (autopilotHardStop())
            return t("Trading is paused to protect your account. Open Details to review it.")
        if (autopilotNeedsRetry())
            return t("Automatic trading paused. Press Try Again to recover.")
        if (state === "exit_only_protection")
            return t("Protecting your holdings. New purchases will resume after conditions recover.")
        if (state === "waiting_reconciliation" || state === "waiting_accounting")
            return t("Checking the latest order and holdings before continuing.")
        if (state === "operator_action")
            return t("Check your account or API settings, then press Refresh Now.")
        if (["protection_error", "protection_retrying", "session_error",
                "retrying", "error"].indexOf(state) >= 0)
            return t("The connection is being checked again automatically.")
        if (state === "market_closed")
            return t("The market is closed. Trading starts automatically when it opens.")
        if (state === "no_target" || state === "researching"
                || (autopilotRunning && Number(autopilotState.selectedCount || 0) === 0))
            return t("Checking news and trends to find suitable stocks.")
        if (state === "protective_exit_ready" || state === "protective_exit_executed")
            return t("A rapid drop was detected, so your holding is being protected.")
        if (state === "auto_executed")
            return t("An order was sent. Its result is being checked.")
        if (autopilotRunning)
            return t("Automatic trading is monitoring the market and your holdings.")
        return t("Automatic trading is off. Turn it on to start.")
    }

    function autopilotHoldingText() {
        if (accountState.status !== "ok") return "—"
        return t("%1 stocks", [(accountState.holdings || []).length])
    }

    function autopilotTodayProfitText() {
        let environment = autopilotEnvironment
        let risk = automationState.risk || ({})
        let grouped = ({})
        Object.keys(risk).forEach(function(key) {
            if (key !== environment && key.indexOf(environment + ":") !== 0) return
            let suffix = key === environment ? "KRX" : key.slice(environment.length + 1)
            let group = suffix === "NASDAQ" || suffix === "NYSE" ? "US" : suffix
            let item = risk[key] || ({})
            if (!grouped[group]
                    || Number(item.updatedAt || 0) > Number(grouped[group].updatedAt || 0))
                grouped[group] = item
        })
        let today = Qt.formatDateTime(new Date(), "yyyy-MM-dd")
        let start = 0
        let current = 0
        let found = false
        Object.keys(grouped).forEach(function(group) {
            let item = grouped[group] || ({})
            if (String(item.date || "") !== today) return
            let base = Number(item.dayStartEvaluation || 0)
            let value = Number(item.lastEvaluation || 0)
            if (base <= 0) return
            start += base
            current += value
            found = true
        })
        if (!found || start <= 0) return "—"
        let amount = current - start
        let percent = amount / start * 100
        return StockService.signedMoney(amount, "KRW") + " · "
            + StockService.signed(percent, 2) + "%"
    }

    function autopilotNextCheckText() {
        if (!autopilotState.enabled) return t("Off")
        let state = autopilotSchedulerState()
        if (state === "market_closed") return t("When market opens")
        if (["retrying", "error", "session_error", "protection_error",
                "protection_retrying"].indexOf(state) >= 0) return t("Soon")
        let seconds = Math.max(0, Number(automationLastRun.nextRunInSeconds || 0))
        return seconds > 0 ? autopilotCountdown(seconds) : t("Within a minute")
    }

    function autopilotSchedulerRawMessage() {
        let run = automationLastRun || ({})
        let policy = automationState.policy || ({})
        let scheduler = automationScheduler || ({})
        let values = autopilotHalted ? [
            policy.haltReason,
            autopilotState.haltReason,
            run.haltReason,
            scheduler.haltReason,
            run.message,
            run.reasonMessage,
            scheduler.message,
            autopilotState.lastError
        ] : [
            run.message,
            run.reasonMessage,
            run.haltReason,
            scheduler.message,
            scheduler.haltReason,
            policy.haltReason,
            autopilotState.lastError
        ]
        let errors = run.protection && Array.isArray(run.protection.errors)
            ? run.protection.errors : []
        if (errors.length > 0) values.push(errors[0].message)
        let sessionErrors = Array.isArray(run.sessionErrors) ? run.sessionErrors : []
        if (sessionErrors.length > 0) values.push(sessionErrors[0].message)
        let sessions = Array.isArray(run.sessions) ? run.sessions : []
        if (sessions.length > 0) values.push(sessions[0].message)
        for (let index = 0; index < values.length; ++index) {
            let value = String(values[index] || "").trim()
            if (value !== "") return value
        }
        return ""
    }

    function autopilotGateLabel(code) {
        let labels = {
            candidate_selected: "Candidate selection",
            technical: "Technical signal",
            kis_data: "KIS market data",
            market_session: "Market session",
            market_data_freshness: "Market data freshness",
            market_safety_freshness: "Market safety freshness",
            market_tradable: "Tradable state",
            volatility_interruption: "Volatility interruption",
            price_limit_clear: "Daily price limit",
            instrument_restrictions: "Instrument restrictions",
            corporate_action_adjustment: "Corporate-action adjustment",
            ai_available: "AI analysis",
            ai_freshness: "AI analysis freshness",
            ai_confidence: "AI confidence",
            ai_agreement: "AI agreement",
            ai_models: "AI model confirmation",
            signal_alignment: "AI and technical alignment",
            ai_tail_risk: "AI downside risk",
            news_status: "News relevance",
            news_quality: "News evidence quality",
            verified_direct_news: "Verified company event",
            behavior_status: "Market psychology evidence",
            behavior_risk: "Market crowding risk",
            walk_forward: "Walk-forward validation",
            oos_edge: "Out-of-sample edge",
            backtest_drawdown: "Backtest drawdown",
            daily_loss: "Daily loss limit",
            portfolio_drawdown: "Portfolio drawdown limit",
            daily_orders: "Daily order limit",
            cooldown: "Trade cooldown",
            sector_data: "Sector data",
            sector_concentration: "Sector concentration",
            liquidity_data: "Liquidity data",
            market_participation: "Market participation",
            correlation_data: "Correlation data",
            portfolio_correlation: "Portfolio correlation",
            volatility_data: "Volatility data",
            risk_sizing: "Risk-based order size",
            sizing: "Sellable quantity",
            portfolio_tail_data: "Portfolio risk history",
            portfolio_var: "Portfolio VaR",
            portfolio_cvar: "Portfolio expected shortfall",
            portfolio_stress: "Portfolio stress test",
            protective_exit: "Protective exit"
        }
        return t(labels[String(code || "")] || String(code || ""))
    }

    function autopilotFailedGates() {
        let plan = automationLastRun.plan || ({})
        let gates = Array.isArray(plan.failedGates) ? plan.failedGates : []
        return gates.filter(gate => String(gate || "") !== "")
    }

    function autopilotFailedGateText(limit) {
        let gates = autopilotFailedGates()
        if (gates.length === 0) return ""
        let count = Math.max(1, Number(limit || 4))
        let labels = gates.slice(0, count).map(gate => autopilotGateLabel(gate))
        if (gates.length > count) labels.push(t("%1 more", [gates.length - count]))
        return labels.join(" · ")
    }

    function autopilotSchedulerReason() {
        let raw = autopilotSchedulerRawMessage()
        if (raw !== "") return t(raw)
        let failed = autopilotFailedGateText(4)
        return failed === "" ? "" : t("Conditions not met · %1", [failed])
    }

    function autopilotStatusDetail() {
        if (autopilotError !== "") return t(autopilotError)
        if (autopilotBusy && (autopilotAction === "autopilot-scan"
                || autopilotAction === "autopilot-start"))
            return t("Analyzing trends, news, and risk…")
        let state = autopilotSchedulerState()
        let reason = autopilotSchedulerReason()
        let selected = Number(autopilotState.selectedCount || 0)
        let automatic = autopilotState.automaticSelection !== false
        if (state === "exit_only_protection")
            return reason !== ""
                ? t("Capital protection active · %1. New entries are stopped; open positions remain monitored and may be sold automatically.", [reason])
                : t("New entries are stopped; open positions remain monitored and may be sold automatically to limit losses.")
        if (autopilotHalted || ["halted", "audit_failure", "accounting_failure",
                "live_session_revoked"].indexOf(state) >= 0)
            return reason !== "" ? reason : t("A safety check stopped automation. Review Advanced Safety.")
        if (state === "waiting_reconciliation")
            return reason !== "" ? reason : t("Checking the final KIS order result before continuing.")
        if (state === "waiting_accounting")
            return reason !== ""
                ? t("Broker position reconciliation will retry · %1", [reason])
                : t("Reconciling broker holdings before automatic trading continues.")
        if (state === "operator_action")
            return reason !== "" ? t("Action required · %1", [reason])
                : t("Your action is required before automatic trading can continue.")
        if (state === "market_closed")
            return reason !== "" ? reason
                : t("The selected market is closed. Monitoring resumes automatically at the next safety window.")
        if (state === "no_target" || state === "researching"
                || (autopilotRunning && automatic && selected === 0))
            return t("Searching for candidates that meet every trading condition.")
        if (state === "protection_error" || state === "protection_retrying")
            return reason !== "" ? t("Protective monitoring will retry · %1", [reason])
                : t("Protective monitoring will retry automatically.")
        if (state === "session_error" || state === "error" || state === "retrying")
            return reason !== "" ? t("Automatic check will retry · %1", [reason])
                : t("Automatic check will retry on the next cycle.")
        if (state === "protective_exit_ready")
            return t("A rapid-loss rule was triggered. Rechecking the protective sell.")
        if (state === "protective_exit_executed")
            return t("Protective sell submitted. Verifying the final KIS result.")
        if (state === "auto_executed")
            return t("Order submitted. Verifying the final KIS result before the next trade.")
        if (state === "observed") {
            let failed = autopilotFailedGateText(4)
            return failed !== "" ? t("No trade · conditions not met: %1", [failed])
                : t("No trade is needed now. Monitoring continues.")
        }
        if (state === "throttled") {
            if (automatic && selected === 0)
                return t("Searching for candidates that meet every trading condition.")
            let seconds = Math.max(0, Number(automationLastRun.nextRunInSeconds || 0))
            return seconds > 0
                ? t("Monitoring · next automatic check in %1", [autopilotCountdown(seconds)])
                : t("Monitoring selected candidates and protective sell rules.")
        }
        if (autopilotRunning)
            return selected > 0
                ? t("Monitoring %1 selected candidates and protective sell rules.", [selected])
                : t("Searching for candidates that meet every trading condition.")
        return reason
    }

    function autopilotCountdown(seconds) {
        let total = Math.max(0, Math.ceil(Number(seconds || 0)))
        if (total < 60) return t("%1 sec", [total])
        let minutes = Math.ceil(total / 60)
        return t("%1 min", [minutes])
    }

    function autopilotTime(value) {
        if (!Number(value)) return t("Not yet")
        return Qt.formatDateTime(new Date(Number(value) * 1000), "MM.dd  hh:mm")
    }

    function autopilotBlockingReason() {
        if (autopilotError !== "") return t(autopilotError)
        if (dataMode !== "kis") return t("Select KIS Live as the data source in Settings.")
        if (!tradingConfigured)
            return t("Save KIS %1 credentials and account in Settings.", [
                t(liveAutopilotContext ? "Production" : "Paper")
            ])
        if (!aiConfigured) return t("Select an AI provider in Settings.")
        if (autopilotSchedulerState() === "exit_only_protection")
            return autopilotStatusDetail()
        if (autopilotHalted) {
            let reason = autopilotSchedulerReason()
            return reason !== "" ? reason
                : t("Reset the safety kill switch in Advanced Safety before restarting.")
        }
        if (liveAutopilotContext && !productionTradingEnabled)
            return t("Unlock production trading in Settings first.")
        if (liveAutopilotContext && !(automationState.policy || {}).liveConsent)
            return t("Accept live automation risk consent in Settings first.")
        if (liveAutopilotContext && !liveAutopilotEligible)
            return t("Complete live readiness before starting · %1/%2 passed", [
                Number(liveReadiness.passed || 0), Number(liveReadiness.total || 0)
            ])
        if (autopilotState.environment === autopilotEnvironment
                && autopilotState.automaticSelection === false
                && Number(autopilotState.selectedCount || 0) === 0)
            return t("Select at least one AI candidate.")
        if (autopilotState.environment === autopilotEnvironment
                && autopilotState.automaticSelection === false
                && autopilotState.lastError) return t(autopilotState.lastError)
        return ""
    }

    function controlAutomation(action) {
        if (backend.automation.running) return
        let liveArmed = (automationState.policy || {}).executionMode === "live"
        let confirmation = action === "arm" ? "ARM PAPER DRY RUN"
            : (action === "arm-paper" ? "ARM KIS PAPER EXECUTION"
            : (action === "arm-live" ? "ARM KIS LIVE EXECUTION"
            : (action === "scheduler-enable" ? "ENABLE OBSERVE SCHEDULER"
            : (action === "scheduler-auto-enable" ? (liveArmed
                ? "ENABLE PROMOTION-GATED LIVE AUTO" : "ENABLE PROMOTION-GATED PAPER AUTO")
            : (action === "reset-kill" ? "RESET PAPER KILL SWITCH" : "")))))
        automationError = ""
        if (action !== "scheduler-enable" && action !== "scheduler-disable"
                && action !== "scheduler-auto-enable" && action !== "scheduler-auto-disable") {
            automationPlan = ({})
            automationExecution = ({})
        }
        pendingAutomation = JSON.stringify({ confirmation: confirmation })
        backend.automation.command = ["python3", StockService.stockScript, "automation", action]
        backend.automation.running = true
    }

    function setAutomationTargetEnabled(enabled) {
        automationTargetEnabled = enabled
        if (frame) frame.save({ automationTargetEnabled: enabled })
    }

    function executeAutomationPlan() {
        if (backend.automation.running || !automationPlan.planId) return
        automationError = ""
        pendingAutomation = JSON.stringify({
            planId: automationPlan.planId,
            confirmation: ((automationState.policy || {}).executionMode === "live"
                ? "EXECUTE KIS LIVE " : "EXECUTE KIS PAPER ") + automationPlan.planId
        })
        backend.automation.command = ["python3", StockService.stockScript, "automation", "execute"]
        backend.automation.running = true
    }

    function reconcileAutomation() {
        if (backend.automation.running) return
        automationError = ""
        pendingAutomation = ""
        backend.automation.command = ["python3", StockService.stockScript, "automation", "reconcile"]
        backend.automation.running = true
    }

    function verifyAutomationOperations() {
        if (backend.automation.running) return
        automationError = ""
        pendingAutomation = JSON.stringify({ confirmation: "VERIFY PAPER OPERATIONS" })
        backend.automation.command = ["python3", StockService.stockScript, "automation", "ops-verify"]
        backend.automation.running = true
    }

    function runAutomationPartOne() {
        if (backend.automation.running) return
        automationError = ""
        automationRefreshQueued = true
        pendingAutomation = JSON.stringify({ confirmation: "RUN OPERATIONS PART ONE" })
        backend.automation.command = ["python3", StockService.stockScript, "automation", "ops-part1"]
        backend.automation.running = true
    }

    function controlAutomationPartTwo(action) {
        if (backend.automation.running) return
        automationError = ""
        automationRefreshQueued = true
        pendingAutomation = JSON.stringify({
            confirmation: action === "start" ? "START KIS PAPER SOAK" : "PAUSE KIS PAPER SOAK"
        })
        backend.automation.command = ["python3", StockService.stockScript, "automation",
            action === "start" ? "ops-part2-start" : "ops-part2-pause"]
        backend.automation.running = true
    }

    function controlLiveReadiness(action) {
        if (backend.automation.running) return
        let confirmation = action === "live-arm-canary"
            ? "ARM MANUAL LIVE CANARY"
            : (action === "live-verify-canary" ? "VERIFY LIVE CANARY"
            : (action === "live-lock" ? "LOCK LIVE AUTOMATION" : ""))
        if (confirmation === "") return
        automationError = ""
        pendingAutomation = JSON.stringify({ confirmation: confirmation })
        backend.automation.command = [
            "python3", StockService.stockScript, "automation", action
        ]
        backend.automation.running = true
    }

    function generateAutomationPlan() {
        if (backend.automation.running) return
        automationError = ""
        pendingAutomation = JSON.stringify({
            symbol: symbol,
            market: market,
            dataMode: dataMode,
            environment: kisEnvironment,
            strategy: backtestStrategy,
            snapshot: {
                name: snapshot.name,
                price: Number(snapshot.price || 0),
                buyingPower: Number(snapshot.buyingPower || 0),
                updatedAt: Number(snapshot.updatedAt || 0),
                marketSafety: snapshot.marketSafety || ({})
            },
            analysis: {
                status: analysisResult.status,
                stance: analysisResult.stance,
                confidence: Number(analysisResult.confidence || 0),
                downProbability: Number(analysisResult.downProbability || 0),
                generatedAt: Number(analysisResult.generatedAt || 0),
                models: analysisResult.models || [],
                ensembleAgreement: analysisResult.ensembleAgreement || ({})
            }
        })
        backend.automation.command = ["python3", StockService.stockScript, "automation", "plan"]
        backend.automation.running = true
    }

    function automationDecisionLabel() {
        if (automationPlan.decision === "ready") return t(
            automationPlan.executionMode === "live" ? "Ready · KIS Live"
                : (automationPlan.executionMode === "paper" ? "Ready · KIS Paper" : "Ready · Dry Run")
        )
        if (automationPlan.decision === "blocked") return t("Blocked")
        if (automationPlan.decision === "hold") return t("Hold")
        return t("No plan")
    }

    function automationDecisionColor() {
        if (automationPlan.decision === "ready") return positiveColor
        if (automationPlan.decision === "blocked") return negativeColor
        if (automationPlan.decision === "hold") return "#ff9f0a"
        return secondaryColor
    }

    function selectScreenerItem(item) {
        if (!item || item.status !== "ok" || !item.symbol || !frame) return
        closeForecasts()
        selectInstrument(item.symbol, item.market || "KRX")
    }

    function formatTokenCount(value) {
        let count = Number(value || 0)
        if (count >= 1000000) return (count / 1000000).toFixed(count >= 10000000 ? 0 : 1) + "M"
        if (count >= 1000) return (count / 1000).toFixed(count >= 100000 ? 0 : 1) + "K"
        return Math.round(count).toString()
    }

    function runBacktest() {
        if (backend.backtest.running) return
        backtestResult = ({})
        backtestError = ""
        let costs = backtestCostSettings()
        backend.backtest.command = ["python3", StockService.stockScript, "backtest", symbol, market,
            dataMode, kisEnvironment, backtestStrategy, String(costs.commission), String(costs.slippage), String(costs.tax)]
        backend.backtest.running = true
    }

    function backtestCostSettings() {
        if (backtestCostProfile === "ideal") return { commission: 0, slippage: 0, tax: 0 }
        if (backtestCostProfile === "stress") return { commission: 3, slippage: 15, tax: market === "KRX" ? 20 : 0 }
        return { commission: 1.5, slippage: 5, tax: market === "KRX" ? 15 : 0 }
    }

    function runComparison() {
        if (backend.comparison.running) return
        resetComparison()
        let costs = backtestCostSettings()
        backend.comparison.command = ["python3", StockService.stockScript, "compare", symbol, market,
            dataMode, kisEnvironment, String(costs.commission), String(costs.slippage), String(costs.tax)]
        backend.comparison.running = true
    }

    function inspectComparisonStrategy(strategy) {
        setBacktestStrategy(strategy)
        resetBacktest()
        quantTab = "backtest"
    }

    function setBacktestStrategy(strategy) {
        backtestStrategy = strategy
        if (frame) frame.save({ backtestStrategy: strategy })
    }

    function comparisonRiskColor(risk) {
        return risk === "low" ? positiveColor : (risk === "high" ? negativeColor : "#ff9f0a")
    }

    function comparisonRiskLabel(risk) {
        return t(risk === "low" ? "Low overfit risk" : (risk === "high" ? "High overfit risk" : "Moderate risk"))
    }

    function validationStatusColor(status) {
        return status === "usable" ? positiveColor : (status === "limited" ? "#ff9f0a" : secondaryColor)
    }

    function calibrationBucket(index) {
        let buckets = aiValidationResult.calibration || []
        return buckets.length > index ? buckets[index] : ({})
    }

    function walkForwardColor() {
        let status = (backtestResult.walkForward || {}).status || ""
        return status === "robust" ? positiveColor : (status === "weak" ? negativeColor : "#ff9f0a")
    }

    function backtestDate(value) {
        if (!Number(value)) return ""
        return Qt.formatDateTime(new Date(Number(value) * 1000), "yyyy.MM.dd")
    }

    function forecastStatusLabel(item) {
        if (item.status !== "resolved") return t("Open")
        return t(item.correct === true ? "Correct" : "Miss")
    }

    function forecastStatusColor(item) {
        if (item.status !== "resolved") return "#0a84ff"
        return item.correct === true ? positiveColor : negativeColor
    }

    function forecastReturn(item) {
        return Number(item.status === "resolved" ? item.returnPct : item.currentReturnPct || 0)
    }

    function forecastTargetLabel(item) {
        let value = Number(item.targetSessionAt || item.targetAt || 0)
        if (!value) return ""
        let date = Qt.formatDateTime(new Date(value * 1000), "yyyy.MM.dd")
        return t(item.status === "resolved" ? "%1 close" : "%1 est.", [date])
    }

    function analysisTime(value) {
        if (!Number(value)) return ""
        return Qt.formatDateTime(new Date(Number(value) * 1000), "yyyy.MM.dd  hh:mm")
    }

    function stanceLabel(value) {
        if (value === "bullish") return t("Bullish")
        if (value === "bearish") return t("Bearish")
        return t(value === "neutral" ? "Neutral" : "Awaiting")
    }

    function chooseRange(value) {
        chartRange = value
        hoverIndex = -1
    }

    function selectMarket(nextMarket) {
        let next = String(nextMarket || "KRX").toUpperCase()
        if (next === market) return
        let fallback = { KRX: "005930", NASDAQ: "AAPL", NYSE: "BRK.B" }
        let candidate = watchlist.find(item => item.market === next)
        selectInstrument(candidate ? candidate.symbol : fallback[next], next)
    }

    function orderStatusText() {
        if (dataMode === "demo") return t("Local preview only")
        if (kisEnvironment === "prod" && !productionTradingEnabled) return t("Production orders are locked")
        if (!kisConfigured) return t("Save KIS %1 API credentials in Settings", [t(kisEnvironment === "prod" ? "Production" : "Paper")])
        if (!kisAccountConfigured) return t("Save the %1 account number in Settings", [t(kisEnvironment === "prod" ? "Production" : "Paper")])
        if (accountBusy) return t("Checking account…")
        if (accountError !== "") return t(accountError)
        if (accountState.status !== "ok") return t("Account data required")
        if (orderSide === "buy" && quantity > Number(accountState.buyingQuantity || 0)) return t("Exceeds available buy quantity")
        if (orderSide === "sell" && quantity > Number(accountState.sellableQuantity || 0)) return t("Exceeds sellable holdings")
        return t(kisEnvironment === "prod" ? "KIS production order · LIVE confirmation required" : "KIS paper order")
    }

    function preflightStatusText() {
        if (orderError !== "") return t(orderError)
        if (backend.preflight.running) return t("Checking account and risk policy…")
        if (preflightError !== "") return t(preflightError)
        if (!preflightReady) return t("Waiting for server checks…")
        if (demoOrderReady) return t("Local preview only · no broker order will be sent")
        if (kisEnvironment === "paper") return t("KIS paper account checks passed · rechecked at submit")
        let risk = preflightState.risk || {}
        let policy = risk.policy || {}
        if (reviewOrder.side === "buy" && Number(policy.maxBuyOrdersPerDay || 0) > 0)
            return t("Risk Guard passed · daily buys %1/%2 · rechecked at submit",
                [Number(risk.dailyBuyOrders || 0) + 1, policy.maxBuyOrdersPerDay])
        return t("Risk Guard passed · all limits are rechecked at submit")
    }

    function openOrderReview() {
        if (!manualOrderAllowed || !canReviewOrder) return
        let token = String(Date.now()) + "-" + String(Math.random())
        reviewOrder = {
            token: token,
            symbol: symbol,
            side: orderSide,
            orderType: orderType,
            quantity: quantity,
            price: orderPrice,
            currency: snapshot.currency,
            estimatedTotal: estimatedTotal
        }
        orderError = ""
        orderMessage = ""
        preflightState = ({})
        preflightError = ""
        mainPanel.clearLiveConfirmation()
        reviewVisible = true
        runPreflight()
    }

    function closeOrderReview() {
        if (backend.order.running) return
        mainPanel.clearLiveConfirmation()
        reviewVisible = false
        reviewOrder = ({})
        preflightState = ({})
        preflightError = ""
        preflightQueued = false
    }

    function runPreflight() {
        if (!reviewVisible || !reviewOrder.symbol) return
        if (demoOrderReady) {
            preflightState = {
                status: "ok",
                availableQuantity: reviewOrder.quantity,
                risk: { estimatedNotional: reviewOrder.estimatedTotal, projectedPositionPercent: 0 }
            }
            return
        }
        if (backend.preflight.running) {
            preflightQueued = true
            return
        }
        preflightState = ({})
        preflightError = ""
        preflightToken = String(reviewOrder.token)
        pendingPreflight = JSON.stringify({
            symbol: reviewOrder.symbol,
            market: market,
            side: reviewOrder.side,
            orderType: reviewOrder.orderType,
            quantity: reviewOrder.quantity,
            price: reviewOrder.price
        })
        backend.preflight.command = ["python3", StockService.stockScript, "preflight", kisEnvironment]
        backend.preflight.running = true
    }

    function submitOrder() {
        if (!reviewVisible || !reviewOrder.symbol || !preflightReady) return
        if (demoOrderReady) {
            orderMessage = t("%1 %2 shares of %3 · Local preview complete",
                [t(reviewOrder.side === "buy" ? "Buy" : "Sell"), reviewOrder.quantity, reviewOrder.symbol])
            orderError = ""
            closeOrderReview()
            return
        }
        if ((!paperOrderReady && !productionOrderReady) || backend.order.running) return
        if (kisEnvironment === "prod" && mainPanel.liveConfirmation !== "LIVE") return
        orderError = ""
        pendingOrder = JSON.stringify({
            symbol: reviewOrder.symbol,
            market: market,
            side: reviewOrder.side,
            orderType: reviewOrder.orderType,
            quantity: reviewOrder.quantity,
            price: reviewOrder.price,
            confirmation: kisEnvironment === "prod" ? mainPanel.liveConfirmation : ""
        })
        backend.order.command = ["python3", StockService.stockScript, "order", kisEnvironment]
        backend.order.running = true
    }

    Item {
        id: primaryPane
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: Math.min(parent.width, Math.max(708, parent.width / 2))

        Stock.StockMarketOverview {
            id: marketOverview
            root: root
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: implicitHeight
        }

        Stock.StockMainPanel {
            id: mainPanel
            root: root
            anchors { left: parent.left; right: parent.right; top: marketOverview.bottom; bottom: parent.bottom }
            anchors.leftMargin: 22
            anchors.rightMargin: 22
            anchors.topMargin: 14
            anchors.bottomMargin: 18
        }
    }

    Rectangle {
        visible: opacity > 0.002
        anchors { left: primaryPane.right; top: parent.top; bottom: parent.bottom }
        width: 1
        color: root.separatorColor
        opacity: root.xxlLayout ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 22 } }
    }

    Stock.StockXXLSidebar {
        root: root
        visible: opacity > 0.002
        anchors { left: primaryPane.right; right: parent.right; top: parent.top; bottom: parent.bottom }
        opacity: root.xxlLayout ? 1 : 0
        Behavior on opacity { AppleSpring { spring: 22 } }
    }

    Loader {
        id: watchlistLoader
        anchors.fill: parent
        active: root.active
        z: 90
        sourceComponent: Component {
            Stock.StockWatchlistSheet { root: backend.root }
        }
    }

    Loader {
        id: alertsLoader
        anchors.fill: parent
        active: root.active
        z: 120
        sourceComponent: Component {
            Stock.StockAlertsSheet { root: backend.root }
        }
    }

    Loader {
        id: analysisReportLoader
        anchors.fill: parent
        active: root.active
        z: 100
        sourceComponent: Component {
            Stock.StockAnalysisReport { root: backend.root }
        }
    }

    Loader {
        id: quantLoader
        anchors.fill: parent
        active: root.active
        z: 130
        sourceComponent: Component {
            Stock.StockQuantSheet { root: backend.root }
        }
    }

    Loader {
        id: autopilotLoader
        anchors.fill: parent
        active: root.active
        z: 150
        sourceComponent: Component {
            Stock.StockAutopilotSheet { root: backend.root }
        }
    }

    Loader {
        id: liveAutopilotReviewLoader
        anchors.fill: parent
        active: root.active
        z: 160
        sourceComponent: Component {
            Stock.StockLiveAutopilotReview { root: backend.root }
        }
    }

    Loader {
        id: activityLoader
        anchors.fill: parent
        active: root.active
        z: 110
        sourceComponent: Component {
            Stock.StockActivitySheet { root: backend.root }
        }
    }




}
