import Quickshell
import QtQuick
import "../nc" as Nc

Image {
    id: root

    property string iconName: ""
    property string desktopId: ""
    property string appClass: ""
    property string genericFallback: ""
    property int resolvePriority: 0
    property bool _initialized: false
    property bool _fallbackMode: false
    property string _fallbackSource: ""
    readonly property var _themeRevision: Nc.ThemeService.iconThemeRevision || 0

    function _isThemeIcon(icon) {
        if (!icon) return false
        if (icon.startsWith("image://icon/")) return true
        return !icon.includes("://") && !icon.startsWith("/")
    }

    function _directUrl(icon) {
        if (!icon) return ""
        if (icon.includes("://")) return icon
        if (icon.startsWith("/")) return "file://" + icon
        return ""
    }

    function _beginFallback() {
        root._initialized = true
        root._fallbackMode = true
        let cached = IconFallbackService.sourceFor(
            iconName, desktopId, appClass, root._themeRevision)
        if (cached !== "") root._fallbackSource = cached
        else IconFallbackService.request(
            iconName, desktopId, appClass, root._themeRevision,
            root.resolvePriority)
    }

    function _refresh() {
        root._fallbackSource = ""
        root._fallbackMode = false
        root._initialized = true
        if (!iconName) return
        // A theme icon can be advertised by QIcon yet still fail to render
        // (for example Whisper App's hicolor-only icon under Os-Catalina).
        // Reuse the direct-file fallback learned from the first failure so
        // every newly-created delegate does not retry the broken provider and
        // emit the same warning again.
        let cached = IconFallbackService.sourceFor(
            iconName, desktopId, appClass, root._themeRevision)
        if (cached !== "") {
            root._fallbackMode = true
            root._fallbackSource = cached
            return
        }
        // Never hand a named icon to Quickshell's image://icon provider here.
        // Per-screen AppIcon delegates are destroyed during monitor hotplug,
        // while that provider renders QIcon/QSvgIconEngine work on the
        // QQuickPixmapReader thread. A pending render can then outlive its
        // screen delegate and leave the shared SVG engine with a corrupt file
        // name. Resolve named icons to ordinary file URLs in the persistent
        // singleton instead; direct files and unrelated image providers remain
        // safe to use as-is.
        if (root._isThemeIcon(iconName)) root._beginFallback()
    }

    function _resolvedSource() {
        // Property values are assigned during delegate construction. Avoid an
        // eager provider request in the short gap before refreshTimer runs,
        // and consult the shared cache directly when a new delegate binds.
        if (!root._initialized) return ""
        let cached = IconFallbackService.sourceFor(
            iconName, desktopId, appClass, root._themeRevision)
        if (cached !== "") return cached
        if (root._fallbackMode) return root._fallbackSource || genericFallback
        return root._directUrl(iconName)
    }

    source: root._resolvedSource()
    // Resolved URLs are immutable icon files. Reusing Qt's image cache avoids
    // starting fresh decode jobs when a screen disappears and its surviving
    // peer recreates the same bar/dock delegates.
    cache: true
    asynchronous: false
    // A Dock can change orientation while this shared icon delegate is alive.
    // Preserve the source aspect ratio even during that layout transition so a
    // temporarily non-square item can never squash the artwork.
    fillMode: Image.PreserveAspectFit

    Timer {
        id: refreshTimer
        interval: 0
        onTriggered: root._refresh()
    }

    Timer {
        id: imageCheckTimer
        interval: 0
        onTriggered: {
            if (!root._fallbackMode && root.status === Image.Ready
                    && (root.paintedWidth <= 0 || root.paintedHeight <= 0))
                root._beginFallback()
        }
    }

    Component.onCompleted: refreshTimer.restart()
    onIconNameChanged: refreshTimer.restart()
    onDesktopIdChanged: refreshTimer.restart()
    onAppClassChanged: refreshTimer.restart()
    on_ThemeRevisionChanged: refreshTimer.restart()
    onStatusChanged: {
        if (status === Image.Ready) imageCheckTimer.restart()
        else if (status === Image.Error && !_fallbackMode) root._beginFallback()
        else if (status === Image.Error && _fallbackSource !== ""
                && _fallbackSource !== genericFallback) {
            _fallbackSource = genericFallback
        }
    }

    Connections {
        target: IconFallbackService
        function onResolvedChanged() {
            if (!root._fallbackMode) return
            let value = IconFallbackService.sourceFor(
                root.iconName, root.desktopId, root.appClass, root._themeRevision)
            if (value !== "") root._fallbackSource = value
        }
    }
}
