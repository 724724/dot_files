pragma Singleton
import Quickshell
import QtQuick

Singleton {
    signal credentialsChanged()
    signal riskPolicyChanged()
    signal automationPolicyChanged()
    property var modelCatalog: ({})

    readonly property var analysisProfileOptions: [
        { id: "quick", label: "Quick" },
        { id: "balanced", label: "Balanced" },
        { id: "deep", label: "Deep" }
    ]

    readonly property var dataModeOptions: [
        { id: "demo", label: "Demo" },
        { id: "kis", label: "KIS Live" }
    ]
    readonly property var kisEnvironmentOptions: [
        { id: "paper", label: "Paper" },
        { id: "prod", label: "Production" }
    ]
    readonly property var marketOptions: [
        { id: "KRX", label: "Korea" },
        { id: "NASDAQ", label: "NASDAQ" },
        { id: "NYSE", label: "NYSE" }
    ]
    readonly property var rangeOptions: [
        { id: "30M", label: "30m" },
        { id: "1D", label: "1D" },
        { id: "1W", label: "1W" },
        { id: "1M", label: "1M" },
        { id: "3M", label: "3M" }
    ]
    readonly property var providerOptions: [
        { id: "none", label: "Off" },
        { id: "openai", label: "OpenAI" },
        { id: "claude", label: "Claude" },
        { id: "both", label: "Both" }
    ]
    readonly property string _configDir: {
        let path = Quickshell.env("XDG_CONFIG_HOME")
        return path && path !== "" ? path : Quickshell.env("HOME") + "/.config"
    }
    readonly property string stockScript: _configDir + "/quickshell/scripts/stock-service.py"

    function marketLabel(id) {
        for (let i = 0; i < marketOptions.length; i++)
            if (marketOptions[i].id === id) return marketOptions[i].label
        return id
    }

    function providerLabel(id) {
        for (let i = 0; i < providerOptions.length; i++)
            if (providerOptions[i].id === id) return providerOptions[i].label
        return "Off"
    }

    function profileLabel(id) {
        for (let i = 0; i < analysisProfileOptions.length; i++)
            if (analysisProfileOptions[i].id === id) return analysisProfileOptions[i].label
        return "Balanced"
    }

    function profileModels(id) {
        let profile = modelCatalog.profiles ? modelCatalog.profiles[id] : null
        if (!profile) return "Sync models after saving an API key"
        let names = []
        if (profile.openai) names.push(profile.openai.displayName || profile.openai.id)
        if (profile.claude) names.push(profile.claude.displayName || profile.claude.id)
        return names.length > 0 ? names.join(" · ") : "No compatible models available"
    }

    function updateModelCatalog(value) {
        if (value && value.status === "ok") modelCatalog = value
    }

    function modelCatalogState() {
        if (!modelCatalog.providers) return "Not synced"
        let openai = modelCatalog.providers.openai
        let claude = modelCatalog.providers.claude
        if ((openai && openai.stale) || (claude && claude.stale)) return "Using cached catalog"
        if ((openai && openai.status === "ok") || (claude && claude.status === "ok")) return "Catalog synced"
        return "Sync unavailable"
    }

    function price(value, currency) {
        let v = Number(value) || 0
        if (currency === "KRW") return Math.round(v).toLocaleString(Qt.locale("ko_KR"), "f", 0)
        return v.toLocaleString(Qt.locale("en_US"), "f", 2)
    }

    function money(value, currency) {
        return currency === "KRW" ? "₩" + price(value, currency) : "$" + price(value, currency)
    }

    function signedMoney(value, currency) {
        let v = Number(value) || 0
        let amount = money(Math.abs(v), currency)
        return v > 0 ? "+" + amount : (v < 0 ? "-" + amount : amount)
    }

    function signed(value, digits) {
        let v = Number(value) || 0
        return (v > 0 ? "+" : "") + v.toFixed(digits === undefined ? 2 : digits)
    }
}
