import os
import pathlib
import re
import subprocess
import tempfile
import textwrap
import unittest


ROOT = pathlib.Path(__file__).parents[2]


class QuickshellLockSourceTests(unittest.TestCase):
    def read(self, relative):
        return (ROOT / relative).read_text(encoding="utf-8")

    def test_lock_uses_the_session_lock_protocol_and_disables_reload(self):
        source = self.read("lock/shell.qml")
        self.assertIn("WlSessionLock {", source)
        self.assertIn("locked: true", source)
        self.assertIn("readonly property bool protocolSecure: sessionLock.secure", source)
        self.assertIn("settings.watchFiles: false", source)
        self.assertIn("//@ pragma Env QS_DISABLE_FILE_WATCHER = 1", source)
        self.assertNotIn("PanelWindow", source)

    def test_every_surface_is_opaque_and_part_of_the_coverage_handshake(self):
        source = self.read("lock/LockSurface.qml")
        self.assertIn("WlSessionLockSurface {", source)
        self.assertIn('color: "#070a10"', source)
        self.assertIn("surface.controller.surfaceShown(surface.outputScreen)", source)
        self.assertIn("surface.controller.surfaceRemoved(surface.outputScreen)", source)
        self.assertIn("property var outputScreen: null", source)

    def test_lock_widgets_share_the_renderer_and_stay_inside_fixed_reservations(self):
        surface = self.read("lock/LockSurface.qml")
        service = self.read("desktop/widgets/WidgetsService.qml")
        editor = self.read("desktop/widgets/LockLayoutEditor.qml")
        window = self.read("desktop/widgets/WidgetsWindow.qml")
        frame = self.read("desktop/widgets/WidgetFrame.qml")
        preview = self.read("desktop/widgets/WidgetPreviewFrame.qml")

        self.assertIn("width * 0.60", surface)
        self.assertIn("anchors.top: clockStack.bottom", surface)
        self.assertIn("anchors.bottomMargin: 202 + (42 + 28) * surface.uiScale", surface)
        self.assertIn("clip: true", surface)
        self.assertIn("readonly property int lockGridColumns: 6", service)
        self.assertIn("readonly property int lockGridRows: 3", service)
        self.assertIn("function lockRegionFree", service)
        self.assertIn("if (!root.lockRegionFree", service)
        self.assertNotIn("Flickable", editor)
        reminders_size = service.split("function remindersSize", 1)[1].split("function removeAt", 1)[0]
        self.assertRegex(reminders_size, r'case 3:\s*return \{\s*"nw": 464,\s*"nh": 464')
        self.assertIn("WidgetsService.gridGap * layoutScale", editor)
        self.assertIn("WidgetsService.gridGap * layoutScale", surface)
        self.assertIn("originX + column * lockWidgetGrid.unitX", surface)
        glass = editor.split("id: glass", 1)[1].split("id: clockReservation", 1)[0]
        self.assertIn("anchors.centerIn: parent", glass)
        self.assertIn('color: "#25272d"', glass)
        self.assertNotIn("gradient:", glass)
        self.assertIn('color: "#0d0e10"', editor)
        self.assertNotIn("id: authHint", editor)
        self.assertIn("id: lockLayoutButton", window)
        self.assertIn("WidgetsService.addLockWidget(type, extra)", window)
        self.assertIn("property bool lockMediaEnabled: true", service)
        self.assertIn('"mediaEnabled": root.lockMediaEnabled', service)
        self.assertIn("WidgetsService.setLockMediaEnabled", editor)
        self.assertIn("WidgetsService.componentSource(wf.type)", frame)
        self.assertIn("WidgetsService.componentSource(frame.type)", preview)
        self.assertIn("content.setSource", frame)
        self.assertIn("content.setSource", preview)
        self.assertNotIn("PanelWindow", editor + preview)

    def test_lock_widget_context_reuses_settings_without_crossing_models(self):
        service = self.read("desktop/widgets/WidgetsService.qml")
        editor = self.read("desktop/widgets/LockLayoutEditor.qml")
        window = self.read("desktop/widgets/WidgetsWindow.qml")

        self.assertIn("signal widgetSettingsRequested", editor)
        self.assertNotIn('enabled: tile.type === "reminders"', editor)
        self.assertIn("editor.widgetSettingsRequested(tile.index", editor)
        self.assertIn('label: "Edit List"', window)
        self.assertIn('label: "Settings"', window)
        self.assertIn("board.openLockSettings(board.lockCtxIndex)", window)
        self.assertIn("function lockEditorIndex(index)", service)
        self.assertIn("function _isLockEditorIndex(index)", service)
        self.assertIn("function _setLockWidgetData(index, patch)", service)
        self.assertIn("root.lockRegionFree(index, column, row", service)
        self.assertIn("root.lockPlacementRejected(", service)

    def test_lock_data_widgets_use_shared_hourly_caches_and_other_services_are_passive(self):
        shell = self.read("lock/shell.qml")
        unit = self.read("systemd/user/quickshell-lock.service")
        preview = self.read("desktop/widgets/WidgetPreviewFrame.qml")
        news_service = self.read("desktop/widgets/NewsService.qml")
        news = self.read("desktop/widgets/NewsWidget.qml")
        weather_service = self.read("desktop/widgets/WeatherService.qml")
        weather = self.read("desktop/widgets/WeatherWidget.qml")
        calendar = self.read("desktop/widgets/CalendarService.qml")
        youtube = self.read("desktop/widgets/YoutubeService.qml")
        spotify = self.read("desktop/widgets/SpotifyService.qml")
        stock = self.read("desktop/widgets/StockWidget.qml")

        self.assertIn("//@ pragma Env QS_LOCK_MODE = 1", shell)
        self.assertIn("Environment=QS_LOCK_MODE=1", unit)
        self.assertIn('Quickshell.env("QS_LOCK_MODE") === "1"', preview)
        self.assertIn('frame.type === "weather"', preview)
        self.assertIn('frame.type === "news"', preview)
        self.assertIn("60 * 60 * 1000", news_service)
        self.assertIn('news-widget-cache.json', news_service)
        self.assertIn("NewsService.feedFresh(sources, categories)", news)
        self.assertIn("interval: newsRoot.refreshIntervalMs", news)
        self.assertIn("60 * 60 * 1000", weather_service)
        self.assertIn('weather-widget-cache.json', weather_service)
        self.assertIn("svc.forecastFresh(effLat, effLon)", weather)
        self.assertIn("interval: 60 * 60 * 1000", weather)
        for source in (calendar, youtube, spotify, stock):
            self.assertIn('Quickshell.env("QS_LOCK_MODE") === "1"', source)
        self.assertIn("if (root.sessionLockPassive) return", calendar)
        self.assertIn("if (root.sessionLockPassive) return", youtube)
        self.assertIn("if (root.sessionLockPassive) return", spotify)
        self.assertIn("if (sessionLockPassive)", stock)

    def test_lock_reminders_use_a_dedicated_data_only_capability(self):
        surface = self.read("lock/LockSurface.qml")
        service = self.read("desktop/widgets/WidgetsService.qml")
        preview = self.read("desktop/widgets/WidgetPreviewFrame.qml")
        reminder = self.read("desktop/widgets/LockRemindersWidget.qml")
        window = self.read("desktop/widgets/WidgetsWindow.qml")

        self.assertIn('Qt.resolvedUrl("LockRemindersWidget.qml")', preview)
        self.assertIn("enabled: frame.reminderEditingEnabled", preview)
        self.assertIn("liveLockInteraction: surface.controller.secure", surface)
        self.assertIn("onInputFinished: surface.restorePasswordFocus()", surface)
        self.assertIn("function addLockReminder(index, text)", service)
        self.assertIn("function renameLockReminder(index, itemId, text)", service)
        self.assertIn("function toggleLockReminder(index, itemId)", service)
        self.assertNotIn("function updateLockReminder", service)
        self.assertIn('"available": false', service)
        self.assertIn("link.available !== false", service)
        self.assertIn("_markReminderUnavailable(removedReminderListId)", service)
        self.assertIn("root._reloadReminderLinksForMutation()", service)
        self.assertGreaterEqual(service.count("root._reloadReminderLinksForMutation()"), 2)
        self.assertIn("reminderLinkStore.waitForJob()", service)
        self.assertIn("onLoaded: if (root._reminderLinksLoaded)", service)
        self.assertIn('"revision": root._reminderRevision', service)
        self.assertIn("_newReminderListId", service)
        self.assertIn("_newReminderItemId", service)
        self.assertIn("linkLockReminder(index, listId)", service)
        self.assertIn("sourceRow.modelData.listId", window)

        for forbidden in ("Process", "Qt.openUrl", "frame.save", "componentSource"):
            self.assertNotIn(forbidden, reminder)
        self.assertIn("maximumLength: 512", reminder)
        self.assertIn("Only Enter is a write", reminder)
        self.assertIn("Never commit on blur", reminder)
        self.assertIn("frame.addLockReminder", reminder)
        self.assertIn("frame.renameLockReminder", reminder)
        self.assertIn("frame.toggleLockReminder", reminder)

    def test_lock_widget_scroll_bridge_is_numeric_and_allowlisted(self):
        preview = self.read("desktop/widgets/WidgetPreviewFrame.qml")
        note = self.read("desktop/widgets/NoteWidget.qml")
        news = self.read("desktop/widgets/NewsWidget.qml")

        self.assertIn('type === "note" || type === "news"', preview)
        self.assertIn("liveLockInteraction &&", preview)
        self.assertIn("Number.isFinite(delta)", preview)
        self.assertIn("Math.max(-180, Math.min(180, delta))", preview)
        self.assertNotIn("contentItem.lockScrollBy(event)", preview)
        self.assertNotIn('type === "stock"', preview)
        self.assertIn("function lockScrollBy(delta)", note)
        self.assertIn("bodyFlick.contentY", note)
        self.assertIn("function lockScrollBy(delta)", news)
        self.assertIn("listViewport.contentY", news)

    def test_surface_does_not_read_visibility_before_its_window_exists(self):
        source = self.read("lock/LockSurface.qml")
        screen_handler = source.split("onScreenChanged:", 1)[1].split(
            "onVisibleChanged:", 1
        )[0]
        self.assertNotIn("announceCoverage", screen_handler)
        self.assertNotIn("surface.visible", screen_handler)
        self.assertIn("onVisibleChanged: surface.announceCoverage()", source)

    def test_unlock_is_only_reached_from_pam_success(self):
        source = self.read("lock/shell.qml")
        self.assertEqual(source.count("sessionLock.locked = false"), 1)
        self.assertNotIn("sessionLock.unlock()", source)
        self.assertEqual(source.count("result === PamResult.Success"), 2)
        self.assertIn("root.passwordEpoch === root.securityEpoch", source)
        self.assertIn("root.fingerprintEpoch === root.securityEpoch", source)
        self.assertIn("!root.locked || !root.secure", source)
        self.assertIn("root.unlockRequested", source)

    def test_effective_secure_transition_starts_authentication(self):
        source = self.read("lock/shell.qml")
        handler = source.split("onSecureChanged:", 1)[1]
        self.assertIn("root.startPasswordPam()", handler)
        self.assertIn("root.startFingerprintPam()", handler)

    def test_ipc_has_status_and_sleep_lifecycle_but_no_unlock_primitive(self):
        source = self.read("lock/shell.qml")
        ipc_source = source.split("IpcHandler {", 1)[1]
        functions = set(re.findall(r"\bfunction\s+(\w+)\s*\(", ipc_source))
        self.assertEqual(functions, {"status", "prepareForSleep", "resumeFromSleep"})
        for forbidden in ("unlock", "quit", "crash", "kill", "reload", "exec"):
            self.assertNotIn(f"function {forbidden}", ipc_source)

    def test_password_field_does_not_persist_or_log_the_secret(self):
        surface = self.read("lock/LockSurface.qml")
        shell = self.read("lock/shell.qml")
        self.assertIn("echoMode: TextInput.Password", surface)
        self.assertIn("Qt.ImhSensitiveData", surface)
        self.assertIn("passwordMaskDelay: 0", surface)
        self.assertIn("Qt.ImhPreferLatin", surface)
        self.assertIn("//@ pragma Env QT_IM_MODULE = compose", shell)
        self.assertIn("//@ pragma Env QT_IM_MODULES = compose", shell)
        self.assertNotIn("property string password", shell)
        self.assertNotRegex(shell, r"console\.(?:log|info|warn|error)\([^\n]*(?:response|passwordPam\.message)")

    def test_theme_is_english_sf_display_and_keeps_pam_failure_delay(self):
        surface = self.read("lock/LockSurface.qml")
        shell = self.read("lock/shell.qml")
        self.assertIn('font.family: "SF Pro Display"', surface)
        self.assertNotRegex(surface + shell, r"[가-힣]")
        self.assertIn('root.showTransientStatus(qsTr("Incorrect password")', shell)
        self.assertIn('root.schedulePasswordRetry(100, qsTr("Ready to try again")', shell)
        self.assertNotIn('root.schedulePasswordRetry(900,', shell)
        self.assertNotIn("nodelay", self.read("pam/quickshell-lock-password"))

    def test_lock_motion_and_auth_feedback_are_surface_local(self):
        surface = self.read("lock/LockSurface.qml")
        shell = self.read("lock/shell.qml")
        self.assertIn("property bool entered: false", surface)
        self.assertIn("property bool unlockAnimating: false", shell)
        self.assertIn("id: unlockAnimationTimer", shell)
        self.assertIn("surface.contentShown", surface)
        self.assertIn("id: inputShakeAnimation", surface)
        self.assertIn("onShakeRevisionChanged", surface)
        self.assertIn("font.weight: Font.Bold", surface)
        self.assertIn("anchors.bottom: parent.bottom", surface)
        self.assertIn("y: (authArea.height - height) / 2", surface)
        self.assertIn("surface.verificationMask", surface)
        self.assertIn('visible: surface.verificationMask !== ""', surface)
        clear_handler = surface.split("function onClearRevisionChanged()", 1)[1].split(
            "function onAuthReadyChanged()", 1
        )[0]
        self.assertNotIn('verificationMask = ""', clear_handler)
        self.assertIn("readonly property bool verificationInProgress", shell)
        submit = shell.split("function submitPassword", 1)[1].split(
            "function completeUnlock", 1
        )[0]
        self.assertLess(submit.index('root.setStatus("verifying"'),
                        submit.index("root.clearSecrets()"))
        self.assertLess(submit.index("root.clearSecrets()"),
                        submit.index("passwordPam.respond(response)"))
        self.assertGreaterEqual(shell.count("root.shakeRevision++"), 3)
        self.assertIn('qsTr("Fingerprint not recognized")', shell)
        self.assertIn("function showFingerprintScanFailure()", shell)
        self.assertIn("id: fingerprintFeedbackCooldown", shell)
        self.assertIn("root.showFingerprintScanFailure()", shell)
        self.assertIn('message.includes("failed to match")', shell)
        self.assertIn("surface.controller.transientStatusText", surface)

    def test_prelock_snapshot_is_bounded_private_and_has_wallpaper_fallback(self):
        capture = self.read("scripts/quickshell-lock-capture.sh")
        blur = self.read("scripts/quickshell-lock-blur.sh")
        unit = self.read("systemd/user/quickshell-lock.service")
        desktop = self.read("desktop/shell.qml")
        wallpaper = self.read("lock/LockWallpaperService.qml")
        surface = self.read("lock/LockSurface.qml")
        self.assertIn('EXPECTED_ROOT="/run/user/$(id -u)/quickshell-lock"', capture)
        self.assertIn('umask 077', capture)
        self.assertIn('capture-attempted', capture)
        self.assertIn('quickshell-desktop-outputs.json', capture)
        self.assertIn('target: "lockCapture"', desktop)
        self.assertIn('lockCaptureOutputs.setText', desktop)
        self.assertIn('/usr/bin/grim -o "$output_name" -s 0.25', capture)
        self.assertIn('-t jpeg -q 90', capture)
        self.assertIn('--kill-after=0.15s 1.50s', capture)
        self.assertNotIn('/usr/bin/magick', capture)
        self.assertIn('capture-plan.json', capture)
        self.assertIn('/usr/bin/magick "$SNAPSHOT_DIR/$raw_name"', blur)
        self.assertIn('-blur 0x24', blur)
        self.assertIn('--kill-after=0.15s 2.00s', blur)
        self.assertIn("Raw frames have served their only purpose", blur)
        self.assertIn('/usr/bin/logger -t quickshell-lock-capture', capture)
        self.assertIn('using wallpaper fallback', capture)
        self.assertIn('RuntimeDirectory=quickshell-lock', unit)
        self.assertIn('RuntimeDirectoryMode=0700', unit)
        self.assertIn('RuntimeDirectoryPreserve=restart', unit)
        self.assertIn('ExecStartPre=-%h/.config/quickshell/scripts/quickshell-lock-capture.sh', unit)
        self.assertIn('ExecStartPost=-%h/.config/quickshell/scripts/quickshell-lock-blur.sh', unit)
        self.assertNotIn('ExecStopPost=', unit)
        self.assertIn('watchChanges: true', wallpaper)
        self.assertIn('onFileChanged: reload()', wallpaper)
        self.assertIn('/^output-[0-9]+\\.jpg$/', wallpaper)
        self.assertIn('id: snapshotImage', surface)
        self.assertIn('id: wallpaperImage', surface)
        self.assertNotIn("MultiEffect", surface)
        self.assertNotIn("blurMax:", surface)

    def test_lock_media_is_surface_local_and_has_no_stem_or_pitch_controls(self):
        shell = self.read("lock/shell.qml")
        surface = self.read("lock/LockSurface.qml")
        media_files = "\n".join(
            self.read(relative)
            for relative in (
                "lock/LockMediaService.qml",
                "lock/LockAudioEqService.qml",
                "lock/LockEqBars.qml",
                "lock/LockMediaPill.qml",
                "lock/LockMediaIsland.qml",
            )
        )
        self.assertIn("LockMediaService {", shell)
        self.assertIn("LockMediaIsland {", surface)
        self.assertIn("LockMediaPill {", surface)
        self.assertIn("property bool mediaIslandOpen: false", surface)
        self.assertIn("surface.mediaIslandOpen = true", surface)
        self.assertIn("WidgetsService.lockMediaEnabled", shell + surface)
        self.assertIn("property real preferredWidth: 450", media_files)
        self.assertIn("width: preferredWidth", media_files)
        self.assertIn("height: 202", media_files)
        self.assertIn("preferredWidth: Math.max(430, Math.min(720,", surface)
        self.assertIn("anchors.bottom: parent.bottom", surface)
        self.assertNotIn("sizeScale", media_files + surface)
        self.assertIn("mediaIslandOpen", surface)
        self.assertNotIn("MultiEffect", media_files)
        self.assertNotIn("PanelWindow", media_files)
        self.assertNotIn("FocusScope", media_files)
        self.assertNotIn("StemService", media_files)
        self.assertNotIn("transpose", media_files.lower())
        self.assertNotRegex(media_files, r'glyph:\s*"(?:−1|\+1)"')

    def test_glass_panel_uses_attached_contact_depth(self):
        surface = self.read("lock/LockSurface.qml")
        self.assertIn("id: panelContactShadow", surface)
        self.assertIn('color: "#18000000"', surface)
        self.assertNotIn("id: panelShadow", surface)
        self.assertNotIn("leftPanel.x + 8", surface)
        self.assertNotIn("leftPanel.y + 10", surface)

    def test_pam_policies_keep_password_and_fingerprint_independent(self):
        shell = self.read("lock/shell.qml")
        password_policy = self.read("pam/quickshell-lock-password")
        fingerprint_policy = self.read("pam/quickshell-lock-fingerprint")
        self.assertIn('config: "quickshell-lock-password"', shell)
        self.assertIn('config: "quickshell-lock-fingerprint"', shell)
        self.assertNotIn("fingerprintPam.respond", shell)
        self.assertIn('root.disableFingerprint("unexpected-prompt")', shell)
        self.assertIn('root.disableFingerprint("max-tries")', shell)
        self.assertIn("auth include system-auth", password_policy)
        self.assertIn("auth required pam_fprintd.so", fingerprint_policy)
        self.assertIn("timeout=-1", fingerprint_policy)

    def test_service_is_on_demand_and_recovers_abnormal_termination(self):
        source = self.read("systemd/user/quickshell-lock.service")
        stage = self.read("scripts/quickshell-lock-stage.sh")
        self.assertIn("ExecStartPre=%h/.config/quickshell/scripts/quickshell-lock-stage.sh", source)
        self.assertIn("ExecStart=/usr/bin/qs --no-duplicate --path %t/quickshell-lock/config/shell.qml", source)
        self.assertIn('RuntimeDirectoryPreserve=restart', source)
        self.assertIn('QUICKSHELL_ROOT/desktop/widgets', stage)
        self.assertIn('QUICKSHELL_ROOT/desktop/nc', stage)
        self.assertIn('QUICKSHELL_ROOT/desktop/icons', stage)
        self.assertIn('RUNTIME_ROOT" != "$EXPECTED_ROOT', stage)
        self.assertNotIn('/home/sejunlee', stage)
        self.assertIn("Environment=QS_DISABLE_FILE_WATCHER=1", source)
        self.assertIn("Environment=QS_DISABLE_CRASH_HANDLER=1", source)
        self.assertIn("Environment=QS_LOCK_MODE=1", source)
        self.assertIn("Environment=QT_IM_MODULE=compose", source)
        self.assertIn("Environment=QT_IM_MODULES=compose", source)
        self.assertIn("Restart=always", source)
        self.assertIn("SuccessExitStatus=10", source)
        self.assertIn("RestartPreventExitStatus=10", source)
        self.assertIn("StartLimitBurst=20", source)
        self.assertIn("KillMode=control-group", source)
        self.assertIn("RuntimeDirectoryPreserve=restart", source)
        self.assertNotIn("[Install]", source)
        self.assertNotIn("WantedBy=", source)
        self.assertNotIn("NoNewPrivileges=", source)

    def test_machine_install_script_is_portable_and_keeps_service_on_demand(self):
        installer = self.read("scripts/installs/install-quickshell-lock.sh")
        pam_installer = self.read("scripts/installs/install-quickshell-lock-pam.sh")
        self.assertIn('readonly SCRIPT_DIR="$(cd --', installer)
        self.assertIn('quickshell-lock-stage.sh', installer)
        self.assertIn('quickshell-lock-blur.sh', installer)
        self.assertIn('[[ ! -x "$STAGE_SCRIPT" ]]', installer)
        self.assertIn('[[ ! -x "$BLUR_SCRIPT" ]]', installer)
        self.assertIn('systemctl --user daemon-reload', installer)
        self.assertIn('systemd-analyze --user verify', installer)
        self.assertNotIn('systemctl --user enable', installer)
        self.assertNotIn('/home/sejunlee', installer + pam_installer)
        self.assertIn('/usr/bin/install -o root -g root -m 0644', pam_installer)

    def test_avatar_sync_keeps_home_private_and_uses_sddm_user_model_path(self):
        source = self.read("scripts/installs/set-user-avatar.sh")
        surface = self.read("lock/LockSurface.qml")
        self.assertIn('LOCK_AVATAR="$HOME_DIR/.face"', source)
        self.assertIn('SDDM_FACES_DIR="/usr/share/sddm/faces"', source)
        self.assertIn('$USER_NAME.face.icon', source)
        self.assertIn('/usr/bin/install -m 0600 --', source)
        self.assertIn('/usr/bin/install -o root -g root -m 0644 --', source)
        self.assertNotIn('ln -s', source)
        self.assertNotIn('setfacl', source)
        self.assertIn("anchors.margins: -1 * surface.uiScale", surface)
        self.assertNotIn("anchors.margins: 2 * surface.uiScale", surface)

    def test_helper_waits_for_compositor_secure_and_has_sleep_handshakes(self):
        source = self.read("scripts/quickshell-lock.sh")
        self.assertIn("ipc prop get lock secure", source)
        self.assertIn("timeout --foreground", source)
        self.assertIn("sync_graphical_environment", source)
        self.assertIn("HYPRLAND_INSTANCE_SIGNATURE", source)
        self.assertIn('systemctl --user import-environment "${names[@]}"', source)
        self.assertIn("prepareForSleep", source)
        self.assertIn("resumeFromSleep", source)
        self.assertNotIn("pgrep", source)
        self.assertNotIn("pidof", source)

    def test_sleep_preparation_has_an_active_time_recovery_guard(self):
        source = self.read("lock/shell.qml")
        self.assertIn("id: sleepSafetyTimer", source)
        self.assertIn("interval: 15000", source)
        self.assertIn("sleepSafetyTimer.restart()", source)
        self.assertIn("root.resumeFromSleep()", source)


