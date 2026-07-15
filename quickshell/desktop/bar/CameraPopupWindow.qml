import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtMultimedia
import Qt5Compat.GraphicalEffects

PanelWindow {
    id: win

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "qs-camera-controls"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property bool dark: ThemeService.isDark
    readonly property bool shown: PrivacyService.popupVisible
    readonly property color cardBg: dark ? Qt.rgba(30/255, 30/255, 32/255, 0.96) : Qt.rgba(246/255, 246/255, 248/255, 0.95)
    readonly property color primaryText: dark ? "#ffffff" : "#1c1c1e"
    readonly property color secondaryText: dark ? Qt.rgba(1, 1, 1, 0.58) : Qt.rgba(0, 0, 0, 0.55)
    readonly property color surface: dark ? Qt.rgba(1, 1, 1, 0.075) : Qt.rgba(0, 0, 0, 0.055)
    readonly property color surfaceHover: dark ? Qt.rgba(1, 1, 1, 0.13) : Qt.rgba(0, 0, 0, 0.09)
    readonly property color divider: dark ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(0, 0, 0, 0.09)
    readonly property string cameraOwners: PrivacyService.cameraApps.map(app => app.name).join(", ") || PrivacyService.cameraAppName
    property bool _surfaceVisible: false
    property bool backgroundPageOpen: false
    visible: _surfaceVisible

    function selectedCamera() {
        let inputs = mediaDevices.videoInputs
        let wanted = PrivacyService.cameraPreviewName.toLowerCase()
        for (let i = 0; i < inputs.length; i++) {
            let description = String(inputs[i].description || "").toLowerCase()
            if (wanted !== "" && (description.indexOf(wanted) >= 0 || wanted.indexOf(description) >= 0))
                return inputs[i]
        }
        return mediaDevices.defaultVideoInput
    }

    Connections {
        target: PrivacyService
        function onPopupVisibleChanged() {
            if (PrivacyService.popupVisible) {
                if (PrivacyService.targetScreen) win.screen = PrivacyService.targetScreen
                win.backgroundPageOpen = false
                win._surfaceVisible = true
            }
        }
    }

    onVisibleChanged: if (visible) focusScope.forceActiveFocus()

    MediaDevices { id: mediaDevices }

    Camera {
        id: previewCamera
        cameraDevice: win.selectedCamera()
        active: win.shown && PrivacyService.cameraUsingVirtual && PrivacyService.cameraPreviewAvailable
    }

    CaptureSession {
        camera: previewCamera
        videoOutput: previewOutput
    }

    Process {
        id: imagePicker
        property string selection: ""
        stdout: StdioCollector { onStreamFinished: imagePicker.selection = text.trim() }
        onExited: {
            if (imagePicker.selection !== "") PrivacyService.setBackground("image", imagePicker.selection)
            PrivacyService.popupVisible = true
            Qt.callLater(() => win.backgroundPageOpen = true)
        }
    }

    Process {
        id: colorPicker
        property string selection: ""
        stdout: StdioCollector { onStreamFinished: colorPicker.selection = text.trim() }
        onExited: {
            const selected = win.normalizePickedColor(colorPicker.selection)
            if (selected !== "") PrivacyService.setBackground("color", selected)
            PrivacyService.popupVisible = true
            Qt.callLater(() => win.backgroundPageOpen = true)
        }
    }

    function chooseBackgroundImage() {
        if (imagePicker.running) return
        imagePicker.selection = ""
        imagePicker.command = [
            "zenity", "--file-selection", "--title=Choose a Background",
            "--file-filter=Images | *.png *.jpg *.jpeg *.webp *.bmp"
        ]
        PrivacyService.popupVisible = false
        imagePicker.running = true
    }

    function normalizePickedColor(value) {
        const selection = String(value).trim()
        if (/^#[0-9a-fA-F]{6}$/.test(selection)) return selection.toUpperCase()
        if (/^#[0-9a-fA-F]{12}$/.test(selection)) {
            return ("#" + selection.slice(1, 3) + selection.slice(5, 7) + selection.slice(9, 11)).toUpperCase()
        }
        const components = selection.match(/[0-9.]+/g)
        if (!components || components.length < 3) return ""
        let values = [Number(components[0]), Number(components[1]), Number(components[2])]
        if (Math.max(values[0], values[1], values[2]) <= 1) values = values.map(component => component * 255)
        return "#" + values.map(component => {
            const byte = Math.max(0, Math.min(255, Math.round(component)))
            return ("0" + byte.toString(16)).slice(-2)
        }).join("").toUpperCase()
    }

    function chooseBackgroundColor() {
        if (colorPicker.running) return
        colorPicker.selection = ""
        const initial = PrivacyService.backgroundMode === "color" ? PrivacyService.backgroundValue : "#5AC8FA"
        colorPicker.command = [
            "zenity", "--color-selection", "--show-palette",
            "--title=Choose a Background Color", "--color=" + initial
        ]
        PrivacyService.popupVisible = false
        colorPicker.running = true
    }

    component ActionRow: Rectangle {
        id: actionRow
        property string icon: ""
        property string title: ""
        property string value: ""
        property bool available: true
        property bool selected: false
        property bool showChevron: true
        signal activated
        height: 48
        radius: 12
        color: rowHover.hovered && available ? win.surfaceHover : "transparent"
        opacity: available ? 1 : 0.46
        scale: rowTap.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 13 } }

        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 30
            height: 30
            radius: 15
            color: actionRow.selected && actionRow.available
                ? "#30D158"
                : (win.dark ? "#48484A" : "#D1D1D6")
            Text {
                anchors.centerIn: parent
                text: actionRow.icon
                color: actionRow.selected && actionRow.available ? "#ffffff" : win.secondaryText
                font.family: "JetBrainsMono Nerd Font Propo"
                font.pixelSize: 14
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 48
            anchors.verticalCenter: parent.verticalCenter
            text: actionRow.title
            color: win.primaryText
            font.family: "SF Pro Display"
            font.pixelSize: 14
            font.weight: Font.Medium
        }

        Text {
            anchors.right: actionRow.showChevron ? chevron.left : parent.right
            anchors.rightMargin: actionRow.showChevron ? 8 : 12
            anchors.verticalCenter: parent.verticalCenter
            text: actionRow.value
            color: win.secondaryText
            font.family: "SF Pro Display"
            font.pixelSize: 12
            font.weight: Font.Medium
        }

        Text {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            visible: actionRow.showChevron && actionRow.available
            text: "󰅂"
            color: win.secondaryText
            font.family: "JetBrainsMono Nerd Font Propo"
            font.pixelSize: 13
        }

        HoverHandler {
            id: rowHover
            enabled: actionRow.available
            cursorShape: actionRow.available ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        TapHandler {
            id: rowTap
            enabled: actionRow.available
            onTapped: actionRow.activated()
        }
    }

    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: {
            if (win.backgroundPageOpen) win.backgroundPageOpen = false
            else PrivacyService.popupVisible = false
        }

        MouseArea { anchors.fill: parent; onPressed: PrivacyService.popupVisible = false }

        Rectangle {
            id: card
            width: win.backgroundPageOpen ? 430 : 372
            height: !win.backgroundPageOpen ? 470
                : (PrivacyService.backgroundMode === "image" ? 420
                : (PrivacyService.backgroundMode === "color" ? 382 : 366))
            x: Math.max(8, Math.min(focusScope.width - width - 8, PrivacyService.anchorX - width / 2))
            y: win.shown ? BarState.contentTop : BarState.contentTop - 8
            radius: 20
            color: win.cardBg
            border.color: ThemeService.stroke
            border.width: 1
            clip: true
            opacity: win.shown ? 1 : 0
            scale: win.shown ? 1 : 0.97
            transformOrigin: Item.Top
            Behavior on width { AppleSpring { spring: 15 } }
            Behavior on height { AppleSpring { spring: 18 } }
            Behavior on opacity { AppleSpring { spring: 14 } }
            Behavior on scale { AppleSpring { spring: 13 } }
            Behavior on y { AppleSpring { spring: 13 } }
            onOpacityChanged: if (!win.shown && opacity <= 0.002) win._surfaceVisible = false
            layer.enabled: true
            layer.effect: DropShadow {
                transparentBorder: true
                radius: 26
                samples: 53
                verticalOffset: 12
                color: Qt.rgba(0, 0, 0, win.dark ? 0.5 : 0.25)
            }

            MouseArea { anchors.fill: parent }

            Item {
                id: mainPage
                anchors.fill: parent
                opacity: win.backgroundPageOpen ? 0 : 1
                x: win.backgroundPageOpen ? -16 : 0
                enabled: !win.backgroundPageOpen
                Behavior on opacity { AppleSpring { spring: 16 } }
                Behavior on x { AppleSpring { spring: 15 } }

                Rectangle {
                    id: appHeader
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: 66
                    color: "transparent"

                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 38
                        height: 38
                        radius: 10
                        color: "#30D158"
                        Text {
                            anchors.centerIn: parent
                            text: "󰖠"
                            color: "#ffffff"
                            font.family: "JetBrainsMono Nerd Font Propo"
                            font.pixelSize: 18
                        }
                        Image {
                            id: appIcon
                            anchors.fill: parent
                            source: "image://icon/" + PrivacyService.cameraAppId
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                        }
                    }

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 66
                        anchors.right: parent.right
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1
                        Text {
                            width: parent.width
                            text: win.cameraOwners
                            color: win.primaryText
                            elide: Text.ElideRight
                            font.family: "SF Pro Display"
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            font.letterSpacing: -0.15
                        }
                        Text {
                            text: PrivacyService.cameraUsingVirtual ? "Using QS Camera" : "Using your camera"
                            color: win.secondaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                    }
                }

                Rectangle {
                    id: previewFrame
                    anchors { top: appHeader.bottom; left: parent.left; right: parent.right }
                    anchors.leftMargin: card.border.width
                    anchors.rightMargin: card.border.width
                    height: 205
                    color: "#080809"
                    clip: true

                    VideoOutput {
                        id: previewOutput
                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectCrop
                        mirrored: true
                        visible: previewCamera.active && previewCamera.error === Camera.NoError
                    }

                    Column {
                        anchors.centerIn: parent
                        width: parent.width - 40
                        spacing: 10
                        visible: !previewOutput.visible

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 44
                            height: 44
                            radius: 11
                            color: "#30D158"

                            Text {
                                anchors.centerIn: parent
                                text: "󰖠"
                                color: "#ffffff"
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 20
                            }

                            Image {
                                anchors.fill: parent
                                source: "image://icon/" + PrivacyService.cameraAppId
                                fillMode: Image.PreserveAspectFit
                                visible: status === Image.Ready
                            }
                        }

                        Text {
                            width: parent.width
                            text: PrivacyService.cameraUsingVirtual
                                ? (previewCamera.errorString || "QS Camera preview is starting")
                                : win.cameraOwners + " is using the physical camera"
                            color: Qt.rgba(1, 1, 1, 0.78)
                            horizontalAlignment: Text.AlignHCenter
                            elide: Text.ElideRight
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }

                        Text {
                            width: parent.width
                            text: PrivacyService.cameraUsingVirtual
                                ? "The processed camera appears here"
                                : "Select QS Camera in the app to use effects"
                            color: Qt.rgba(1, 1, 1, 0.45)
                            horizontalAlignment: Text.AlignHCenter
                            font.family: "SF Pro Display"
                            font.pixelSize: 11
                        }
                    }
                }

                Text {
                    id: cameraName
                    anchors { top: previewFrame.bottom; left: parent.left; right: parent.right }
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    height: 42
                    verticalAlignment: Text.AlignVCenter
                    text: PrivacyService.cameraName
                    color: win.primaryText
                    elide: Text.ElideRight
                    font.family: "SF Pro Display"
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                Column {
                    id: effectRows
                    anchors { top: cameraName.bottom; left: parent.left; right: parent.right }
                    anchors.leftMargin: 8
                    anchors.rightMargin: 8
                    spacing: 0

                    ActionRow {
                        width: parent.width
                        icon: "󰹑"
                        title: "Portrait"
                        value: !PrivacyService.portraitAvailable ? "Unavailable"
                            : !PrivacyService.cameraUsingVirtual ? "Select QS Camera"
                            : (PrivacyService.portraitEnabled ? "On" : "Off")
                        available: PrivacyService.portraitAvailable && PrivacyService.cameraUsingVirtual
                        selected: PrivacyService.portraitEnabled
                        showChevron: false
                        onActivated: PrivacyService.setPortrait(!PrivacyService.portraitEnabled)
                    }
                    ActionRow {
                        width: parent.width
                        icon: "󰸉"
                        title: "Background"
                        value: !PrivacyService.backgroundAvailable ? "Unavailable"
                            : !PrivacyService.cameraUsingVirtual ? "Select QS Camera"
                            : ""
                        available: PrivacyService.backgroundAvailable && PrivacyService.cameraUsingVirtual
                        selected: PrivacyService.backgroundMode !== "none"
                        onActivated: win.backgroundPageOpen = true
                    }
                }

                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: micMode.top }
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    height: 1
                    color: win.divider
                }

                Item {
                    id: micMode
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 61

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Mic Mode"
                        color: win.primaryText
                        font.family: "SF Pro Display"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Repeater {
                            model: PrivacyService.voiceIsolationAvailable
                                ? [{ id: "standard", name: "Standard" }, { id: "voice-isolation", name: "Voice Isolation" }]
                                : [{ id: "standard", name: "Standard" }]
                            delegate: Rectangle {
                                required property var modelData
                                readonly property bool selected: PrivacyService.micMode === modelData.id
                                width: label.implicitWidth + 18
                                height: 28
                                radius: 9
                                color: selected ? (win.dark ? Qt.rgba(1, 1, 1, 0.16) : "#ffffff") : win.surface
                                border.color: selected ? ThemeService.stroke : "transparent"
                                border.width: 1
                                scale: modeTap.pressed ? ThemeService.pressScale : 1
                                Behavior on scale { AppleSpring { spring: 13 } }
                                Text {
                                    id: label
                                    anchors.centerIn: parent
                                    text: modelData.name
                                    color: selected ? win.primaryText : win.secondaryText
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 11
                                    font.weight: selected ? Font.DemiBold : Font.Medium
                                }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                                TapHandler {
                                    id: modeTap
                                    enabled: !PrivacyService.busy && !parent.selected
                                    onTapped: PrivacyService.setMicMode(parent.modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            Item {
                id: backgroundPage
                anchors.fill: parent
                opacity: win.backgroundPageOpen ? 1 : 0
                x: win.backgroundPageOpen ? 0 : 16
                enabled: win.backgroundPageOpen
                Behavior on opacity { AppleSpring { spring: 16 } }
                Behavior on x { AppleSpring { spring: 15 } }

                Rectangle {
                    x: 14
                    y: 14
                    width: 30
                    height: 30
                    radius: 15
                    color: backHover.hovered ? win.surfaceHover : win.surface
                    scale: backTap.pressed ? ThemeService.pressScale : 1
                    Behavior on scale { AppleSpring { spring: 15 } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰅁"
                        color: win.primaryText
                        font.family: "JetBrainsMono Nerd Font Propo"
                        font.pixelSize: 14
                    }

                    HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: backTap; onTapped: win.backgroundPageOpen = false }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 18
                    text: "Background"
                    color: win.primaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 17
                    font.weight: Font.Bold
                    font.letterSpacing: -0.2
                }

                Row {
                    id: modeSelector
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    anchors.topMargin: 58
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    height: 44
                    spacing: 4

                    Repeater {
                        model: [
                            { id: "none", icon: "󰅖", name: "None" },
                            { id: "color", icon: "󰏘", name: "Color" },
                            { id: "image", icon: "󰋩", name: "Image" },
                            { id: "chroma", icon: "󰒀", name: "Chroma" }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool selected: PrivacyService.backgroundMode === modelData.id
                            width: (modeSelector.width - 12) / 4
                            height: modeSelector.height
                            radius: 12
                            color: selected ? (win.dark ? Qt.rgba(1, 1, 1, 0.16) : "#ffffff") : win.surface
                            border.color: selected ? ThemeService.stroke : "transparent"
                            border.width: 1
                            scale: modeTap.pressed ? ThemeService.pressScale : 1
                            Behavior on scale { AppleSpring { spring: 15 } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 1

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon
                                    color: selected ? "#30D158" : win.secondaryText
                                    font.family: "JetBrainsMono Nerd Font Propo"
                                    font.pixelSize: 15
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.name
                                    color: selected ? win.primaryText : win.secondaryText
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 10
                                    font.weight: Font.Medium
                                }
                            }

                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                id: modeTap
                                onTapped: {
                                    if (modelData.id === "image") {
                                        if (PrivacyService.backgroundImage !== "")
                                            PrivacyService.setBackground("image", PrivacyService.backgroundImage)
                                        else
                                            win.chooseBackgroundImage()
                                    }
                                    else PrivacyService.setBackground(modelData.id, modelData.id === "color" ? "#5AC8FA" : "")
                                }
                            }
                        }
                    }
                }

                Grid {
                    visible: PrivacyService.backgroundMode === "color"
                    anchors.top: modeSelector.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.topMargin: 28
                    width: 316
                    columns: 4
                    spacing: 20

                    Repeater {
                        model: [
                            "#5AC8FA", "#34C759", "#FF9F0A", "#FF375F",
                            "#BF5AF2", "#5E5CE6", "#8E8E93", "#2C2C2E",
                            "#FFD60A", "#64D2FF", "#AC8E68", "custom"
                        ]

                        delegate: Rectangle {
                            required property string modelData
                            readonly property bool custom: modelData === "custom"
                            width: 64
                            height: 64
                            radius: 16
                            color: custom ? win.surface : modelData
                            border.color: !custom && PrivacyService.backgroundValue === modelData
                                ? "#ffffff"
                                : Qt.rgba(1, 1, 1, 0.24)
                            border.width: !custom && PrivacyService.backgroundValue === modelData ? 3 : 1
                            scale: colorTap.pressed ? ThemeService.pressScale : 1
                            Behavior on scale { AppleSpring { spring: 15 } }

                            Text {
                                anchors.centerIn: parent
                                visible: parent.custom
                                text: "+"
                                color: win.primaryText
                                font.family: "SF Pro Display"
                                font.pixelSize: 28
                                font.weight: Font.Light
                            }

                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                id: colorTap
                                onTapped: {
                                    if (parent.custom) win.chooseBackgroundColor()
                                    else PrivacyService.setBackground("color", parent.modelData)
                                }
                            }
                        }
                    }
                }

                Item {
                    visible: PrivacyService.backgroundMode !== "color"
                    anchors { top: modeSelector.bottom; left: parent.left; right: parent.right; bottom: parent.bottom }
                    anchors.topMargin: 22
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.bottomMargin: 18

                    Rectangle {
                        id: backgroundPreview
                        anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: width * 9 / 16
                        radius: 16
                        color: win.surface
                        clip: true

                        Image {
                            anchors.fill: parent
                            visible: PrivacyService.backgroundMode === "image" && PrivacyService.backgroundImage !== ""
                            source: visible ? PrivacyService.backgroundImage : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 12
                            visible: PrivacyService.backgroundMode === "chroma"

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰒀"
                                color: win.secondaryText
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 30
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Transparent Background"
                                color: win.secondaryText
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 12
                            visible: PrivacyService.backgroundMode === "none"

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "󰅖"
                                color: win.secondaryText
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 30
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "Background is off"
                                color: win.secondaryText
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                            }
                        }
                    }

                    Rectangle {
                        anchors { top: backgroundPreview.bottom; left: parent.left; right: parent.right }
                        anchors.topMargin: 12
                        visible: PrivacyService.backgroundMode === "image"
                        height: 42
                        radius: 12
                        color: changeImageHover.hovered ? win.surfaceHover : win.surface
                        scale: changeImageTap.pressed ? ThemeService.pressScale : 1
                        Behavior on scale { AppleSpring { spring: 15 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 8

                            Text {
                                text: "󰋩"
                                color: "#30D158"
                                font.family: "JetBrainsMono Nerd Font Propo"
                                font.pixelSize: 14
                            }

                            Text {
                                text: "Change Image"
                                color: win.primaryText
                                font.family: "SF Pro Display"
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }

                        HoverHandler { id: changeImageHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: changeImageTap; onTapped: win.chooseBackgroundImage() }
                    }
                }
            }

        }
    }
}
