pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// System usage metrics + the RunCat toggle. Lives in nc/ but is shared with the
// bar's RunCatWidget (imported as Nc.SysUsageService). CPU is polled whenever
// RunCat is on OR the Usage panel is open; the heavier stats (GPU via nvidia-smi,
// memory/disk/network) only while the Usage panel is open.
Singleton {
    id: root

    // ── live metrics ─────────────────────────────────────────────────────────
    property real cpu: 0           // %

    // Intel iGPU — only surfaced when it uses the i915 driver (which
    // intel_gpu_top can read). The xe driver has no root-free utilization API,
    // so on xe the card is hidden entirely; switch to i915 and it appears.
    property string igpuDriver: ""                 // "i915" | "xe" | ""
    readonly property bool igpuAvailable: igpuDriver === "i915"
    property real igpu: 0          // % (i915 via intel_gpu_top)
    property string igpuName: ""

    // NVIDIA dGPU (nvidia-smi).
    property real dgpu: 0          // %
    property real dgpuMemUsed: 0   // MiB
    property real dgpuMemTotal: 0  // MiB
    property real dgpuTemp: 0      // °C
    property string dgpuName: ""

    property real memUsed: 0       // bytes
    property real memTotal: 0      // bytes
    property real diskUsed: 0      // bytes
    property real diskTotal: 0     // bytes
    property real netDown: 0       // bytes/s
    property real netUp: 0         // bytes/s

    readonly property real memPct:  memTotal  > 0 ? memUsed  / memTotal  * 100 : 0
    readonly property real diskPct: diskTotal > 0 ? diskUsed / diskTotal * 100 : 0

    // ── runcat toggle (persisted, shared with the bar) ───────────────────────
    property bool runcatEnabled: false
    property bool detailActive: false   // Usage panel open → poll heavy stats

    function toggleRuncat() { setRuncat(!root.runcatEnabled) }
    function setRuncat(v) {
        root.runcatEnabled = v
        runcatStore.setText(v ? "1" : "0")
    }

    // ── runcat asset sets ────────────────────────────────────────────────────
    // Each subfolder of quickshell/assets/runcat/ is a set; its image files
    // (sorted naturally) are the animation frames. We use a real absolute path
    // (NOT Qt.resolvedUrl, which Quickshell maps to a virtual qrc:/qs-blackhole
    // path that breaks shell commands).
    readonly property string _configDir: {
        let x = Quickshell.env("XDG_CONFIG_HOME")
        return (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config")
    }
    readonly property string assetsPath: _configDir + "/quickshell/assets/runcat"
    readonly property string assetsUrl: "file://" + assetsPath
    readonly property string scanScript: _configDir + "/quickshell/assets/runcat-scan.py"
    property var runcatSetNames: []          // ["cat","horse",…]
    property var runcatFramesMap: ({})        // name → ["0.png",…]
    property var runcatColoredMap: ({})       // name → bool (true = show as-is)
    property string runcatSet: "cat"          // selected set (persisted)
    readonly property var runcatFrames: runcatFramesMap[runcatSet] || []
    readonly property bool runcatColored: !!runcatColoredMap[runcatSet]

    // Built-in sets ship with the config and can't be removed; anything else is
    // user-added (removable from the picker).
    readonly property var builtinSets: ["cat", "horse"]
    function isBuiltin(name) { return builtinSets.indexOf(name) !== -1 }

    function setRuncatSet(name) {
        root.runcatSet = name
        runcatSetStore.setText(name)
    }
    function rescanSets() { scanProc.running = true }
    function removeSet(name) {
        if (isBuiltin(name)) return                  // never delete a built-in
        rmProc.command = ["rm", "-rf", root.assetsPath + "/" + name]
        rmProc.running = true
        if (root.runcatSet === name) root.setRuncatSet("cat")
    }
    Process { id: rmProc; command: ["true"]; onRunningChanged: if (!running) root.rescanSets() }

    // ── device info (model names) ────────────────────────────────────────────
    // Persisted to disk (sysusage-info.json) so the panel renders instantly on
    // open; a background re-query runs once per session and rewrites the cache
    // only if the hardware actually changed.
    property string cpuModel: ""
    property string diskInfo: ""
    property string netInterface: ""
    property bool _infoChecked: false

    // ── per-detail data, polled only while that row is expanded ─────────────
    // Which metric row is expanded in the Usage panel ("" = none). Drives all
    // the detail pollers below so nothing runs for collapsed rows.
    property string expandedDetail: ""

    property var coreUsages: []        // per-core % (CPU row)
    property var _prevCoreTot: []
    property var _prevCoreIdle: []

    property real dgpuPower: 0         // W
    property real dgpuClock: 0         // MHz (graphics)
    property string dgpuPState: ""     // P0..P12
    property var gpuProcs: []          // [{name, mem(MiB)}]

    property var memTop: []            // [{name, bytes}] top-7 by RSS (grouped)

    property var diskTop: []           // [{path, bytes}] largest folders in ~
    property real diskTopTs: 0         // epoch s of last du scan (persisted)
    property bool duScanning: false

    property var netDetail: ({})       // {ip,gw,dns,ssid,signal,rate,rx,tx}

    onExpandedDetailChanged: {
        // Kick an immediate sample so the freshly expanded row fills right away;
        // the matching Timer below keeps it updated afterwards.
        if (expandedDetail === "cpu") statView.reload()
        else if (expandedDetail === "mem" && !memTopProc.running) memTopProc.running = true
        else if (expandedDetail === "gpu" && !gpuDetailProc.running) gpuDetailProc.running = true
        else if (expandedDetail === "net" && !netDetailProc.running) netDetailProc.running = true
        else if (expandedDetail === "disk") refreshDiskTop(false)
    }

    // ── add a RunCat style by picking a folder (validated). The Usage panel
    //    listens to addResult to refresh or show an error. ─────────────────────
    signal addResult(bool ok, string message)
    function addSet() {
        addProc.command = ["bash", "-c",
            "sel=$(zenity --file-selection --directory --title='Add RunCat style' 2>/dev/null) || exit 0; " +
            "[ -z \"$sel\" ] && exit 0; " +
            "name=$(basename \"$sel\"); " +
            "p=$(find \"$sel\" -maxdepth 1 -type f -iname '*.png' | wc -l); " +
            "s=$(find \"$sel\" -maxdepth 1 -type f -iname '*.svg' | wc -l); " +
            "g=$(find \"$sel\" -maxdepth 1 -type f -iname '*.gif' | wc -l); " +
            "o=$(find \"$sel\" -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' -o -iname '*.bmp' \\) | wc -l); " +
            "n=0; [ $p -gt 0 ] && n=$((n+1)); [ $s -gt 0 ] && n=$((n+1)); [ $g -gt 0 ] && n=$((n+1)); " +
            "if [ $o -gt 0 ]; then echo 'ERR|Unsupported files found — use only PNG, SVG, or GIF.'; exit 0; fi; " +
            "if [ $n -eq 0 ]; then echo 'ERR|No PNG, SVG, or GIF frames in that folder.'; exit 0; fi; " +
            "if [ $n -gt 1 ]; then echo 'ERR|Mixed file types — use only one of PNG, SVG, or GIF.'; exit 0; fi; " +
            "base='" + root.assetsPath + "'; dest=\"$base/$name\"; rm -rf \"$dest\"; mkdir -p \"$dest\"; " +
            "cp \"$sel\"/*.png \"$sel\"/*.svg \"$sel\"/*.gif \"$dest\"/ 2>/dev/null; " +
            "echo \"OK|$name\""]
        addProc.running = true
    }

    function refresh() {
        statView.reload()
        if (root.detailActive) {
            statsProc.running = true
            gpuProc.running = true
            if (root.igpuAvailable) igpuProc.running = true
            // Model names come from the disk cache; re-verify once per session.
            if (!root._infoChecked) { root._infoChecked = true; infoProc.running = true }
        }
    }

    function fmtBytes(b) {
        if (b >= 1073741824) return (b / 1073741824).toFixed(1) + " GB"
        if (b >= 1048576)    return (b / 1048576).toFixed(0) + " MB"
        if (b >= 1024)       return (b / 1024).toFixed(0) + " KB"
        return Math.round(b) + " B"
    }
    function fmtRate(b) { return fmtBytes(b) + "/s" }

    FileView {
        id: runcatStore
        path: Quickshell.stateDir + "/runcat-enabled.txt"
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: runcatSetStore
        path: Quickshell.stateDir + "/runcat-set.txt"
        blockLoading: true
        printErrors: false
    }
    // Cached hardware info + last du scan, so the panel never opens empty.
    FileView {
        id: infoStore
        path: Quickshell.stateDir + "/sysusage-info.json"
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: duStore
        path: Quickshell.stateDir + "/sysusage-du.json"
        blockLoading: true
        printErrors: false
    }
    Component.onCompleted: {
        root.runcatEnabled = (runcatStore.text().trim() === "1")
        let s = runcatSetStore.text().trim()
        if (s) root.runcatSet = s
        try {
            let d = JSON.parse(infoStore.text())
            root.cpuModel = d.cpu  || ""
            root.igpuName = d.igpu || ""
            root.dgpuName = d.dgpu || ""
            root.diskInfo = d.disk || ""
            root.netInterface = d.net || ""
        } catch (e) {}
        try {
            let d = JSON.parse(duStore.text())
            if (d && d.rows && d.rows.length > 0) {
                root.diskTop = d.rows
                root.diskTopTs = d.ts || 0
            }
        } catch (e) {}
        scanProc.running = true
        driverProc.running = true
    }

    // Which driver backs the Intel GPU (if any): i915 → show it, xe → hide it.
    Process {
        id: driverProc
        command: ["bash", "-c",
            "for c in /sys/class/drm/card[0-9]; do v=$(cat $c/device/vendor 2>/dev/null); " +
            "[ \"$v\" = \"0x8086\" ] || continue; " +
            "basename \"$(readlink -f $c/device/driver 2>/dev/null)\"; break; done"]
        stdout: StdioCollector { onStreamFinished: root.igpuDriver = text.trim() }
    }

    // Intel iGPU utilization via intel_gpu_top (i915 only; needs perf access).
    Process {
        id: igpuProc
        command: ["bash", "-c",
            "timeout 1.6 intel_gpu_top -J -s 1200 2>/dev/null | " +
            "grep -oE '\"busy\":[ ]*[0-9.]+' | " +
            "awk -F: '{if ($2+0 > m) m = $2+0} END {printf \"%d\", m+0.5}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let v = parseInt(text.trim())
                if (!isNaN(v)) root.igpu = Math.max(0, Math.min(100, v))
            }
        }
    }

    // ── Asset-set scan: each subfolder + its (naturally sorted) frames, plus a
    //    colour flag so colourful sets are shown as-is and silhouettes tinted. ──
    Process {
        id: scanProc
        command: ["python3", root.scanScript, root.assetsPath]
        stdout: StdioCollector {
            onStreamFinished: {
                let names = []; let map = ({}); let colored = ({})
                for (let line of text.trim().split("\n")) {
                    if (!line) continue
                    let parts = line.split("|")
                    if (parts.length < 2) continue
                    let frames = parts[1].split(",").filter(x => x.length > 0)
                    if (frames.length === 0) continue
                    names.push(parts[0])
                    map[parts[0]] = frames
                    colored[parts[0]] = (parts[2] === "1")
                }
                // Built-ins first (in declared order), then user sets in scan order.
                let ordered = []
                for (let b of root.builtinSets) if (names.indexOf(b) !== -1) ordered.push(b)
                for (let n of names) if (root.builtinSets.indexOf(n) === -1) ordered.push(n)
                root.runcatSetNames = ordered
                root.runcatFramesMap = map
                root.runcatColoredMap = colored
                if (ordered.length > 0 && ordered.indexOf(root.runcatSet) === -1)
                    root.setRuncatSet(ordered.indexOf("cat") !== -1 ? "cat" : ordered[0])
            }
        }
    }

    // ── Device model names (CPU/GPU/disk/network) ────────────────────────────
    Process {
        id: infoProc
        command: ["bash", "-c",
            "echo \"cpu|$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//') ($(nproc) cores)\"; " +
            "echo \"igpu|$(lspci -nn 2>/dev/null | grep -iE 'VGA|3D|Display' | grep -i intel | head -1 | sed -E 's/.*: //; s/ \\[[0-9a-f]{4}:[0-9a-f]{4}\\].*//; s/Intel Corporation/Intel/')\"; " +
            "echo \"dgpu|$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)\"; " +
            "echo \"disk|$(df --output=source,fstype / 2>/dev/null | tail -1)\"; " +
            "echo \"net|$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')\""]
        stdout: StdioCollector {
            onStreamFinished: {
                for (let line of text.trim().split("\n")) {
                    let i = line.indexOf("|"); if (i < 0) continue
                    let k = line.substring(0, i)
                    let v = line.substring(i + 1).trim()
                    if (k === "cpu") root.cpuModel = v
                    else if (k === "igpu") root.igpuName = v
                    else if (k === "dgpu") root.dgpuName = v
                    else if (k === "disk") {
                        let f = v.split(/\s+/)
                        root.diskInfo = f.length >= 2 ? (f[0] + "  (" + f[1] + ")") : v
                    }
                    else if (k === "net") root.netInterface = v
                }
                // Persist so the next panel open (or session) renders instantly.
                let j = JSON.stringify({ cpu: root.cpuModel, igpu: root.igpuName,
                    dgpu: root.dgpuName, disk: root.diskInfo, net: root.netInterface })
                if (j !== infoStore.text()) infoStore.setText(j)
            }
        }
    }

    // ── CPU (drives RunCat speed + the Usage panel) ──────────────────────────
    // Read /proc/stat in-process via FileView — no `head` fork per sample, so
    // the 1s cadence below is essentially free.
    property real _prevTotal: 0
    property real _prevIdle: 0
    FileView {
        id: statView
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            let lines = text().split("\n")
            let p = lines[0].trim().split(/\s+/)   // cpu user nice system idle iowait …
            if (p.length < 5) return
            let idle = (parseInt(p[4]) || 0) + (parseInt(p[5]) || 0)
            let total = 0
            for (let i = 1; i < p.length; ++i) total += parseInt(p[i]) || 0
            let dt = total - root._prevTotal
            let di = idle - root._prevIdle
            if (root._prevTotal > 0 && dt > 0)
                root.cpu = Math.max(0, Math.min(100, (1 - di / dt) * 100))
            root._prevTotal = total
            root._prevIdle = idle

            // Per-core breakdown — same file, parsed only while the CPU row
            // is expanded, so the RunCat-driven 1s cadence stays as cheap as
            // before.
            if (root.expandedDetail !== "cpu") return
            let us = []
            for (let li of lines) {
                if (!/^cpu[0-9]/.test(li)) continue
                let c = li.trim().split(/\s+/)
                let n = parseInt(c[0].substring(3))
                if (isNaN(n) || c.length < 5) continue
                let cIdle = (parseInt(c[4]) || 0) + (parseInt(c[5]) || 0)
                let cTot = 0
                for (let i = 1; i < c.length; ++i) cTot += parseInt(c[i]) || 0
                let cdt = cTot - (root._prevCoreTot[n] || 0)
                let cdi = cIdle - (root._prevCoreIdle[n] || 0)
                us[n] = (root._prevCoreTot[n] > 0 && cdt > 0)
                    ? Math.max(0, Math.min(100, (1 - cdi / cdt) * 100)) : 0
                root._prevCoreTot[n] = cTot
                root._prevCoreIdle[n] = cIdle
            }
            root.coreUsages = us
        }
    }

    // ── Memory + Disk + Network in one cheap read ────────────────────────────
    property real _prevRx: 0
    property real _prevTx: 0
    property real _prevNetT: 0
    Process {
        id: statsProc
        command: ["bash", "-c",
            "free -b | awk '/^Mem:/{print $2, $3}'; " +
            "df -B1 --output=size,used / | tail -1; " +
            "awk 'NR>2 && $1 !~ /^lo:/ {rx+=$2; tx+=$10} END{print rx+0, tx+0}' /proc/net/dev; " +
            "date +%s%3N"]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = text.trim().split("\n")
                if (lines.length < 4) return
                let mem = lines[0].trim().split(/\s+/)
                root.memTotal = parseFloat(mem[0]) || 0
                root.memUsed  = parseFloat(mem[1]) || 0
                let disk = lines[1].trim().split(/\s+/)
                root.diskTotal = parseFloat(disk[0]) || 0
                root.diskUsed  = parseFloat(disk[1]) || 0
                let net = lines[2].trim().split(/\s+/)
                let rx = parseFloat(net[0]) || 0
                let tx = parseFloat(net[1]) || 0
                let now = (parseFloat(lines[3]) || 0) / 1000
                let dtt = now - root._prevNetT
                if (root._prevNetT > 0 && dtt > 0) {
                    root.netDown = Math.max(0, (rx - root._prevRx) / dtt)
                    root.netUp   = Math.max(0, (tx - root._prevTx) / dtt)
                }
                root._prevRx = rx; root._prevTx = tx; root._prevNetT = now
            }
        }
    }

    // ── GPU (NVIDIA dGPU) — polled only while the Usage panel is open so we
    //    don't keep the discrete GPU awake. ───────────────────────────────────
    Process {
        id: gpuProc
        command: ["bash", "-c",
            "nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu " +
            "--format=csv,noheader,nounits 2>/dev/null | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                let p = text.trim().split(",")
                if (p.length < 4) return
                root.dgpu         = parseFloat(p[0]) || 0
                root.dgpuMemUsed  = parseFloat(p[1]) || 0
                root.dgpuMemTotal = parseFloat(p[2]) || 0
                root.dgpuTemp     = parseFloat(p[3]) || 0
            }
        }
    }

    // ── Detail pollers — each runs ONLY while its row is expanded ────────────

    // RAM: top-7 by RSS, grouped by command name (comm can contain spaces).
    Process {
        id: memTopProc
        command: ["bash", "-c",
            "ps -eo rss=,comm= | awk '{c=$2; for(i=3;i<=NF;i++) c=c\" \"$i; a[c]+=$1} " +
            "END{for(k in a) printf \"%d|%s\\n\", a[k]*1024, k}' | sort -rn | head -7"]
        stdout: StdioCollector {
            onStreamFinished: {
                let rows = []
                for (let line of text.trim().split("\n")) {
                    let i = line.indexOf("|"); if (i < 0) continue
                    rows.push({ bytes: parseFloat(line.substring(0, i)) || 0,
                                name: line.substring(i + 1) })
                }
                if (JSON.stringify(rows) !== JSON.stringify(root.memTop))
                    root.memTop = rows
            }
        }
    }
    Timer {
        interval: 3000; repeat: true
        running: root.detailActive && root.expandedDetail === "mem"
        onTriggered: if (!memTopProc.running) memTopProc.running = true
    }

    // GPU extras: power/clock/P-state + per-process VRAM (pmon shows both
    // compute and graphics clients; fb column is MiB).
    Process {
        id: gpuDetailProc
        command: ["bash", "-c",
            "nvidia-smi --query-gpu=power.draw,clocks.gr,pstate --format=csv,noheader,nounits 2>/dev/null | head -1; " +
            "echo ---; " +
            "nvidia-smi pmon -c 1 -s m 2>/dev/null | " +
            "awk 'NR>2 && $2 ~ /^[0-9]+$/ {cmd=$6; for(i=7;i<=NF;i++) cmd=cmd\" \"$i; " +
            "if (cmd != \"-\" && cmd != \"\") print $4+0 \"|\" cmd}' | sort -rn | head -5"]
        stdout: StdioCollector {
            onStreamFinished: {
                let parts = text.split("---")
                let g = parts[0].trim().split(",")
                if (g.length >= 3) {
                    root.dgpuPower  = parseFloat(g[0]) || 0
                    root.dgpuClock  = parseFloat(g[1]) || 0
                    root.dgpuPState = g[2].trim()
                }
                let rows = []
                if (parts.length > 1) {
                    for (let line of parts[1].trim().split("\n")) {
                        let i = line.indexOf("|"); if (i < 0) continue
                        rows.push({ mem: parseFloat(line.substring(0, i)) || 0,
                                    name: line.substring(i + 1) })
                    }
                }
                if (JSON.stringify(rows) !== JSON.stringify(root.gpuProcs))
                    root.gpuProcs = rows
            }
        }
    }
    Timer {
        interval: 2000; repeat: true
        running: root.detailActive && root.expandedDetail === "gpu"
        onTriggered: if (!gpuDetailProc.running) gpuDetailProc.running = true
    }

    // Disk: largest top-level folders in $HOME (one filesystem). A scan takes
    // seconds, so results are persisted and reused; rescan only when the cache
    // is older than 10 min (or forced from the UI).
    function refreshDiskTop(force) {
        if (duProc.running) return
        let age = Date.now() / 1000 - root.diskTopTs
        if (!force && root.diskTop.length > 0 && age < 600) return
        root.duScanning = true
        duProc.running = true
    }
    Process {
        id: duProc
        command: ["bash", "-c",
            "du -x -B1 -d1 \"$HOME\" 2>/dev/null | sort -rn | " +
            "awk -F'\\t' -v h=\"$HOME\" '$2 != h' | head -7"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.duScanning = false
                let rows = []
                for (let line of text.trim().split("\n")) {
                    let p = line.split("\t")
                    if (p.length < 2) continue
                    rows.push({ bytes: parseFloat(p[0]) || 0, path: p[1] })
                }
                if (rows.length === 0) return
                root.diskTop = rows
                root.diskTopTs = Date.now() / 1000
                duStore.setText(JSON.stringify({ ts: root.diskTopTs, rows: rows }))
            }
        }
    }

    // Network: connection details (IP/gateway/DNS/Wi-Fi link) + totals since
    // boot. All cheap one-shot commands; 5s cadence only while expanded.
    Process {
        id: netDetailProc
        command: ["bash", "-c",
            "IF=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}'); " +
            "echo \"if|$IF\"; " +
            "echo \"ip|$(ip -4 addr show dev \"$IF\" 2>/dev/null | awk '/inet /{print $2; exit}')\"; " +
            "echo \"gw|$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')\"; " +
            "echo \"dns|$(nmcli -t -f IP4.DNS dev show \"$IF\" 2>/dev/null | cut -d: -f2 | paste -sd ', ')\"; " +
            "nmcli -t -f active,ssid,signal,rate dev wifi 2>/dev/null | " +
            "awk -F: '$1==\"yes\"{print \"wifi|\" $2 \"|\" $3 \"|\" $4; exit}'; " +
            "awk -v i=\"$IF:\" '$1==i {print \"tot|\" $2 \"|\" $10}' /proc/net/dev"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {}
                for (let line of text.trim().split("\n")) {
                    let p = line.split("|")
                    if (p[0] === "if")   d.iface = p[1] || ""
                    else if (p[0] === "ip")  d.ip  = p[1] || ""
                    else if (p[0] === "gw")  d.gw  = p[1] || ""
                    else if (p[0] === "dns") d.dns = p[1] || ""
                    else if (p[0] === "wifi") {
                        d.ssid = p[1] || ""; d.signal = p[2] || ""; d.rate = p[3] || ""
                    } else if (p[0] === "tot") {
                        d.rx = parseFloat(p[1]) || 0; d.tx = parseFloat(p[2]) || 0
                    }
                }
                if (JSON.stringify(d) !== JSON.stringify(root.netDetail))
                    root.netDetail = d
            }
        }
    }
    Timer {
        interval: 5000; repeat: true
        running: root.detailActive && root.expandedDetail === "net"
        onTriggered: if (!netDetailProc.running) netDetailProc.running = true
    }

    // ── Add-folder picker + validation (zenity) ──────────────────────────────
    Process {
        id: addProc
        stdout: StdioCollector {
            onStreamFinished: {
                let t = text.trim()
                if (!t) return                       // cancelled
                let i = t.indexOf("|")
                let tag = i >= 0 ? t.substring(0, i) : t
                let msg = i >= 0 ? t.substring(i + 1) : ""
                if (tag === "OK") {
                    root.rescanSets()
                    root.setRuncatSet(msg)
                    root.addResult(true, msg)
                } else {
                    root.addResult(false, msg || "Could not add that folder.")
                }
            }
        }
    }

    // 1s so RunCat's pace tracks load changes promptly. The CPU read is a
    // fork-free FileView reload; the heavier stats still only run with the
    // Usage panel open (refresh() gates them on detailActive).
    Timer {
        interval: 1000
        running: root.runcatEnabled || root.detailActive
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
