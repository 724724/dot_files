import QtQuick

Rectangle {
    id: panel
    default property alias contentItem: inner.data
    property real contentPadding: 14
    readonly property bool dark: ThemeService.isDark

    radius: 14
    color: ThemeService.tileBg
    border.color: ThemeService.tileStroke
    border.width: 1

    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: panel.contentPadding
    }
}
