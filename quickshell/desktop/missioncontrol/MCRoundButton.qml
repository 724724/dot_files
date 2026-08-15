import QtQuick

// Small circular control (× / exit-fullscreen) shown on a workspace tile on hover.
Rectangle {
    id: btn
    property string glyph: ""
    signal clicked()

    width: 22; height: 22; radius: 11
    color: ma.containsMouse ? "#ff5b54" : Qt.rgba(0, 0, 0, 0.72)
    border.color: Qt.rgba(1, 1, 1, 0.75)
    border.width: 1
    scale: ma.pressed ? ThemeService.pressScale : 1.0
    Behavior on scale { AppleSpring { spring: 4.4 } }

    Text {
        anchors.centerIn: parent
        text: btn.glyph
        color: "#ffffff"
        font.family: "JetBrainsMono Nerd Font Propo"
        font.pixelSize: 13
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
