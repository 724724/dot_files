pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Placed-widget board model + disk persistence.

// Each row: { wid, type, nx, ny, nw, nh, payload } where `payload` is a JSON
// string of type-specific state (note html/colour, reminders items, clock
// layout + faces, …). Role names avoid Item built-ins (x/y/width/height/data)
// so the delegate can use required properties. See [[quickshell-hyprland-quirks]].
Singleton {
    // tz filled in live via localOffset()

    id: root

    property var _boards: ({})
    property var _legacyWidgets: []
    property var _reminderLinks: []
    property bool _loaded: false
    property bool _lockLoaded: false
    property bool _reminderLinksLoaded: false
    property int _reminderRevision: 0
    property string activeBoardKey: ""
    // World-clock city presets (standard-time UTC offsets; DST not tracked).
    readonly property var cityPresets: [
        {
            "name": "Local",
            "tz": 0
        },
        {
            "name": "Honolulu",
            "tz": -10
        },
        {
            "name": "Los Angeles",
            "tz": -8
        },
        {
            "name": "Cupertino",
            "tz": -8
        },
        {
            "name": "Denver",
            "tz": -7
        },
        {
            "name": "Chicago",
            "tz": -6
        },
        {
            "name": "New York",
            "tz": -5
        },
        {
            "name": "São Paulo",
            "tz": -3
        },
        {
            "name": "London",
            "tz": 0
        },
        {
            "name": "Paris",
            "tz": 1
        },
        {
            "name": "Berlin",
            "tz": 1
        },
        {
            "name": "Cairo",
            "tz": 2
        },
        {
            "name": "Cape Town",
            "tz": 2
        },
        {
            "name": "Moscow",
            "tz": 3
        },
        {
            "name": "Dubai",
            "tz": 4
        },
        {
            "name": "Karachi",
            "tz": 5
        },
        {
            "name": "Mumbai",
            "tz": 5.5
        },
        {
            "name": "Dhaka",
            "tz": 6
        },
        {
            "name": "Bangkok",
            "tz": 7
        },
        {
            "name": "Beijing",
            "tz": 8
        },
        {
            "name": "Singapore",
            "tz": 8
        },
        {
            "name": "Hong Kong",
            "tz": 8
        },
        {
            "name": "Tokyo",
            "tz": 9
        },
        {
            "name": "Seoul",
            "tz": 9
        },
        {
            "name": "Sydney",
            "tz": 10
        },
        {
            "name": "Auckland",
            "tz": 12
        }
    ]

    // ── Board grid ───────────────────────────────────────────────────────
    // Every widget except sticky notes snaps to an n×m grid sized to the
    // monitor: cells of gridCell px separated by gridGap. Preset sizes below
    // are exact cell multiples (220 / 464 / 708 / 1440 = 1 / 2 / 3 / 6 cells). The board
    // (WidgetsWindow) auto-flows widgets into free slots; it re-runs when
    // relayoutNeeded fires.
    readonly property int gridCell: 220
    readonly property int gridGap: 24
    readonly property int gridUnit: gridCell + gridGap
    readonly property int lockGridColumns: 6
    readonly property int lockGridRows: 3
    // Lock-screen widgets use the same type/payload contract as the desktop
    // board, but keep a separate, bounded layout. The file lives outside a
    // shell-specific Quickshell stateDir so the independent `desktop` and
    // `lock` processes see exactly the same data.
    property alias lockWidgets: lockWidgetsModel
    property bool lockMediaEnabled: true
    readonly property int maxFont: 40
    readonly property int minFont: 9
    // Sticky-note palette (macOS Stickies-ish). First entry is the default.
    readonly property var palette: ["#FEF49C", "#FFC4D6", "#C7F0BD", "#BFE3F7", "#E5D4F7", "#FFD9A8"]
    readonly property string sharedStateRoot: {
        const xdg = String(Quickshell.env("XDG_STATE_HOME") || "").trim();
        if (xdg !== "")
            return xdg + "/quickshell";
        const home = String(Quickshell.env("HOME") || "").trim();
        return home !== "" ? home + "/.local/state/quickshell" : "";
    }
    property alias widgets: widgetsModel

    signal boardChanged(string key)
    signal lockPlacementRejected(string message)
    signal relayoutNeeded

    function _captureActiveBoard() {
        if (!root.activeBoardKey)
            return;

        let rows = [];
        for (let i = 0; i < widgetsModel.count; i++) {
            let w = widgetsModel.get(i);
            rows.push({
                "wid": w.wid,
                "type": w.type,
                "nx": w.nx,
                "ny": w.ny,
                "nw": w.nw,
                "nh": w.nh,
                "payload": w.payload
            });
        }
        let boards = Object.assign({}, root._boards);
        boards[root.activeBoardKey] = rows;
        root._boards = boards;
    }
    function _countOfType(type) {
        let n = 0;
        for (let i = 0; i < widgetsModel.count; i++)
            if (widgetsModel.get(i).type === type) {
                n++;
            }
        return n;
    }

    // Default size + initial data per widget type.
    function _defaults(type) {
        switch (type) {
        case "clock":
            return {
                "nw": 220,
                "nh": 220,
                "data": {
                    "layout": 4,
                    "faces": root.defaultClockFaces(4)
                }
            };
        case "weather":
            return {
                "nw": 464,
                "nh": 464,
                "data": {
                    "layout": 1
                }
            };
        case "reminders":
            return {
                "nw": 464,
                "nh": 220,
                "data": {
                    "layout": 2,
                    "title": "Reminders",
                    "accent": "blue",
                    "items": []
                }
            };
        case "news":
            return {
                "nw": 708,
                "nh": 464,
                "data": {
                    "layout": 2,
                    "sources": NewsService.defaultSources(),
                    "categories": NewsService.defaultCategories(),
                    "model": NewsService.defaultModel
                }
            };
        case "calendar":
            return {
                "nw": 464,
                "nh": 220,
                "data": {
                    "layout": 2
                }
            };
        case "stock":
            return {
                "nw": 708,
                "nh": 708,
                "data": {
                    "layout": 1,
                    "language": "ko",
                    "symbol": "005930",
                    "market": "KRX",
                    "range": "1D",
                    "aiProvider": "none",
                    "analysisProfile": "balanced",
                    "dataMode": "demo",
                    "kisEnvironment": "paper",
                    "tradingMode": "manual",
                    "productionTradingEnabled": false,
                    "watchlist": [
                        {
                            "symbol": "005930",
                            "market": "KRX"
                        },
                        {
                            "symbol": "000660",
                            "market": "KRX"
                        },
                        {
                            "symbol": "035420",
                            "market": "KRX"
                        }
                    ],
                    "priceAlerts": []
                }
            };
        case "youtube":
            return {
                "nw": 708,
                "nh": 464,
                "data": {
                    "layout": 3,
                    "url": "",
                    "mediaKind": "video",
                    "videoQuality": "best",
                    "audioFormat": "m4a",
                    "cookieBrowser": "auto"
                }
            };
        case "spotify":
            return {
                "nw": 708,
                "nh": 464,
                "data": {
                    "layout": 3,
                    "url": "",
                    "audioFormat": "opus",
                    "bitrate": "auto",
                    "cookieBrowser": "auto"
                }
            };
        case "note":
        default:
            return {
                "nw": 240,
                "nh": 240,
                "data": {
                    "content": "",
                    "swatch": root.palette[root._countOfType("note") % root.palette.length],
                    "fontSize": 15,
                    "fontFamily": "Apple SD Gothic Neo",
                    "collapsed": false
                }
            };
        }
    }
    function _firstLockSlot(columns, rows) {
        if (columns > root.lockGridColumns || rows > root.lockGridRows)
            return null;
        for (let row = 0; row <= root.lockGridRows - rows; row++)
            for (let column = 0; column <= root.lockGridColumns - columns; column++)
                if (root.lockRegionFree(-1, column, row, columns, rows))
                    return {
                        "column": column,
                        "row": row
                    };
        return null;
    }
    function _nearestLockSlot(skipIndex, columns, rows, preferredColumn, preferredRow) {
        let best = null;
        let bestDistance = Number.POSITIVE_INFINITY;
        for (let row = 0; row <= root.lockGridRows - rows; row++) {
            for (let column = 0; column <= root.lockGridColumns - columns; column++) {
                if (!root.lockRegionFree(skipIndex, column, row, columns, rows))
                    continue;
                const distance = Math.abs(column - preferredColumn) + Math.abs(row - preferredRow);
                if (distance < bestDistance) {
                    bestDistance = distance;
                    best = {
                        "column": column,
                        "row": row
                    };
                }
            }
        }
        return best;
    }
    function _load() {
        if (root._loaded)
            return;

        let raw = store.text();
        if (raw) {
            try {
                let value = JSON.parse(raw);
                if (Array.isArray(value))
                    root._legacyWidgets = value;
                else if (value && value.boards && typeof value.boards === "object")
                    root._boards = value.boards;
            } catch (e) {}
        } else {
            let old = legacy.text();
            if (old)
                root._legacyWidgets = root._migrate(old);
        }
        root._loaded = true;
    }
    function _loadLockWidgets() {
        if (root._lockLoaded)
            return;
        root._lockLoaded = true;
        const raw = lockStore.text();
        if (!raw)
            return;
        let entries = [];
        try {
            const parsed = JSON.parse(raw);
            if (parsed && !Array.isArray(parsed))
                root.lockMediaEnabled = parsed.mediaEnabled !== false;
            entries = Array.isArray(parsed) ? parsed : (parsed && Array.isArray(parsed.widgets) ? parsed.widgets : []);
        } catch (e) {
            return;
        }

        // Treat persisted geometry as untrusted. Invalid, overlapping, or
        // unknown-source entries are ignored instead of ever being clipped
        // over the clock/media reservations.
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i] || ({});
            const type = String(entry.type || "");
            if (root.componentFile(type) === "")
                continue;
            const payload = root._linkedLockReminderPayload(type, entry.payload);
            const span = root._lockSpan(type, payload);
            let column = Math.round(Number(entry.column));
            let row = Math.round(Number(entry.row));
            if (!root.lockRegionFree(-1, column, row, span.columns, span.rows)) {
                // Preset changes (for example Reminders Large moving from a
                // legacy 1×2 footprint to 2×2) must not silently discard a
                // saved widget. Reflow it to the first valid bounded slot.
                const replacement = root._firstLockSlot(span.columns, span.rows);
                if (!replacement)
                    continue;
                column = replacement.column;
                row = replacement.row;
            }
            lockWidgetsModel.append({
                "wid": Number(entry.wid) || (Date.now() + i),
                "type": type,
                "column": column,
                "row": row,
                "columns": span.columns,
                "rows": span.rows,
                "payload": payload
            });
        }
    }

    // ── Shared Reminder sources ──────────────────────────────────────────
    // Lock input is data-only. It can update a bounded Reminder record, but
    // no user string is ever interpolated into a command, URL, QML source, or
    // executable path. Desktop and lock processes exchange only this JSON.
    function _objectFromJson(value) {
        if (value && typeof value === "object")
            return value;
        try {
            const parsed = JSON.parse(String(value || "{}"));
            return parsed && typeof parsed === "object" ? parsed : ({});
        } catch (e) {
            return ({});
        }
    }
    function _safeReminderText(value, maximum) {
        // Remove control/bidi formatting characters that can spoof the editor
        // while preserving ordinary Unicode. Shell metacharacters remain plain
        // text because this data has no process-execution sink.
        return String(value === undefined || value === null ? "" : value).replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g, " ").replace(/\s+/g, " ").trim().slice(0, maximum);
    }
    function _newReminderListId() {
        return "rem-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 0x100000000).toString(36);
    }
    function _newReminderItemId() {
        return "item-" + Date.now().toString(36) + "-" + Math.floor(Math.random() * 0x100000000).toString(36);
    }
    function _safeReminderListId(value) {
        const id = String(value || "");
        return /^[A-Za-z0-9._-]{1,128}$/.test(id) ? id : "";
    }
    function _safeReminderItemId(value) {
        const id = String(value || "");
        return /^[A-Za-z0-9._-]{1,128}$/.test(id) ? id : "";
    }
    function _normalizedReminderData(value) {
        const data = root._objectFromJson(value);
        const layoutNumber = Math.round(Number(data.layout || 2));
        const layout = layoutNumber >= 1 && layoutNumber <= 3 ? layoutNumber : 2;
        const accents = ["red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink", "brown"];
        const icons = ["list", "check", "star", "flag", "heart", "bell", "bookmark", "cart", "gift", "leaf", "home", "briefcase", "calendar", "bolt"];
        const accent = accents.includes(String(data.accent || "")) ? String(data.accent) : "blue";
        const icon = icons.includes(String(data.icon || "")) ? String(data.icon) : "list";
        const sourceItems = Array.isArray(data.items) ? data.items.slice(0, 128) : [];
        const items = [];
        const seenItemIds = ({});
        for (let i = 0; i < sourceItems.length; i++) {
            const item = sourceItems[i] || ({});
            const text = root._safeReminderText(item.text, 512);
            if (text !== "") {
                let itemId = root._safeReminderItemId(item.itemId);
                if (itemId === "" || seenItemIds[itemId]) {
                    do {
                        itemId = root._newReminderItemId();
                    } while (seenItemIds[itemId])
                }
                seenItemIds[itemId] = true;
                items.push({
                    "itemId": itemId,
                    "text": text,
                    "done": item.done === true
                });
            }
        }
        const result = {
            "layout": layout,
            "title": root._safeReminderText(data.title || "Reminders", 96) || "Reminders",
            "accent": accent,
            "icon": icon,
            "items": items
        };
        const listId = root._safeReminderListId(data.listId);
        if (listId !== "")
            result.listId = listId;
        return result;
    }
    function _safeSourceBoard(value) {
        return root._safeReminderText(value, 128);
    }
    function _ensureReminderListIds() {
        const boards = Object.assign({}, root._boards);
        const names = Object.keys(boards);
        const seen = ({});
        let changed = false;
        for (let b = 0; b < names.length; b++) {
            const rows = Array.isArray(boards[names[b]]) ? boards[names[b]].slice() : [];
            for (let i = 0; i < rows.length; i++) {
                const row = rows[i];
                if (!row || row.type !== "reminders")
                    continue;
                const data = root._normalizedReminderData(row.payload);
                let listId = root._safeReminderListId(data.listId);
                if (listId === "" || seen[listId]) {
                    do {
                        listId = root._newReminderListId();
                    } while (seen[listId])
                    data.listId = listId;
                }
                seen[listId] = true;
                const normalizedPayload = JSON.stringify(data);
                if (row.payload !== normalizedPayload) {
                    rows[i] = Object.assign({}, row, {
                        "payload": normalizedPayload
                    });
                    changed = true;
                }
            }
            boards[names[b]] = rows;
        }
        if (changed) {
            root._boards = boards;
            if (names.length > 0)
                store.setText(JSON.stringify({
                    "version": 2,
                    "boards": root._boards
                }));
        }
    }
    function _findReminderLinkIndex(listId) {
        const safeListId = root._safeReminderListId(listId);
        if (safeListId === "")
            return -1;
        for (let i = 0; i < root._reminderLinks.length; i++) {
            const link = root._reminderLinks[i] || ({});
            if (link.listId === safeListId)
                return i;
        }
        return -1;
    }
    function _reminderLink(listId) {
        const index = root._findReminderLinkIndex(listId);
        return index >= 0 ? root._reminderLinks[index] : null;
    }
    function _upsertReminderLink(listId, board, wid, data) {
        const safeListId = root._safeReminderListId(listId);
        const safeBoard = root._safeSourceBoard(board);
        const safeWid = Math.round(Number(wid));
        if (safeListId === "" || safeBoard === "" || !isFinite(safeWid) || safeWid < 0)
            return false;
        const links = root._reminderLinks.slice();
        const normalized = root._normalizedReminderData(data);
        normalized.listId = safeListId;
        const next = {
            "listId": safeListId,
            "board": safeBoard,
            "wid": safeWid,
            "available": true,
            "data": normalized
        };
        const index = root._findReminderLinkIndex(safeListId);
        if (index >= 0)
            links[index] = next;
        else
            links.push(next);
        root._reminderLinks = links;
        return true;
    }
    function _loadReminderLinks(force) {
        if (root._reminderLinksLoaded && !force)
            return;
        root._reminderLinksLoaded = true;
        const raw = reminderLinkStore.text();
        const links = [];
        root._reminderRevision = 0;
        if (raw) {
            try {
                const parsed = JSON.parse(raw);
                const revision = Math.round(Number(parsed && parsed.revision));
                root._reminderRevision = isFinite(revision) && revision >= 0 ? revision : 0;
                const source = parsed && Array.isArray(parsed.links) ? parsed.links : [];
                for (let i = 0; i < source.length; i++) {
                    const item = source[i] || ({});
                    const listId = root._safeReminderListId(item.listId);
                    const board = root._safeSourceBoard(item.board);
                    const wid = Math.round(Number(item.wid));
                    if (listId === "" || board === "" || !isFinite(wid) || wid < 0)
                        continue;
                    let duplicate = false;
                    for (let j = 0; j < links.length; j++)
                        if (links[j].listId === listId) {
                            duplicate = true;
                            break;
                        }
                    if (!duplicate) {
                        const data = root._normalizedReminderData(item.data);
                        data.listId = listId;
                        links.push({
                            "listId": listId,
                            "board": board,
                            "wid": wid,
                            "available": item.available !== false,
                            "data": data
                        });
                    }
                }
            } catch (e) {}
        }
        root._reminderLinks = links;
        root._refreshLinkedReminders(force);
    }
    function _persistReminderLinks() {
        if (root.sharedStateRoot === "")
            return;
        root._reminderRevision = Math.max(0, root._reminderRevision) + 1;
        reminderLinkStore.setText(JSON.stringify({
            "version": 2,
            "revision": root._reminderRevision,
            "links": root._reminderLinks
        }));
    }
    function _reloadReminderLinksForMutation() {
        // A lock-screen operation always reloads immediately before its
        // read/modify/write. The revision is persisted for diagnostics and
        // future compare-and-swap migration; normal session-lock usage has a
        // single interactive writer because the desktop is inaccessible.
        reminderLinkStore.reload();
        reminderLinkStore.waitForJob();
        root._loadReminderLinks(true);
    }
    function _linkedLockReminderPayload(type, payload) {
        const own = root._objectFromJson(payload);
        if (type !== "reminders")
            return typeof payload === "string" ? payload : JSON.stringify(own);
        const normalized = root._normalizedReminderData(own);
        const listId = root._safeReminderListId(own.sourceListId);
        const board = root._safeSourceBoard(own.sourceBoard);
        const wid = Math.round(Number(own.sourceWid));
        const link = root._reminderLink(listId);
        const result = link ? root._normalizedReminderData(link.data) : normalized;
        // Layout belongs to the bounded lock placement; the selected source
        // supplies only list identity/style/items and cannot resize into peers.
        result.layout = normalized.layout;
        if (link) {
            result.sourceListId = link.listId;
            result.sourceBoard = link.board;
            result.sourceWid = link.wid;
        } else if (listId !== "") {
            // Keep the stable identity and last known snapshot if the desktop
            // list was deleted or the shared store is temporarily unavailable.
            // Never reconnect by a reused positional widget id.
            result.sourceListId = listId;
            if (board !== "")
                result.sourceBoard = board;
            if (isFinite(wid) && wid >= 0)
                result.sourceWid = wid;
        }
        return JSON.stringify(result);
    }
    function _findBoardReminder(board, wid) {
        const rows = root._boards[board];
        if (!Array.isArray(rows))
            return null;
        for (let i = 0; i < rows.length; i++)
            if (rows[i] && rows[i].type === "reminders" && Number(rows[i].wid) === Number(wid))
                return rows[i];
        return null;
    }
    function _findBoardReminderByListId(listId) {
        const safeListId = root._safeReminderListId(listId);
        if (safeListId === "")
            return null;
        const boardNames = Object.keys(root._boards);
        for (let b = 0; b < boardNames.length; b++) {
            const board = boardNames[b];
            const rows = root._boards[board];
            if (!Array.isArray(rows))
                continue;
            for (let i = 0; i < rows.length; i++) {
                const row = rows[i];
                if (!row || row.type !== "reminders")
                    continue;
                const data = root._normalizedReminderData(row.payload);
                if (root._safeReminderListId(data.listId) === safeListId)
                    return {
                        "board": board,
                        "wid": Math.round(Number(row.wid)),
                        "data": data
                    };
            }
        }
        return null;
    }
    function _refreshLinkedReminders(persistDesktop) {
        let boardsChanged = false;
        const boards = Object.assign({}, root._boards);
        const boardNames = Object.keys(boards);
        for (let b = 0; b < boardNames.length; b++) {
            const boardName = boardNames[b];
            const oldRows = Array.isArray(boards[boardName]) ? boards[boardName] : [];
            const rows = oldRows.slice();
            for (let i = 0; i < rows.length; i++) {
                const row = rows[i];
                if (!row || row.type !== "reminders")
                    continue;
                const rowData = root._normalizedReminderData(row.payload);
                const link = root._reminderLink(rowData.listId);
                if (!link || link.available === false)
                    continue;
                const nextPayload = JSON.stringify(root._normalizedReminderData(link.data));
                if (row.payload !== nextPayload) {
                    rows[i] = Object.assign({}, row, {
                        "payload": nextPayload
                    });
                    boardsChanged = true;
                }
            }
            boards[boardName] = rows;
        }
        if (boardsChanged)
            root._boards = boards;

        if (root.activeBoardKey !== "") {
            const activeRows = root._boards[root.activeBoardKey] || [];
            for (let i = 0; i < widgetsModel.count; i++) {
                const modelItem = widgetsModel.get(i);
                if (modelItem.type !== "reminders")
                    continue;
                for (let j = 0; j < activeRows.length; j++)
                    if (Number(activeRows[j].wid) === Number(modelItem.wid)) {
                        if (modelItem.payload !== activeRows[j].payload)
                            widgetsModel.setProperty(i, "payload", activeRows[j].payload);
                        break;
                    }
            }
        }

        for (let i = 0; i < lockWidgetsModel.count; i++) {
            const item = lockWidgetsModel.get(i);
            if (item.type !== "reminders")
                continue;
            const nextPayload = root._linkedLockReminderPayload(item.type, item.payload);
            if (nextPayload !== item.payload)
                lockWidgetsModel.setProperty(i, "payload", nextPayload);
        }

        if (persistDesktop && boardNames.length > 0)
            store.setText(JSON.stringify({
                "version": 2,
                "boards": root._boards
            }));
    }
    function reminderSources() {
        if (root.activeBoardKey !== "")
            root._captureActiveBoard();
        const result = [];
        const boardNames = Object.keys(root._boards).sort();
        for (let b = 0; b < boardNames.length; b++) {
            const board = boardNames[b];
            const rows = root._boards[board] || [];
            for (let i = 0; i < rows.length; i++) {
                const row = rows[i];
                if (!row || row.type !== "reminders")
                    continue;
                const rowData = root._normalizedReminderData(row.payload);
                const link = root._reminderLink(rowData.listId);
                const data = link && link.available !== false ? root._normalizedReminderData(link.data) : root._normalizedReminderData(row.payload);
                let incomplete = 0;
                for (let j = 0; j < data.items.length; j++)
                    if (!data.items[j].done)
                        incomplete++;
                result.push({
                    "board": board,
                    "wid": Number(row.wid),
                    "listId": data.listId,
                    "title": data.title,
                    "accent": data.accent,
                    "icon": data.icon,
                    "incomplete": incomplete,
                    "total": data.items.length
                });
            }
        }
        return result;
    }
    function linkLockReminder(index, listId) {
        if (index < 0 || index >= lockWidgetsModel.count)
            return false;
        const item = lockWidgetsModel.get(index);
        if (item.type !== "reminders")
            return false;
        if (root.activeBoardKey !== "")
            root._captureActiveBoard();
        const source = root._findBoardReminderByListId(listId);
        if (!source)
            return false;
        const sourceData = root._normalizedReminderData(source.data);
        const safeListId = root._safeReminderListId(sourceData.listId);
        if (safeListId === "" || !root._upsertReminderLink(safeListId, source.board, source.wid, sourceData))
            return false;
        const own = root._normalizedReminderData(item.payload);
        sourceData.layout = own.layout;
        sourceData.sourceListId = safeListId;
        sourceData.sourceBoard = source.board;
        sourceData.sourceWid = source.wid;
        lockWidgetsModel.setProperty(index, "payload", JSON.stringify(sourceData));
        root._persistReminderLinks();
        root.persistLockWidgets();
        root._refreshLinkedReminders(true);
        return true;
    }
    function lockReminderLinked(index) {
        if (index < 0 || index >= lockWidgetsModel.count)
            return false;
        const item = lockWidgetsModel.get(index);
        if (item.type !== "reminders")
            return false;
        const data = root._objectFromJson(item.payload);
        const link = root._reminderLink(data.sourceListId);
        return link !== null && link.available !== false;
    }
    function lockReminderSourceListId(index) {
        if (index < 0 || index >= lockWidgetsModel.count)
            return "";
        const item = lockWidgetsModel.get(index);
        if (item.type !== "reminders")
            return "";
        return root._safeReminderListId(root._objectFromJson(item.payload).sourceListId);
    }
    function lockReminderFollows(index, listId) {
        return root.lockReminderSourceListId(index) !== "" && root.lockReminderSourceListId(index) === root._safeReminderListId(listId);
    }
    function _mutateLockReminder(index, operation, itemId, text) {
        if (index < 0 || index >= lockWidgetsModel.count)
            return false;
        const item = lockWidgetsModel.get(index);
        if (item.type !== "reminders")
            return false;
        const sourceListId = root._safeReminderListId(root._objectFromJson(item.payload).sourceListId);
        if (sourceListId === "")
            return false;

        root._reloadReminderLinksForMutation();
        const link = root._reminderLink(sourceListId);
        if (!link || link.available === false)
            return false;
        const nextData = root._normalizedReminderData(link.data);
        const items = nextData.items.slice();
        const safeItemId = root._safeReminderItemId(itemId);
        const safeText = root._safeReminderText(text, 512);

        if (operation === "add") {
            if (safeText === "" || items.length >= 128)
                return false;
            items.push({
                "itemId": root._newReminderItemId(),
                "text": safeText,
                "done": false
            });
        } else {
            if (safeItemId === "")
                return false;
            let itemIndex = -1;
            for (let i = 0; i < items.length; i++)
                if (items[i].itemId === safeItemId) {
                    itemIndex = i;
                    break;
                }
            if (itemIndex < 0)
                return false;
            if (operation === "rename") {
                if (safeText === "")
                    return false;
                items[itemIndex] = Object.assign({}, items[itemIndex], {
                    "text": safeText
                });
            } else if (operation === "toggle") {
                items[itemIndex] = Object.assign({}, items[itemIndex], {
                    "done": items[itemIndex].done !== true
                });
            } else {
                return false;
            }
        }

        nextData.items = items;
        if (!root._upsertReminderLink(link.listId, link.board, link.wid, nextData))
            return false;
        root._persistReminderLinks();
        root._refreshLinkedReminders(true);
        root.persistLockWidgets();
        return true;
    }
    function addLockReminder(index, text) {
        return root._mutateLockReminder(index, "add", "", text);
    }
    function renameLockReminder(index, itemId, text) {
        return root._mutateLockReminder(index, "rename", itemId, text);
    }
    function toggleLockReminder(index, itemId) {
        return root._mutateLockReminder(index, "toggle", itemId, "");
    }
    function _syncLinkedReminderSource(board, wid, data) {
        const normalized = root._normalizedReminderData(data);
        const listId = root._safeReminderListId(normalized.listId);
        if (listId === "")
            return;
        // Desktop edits are normally impossible while the lock is receiving
        // input, but reload here as well so an external state writer cannot be
        // silently overwritten by an old in-memory snapshot.
        root._reloadReminderLinksForMutation();
        if (root._findReminderLinkIndex(listId) < 0)
            return;
        if (!root._upsertReminderLink(listId, board, wid, normalized))
            return;
        root._persistReminderLinks();
        root._refreshLinkedReminders(true);
        root.persistLockWidgets();
    }
    function _markReminderUnavailable(listId) {
        const index = root._findReminderLinkIndex(listId);
        if (index < 0)
            return;
        const links = root._reminderLinks.slice();
        links[index] = Object.assign({}, links[index], {
            "available": false
        });
        root._reminderLinks = links;
        root._persistReminderLinks();
        root._refreshLinkedReminders(false);
        root.persistLockWidgets();
    }

    // ── Lock-screen board ────────────────────────────────────────────────
    // Positions are stored as grid coordinates, never pixels. The renderer
    // can therefore scale the same 6×3 layout to any monitor without changing
    // its ordering, overflowing, or introducing a scroll view.
    function _lockSpan(type, payload) {
        let data = payload;
        if (typeof data === "string") {
            try {
                data = JSON.parse(data || "{}");
            } catch (e) {
                data = ({});
            }
        }
        data = data || ({});
        const preset = root.presetSize(type, Number(data.layout || 0));
        const width = preset ? preset.nw : root.gridCell;
        const height = preset ? preset.nh : root.gridCell;
        return {
            "columns": Math.max(1, Math.round((width + root.gridGap) / root.gridUnit)),
            "rows": Math.max(1, Math.round((height + root.gridGap) / root.gridUnit))
        };
    }

    // Convert the old notes.json (array of sticky notes) into note widgets.
    function _migrate(old) {
        let result = [];
        try {
            let arr = JSON.parse(old);
            if (!Array.isArray(arr))
                return result;

            for (let i = 0; i < arr.length; i++) {
                let n = arr[i] || {};
                result.push({
                    "wid": (n.noteId !== undefined) ? n.noteId : (Date.now() + i),
                    "type": "note",
                    "nx": (n.nx !== undefined) ? n.nx : 80,
                    "ny": (n.ny !== undefined) ? n.ny : 80,
                    "nw": (n.nw !== undefined) ? n.nw : 240,
                    "nh": (n.nh !== undefined) ? n.nh : 240,
                    "payload": JSON.stringify({
                        "content": n.content || "",
                        "swatch": n.swatch || root.palette[0],
                        "fontSize": (n.fontSize !== undefined) ? n.fontSize : 15,
                        "collapsed": (n.collapsed !== undefined) ? n.collapsed : false
                    })
                });
            }
        } catch (e) {} // ignore
        return result;
    }
    function _newId() {
        let max = 0;
        for (let i = 0; i < widgetsModel.count; i++)
            max = Math.max(max, widgetsModel.get(i).wid);
        return max + 1;
    }
    function _nextLockId() {
        let maximum = 0;
        for (let i = 0; i < lockWidgetsModel.count; i++)
            maximum = Math.max(maximum, Number(lockWidgetsModel.get(i).wid) || 0);
        return maximum + 1;
    }
    function _normalizedWidget(w, fallbackId) {
        w = w || {};
        return {
            "wid": (w.wid !== undefined) ? w.wid : fallbackId,
            "type": w.type || "note",
            "nx": (w.nx !== undefined) ? w.nx : 80,
            "ny": (w.ny !== undefined) ? w.ny : 80,
            "nw": (w.nw !== undefined) ? w.nw : 240,
            "nh": (w.nh !== undefined) ? w.nh : 240,
            "payload": (typeof w.payload === "string") ? w.payload : JSON.stringify(w.payload || {})
        };
    }
    function activateBoard(key) {
        if (!root._loaded)
            root._load();

        let nextKey = (key || "unknown-monitor").toString().trim() || "unknown-monitor";
        if (root.activeBoardKey === nextKey)
            return;

        root._captureActiveBoard();
        let boards = Object.assign({}, root._boards);
        if (!Array.isArray(boards[nextKey])) {
            boards[nextKey] = root._legacyWidgets.length > 0 ? root._legacyWidgets.slice() : [];
            root._legacyWidgets = [];
        }
        root._boards = boards;
        root.activeBoardKey = nextKey;
        widgetsModel.clear();
        root._refreshLinkedReminders(false);
        let rows = root._boards[nextKey];
        for (let i = 0; i < rows.length; i++)
            widgetsModel.append(root._normalizedWidget(rows[i], Date.now() + i));
        root.persist();
        root.boardChanged(nextKey);
        root.relayoutNeeded();
    }
    function addLockWidget(type, extra) {
        const defaults = root._defaults(type);
        const data = defaults.data;
        if (extra)
            for (let key in extra)
                data[key] = extra[key];

        const span = root._lockSpan(type, data);
        const slot = root._firstLockSlot(span.columns, span.rows);
        if (!slot)
            return -1;

        lockWidgetsModel.append({
            "wid": root._nextLockId(),
            "type": String(type || "note"),
            "column": slot.column,
            "row": slot.row,
            "columns": span.columns,
            "rows": span.rows,
            "payload": JSON.stringify(data)
        });
        root.persistLockWidgets();
        return lockWidgetsModel.count - 1;
    }

    // `extra` (optional) is merged into the default data (e.g. clock layout/faces).
    function addWidget(type, x, y, extra) {
        let d = _defaults(type);
        let data = d.data;
        if (extra)
            for (let k in extra)
                data[k] = extra[k];
        if (type === "reminders" && root._safeReminderListId(data.listId) === "")
            data.listId = root._newReminderListId();

        let nw = d.nw, nh = d.nh;
        if (type === "clock") {
            let sz = root.clockSize(data.layout || 4);
            nw = sz.nw;
            nh = sz.nh;
        } else if (type === "weather") {
            let sz = root.weatherSize(data.layout || 1);
            nw = sz.nw;
            nh = sz.nh;
        } else if (type === "reminders") {
            let sz = root.remindersSize(data.layout || 2);
            nw = sz.nw;
            nh = sz.nh;
        } else if (type === "news") {
            let sz = root.newsSize(data.layout || 2);
            nw = sz.nw;
            nh = sz.nh;
        } else if (type === "calendar") {
            let sz = root.calendarSize(data.layout || 2);
            nw = sz.nw;
            nh = sz.nh;
        } else if (type === "stock") {
            let sz = root.stockSize(data.layout || 1);
            nw = sz.nw;
            nh = sz.nh;
        } else if (type === "youtube") {
            let sz = root.youtubeSize(data.layout || 3);
            nw = sz.nw;
            nh = sz.nh;
        } else if (type === "spotify") {
            let sz = root.spotifySize(data.layout || 3);
            nw = sz.nw;
            nh = sz.nh;
        }
        widgetsModel.append({
            "wid": root._newId(),
            "type": type,
            "nx": (x !== undefined) ? x : 120,
            "ny": (y !== undefined) ? y : 120,
            "nw": nw,
            "nh": nh,
            "payload": JSON.stringify(data)
        });
        root.persist();
        if (type !== "note")
            root.relayoutNeeded();

        return widgetsModel.count - 1;
    }
    function calendarSize(layout) {
        switch (layout) {
        case 1:
            return {
                "nw": 220,
                "nh": 220
            }; // small
        case 3:
            return {
                "nw": 464,
                "nh": 464
            }; // large
        case 2:
        default:
            return {
                "nw": 464,
                "nh": 220
            }; // medium
        }
    }

    // All preset sizes are exact grid spans (220=1, 464=2, 708=3, 1440=6 cells).
    function clockSize(layout) {
        switch (layout) {
        case 2:
            return {
                "nw": 464,
                "nh": 220
            }; // world row
        case 1:
        case 3:
        case 4:
        case 5:
        default:
            return {
                "nw": 220,
                "nh": 220
            };
        }
    }

    // Widget QML follows one convention (`weather` -> WeatherWidget.qml).
    // Both desktop and lock render through this function, so adding a normal
    // widget never requires a second lock-specific type switch.
    function componentFile(type) {
        const value = String(type || "").trim().toLowerCase();
        if (!/^[a-z][a-z0-9-]*$/.test(value))
            return "";
        const words = value.split("-");
        let stem = "";
        for (let i = 0; i < words.length; i++)
            stem += words[i].charAt(0).toUpperCase() + words[i].slice(1);
        return stem + "Widget.qml";
    }
    function componentSource(type) {
        const file = root.componentFile(type);
        return file !== "" ? Qt.resolvedUrl(file) : "";
    }
    function defaultClockFaces(layout) {
        if (layout === 2 || layout === 3)
            return [faceFromName("Local"), faceFromName("New York"), faceFromName("London"), faceFromName("Tokyo")];

        return [faceFromName("Local")];
    }
    function faceFromName(name) {
        if (name === "Local")
            return {
                "city": "Local",
                "tz": root.localOffset()
            };

        for (let i = 0; i < cityPresets.length; i++)
            if (cityPresets[i].name === name) {
                return {
                    "city": name,
                    "tz": cityPresets[i].tz
                };
            }
        return {
            "city": "Local",
            "tz": root.localOffset()
        };
    }
    // Editors use -2, -3, ... as an internal, non-persisted address for lock
    // widgets. -1 remains the universal "no editor" sentinel.
    function lockEditorIndex(index) {
        return index >= 0 && index < lockWidgetsModel.count ? -index - 2 : -1;
    }
    function _isLockEditorIndex(index) {
        return Number.isInteger(index) && index <= -2;
    }
    function _lockIndexFromEditor(index) {
        return root._isLockEditorIndex(index) ? -index - 2 : -1;
    }
    function lockTypeAt(index) {
        if (index < 0 || index >= lockWidgetsModel.count)
            return "";
        return lockWidgetsModel.get(index).type;
    }
    function getData(index) {
        if (root._isLockEditorIndex(index)) {
            const lockIndex = root._lockIndexFromEditor(index);
            if (lockIndex < 0 || lockIndex >= lockWidgetsModel.count)
                return ({});
            return root._objectFromJson(lockWidgetsModel.get(lockIndex).payload);
        }
        if (index < 0 || index >= widgetsModel.count)
            return ({});

        try {
            return JSON.parse(widgetsModel.get(index).payload || "{}");
        } catch (e) {
            return ({});
        }
    }
    function _setLockWidgetData(index, patch) {
        if (index < 0 || index >= lockWidgetsModel.count || !patch || typeof patch !== "object")
            return false;

        const item = lockWidgetsModel.get(index);
        let current = root._objectFromJson(item.payload);
        for (let key in patch)
            current[key] = patch[key];

        const span = root._lockSpan(item.type, current);
        let column = item.column;
        let row = item.row;
        if (!root.lockRegionFree(index, column, row, span.columns, span.rows)) {
            const replacement = root._nearestLockSlot(index, span.columns, span.rows, column, row);
            if (!replacement) {
                root.lockPlacementRejected(span.columns > root.lockGridColumns || span.rows > root.lockGridRows
                    ? "This layout is larger than the Lock Screen grid. Choose a smaller size."
                    : "There isn’t enough room for this size on the Lock Screen.");
                return false;
            }
            column = replacement.column;
            row = replacement.row;
        }

        const payload = JSON.stringify(current);
        lockWidgetsModel.setProperty(index, "column", column);
        lockWidgetsModel.setProperty(index, "row", row);
        lockWidgetsModel.setProperty(index, "columns", span.columns);
        lockWidgetsModel.setProperty(index, "rows", span.rows);
        lockWidgetsModel.setProperty(index, "payload", payload);
        root.persistLockWidgets();
        return true;
    }
    function localOffset() {
        return -(new Date().getTimezoneOffset()) / 60;
    }
    function lockRegionFree(skipIndex, column, row, columns, rows) {
        column = Math.round(Number(column));
        row = Math.round(Number(row));
        columns = Math.max(1, Math.round(Number(columns)));
        rows = Math.max(1, Math.round(Number(rows)));
        if (column < 0 || row < 0 || column + columns > root.lockGridColumns || row + rows > root.lockGridRows)
            return false;

        for (let i = 0; i < lockWidgetsModel.count; i++) {
            if (i === skipIndex)
                continue;
            const item = lockWidgetsModel.get(i);
            if (column < item.column + item.columns && item.column < column + columns && row < item.row + item.rows && item.row < row + rows)
                return false;
        }
        return true;
    }
    function moveLockWidget(index, column, row, save) {
        if (index < 0 || index >= lockWidgetsModel.count)
            return false;
        const item = lockWidgetsModel.get(index);
        column = Math.round(Number(column));
        row = Math.round(Number(row));
        if (!root.lockRegionFree(index, column, row, item.columns, item.rows))
            return false;
        lockWidgetsModel.setProperty(index, "column", column);
        lockWidgetsModel.setProperty(index, "row", row);
        if (save)
            root.persistLockWidgets();
        return true;
    }
    function newsSize(layout) {
        switch (layout) {
        case 4:
            return {
                "nw": 220,
                "nh": 220
            }; // x-small
        case 1:
            return {
                "nw": 464,
                "nh": 464
            }; // small
        case 3:
            return {
                "nw": 708,
                "nh": 708
            }; // large
        case 2:
        default:
            return {
                "nw": 708,
                "nh": 464
            }; // medium
        }
    }

    // 1-based position of a note among all notes, in board (open) order. Used
    // for the user-facing export filename (notes-1, notes-2, …) instead of the
    // internal `wid`, which is a stable key that can be large/stale after
    // creating + deleting notes.
    function noteOrdinal(index) {
        let n = 0;
        for (let i = 0; i <= index && i < widgetsModel.count; i++)
            if (widgetsModel.get(i).type === "note") {
                n++;
            }
        return n;
    }
    function persist() {
        if (!root.activeBoardKey)
            return;

        root._captureActiveBoard();
        store.setText(JSON.stringify({
            "version": 2,
            "boards": root._boards
        }));
    }
    function persistLockWidgets() {
        if (root.sharedStateRoot === "")
            return;
        const rows = [];
        for (let i = 0; i < lockWidgetsModel.count; i++) {
            const item = lockWidgetsModel.get(i);
            rows.push({
                "wid": item.wid,
                "type": item.type,
                "column": item.column,
                "row": item.row,
                "columns": item.columns,
                "rows": item.rows,
                "payload": item.payload
            });
        }
        lockStore.setText(JSON.stringify({
            "version": 2,
            "columns": root.lockGridColumns,
            "rows": root.lockGridRows,
            "mediaEnabled": root.lockMediaEnabled,
            "widgets": rows
        }));
    }
    function setLockMediaEnabled(enabled) {
        const next = !!enabled;
        if (root.lockMediaEnabled === next)
            return;
        root.lockMediaEnabled = next;
        root.persistLockWidgets();
    }
    function preferredNewsModel() {
        for (let i = 0; i < widgetsModel.count; i++) {
            if (widgetsModel.get(i).type !== "news")
                continue;

            let data = getData(i);
            if (data.model)
                return data.model;
        }
        return NewsService.defaultModel;
    }

    // Canonical size for a grid widget, derived from its type + layout. The
    // board relayout always sizes from this (never from persisted nw/nh, which
    // a mis-timed early relayout could otherwise shrink permanently). Notes
    // return null — they keep their free-form size.
    function presetSize(type, layout) {
        switch (type) {
        case "clock":
            return clockSize(layout || 4);
        case "weather":
            return weatherSize(layout || 1);
        case "reminders":
            return remindersSize(layout || 2);
        case "news":
            return newsSize(layout || 2);
        case "calendar":
            return calendarSize(layout || 2);
        case "stock":
            return stockSize(layout || 1);
        case "youtube":
            return youtubeSize(layout || 3);
        case "spotify":
            return spotifySize(layout || 3);
        }
        return null;
    }
    function remindersSize(layout) {
        switch (layout) {
        case 1:
            return {
                "nw": 220,
                "nh": 220
            }; // small
        case 3:
            return {
                "nw": 464,
                "nh": 464
            }; // large
        case 2:
        default:
            return {
                "nw": 464,
                "nh": 220
            }; // medium
        }
    }
    function removeAt(index) {
        if (index < 0 || index >= widgetsModel.count)
            return;

        const removed = widgetsModel.get(index);
        let wasNote = removed.type === "note";
        const removedReminderListId = removed.type === "reminders" ? root._safeReminderListId(root._objectFromJson(removed.payload).listId) : "";
        widgetsModel.remove(index);
        root.persist();
        if (removedReminderListId !== "")
            root._markReminderUnavailable(removedReminderListId);
        if (!wasNote)
            root.relayoutNeeded();
    }
    function removeLockWidget(index) {
        if (index < 0 || index >= lockWidgetsModel.count)
            return;
        lockWidgetsModel.remove(index);
        root.persistLockWidgets();
    }
    function setCalendarLayout(index, layout) {
        if (root._isLockEditorIndex(index))
            return root._setLockWidgetData(root._lockIndexFromEditor(index), { "layout": layout });
        if (index < 0 || index >= widgetsModel.count)
            return false;

        let sz = root.calendarSize(layout);
        widgetsModel.setProperty(index, "nw", sz.nw);
        widgetsModel.setProperty(index, "nh", sz.nh);
        setData(index, {
            "layout": layout
        });
        root.relayoutNeeded();
        return true;
    }

    // Resize a clock to its layout's preferred size + ensure face count.
    function setClockLayout(index, layout) {
        let cur = getData(index);
        let faces = cur.faces || [];
        let needMulti = (layout === 2 || layout === 3);
        if (needMulti) {
            let defs = root.defaultClockFaces(layout);
            while (faces.length < 4)
                faces.push(defs[faces.length]);
            faces = faces.slice(0, 4);
        } else {
            faces = faces.slice(0, 1);
            if (faces.length === 0)
                faces = root.defaultClockFaces(layout);
        }
        if (root._isLockEditorIndex(index))
            return root._setLockWidgetData(root._lockIndexFromEditor(index), {
                "layout": layout,
                "faces": faces
            });
        if (index < 0 || index >= widgetsModel.count)
            return false;
        let sz = root.clockSize(layout);
        widgetsModel.setProperty(index, "nw", sz.nw);
        widgetsModel.setProperty(index, "nh", sz.nh);
        setData(index, {
            "layout": layout,
            "faces": faces
        });
        root.relayoutNeeded();
        return true;
    }

    // Merge `patch` into the widget's data object and persist.
    function setData(index, patch) {
        if (root._isLockEditorIndex(index))
            return root._setLockWidgetData(root._lockIndexFromEditor(index), patch);
        if (index < 0 || index >= widgetsModel.count)
            return false;

        const item = widgetsModel.get(index);
        let cur = getData(index);
        for (let k in patch)
            cur[k] = patch[k];
        if (item.type === "reminders")
            cur = root._normalizedReminderData(cur);
        let str = JSON.stringify(cur);
        if (str === item.payload)
            return true;

        widgetsModel.setProperty(index, "payload", str);
        root.persist();
        if (item.type === "reminders" && root.activeBoardKey !== "")
            root._syncLinkedReminderSource(root.activeBoardKey, item.wid, cur);
        return true;
    }
    function setNewsLayout(index, layout) {
        if (root._isLockEditorIndex(index))
            return root._setLockWidgetData(root._lockIndexFromEditor(index), { "layout": layout });
        if (index < 0 || index >= widgetsModel.count)
            return false;

        let sz = root.newsSize(layout);
        widgetsModel.setProperty(index, "nw", sz.nw);
        widgetsModel.setProperty(index, "nh", sz.nh);
        setData(index, {
            "layout": layout
        });
        root.relayoutNeeded();
        return true;
    }
    function setPosition(index, x, y, save) {
        if (index < 0 || index >= widgetsModel.count)
            return;

        widgetsModel.setProperty(index, "nx", x);
        widgetsModel.setProperty(index, "ny", y);
        if (save)
            root.persist();
    }
    function setRemindersLayout(index, layout) {
        if (root._isLockEditorIndex(index))
            return root._setLockWidgetData(root._lockIndexFromEditor(index), { "layout": layout });
        if (index < 0 || index >= widgetsModel.count)
            return false;

        let sz = root.remindersSize(layout);
        widgetsModel.setProperty(index, "nw", sz.nw);
        widgetsModel.setProperty(index, "nh", sz.nh);
        setData(index, {
            "layout": layout
        });
        root.relayoutNeeded();
        return true;
    }
    function setSize(index, w, h, save) {
        if (index < 0 || index >= widgetsModel.count)
            return;

        widgetsModel.setProperty(index, "nw", w);
        widgetsModel.setProperty(index, "nh", h);
        if (save)
            root.persist();
    }
    function setSpotifyLayout(index, layout) {
        if (root._isLockEditorIndex(index))
            return root._setLockWidgetData(root._lockIndexFromEditor(index), { "layout": layout });
        if (index < 0 || index >= widgetsModel.count)
            return false;

        let sz = root.spotifySize(layout);
        widgetsModel.setProperty(index, "nw", sz.nw);
        widgetsModel.setProperty(index, "nh", sz.nh);
        setData(index, {
            "layout": layout
        });
        root.relayoutNeeded();
        return true;
    }
    function setStockLayout(index, layout) {
        if (root._isLockEditorIndex(index))
            return root._setLockWidgetData(root._lockIndexFromEditor(index), { "layout": layout });
        if (index < 0 || index >= widgetsModel.count)
            return false;

        let sz = root.stockSize(layout);
        widgetsModel.setProperty(index, "nw", sz.nw);
        widgetsModel.setProperty(index, "nh", sz.nh);
        setData(index, {
            "layout": layout
        });
        root.relayoutNeeded();
        return true;
    }

    // Resize a weather widget to its layout's preferred size.
    function setWeatherLayout(index, layout) {
        if (root._isLockEditorIndex(index))
            return root._setLockWidgetData(root._lockIndexFromEditor(index), { "layout": layout });
        if (index < 0 || index >= widgetsModel.count)
            return false;

        let sz = root.weatherSize(layout);
        widgetsModel.setProperty(index, "nw", sz.nw);
        widgetsModel.setProperty(index, "nh", sz.nh);
        setData(index, {
            "layout": layout
        });
        root.relayoutNeeded();
        return true;
    }
    function setYoutubeLayout(index, layout) {
        if (root._isLockEditorIndex(index))
            return root._setLockWidgetData(root._lockIndexFromEditor(index), { "layout": layout });
        if (index < 0 || index >= widgetsModel.count)
            return false;

        let sz = root.youtubeSize(layout);
        widgetsModel.setProperty(index, "nw", sz.nw);
        widgetsModel.setProperty(index, "nh", sz.nh);
        setData(index, {
            "layout": layout
        });
        root.relayoutNeeded();
        return true;
    }
    function spotifySize(layout) {
        switch (layout) {
        case 1:
            return {
                "nw": 220,
                "nh": 220
            };
        case 2:
            return {
                "nw": 464,
                "nh": 220
            };
        case 3:
        default:
            return {
                "nw": 708,
                "nh": 464
            };
        }
    }
    function stockSize(layout) {
        switch (layout) {
        case 2:
            return {
                "nw": 1440,
                "nh": 708
            }; // XXL, twice the large footprint
        case 1:
        default:
            return {
                "nw": 708,
                "nh": 708
            }; // large
        }
    }
    function typeAt(index) {
        if (root._isLockEditorIndex(index))
            return root.lockTypeAt(root._lockIndexFromEditor(index));
        if (index < 0 || index >= widgetsModel.count)
            return "";

        return widgetsModel.get(index).type;
    }
    function weatherSize(layout) {
        switch (layout) {
        case 2:
            return {
                "nw": 464,
                "nh": 220
            }; // medium (hourly)
        case 3:
            return {
                "nw": 220,
                "nh": 220
            }; // conditions (small)
        case 4:
            return {
                "nw": 220,
                "nh": 220
            }; // sun
        case 1:
        default:
            return {
                "nw": 464,
                "nh": 464
            }; // large (hourly + daily)
        }
    }
    function youtubeSize(layout) {
        switch (layout) {
        case 1:
            return {
                "nw": 220,
                "nh": 220
            };
        case 2:
            return {
                "nw": 464,
                "nh": 220
            };
        case 3:
        default:
            return {
                "nw": 708,
                "nh": 464
            };
        }
    }

    Component.onCompleted: {
        root._load();
        root._ensureReminderListIds();
        root._loadReminderLinks(false);
        root._loadLockWidgets();
        root._refreshLinkedReminders(false);
    }

    ListModel {
        id: widgetsModel
    }
    ListModel {
        id: lockWidgetsModel
    }
    FileView {
        id: store

        blockLoading: true
        path: Quickshell.stateDir + "/widgets.json"
        printErrors: false
    }
    // Legacy sticky-notes file from before the widgets refactor — migrated once.

    FileView {
        id: legacy

        blockLoading: true
        path: Quickshell.stateDir + "/notes.json"
        printErrors: false
    }
    FileView {
        id: lockStore

        blockLoading: true
        path: root.sharedStateRoot !== "" ? root.sharedStateRoot + "/lock-widgets.json" : ""
        printErrors: false
    }
    FileView {
        id: reminderLinkStore

        blockLoading: true
        blockWrites: true
        path: root.sharedStateRoot !== "" ? root.sharedStateRoot + "/lock-reminders.json" : ""
        printErrors: false
        watchChanges: true

        onFileChanged: reload()
        onLoaded: if (root._reminderLinksLoaded)
            root._loadReminderLinks(true)
    }
}
