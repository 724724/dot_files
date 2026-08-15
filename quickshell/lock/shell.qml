//@ pragma Env QS_DISABLE_FILE_WATCHER = 1
//@ pragma Env QS_LOCK_MODE = 1
//@ pragma Env QT_IM_MODULE = compose
//@ pragma Env QT_IM_MODULES = compose
//@ pragma AppId org.quickshell.lock
//@ pragma ShellId quickshell-lock
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import QtQuick
import qs.desktop.widgets

// This process is intentionally independent from the running `desktop`
// instance. Its immutable runtime tree includes the shared widget module.
// Starting it immediately requests an ext-session-lock-v1 session lock.
ShellRoot {
    id: root

    // A lock screen must never be hot reloaded. In addition to the early
    // instance pragma above, keep the runtime setting disabled as a second
    // line of defence.
    settings.watchFiles: false

    readonly property bool locked: sessionLock.locked
    // `secure` is stricter than the raw protocol flag during hotplug: it also
    // requires a visible lock surface for every screen currently known to Qt.
    readonly property bool protocolSecure: sessionLock.secure
    readonly property bool surfacesCovered: {
        const screens = Quickshell.screens
        const covered = root.coveredScreens
        if (screens.length === 0)
            return false

        for (let i = 0; i < screens.length; i++) {
            if (!covered.includes(screens[i]))
                return false
        }
        return true
    }
    readonly property bool secure: protocolSecure
        && surfacesCovered
        && !screenSettlePending
    readonly property bool authReady: secure
        && passwordPam.active
        && passwordPam.responseRequired
        && phase === "ready"
        && !sleepPreparing
        && !unlockRequested
    readonly property bool fingerprintActive: secure
        && fingerprintPam.active
        && !fingerprintDisabled
        && !sleepPreparing
        && !unlockRequested
    readonly property date currentDate: wallClock.date
    readonly property string displayUser: {
        const name = Quickshell.env("USER")
        return name ? String(name) : "user"
    }
    property bool defaultAvatarAvailable: false
    readonly property string avatarSource: {
        const configured = String(Quickshell.env("QS_LOCK_AVATAR") || "").trim()
        if (configured !== "") {
            // Keep explicit URLs intact. A plain absolute path is converted to
            // a local URL; a relative override is resolved from the user's
            // home directory instead of the lock service's working directory.
            if (/^[A-Za-z][A-Za-z0-9+.-]*:/.test(configured))
                return configured
            if (configured.startsWith("/"))
                return "file://" + configured

            const configuredHome = String(Quickshell.env("HOME") || "")
            return configuredHome !== ""
                ? "file://" + configuredHome + "/" + configured : ""
        }

        const home = String(Quickshell.env("HOME") || "")
        return root.defaultAvatarAvailable && home !== ""
            ? "file://" + home + "/.face" : ""
    }

    // `phase` contains no PAM message or credential material, so it is safe to
    // expose through the read-only IPC status endpoint.
    property string phase: "covering"
    readonly property bool verificationInProgress: phase === "verifying"
        && !sleepPreparing
        && !unlockRequested
    property string statusText: qsTr("Preparing the lock screen…")
    property bool statusIsError: false
    property string transientStatusText: ""
    property bool transientStatusIsError: false
    readonly property string displayStatusText: transientStatusText !== ""
        ? transientStatusText : statusText
    readonly property bool displayStatusIsError: transientStatusText !== ""
        ? transientStatusIsError : statusIsError
    property int failureCount: 0
    property int fingerprintFailureCount: 0
    property int clearRevision: 0
    property int shakeRevision: 0
    property int securityEpoch: 0
    property int passwordEpoch: -1
    property int fingerprintEpoch: -1
    property int passwordRetryDelay: 750
    property int fingerprintRetryDelay: 1200
    property string fingerprintState: "idle"
    property bool fingerprintDisabled: false
    property int fingerprintErrorRetries: 0
    readonly property int maxFingerprintErrorRetries: 3
    property var coveredScreens: []
    property bool screenSettlePending: false
    property bool sleepPreparing: false
    property bool unlockRequested: false
    property bool unlockAnimating: false

    function setStatus(nextPhase, text, isError) {
        root.phase = nextPhase
        root.statusText = text
        root.statusIsError = isError
    }

    function showTransientStatus(text, isError, duration) {
        root.transientStatusText = text
        root.transientStatusIsError = isError
        transientStatusTimer.interval = Math.max(250, Number(duration) || 1800)
        transientStatusTimer.restart()
    }

    function dismissTransientStatus() {
        transientStatusTimer.stop()
        root.transientStatusText = ""
        root.transientStatusIsError = false
    }

    function clearSecrets() {
        // Each WlSessionLockSurface watches this revision and clears its own
        // local TextInput. Passwords never become a shared QML property.
        root.clearRevision++
    }

    function surfaceShown(outputScreen) {
        if (!outputScreen)
            return

        // WlSessionLockSurface.screen and Quickshell.screens expose the same
        // QuickshellTracked wrapper for a QScreen. Object identity keeps an old
        // deleteLater surface distinct from a replacement using the same
        // connector name.
        const next = root.coveredScreens.slice()
        next.push(outputScreen)
        root.coveredScreens = next
        root.maybeFinishScreenSettle()
    }

    function surfaceRemoved(outputScreen) {
        const next = root.coveredScreens.slice()
        const index = next.indexOf(outputScreen)
        if (index >= 0) {
            next.splice(index, 1)
            root.coveredScreens = next
        }
        root.maybeFinishScreenSettle()
    }

    function maybeFinishScreenSettle() {
        if (root.screenSettlePending
                && root.protocolSecure
                && root.surfacesCovered
                && !root.unlockRequested) {
            screenSettleTimer.restart()
        }
    }

    function invalidateAuthenticationForScreens() {
        if (!root.locked || root.unlockRequested)
            return

        root.securityEpoch++
        root.screenSettlePending = true
        root.clearSecrets()
        passwordRetryTimer.stop()
        fingerprintRetryTimer.stop()
        screenSettleTimer.stop()

        if (passwordPam.active)
            passwordPam.abort()
        if (fingerprintPam.active)
            fingerprintPam.abort()

        root.fingerprintState = "waiting-for-surface"
        root.setStatus("covering", qsTr("Securing connected displays…"), false)
        console.info("QS_LOCK screens changed epoch=" + root.securityEpoch
            + " screenCount=" + Quickshell.screens.length)
        root.maybeFinishScreenSettle()
    }

    function prepareForSleep(): bool {
        // Repeated calls from overlapping lid/logind hooks are harmless. The
        // first successful call already released both PAM conversations.
        if (root.sleepPreparing)
            return true

        if (!root.locked || !root.secure || root.unlockRequested) {
            console.info("QS_LOCK sleep prepare result=rejected locked=" + root.locked
                + " secure=" + root.secure)
            return false
        }

        root.sleepPreparing = true
        sleepSafetyTimer.restart()
        root.securityEpoch++
        root.clearSecrets()
        passwordRetryTimer.stop()
        fingerprintRetryTimer.stop()
        screenSettleTimer.stop()

        // PamContext.abort() synchronously disconnects the active conversation
        // and schedules its PAM subprocess for teardown. Returning to Qt's event
        // loop completes that teardown before the caller's subsequent logind
        // suspend transaction.
        if (passwordPam.active)
            passwordPam.abort()
        if (fingerprintPam.active)
            fingerprintPam.abort()

        root.fingerprintState = "sleep-preparing"
        root.setStatus("sleep-preparing", qsTr("Preparing for sleep…"), false)
        console.info("QS_LOCK sleep prepare result=ready epoch=" + root.securityEpoch)
        return true
    }

    function resumeFromSleep(): bool {
        if (!root.locked || root.unlockRequested) {
            console.info("QS_LOCK sleep resume result=rejected locked=" + root.locked)
            return false
        }

        // Idempotent: a duplicate resume notification must not invalidate a
        // newly started authentication conversation.
        if (!root.sleepPreparing) {
            sleepSafetyTimer.stop()
            return true
        }

        root.sleepPreparing = false
        sleepSafetyTimer.stop()
        root.securityEpoch++
        root.clearSecrets()
        console.info("QS_LOCK sleep resume result=ready epoch=" + root.securityEpoch
            + " secure=" + root.secure)

        if (root.secure && root.surfacesCovered) {
            root.startPasswordPam()
            root.startFingerprintPam()
        } else {
            root.fingerprintState = "waiting-for-secure"
            root.setStatus("covering", qsTr("Verifying display security after wake…"), false)
            if (root.protocolSecure)
                root.screenSettlePending = true
            root.maybeFinishScreenSettle()
        }
        return true
    }

    function startPasswordPam() {
        if (!root.secure || root.sleepPreparing || root.unlockRequested || passwordPam.active)
            return

        root.passwordEpoch = root.securityEpoch
        root.setStatus("starting-auth", qsTr("Preparing password authentication…"), false)
        if (!passwordPam.start()) {
            root.clearSecrets()
            root.setStatus("service-error", qsTr("Password authentication is unavailable. Retrying…"), true)
            root.passwordRetryDelay = 2000
            passwordRetryTimer.restart()
        }
    }

    function schedulePasswordRetry(delay, text, isError) {
        if (root.sleepPreparing || root.unlockRequested)
            return

        root.clearSecrets()
        root.passwordRetryDelay = delay
        root.setStatus(isError ? "service-error" : "retry-wait", text, isError)
        passwordRetryTimer.restart()
    }

    function startFingerprintPam() {
        if (!root.secure
                || root.fingerprintDisabled
                || root.sleepPreparing
                || root.unlockRequested
                || fingerprintPam.active) {
            return
        }

        root.fingerprintEpoch = root.securityEpoch
        root.fingerprintState = "starting"
        if (!fingerprintPam.start()) {
            root.handleFingerprintError("start-failed")
        }
    }

    function scheduleFingerprintRetry(delay, nextState) {
        if (root.fingerprintDisabled || root.sleepPreparing || root.unlockRequested)
            return

        root.fingerprintState = nextState
        root.fingerprintRetryDelay = delay
        fingerprintRetryTimer.restart()
    }

    function disableFingerprint(reason) {
        if (root.fingerprintDisabled)
            return

        root.fingerprintDisabled = true
        root.fingerprintState = "disabled"
        fingerprintRetryTimer.stop()
        if (fingerprintPam.active)
            fingerprintPam.abort()
        console.info("QS_LOCK fingerprint disabled reason=" + reason)
    }

    function handleFingerprintError(reason) {
        if (root.fingerprintDisabled || root.sleepPreparing || root.unlockRequested)
            return

        root.fingerprintFailureCount++
        if (root.fingerprintErrorRetries >= root.maxFingerprintErrorRetries) {
            root.disableFingerprint(reason + "-retry-limit")
            return
        }

        const delay = 1000 * Math.pow(2, root.fingerprintErrorRetries)
        root.fingerprintErrorRetries++
        console.info("QS_LOCK fingerprint retry reason=" + reason
            + " attempt=" + root.fingerprintErrorRetries
            + " delayMs=" + delay)
        root.scheduleFingerprintRetry(delay, "service-error")
    }

    function showFingerprintScanFailure() {
        // Some readers emit the same PAM error message many times for one
        // rejected touch. Give immediate feedback once, without turning that
        // message burst into a continuous shake animation.
        if (fingerprintFeedbackCooldown.running)
            return

        root.shakeRevision++
        root.showTransientStatus(qsTr("Fingerprint not recognized"), true, 2200)
        fingerprintFeedbackCooldown.restart()
    }

    function submitPassword(response) {
        // Do not start or complete authentication until the compositor has
        // explicitly confirmed that every output is covered.
        if (!root.authReady || typeof response !== "string" || response.length === 0)
            return

        root.dismissTransientStatus()
        root.setStatus("verifying", qsTr("Checking…"), false)
        // Publish the non-sensitive phase first so each surface keeps its
        // bullet-only surrogate when clearRevision synchronously erases the
        // actual TextInput. The credential is still cleared before PAM sees it.
        root.clearSecrets()
        passwordPam.respond(response)

        // Drop this function's last explicit reference immediately. QML/JS
        // cannot promise memory zeroisation, but no long-lived property keeps
        // the response and every TextInput has already been cleared.
        response = ""
    }

    function completeUnlock(method) {
        // Success is not sufficient on its own: re-check both protocol states
        // in the same event-loop turn before sending unlock_and_destroy.
        if (root.sleepPreparing || root.unlockRequested || !root.locked || !root.secure)
            return

        root.unlockRequested = true
        root.unlockAnimating = true
        sleepSafetyTimer.stop()
        root.clearSecrets()
        root.dismissTransientStatus()
        root.setStatus("unlocking", qsTr("Unlocking…"), false)
        console.info("QS_LOCK unlock requested method=" + method)

        // Cancel the other independent PAM stack. `unlockRequested` is already
        // true, so completion callbacks caused by abort cannot schedule work.
        if (passwordPam.active)
            passwordPam.abort()
        if (fingerprintPam.active)
            fingerprintPam.abort()

        // Keep ext-session-lock held while every surface plays the symmetric
        // exit motion. The timer performs one final coverage/security check
        // before it reaches the compositor's public unlock property.
        unlockAnimationTimer.restart()
    }

    LockWallpaperService {
        id: lockWallpaper
    }

    Process {
        id: defaultAvatarProbe
        command: ["/usr/bin/find", String(Quickshell.env("HOME") || ""),
                  "-maxdepth", "1", "-name", ".face", "-readable",
                  "-print", "-quit"]
        running: String(Quickshell.env("HOME") || "") !== ""
        stdout: StdioCollector {
            onStreamFinished: {
                const home = String(Quickshell.env("HOME") || "")
                root.defaultAvatarAvailable = text.trim() === home + "/.face"
            }
        }
        stderr: StdioCollector {}
    }

    LockMediaService {
        id: lockMedia
        detailedVisible: enabled
        enabled: WidgetsService.lockMediaEnabled
    }

    LockAudioEqService {
        id: lockEqualizer
        media: lockMedia
        enabled: WidgetsService.lockMediaEnabled && root.locked && !root.sleepPreparing && !root.unlockRequested
    }

    SystemClock {
        id: wallClock
        enabled: true
        precision: SystemClock.Seconds
    }

    // Password and fingerprint use independent PAM stacks. pam_fprintd cannot
    // safely share a sequential stack with an interactive password prompt when
    // both methods must remain available at the same time.
    PamContext {
        id: passwordPam
        config: "quickshell-lock-password"

        onPamMessage: {
            if (!root.secure || root.sleepPreparing || root.unlockRequested)
                return

            if (passwordPam.responseRequired) {
                root.setStatus("ready", qsTr("Ready"), passwordPam.messageIsError)
            } else if (passwordPam.messageIsError) {
                // Never reflect arbitrary PAM text into IPC or logs.
                root.setStatus("verifying", qsTr("Checking your password…"), true)
            }
        }

        onError: {
            if (root.sleepPreparing || root.unlockRequested)
                return

            // `completed(PamResult.Error)` follows this signal. Stay locked and
            // let the completion handler schedule a fresh PAM conversation.
            root.clearSecrets()
            root.setStatus("service-error", qsTr("Password authentication encountered an error."), true)
        }

        onCompleted: result => {
            root.clearSecrets()

            if (root.sleepPreparing || root.unlockRequested)
                return

            if (result === PamResult.Success) {
                console.info("QS_LOCK auth method=password result=success")
                if (root.locked
                        && root.secure
                        && root.passwordEpoch === root.securityEpoch) {
                    root.completeUnlock("password")
                } else {
                    // Never cache a successful login across a monitor/security
                    // epoch boundary. Require a completely new conversation.
                    root.schedulePasswordRetry(1000, qsTr("Display security changed. Please try again."), true)
                }
                return
            }

            if (result === PamResult.Failed) {
                console.info("QS_LOCK auth method=password result=failed")
                root.failureCount++
                // pam_unix deliberately withholds a failed result for roughly
                // two seconds. Do not weaken that security delay, but restart
                // the next conversation promptly and keep the error visible on
                // an independent timer so input is not blocked for 900ms more.
                root.shakeRevision++
                root.showTransientStatus(qsTr("Incorrect password"), true, 2200)
                root.schedulePasswordRetry(100, qsTr("Ready to try again"), false)
            } else if (result === PamResult.MaxTries) {
                console.info("QS_LOCK auth method=password result=max-tries")
                root.failureCount++
                root.showTransientStatus(qsTr("Too many attempts. Please wait."), true, 3000)
                root.schedulePasswordRetry(3000, qsTr("Too many attempts. Please wait."), true)
            } else {
                console.info("QS_LOCK auth method=password result=error")
                root.schedulePasswordRetry(2000, qsTr("Preparing password authentication again…"), true)
            }
        }
    }

    PamContext {
        id: fingerprintPam
        config: "quickshell-lock-fingerprint"

        onPamMessage: {
            if (!root.secure
                    || root.fingerprintDisabled
                    || root.sleepPreparing
                    || root.unlockRequested) {
                return
            }

            // The fingerprint-only policy must never ask the UI for a value.
            // A prompt proves the root-owned policy is wrong; disable this
            // method for the session without sending an empty or password
            // response, while leaving password authentication available.
            if (fingerprintPam.responseRequired) {
                root.disableFingerprint("unexpected-prompt")
                return
            }

            if (fingerprintPam.messageIsError) {
                root.fingerprintState = "message-error"
                // pam_fprintd also marks harmless guidance such as "place
                // your finger again" as an error. Only map definitive
                // rejection messages to the user-facing failure animation.
                const message = String(fingerprintPam.message || "").toLowerCase()
                if (message.includes("failed to match")
                        || message.includes("not recognized")
                        || message.includes("no match")) {
                    root.showFingerprintScanFailure()
                }
            } else {
                root.fingerprintState = "scanning"
            }
        }

        onError: {
            if (root.fingerprintDisabled || root.sleepPreparing || root.unlockRequested)
                return
            root.fingerprintState = "service-error"
        }

        onCompleted: result => {
            if (root.fingerprintDisabled || root.sleepPreparing || root.unlockRequested)
                return

            if (result === PamResult.Success) {
                console.info("QS_LOCK auth method=fingerprint result=success")
                if (root.locked
                        && root.secure
                        && root.fingerprintEpoch === root.securityEpoch) {
                    root.completeUnlock("fingerprint")
                } else {
                    root.scheduleFingerprintRetry(1000, "security-changed")
                }
                return
            }

            if (result === PamResult.Failed) {
                console.info("QS_LOCK auth method=fingerprint result=failed")
                root.fingerprintFailureCount++
                root.shakeRevision++
                root.showTransientStatus(qsTr("Fingerprint not recognized"), true, 2200)
                root.disableFingerprint("authentication-failed")
            } else if (result === PamResult.MaxTries) {
                console.info("QS_LOCK auth method=fingerprint result=max-tries")
                root.fingerprintFailureCount++
                root.shakeRevision++
                root.showTransientStatus(
                    qsTr("Too many fingerprint attempts. Use your password."), true, 3000)
                root.disableFingerprint("max-tries")
            } else {
                console.info("QS_LOCK auth method=fingerprint result=error")
                root.handleFingerprintError("pam-error")
            }
        }
    }

    Timer {
        id: fingerprintFeedbackCooldown
        interval: 1000
        repeat: false
    }

    Timer {
        id: transientStatusTimer
        interval: 1800
        repeat: false
        onTriggered: root.dismissTransientStatus()
    }

    Timer {
        id: passwordRetryTimer
        interval: root.passwordRetryDelay
        repeat: false
        onTriggered: {
            if (root.secure && !root.sleepPreparing && !root.unlockRequested)
                root.startPasswordPam()
            else if (!root.sleepPreparing && !root.unlockRequested)
                root.setStatus("covering", qsTr("Rechecking display security…"), false)
        }
    }

    Timer {
        id: fingerprintRetryTimer
        interval: root.fingerprintRetryDelay
        repeat: false
        onTriggered: {
            if (root.secure
                    && !root.fingerprintDisabled
                    && !root.sleepPreparing
                    && !root.unlockRequested) {
                root.startFingerprintPam()
            } else if (!root.fingerprintDisabled
                    && !root.sleepPreparing
                    && !root.unlockRequested) {
                root.fingerprintState = "waiting-for-secure"
            }
        }
    }

    Timer {
        id: screenSettleTimer
        interval: 100
        repeat: false
        onTriggered: {
            if (!root.screenSettlePending
                    || !root.protocolSecure
                    || !root.surfacesCovered
                    || root.unlockRequested) {
                return
            }

            root.screenSettlePending = false
            console.info("QS_LOCK secure entered reason=screen-settle epoch=" + root.securityEpoch
                + " screenCount=" + Quickshell.screens.length)
            statusIpc.secured()
            root.startPasswordPam()
            root.startFingerprintPam()
        }
    }

    Timer {
        id: sleepSafetyTimer
        interval: 15000
        repeat: false
        onTriggered: {
            // CLOCK_MONOTONIC-backed Qt timers do not advance while the
            // machine is suspended. This fires only if suspend was cancelled,
            // or after wake when hypridle's after_sleep callback was lost.
            if (root.sleepPreparing && root.locked && !root.unlockRequested) {
                console.info("QS_LOCK sleep safety resume reason=callback-timeout")
                root.resumeFromSleep()
            }
        }
    }

    Timer {
        id: unlockAnimationTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!root.unlockRequested)
                return

            if (root.sleepPreparing || !root.locked || !root.secure) {
                console.info("QS_LOCK unlock animation result=security-lost")
                Qt.exit(1)
                return
            }

            // Quickshell 0.3 exposes unlock through the writable `locked`
            // property. Its C++ `unlock` slot is private at runtime.
            sessionLock.locked = false
        }
    }

    Timer {
        id: quitTimer
        interval: 250
        repeat: false
        onTriggered: Qt.exit(10)
    }

    WlSessionLock {
        id: sessionLock
        locked: true

        LockSurface {
            controller: root
            wallpaper: lockWallpaper
            media: lockMedia
            equalizer: lockEqualizer
        }

        onSecureStateChanged: {
            root.securityEpoch++
            root.clearSecrets()

            if (sessionLock.secure) {
                if (root.surfacesCovered) {
                    root.screenSettlePending = false
                    console.info("QS_LOCK secure entered reason=protocol epoch=" + root.securityEpoch
                        + " screenCount=" + Quickshell.screens.length)
                    statusIpc.secured()
                    root.startPasswordPam()
                    root.startFingerprintPam()
                } else {
                    root.screenSettlePending = true
                    root.setStatus("covering", qsTr("Preparing every display…"), false)
                    root.maybeFinishScreenSettle()
                }
            } else if (sessionLock.locked && !root.unlockRequested) {
                console.info("QS_LOCK secure left epoch=" + root.securityEpoch
                    + " screenCount=" + Quickshell.screens.length)
                passwordRetryTimer.stop()
                fingerprintRetryTimer.stop()
                screenSettleTimer.stop()

                if (passwordPam.active)
                    passwordPam.abort()
                if (fingerprintPam.active)
                    fingerprintPam.abort()

                root.screenSettlePending = false
                root.fingerprintState = "waiting-for-secure"
                root.setStatus("covering", qsTr("Verifying that every display is secure…"), false)
            }
        }

        onLockStateChanged: {
            if (sessionLock.locked)
                return

            if (root.unlockRequested) {
                quitTimer.restart()
            } else {
                // A compositor "finished" event or lock refusal is never a
                // successful unlock. Exit non-zero so the user unit can
                // reacquire instead of leaving an insecure zombie instance
                // that makes the lock helper wait forever.
                console.info("QS_LOCK lock state=lost result=failure")
                root.clearSecrets()
                if (passwordPam.active)
                    passwordPam.abort()
                if (fingerprintPam.active)
                    fingerprintPam.abort()
                Qt.exit(1)
            }
        }
    }

    Connections {
        target: Quickshell

        function onScreensChanged() {
            root.invalidateAuthenticationForScreens()
        }
    }

    // Status is read-only. The only mutating calls suspend/resume PAM
    // conversations; neither can unlock, quit, reload, crash, accept a
    // password, or execute an arbitrary command.
    IpcHandler {
        id: statusIpc
        target: "lock"

        readonly property bool locked: root.locked
        readonly property bool secure: root.secure
        readonly property bool ready: root.authReady
        readonly property bool fingerprintActive: root.fingerprintActive
        readonly property bool fingerprintDisabled: root.fingerprintDisabled
        readonly property bool sleepPreparing: root.sleepPreparing
        readonly property string state: root.phase
        readonly property string fingerprintState: root.fingerprintState
        readonly property int failures: root.failureCount
        readonly property int fingerprintFailures: root.fingerprintFailureCount
        readonly property int fingerprintErrorRetries: root.fingerprintErrorRetries
        readonly property int screenCount: Quickshell.screens.length

        signal secured()
        signal authenticationReady()

        function status(): string {
            return JSON.stringify({
                locked: root.locked,
                secure: root.secure,
                ready: root.authReady,
                fingerprintActive: root.fingerprintActive,
                fingerprintDisabled: root.fingerprintDisabled,
                sleepPreparing: root.sleepPreparing,
                state: root.phase,
                fingerprintState: root.fingerprintState,
                failures: root.failureCount,
                fingerprintFailures: root.fingerprintFailureCount,
                fingerprintErrorRetries: root.fingerprintErrorRetries,
                screenCount: Quickshell.screens.length
            })
        }

        function prepareForSleep(): bool {
            return root.prepareForSleep()
        }

        function resumeFromSleep(): bool {
            return root.resumeFromSleep()
        }
    }

    onAuthReadyChanged: {
        if (root.authReady)
            statusIpc.authenticationReady()
    }

    // sessionLock.secure changes before this composite binding is guaranteed
    // to have re-evaluated. Start PAM from the effective-security transition,
    // otherwise the initial protocol callback can observe secure=false once
    // and leave the password field permanently disabled.
    onSecureChanged: {
        if (!root.secure
                || !root.locked
                || root.sleepPreparing
                || root.unlockRequested) {
            return
        }

        root.startPasswordPam()
        root.startFingerprintPam()
    }
}
