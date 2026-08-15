# Quickshell installers

Run the aggregate installer once after copying these dotfiles to a machine:

```sh
~/.config/quickshell/scripts/installs/install-all.sh
```

It installs all compatible machine-local pieces: the Quickshell lock user unit
and PAM policies, wallpaper portal, focus-mode policy directories, stock worker,
an existing `~/.face` for SDDM, and the NVIDIA stem environment. The stem setup
downloads roughly 5 GiB; pass `--skip-stem` when it is not wanted. Pass
`--avatar /path/to/image` to create `~/.face` and its SDDM copy in the same run.

The scripts here may also be run individually for repair or component-specific
maintenance. They are location-independent as long as this directory remains
inside the repository at `scripts/installs/`.

## Screenshot toolbar packages

The Quickshell Screenshot toolbar itself needs no service or autostart entry. Its
screenshot tools use packages normally installed with this setup:

```sh
sudo pacman -Syu --needed grim imagemagick wl-clipboard libnotify xdg-user-dirs
```

Install the recording backend separately when screen recording is wanted:

```sh
sudo pacman -Syu --needed gpu-screen-recorder
```

Until that package is present, the three screenshot modes remain fully usable
and only the recording action shows an installation notice. On Arch Linux, do
not use `pacman -Sy package`: a recorder built against a newer FFmpeg cannot run
with older libraries left by a partial upgrade.
