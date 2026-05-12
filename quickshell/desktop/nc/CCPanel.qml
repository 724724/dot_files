import QtQuick

Rectangle {
    id: panel
    default property alias contentItem: inner.data
    property real contentPadding: 14
    readonly property bool dark: ThemeService.isDark

    radius: 14
    color: dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(1, 1, 1, 0.62)
    border.color: dark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.05)
    border.width: 1

    Behavior on color { ColorAnimation { duration: 200 } }

    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: panel.contentPadding
    }
}
