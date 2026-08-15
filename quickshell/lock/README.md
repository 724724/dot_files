# Quickshell session lock

This is a standalone Quickshell 0.3.0 process. It has no control IPC to the
running `desktop` process, but it reuses the widget renderers from
`desktop/widgets`. A small validated JSON store synchronizes only explicitly
linked Reminder lists between the two independent processes.

## Installing on another laptop

After placing these dotfiles at `~/.config/quickshell`, install the lock's
machine-local pieces from a terminal:

```sh
~/.config/quickshell/scripts/installs/install-all.sh
```

The aggregate installer sets up every compatible machine-local component in
these dotfiles. Its lock step checks the runtime commands, copies the user unit to
`~/.config/systemd/user/quickshell-lock.service`, installs both PAM policies as
root-owned mode-`0644` files, reloads the user systemd manager, and verifies the
unit. The aggregate installer validates `sudo` once for PAM, browser-policy,
and optional SDDM-avatar installation. The lock service is static and starts on
demand through the helper, so it must not be enabled at boot.

Quickshell 0.3 scans only below a configuration entrypoint. Immediately before
the lock starts, the user unit therefore stages an immutable private copy of
`lock/` plus `desktop/widgets`, `desktop/nc`, and `desktop/icons` under
`%t/quickshell-lock/config`. The lock entrypoint uses the supported
`qs.desktop.widgets` root import from that tree. This is a generated runtime
snapshot, not another hand-maintained widget list; the next unlocked start
automatically includes newly added widgets. It is preserved unchanged across a
crash restart and removed after authenticated unlock.

On Arch Linux the relevant packages are `quickshell`, `hyprland`, `hypridle`,
`pam`, `fprintd`, `imagemagick`, `grim`, `jq`, `playerctl`, `python`,
`python-numpy`, `libpulse`, and `util-linux`. Enroll a fingerprint separately
with `fprintd-enroll`; password authentication still works on a machine without
an enrolled reader.

The Hyprland configuration must keep
`misc:allow_session_lock_restore = true`. Point `hypridle`'s `lock_cmd` to
`quickshell-lock.sh lock`, `before_sleep_cmd` to `quickshell-lock.sh
prepare-sleep`, and its post-resume path to `quickshell-lock.sh resume` (or to a
lid manager that calls that helper). The graphical-session autostart must import
`WAYLAND_DISPLAY` into the user systemd manager before the first lock request.
These settings are already present when this repository's accompanying
Hyprland dotfiles are copied as a whole.

Start it with:

```sh
~/.config/quickshell/scripts/quickshell-lock.sh lock
```

Use this systemd-supervised helper for operation and recovery tests. Do not run
the lock directly with `qs`: the user unit supplies the crash-handler policy and
is responsible for reacquiring a lock after an abnormal process exit.

Launching the configuration immediately requests an `ext-session-lock-v1`
lock. The QML entrypoint also forces `QS_DISABLE_FILE_WATCHER=1`; runtime file
watching is disabled a second time through `ShellRoot.settings.watchFiles`.

The lock process forces Qt's local `compose` input backend and requests Latin
input for the password field. It therefore bypasses fcitx5 and uses the
Hyprland `us` keyboard layout for direct English, number, and symbol input even
when fcitx5 is currently in Korean mode. This is process-local: the input-method
state used by other applications is not changed.

The visual layout follows the linked Figma direction: the current local
wallpaper is blurred and dimmed over the opaque security colour, a translucent
clock/media panel occupies the left side, and the password capsule remains in a
separate high-contrast area. All visible lock text uses `SF Pro Display` and an
English locale. Wallpaper loading is decorative and asynchronous, so a missing
image never delays or weakens the first secure frame.

The user unit captures each active output immediately before starting the lock
client. The running desktop process publishes only its sanitized output names
to the per-user runtime directory; the capture helper reads that list first and
uses Hyprland IPC only as a fallback. A quarter-scale JPEG is captured inside
systemd's private `%t/quickshell-lock` runtime directory. This capture is the
only image step that blocks lock acquisition. ImageMagick then strongly blurs
it once on the CPU in `ExecStartPost`, in parallel with QML startup; the blurred
manifest is atomically published and fades in when ready. The resulting
mode-`0600` image keeps colour and gradients smooth while making text and window
contents unrecognizable. The lock renders it as a single ordinary texture, with
no persistent GPU blur effect.
The runtime directory is preserved only across crash recovery and is deleted by
systemd after a final stop or authenticated unlock. If capture fails, or a new
monitor appears after locking, the ordinary wallpaper remains the fallback and
the exact failed capture stage is recorded under the
`quickshell-lock-capture` journal tag.

