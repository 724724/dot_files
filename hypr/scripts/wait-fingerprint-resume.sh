#!/bin/sh
# systemd-sleep hook: block resume completion until the fingerprint reader is
# back on the USB bus. logind emits PrepareForSleep(false) only after all
# post hooks return, and that signal is what triggers hyprlock's single
# (non-retried) fprintd Claim/VerifyStart. Waiting here guarantees the sensor
# exists before hyprlock's one shot fires.
#
# Install: sudo install -Dm755 ~/.config/hypr/scripts/wait-fingerprint-resume.sh \
#              /usr/lib/systemd/system-sleep/10-wait-fingerprint

VENDOR=06cb   # Synaptics
PRODUCT=00f9

[ "$1" = "post" ] || exit 0

i=0
while [ $i -lt 50 ]; do          # bounded: never delay resume more than ~5s
    for d in /sys/bus/usb/devices/*/idVendor; do
        dir=${d%/idVendor}
        [ "$(cat "$d" 2>/dev/null)" = "$VENDOR" ] || continue
        [ "$(cat "$dir/idProduct" 2>/dev/null)" = "$PRODUCT" ] || continue
        udevadm settle --timeout=2 2>/dev/null
        echo "fingerprint sensor ready after $((i * 100))ms"
        exit 0
    done
    sleep 0.1
    i=$((i + 1))
done

echo "fingerprint sensor did not reappear within 5s, resuming anyway"
exit 0
