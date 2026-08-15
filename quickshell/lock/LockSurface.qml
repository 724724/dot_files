pragma ComponentBehavior: Bound
import Quickshell.Wayland
import Quickshell.Widgets
import QtQuick
import qs.desktop.widgets

// WlSessionLock creates one surface for every current and newly connected
// screen. Authentication state is shared, while credential text stays local to
// each surface and is cleared globally through clearRevision.
WlSessionLockSurface {
    id: surface

    readonly property string avatarSource: {
        const path = String(controller.avatarSource || "");
        if (path === "")
            return "";
        return path.includes("://") ? path : "file://" + path;
    }
    readonly property bool compactLayout: width < 1200 || height < 760
    readonly property bool contentShown: entered && !controller.unlockAnimating
    required property var controller
    property bool coverageAnnounced: false
    property bool creationLogged: false
    readonly property real edgeInset: compactLayout ? 10 : 14 * uiScale
    property bool entered: false
    required property var equalizer
    required property var media
    property bool mediaIslandOpen: false
    property string outputName: "unknown"
    property var outputScreen: null
    readonly property real panelWidth: compactLayout ? width - edgeInset * 2 : Math.min(width * 0.60, 1200 * uiScale)
    readonly property real rightCenterX: compactLayout ? width / 2 : leftPanel.x + leftPanel.width + (width - leftPanel.x - leftPanel.width) / 2
    readonly property string snapshotSource: wallpaper.snapshotFor(outputName)
    readonly property real uiScale: Math.max(0.78, Math.min(1.2, Math.min(width / 1920, height / 1200)))
    property string verificationMask: ""
    required property var wallpaper
    readonly property string wallpaperSource: {
        const path = String(wallpaper.current || "");
        if (path === "")
            return "";
        return path.includes("://") ? path : "file://" + path;
    }

    function announceCoverage() {
        if (surface.visible)
            surface.beginEnterAnimation();
        if (surface.visible && surface.outputScreen && !surface.coverageAnnounced) {
            surface.coverageAnnounced = true;
            surface.controller.surfaceShown(surface.outputScreen);
        }
    }
    function beginEnterAnimation() {
        if (!surface.entered)
            enterAnimationStart.restart();
    }
    function makeVerificationMask(length) {
        // Retain only a bounded visual length surrogate while PAM is working;
        // the submitted credential itself is cleared from the TextInput.
        const visibleLength = Math.max(0, Math.min(Number(length) || 0, 48));
        let mask = "";
        for (let i = 0; i < visibleLength; i++)
            mask += "●";
        return mask;
    }
    function restorePasswordFocus() {
        if (surface.controller.authReady && !surface.controller.verificationInProgress) {
            Qt.callLater(() => passwordInput.forceActiveFocus());
        }
    }
    function submitAttempt() {
        if (!surface.controller.authReady || surface.controller.verificationInProgress || passwordInput.text.length === 0) {
            return;
        }

        let response = passwordInput.text;
        surface.verificationMask = surface.makeVerificationMask(response.length);
        // Only the non-sensitive dot surrogate remains on screen during the
        // intentional PAM failure delay.
        passwordInput.clear();
        surface.controller.submitPassword(response);
        response = "";
    }

    // This compositor-visible first-frame colour stays fully opaque before the
    // wallpaper or any QML scene-graph effects have loaded.
    color: "#070a10"

    Component.onDestruction: {
        if (surface.coverageAnnounced)
            surface.controller.surfaceRemoved(surface.outputScreen);
        if (surface.creationLogged)
            console.info("QS_LOCK surface removed screen=" + surface.outputName);
    }
    onScreenChanged: {
        // Preserve the first non-null wrapper. A replacement QScreen using the
        // same connector name receives a distinct wrapper identity.
        if (surface.screen && !surface.outputScreen) {
            surface.outputScreen = surface.screen;
            surface.outputName = surface.screen.name;
            surface.creationLogged = true;
            console.info("QS_LOCK surface created screen=" + surface.outputName);
        }
    }

    // Quickshell 0.3 emits screenChanged before it creates the backing
    // QQuickWindow. Its visible getter dereferences that window, so only read
    // visible from this signal, which is emitted after the window exists.
    onVisibleChanged: surface.announceCoverage()
    onContentShownChanged: if (!surface.contentShown)
        surface.mediaIslandOpen = false

    Timer {
        id: enterAnimationStart

        interval: 1
        repeat: false

        onTriggered: surface.entered = true
    }
    Rectangle {
        id: backdrop

        anchors.fill: parent
        color: "#070a10"

        // The capture helper pre-blurs the snapshot once on the CPU. At runtime
        // these are ordinary image quads: no persistent GPU blur passes or
        // full-output effect targets are kept while the session is locked.
        Item {
            id: backgroundMotion

            anchors.fill: parent
            scale: surface.controller.unlockAnimating ? 1.018 : 1
            transformOrigin: Item.Center

            Behavior on scale {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }

            Image {
                id: wallpaperImage

                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                height: Math.max(1, Math.ceil(backgroundMotion.height / 12))
                mipmap: false
                opacity: status === Image.Ready ? 1 : 0
                scale: 12
                smooth: true
                source: surface.wallpaperSource
                sourceSize.height: height
                sourceSize.width: width
                transformOrigin: Item.TopLeft
                width: Math.max(1, Math.ceil(backgroundMotion.width / 12))

                Behavior on opacity {
                    NumberAnimation {
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                }
            }

            // The file has already been resized and blurred. Decode no more
            // than half the logical output size and render it as one texture.
            Image {
                id: snapshotImage

                anchors.fill: parent
                asynchronous: true
                cache: false
                fillMode: Image.PreserveAspectCrop
                mipmap: false
                opacity: status === Image.Ready ? 1 : 0
                smooth: true
                source: surface.snapshotSource
                sourceSize.height: Math.max(1, Math.ceil(height / 2))
                sourceSize.width: Math.max(1, Math.ceil(width / 2))

                Behavior on opacity {
                    NumberAnimation {
                        duration: 180
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        // Figma-inspired deep focus layer: the right side stays dark enough for
        // the white password capsule while the left glass panel remains airy.
        Rectangle {
            anchors.fill: parent
            color: "#52000000"
        }
        Rectangle {
            anchors.fill: parent

            gradient: Gradient {
                orientation: Gradient.Horizontal

                GradientStop {
                    color: "#14ffffff"
                    position: 0.0
                }
                GradientStop {
                    color: "#26000000"
                    position: 0.42
                }
                GradientStop {
                    color: "#9c000000"
                    position: 1.0
                }
            }
        }
        Rectangle {
            id: panelContactShadow

            // A tight contact shadow keeps the glass attached to the backdrop.
            // The old 8×10px opaque duplicate read as a second floating panel.
            color: "#18000000"
            height: leftPanel.height
            opacity: surface.contentShown ? 1 : 0
            radius: leftPanel.radius
            scale: surface.contentShown ? 1 : 0.992
            width: leftPanel.width
            x: leftPanel.x
            y: leftPanel.y + 2 * surface.uiScale

            Behavior on opacity {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                LockSpring {
                    damping: 1
                    epsilon: 0.001
                    spring: 12
                }
            }
            transform: Translate {
                x: surface.contentShown ? 0 : -12 * surface.uiScale

                Behavior on x {
                    LockSpring {
                        damping: 1
                        epsilon: 0.001
                        spring: 12
                    }
                }
            }
        }
        Rectangle {
            id: leftPanel

            border.color: "#70ffffff"
            border.width: 1
            color: surface.compactLayout ? "#30ffffff" : "#3affffff"
            height: surface.height - surface.edgeInset * 2
            opacity: surface.contentShown ? 1 : 0
            radius: (surface.compactLayout ? 24 : 34) * surface.uiScale
            scale: surface.contentShown ? 1 : 0.992
            width: surface.panelWidth
            x: surface.edgeInset
            y: surface.edgeInset

            gradient: Gradient {
                GradientStop {
                    color: "#55ffffff"
                    position: 0.0
                }
                GradientStop {
                    color: "#36ffffff"
                    position: 0.55
                }
                GradientStop {
                    color: "#24ffffff"
                    position: 1.0
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on scale {
                LockSpring {
                    damping: 1
                    epsilon: 0.001
                    spring: 12
                }
            }
            transform: Translate {
                x: surface.contentShown ? 0 : -12 * surface.uiScale

                Behavior on x {
                    LockSpring {
                        damping: 1
                        epsilon: 0.001
                        spring: 12
                    }
                }
            }

            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: leftPanel.radius * 0.72
                anchors.right: parent.right
                anchors.rightMargin: leftPanel.radius * 0.72
                anchors.top: parent.top
                anchors.topMargin: 1
                color: "#70ffffff"
                height: 1
                opacity: 0.56
                radius: 1
            }
            Column {
                id: clockStack

                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: (surface.compactLayout ? 82 : 148) * surface.uiScale
                opacity: surface.contentShown ? 1 : 0
                spacing: 9 * surface.uiScale

                Behavior on opacity {
                    NumberAnimation {
                        duration: 320
                        easing.type: Easing.OutCubic
                    }
                }
                transform: Translate {
                    y: surface.contentShown ? 0 : 10 * surface.uiScale

                    Behavior on y {
                        LockSpring {
                            damping: 1
                            epsilon: 0.001
                            spring: 13
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#f8ffffff"
                    font.family: "SF Pro Display"
                    font.letterSpacing: -2.5 * surface.uiScale
                    font.pixelSize: Math.round((surface.compactLayout ? 70 : 92) * surface.uiScale)
                    font.weight: Font.Bold
                    renderType: Text.NativeRendering
                    text: Qt.formatDateTime(surface.controller.currentDate, "HH:mm:ss")
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#e8ffffff"
                    font.family: "SF Pro Display"
                    font.letterSpacing: 0.05
                    font.pixelSize: Math.round(16 * surface.uiScale)
                    font.weight: Font.Medium
                    renderType: Text.NativeRendering
                    text: surface.controller.currentDate.toLocaleDateString(Qt.locale("en_US"), "dddd, d MMM")
                }
            }

            // Fixed, non-scrolling widget canvas. It is anchored strictly
            // between the clock/date stack and the permanently reserved media
            // area. Even malformed saved geometry cannot cross either bound:
            // WidgetsService validates every row and this item clips as a
            // final rendering guard.
            Item {
                id: lockWidgetGrid

                readonly property real cellHeight: WidgetsService.gridCell * layoutScale
                readonly property real cellWidth: cellHeight
                readonly property int columns: WidgetsService.lockGridColumns
                readonly property real designHeight: rows * WidgetsService.gridCell + (rows - 1) * WidgetsService.gridGap
                readonly property real designWidth: columns * WidgetsService.gridCell + (columns - 1) * WidgetsService.gridGap
                readonly property real gap: WidgetsService.gridGap * layoutScale
                readonly property real gridHeight: designHeight * layoutScale
                readonly property real gridWidth: designWidth * layoutScale
                readonly property real layoutScale: Math.max(0.01, Math.min(width / designWidth, height / designHeight))
                readonly property real originX: (width - gridWidth) / 2
                readonly property real originY: (height - gridHeight) / 2
                readonly property int rows: WidgetsService.lockGridRows
                readonly property real unitX: cellWidth + gap
                readonly property real unitY: cellHeight + gap

                anchors.bottom: parent.bottom
                anchors.bottomMargin: 202 + (42 + 28) * surface.uiScale
                anchors.left: parent.left
                anchors.leftMargin: 36 * surface.uiScale
                anchors.right: parent.right
                anchors.rightMargin: 36 * surface.uiScale
                anchors.top: clockStack.bottom
                anchors.topMargin: 28 * surface.uiScale
                clip: true
                opacity: visible ? 1 : 0
                visible: !surface.compactLayout && surface.contentShown && WidgetsService.lockWidgets.count > 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: 260
                        easing.type: Easing.OutCubic
                    }
                }

                Repeater {
                    model: WidgetsService.lockWidgets

                    delegate: WidgetPreviewFrame {
                        required property int column
                        required property int columns
                        required property int row
                        required property int rows

                        contentActive: surface.contentShown && !surface.controller.sleepPreparing
                        cornerRadius: 13 * surface.uiScale
                        height: rows * lockWidgetGrid.cellHeight + (rows - 1) * lockWidgetGrid.gap
                        liveLockInteraction: surface.controller.secure && surface.controller.locked && !surface.controller.sleepPreparing && !surface.controller.unlockRequested
                        width: columns * lockWidgetGrid.cellWidth + (columns - 1) * lockWidgetGrid.gap
                        x: lockWidgetGrid.originX + column * lockWidgetGrid.unitX
                        y: lockWidgetGrid.originY + row * lockWidgetGrid.unitY

                        onInputFinished: surface.restorePasswordFocus()
                    }
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.ArrowCursor
                enabled: surface.mediaIslandOpen
                visible: enabled
                z: 31

                onClicked: {
                    surface.mediaIslandOpen = false;
                    surface.restorePasswordFocus();
                }
            }
            LockMediaPill {
                id: mediaPill

                anchors.bottom: parent.bottom
                anchors.bottomMargin: 42 * surface.uiScale
                anchors.horizontalCenter: parent.horizontalCenter
                equalizer: surface.equalizer
                media: surface.media
                preferredWidth: Math.max(300, Math.min(520, leftPanel.width - 72 * surface.uiScale))
                shown: WidgetsService.lockMediaEnabled && surface.media.hasMedia && surface.contentShown && !surface.mediaIslandOpen
                z: 32

                onActivated: {
                    surface.mediaIslandOpen = true;
                    surface.restorePasswordFocus();
                }
            }
            LockMediaIsland {
                id: mediaCard

                anchors.bottom: parent.bottom
                anchors.bottomMargin: 42 * surface.uiScale
                anchors.horizontalCenter: parent.horizontalCenter
                equalizer: surface.equalizer
                media: surface.media
                preferredWidth: Math.max(430, Math.min(720, leftPanel.width - 72 * surface.uiScale))
                shown: WidgetsService.lockMediaEnabled && surface.media.hasMedia && surface.contentShown && surface.mediaIslandOpen
                z: 32
            }
        }
        Item {
            id: authArea

            height: surface.height
            width: surface.compactLayout ? surface.width - surface.edgeInset * 2 : surface.width - x
            x: surface.compactLayout ? surface.edgeInset : leftPanel.x + leftPanel.width

            Column {
                id: authStack

                opacity: surface.contentShown ? 1 : 0
                width: Math.max(260, Math.min(430 * surface.uiScale, authArea.width - 72 * surface.uiScale))
                x: (authArea.width - width) / 2
                y: (authArea.height - height) / 2

                Behavior on opacity {
                    NumberAnimation {
                        duration: 340
                        easing.type: Easing.OutCubic
                    }
                }
                transform: Translate {
                    y: surface.contentShown ? 0 : 10 * surface.uiScale

                    Behavior on y {
                        LockSpring {
                            damping: 1
                            epsilon: 0.001
                            spring: 13
                        }
                    }
                }

                Rectangle {
                    id: inputShadow

                    color: "#30000000"
                    height: 58 * surface.uiScale
                    radius: height / 2
                    width: authStack.width

                    transform: Translate {
                        id: inputShake

                        x: 0
                    }

                    SequentialAnimation {
                        id: inputShakeAnimation

                        NumberAnimation {
                            duration: 42
                            easing.type: Easing.OutQuad
                            property: "x"
                            target: inputShake
                            to: -5 * surface.uiScale
                        }
                        NumberAnimation {
                            duration: 72
                            easing.type: Easing.InOutQuad
                            property: "x"
                            target: inputShake
                            to: 5 * surface.uiScale
                        }
                        NumberAnimation {
                            duration: 62
                            easing.type: Easing.InOutQuad
                            property: "x"
                            target: inputShake
                            to: -3 * surface.uiScale
                        }
                        NumberAnimation {
                            duration: 52
                            easing.type: Easing.InOutQuad
                            property: "x"
                            target: inputShake
                            to: 2 * surface.uiScale
                        }
                        NumberAnimation {
                            duration: 46
                            easing.type: Easing.OutQuad
                            property: "x"
                            target: inputShake
                            to: 0
                        }
                    }
                    Rectangle {
                        id: inputShell

                        anchors.bottomMargin: 3 * surface.uiScale
                        anchors.fill: parent
                        border.color: surface.controller.displayStatusIsError ? "#d45e67" : (passwordInput.activeFocus && surface.controller.authReady ? "#8e8e93" : "#60ffffff")
                        border.width: passwordInput.activeFocus && surface.controller.authReady ? 2 : 1
                        color: "#f5f5f5"
                        radius: height / 2
                        scale: submitTap.pressed ? 0.992 : 1

                        Behavior on scale {
                            LockSpring {
                                spring: 22
                            }
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 22 * surface.uiScale
                            anchors.verticalCenter: parent.verticalCenter
                            color: surface.controller.displayStatusIsError ? "#b4434d" : "#7d7d82"
                            font.family: "SF Pro Display"
                            font.pixelSize: Math.round(14 * surface.uiScale)
                            font.weight: Font.Normal
                            text: surface.controller.displayStatusIsError ? surface.controller.displayStatusText : qsTr("Enter password")
                            visible: surface.verificationMask === "" && passwordInput.text.length === 0
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 22 * surface.uiScale
                            anchors.right: submitButton.left
                            anchors.rightMargin: 12 * surface.uiScale
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 2 * surface.uiScale
                            clip: true
                            color: "#17171a"
                            elide: Text.ElideRight
                            font.family: "SF Pro Display"
                            font.pixelSize: Math.round(17 * surface.uiScale)
                            font.weight: Font.Medium
                            text: surface.verificationMask
                            visible: surface.verificationMask !== ""
                        }
                        TextInput {
                            id: passwordInput

                            activeFocusOnTab: false
                            anchors.left: parent.left
                            anchors.leftMargin: 22 * surface.uiScale
                            anchors.right: submitButton.left
                            anchors.rightMargin: 12 * surface.uiScale
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 2 * surface.uiScale
                            clip: true
                            color: "#17171a"
                            echoMode: TextInput.Password
                            enabled: surface.controller.authReady && !surface.controller.verificationInProgress
                            font.family: "SF Pro Display"
                            font.pixelSize: Math.round(17 * surface.uiScale)
                            font.weight: Font.Medium
                            height: 32 * surface.uiScale
                            inputMethodHints: Qt.ImhHiddenText | Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhPreferLatin
                            maximumLength: 512
                            passwordCharacter: "●"
                            passwordMaskDelay: 0
                            persistentSelection: false
                            selectByMouse: false
                            selectedTextColor: color
                            selectionColor: "transparent"
                            verticalAlignment: TextInput.AlignVCenter

                            Component.onCompleted: {
                                if (surface.controller.authReady)
                                    Qt.callLater(() => passwordInput.forceActiveFocus());
                            }
                            Keys.onPressed: event => {
                                const clipboardCombo = (event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_C || event.key === Qt.Key_X || event.key === Qt.Key_V);
                                const primaryPaste = (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_Insert;
                                if (clipboardCombo || primaryPaste) {
                                    event.accepted = true;
                                }
                            }
                            Keys.onShortcutOverride: event => {
                                if (event.matches(StandardKey.Copy) || event.matches(StandardKey.Cut) || event.matches(StandardKey.Paste)) {
                                    event.accepted = true;
                                }
                            }
                            onAccepted: surface.submitAttempt()
                            onTextEdited: surface.controller.dismissTransientStatus()
                        }

                        // Consume pointer selection and all X/primary clipboard
                        // paste paths while still allowing the field to focus.
                        MouseArea {
                            acceptedButtons: Qt.AllButtons
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: submitButton.left
                            anchors.top: parent.top
                            cursorShape: Qt.IBeamCursor
                            enabled: !surface.controller.verificationInProgress

                            onPressed: event => {
                                event.accepted = true;
                                if (surface.controller.authReady && !surface.controller.verificationInProgress) {
                                    passwordInput.forceActiveFocus();
                                }
                            }
                        }
                        Rectangle {
                            id: submitButton

                            anchors.right: parent.right
                            anchors.rightMargin: 8 * surface.uiScale
                            anchors.verticalCenter: parent.verticalCenter
                            color: surface.controller.authReady && !surface.controller.verificationInProgress && passwordInput.text.length > 0 ? "#202024" : "#c9c9cd"
                            height: width
                            radius: width / 2
                            scale: submitTap.pressed ? 0.9 : 1
                            width: 40 * surface.uiScale

                            Behavior on color {
                                ColorAnimation {
                                    duration: 100
                                }
                            }
                            Behavior on scale {
                                LockSpring {
                                    spring: 22
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -1
                                color: "#ffffff"
                                font.family: "SF Pro Display"
                                font.pixelSize: Math.round(20 * surface.uiScale)
                                font.weight: Font.DemiBold
                                text: "→"
                            }
                            TapHandler {
                                id: submitTap

                                acceptedButtons: Qt.LeftButton
                                enabled: surface.controller.authReady && !surface.controller.verificationInProgress && passwordInput.text.length > 0

                                onTapped: surface.submitAttempt()
                            }
                            HoverHandler {
                                cursorShape: surface.controller.authReady && !surface.controller.verificationInProgress && passwordInput.text.length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            }
                        }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: parent.bottom
                        anchors.topMargin: 8 * surface.uiScale
                        color: "#f0a2a9"
                        elide: Text.ElideRight
                        font.family: "SF Pro Display"
                        font.pixelSize: Math.round(12 * surface.uiScale)
                        font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter
                        opacity: visible ? 1 : 0
                        text: surface.controller.transientStatusText
                        textFormat: Text.PlainText
                        visible: surface.controller.transientStatusText !== "" && surface.controller.transientStatusIsError
                        width: parent.width - 24 * surface.uiScale

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 120
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                }
            }
            Column {
                id: accountStack

                anchors.bottom: parent.bottom
                anchors.bottomMargin: 38 * surface.uiScale
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: surface.contentShown ? 1 : 0
                spacing: 8 * surface.uiScale

                Behavior on opacity {
                    NumberAnimation {
                        duration: 340
                        easing.type: Easing.OutCubic
                    }
                }
                transform: Translate {
                    y: surface.contentShown ? 0 : 8 * surface.uiScale

                    Behavior on y {
                        LockSpring {
                            damping: 1
                            epsilon: 0.001
                            spring: 13
                        }
                    }
                }

                ClippingRectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    border.color: "#66ffffff"
                    border.width: 1
                    color: "#2b1b1b1e"
                    height: width
                    radius: width / 2
                    width: 48 * surface.uiScale

                    Image {
                        id: accountAvatar

                        anchors.fill: parent
                        // Overscan beneath the circular clip. Leaving an inset here
                        // exposed the dark fallback as a thin ring around otherwise
                        // square avatars, especially at fractional output scales.
                        anchors.margins: -1 * surface.uiScale
                        asynchronous: true
                        cache: true
                        fillMode: Image.PreserveAspectCrop
                        mipmap: true
                        source: surface.avatarSource
                        sourceSize.height: Math.round(96 * surface.uiScale)
                        sourceSize.width: Math.round(96 * surface.uiScale)
                        smooth: true
                    }
                    Text {
                        anchors.centerIn: parent
                        color: "#e8ffffff"
                        font.family: "SF Pro Display"
                        font.pixelSize: Math.round(13 * surface.uiScale)
                        text: "●"
                        visible: accountAvatar.status !== Image.Ready
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: "#e8ffffff"
                    font.family: "SF Pro Display"
                    font.pixelSize: Math.round(12 * surface.uiScale)
                    font.weight: Font.Medium
                    text: surface.controller.displayUser
                    textFormat: Text.PlainText
                }
            }
        }
    }
    Connections {
        function onHasMediaChanged() {
            if (!surface.media.hasMedia)
                surface.mediaIslandOpen = false;
        }

        target: surface.media
    }
    Connections {
        function onLockMediaEnabledChanged() {
            if (!WidgetsService.lockMediaEnabled)
                surface.mediaIslandOpen = false;
        }

        target: WidgetsService
    }
    Connections {
        function onClearRevisionChanged() {
            passwordInput.clear();
        }
        function onAuthReadyChanged() {
            passwordInput.clear();
            if (surface.controller.authReady) {
                surface.verificationMask = "";
                surface.restorePasswordFocus();
            }
        }
        function onSecureChanged() {
            if (!surface.controller.secure)
                surface.verificationMask = "";
        }
        function onShakeRevisionChanged() {
            inputShakeAnimation.stop();
            inputShake.x = 0;
            inputShakeAnimation.start();
        }
        function onSleepPreparingChanged() {
            if (surface.controller.sleepPreparing)
                surface.verificationMask = "";
        }

        target: surface.controller
    }
}