class QuickshellLockHelperTests(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.state = pathlib.Path(self.tempdir.name)
        self.bin = self.state / "bin"
        self.bin.mkdir()
        self._write_executable(
            "qs",
            r"""
            #!/bin/bash
            set -eu
            count_file="$LOCK_TEST_DIR/qs-count"
            count=0
            if [[ -r "$count_file" ]]; then read -r count < "$count_file"; fi
            count=$((count + 1))
            printf '%s\n' "$count" > "$count_file"
            if [[ "$*" == *"ipc call lock"* ]]; then
                [[ "${LOCK_TEST_LIFECYCLE:-true}" == "true" ]] && printf 'true\n' || printf 'false\n'
                exit 0
            fi
            case "${LOCK_TEST_MODE:-never}" in
                immediate) printf 'true\n' ;;
                delayed) ((count >= 3)) && printf 'true\n' || printf 'false\n' ;;
                *) printf 'false\n' ;;
            esac
            """,
        )
        self._write_executable(
            "systemctl",
            r"""
            #!/bin/bash
            printf '%s\n' "$*" >> "$LOCK_TEST_DIR/systemctl-log"
            if [[ "$*" == *"is-failed"* ]]; then exit 1; fi
            exit 0
            """,
        )
        self._write_executable("sleep", "#!/bin/bash\nexit 0\n")
        self._write_executable(
            "logger",
            "#!/bin/bash\nprintf '%s\\n' \"$*\" >> \"$LOCK_TEST_DIR/logger-log\"\n",
        )

    def tearDown(self):
        self.tempdir.cleanup()

    def _write_executable(self, name, source):
        path = self.bin / name
        path.write_text(textwrap.dedent(source).lstrip(), encoding="utf-8")
        path.chmod(0o755)

    def run_helper(self, action, mode="never", lifecycle="true"):
        env = os.environ.copy()
        env.update(
            {
                "PATH": f"{self.bin}:/usr/bin:/bin",
                "LOCK_TEST_DIR": str(self.state),
                "LOCK_TEST_MODE": mode,
                "LOCK_TEST_LIFECYCLE": lifecycle,
            }
        )
        return subprocess.run(
            [str(ROOT / "scripts/quickshell-lock.sh"), action],
            env=env,
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )

    def test_already_secure_never_starts_service(self):
        result = self.run_helper("lock", mode="immediate")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.state / "systemctl-log").exists())

    def test_lock_waits_until_secure_after_start(self):
        result = self.run_helper("lock", mode="delayed")
        self.assertEqual(result.returncode, 0, result.stderr)
        log = (self.state / "systemctl-log").read_text(encoding="utf-8")
        self.assertIn("--user start --no-block quickshell-lock.service", log)

    def test_timeout_fails_closed(self):
        result = self.run_helper("lock", mode="never")
        self.assertNotEqual(result.returncode, 0)
        log = (self.state / "logger-log").read_text(encoding="utf-8")
        self.assertIn("timed out before compositor secure confirmation", log)

    def test_sleep_lifecycle_requires_positive_lock_acknowledgement(self):
        accepted = self.run_helper("prepare-sleep", mode="immediate", lifecycle="true")
        self.assertEqual(accepted.returncode, 0, accepted.stderr)

        (self.state / "qs-count").unlink(missing_ok=True)
        rejected = self.run_helper("resume", mode="immediate", lifecycle="false")
        self.assertNotEqual(rejected.returncode, 0)

    def test_resume_clears_sleep_state_before_waiting_for_output_secure(self):
        result = self.run_helper("resume", mode="never", lifecycle="true")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.state / "systemctl-log").exists())


if __name__ == "__main__":
    unittest.main()
