#!/usr/bin/env bash
# One-shot setup for the media pill's GPU stem filter.
#
#   ./install-stem-split.sh            install / repair
#   ./install-stem-split.sh --check    report status only
#   ./install-stem-split.sh --uninstall
#
# Creates a self-contained venv and installs CUDA PyTorch + Demucs into it.
# Nothing is installed system-wide and no sudo is needed — delete the venv
# directory and every trace is gone.
#
# Roughly 5 GB on disk and a large download; safe to re-run (pip skips what's
# already satisfied) and safe to interrupt.
set -uo pipefail

VENV="${QS_STEM_VENV:-$HOME/.local/share/quickshell/stem-venv}"
PKGS=(torch torchaudio demucs numpy)
MODEL_NAMES=(htdemucs htdemucs_ft)

c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
ok()   { printf '%s  ok%s  %s\n'   "$c_ok"   "$c_off" "$1"; }
warn() { printf '%s  !!%s  %s\n'   "$c_warn" "$c_off" "$1"; }
err()  { printf '%s  xx%s  %s\n'   "$c_err"  "$c_off" "$1"; }
step() { printf '\n%s==>%s %s\n' "$c_dim" "$c_off" "$1"; }

have() { command -v "$1" >/dev/null 2>&1; }

check_prereqs() {
    local fail=0
    step "Checking prerequisites"

    if have python3; then ok "python3 $(python3 --version 2>&1 | cut -d' ' -f2)"
    else err "python3 not found"; fail=1; fi

    if python3 -c 'import venv' 2>/dev/null; then ok "python venv module"
    else err "python venv module missing (install python-virtualenv)"; fail=1; fi

    if have pactl; then ok "pactl (PipeWire/PulseAudio)"
    else err "pactl not found — the filter cannot route audio"; fail=1; fi

    if have parec && have pacat; then ok "parec / pacat"
    else err "parec or pacat not found (install libpulse)"; fail=1; fi

    if have nvidia-smi; then
        local gpu
        gpu=$(nvidia-smi --query-gpu=name,compute_cap --format=csv,noheader 2>/dev/null | head -1)
        if [ -n "$gpu" ]; then ok "GPU: $gpu"
        else err "nvidia-smi present but no GPU reported"; fail=1; fi
    else
        err "nvidia-smi not found — this build requires an NVIDIA GPU with CUDA"
        fail=1
    fi

    local free
    free=$(df -Pk "$(dirname "$VENV")" 2>/dev/null | awk 'NR==2{print int($4/1048576)}')
    if [ -n "$free" ] && [ "$free" -lt 8 ]; then
        warn "only ${free} GiB free where the venv goes; ~5 GiB is needed"
    else
        ok "disk space (${free:-?} GiB free)"
    fi

    return $fail
}

