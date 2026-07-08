import QtQuick
import Qt5Compat.GraphicalEffects
import "../nc" as Nc

// RunCat: a little animation that runs faster the busier the CPU is. Lives inside
// the tray pill. The chosen asset set comes from the Usage panel; frames are
// tinted to the bar foreground so silhouette art reads in either theme.
Item {
    id: root
    visible: Nc.SysUsageService.runcatEnabled
    implicitWidth: visible ? 22 : 0
    implicitHeight: 33

    readonly property var frames: Nc.SysUsageService.runcatFrames
    readonly property int frameCount: frames ? frames.length : 0
    property int frame: 0

    readonly property string currentFile: frameCount > 0 ? frames[frame % frameCount] : ""
    readonly property string frameUrl: currentFile === "" ? ""
        : Nc.SysUsageService.assetsUrl + "/" + Nc.SysUsageService.runcatSet + "/" + currentFile
    readonly property bool isGif: frameCount === 1 && currentFile.toLowerCase().endsWith(".gif")
    // Colourful sets are shown as-is; silhouettes get tinted to the bar fg.
    readonly property bool colored: Nc.SysUsageService.runcatColored

    // CPU 0–100% → frame interval (slow when idle, fast when busy). Power
    // curve so mid loads already look lively, with a ~24ms floor at 100% —
    // matching macOS RunCat's full-tilt pace (5-frame cat: ~8 run cycles/sec
    // at full load, ~0.7 at idle). The old linear map bottomed out at 70ms,
    // which read as a lazy jog even with the CPU pinned.
    readonly property real cpu: Nc.SysUsageService.cpu
    readonly property int frameInterval:
        Math.round(24 + 276 * Math.pow(1 - cpu / 100, 1.35))

    Image {
        id: frameImg
        anchors.centerIn: parent
        width: 20; height: 18
        sourceSize.width: 40; sourceSize.height: 36
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: !root.isGif && root.colored   // colourful → shown directly
        source: root.isGif ? "" : root.frameUrl
    }
    AnimatedImage {
        id: gifImg
        anchors.centerIn: parent
        width: 20; height: 18
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: root.isGif && root.colored
        playing: root.isGif && root.visible
        speed: 0.5 + root.cpu / 100 * 3.0
        source: root.isGif ? root.frameUrl : ""
    }
    // Tint silhouette frames to the bar foreground (theme-adaptive).
    ColorOverlay {
        anchors.fill: frameImg
        source: root.isGif ? gifImg : frameImg
        color: ThemeService.fg
        visible: !root.colored
    }

    Timer {
        interval: root.frameInterval
        running: root.visible && root.frameCount > 1
        repeat: true
        onTriggered: root.frame = (root.frame + 1) % root.frameCount
    }
}
