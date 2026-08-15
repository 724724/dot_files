pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Persistent launchpad layout: an ordered list of top-level items, each either
// an app or a folder of apps. Reconciled against the installed .desktop entries
// (new apps appended, uninstalled ones dropped) and saved to disk so the user's
// order + folders survive restarts.
//
//   app:    { type: "app",    id: "<desktop-id>" }
//   folder: { type: "folder", name: "Games", apps: ["steam", "lutris"] }
Singleton {
    id: root

    // The reconciled, render-ready layout the window draws from.
    property var items: []
    // The authoritative saved layout (what gets persisted); reconciliation always
    // rebuilds `items` from this so app installs/removals never lose the order.
    property var _saved: []
    property bool _loaded: false

    // id → live app object, rebuilt whenever the installed apps change.
    readonly property var appsById: {
        let m = ({})
        let apps = DesktopEntries.applications.values
        for (let i = 0; i < apps.length; i++) {
            let a = apps[i]
            if (!a || a.noDisplay || !a.name) continue
            m[a.id] = a
        }
        return m
    }
    function appById(id) { return appsById[id] || null }

    FileView {
        id: store
        path: Quickshell.stateDir + "/launchpad-layout.json"
        blockLoading: true
        printErrors: false
    }

    Component.onCompleted: {
        let raw = store.text()
        if (raw) { try { let p = JSON.parse(raw); if (Array.isArray(p)) root._saved = p } catch (e) {} }
        root._loaded = true
        root._reconcile()
    }
    // Re-run when apps are installed/removed (also fires once when entries first
    // populate after startup).
    onAppsByIdChanged: if (root._loaded) root._reconcile()

    function _persist() { if (root._loaded) store.setText(JSON.stringify(root._saved)) }
    function _commit(next) { root._saved = next; root.items = next; _persist() }

    // Merge the saved layout with the current app set: keep known order, drop
    // missing apps, unwrap folders that fall below 2 apps, append newcomers.
    function _reconcile() {
        let live = root.appsById
        let seen = ({})
        let out = []
        let base = root._saved || []
        for (let i = 0; i < base.length; i++) {
            let it = base[i]
            if (!it) continue
            if (it.type === "folder") {
                let apps = []
                let list = it.apps || []
                for (let j = 0; j < list.length; j++) {
                    let id = list[j]
                    if (live[id] && !seen[id]) { apps.push(id); seen[id] = true }
                }
                if (apps.length >= 2) out.push({ type: "folder", name: it.name || "Folder", apps: apps })
                else if (apps.length === 1) out.push({ type: "app", id: apps[0] })
            } else if (it.type === "app") {
                if (live[it.id] && !seen[it.id]) { out.push({ type: "app", id: it.id }); seen[it.id] = true }
            }
        }
        // Append installed apps not placed anywhere yet, alphabetically.
        let extra = []
        for (let id in live) if (!seen[id]) extra.push(id)
        extra.sort((a, b) => (live[a].name || "").toLowerCase().localeCompare((live[b].name || "").toLowerCase()))
        for (let k = 0; k < extra.length; k++) out.push({ type: "app", id: extra[k] })
        root.items = out
        // NOTE: do *not* overwrite `_saved` here. At startup _reconcile() runs
        // once before DesktopEntries is populated (live set empty), which would
        // otherwise blow away the saved folders/order. `_saved` stays the
        // authoritative layout (from disk, or the last user edit); only _commit
        // updates it.
    }

    // ── Mutations (each persists) ────────────────────────────────────────
    function reorderTo(src, dst) {
        if (src === dst || src < 0 || src >= items.length) return
        let next = items.slice()
        let it = next.splice(src, 1)[0]
        next.splice(Math.max(0, Math.min(next.length, dst)), 0, it)
        _commit(next)
    }

    // Drop app `srcIdx` onto app `dstIdx` → a new folder holding both, placed
    // where the target was.
    function makeFolder(srcIdx, dstIdx) {
        let next = items.slice()
        let src = next[srcIdx], dst = next[dstIdx]
        if (!src || !dst || src.type !== "app" || dst.type !== "app") return
        let folder = { type: "folder", name: "Folder", apps: [dst.id, src.id] }
        let hi = Math.max(srcIdx, dstIdx), lo = Math.min(srcIdx, dstIdx)
        next.splice(hi, 1)
        next.splice(lo, 1)
        next.splice(lo, 0, folder)
        _commit(next)
    }

    // Drop app `appIdx` onto folder `folderIdx` → add it to that folder.
    function addToFolder(folderIdx, appIdx) {
        let next = items.slice()
        let folder = next[folderIdx], appItem = next[appIdx]
        if (!folder || folder.type !== "folder" || !appItem || appItem.type !== "app") return
        if (folder.apps.indexOf(appItem.id) === -1)
            next[folderIdx] = { type: "folder", name: folder.name, apps: folder.apps.concat([appItem.id]) }
        next.splice(appIdx, 1)
        _commit(next)
    }

    // Pop an app out of a folder back to the top level (just after the folder).
    function removeFromFolder(folderIdx, appId) {
        let next = items.slice()
        let folder = next[folderIdx]
        if (!folder || folder.type !== "folder") return
        let apps = folder.apps.filter(id => id !== appId)
        if (apps.length >= 2) {
            next[folderIdx] = { type: "folder", name: folder.name, apps: apps }
            next.splice(folderIdx + 1, 0, { type: "app", id: appId })
        } else if (apps.length === 1) {
            next.splice(folderIdx, 1, { type: "app", id: apps[0] }, { type: "app", id: appId })
        } else {
            next.splice(folderIdx, 1, { type: "app", id: appId })
        }
        _commit(next)
    }

    function extractFromFolderToEnd(folderIdx, appId) {
        extractFromFolderAt(folderIdx, appId, -1)
    }

    function extractFromFolderAt(folderIdx, appId, dstIdx) {
        let next = items.slice()
        let folder = next[folderIdx]
        if (!folder || folder.type !== "folder") return
        let apps = folder.apps.filter(id => id !== appId)
        if (apps.length === folder.apps.length) return
        if (apps.length >= 2)
            next[folderIdx] = { type: "folder", name: folder.name, apps: apps }
        else if (apps.length === 1)
            next.splice(folderIdx, 1, { type: "app", id: apps[0] })
        else
            next.splice(folderIdx, 1)
        let insertAt = dstIdx >= 0
            ? Math.max(0, Math.min(next.length, dstIdx)) : next.length
        next.splice(insertAt, 0, { type: "app", id: appId })
        _commit(next)
    }

    function dropExtractedFolderApp(folderIdx, appId, dstIdx, merge) {
        let source = items[folderIdx]
        if (!source || source.type !== "folder"
                || source.apps.indexOf(appId) < 0) return
        if (merge && dstIdx === folderIdx) return

        let next = items.slice()
        let apps = source.apps.filter(id => id !== appId)
        let sourceRemoved = false
        if (apps.length >= 2)
            next[folderIdx] = { type: "folder", name: source.name, apps: apps }
        else if (apps.length === 1)
            next.splice(folderIdx, 1, { type: "app", id: apps[0] })
        else {
            next.splice(folderIdx, 1)
            sourceRemoved = true
        }

        let targetIdx = dstIdx
        if (sourceRemoved && targetIdx > folderIdx) targetIdx--
        let target = targetIdx >= 0 && targetIdx < next.length
            ? next[targetIdx] : null
        if (merge && target && target.type === "folder") {
            next[targetIdx] = {
                type: "folder",
                name: target.name,
                apps: target.apps.concat([appId])
            }
        } else if (merge && target && target.type === "app") {
            next[targetIdx] = {
                type: "folder",
                name: "Folder",
                apps: [target.id, appId]
            }
        } else {
            let insertAt = targetIdx >= 0
                ? Math.max(0, Math.min(next.length, targetIdx)) : next.length
            next.splice(insertAt, 0, { type: "app", id: appId })
        }
        _commit(next)
    }

    function reorderInFolder(folderIdx, from, to) {
        let next = items.slice()
        let folder = next[folderIdx]
        if (!folder || folder.type !== "folder" || from === to) return
        let apps = folder.apps.slice()
        let it = apps.splice(from, 1)[0]
        apps.splice(Math.max(0, Math.min(apps.length, to)), 0, it)
        next[folderIdx] = { type: "folder", name: folder.name, apps: apps }
        _commit(next)
    }

    function renameFolder(idx, name) {
        let next = items.slice()
        if (!next[idx] || next[idx].type !== "folder") return
        next[idx] = { type: "folder", name: (name || "").trim() || "Folder", apps: next[idx].apps }
        _commit(next)
    }
}
