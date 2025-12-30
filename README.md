# dot_files

![Hyprland Screenshot](/assets/screenshot.png)

```bash
sudo nano /etc/pacman.conf
# [multilib]
# Include = /etc/pacman.d/mirrorlist
```

packages (Arch btw)

```bash
sudo pacman -S \
  # --- [1] Hyprland Core & System ---
  hyprland hypridle hyprlock hyprpaper xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  waybar sddm swaync rofi-wayland \
  jq grim slurp wl-clipboard hyprpicker brightnessctl playerctl \
  libnotify dunst \
  
  # --- [2] Hardware Drivers (ThinkPad T14s Gen 2i) ---
  intel-ucode intel-media-driver vulkan-intel lib32-vulkan-intel \
  mesa lib32-mesa fprintd tlp sof-firmware \
  
  # --- [3] Audio & Network ---
  pipewire pipewire-pulse wireplumber pipewire-audio pipewire-alsa pavucontrol \
  network-manager-applet bluez bluez-utils blueman \
  
  # --- [4] Apps & Tools ---
  fastfetch firefox obs-studio gimp inkscape vlc \
  gnome-boxes docker gnome-calculator gnome-calendar gnome-system-monitor gnome-clocks nautilus \
  loupe imagemagick libreoffice-still \
  
  # --- [5] Fonts & Input (Korean) ---
  noto-fonts-cjk ttf-nanum ttf-jetbrains-mono-nerd adobe-source-han-sans-kr-fonts \
  fcitx5-im fcitx5-hangul \
  
  # --- [6] Wine / Windows Support ---
  wine wine-gecko wine-mono winetricks
```

yay install

```bash
sudo pacman -S --needed git base-devel
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
```

```bash
yay -S \
  ghostty-git hyprshell \
  nwg-look nwg-displays \
  grimblast-git wl-clip-persist \
  google-chrome visual-studio-code-bin \
  spotify vesktop notion-app-enhanced \
  heroic-games-launcher-bin \
  sticky librepods
```

turn on the systemctl

```bash
sudo systemctl enable sddm
sudo systemctl enable --now bluetooth
sudo systemctl enable --now tlp
sudo systemctl enable --now fprintd
sudo systemctl enable --now docker
```
