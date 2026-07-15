#!/bin/bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MEDIA="$ROOT/scripts/media"

MODEL_DIR="$HOME/.local/share/quickshell/camera-effects"
MODEL="$MODEL_DIR/SINet_Softmax.onnx"
VENV="$MODEL_DIR/venv"
MODEL_URL="https://raw.githubusercontent.com/anilsathyan7/Portrait-Segmentation/master/SINet/SINet_Softmax.onnx"
MODEL_SHA256="932c83e0013e07bbe597fe0007ba5ae6add3fbb6413ca5b81f18b2d410ac7259"

sudo pacman -S --needed noise-suppression-for-voice v4l2loopback-dkms v4l2loopback-utils python-opencv intel-compute-runtime

install -Dm644 "$MEDIA/90-quickshell-voice-isolation.conf" \
    "$HOME/.config/pipewire/filter-chain.conf.d/90-quickshell-voice-isolation.conf"
install -Dm644 "$MEDIA/quickshell-voice-isolation.service" \
    "$HOME/.config/systemd/user/quickshell-voice-isolation.service"
install -Dm644 "$MEDIA/quickshell-camera-effects.service" \
    "$HOME/.config/systemd/user/quickshell-camera-effects.service"
systemctl --user daemon-reload

install -d "$MODEL_DIR"
if [[ ! -f "$MODEL" ]] || ! echo "$MODEL_SHA256  $MODEL" | sha256sum --check --status; then
    temporary=$(mktemp)
    trap 'rm -f "$temporary"' EXIT
    curl -fsSL "$MODEL_URL" -o "$temporary"
    echo "$MODEL_SHA256  $temporary" | sha256sum --check --status
    install -m644 "$temporary" "$MODEL"
fi

python3 -m venv --system-site-packages "$VENV"
if ! "$VENV/bin/python" -c 'import openvino' 2>/dev/null; then
    "$VENV/bin/python" -m pip install --disable-pip-version-check --no-input 'openvino==2026.2.1'
fi

sudo install -Dm644 "$MEDIA/v4l2loopback.conf" /etc/modprobe.d/quickshell-v4l2loopback.conf
sudo install -Dm644 "$MEDIA/v4l2loopback.modules" /etc/modules-load.d/quickshell-v4l2loopback.conf
camera_name=""
if [[ -r /sys/class/video4linux/video10/name ]]; then
    camera_name=$(< /sys/class/video4linux/video10/name)
fi
if [[ ! -e /dev/video10 || "$camera_name" != "QS Camera" ]]; then
    systemctl --user stop quickshell-camera-effects.service 2>/dev/null || true
    if grep -q '^v4l2loopback ' /proc/modules; then
        sudo modprobe -r v4l2loopback
    fi
    sudo modprobe v4l2loopback video_nr=10 card_label="QS Camera" exclusive_caps=1 max_buffers=2
fi

systemctl --user enable --now quickshell-voice-isolation.service
systemctl --user enable --now quickshell-camera-effects.service

printf 'QS Camera is ready at /dev/video10\n'
