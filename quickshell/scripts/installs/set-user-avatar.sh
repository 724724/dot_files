#!/usr/bin/env bash
# Keep the private Quickshell avatar and SDDM's public greeter copy in sync.

set -euo pipefail

readonly HOME_DIR="${HOME:?HOME is not set}"
readonly USER_NAME="$(/usr/bin/id -un)"
readonly LOCK_AVATAR="$HOME_DIR/.face"
readonly SDDM_FACES_DIR="/usr/share/sddm/faces"
readonly SDDM_AVATAR="$SDDM_FACES_DIR/$USER_NAME.face.icon"

case "$USER_NAME" in
    ""|*[!A-Za-z0-9_.-]*)
        printf 'Unsupported account name: %s\n' "$USER_NAME" >&2
        exit 1
        ;;
esac

if (( $# > 1 )); then
    printf 'Usage: %s [image]\n' "$0" >&2
    exit 2
fi

source_image="${1:-$LOCK_AVATAR}"
if [[ ! -f "$source_image" || ! -r "$source_image" ]]; then
    printf 'Avatar image is not a readable file: %s\n' "$source_image" >&2
    if (( $# == 0 )); then
        printf 'Choose one with: %s /path/to/avatar.png\n' "$0" >&2
    fi
    exit 1
fi

if ! command -v magick >/dev/null 2>&1; then
    printf '%s\n' 'ImageMagick (magick) is required.' >&2
    exit 1
fi

# An explicit image becomes the lock's canonical private avatar. Preserve the
# original bytes and let each QML Image choose its own crop at render time.
if (( $# == 1 )); then
    source_path="$(/usr/bin/realpath -- "$source_image")"
    avatar_path="$(/usr/bin/realpath -m -- "$LOCK_AVATAR")"
    if [[ "$source_path" != "$avatar_path" ]]; then
        /usr/bin/install -m 0600 -- "$source_path" "$LOCK_AVATAR"
    elif [[ ! -L "$LOCK_AVATAR" ]]; then
        /usr/bin/chmod 0600 -- "$LOCK_AVATAR"
    fi
fi

runtime_parent="${XDG_RUNTIME_DIR:-/tmp}"
temp_avatar="$(/usr/bin/mktemp "$runtime_parent/quickshell-avatar.XXXXXX.png")"
cleanup() {
    /usr/bin/rm -f -- "$temp_avatar"
}
trap cleanup EXIT

# SDDM's UserModel expects <username>.face.icon in FacesDir. Give it a bounded,
# square PNG instead of access to the user's home directory or private .face.
/usr/bin/magick "$LOCK_AVATAR" \
    -auto-orient \
    -thumbnail '512x512^' \
    -gravity center \
    -extent 512x512 \
    -strip \
    "$temp_avatar"
/usr/bin/chmod 0600 -- "$temp_avatar"

/usr/bin/sudo /usr/bin/install -d -m 0755 -- "$SDDM_FACES_DIR"
/usr/bin/sudo /usr/bin/install -o root -g root -m 0644 -- \
    "$temp_avatar" "$SDDM_AVATAR"

printf 'Quickshell avatar: %s\n' "$LOCK_AVATAR"
printf 'SDDM avatar:       %s\n' "$SDDM_AVATAR"
printf '%s\n' 'The new image appears on the next lock and the next SDDM greeter start.'
