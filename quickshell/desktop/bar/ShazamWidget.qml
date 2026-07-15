import QtQuick
import Quickshell

// Round Shazam button living inside the tray pill, just right of RunCat.
//   • Left-click  → toggle the Music Recognition history popup (drops down
//                   centred under this icon).
//   • Right-click → recognize immediately in the background (no popup).
// It pulses while a recognition is in flight.
Item {
    id: root
    property var screen: null

    implicitWidth: 22
    implicitHeight: 33

    readonly property bool active: ShazamService.popupVisible
    readonly property bool pressed: leftTap.pressed || rightTap.pressed

    // Report this icon's screen-space centre to the service so the popup can
    // drop down centred under it. The bar window is inset from the screen's
    // left edge by its margin (Bar.qml margins.left), while the popup overlay
    // starts at the screen edge, so add that inset.
    readonly property int barLeftMargin: 10
    function updateAnchor() {
        let w = root.QsWindow.window
        if (!w) return
        let p = w.contentItem.mapFromItem(root, root.width / 2, 0)
        ShazamService.anchorX = p.x + barLeftMargin
    }

    // Hover / active backdrop ring.
    Rectangle {
        anchors.centerIn: parent
        width: 22; height: 22; radius: 11
        color: (hover.hovered || root.active)
            ? (ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.10))
            : "transparent"
        scale: root.pressed ? ThemeService.pressScale : 1
        Behavior on scale { AppleSpring { spring: 13 } }
    }

    Image {
        id: logo
        anchors.centerIn: parent
        width: 18; height: 18
        sourceSize.width: 36; sourceSize.height: 36
        smooth: true
        mipmap: true
        fillMode: Image.PreserveAspectFit
        source: ShazamService.iconUrl
        opacity: ShazamService.recognizing ? 0.58 : 1
        scale: root.pressed ? ThemeService.pressScale : 1
        Behavior on opacity { AppleSpring { spring: 7 } }
        Behavior on scale { AppleSpring { spring: 13 } }
    }

    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }

    TapHandler {
        id: leftTap
        acceptedButtons: Qt.LeftButton
        onTapped: {
            root.updateAnchor()
            ShazamService.targetScreen = root.screen
            ShazamService.popupVisible = !ShazamService.popupVisible
        }
    }
    TapHandler {
        id: rightTap
        acceptedButtons: Qt.RightButton
        onTapped: {
            // Recognize straight away, in the background — close the popup if
            // it happened to be open so a notification is what reports the result.
            if (ShazamService.popupVisible) ShazamService.popupVisible = false
            ShazamService.recognize()
        }
    }
}
