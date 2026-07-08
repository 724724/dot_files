#!/usr/bin/env python3
# Minimal org.freedesktop.impl.portal.Wallpaper backend for Hyprland.
#
# Neither xdg-desktop-portal-hyprland nor -gtk implements the Wallpaper portal,
# so Nautilus "Set as Background" (which goes through the portal, not gsettings)
# silently did nothing. This backend accepts SetWallpaperURI and hands the file
# to hypr/scripts/wallpaper.sh after asking how the image should be fitted.
# wallpaper.sh applies it via awww and mirrors both URI and fit mode into the
# GNOME background keys (quickshell's WallpaperService keeps Mission Control in
# sync from there).
#
# Launched on demand via D-Bus activation:
#   ~/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprqs.service
# Registered with xdg-desktop-portal via:
#   ~/.local/share/xdg-desktop-portal/portals/hyprqs.portal
#   ~/.config/xdg-desktop-portal/hyprland-portals.conf  (Wallpaper=hyprqs)

import os
import subprocess
import urllib.parse

from gi.repository import Gio, GLib

BUS_NAME = "org.freedesktop.impl.portal.desktop.hyprqs"
OBJECT_PATH = "/org/freedesktop/portal/desktop"
WALLPAPER_SH = os.path.expanduser("~/.config/hypr/scripts/wallpaper.sh")
RESIZE_CHOICES = [
    ("crop", "Fill Screen", "Fill the screen and crop edges if needed"),
    ("fit", "Fit to Screen", "Show the whole image with padding if needed"),
    ("stretch", "Stretch to Fill Screen", "Fill the screen without preserving aspect ratio"),
    ("no", "Center", "Keep original size and center it"),
]
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
    <property name="version" type="u" access="read"/>
  </interface>
</node>
"""


def current_padding_color():
    try:
        r = subprocess.run(
            ["gsettings", "get", "org.gnome.desktop.background", "primary-color"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=5,
        )
    except Exception:
        return "#000000"

    color = r.stdout.strip().strip("'")
    return color if color.startswith("#") else "#000000"


def choose_padding_color():
    try:
        r = subprocess.run(
            [
                "zenity",
                "--color-selection",
                "--show-palette",
                "--title=Wallpaper Padding Color",
                "--color=" + current_padding_color(),
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=300,
        )
    except FileNotFoundError:
        return "#000000"
    except subprocess.TimeoutExpired:
        return None

    if r.returncode != 0:
        return None

    color = r.stdout.strip()
    return color if color else "#000000"


def choose_wallpaper_options(path):
    cmd = [
        "zenity",
        "--list",
        "--radiolist",
        "--title=Set Wallpaper",
        "--text=Choose how to display this wallpaper:\n" + os.path.basename(path),
        "--ok-label=Set",
        "--cancel-label=Cancel",
        "--width=620",
        "--height=290",
        "--column=",
        "--column=Mode",
        "--column=Value",
        "--column=Description",
        "--hide-column=3",
        "--print-column=3",
    ]
    for mode, label, desc in RESIZE_CHOICES:
        cmd.extend(["TRUE" if mode == "crop" else "FALSE", label, mode, desc])

    try:
        r = subprocess.run(
            cmd,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=300,
        )
    except FileNotFoundError:
        return "crop"
    except subprocess.TimeoutExpired:
        return None

    if r.returncode != 0:
        return None

    mode = r.stdout.strip()
    if mode not in {choice[0] for choice in RESIZE_CHOICES}:
        mode = "crop"

    color = choose_padding_color() if mode in PADDING_COLOR_MODES else None
    if mode in PADDING_COLOR_MODES and color is None:
        return None

    return mode, color


def set_wallpaper(uri: str) -> int:
    """Portal response codes: 0 = success, 1 = cancelled, 2 = error."""
    parsed = urllib.parse.urlparse(uri)
    if parsed.scheme != "file":
        return 2
    path = urllib.parse.unquote(parsed.path)
    if not os.path.isfile(path):
        return 2
    options = choose_wallpaper_options(path)
    if options is None:
        return 1
    mode, color = options
    cmd = [WALLPAPER_SH, path, mode]
    if color:
        cmd.append(color)
    r = subprocess.run(cmd, timeout=30)
    return 0 if r.returncode == 0 else 2


def on_method_call(_conn, _sender, _path, _iface, method, params, invocation):
    if method == "SetWallpaperURI":
        _handle, _app_id, _parent, uri, _options = params.unpack()
        try:
            response = set_wallpaper(uri)
        except Exception:
            response = 2
        invocation.return_value(GLib.Variant("(u)", (response,)))
    else:
        invocation.return_error_literal(
            Gio.dbus_error_quark(), Gio.DBusError.UNKNOWN_METHOD, "unknown method")


def on_get_property(_conn, _sender, _path, _iface, prop):
    if prop == "version":
        return GLib.Variant("u", 1)
    return None


def on_bus_acquired(conn, _name):
    node = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML)
    conn.register_object(
        OBJECT_PATH, node.interfaces[0], on_method_call, on_get_property, None)


def main():
    loop = GLib.MainLoop()
    Gio.bus_own_name(
        Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.NONE,
        on_bus_acquired, None, lambda *_: loop.quit())
    loop.run()


if __name__ == "__main__":
    main()
