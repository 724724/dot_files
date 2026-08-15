# Screenshot and screen recording

All three screenshot shortcuts now use the same Quickshell capture service and
saved options:

- `Super+Shift+3` captures the focused screen directly and shows only the result
  notification. It uses the destination and pointer setting saved from the toolbar.
- `Super+Shift+4` opens Selected Portion without the toolbar. Drag outside the box
  to redraw it, drag a corner to resize it, then click inside with the camera cursor
  to capture.
- `Super+Shift+5` opens the full Screenshot toolbar. Its six modes are entire
  screen, window, selected portion, and the matching three recording modes.

The toolbar is compact and can be moved by dragging any empty part of its
background. Its normalized position is remembered across openings and remains
sensible across output sizes. The toolbar, options menu, and folder picker follow
the desktop light/dark appearance and use a border without a drop shadow.

The last mode chosen in the full toolbar is stored independently from the temporary
`Super+Shift+4` Selected Portion session, so closing, reopening, and reloading
Quickshell all return `Super+Shift+5` to the last toolbar mode. Escape always closes
either capture overlay, including while Options or the folder picker is open.

In the full toolbar, a selected portion can be redrawn, moved, or resized from its
corners. Clicking a highlighted window captures it immediately without a title
label. Window capture briefly raises only that selected window for the compositor
copy, then restores the previously focused window so overlapping windows are not
included. The blue button works for every mode.

Options open as an anchored menu above the toolbar. File destinations are limited
to Desktop, Documents, Clipboard, and one replaceable custom folder selected with
Other Locations. The custom directory browser is an in-QML `FolderListModel`
picker derived from the Bar clock picker; it does not launch zenity or a native
dialog behind the layer surface. Clipboard writes no file; every other screenshot
is saved and also copied to the clipboard. The menu also includes the 5/10 second timer,
cursor visibility, system audio, microphone input, and remembering the last area.
Window screenshots alone receive an alpha-backed ImageMagick shadow.

The screenshot path uses packages already common to this setup:

```sh
sudo pacman -S --needed grim imagemagick wl-clipboard libnotify xdg-user-dirs
```

Recording uses the GPU-only backend and is intentionally unavailable until it is
installed:

```sh
sudo pacman -S --needed gpu-screen-recorder
```

On NVIDIA, `nvidia-utils` is the recorder's optional runtime dependency and is
already part of this machine's driver stack. Recordings use H.264, high quality,
variable frame rate, and the GPU encoder to keep CPU and memory overhead low.
They are saved as MKV under Documents, Desktop, or the selected custom directory
and can be stopped from the red elapsed-time pill immediately to the left of the
Magic workspace pill in the Bar.

The backend accepts only fixed actions, output names, bounded integer geometry,
and enum-like options. It never evaluates text supplied by window titles or the
UI as shell code.

The full-screen selection surfaces remain mapped with an empty input region while
closed. Opening the toolbar activates their input region immediately, avoiding a
Wayland layer-map race. Window mode takes a fresh, read-only snapshot of windows
on each monitor's visible workspace instead of depending on the Dock cache.
