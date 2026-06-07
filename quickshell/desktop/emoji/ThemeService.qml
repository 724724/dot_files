pragma Singleton
import Quickshell
import Quickshell.Io

// Tracks the GNOME colour-scheme so the emoji popup can match light/dark like
// the rest of the shell. (Self-contained copy of the per-module ThemeService
// pattern used by spotlight/launchpad/switcher.)
Singleton {
    id: root
    property bool isDark: true

    Process {
        command: ["bash", "-c", "gsettings get org.gnome.desktop.interface color-scheme"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: root.isDark = text.trim().includes("dark")
        }
    }

    Process {
        command: ["gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.includes("color-scheme"))
                    root.isDark = data.includes("dark")
            }
        }
    }
}
