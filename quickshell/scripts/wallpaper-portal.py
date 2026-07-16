#!/usr/bin/env python3
"""Wallpaper portal backend for the Hyprland quickshell desktop.

xdg-desktop-portal-hyprland does not implement the Wallpaper portal.  This
small backend receives the local URI prepared by xdg-desktop-portal, stores a
durable copy, and delegates the actual update to Hyprland's wallpaper.sh.  That
script updates both awww and the GNOME background keys watched by Mission
Control.
"""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import traceback
import urllib.parse

from gi.repository import Gio, GLib


BUS_NAME = "org.freedesktop.impl.portal.desktop.hyprqs"
OBJECT_PATH = "/org/freedesktop/portal/desktop"
WALLPAPER_SH = Path(os.path.expanduser("~/.config/hypr/scripts/wallpaper.sh"))
WALLPAPER_DIR = Path(
    os.path.expanduser(
        os.path.join(
            os.environ.get("XDG_DATA_HOME", "~/.local/share"),
            "backgrounds",
            "quickshell",
        )
    )
)
RESIZE_CHOICES = (
    ("crop", "Fill Screen", "Fill the screen and crop the edges if needed"),
    ("fit", "Fit to Screen", "Show the whole image with padding if needed"),
    ("stretch", "Stretch to Fill Screen", "Fill without preserving the aspect ratio"),
    ("no", "Center", "Keep the original size and center the image"),
)
PADDING_COLOR_MODES = {"fit", "no"}

INTROSPECTION_XML = """
<node>
  <interface name="org.freedesktop.impl.portal.Wallpaper">
    <method name="SetWallpaperURI">
      <arg type="o" name="handle" direction="in"/>
      <arg type="s" name="app_id" direction="in"/>
      <arg type="s" name="parent_window" direction="in"/>
      <arg type="s" name="uri" direction="in"/>
      <arg type="a{sv}" name="options" direction="in"/>
      <arg type="u" name="response" direction="out"/>
    </method>
  </interface>
</node>
"""


def log(message: str) -> None:
    print(f"wallpaper-portal: {message}", file=sys.stderr, flush=True)


def run_gsettings(key: str, fallback: str) -> str:
    try:
        result = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.background", key],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return fallback

    if result.returncode != 0:
        return fallback
    value = result.stdout.strip().strip("'")
    return value or fallback


def current_resize_mode() -> str:
    option = run_gsettings("picture-options", "zoom")
    return {
        "scaled": "fit",
        "stretched": "stretch",
        "centered": "no",
        "none": "no",
        "wallpaper": "no",
    }.get(option, "crop")


def current_padding_color() -> str:
    color = run_gsettings("primary-color", "#000000")
    if len(color) == 7 and color.startswith("#"):
        try:
            int(color[1:], 16)
            return color.lower()
        except ValueError:
            pass
    return "#000000"


def choose_wallpaper_options(path: Path) -> tuple[str, str] | None:
    """Show the desktop's wallpaper layout chooser.

    The backend used to depend on zenity, which is not installed on this
    machine.  Building the small chooser directly with GTK keeps D-Bus
    activation self-contained and makes the Nautilus action behave like a
    native desktop operation.
    """
    import gi

    gi.require_version("Gtk", "4.0")
    from gi.repository import Gdk, Gtk, Pango

    Gtk.init()
    loop = GLib.MainLoop()
    result: tuple[str, str] | None = None
    finished = False

    window = Gtk.Window(title="Set Wallpaper")
    window.set_default_size(560, 390)
    window.set_resizable(False)
    window.set_modal(True)

    content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=16)
    content.set_margin_top(24)
    content.set_margin_bottom(20)
    content.set_margin_start(24)
    content.set_margin_end(24)
    window.set_child(content)

    title = Gtk.Label(label="Choose how to display this wallpaper")
    title.set_halign(Gtk.Align.START)
    title.add_css_class("title-2")
    content.append(title)

    filename = Gtk.Label(label=path.name)
    filename.set_halign(Gtk.Align.START)
    filename.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
    filename.add_css_class("dim-label")
    content.append(filename)

    choices = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    content.append(choices)
    buttons: dict[str, Gtk.CheckButton] = {}
    group = None
    selected_mode = current_resize_mode()

    for mode, label, description in RESIZE_CHOICES:
        row = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        radio = Gtk.CheckButton(label=label)
        if group is None:
            group = radio
        else:
            radio.set_group(group)
        radio.set_active(mode == selected_mode)
        detail = Gtk.Label(label=description)
        detail.set_halign(Gtk.Align.START)
        detail.set_margin_start(30)
        detail.add_css_class("dim-label")
        row.append(radio)
        row.append(detail)
        choices.append(row)
        buttons[mode] = radio

    color_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
    color_label = Gtk.Label(label="Padding Color")
    color_label.set_hexpand(True)
    color_label.set_halign(Gtk.Align.START)
    color_button = Gtk.ColorButton()
    rgba = Gdk.RGBA()
    rgba.parse(current_padding_color())
    color_button.set_rgba(rgba)
    color_row.append(color_label)
    color_row.append(color_button)
    content.append(color_row)

    def selected() -> str:
        for mode, button in buttons.items():
            if button.get_active():
                return mode
        return "crop"

    def update_color_visibility(*_args) -> None:
        color_row.set_visible(selected() in PADDING_COLOR_MODES)

    for button in buttons.values():
        button.connect("toggled", update_color_visibility)
    update_color_visibility()

    content.append(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))
    actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    actions.set_halign(Gtk.Align.END)
    cancel = Gtk.Button(label="Cancel")
    confirm = Gtk.Button(label="Set")
    confirm.add_css_class("suggested-action")
    actions.append(cancel)
    actions.append(confirm)
    content.append(actions)

    def finish(value: tuple[str, str] | None) -> None:
        nonlocal result, finished
        if finished:
            return
        finished = True
        result = value
        window.set_visible(False)
        loop.quit()

    def on_confirm(_button) -> None:
        mode = selected()
        picked = color_button.get_rgba()
        color = "#{:02x}{:02x}{:02x}".format(
            round(picked.red * 255),
            round(picked.green * 255),
            round(picked.blue * 255),
        )
        finish((mode, color))

    def on_close(_window) -> bool:
        finish(None)
        return False

    cancel.connect("clicked", lambda *_: finish(None))
    confirm.connect("clicked", on_confirm)
    window.connect("close-request", on_close)
    window.present()
    loop.run()
    return result


