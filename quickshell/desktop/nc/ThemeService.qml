pragma Singleton
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    property bool isDark: true

    // Single source of truth for the GTK theme paired with each color scheme.
    readonly property string lightTheme: "MacTahoe-Light"
    readonly property string darkTheme: "MacTahoe-Dark"

    // Theme switching lives here now (replaces scripts/toggle-theme.sh). Every
    // Quickshell component watches color-scheme via the monitor below and
    // re-themes itself automatically once it flips.
    function setLight() {
        Quickshell.execDetached(["bash", "-c",
            "gsettings set org.gnome.desktop.interface gtk-theme '" + root.lightTheme + "'; " +
            "gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'"])
    }
    function setDark() {
        Quickshell.execDetached(["bash", "-c",
            "gsettings set org.gnome.desktop.interface gtk-theme '" + root.darkTheme + "'; " +
            "gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'"])
    }
    function toggle() {
        if (root.isDark) root.setLight()
        else root.setDark()
    }

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
