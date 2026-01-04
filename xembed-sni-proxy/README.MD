## Dependencies (Arch Linux)
```bash
sudo pacman -S extra-cmake-modules qt6-base kwindowsystem kdbusaddons kcoreaddons kcrash xcb-util xcb-util-image libxtst
```

## Build & Install
```bash
mkdir build && cd build
cmake ..
make
sudo make install
```

## Usage (Hyprland)

Add to your `hyprland.conf`:
```
exec-once = xembedsniproxy
```