def path_from_uri(uri: str) -> Path | None:
    parsed = urllib.parse.urlparse(uri)
    if parsed.scheme != "file" or parsed.netloc not in {"", "localhost"}:
        return None
    path = Path(urllib.parse.unquote(parsed.path))
    return path if path.is_file() else None


def persist_wallpaper(source: Path) -> Path:
    """Copy a portal/document path to durable per-user storage.

    SetWallpaperFile may expose the selected file through a document-portal
    path below /run/user.  Keeping that URI directly would break after logout.
    A content hash also avoids accumulating duplicate copies.
    """
    source = source.resolve()
    WALLPAPER_DIR.mkdir(parents=True, exist_ok=True)

    try:
        source.relative_to(WALLPAPER_DIR.resolve())
        return source
    except ValueError:
        pass

    digest = hashlib.sha256()
    with source.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)

    suffix = source.suffix.lower()
    if not suffix or len(suffix) > 12 or not suffix[1:].isalnum():
        suffix = ".img"
    destination = WALLPAPER_DIR / f"{digest.hexdigest()}{suffix}"
    if not destination.is_file():
        shutil.copy2(source, destination)
    return destination


def set_wallpaper(uri: str, options: dict | None = None) -> int:
    """Apply a wallpaper and return a portal response code.

    Portal response codes are 0 for success, 1 for cancellation, and 2 for an
    error.  Lock-screen-only requests are rejected because this desktop only
    owns the background wallpaper.
    """
    options = options or {}
    if options.get("set-on") == "lockscreen":
        return 2

    source = path_from_uri(uri)
    if source is None or not WALLPAPER_SH.is_file():
        return 2

    selection = choose_wallpaper_options(source)
    if selection is None:
        return 1
    resize_mode, padding_color = selection

    stored = persist_wallpaper(source)
    command = [
        str(WALLPAPER_SH),
        str(stored),
        resize_mode,
        padding_color,
    ]
    try:
        result = subprocess.run(command, timeout=30, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        log(f"failed to run wallpaper helper: {error}")
        return 2

    if result.returncode != 0:
        log(f"wallpaper helper exited with status {result.returncode}")
        return 2
    log(f"applied {stored}")
    return 0


def on_method_call(_conn, _sender, _path, _iface, method, params, invocation):
    if method != "SetWallpaperURI":
        invocation.return_error_literal(
            Gio.dbus_error_quark(),
            Gio.DBusError.UNKNOWN_METHOD,
            f"unknown method: {method}",
        )
        return

    _handle, _app_id, _parent, uri, options = params.unpack()
    try:
        response = set_wallpaper(uri, options)
    except Exception:
        log(traceback.format_exc().rstrip())
        response = 2
    invocation.return_value(GLib.Variant("(u)", (response,)))


def on_bus_acquired(connection, _name):
    node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML)
    connection.register_object(
        OBJECT_PATH,
        node.interfaces[0],
        on_method_call,
        None,
        None,
    )


def main() -> None:
    loop = GLib.MainLoop()
    Gio.bus_own_name(
        Gio.BusType.SESSION,
        BUS_NAME,
        Gio.BusNameOwnerFlags.NONE,
        on_bus_acquired,
        None,
        lambda *_: loop.quit(),
    )
    loop.run()


if __name__ == "__main__":
    main()
