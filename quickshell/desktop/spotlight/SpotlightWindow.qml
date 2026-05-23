import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Controls

PanelWindow {
    id: win

    // ── Public state ─────────────────────────────────────────────────────
    property bool show: false
    signal closeRequested

    // Stay mapped a bit after `show=false` so the close animation can play out
    // before the wayland surface unmaps.
    property bool _surfaceVisible: false
    visible: _surfaceVisible

    onShowChanged: {
        if (show) {
            // Open on the currently focused monitor
            let m = Hyprland.focusedMonitor
            if (m && m.screen) win.screen = m.screen
            // Reset state
            queryField.text = ""
            win.selectedIndex = 0
            _surfaceVisible = true
            unmapTimer.stop()
            queryField.forceActiveFocus()
        } else {
            unmapTimer.restart()
        }
    }

    Timer {
        id: unmapTimer
        interval: 220
        onTriggered: win._surfaceVisible = false
    }

    // ── Layer / placement ───────────────────────────────────────────────
    WlrLayershell.namespace: "qs-spotlight"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand lets fcitx5's wayland_v2 frontend bind to the TextField's
    // text-input request. With Exclusive the compositor short-circuits the
    // text-input protocol path and Qt's fcitx plugin falls back to its dbus
    // frontend — Hangul composition is unreliable on dbus + layer-shell.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Full-screen overlay so the empty area outside the card receives clicks
    // and the root MouseArea (below) can dismiss the spotlight.
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    readonly property bool dark: ThemeService.isDark
    readonly property string query: queryField.text
    property int selectedIndex: 0

    // ── Calc support ─────────────────────────────────────────────────────
    readonly property bool isCalc: {
        let q = query.trim()
        if (!q) return false
        // Looks like a math expression: contains an operator and only safe chars
        if (!/^[\d\s+\-*/().%^]+$/.test(q)) return false
        if (!/[\d]/.test(q)) return false
        return /[+\-*/^%]/.test(q)
    }
    readonly property string calcResult: {
        if (!isCalc) return ""
        try {
            // Replace ^ with ** for exponentiation
            let expr = query.trim().replace(/\^/g, "**")
            let r = Function('"use strict"; return (' + expr + ')')()
            if (typeof r !== "number" || !Number.isFinite(r)) return ""
            // Pretty-print: trim trailing zeros
            return Number.isInteger(r) ? String(r) : String(Number(r.toFixed(8)))
        } catch (e) { return "" }
    }

    // ── Google search fallback ──────────────────────────────────────────
    readonly property bool showGoogleFallback:
        query.trim() !== "" && !isCalc && filtered.length === 0

    function activateGoogleSearch() {
        let q = query.trim()
        if (!q) return
        let url = "https://www.google.com/search?q=" + encodeURIComponent(q)
        // execDetached fully reparents the child to PID 1 so it survives even
        // if Quickshell's Process plumbing is torn down. `runProc.running = true`
        // kept the child tied to Quickshell, which silently killed slower-to-
        // initialize GTK apps like nwg-look/nwg-displays after gtk-launch
        // returned.
        Quickshell.execDetached(["xdg-open", url])
        win.closeRequested()
    }

    // ── App search ───────────────────────────────────────────────────────
    readonly property var filtered: {
        let q = query.trim().toLowerCase()
        if (!q || isCalc) return []
        let apps = DesktopEntries.applications.values
        let out = []
        for (let i = 0; i < apps.length; i++) {
            let app = apps[i]
            if (!app || app.noDisplay) continue
            let n = (app.name || "").toLowerCase()
            if (!n) continue
            let g = (app.genericName || "").toLowerCase()
            let c = (app.comment || "").toLowerCase()
            let kw = (app.keywords || []).join(" ").toLowerCase()

            let score = 0
            if (n === q)                  score = 1000
            else if (n.startsWith(q))     score = 800
            else if (n.split(/\s+/).some(w => w.startsWith(q))) score = 600
            else if (n.includes(q))       score = 400
            else if (g && g.includes(q))  score = 200
            else if (kw.includes(q))      score = 150
            else if (c && c.includes(q))  score = 100
            if (score > 0) out.push({ app: app, score: score })
        }
        out.sort((a, b) => b.score - a.score)
        return out.slice(0, 8).map(o => o.app)
    }
    readonly property int rowH: 52
    readonly property int bodyHeight: {
        if (isCalc && calcResult !== "") return rowH + 8
        if (filtered.length > 0) return Math.min(filtered.length, 8) * rowH + 8
        if (showGoogleFallback) return rowH + 8
        return 0
    }

    // Reset selection when filter changes
    onFilteredChanged: selectedIndex = 0

    function activateSelected() {
        if (isCalc) {
            if (calcResult === "") return
            Quickshell.execDetached(["bash", "-c", "printf %s '" + calcResult.replace(/'/g, "'\\''") + "' | wl-copy"])
            win.closeRequested()
            return
        }
        if (showGoogleFallback) {
            activateGoogleSearch()
            return
        }
        if (filtered.length === 0) return
        let idx = Math.max(0, Math.min(selectedIndex, filtered.length - 1))
        let app = filtered[idx]
        if (app) {
            // Quickshell's app.execute() runs into trouble with .desktop
            // entries that have complex escapes — kakaotalk.exe.desktop's
            // Exec line has \\\\ and escaped spaces for a Wine path and
            // simply doesn't launch. gtk-launch hands the entry to GIO
            // which parses the spec correctly, and matches the dock.
            //
            // Quickshell.execDetached fully reparents the child to PID 1, so
            // slow-starting GTK apps (nwg-look, nwg-displays) aren't killed
            // when the surrounding Process state is torn down.
            Quickshell.execDetached(["gtk-launch", app.id])
        }
        win.closeRequested()
    }

    // ── UI ───────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        width: 720
        height: 64 + win.bodyHeight
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(120, Math.round((parent ? parent.height : 1080) * 0.22))
        radius: 18
        color: dark ? Qt.rgba(16/255, 16/255, 21/255, 0.78)
                    : Qt.rgba(255/255, 255/255, 255/255, 0.78)
        border.color: dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.13)
        border.width: 1

        // Open: fade + scale-up from 0.96. Close: fade + slight scale-down.
        opacity: win.show ? 1.0 : 0.0
        scale: win.show ? 1.0 : 0.96
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }

        // Search row
        Item {
            id: inputRow
            x: 14
            y: 12
            width: parent.width - 28
            height: 40

            // Use the system icon-theme glyph instead of Nerd Font here —
            // some Propo variants don't render U+F0349 at large pixel sizes
            // (works in launchpad at 18px but not here at 22px). Image source
            // resolution falls back through symbolic, then the regular icon.
            Image {
                id: searchIcon
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 12
                width: 20; height: 20
                sourceSize.width: 20; sourceSize.height: 20
                smooth: true
                mipmap: true
                source: "image://icon/system-search-symbolic"
                // In light mode the Adwaita symbolic SVG is dark grey; raising
                // its opacity ensures it stays visible on the light glass card.
                opacity: dark ? 0.65 : 0.85

                // Fallback chain if the symbolic icon is missing in the theme
                onStatusChanged: {
                    if (status === Image.Error) {
                        if (source.toString().endsWith("system-search-symbolic"))
                            source = "image://icon/edit-find-symbolic"
                        else if (source.toString().endsWith("edit-find-symbolic"))
                            source = "image://icon/search"
                    }
                }
            }

            TextField {
                id: queryField
                anchors.left: searchIcon.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                background: null
                color: dark ? "#ffffff" : "#222222"
                placeholderText: "Search"
                placeholderTextColor: dark ? Qt.rgba(1, 1, 1, 0.35) : Qt.rgba(0, 0, 0, 0.35)
                font.family: "SF Pro Display"
                font.pixelSize: 16
                selectByMouse: true

                Keys.onEscapePressed: win.closeRequested()
                Keys.onUpPressed: {
                    if (win.filtered.length > 0)
                        win.selectedIndex = (win.selectedIndex - 1 + win.filtered.length) % win.filtered.length
                }
                Keys.onDownPressed: {
                    if (win.filtered.length > 0)
                        win.selectedIndex = (win.selectedIndex + 1) % win.filtered.length
                }
                Keys.onReturnPressed: win.activateSelected()
                Keys.onEnterPressed: win.activateSelected()
            }
        }

        // Divider above body
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: inputRow.bottom
            anchors.topMargin: 6
            height: 1
            color: dark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08)
            visible: win.bodyHeight > 0
        }

        // ── Calc result row ──────────────────────────────────────────────
        Rectangle {
            visible: win.isCalc && win.calcResult !== ""
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.top: inputRow.bottom
            anchors.topMargin: 10
            height: win.rowH - 4
            radius: 12
            color: Qt.rgba(10/255, 132/255, 255/255, 0.18)

            Row {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 14

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰃬"
                    color: dark ? "#ffffff" : "#222222"
                    font.family: "JetBrainsMono Nerd Font Propo"
                    font.pixelSize: 22
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "= " + win.calcResult
                    color: dark ? "#ffffff" : "#222222"
                    font.family: "SF Pro Display"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                }

                Item { width: 6; height: 1 }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Enter to copy"
                    color: dark ? Qt.rgba(1, 1, 1, 0.45) : Qt.rgba(0, 0, 0, 0.40)
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                }
            }
        }

        // ── Google search fallback row ───────────────────────────────────
        Rectangle {
            visible: win.showGoogleFallback
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.top: inputRow.bottom
            anchors.topMargin: 10
            height: win.rowH - 4
            radius: 12
            color: googleHover.hovered
                ? (dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                : "transparent"
            Behavior on color { ColorAnimation { duration: 80 } }

            HoverHandler { id: googleHover }

            Row {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12

                // Google "G" — colorful icon if available, fallback to nerd-font
                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28; height: 28
                    sourceSize.width: 28; sourceSize.height: 28
                    source: "image://icon/google-chrome"
                    smooth: true; mipmap: true
                    visible: status === Image.Ready
                }
                Text {
                    visible: !googIcon.parent  // never (placeholder; the Image above acts as primary)
                    text: ""
                    id: googIcon
                }

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 28 - 12
                    height: searchLine.implicitHeight + searchHint.implicitHeight + 2

                    Text {
                        id: searchLine
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        text: "Search \"" + win.query.trim() + "\" on Google"
                        color: dark ? "#ffffff" : "#1a1a1a"
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        id: searchHint
                        anchors.left: parent.left
                        anchors.top: searchLine.bottom
                        anchors.topMargin: 1
                        text: "Press Enter to open in browser"
                        color: dark ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(0, 0, 0, 0.50)
                        font.family: "SF Pro Display"
                        font.pixelSize: 11
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: win.activateGoogleSearch()
            }
        }

        // ── Result list ──────────────────────────────────────────────────
        ListView {
            id: results
            visible: !win.isCalc && win.filtered.length > 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: inputRow.bottom
            anchors.bottom: parent.bottom
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            interactive: false
            currentIndex: win.selectedIndex
            model: win.filtered

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: ListView.view.width
                height: win.rowH
                radius: 12
                color: index === win.selectedIndex
                    ? (dark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.06))
                    : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 14
                    spacing: 12

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 32
                        height: 32
                        source: modelData.icon ? "image://icon/" + modelData.icon : "image://icon/application-x-executable"
                        smooth: true
                        mipmap: true
                        sourceSize.width: 32
                        sourceSize.height: 32
                        onStatusChanged: {
                            if (status === Image.Error)
                                source = "image://icon/application-x-executable"
                        }
                    }

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 32 - 12
                        height: nameLabel.implicitHeight + (commentLabel.visible ? commentLabel.implicitHeight + 2 : 0)

                        Text {
                            id: nameLabel
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            text: modelData.name
                            color: dark ? "#ffffff" : "#1a1a1a"
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }

                        Text {
                            id: commentLabel
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: nameLabel.bottom
                            anchors.topMargin: 1
                            text: modelData.comment || ""
                            visible: text !== ""
                            color: dark ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(0, 0, 0, 0.50)
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onPositionChanged: win.selectedIndex = index
                    onClicked: {
                        win.selectedIndex = index
                        win.activateSelected()
                    }
                }
            }
        }
    }

    // Click-outside dismisses (the panel is full-width but card is centered;
    // empty area outside the card consumes the click).
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: win.closeRequested()
    }
}
