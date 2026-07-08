pragma Singleton
import Quickshell
import QtQuick
import "../nc" as Nc

// Thin proxy over nc/AudioService — the bar and control center share one qs
// process, so keeping a second `pactl subscribe` + its own refresh pipeline
// here just doubled every audio event's process spawns. The widget keeps its
// VolumeService API; the data comes from the single shared subscription.
Singleton {
    id: root
    readonly property int vol: Nc.AudioService.vol
    readonly property bool muted: Nc.AudioService.muted

    function refresh() { Nc.AudioService.refresh() }
}