do_install() {
    check_prereqs || { err "prerequisites unmet — nothing was changed"; return 1; }

    step "Creating venv at $VENV"
    mkdir -p "$(dirname "$VENV")" || return 1
    if [ ! -x "$VENV/bin/python" ]; then
        python3 -m venv "$VENV" || { err "venv creation failed"; return 1; }
        ok "venv created"
    else
        ok "venv already present (reusing)"
    fi

    "$VENV/bin/python" -m ensurepip --upgrade >/dev/null 2>&1
    "$VENV/bin/python" -m pip install --upgrade pip >/dev/null 2>&1 && ok "pip up to date"

    step "Installing ${PKGS[*]} (large download, please wait)"
    if ! "$VENV/bin/python" -m pip install --no-input "${PKGS[@]}"; then
        err "package install failed"
        return 1
    fi
    ok "packages installed"

    step "Verifying CUDA"
    "$VENV/bin/python" - <<'PY' || { err "CUDA verification failed"; return 1; }
import sys, torch
print("      torch      :", torch.__version__)
print("      cuda build :", torch.version.cuda)
if not torch.cuda.is_available():
    print("      CUDA is NOT available to torch"); sys.exit(1)
cap = "sm_%d%d" % torch.cuda.get_device_capability(0)
print("      device     :", torch.cuda.get_device_name(0))
print("      capability :", cap)
archs = torch.cuda.get_arch_list()
if cap not in archs:
    # e.g. a Blackwell card against a torch built only up to sm_90
    print("      this torch build does not target %s (has %s)" % (cap, ", ".join(archs)))
    sys.exit(1)
torch.randn(64, 64, device="cuda").sum().item()
print("      compute    : working")
PY
    ok "CUDA verified"

    step "Fetching ${MODEL_NAMES[*]} weights (cached for later)"
    if "$VENV/bin/python" - "${MODEL_NAMES[@]}" <<'PY'
import gc
import sys
from demucs.pretrained import get_model
for name in sys.argv[1:]:
    model = get_model(name)
    print("      %-12s: %s" % (name, ", ".join(model.sources)))
    del model
    gc.collect()
PY
    then ok "speed and quality models ready"
    else err "model download failed — rerun the installer before using stem mode"; return 1; fi

    step "Done"
    ok "stem filter is ready; open the media pill's EQ to use it"
    printf '%s      venv: %s%s\n' "$c_dim" "$VENV" "$c_off"
}

do_check() {
    check_prereqs || true
    step "Installation"
    if [ -x "$VENV/bin/python" ]; then
        ok "venv present at $VENV"
        for p in "${PKGS[@]}"; do
            v=$("$VENV/bin/python" -c "import importlib.metadata as m;print(m.version('$p'))" 2>/dev/null)
            if [ -n "$v" ]; then ok "$p $v"; else err "$p missing"; fi
        done
        "$VENV/bin/python" -c "import torch;print('      cuda available:', torch.cuda.is_available())" 2>/dev/null
        printf '%s      size: %s%s\n' "$c_dim" "$(du -sh "$VENV" 2>/dev/null | cut -f1)" "$c_off"

        step "Model cache"
        if "$VENV/bin/python" - "${MODEL_NAMES[@]}" <<'PY'
import sys
import yaml
from demucs.hf import DEFAULT_NAMESPACE, hf_repo_name
from huggingface_hub import hf_hub_download

complete = True
for name in sys.argv[1:]:
    repo = f"{DEFAULT_NAMESPACE}/{hf_repo_name(name)}"
    try:
        definition = hf_hub_download(
            repo, f"{name}.yaml", local_files_only=True)
        with open(definition) as stream:
            signatures = yaml.safe_load(stream)["models"]
        for signature in signatures:
            hf_hub_download(
                repo, f"{signature}.safetensors", local_files_only=True)
        print("      %-12s: cached (%d weight file%s)" % (
            name, len(signatures), "" if len(signatures) == 1 else "s"))
    except Exception:
        complete = False
        print("      %-12s: missing" % name)
sys.exit(0 if complete else 1)
PY
        then ok "speed and quality model caches complete"
        else warn "model cache incomplete — rerun this script without arguments"; fi
    else
        warn "not installed — run this script with no arguments to install"
    fi
}

do_uninstall() {
    step "Removing $VENV"
    if [ -d "$VENV" ]; then
        case "$VENV" in
            ""|"/"|"$HOME"|"$HOME/")
                err "refusing unsafe venv path: $VENV"
                return 1
                ;;
        esac
        if [ ! -f "$VENV/pyvenv.cfg" ] || [ ! -x "$VENV/bin/python" ]; then
            err "refusing to remove a directory that is not a Python venv"
            return 1
        fi
        rm -rf -- "$VENV" && ok "venv removed"
    else
        ok "nothing to remove"
    fi
    warn "model weights remain in ~/.cache/huggingface (delete manually if unwanted)"
}

case "${1:-}" in
    --check)      do_check ;;
    --uninstall)  do_uninstall ;;
    -h|--help)    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
    "")           do_install ;;
    *)            err "unknown option: $1"; exit 2 ;;
esac
