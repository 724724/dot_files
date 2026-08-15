pragma Singleton
import Quickshell
import QtQuick

Singleton {
    property bool popupOpen: false
    property real popupAnchorX: 0
    property var popupScreen: null
}
