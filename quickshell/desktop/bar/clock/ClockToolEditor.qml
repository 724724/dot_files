import QtQuick
import ".." as Bar
import "../../icons" as Icons

Item {
    id: root

    property string mode: ""
    property bool dark: false
    property color accent: "#007aff"
    property color primaryText: "#1a1a1a"
    property color secondaryText: Qt.rgba(0, 0, 0, 0.55)
    property color surface: Qt.rgba(0, 0, 0, 0.05)
    property color lineColor: Qt.rgba(0, 0, 0, 0.10)
    property int alarmHour: 7
    property int alarmMinute: 0
    property bool alarmPm: false
    property var repeatDays: []
    property string selectedSound: "Radial"
    property bool snooze: true
    property int timerHours: 0
    property int timerMinutes: 5
    property int timerSeconds: 0
    property int focusMinutes: 25
    property int breakMinutes: 5
    property int focusRounds: 4
    property bool restrictionsEnabled: true
    property var allowedApps: []   // desktop ids allowed during this focus session
    property var allowedSites: []  // hosts a browser may visit while focusing
    property int ddayYear: 2026
    property int ddayMonth: 1
    property int ddayDay: 1
    property string ddayCountType: "minus"
    // When set, the editor edits this existing item instead of creating a new one.
    property var editItem: null
    readonly property bool editing: editItem !== null && editItem !== undefined
    signal cancelled
    signal saved
    signal detailRequested(string mode)

    readonly property string title: (editing ? "Edit " : "Add ")
        + (mode === "alarm" ? "Alarm" : mode === "timer" ? "Timer"
            : mode === "dday" ? "D-Day" : "Pomodoro")
    implicitWidth: 310
    implicitHeight: editorColumn.implicitHeight

    onModeChanged: if (mode !== "") loadForm()

    // Load either the existing item's values (edit) or the defaults (add). Driven
    // explicitly by ClockPopupWindow when it opens the editor.
    function loadForm() {
        if (editing) loadFromItem(editItem)
        else reset()
    }

    function loadFromItem(item) {
        labelInput.text = item.label
            || (mode === "pomodoro" ? "Focus" : mode === "alarm" ? "Alarm"
                : mode === "dday" ? "D-Day" : "Timer")
        if (mode === "alarm") {
            let h = Number(item.hour || 0)
            alarmPm = h >= 12
            alarmHour = (h % 12) || 12
            alarmMinute = Number(item.minute || 0)
            repeatDays = Bar.ClockService.toArray(item.repeatDays)
            selectedSound = item.sound || "Radial"
            snooze = item.snooze !== false
        } else if (mode === "timer") {
            let d = Math.max(0, Math.floor(item.duration || 0))
            timerHours = Math.floor(d / 3600)
            timerMinutes = Math.floor((d % 3600) / 60)
            timerSeconds = d % 60
            selectedSound = item.sound || "Radial"
        } else if (mode === "pomodoro") {
            focusMinutes = Math.max(1, Math.floor(item.focusMinutes || 25))
            breakMinutes = Math.max(1, Math.floor(item.breakMinutes || 5))
            focusRounds = Math.max(1, Math.floor(item.rounds || 4))
            restrictionsEnabled = item.restrictionsEnabled !== false
            allowedApps = Bar.ClockService.toArray(item.allowedApps)
            allowedSites = Bar.ClockService.toArray(item.allowedSites)
        } else {
            let date = Bar.ClockService.normalizedDdayDate(item.year, item.month, item.day)
            ddayYear = date.year
            ddayMonth = date.month
            ddayDay = date.day
            ddayCountType = item.countType === "plus" ? "plus" : "minus"
        }
    }

    function reset() {
        let now = new Date()
        let nextMinutes = Math.floor(now.getMinutes() / 5) * 5 + 5
        let nextHour = now.getHours() + (nextMinutes >= 60 ? 1 : 0)
        alarmHour = nextHour % 12 || 12
        alarmMinute = nextMinutes % 60
        alarmPm = nextHour % 24 >= 12
        repeatDays = []
        selectedSound = "Radial"
        snooze = true
        timerHours = 0
        timerMinutes = 5
        timerSeconds = 0
        focusMinutes = 25
        breakMinutes = 5
        focusRounds = 4
        restrictionsEnabled = true
        allowedApps = []
        allowedSites = []
        let target = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 30)
        ddayYear = target.getFullYear()
        ddayMonth = target.getMonth() + 1
        ddayDay = target.getDate()
        ddayCountType = "minus"
        labelInput.text = mode === "pomodoro" ? "Focus"
            : (mode === "alarm" ? "Alarm" : mode === "dday" ? "D-Day" : "Timer")
    }

    // "https://www.Instagram.com/x" → "instagram.com" (matches focus-sites.sh).
    function normalizeSite(value) {
        let s = String(value || "").trim().toLowerCase()
        s = s.replace(/^[a-z][a-z0-9+.-]*:\/\//, "")
        s = s.split("/")[0]
        s = s.split(":")[0]
        s = s.replace(/^www\./, "")
        return s
    }

    function addSite() {
        let host = normalizeSite(siteInput.text)
        siteInput.text = ""
        if (host === "" || host.indexOf(".") < 0) return
        if (allowedSites.indexOf(host) >= 0) return
        allowedSites = allowedSites.concat([host])
    }

    function removeApp(id) {
        allowedApps = allowedApps.filter(a => a !== id)
    }

    function removeSite(host) {
        allowedSites = allowedSites.filter(s => s !== host)
    }

    function commit() {
        if (mode === "alarm") {
            let hour = alarmHour % 12 + (alarmPm ? 12 : 0)
            if (editing)
                Bar.ClockService.updateAlarm(editItem.id, hour, alarmMinute, labelInput.text,
                    repeatLabel(), repeatDays, selectedSound, snooze)
            else
                Bar.ClockService.addAlarm(hour, alarmMinute, labelInput.text, repeatLabel(),
                    repeatDays, selectedSound, snooze)
        } else if (mode === "timer") {
            let secs = timerHours * 3600 + timerMinutes * 60 + timerSeconds
            if (editing) Bar.ClockService.updateTimer(editItem.id, secs, labelInput.text, selectedSound)
            else Bar.ClockService.addTimer(secs, labelInput.text, selectedSound)
        } else if (mode === "pomodoro") {
            if (editing)
                Bar.ClockService.updatePomodoro(editItem.id, labelInput.text, focusMinutes,
                    breakMinutes, focusRounds, restrictionsEnabled, allowedApps, allowedSites)
            else
                Bar.ClockService.addPomodoro(labelInput.text, focusMinutes, breakMinutes, focusRounds,
                    restrictionsEnabled, allowedApps, allowedSites)
        } else {
            if (editing)
                Bar.ClockService.updateDday(editItem.id, labelInput.text,
                    ddayYear, ddayMonth, ddayDay, ddayCountType)
            else
                Bar.ClockService.addDday(labelInput.text,
                    ddayYear, ddayMonth, ddayDay, ddayCountType)
        }
        saved()
    }

    function setDdayDate(year, month, day) {
        let date = Bar.ClockService.normalizedDdayDate(year, month, day)
        ddayYear = date.year
        ddayMonth = date.month
        ddayDay = date.day
    }

    function hasDay(day) {
        return Array.isArray(repeatDays) && repeatDays.indexOf(day) >= 0
    }

    function repeatLabel() {
        let days = Array.isArray(repeatDays) ? repeatDays : []
        if (days.length === 0) return "Once"
        if (days.length === 7) return "Every Day"
        if (days.length === 5 && hasDay(1) && hasDay(2) && hasDay(3) && hasDay(4) && hasDay(5))
            return "Weekdays"
        if (days.length === 2 && hasDay(0) && hasDay(6)) return "Weekends"
        return "Custom"
    }

    component HeaderAction: Text {
        id: action
        property bool enabled: true
        signal activated
        color: enabled ? root.accent : root.secondaryText
        opacity: enabled ? 1 : 0.45
        font.family: "SF Pro Display"
        font.pixelSize: 14
        font.weight: Font.DemiBold
        scale: actionTap.pressed ? Bar.ThemeService.pressScale : 1
        Behavior on scale { Bar.AppleSpring { spring: 20 } }
        HoverHandler { cursorShape: Qt.PointingHandCursor; enabled: action.enabled }
        TapHandler {
            id: actionTap
            enabled: action.enabled
            onTapped: action.activated()
        }
    }

    component Stepper: Item {
        id: stepper
        property int value: 0
        property int minimum: 0
        property int maximum: 59
        property int step: 1
        property string suffix: ""
        signal changed(int value)
        width: 76
        height: 92
        onValueChanged: if (!stepperInput.activeFocus)
            stepperInput.text = String(stepper.value).padStart(2, "0")

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            text: "⌃"
            color: upHover.hovered ? root.primaryText : root.secondaryText
            font.family: "SF Pro Display"
            font.pixelSize: 16
            HoverHandler { id: upHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    let next = stepper.value + stepper.step
                    if (next > stepper.maximum) next = stepper.minimum
                    stepper.changed(next)
                }
            }
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 42
            radius: 12
            color: root.surface
            TextInput {
                id: stepperInput
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 8
                anchors.rightMargin: stepper.suffix === "" ? 8 : 20
                anchors.verticalCenter: parent.verticalCenter
                text: String(stepper.value).padStart(2, "0")
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 22
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
                horizontalAlignment: TextInput.AlignHCenter
                verticalAlignment: TextInput.AlignVCenter
                inputMethodHints: Qt.ImhDigitsOnly
                selectByMouse: true
                activeFocusOnTab: true
                validator: IntValidator { bottom: stepper.minimum; top: stepper.maximum }
                onActiveFocusChanged: {
                    if (activeFocus) selectAll()
                    else commitValue()
                }
                onAccepted: {
                    commitValue()
                    focus = false
                }
                function commitValue() {
                    let parsed = parseInt(text)
                    if (isNaN(parsed)) parsed = stepper.value
                    parsed = Math.max(stepper.minimum, Math.min(stepper.maximum, parsed))
                    stepper.changed(parsed)
                    text = String(parsed).padStart(2, "0")
                }
            }
            Text {
                visible: stepper.suffix !== ""
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: stepper.suffix
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 15
                font.weight: Font.Medium
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: "⌄"
            color: downHover.hovered ? root.primaryText : root.secondaryText
            font.family: "SF Pro Display"
            font.pixelSize: 16
            HoverHandler { id: downHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    let next = stepper.value - stepper.step
                    if (next < stepper.minimum) next = stepper.maximum
                    stepper.changed(next)
                }
            }
        }
    }

    component SettingsRow: Rectangle {
        id: settingsRow
        property string label: ""
        property string value: ""
        signal activated
        width: parent ? parent.width : 0
        height: 46
        color: rowHover.hovered ? root.surface : "transparent"
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: settingsRow.label
            color: root.primaryText
            font.family: "SF Pro Display"
            font.pixelSize: 14
            font.weight: Font.Medium
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: settingsRow.value
            color: root.secondaryText
            font.family: "SF Pro Display"
            font.pixelSize: 14
        }
        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: settingsRow.activated() }
    }

    Column {
        id: editorColumn
        width: parent.width
        spacing: 12

        Item {
            width: parent.width
            height: 30
            HeaderAction {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Cancel"
                onActivated: root.cancelled()
            }
            Text {
                anchors.centerIn: parent
                text: root.title
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 17
                font.weight: Font.DemiBold
                font.letterSpacing: -0.2
            }
            HeaderAction {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Save"
                enabled: root.mode !== "timer" || root.timerHours + root.timerMinutes + root.timerSeconds > 0
                onActivated: root.commit()
            }
        }

        Row {
            visible: root.mode === "alarm"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Stepper { value: root.alarmHour; minimum: 1; maximum: 12; onChanged: value => root.alarmHour = value }
            Stepper { value: root.alarmMinute; step: 1; onChanged: value => root.alarmMinute = value }
            Rectangle {
                width: 76
                height: 42
                radius: 12
                anchors.verticalCenter: parent.verticalCenter
                color: root.surface
                Text {
                    anchors.centerIn: parent
                    text: root.alarmPm ? "PM" : "AM"
                    color: root.primaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 20
                    font.weight: Font.Medium
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.alarmPm = !root.alarmPm }
            }
        }

        Row {
            visible: root.mode === "timer"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Stepper { value: root.timerHours; maximum: 23; suffix: "h"; onChanged: value => root.timerHours = value }
            Stepper { value: root.timerMinutes; suffix: "m"; onChanged: value => root.timerMinutes = value }
            Stepper { value: root.timerSeconds; suffix: "s"; onChanged: value => root.timerSeconds = value }
        }

        Column {
            visible: root.mode === "pomodoro"
            width: parent.width
            spacing: 6
            Text {
                text: "FOCUS · BREAK · ROUNDS"
                color: root.secondaryText
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Stepper { value: root.focusMinutes; minimum: 1; maximum: 90; suffix: "m"; onChanged: value => root.focusMinutes = value }
                Stepper { value: root.breakMinutes; minimum: 1; maximum: 30; suffix: "m"; onChanged: value => root.breakMinutes = value }
                Stepper { value: root.focusRounds; minimum: 1; maximum: 12; suffix: "×"; onChanged: value => root.focusRounds = value }
            }
        }

        Column {
            visible: root.mode === "dday"
            width: parent.width
            spacing: 10

            Text {
                text: "COUNT"
                color: root.secondaryText
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                Repeater {
                    model: [
                        { value: "minus", label: "D−", hint: "Until" },
                        { value: "plus", label: "D+", hint: "Since" }
                    ]

                    delegate: Rectangle {
                        id: countTypeButton
                        required property var modelData
                        readonly property bool selected: root.ddayCountType === modelData.value
                        width: 116
                        height: 32
                        radius: 16
                        color: selected ? root.accent
                            : (countTypeHover.hovered ? root.surface : "transparent")
                        border.width: selected ? 0 : 1
                        border.color: root.lineColor
                        scale: countTypeTap.pressed ? Bar.ThemeService.pressScale : 1
                        Behavior on scale { Bar.AppleSpring { spring: 20 } }

                        Row {
                            anchors.centerIn: parent
                            spacing: 7
                            Text {
                                text: countTypeButton.modelData.label
                                color: countTypeButton.selected ? "#ffffff" : root.primaryText
                                font.family: "SF Pro Display"
                                font.pixelSize: 14
                                font.weight: Font.DemiBold
                            }
                            Text {
                                text: countTypeButton.modelData.hint
                                color: countTypeButton.selected
                                    ? Qt.rgba(1, 1, 1, 0.72) : root.secondaryText
                                font.family: "SF Pro Display"
                                font.pixelSize: 11
                                font.weight: Font.Medium
                            }
                        }

                        HoverHandler { id: countTypeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            id: countTypeTap
                            onTapped: root.ddayCountType = countTypeButton.modelData.value
                        }
                    }
                }
            }

            Text {
                text: "DATE"
                color: root.secondaryText
                font.family: "SF Pro Display"
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Stepper {
                    width: 90
                    value: root.ddayYear
                    minimum: 1970
                    maximum: 2200
                    suffix: "y"
                    onChanged: value => root.setDdayDate(value, root.ddayMonth, root.ddayDay)
                }
                Stepper {
                    value: root.ddayMonth
                    minimum: 1
                    maximum: 12
                    suffix: "m"
                    onChanged: value => root.setDdayDate(root.ddayYear, value, root.ddayDay)
                }
                Stepper {
                    value: root.ddayDay
                    minimum: 1
                    maximum: new Date(root.ddayYear, root.ddayMonth, 0).getDate()
                    suffix: "d"
                    onChanged: value => root.setDdayDate(root.ddayYear, root.ddayMonth, value)
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 48
            radius: 12
            color: root.surface
            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                text: "Label"
                color: root.primaryText
                font.family: "SF Pro Display"
                font.pixelSize: 14
                font.weight: Font.Medium
            }
            TextInput {
                id: labelInput
                anchors.left: parent.left
                anchors.leftMargin: 78
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: TextInput.AlignRight
                color: root.secondaryText
                selectionColor: root.accent
                font.family: "SF Pro Display"
                font.pixelSize: 14
                maximumLength: 32
            }
        }

        // ── Allowed Apps (Pomodoro only) ─────────────────────────────────
        Rectangle {
            visible: root.mode === "pomodoro"
            width: parent.width
            height: 58
            radius: 12
            color: root.surface

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: restrictionSwitch.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: "Use Allowed Apps & Sites"
                    color: root.primaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                Text {
                    width: parent.width
                    text: root.restrictionsEnabled
                        ? "Only added items are available" : "Everything is available"
                    color: root.secondaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                id: restrictionSwitch
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 42
                height: 24
                radius: 12
                color: root.restrictionsEnabled ? root.accent
                    : (root.dark ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(0, 0, 0, 0.14))
                Behavior on color { ColorAnimation { duration: 120 } }
                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    y: 2
                    x: root.restrictionsEnabled ? parent.width - width - 2 : 2
                    color: "white"
                    Behavior on x { Bar.AppleSpring { spring: 20 } }
                }
            }

            HoverHandler { cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.restrictionsEnabled = !root.restrictionsEnabled }
        }

        // Apps picked here stay usable during the focus phase; every other app
        // is masked + blocked in the launchpad, dock, spotlight and keybindings.
        Rectangle {
            visible: root.mode === "pomodoro" && root.restrictionsEnabled
            width: parent.width
            height: allowedCol.implicitHeight
            radius: 12
            color: root.surface
            clip: true
            Column {
                id: allowedCol
                width: parent.width

                SettingsRow {
                    label: "Allowed Apps"
                    value: (root.allowedApps.length === 0
                        ? "None"
                        : root.allowedApps.length + (root.allowedApps.length === 1 ? " app" : " apps"))
                        + "  ›"
                    onActivated: root.detailRequested("apps")
                }

                // Quick visual of the picked apps' icons.
                Flow {
                    visible: root.allowedApps.length > 0
                    x: 12
                    width: parent.width - 24
                    spacing: 6
                    Repeater {
                        model: root.allowedApps
                        delegate: Item {
                            id: appChip
                            required property var modelData
                            width: 30
                            height: 30
                            scale: appChipTap.pressed ? Bar.ThemeService.pressScale : 1
                            Behavior on scale { Bar.AppleSpring { spring: 20 } }
                            Icons.AppIcon {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                sourceSize.width: 26
                                sourceSize.height: 26
                                smooth: true
                                mipmap: true
                                fillMode: Image.PreserveAspectFit
                                opacity: appChipHover.hovered ? 0.3 : 1
                                iconName: Bar.ClockService.focusAppIcon(appChip.modelData)
                                desktopId: appChip.modelData
                            }
                            // Hover reveals a × over the icon — click to un-allow.
                            Rectangle {
                                anchors.fill: parent
                                radius: 15
                                visible: appChipHover.hovered
                                color: Qt.rgba(1, 0.23, 0.19, 0.16)
                                Text {
                                    anchors.centerIn: parent
                                    text: "×"
                                    color: "#ff453a"
                                    font.family: "SF Pro Display"
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
                                }
                            }
                            HoverHandler { id: appChipHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                id: appChipTap
                                onTapped: root.removeApp(appChip.modelData)
                            }
                        }
                    }
                }

                Text {
                    visible: root.allowedApps.length === 0
                    x: 12
                    width: parent.width - 24
                    text: "No apps allowed — everything is blocked while focusing."
                    color: root.secondaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }

                // Bottom breathing room under the icons / hint.
                Item { width: 1; height: 12 }
            }
        }

        // ── Allowed Sites — only when a browser is among the Allowed Apps ───
        // Enforced through the browser's enterprise policy file (Firefox
        // WebsiteFilter / Chrome URLAllowlist), written by scripts/focus-sites.sh
        // while the session runs. Empty list = the browser is unrestricted.
        Rectangle {
            visible: root.mode === "pomodoro" && root.restrictionsEnabled
                && Bar.ClockService.hasAllowedBrowser(root.allowedApps)
            width: parent.width
            height: sitesCol.implicitHeight
            radius: 12
            color: root.surface
            clip: true
            Column {
                id: sitesCol
                width: parent.width

                Item {
                    width: parent.width
                    height: 42
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Allowed Sites"
                        color: root.primaryText
                        font.family: "SF Pro Display"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.allowedSites.length === 0
                            ? "All sites"
                            : root.allowedSites.length
                                + (root.allowedSites.length === 1 ? " site" : " sites")
                        color: root.secondaryText
                        font.family: "SF Pro Display"
                        font.pixelSize: 14
                    }
                }

                Item {
                    width: parent.width
                    height: 44
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.right: addSiteBtn.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        height: 34
                        radius: 9
                        color: root.dark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.05)
                        border.width: 1
                        border.color: siteInput.activeFocus ? root.accent : "transparent"
                        TextInput {
                            id: siteInput
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.primaryText
                            selectionColor: root.accent
                            selectByMouse: true
                            clip: true
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            onAccepted: root.addSite()
                        }
                    }
                    Rectangle {
                        id: addSiteBtn
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 54
                        height: 34
                        radius: 9
                        opacity: siteInput.text.trim() === "" ? 0.4 : 1
                        color: addSiteHover.hovered
                            ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28)
                            : Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)
                        scale: addSiteTap.pressed ? Bar.ThemeService.pressScale : 1
                        Behavior on scale { Bar.AppleSpring { spring: 20 } }
                        Text {
                            anchors.centerIn: parent
                            text: "Add"
                            color: root.accent
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        HoverHandler {
                            id: addSiteHover
                            enabled: siteInput.text.trim() !== ""
                            cursorShape: Qt.PointingHandCursor
                        }
                        TapHandler {
                            id: addSiteTap
                            enabled: siteInput.text.trim() !== ""
                            onTapped: root.addSite()
                        }
                    }
                }

                Repeater {
                    model: root.allowedSites
                    delegate: Item {
                        required property var modelData
                        width: sitesCol.width
                        height: 32
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.right: removeSiteBtn.left
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData
                            color: root.primaryText
                            font.family: "SF Pro Display"
                            font.pixelSize: 13
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            id: removeSiteBtn
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            radius: 12
                            color: removeSiteHover.hovered
                                ? Qt.rgba(1, 0.23, 0.19, 0.14) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "×"
                                color: "#ff453a"
                                font.family: "SF Pro Display"
                                font.pixelSize: 15
                            }
                            HoverHandler { id: removeSiteHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.removeSite(modelData) }
                        }
                    }
                }

                Text {
                    visible: root.allowedSites.length === 0
                    x: 12
                    width: parent.width - 24
                    text: "No sites added — the browser opens normally. "
                        + "Add one to limit it to just those sites."
                    color: root.secondaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 11
                    wrapMode: Text.Wrap
                }

                // Browsers read their policy file only at startup, so the limit
                // lands on the next launch — the browser is closed for you when
                // the session starts.
                Text {
                    visible: root.allowedSites.length > 0
                    x: 12
                    width: parent.width - 24
                    text: "Applies when the browser restarts — it's closed for you when the session starts."
                    color: root.secondaryText
                    font.family: "SF Pro Display"
                    font.pixelSize: 10
                    opacity: 0.85
                    wrapMode: Text.Wrap
                }

                Item { width: 1; height: 12 }
            }
        }

        Rectangle {
            visible: root.mode === "alarm"
            width: parent.width
            height: alarmSettings.implicitHeight
            radius: 12
            color: root.surface
            clip: true
            Column {
                id: alarmSettings
                width: parent.width
                SettingsRow {
                    label: "Repeat"
                    value: root.repeatLabel() + "  ›"
                    onActivated: root.detailRequested("repeat")
                }
                Rectangle { width: parent.width; height: 1; color: root.lineColor }
                SettingsRow {
                    label: "Sound"
                    value: Bar.ClockService.soundLabel(root.selectedSound) + "  ›"
                    onActivated: root.detailRequested("sound")
                }
                Rectangle { width: parent.width; height: 1; color: root.lineColor }
                SettingsRow {
                    label: "Snooze"
                    value: root.snooze ? "On" : "Off"
                    onActivated: root.snooze = !root.snooze
                }
            }
        }

        Rectangle {
            visible: root.mode === "timer"
            width: parent.width
            height: 46
            radius: 12
            color: root.surface
            clip: true
            SettingsRow {
                label: "Sound"
                value: Bar.ClockService.soundLabel(root.selectedSound) + "  ›"
                onActivated: root.detailRequested("sound")
            }
        }
    }
}
