import QtQuick
import QtQuick.Controls
import Quickshell.Io

Item {
    id: ed
    property int index: -1
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

    implicitWidth: 440
    implicitHeight: col.implicitHeight

    readonly property bool kisConfigured: kisEnvironment === "prod" ? !!credentialState.kisProd : !!credentialState.kisPaper
    readonly property bool kisAccountConfigured: kisEnvironment === "prod" ? !!credentialState.kisProdAccount : !!credentialState.kisPaperAccount

    onIndexChanged: reload()
    Component.onCompleted: {
        reload()
        refreshCredentialState()
        refreshRiskPolicy()
    }

    Connections {
        target: StockService
        function onCredentialsChanged() {
            ed.refreshCredentialState()
            ed.refreshModelCatalog(true)
        }
        function onRiskPolicyChanged() { ed.refreshRiskPolicy() }
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

    function reload() {
        if (index < 0) return
        let data = WidgetsService.getData(index)
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
        if (index >= 0) WidgetsService.setData(index, patch)
    }

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

    Column {
        id: col
        width: parent.width
        spacing: 12

        Row {
            width: parent.width
            height: 24
            Text {
                text: "Stocks"
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
                label: ed.credentialState.keychain ? "Keychain Ready" : "Keychain"
                ready: !!ed.credentialState.keychain
            }
        }

        Column {
            width: parent.width
            spacing: 7
            LabelText { text: "Symbol" }
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
                title: "Market"
                options: StockService.marketOptions
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
                title: "Default Range"
                options: StockService.rangeOptions
                selectedId: ed.range
                onSelected: id => { ed.range = id; ed.save({ range: id }) }
            }
        }

        Row {
            width: parent.width
            spacing: 16
            OptionGroup {
                width: (parent.width - 16) / 2
                title: "Data Source"
                options: StockService.dataModeOptions
                selectedId: ed.dataMode
                onSelected: id => { ed.dataMode = id; ed.save({ dataMode: id }) }
            }
            OptionGroup {
                width: (parent.width - 16) / 2
                title: "KIS Environment"
                options: StockService.kisEnvironmentOptions
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

        Rectangle {
            width: parent.width
            height: kisCredentials.implicitHeight + 20
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.055)
            border.color: Qt.rgba(1, 1, 1, 0.10)
            border.width: 1
            Column {
                id: kisCredentials
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8
                Row {
                    width: parent.width
                    Text {
                        text: "KIS " + (ed.kisEnvironment === "prod" ? "Production" : "Paper")
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Item { width: parent.width - parent.children[0].width - kisStatus.width; height: 1 }
                    StatusBadge {
                        id: kisStatus
                        label: ed.kisConfigured && ed.kisAccountConfigured ? "Trade Ready" : (ed.kisConfigured ? "Quotes Ready" : "Not Saved")
                        ready: ed.kisConfigured && ed.kisAccountConfigured
                    }
                }
                CredentialField {
                    label: "App Key"
                    configured: ed.kisConfigured
                    onRequested: (value, field) => ed.storeCredential(
                        ed.kisEnvironment === "prod" ? "kis_prod_app_key" : "kis_paper_app_key", value, field)
                }
                CredentialField {
                    label: "App Secret"
                    configured: ed.kisConfigured
                    onRequested: (value, field) => ed.storeCredential(
                        ed.kisEnvironment === "prod" ? "kis_prod_app_secret" : "kis_paper_app_secret", value, field)
                }
                CredentialField {
                    label: "Account Number (8-2)"
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
                        text: "Production Orders"
                        color: "#ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Item { width: parent.width - parent.children[0].width - productionStatus.width; height: 1 }
                    StatusBadge {
                        id: productionStatus
                        label: ed.productionTradingEnabled ? "Enabled" : "Locked"
                        ready: false
                    }
                }
                Text {
                    width: parent.width
                    text: ed.productionTradingEnabled
                        ? "Every live order still requires typing LIVE in its confirmation sheet."
                        : "Type ENABLE LIVE to permit production order confirmation screens."
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
                            text: riskProcess.running ? "Saving…" : (ed.productionTradingEnabled ? "Lock" : "Enable")
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
                    text: "Risk Guard"
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
                        label: "Per order · KRW"
                        policyKey: "maxOrderValueKrw"
                        value: ed.riskPolicy.maxOrderValueKrw
                    }
                    RiskField {
                        width: (parent.width - 8) / 2
                        label: "Daily buys · KRW"
                        policyKey: "maxDailyBuyValueKrw"
                        value: ed.riskPolicy.maxDailyBuyValueKrw
                    }
                }
                Row {
                    width: parent.width
                    spacing: 8
                    RiskField {
                        width: (parent.width - 8) / 2
                        label: "Buy orders / day"
                        policyKey: "maxBuyOrdersPerDay"
                        value: ed.riskPolicy.maxBuyOrdersPerDay
                        maximum: 1000
                    }
                    RiskField {
                        width: (parent.width - 8) / 2
                        label: "Max position · %"
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
                title: "AI Provider"
                options: StockService.providerOptions
                selectedId: ed.aiProvider
                onSelected: id => { ed.aiProvider = id; ed.save({ aiProvider: id }) }
            }
            OptionGroup {
                width: parent.width
                title: "Analysis Quality"
                options: StockService.analysisProfileOptions
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
                text: StockService.profileModels(ed.analysisProfile)
                    + (ed.modelMessage !== "" ? "  ·  " + ed.modelMessage : "")
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
                    text: modelProcess.running ? "Syncing" : "Refresh"
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
                label: "OpenAI API Key"
                configured: !!ed.credentialState.openai
                onRequested: (value, field) => ed.storeCredential("openai_api_key", value, field)
            }
            CredentialField {
                width: (parent.width - 10) / 2
                label: "Claude API Key"
                configured: !!ed.credentialState.claude
                onRequested: (value, field) => ed.storeCredential("anthropic_api_key", value, field)
            }
        }

        Text {
            visible: ed.credentialMessage !== ""
            width: parent.width
            text: ed.credentialMessage
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
                text: "Secrets and account numbers are stored only in GNOME Keyring. AI cannot place orders. Production trading requires settings opt-in and LIVE confirmation for every action."
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

    component CredentialField: Column {
        id: credential
        property string label: ""
        property bool configured: false
        signal requested(string value, var field)
        spacing: 5
        Row {
            width: parent.width
            LabelText { text: credential.label }
            Item { width: parent.width - parent.children[0].width - savedText.width; height: 1 }
            Text {
                id: savedText
                text: credential.configured ? "Saved" : ""
                color: "#30d158"
                font.family: "SF Pro Display"
                font.pixelSize: 9
                font.weight: Font.DemiBold
            }
        }
        Rectangle {
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
                placeholderText: credential.configured ? "Replace saved value" : "Enter securely"
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
                    text: "Save"
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