The panel and authentication controls materialize with short, critically
damped entrance motion over the already-opaque first frame. After successful
authentication they dematerialize along the same spatial path while the
session-lock protocol remains held; the compositor is released only after a
final security check at the end of the 300 ms motion. Authentication is never
delayed by the entrance animation. A rejected password or fingerprint gives the
password capsule a small horizontal shake; errors appear inside the capsule
instead of occupying a permanent status row below it.

To use one account icon for both this lock and the active SDDM theme, run:

```sh
~/.config/quickshell/scripts/installs/set-user-avatar.sh ~/Pictures/avatar.png
```

The script keeps the canonical Quickshell image private at `~/.face` (mode
`0600`) and installs a cropped, root-owned mode-`0644` greeter copy at
`/usr/share/sddm/faces/<username>.face.icon`. SDDM runs outside the user's
session, so intentionally copying the public avatar avoids granting its greeter
access to the home directory. After replacing `~/.face` manually, run
`scripts/installs/set-user-avatar.sh` without an argument to refresh only the
SDDM copy. Changes appear on the next lock and the next SDDM greeter start. To
use another local
path or URL only in the lock, set `QS_LOCK_AVATAR` in the user unit environment.
Missing or unreadable images fall back to the built-in dot badge.

When Lock Screen media is enabled and something is playing, a compact media
pill appears at the bottom of the clock panel. Clicking it expands the local
dynamic island; clicking elsewhere on the panel collapses it. The island width
adapts from 430 to 720 logical pixels and contains the timeline plus
previous/play-next controls, but deliberately has no stem separator or pitch
controls. In the desktop Widgets editor, enter Lock Screen mode and click the
media pill preview to persistently show or hide this region. Disabling it also
stops the lock-local media and sink-monitor EQ processes. The implementation
does not import the desktop bar or create another layer-shell window, and
systemd's cgroup cleanup owns every child process.

## Lock Screen widgets

Open the desktop Widgets board, enter edit mode with the pencil, then use the
round lock button at the top-right. The preview switches to the same 60/40
widget geometry used by the real lock, presented as a centered opaque editing
canvas so the desktop cannot reduce placement contrast. The existing `+`
gallery now adds to the Lock Screen; drag cards between slots and use their red
close badge to remove them. Switching the lock button off returns to the
desktop board. Right-click any Lock Screen card to open its anchored context
menu. Reminder cards expose `Edit List`; the other built-in cards expose the
same type-specific `Settings` editor used by the desktop board. A size change
that cannot fit the bounded grid is rejected without corrupting the saved
layout.

The Lock Screen layout is a fixed 6×3 grid saved at
`$XDG_STATE_HOME/quickshell/lock-widgets.json` (or
`~/.local/state/quickshell/lock-widgets.json`). It never scrolls. The clock and
the full expanded media-card footprint are separate, permanently reserved
regions, so a widget cannot cover either one even when media is hidden. A
layout larger than 6×3 or a card for which no contiguous region remains is
rejected with an explanation instead of being clipped or overlapped.

`WidgetFrame` and the lock preview both resolve widget content through the same
`<Type>Widget.qml` naming convention. Consequently a widget added to the normal
Widgets gallery/service becomes renderable on the lock without adding another
lock-specific type switch. Generic widget pointer input and persistence remain
disabled. The lock exposes only three reviewed interaction capabilities:

- Note and News cards accept a bounded numeric wheel delta for their existing
  read-only viewport. Raw pointer events, strings, URLs, and method names never
  cross that bridge.
- A linked Reminder uses the separate process-free
  `LockRemindersWidget.qml`, not the generic desktop input component. It may add,
  rename, or toggle an item through fixed `listId`/`itemId` service methods.
- Every other current or future widget remains display-only until a dedicated
  lock capability is reviewed and added.

