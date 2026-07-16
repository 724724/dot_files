pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Per-app "screen time" tracker. Linux has no per-app battery accounting like
// iOS, so we approximate usage by sampling the focused Hyprland window every
// `tickSeconds` and crediting that interval to the app's class. Totals are kept
// per calendar day and persist to disk so a quickshell restart doesn't wipe the
// running tally, and so the Screen Time panel can chart a trailing week. There
// is no historical data before this tracker first ran — past days simply read
// as empty until they've been lived through. Suspended/asleep time isn't
// counted because the poll timer doesn't fire while the machine is asleep.
Singleton {
    id: root

    // All tracked days: "YYYY-MM-DD" → { normalizedClass: secondsFocused }.
    property var days: ({})
    // Per-hour breakdown: "YYYY-MM-DD" → { "HH": { normalizedClass: seconds } }.
    // Kept alongside `days` (which stays the day-total source of truth) so the
    // Screen Time panel can chart an hourly detail view. Only populated from when
    // hourly tracking began, so older days have no hourly data.
    property var hours: ({})
    property string day: ""        // YYYY-MM-DD currently being accumulated

    readonly property string dataDir:  Quickshell.env("HOME") + "/.local/share/quickshell"
    readonly property string dataFile: dataDir + "/screentime.json"
    // One focused-window sample per minute is sufficient for daily totals and
    // cuts the bash + hyprctl + jq wakeups and state writes by two thirds.
    readonly property int tickSeconds: 60
    readonly property int keepDays: 35    // drop anything older on load

    // Today's per-app map. Bindings that reference `apps` re-evaluate whenever
    // `days` or `day` change (both observable), so the live tally stays fresh.
    readonly property var apps: root.days[root.day] || ({})

    // Σ of today's seconds (active screen time today).
    readonly property int totalSeconds: {
        let t = 0, m = root.apps
        for (let k in m) t += m[k]
        return t
    }

    // Today's [{ cls, seconds }] sorted descending.
    readonly property var ranked: {
        let arr = []
        let m = root.apps
        for (let k in m) arr.push({ cls: k, seconds: m[k] })
        arr.sort((a, b) => b.seconds - a.seconds)
        return arr
    }

    // ── Per-day queries (used by the Screen Time panel) ──────────────────────
    // Total focused seconds for a given "YYYY-MM-DD".
    function totalFor(dayKey) {
        let m = root.days[dayKey]
        if (!m) return 0
        let t = 0
        for (let k in m) t += m[k]
        return t
    }

    // [{ cls, seconds }] for a given day, sorted descending.
    function rankedFor(dayKey) {
        let arr = []
        let m = root.days[dayKey] || {}
        for (let k in m) arr.push({ cls: k, seconds: m[k] })
        arr.sort((a, b) => b.seconds - a.seconds)
        return arr
    }

    // Per-hour app breakdown for a given day, always 24 entries (0…23):
    //   [{ hour, total, segments: [{ cls, seconds }] sorted desc }]
    // Hours with no tracked data come back with total 0 and no segments.
    function hoursFor(dayKey) {
        let h = root.hours[dayKey] || {}
        let out = []
        for (let i = 0; i < 24; i++) {
            let m = h[String(i).padStart(2, "0")] || {}
            let segs = [], total = 0
            for (let k in m) { segs.push({ cls: k, seconds: m[k] }); total += m[k] }
            segs.sort((a, b) => b.seconds - a.seconds)
            out.push({ hour: i, total: total, segments: segs })
        }
        return out
    }

    // Trailing `n` days ending today, oldest→newest:
    //   [{ key, date, seconds, isToday, dow }]
    // `dow` is the JS day-of-week (0=Sun) for the column letter.
    function lastDays(n) {
        let out = []
        let base = new Date()
        for (let i = n - 1; i >= 0; i--) {
            let d = new Date(base.getFullYear(), base.getMonth(), base.getDate() - i)
            let key = root._dayKey(d)
            out.push({
                key: key,
                date: d,
                seconds: root.totalFor(key),
                isToday: key === root.day,
                dow: d.getDay()
            })
        }
        return out
    }

    // The Sun→Sat calendar week containing `dayKey`, oldest→newest. Same shape as
    // lastDays(); lets the chart flip to whichever week the selected day is in.
    function weekOf(dayKey) {
        let base = root._parse(dayKey)
        let sun = new Date(base.getFullYear(), base.getMonth(), base.getDate() - base.getDay())
        let out = []
        for (let i = 0; i < 7; i++) {
            let d = new Date(sun.getFullYear(), sun.getMonth(), sun.getDate() + i)
            let key = root._dayKey(d)
            out.push({
                key: key,
                date: d,
                seconds: root.totalFor(key),
                isToday: key === root.day,
                dow: d.getDay()
            })
        }
        return out
    }

    // One app's focused seconds on a given day (0 if it saw no use). Drives the
    // app-focus mode of the charts, where a single app is isolated in blue.
    function appSecondsFor(dayKey, cls) {
        let m = root.days[dayKey]
        return (m && m[cls]) ? m[cls] : 0
    }

    // Average daily use of `cls` across the Sun→Sat week containing `dayKey`,
    // taken over the days the app was actually used — mirrors the week chart's
    // average rule, so a single tracked day sits the figure right at that day and
    // it re-settles as more come in. 0 if the app saw no use that week.
    function appWeekAverage(dayKey, cls) {
        let w = root.weekOf(dayKey)
        let t = 0, n = 0
        for (let i = 0; i < w.length; i++) {
            let s = root.appSecondsFor(w[i].key, cls)
            if (s > 0) { t += s; n++ }
        }
        return n > 0 ? Math.round(t / n) : 0
    }

    // `dayKey` shifted by `n` days (may be negative) → new "YYYY-MM-DD".
    function addDays(dayKey, n) {
        let d = root._parse(dayKey)
        return root._dayKey(new Date(d.getFullYear(), d.getMonth(), d.getDate() + n))
    }

    // Days with recorded usage (plus today), newest first: [{ key, seconds }].
    function availableDays() {
        let set = ({})
        set[root.day] = true
        for (let k in root.days) if (root.totalFor(k) > 0) set[k] = true
        let arr = Object.keys(set)
        arr.sort((a, b) => (a < b ? 1 : (a > b ? -1 : 0)))   // ISO keys → desc by date
        return arr.map(k => ({ key: k, seconds: root.totalFor(k) }))
    }

    // Sunday key of the week containing `dayKey`.
    function _sundayKey(dayKey) {
        let d = root._parse(dayKey)
        return root._dayKey(new Date(d.getFullYear(), d.getMonth(), d.getDate() - d.getDay()))
    }

    // Σ seconds across the Sun→Sat week starting at `sundayKey`.
    function weekTotalFor(sundayKey) {
        let w = root.weekOf(sundayKey)
        let t = 0
        for (let i = 0; i < w.length; i++) t += w[i].seconds
        return t
    }

    // Merged app→seconds across the whole Sun→Sat week containing `dayKey`.
    // Drives the week-average view's category colours and app list.
    function weekAppMap(dayKey) {
        let w = root.weekOf(dayKey)
        let out = ({})
        for (let i = 0; i < w.length; i++) {
            let m = root.days[w[i].key] || {}
            for (let c in m) out[c] = (out[c] || 0) + m[c]
        }
        return out
    }

    // Average daily total across the week's days that actually have usage —
    // mirrors the week chart's dashed average line. 0 if the week is empty.
    function weekAverage(dayKey) {
        let w = root.weekOf(dayKey)
        let t = 0, n = 0
        for (let i = 0; i < w.length; i++) {
            if (w[i].seconds > 0) { t += w[i].seconds; n++ }
        }
        return n > 0 ? Math.round(t / n) : 0
    }

    // [{ cls, seconds }] for the whole week containing `dayKey`, sorted desc.
    function rankedWeekApps(dayKey) {
        let m = root.weekAppMap(dayKey)
        let arr = []
        for (let c in m) arr.push({ cls: c, seconds: m[c] })
        arr.sort((a, b) => b.seconds - a.seconds)
        return arr
    }

    // Weeks with recorded usage (plus the current week), newest first, keyed by
    // their Sunday: [{ weekKey, seconds }]. Powers the picker dropdown.
    function availableWeeks() {
        let set = ({})
        set[root._sundayKey(root.day)] = true
        for (let k in root.days) if (root.totalFor(k) > 0) set[root._sundayKey(k)] = true
        let arr = Object.keys(set)
        arr.sort((a, b) => (a < b ? 1 : (a > b ? -1 : 0)))   // ISO keys → desc by date
        return arr.map(sk => ({ weekKey: sk, seconds: root.weekTotalFor(sk) }))
    }

    function fmt(secs) {
        let h = Math.floor(secs / 3600)
        let m = Math.floor((secs % 3600) / 60)
        if (h > 0) return h + "h " + m + "m"
        if (m > 0) return m + "m"
        return secs > 0 ? "<1m" : "0m"
    }

    // Class → icon-theme name (mirrors the switcher's mapping for the few apps
    // whose wmClass doesn't match their themed icon name).
    function iconNameFor(cls) {
        if (!cls) return "application-x-executable"
        let lc = cls.toLowerCase()
        if (lc === "code")    return "visual-studio-code"
        if (lc === "spotify") return "spotify-client"
        if (lc === "kakaotalk.exe") {
            // Wine's .desktop entry only declares its raw hash icon; prefer the
            // themed "KakaoTalk" name (follows the active icon theme), falling
            // back to the hash if the theme doesn't provide it.
            return Quickshell.iconPath("KakaoTalk", true) !== "" ? "KakaoTalk" : "DDB7_KakaoTalk.0"
        }
        return cls
    }

    // Pretty label: reverse-DNS → last segment, dashes/underscores → spaces,
    // Title-Cased. "google-chrome" → "Google Chrome", "org.gnome.Nautilus" →
    // "Nautilus", "code" → "Code".
    function displayName(cls) {
        if (!cls) return ""
        let parts = cls.split(".")
        let base = parts.length >= 3 ? parts[parts.length - 1] : cls
        base = base.replace(/[-_]/g, " ")
        return base.replace(/\b\w/g, c => c.toUpperCase())
    }

    // ── App categories (iOS Screen Time parity) ──────────────────────────────
    // Apple buckets every app into one of these twelve categories. Crucially,
    // the chart colours are NOT fixed per category — Apple colours by *rank*: the
    // most-used category for the day is blue, the 2nd orange, the 3rd teal, and
    // everything else is grey. So `categories` only carries keys + labels; the
    // colours come from `categoryRankColors` once a day's ranking is known.
    readonly property var categories: [
        { key: "social",       label: "Social" },
        { key: "games",        label: "Games" },
        { key: "entertainment",label: "Entertainment" },
        { key: "creativity",   label: "Creativity" },
        { key: "productivity", label: "Productivity & Finance" },
        { key: "education",    label: "Education" },
        { key: "reading",      label: "Information & Reading" },
        { key: "health",       label: "Health & Fitness" },
        { key: "utilities",    label: "Utilities" },
        { key: "shopping",     label: "Shopping & Food" },
        { key: "travel",       label: "Travel" },
        { key: "other",        label: "Other" }
    ]

    // Rank colours: 1st place blue, 2nd orange, 3rd teal (the iOS Screen Time
    // trio); 4th-and-below fall back to a theme-aware grey ("Other" in Apple).
    readonly property var categoryRankColors: ["#007AFF", "#FF9500", "#5AC8FA"]
    readonly property color categoryOtherColor:
        ThemeService.isDark ? Qt.rgba(1, 1, 1, 0.26) : Qt.rgba(0, 0, 0, 0.17)

    // key → label, derived once from `categories`.
    readonly property var _catLabels: {
        let m = ({})
        for (let i = 0; i < root.categories.length; i++) m[root.categories[i].key] = root.categories[i].label
        return m
    }

    // Window-class → category. Mirrors how Apple files each app; unknown apps
    // fall through to "other". Browsers/terminals/JetBrains IDEs/office suites
    // come in too many variants to enumerate, so they're matched by family below.
    readonly property var _catMap: ({
        // Social
        "discord": "social", "vesktop": "social", "webcord": "social", "armcord": "social",
        "telegram": "social", "telegram-desktop": "social", "slack": "social",
        "signal": "social", "whatsapp": "social", "whatsapp-for-linux": "social",
        "ferdium": "social", "franz": "social", "rambox": "social", "element": "social",
        "element-desktop": "social", "schildichat": "social", "kakaotalk": "social",
        "line": "social", "wechat": "social", "skype": "social", "skypeforlinux": "social",
        "teams": "social", "teams-for-linux": "social", "mattermost": "social",
        "zoom": "social", "caprine": "social", "messenger": "social", "pidgin": "social",
        "hexchat": "social", "nheko": "social", "dino": "social", "gajim": "social",
        // Mail → Apple files under Productivity & Finance
        "thunderbird": "productivity", "evolution": "productivity", "geary": "productivity",
        "mailspring": "productivity", "kmail": "productivity",
        // Games
        "steam": "games", "lutris": "games", "heroic": "games", "bottles": "games",
        "minecraft": "games", "minecraft-launcher": "games", "prismlauncher": "games",
        "polymc": "games", "multimc": "games", "retroarch": "games", "dolphin-emu": "games",
        "pcsx2": "games", "rpcs3": "games", "yuzu": "games", "ryujinx": "games", "citra": "games",
        "ppsspp": "games", "duckstation": "games", "supertuxkart": "games", "0ad": "games",
        "openttd": "games", "wesnoth": "games", "osu!": "games", "gamescope": "games",
        "factorio": "games",
        // Entertainment
        "spotify": "entertainment", "spotube": "entertainment", "ncspot": "entertainment",
        "rhythmbox": "entertainment", "clementine": "entertainment", "strawberry": "entertainment",
        "audacious": "entertainment", "lollypop": "entertainment", "elisa": "entertainment",
        "amberol": "entertainment", "vlc": "entertainment", "mpv": "entertainment",
        "smplayer": "entertainment", "celluloid": "entertainment", "totem": "entertainment",
        "haruna": "entertainment", "kodi": "entertainment", "plex": "entertainment",
        "plexmediaplayer": "entertainment", "jellyfin": "entertainment",
        "jellyfinmediaplayer": "entertainment", "stremio": "entertainment",
        "freetube": "entertainment", "tidal-hifi": "entertainment", "deezer": "entertainment",
        // Creativity
        "gimp": "creativity", "inkscape": "creativity", "krita": "creativity",
        "blender": "creativity", "darktable": "creativity", "rawtherapee": "creativity",
        "digikam": "creativity", "kdenlive": "creativity", "shotcut": "creativity",
        "resolve": "creativity", "openshot": "creativity", "flowblade": "creativity",
        "audacity": "creativity", "ardour": "creativity", "lmms": "creativity",
        "reaper": "creativity", "musescore": "creativity", "mscore": "creativity",
        "scribus": "creativity", "figma-linux": "creativity", "penpot": "creativity",
        "obs": "creativity", "com.obsproject.studio": "creativity", "obsproject": "creativity",
        "synfig": "creativity", "pencil2d": "creativity", "natron": "creativity",
        "fontforge": "creativity",
        // Productivity & Finance
        "code": "productivity", "code-oss": "productivity", "vscodium": "productivity",
        "codium": "productivity", "cursor": "productivity", "zed": "productivity",
        "sublime_text": "productivity", "subl": "productivity", "gedit": "productivity",
        "gnome-text-editor": "productivity", "kate": "productivity", "kwrite": "productivity",
        "nvim": "productivity", "neovim": "productivity", "vim": "productivity",
        "gvim": "productivity", "emacs": "productivity", "neovide": "productivity",
        "helix": "productivity", "godot": "productivity", "eclipse": "productivity",
        "netbeans": "productivity", "qtcreator": "productivity", "notion": "productivity",
        "notion-app": "productivity", "obsidian": "productivity", "logseq": "productivity",
        "joplin": "productivity", "anytype": "productivity", "standardnotes": "productivity",
        "zotero": "productivity", "gnucash": "productivity", "kmymoney": "productivity",
        "homebank": "productivity", "gnome-calendar": "productivity", "kontact": "productivity",
        "postman": "productivity", "insomnia": "productivity", "dbeaver": "productivity",
        "filezilla": "productivity",
        // Information & Reading
        "zathura": "reading", "okular": "reading", "evince": "reading", "foliate": "reading",
        "calibre": "reading", "ebook-viewer": "reading", "mupdf": "reading", "sioyek": "reading",
        "qpdfview": "reading", "atril": "reading", "xpdf": "reading", "newsflash": "reading",
        "liferea": "reading", "fluentreader": "reading", "akregator": "reading",
        "gfeeds": "reading", "koreader": "reading",
        // Education
        "anki": "education", "gcompris": "education", "stellarium": "education",
        "kstars": "education", "geogebra": "education", "klavaro": "education", "kalzium": "education",
        // Utilities
        "nautilus": "utilities", "dolphin": "utilities", "nemo": "utilities", "thunar": "utilities",
        "pcmanfm": "utilities", "caja": "utilities", "krusader": "utilities", "doublecmd": "utilities",
        "gnome-system-monitor": "utilities", "ksysguard": "utilities", "plasma-systemmonitor": "utilities",
        "gnome-disks": "utilities", "gparted": "utilities", "baobab": "utilities",
        "gnome-calculator": "utilities", "kcalc": "utilities", "galculator": "utilities",
        "qalculate-gtk": "utilities", "pavucontrol": "utilities", "easyeffects": "utilities",
        "helvum": "utilities", "blueman-manager": "utilities", "nm-connection-editor": "utilities",
        "gnome-control-center": "utilities", "systemsettings": "utilities", "gnome-tweaks": "utilities",
        "dconf-editor": "utilities", "flameshot": "utilities", "spectacle": "utilities",
        "ksnip": "utilities", "gnome-screenshot": "utilities", "keepassxc": "utilities",
        "bitwarden": "utilities", "1password": "utilities", "seahorse": "utilities",
        "virt-manager": "utilities", "gnome-boxes": "utilities", "virtualbox": "utilities",
        "transmission-gtk": "utilities", "qbittorrent": "utilities", "deluge": "utilities",
        "fragments": "utilities", "file-roller": "utilities", "ark": "utilities",
        "xarchiver": "utilities", "gnome-software": "utilities", "timeshift": "utilities",
        "gnome-clocks": "utilities", "gnome-weather": "utilities", "htop": "utilities", "btop": "utilities",
        // Travel
        "gnome-maps": "travel", "marble": "travel", "google-earth": "travel",
        "googleearth-pro": "travel", "organicmaps": "travel"
    })

    // Window-class → category key. Tries the whole class, then each dotted
    // segment (so "org.telegram.desktop" still matches "telegram"), then a few
    // family regexes for the variant-heavy app types.
    function categoryFor(cls) {
        if (!cls) return "other"
        let lc = cls.toLowerCase().replace(/\.exe$/, "")
        let m = root._catMap
        if (m[lc] !== undefined) return m[lc]
        let segs = lc.split(".")
        for (let i = segs.length - 1; i >= 0; i--)
            if (m[segs[i]] !== undefined) return m[segs[i]]
        // Web browsers — Apple files Safari under Productivity & Finance.
        if (/firefox|chrom|brave|vivaldi|opera|microsoft-edge|librewolf|floorp|waterfox|qutebrowser|falkon|epiphany|gnome-web|midori|tor-browser/.test(lc)) return "productivity"
        // Terminals / IDEs / office suites.
        if (/term$|terminal|kitty|alacritty|wezterm|konsole|tilix|ghostty|warp|tabby|ptyxis|contour|blackbox|foot/.test(lc)) return "productivity"
        if (/idea|pycharm|clion|goland|webstorm|rider|datagrip|phpstorm|rubymine|jetbrains|android-studio/.test(lc)) return "productivity"
        if (/libreoffice|soffice|onlyoffice|abiword|gnumeric|^wps/.test(lc)) return "productivity"
        if (/obs/.test(lc)) return "creativity"
        return "other"
    }
    function categoryLabelFor(cls) { return root._catLabels[root.categoryFor(cls)] }

    // Sum an app→seconds map into per-category seconds: { categoryKey: seconds }.
    function categoryTotals(appMap) {
        let t = ({})
        for (let cls in appMap) {
            let cat = root.categoryFor(cls)
            t[cat] = (t[cat] || 0) + appMap[cls]
        }
        return t
    }

    // A day's categories ranked by usage, with their rank-derived colour:
    //   [{ key, label, color, seconds }]  (descending; top 3 coloured, rest grey)
    // This ranking defines the colour every chart/list uses for the day, so the
    // same category reads the same colour everywhere on screen.
    function categoryBreakdown(appMap) {
        let totals = root.categoryTotals(appMap)
        let arr = []
        for (let k in totals) arr.push({ key: k, seconds: totals[k] })
        arr.sort((a, b) => b.seconds - a.seconds)
        let out = []
        for (let i = 0; i < arr.length; i++) {
            out.push({
                key: arr[i].key,
                label: root._catLabels[arr[i].key],
                color: i < root.categoryRankColors.length
                    ? root.categoryRankColors[i] : root.categoryOtherColor,
                seconds: arr[i].seconds
            })
        }
        return out
    }

    // categoryKey → colour map for a day, from its ranking (see categoryBreakdown).
    function categoryColorMap(appMap) {
        let b = root.categoryBreakdown(appMap)
        let m = ({})
        for (let i = 0; i < b.length; i++) m[b[i].key] = b[i].color
        return m
    }

    // Stacked category segments for one bar (a day or an hour), coloured from an
    // externally-supplied rank order + colour map so every bar on the panel
    // shares the selected day's colour scheme. Categories are emitted in `order`
    // (rank 0 first); any category present here but outside `order` is appended
    // and renders grey. Returns bottom→top: [{ seconds, color }]; callers reverse
    // it for a top-down Column.
    function orderedSegments(appMap, order, colorMap) {
        let totals = root.categoryTotals(appMap)
        let out = [], seen = ({})
        for (let i = 0; i < order.length; i++) {
            let k = order[i]
            if (totals[k] > 0) {
                out.push({ seconds: totals[k], color: colorMap[k] || root.categoryOtherColor })
                seen[k] = true
            }
        }
        for (let k in totals)
            if (!seen[k] && totals[k] > 0)
                out.push({ seconds: totals[k], color: colorMap[k] || root.categoryOtherColor })
        return out
    }

    function _dayKey(d) {
        let mm = String(d.getMonth() + 1).padStart(2, "0")
        let dd = String(d.getDate()).padStart(2, "0")
        return d.getFullYear() + "-" + mm + "-" + dd
    }
    function _today() { return root._dayKey(new Date()) }

    // "YYYY-MM-DD" → local Date at midnight (avoids the UTC-parsing surprise of
    // `new Date(string)`).
    function _parse(dayKey) {
        let p = dayKey.split("-")
        return new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]))
    }

    // Merge per-launch Qt instance suffixes ("foo_1234_5678" → "foo") so the
    // same app doesn't fragment into multiple rows across relaunches.
    function _norm(cls) {
        if (!cls) return ""
        let m = cls.match(/^(.+?)_\d+_\d+$/)
        return m ? m[1] : cls
    }

    // Drop days older than `keepDays` so the file doesn't grow forever. Keys are
    // zero-padded ISO dates, so a lexical compare is also a chronological one.
    function _prune(map) {
        let cutoff = new Date()
        cutoff.setDate(cutoff.getDate() - root.keepDays)
        let cutKey = root._dayKey(cutoff)
        let out = ({})
        for (let k in map) if (k >= cutKey) out[k] = map[k]
        return out
    }

    Component.onCompleted: loadProc.running = true

    // ── Load persisted history on startup ────────────────────────────────────
    // Also makes sure the data dir exists so the FileView below can write to it.
    Process {
        id: loadProc
        command: ["bash", "-c", "mkdir -p '" + root.dataDir + "'; cat '" + root.dataFile + "' 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let loaded = ({}), loadedHours = ({})
                try {
                    let obj = JSON.parse(text)
                    if (obj && obj.days) {
                        loaded = obj.days
                        if (obj.hours) loadedHours = obj.hours
                    } else if (obj && obj.apps && obj.day) {
                        // Migrate the old single-day format ({ day, apps }).
                        loaded[obj.day] = obj.apps
                    }
                } catch (e) {
                    loaded = ({})
                }
                root.day = root._today()
                if (!loaded[root.day]) loaded[root.day] = ({})
                root.days = root._prune(loaded)
                root.hours = root._prune(loadedHours)   // same dayKey layout as `days`
                root._persist()
                pollTimer.start()
            }
        }
    }

    // ── Sample the focused window ────────────────────────────────────────────
    Process {
        id: activeProc
        command: ["bash", "-c",
            "hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty'"]
        stdout: StdioCollector {
            onStreamFinished: root._accumulate(text.trim())
        }
    }

    Timer {
        id: pollTimer
        interval: root.tickSeconds * 1000
        repeat: true
        running: false
        onTriggered: activeProc.running = true
    }

    function _accumulate(rawClass) {
        let now = new Date()
        let today = root._dayKey(now)
        if (today !== root.day) root.day = today   // crossed midnight → new day

        let cls = root._norm(rawClass)
        // Reassign fresh objects so `apps`/`ranked`/`days` bindings re-evaluate.
        let all = Object.assign({}, root.days)
        let dayMap = Object.assign({}, all[root.day] || {})
        if (cls.length > 0) dayMap[cls] = (dayMap[cls] || 0) + root.tickSeconds
        all[root.day] = dayMap
        root.days = all

        // Mirror the same tick into the current hour's bucket (fresh objects so
        // `hours`/`hoursFor` bindings re-evaluate too).
        if (cls.length > 0) {
            let hh = String(now.getHours()).padStart(2, "0")
            let allH = Object.assign({}, root.hours)
            let dayH = Object.assign({}, allH[root.day] || {})
            let hourMap = Object.assign({}, dayH[hh] || {})
            hourMap[cls] = (hourMap[cls] || 0) + root.tickSeconds
            dayH[hh] = hourMap
            allH[root.day] = dayH
            root.hours = allH
        }
        root._persist()
    }

    // ── Persist ──────────────────────────────────────────────────────────────
    // Direct FileView write — the old path spawned bash + base64 for every
    // 20-second tick just to write a JSON file the process can write itself.
    FileView {
        id: dataStore
        path: root.dataFile
        printErrors: false
    }
    function _persist() {
        dataStore.setText(JSON.stringify({ days: root.days, hours: root.hours }))
    }
}
