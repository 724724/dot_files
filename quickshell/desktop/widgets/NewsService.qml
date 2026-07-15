pragma Singleton
import Quickshell
import QtQuick

Singleton {
    id: root

    readonly property string iconFont: "JetBrainsMono Nerd Font Propo"
    readonly property string defaultModel: "qwen2.5:3b"
    readonly property var sourceOptions: [
        { id: "chosun", label: "Chosun" },
        { id: "joongang", label: "JoongAng" },
        { id: "donga", label: "Donga" }
    ]
    readonly property var categoryOptions: [
        { id: "politics", label: "Politics" },
        { id: "economy", label: "Economics" },
        { id: "society", label: "Society" },
        { id: "culture", label: "Culture" },
        { id: "it", label: "Science" },
        { id: "world", label: "World" }
    ]
    readonly property var layoutOptions: [
        { id: 4, label: "X-Small" },
        { id: 1, label: "Small" },
        { id: 2, label: "Medium" },
        { id: 3, label: "Large" }
    ]
    readonly property var commonModels: ["qwen2.5:3b", "llama3.2:3b", "gemma3:4b", "exaone3.5:2.4b", "mistral:7b"]
    readonly property string _configDir: {
        let x = Quickshell.env("XDG_CONFIG_HOME")
        return (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config")
    }
    readonly property string newsScript: _configDir + "/quickshell/scripts/news-fetch.py"

    function defaultSources() {
        let a = []
        for (let i = 0; i < sourceOptions.length; i++) a.push(sourceOptions[i].id)
        return a
    }

    function defaultCategories() {
        let a = []
        for (let i = 0; i < categoryOptions.length; i++) a.push(categoryOptions[i].id)
        return a
    }

    function has(list, id) {
        if (!list) return false
        for (let i = 0; i < list.length; i++) if (list[i] === id) return true
        return false
    }

    function labelOf(options, id) {
        for (let i = 0; i < options.length; i++) if (options[i].id === id) return options[i].label
        return id
    }

    function categoryColor(id) {
        if (id === "politics") return "#ff453a"
        if (id === "economy") return "#30d158"
        if (id === "society") return "#0a84ff"
        if (id === "culture") return "#bf5af2"
        if (id === "it") return "#64d2ff"
        if (id === "world") return "#ff9f0a"
        return "#8e8e93"
    }

    function clock(ts) {
        if (!ts) return ""
        let d = new Date(ts * 1000)
        let h = d.getHours(), m = d.getMinutes()
        return (h < 10 ? "0" + h : h) + ":" + (m < 10 ? "0" + m : m)
    }
}