Here, display-only describes the input boundary: generic widgets cannot receive
pointer/keyboard actions or persistence calls. Their trusted local QML is still
instantiated to render data. The lock marks known process-heavy widgets
passive, including Calendar, Stocks, YouTube, and Spotify. Weather and News are
the only network data widgets allowed to refresh in the lock: both first read a
shared cache under `$XDG_STATE_HOME/quickshell` (or
`~/.local/state/quickshell`) and fetch only when that entry is missing or at
least one hour old. Opening the lock therefore does not trigger another request
while the cache is fresh. Newly added widget code must still be reviewed like
any other executable dotfile; untrusted Reminder/password text is never passed
to refresh paths.

To choose a Reminder list, right-click its card in Lock Screen edit mode, choose
`Edit List`, then select an existing Reminder list from any desktop Widgets board.
The link uses a permanent random `listId`, so deleting and later recreating a
desktop widget cannot silently attach the lock card to the wrong list. The lock
keeps its own layout size while title, colour, icon, and items follow the chosen
source. If that source disappears, the last validated snapshot remains visible
but editing is disabled.

Reminder text is data only: it is bounded, control and bidirectional formatting
characters are removed, and it is never interpolated into a command, URL, QML
source, or executable path. Add and rename drafts commit only on Enter. Escape,
clicking the password field, or any other focus loss discards the draft before
password focus is restored. This prevents credential keystrokes from being
saved as a Reminder. The independent lock process loads a validated snapshot of
the shared layout at startup; geometry changes therefore appear on the next lock
session.

A wrong password is normally reported after about two seconds because
`pam_unix` deliberately delays failure results. That security delay remains in
place. The submitted credential is immediately erased, but a bounded dot-only
length surrogate remains visible while Enter is disabled and PAM is working.
The old additional 900 ms UI lockout was removed: a new PAM prompt is prepared
after 100 ms while the independent `Incorrect password` notice remains visible
long enough to read.

The only IPC target is `lock`. It contains read-only status properties and a
status function. Its only state-changing calls prepare and restore PAM around
system sleep; it deliberately has no unlock, quit, crash, reload, password, or
command-execution method.

```sh
qs ipc -c lock prop get lock secure
qs ipc -c lock prop get lock ready
qs ipc -c lock prop get lock screenCount
qs ipc -c lock call lock status
qs ipc -c lock wait lock secured
qs ipc -c lock wait lock authenticationReady
qs ipc -c lock call lock prepareForSleep
qs ipc -c lock call lock resumeFromSleep
```

`secure=true` means the compositor has confirmed that all connected screens are
covered. Callers that suspend the machine must observe this state before
suspending; process creation alone is not a security handshake.

`prepareForSleep()` succeeds only while the session is both locked and secure.
It invalidates in-flight authentication, clears every password field, stops
retries, and aborts both PAM conversations so pam_fprintd releases its device
claim before suspend. `resumeFromSleep()` starts both conversations from a new
security epoch after output coverage is ready. Both calls are idempotent and
neither contains an unlock path. The `sleepPreparing` status property exposes
their current lifecycle state. A 15-second active-time safety timer restores
authentication if suspend is cancelled or the post-resume callback is lost;
Qt's monotonic timer does not consume that interval while the machine sleeps.

Authentication uses two independent, root-owned PAM policies so fingerprint and
password authentication can remain available concurrently:

- `/etc/pam.d/quickshell-lock-password`
- `/etc/pam.d/quickshell-lock-fingerprint`

Both files must be installed before a live test. Only `PamResult.Success` from
either policy, received in the same security epoch while both `locked` and
`secure` are still true, can set `WlSessionLock.locked = false`. All other results
leave the session locked and start a fresh conversation for that authentication
method. A screen hotplug or other loss of the compositor secure handshake aborts
both conversations and invalidates any in-flight success.

After an authenticated unlock, the process exits with status `10`, the only
status the user unit treats as a successful, non-restartable completion. Exit
`0` remains restartable so `qs kill -c lock` cannot disable lock supervision.

The fingerprint policy must never request a text response. An unexpected prompt
disables fingerprint for the rest of that lock session without sending any
response; password authentication remains available. Fingerprint `Failed` and
`MaxTries` results also disable it for the session. Service errors retry at most
three times with exponential delays before disabling it. Suspend/resume does not
reset this disabled state.

Non-secret lifecycle events use the structured `QS_LOCK` log prefix. They cover
surface creation/removal, secure-state entry/loss, authentication result, and
the unlock request. Password text and PAM responses are never logged.

If this process is killed while locked, a conforming compositor keeps the
session locked. That is fail-closed, but recovery must be tested before replacing
the existing locker because the screen can otherwise remain inoperable.
