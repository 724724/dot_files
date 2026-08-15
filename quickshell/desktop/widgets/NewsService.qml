pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string iconFont: "JetBrainsMono Nerd Font Propo"
    readonly property string defaultModel: "qwen2.5:3b"
    readonly property var sourceOptions: [{
        "id": "chosun",
        "label": "Chosun"
    }, {
        "id": "joongang",
        "label": "JoongAng"
    }, {
        "id": "donga",
        "label": "Donga"
    }]
    readonly property var categoryOptions: [{
        "id": "politics",
        "label": "Politics"
    }, {
        "id": "economy",
        "label": "Economics"
    }, {
        "id": "society",
        "label": "Society"
    }, {
        "id": "culture",
        "label": "Culture"
    }, {
        "id": "it",
        "label": "Science"
    }, {
        "id": "world",
        "label": "World"
    }]
    readonly property var layoutOptions: [{
        "id": 4,
        "label": "X-Small"
    }, {
        "id": 1,
        "label": "Small"
    }, {
        "id": 2,
        "label": "Medium"
    }, {
        "id": 3,
        "label": "Large"
    }]
    readonly property var commonModels: ["qwen2.5:3b", "llama3.2:3b", "gemma3:4b", "exaone3.5:2.4b", "mistral:7b"]
    readonly property string _configDir: {
        let x = Quickshell.env("XDG_CONFIG_HOME");
        return (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config");
    }
    readonly property string newsScript: _configDir + "/quickshell/scripts/news-fetch.py"
    readonly property int cacheTtlMs: 60 * 60 * 1000
    readonly property string sharedStateRoot: {
        const xdg = String(Quickshell.env("XDG_STATE_HOME") || "").trim();
        if (xdg !== "")
            return xdg + "/quickshell";
        const home = String(Quickshell.env("HOME") || "").trim();
        return home !== "" ? home + "/.local/state/quickshell" : "";
    }
    property var _feedCache: ({})

    function _normalizedIds(values) {
        let result = [];
        const input = Array.isArray(values) ? values : [];
        for (let i = 0; i < input.length; i++) {
            const value = String(input[i] || "").trim().toLowerCase();
            if (/^[a-z0-9_-]{1,32}$/.test(value) && result.indexOf(value) < 0)
                result.push(value);
        }
        result.sort();
        return result;
    }
    function cacheKey(sources, categories) {
        return root._normalizedIds(sources).join(",") + "|" + root._normalizedIds(categories).join(",");
    }
    function cachedFeed(sources, categories) {
        const entry = root._feedCache[root.cacheKey(sources, categories)];
        if (!entry || typeof entry !== "object" || !entry.payload || typeof entry.payload !== "object")
            return null;
        return entry;
    }
    function feedFresh(sources, categories) {
        const entry = root.cachedFeed(sources, categories);
        const savedAt = Number(entry && entry.savedAt);
        return Number.isFinite(savedAt) && savedAt > 0 && Date.now() - savedAt < root.cacheTtlMs;
    }
    function storeFeed(sources, categories, payload) {
        if (!payload || typeof payload !== "object" || !Array.isArray(payload.items))
            return;
        const key = root.cacheKey(sources, categories);
        if (key === "|")
            return;
        let next = Object.assign({}, root._feedCache);
        next[key] = {
            "savedAt": Date.now(),
            "payload": payload
        };
        const keys = Object.keys(next).sort((a, b) => Number(next[b].savedAt || 0) - Number(next[a].savedAt || 0));
        for (let i = 24; i < keys.length; i++)
            delete next[keys[i]];
        root._feedCache = next;
        feedCacheStore.setText(JSON.stringify({ "version": 1, "feeds": next }));
    }
    function _loadFeedCache() {
        try {
            const parsed = JSON.parse(feedCacheStore.text() || "{}");
            root._feedCache = parsed && parsed.feeds && typeof parsed.feeds === "object" ? parsed.feeds : ({});
        } catch (error) {
            root._feedCache = ({});
        }
    }

    function defaultSources() {
        let a = [];
        for (let i = 0; i < sourceOptions.length; i++) a.push(sourceOptions[i].id)
        return a;
    }

    function defaultCategories() {
        let a = [];
        for (let i = 0; i < categoryOptions.length; i++) a.push(categoryOptions[i].id)
        return a;
    }

    function has(list, id) {
        if (!list)
            return false;

        for (let i = 0; i < list.length; i++) if (list[i] === id) {
            return true;
        }
        return false;
    }

    function labelOf(options, id) {
        for (let i = 0; i < options.length; i++) if (options[i].id === id) {
            return options[i].label;
        }
        return id;
    }

    function categoryColor(id) {
        if (id === "politics")
            return "#ff453a";

        if (id === "economy")
            return "#30d158";

        if (id === "society")
            return "#0a84ff";

        if (id === "culture")
            return "#bf5af2";

        if (id === "it")
            return "#64d2ff";

        if (id === "world")
            return "#ff9f0a";

        return "#8e8e93";
    }

    function clock(ts) {
        if (!ts)
            return "";

        let d = new Date(ts * 1000);
        let h = d.getHours(), m = d.getMinutes();
        return (h < 10 ? "0" + h : h) + ":" + (m < 10 ? "0" + m : m);
    }

    Component.onCompleted: root._loadFeedCache()

    FileView {
        id: feedCacheStore

        blockLoading: true
        path: root.sharedStateRoot !== "" ? root.sharedStateRoot + "/news-widget-cache.json" : ""
        printErrors: false
        watchChanges: true

        onFileChanged: reload()
        onLoaded: root._loadFeedCache()
    }

}
