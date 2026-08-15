pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Live spectrum for the media pill's EQ meter.
//
// scripts/audio-eq.py captures the default sink's monitor and emits one JSON
// array of band levels (0..1, bass → treble) per frame at ~30fps. Capture runs
// ONLY while something is playing — while paused the meter shows dots, so
// there's no reason to keep parec + an FFT alive.
Singleton {
    id: root

    readonly property int bandCount: 8
    property var levels: []

    readonly property bool active: MediaService.isPlaying && MediaService.hasMedia

    Process {
        id: eqProc
        running: root.active
        // --pdeathsig so the capture dies with the shell instead of lingering.
        command: ["setpriv", "--pdeathsig", "TERM", "--", "python3",
                  Quickshell.env("HOME") + "/.config/quickshell/scripts/audio-eq.py"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (!root.active) return
                try {
                    let arr = JSON.parse(data)
                    if (arr && arr.length > 0) root.levels = arr
                } catch (e) {}
            }
        }
    }

    // Let the bars settle to dots the moment playback stops.
    onActiveChanged: if (!active) levels = []
}
