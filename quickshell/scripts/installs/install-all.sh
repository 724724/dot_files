#!/usr/bin/env bash
# Install every machine-local component used by these Quickshell dotfiles.

set -euo pipefail

readonly INSTALL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly LOCK_AVATAR="${HOME:?HOME is not set}/.face"

skip_stem=0
skip_avatar=0
avatar_source=""

usage() {
    cat <<'EOF'
Usage: install-all.sh [options]

Installs the session lock, wallpaper portal, focus-mode policy directories,
stock background worker, SDDM avatar copy, and the NVIDIA stem-split venv.

Options:
  --avatar IMAGE  Set IMAGE as ~/.face and install its SDDM copy
  --skip-avatar   Do not synchronize ~/.face with SDDM
  --skip-stem     Skip the NVIDIA-only ~5 GiB stem-split environment
  -h, --help      Show this help

Without --avatar, an existing ~/.face is synchronized automatically. If no
avatar exists, that optional step is skipped. Stem setup is attempted only when
nvidia-smi is available; use --skip-stem to omit its large download explicitly.
EOF
}

while (( $# > 0 )); do
    case "$1" in
        --avatar)
            if (( $# < 2 )); then
                printf '%s\n' '--avatar requires an image path.' >&2
                exit 2
            fi
            avatar_source="$2"
            shift 2
            ;;
        --skip-avatar)
            skip_avatar=1
            shift
            ;;
        --skip-stem)
            skip_stem=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if (( skip_avatar == 1 )) && [[ -n "$avatar_source" ]]; then
    printf '%s\n' '--avatar and --skip-avatar cannot be used together.' >&2
    exit 2
fi

missing=()
for command_name in sudo install systemctl systemd-analyze gdbus sed python3; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        missing+=("$command_name")
    fi
done
if (( ${#missing[@]} > 0 )); then
    printf 'Missing installer prerequisites: %s\n' "${missing[*]}" >&2
    exit 1
fi

run_step() {
    local label="$1"
    shift
    printf '\n==> %s\n' "$label"
    "$@"
}

# Validate sudo before any user-level installation starts, preventing a late
# privilege prompt after several components have already been changed.
/usr/bin/sudo -v

run_step "Quickshell session lock" \
    "$INSTALL_DIR/install-quickshell-lock.sh"
run_step "Wallpaper portal backend" \
    "$INSTALL_DIR/install-wallpaper-portal.sh"
run_step "Focus-mode browser policy directories" \
    "$INSTALL_DIR/install-focus-sites.sh"
run_step "Stock background worker" \
    "$INSTALL_DIR/install-stock-worker.sh" install

if (( skip_avatar == 0 )); then
    if [[ -n "$avatar_source" ]]; then
        run_step "Quickshell and SDDM avatar" \
            "$INSTALL_DIR/set-user-avatar.sh" "$avatar_source"
    elif [[ -f "$LOCK_AVATAR" && -r "$LOCK_AVATAR" ]]; then
        run_step "Quickshell and SDDM avatar" \
            "$INSTALL_DIR/set-user-avatar.sh"
    else
        printf '\n==> Avatar\n'
        printf '%s\n' 'Skipped: ~/.face does not exist (use --avatar IMAGE).'
    fi
fi

if (( skip_stem == 1 )); then
    printf '\n==> NVIDIA stem-split environment\n'
    printf '%s\n' 'Skipped by --skip-stem.'
elif command -v nvidia-smi >/dev/null 2>&1; then
    run_step "NVIDIA stem-split environment (~5 GiB)" \
        "$INSTALL_DIR/install-stem-split.sh"
else
    printf '\n==> NVIDIA stem-split environment\n'
    printf '%s\n' 'Skipped: no NVIDIA GPU tooling is available on this laptop.'
fi

printf '\n%s\n' 'All compatible Quickshell components are installed.'
printf '%s\n' 'The lock remains static/on-demand and must not be enabled at boot.'
