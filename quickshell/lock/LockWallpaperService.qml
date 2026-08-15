import Quickshell
import Quickshell.Io
import QtQuick

// One-shot, read-only wallpaper discovery for the standalone lock process.
// The opaque WlSessionLockSurface remains the first frame and security layer;
// this path only decorates it once the current local image is available.
Scope {
    id: root

    property string current: ""
    property var snapshots: []
    readonly property string runtimeRoot: {
        const supplied = String(Quickshell.env("RUNTIME_DIRECTORY") || "")
        const expected = String(Quickshell.env("XDG_RUNTIME_DIR") || "")
            + "/quickshell-lock"
        return supplied !== "" && supplied === expected ? supplied : ""
    }
    readonly property string snapshotRoot: runtimeRoot === ""
        ? "" : runtimeRoot + "/snapshot"

    function snapshotFor(outputName) {
        const exactName = String(outputName || "")
        for (let i = 0; i < root.snapshots.length; i++) {
            const entry = root.snapshots[i]
            if (entry.name === exactName)
                return entry.url
        }
        return ""
    }

    function fromUri(uri) {
        let value = String(uri || "").trim().replace(/^'|'$/g, "")
        if (value.startsWith("file://"))
            value = value.substring(7)
        try {
            value = decodeURIComponent(value)
        } catch (error) {}
        return value === "/" ? "" : value
    }

    function refresh() {
        if (!awwwQuery.running)
            awwwQuery.running = true
    }

    FileView {
        id: snapshotManifest
        path: root.snapshotRoot === ""
            ? "" : root.snapshotRoot + "/manifest.json"
        watchChanges: true
        printErrors: false

        onFileChanged: reload()

        onLoaded: {
            try {
                const manifest = JSON.parse(text())
                if (manifest.version !== 1 || !Array.isArray(manifest.outputs)) {
                    root.snapshots = []
                    return
                }

                const validated = []
                for (let i = 0; i < manifest.outputs.length; i++) {
                    const entry = manifest.outputs[i]
                    const name = String(entry.name || "")
                    const file = String(entry.file || "")
                    if (!/^[A-Za-z0-9._-]{1,64}$/.test(name)
                            || !/^output-[0-9]+\.jpg$/.test(file)) {
                        continue
                    }
                    validated.push({
                        name: name,
                        url: "file://" + root.snapshotRoot + "/" + file
                    })
                }
                root.snapshots = validated
            } catch (error) {
                root.snapshots = []
            }
        }

        onLoadFailed: root.snapshots = []
    }

    Process {
        id: awwwQuery
        command: ["/usr/bin/awww", "query"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/image:\s*(.+)$/m)
                const path = match ? match[1].trim() : ""
                if (path !== "" && path !== "/")
                    root.current = path
                if (root.current === "" && !darkPicture.running)
                    darkPicture.running = true
            }
        }
    }

    Process {
        id: darkPicture
        command: ["/usr/bin/gsettings", "get",
                  "org.gnome.desktop.background", "picture-uri-dark"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = root.fromUri(text)
                if (path !== "")
                    root.current = path
                if (root.current === "" && !lightPicture.running)
                    lightPicture.running = true
            }
        }
    }

    Process {
        id: lightPicture
        command: ["/usr/bin/gsettings", "get",
                  "org.gnome.desktop.background", "picture-uri"]
        stdout: StdioCollector {
            onStreamFinished: {
                const path = root.fromUri(text)
                if (path !== "")
                    root.current = path
            }
        }
    }
}
