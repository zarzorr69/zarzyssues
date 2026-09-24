#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# Zarzysseus AI Installer / Service Manager
# Multi-distro Linux (package-manager capability detection; distro derivatives supported)
# Python 3.12 via pyenv
# Idempotent / safe to rerun
#
# Usage:
#   ./zarzysseus.sh              Launch the interactive TUI
#   ./zarzysseus.sh tui          Launch the interactive TUI
#   ./zarzysseus.sh repo-update Check/fetch/fast-forward existing Odysseus checkout (no OS upgrade)
#   ./zarzysseus.sh install      Install/update Zarzysseus
#   ./zarzysseus.sh install-full Install/update + auto-fit text/video/photo/audio models
#   ./zarzysseus.sh install-auto-fit <nonempty text/video/photo/audio combination>
#   ./zarzysseus.sh start
#   ./zarzysseus.sh stop
#   ./zarzysseus.sh restart
#   ./zarzysseus.sh status
#   ./zarzysseus.sh enable
#   ./zarzysseus.sh disable
#   ./zarzysseus.sh tools
#   ./zarzysseus.sh ollama-start
#   ./zarzysseus.sh ollama-stop
#   ./zarzysseus.sh ollama-restart
#   ./zarzysseus.sh ollama-status
#   ./zarzysseus.sh ollama-enable
#   ./zarzysseus.sh ollama-disable
#   ./zarzysseus.sh ollama-sync
#   ./zarzysseus.sh ollama-pull <model>
#   ./zarzysseus.sh opull <model>
#   ./zarzysseus.sh vpull <org/model> [include-glob]
#   ./zarzysseus.sh spull <org/model> [include-glob]
#   ./zarzysseus.sh mlx-status
#   ./zarzysseus.sh mlx-install
#   ./zarzysseus.sh model-default [vllm|sglang|ollama|mlx_lm] [model]
#   ./zarzysseus.sh linux-status
#   ./zarzysseus.sh system-update
#   ./zarzysseus.sh pull <model>
#   ./zarzysseus.sh hf-token [token|status|clear]
#   ./zarzysseus.sh token [token|status|clear]
#   ./zarzysseus.sh hf-pull <org/model> [include-glob]
#   ./zarzysseus.sh providers
#   ./zarzysseus.sh model-list [use-case] [limit] [search] [sort] [fit-only]
#   ./zarzysseus.sh model-list-json [use-case] [limit] [search] [sort] [fit-only]
#   ./zarzysseus.sh model-pick [use-case] [limit] [search]
#   ./zarzysseus.sh model-install <org/model> [include-glob]
#   ./zarzysseus.sh endpoint-add <id> <name> <base_url> [model] [tools]
#   ./zarzysseus.sh accelerator-status
#   ./zarzysseus.sh accelerator-setup
#   ./zarzysseus.sh vllm-status
#   ./zarzysseus.sh sam-mask-status
#   ./zarzysseus.sh sam-mask-install
#   ./zarzysseus.sh hf-repair <org/model>
#   ./zarzysseus.sh uninstall
#   ./zarzysseus.sh uninstall-service
#   ./zarzysseus.sh skills-search <query>
#   ./zarzysseus.sh skills-install <name|skills.sh URL|GitHub repo|skill URL>
#   ./zarzysseus.sh skills-summary <name|skills.sh URL|source/slug>
#   ./zarzysseus.sh skills-list
#   ./zarzysseus.sh skills-update
#
# Running with no arguments launches the interactive TUI when attached to a terminal.
# An interactive launch first fetches the existing upstream checkout (fast-forward only),
# with no OS update, installation, or destructive changes on TUI startup.
# The script can be launched from ANY directory. It auto-detects existing Zarzysseus
# checkouts/services/installer copies, updates the detected Linux distribution before
# mutating install actions, clones only when no checkout exists, switches its internal
# working directory to the selected project, and keeps a managed installer copy there.
# start/enable/restart automatically install Zarzysseus first when needed.
# stop/disable/status never install anything unexpectedly.
# TUI launch fetches Git once before drawing the screen; no OS upgrade on launch.
# ==========================================

PYTHON_VERSION="${PYTHON_VERSION:-3.12.14}"
REPO_URL="${REPO_URL:-https://github.com/odysseus-dev/odysseus.git}"

# Bootstrap discovery happens before any project-relative path is derived. This
# lets a freshly downloaded copy locate an existing Zarzysseus checkout (including
# one referenced by an older user service) instead of blindly creating another
# ~/odysseus clone.
LAUNCH_SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
PROJECT_DIR_EXPLICIT=0
[[ -n "${PROJECT_DIR+x}" && -n "${PROJECT_DIR:-}" ]] && PROJECT_DIR_EXPLICIT=1
ODYSSEUS_AUTO_DISCOVER="${ZARZYSSEUS_AUTO_DISCOVER:-${ODYSSEUS_AUTO_DISCOVER:-1}}"
ODYSSEUS_DISCOVERY_MAXDEPTH="${ZARZYSSEUS_DISCOVERY_MAXDEPTH:-${ODYSSEUS_DISCOVERY_MAXDEPTH:-5}}"
PROJECT_DISCOVERY_SOURCE="default"

_bootstrap_is_odysseus_checkout() {
    local dir="${1:-}"
    [[ -n "$dir" && ( -d "$dir/.git" || -f "$dir/.git" ) ]] || return 1
    [[ -f "$dir/app.py" || -f "$dir/pyproject.toml" ]] || return 1
    if [[ -r "$dir/.git/config" ]] && grep -qiE 'github\.com[/:]odysseus-dev/odysseus(\.git)?' "$dir/.git/config" 2>/dev/null; then
        return 0
    fi
    if [[ -f "$dir/.git" ]] && command -v git >/dev/null 2>&1; then
        local checkout_origin
        checkout_origin="$(git -C "$dir" config --get remote.origin.url 2>/dev/null || true)"
        [[ "$checkout_origin" =~ github\.com[/:]odysseus-dev/odysseus(\.git)?/?$ ]] && return 0
    fi
    [[ "$(basename "$dir" | tr '[:upper:]' '[:lower:]')" == "odysseus" ]]
}

_bootstrap_checkout_ancestor() {
    local start="${1:-}" dir
    [[ -n "$start" ]] || return 1
    if [[ -f "$start" ]]; then dir="$(dirname "$start")"; else dir="$start"; fi
    dir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
    while [[ "$dir" != "/" && -n "$dir" ]]; do
        if _bootstrap_is_odysseus_checkout "$dir"; then
            printf '%s\n' "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

_bootstrap_service_workdir() {
    local service_file="$HOME/.config/systemd/user/${SERVICE_NAME:-odysseus}.service"
    [[ -r "$service_file" ]] || return 1
    local wd
    wd="$(sed -n 's/^[[:space:]]*WorkingDirectory=//p' "$service_file" | tail -n1)"
    wd="${wd%\"}"; wd="${wd#\"}"
    _bootstrap_is_odysseus_checkout "$wd" || return 1
    printf '%s\n' "$wd"
}

_bootstrap_scan_home_for_checkout() {
    local cfg dir
    command -v find >/dev/null 2>&1 || return 1
    while IFS= read -r -d '' cfg; do
        if [[ "$cfg" == */.git/config ]]; then dir="${cfg%/.git/config}"; else dir="${cfg%/.git}"; fi
        if _bootstrap_is_odysseus_checkout "$dir"; then
            printf '%s\n' "$dir"
            return 0
        fi
    done < <(
        find "$HOME" -maxdepth "$ODYSSEUS_DISCOVERY_MAXDEPTH" \
            \( -path "$HOME/.cache" -o -path "$HOME/.local/share/Trash" -o -path "$HOME/.npm" \) -prune -o \
            -type f \( -path '*/.git/config' -o -name .git \) -print0 2>/dev/null
    )
    return 1
}

_bootstrap_discover_project_dir() {
    local found="" candidate=""

    if (( PROJECT_DIR_EXPLICIT )); then
        printf 'environment|%s\n' "$PROJECT_DIR"
        return 0
    fi
    [[ "$ODYSSEUS_AUTO_DISCOVER" == "1" ]] || {
        printf 'default|%s\n' "$HOME/odysseus"
        return 0
    }

    # Strongest signals first: the script itself, the caller's cwd, then a
    # checkout referenced by a previously installed systemd user service.
    if found="$(_bootstrap_checkout_ancestor "$LAUNCH_SCRIPT_PATH" 2>/dev/null)"; then
        printf 'installer-location|%s\n' "$found"; return 0
    fi
    if found="$(_bootstrap_checkout_ancestor "$PWD" 2>/dev/null)"; then
        printf 'current-directory|%s\n' "$found"; return 0
    fi
    if found="$(_bootstrap_service_workdir 2>/dev/null)"; then
        printf 'existing-service|%s\n' "$found"; return 0
    fi

    for candidate in \
        "$HOME/odysseus" \
        "$HOME/Zarzysseus" \
        "$HOME/src/odysseus" \
        "$HOME/git/odysseus" \
        "$HOME/projects/odysseus" \
        "$HOME/Projects/odysseus" \
        "$HOME/Documents/odysseus" \
        "$HOME/Downloads/odysseus"
    do
        if _bootstrap_is_odysseus_checkout "$candidate"; then
            printf 'known-location|%s\n' "$candidate"; return 0
        fi
    done

    if found="$(_bootstrap_scan_home_for_checkout 2>/dev/null)"; then
        printf 'home-scan|%s\n' "$found"; return 0
    fi

    printf 'default|%s\n' "$HOME/odysseus"
}

_project_discovery="$(_bootstrap_discover_project_dir)"
PROJECT_DISCOVERY_SOURCE="${_project_discovery%%|*}"
PROJECT_DIR="${_project_discovery#*|}"
unset _project_discovery

MANAGED_SCRIPT_PATH="${MANAGED_SCRIPT_PATH:-$PROJECT_DIR/zarzysseus.sh}"
VENV_DIR="${VENV_DIR:-$PROJECT_DIR/venv312}"
ODYSSEUS_HOST="${ZARZYSSEUS_HOST:-${ODYSSEUS_HOST:-0.0.0.0}}"
ODYSSEUS_PORT="${ZARZYSSEUS_PORT:-${ODYSSEUS_PORT:-7000}}"
SERVICE_NAME="${SERVICE_NAME:-odysseus}"
SERVICE_FILE="$HOME/.config/systemd/user/${SERVICE_NAME}.service"
OLLAMA_SERVICE_NAME="${OLLAMA_SERVICE_NAME:-ollama-odysseus}"
OLLAMA_SERVICE_FILE="$HOME/.config/systemd/user/${OLLAMA_SERVICE_NAME}.service"
OLLAMA_SYNC_SERVICE_NAME="${OLLAMA_SYNC_SERVICE_NAME:-odysseus-ollama-sync}"
OLLAMA_SYNC_SERVICE_FILE="$HOME/.config/systemd/user/${OLLAMA_SYNC_SERVICE_NAME}.service"
OLLAMA_SYNC_TIMER_FILE="$HOME/.config/systemd/user/${OLLAMA_SYNC_SERVICE_NAME}.timer"
OLLAMA_SYNC_STATE_FILE="$PROJECT_DIR/data/local/ollama-models.sha256"
OLLAMA_ENDPOINT="http://127.0.0.1:11434"
OLLAMA_OPENAI_ENDPOINT="${OLLAMA_OPENAI_ENDPOINT:-http://127.0.0.1:11434/v1}"
OLLAMA_DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-llama3.1:8b}"
OLLAMA_PULL_DEFAULT_MODEL="${OLLAMA_PULL_DEFAULT_MODEL:-1}"
OLLAMA_SUPPORTS_TOOLS="${OLLAMA_SUPPORTS_TOOLS:-1}"
OLLAMA_MAX_LOADED_MODELS="${OLLAMA_MAX_LOADED_MODELS:-1}"
OLLAMA_CONTEXT_LENGTH="${OLLAMA_CONTEXT_LENGTH:-32768}"
SAM_MODEL_TYPE="${SAM_MODEL_TYPE:-vit_b}"
SAM_MODEL_DIR="${SAM_MODEL_DIR:-$PROJECT_DIR/models/sam}"
SAM_MARKER_FILE="${SAM_MARKER_FILE:-$PROJECT_DIR/data/local/sam_mask.installed.json}"
PLAYWRIGHT_CACHE_DIR="${PLAYWRIGHT_CACHE_DIR:-$PROJECT_DIR/data/local/playwright-mcp-cache}"
PLAYWRIGHT_BROWSERS_DIR="$PLAYWRIGHT_CACHE_DIR/browsers"
HF_HOME="${HF_HOME:-$PROJECT_DIR/data/huggingface}"
HF_HUB_CACHE="${HF_HUB_CACHE:-$HF_HOME/hub}"
COOKBOOK_STATE_FILE="${COOKBOOK_STATE_FILE:-$PROJECT_DIR/data/cookbook_state.json}"
HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"
HF_HUB_DOWNLOAD_TIMEOUT="${HF_HUB_DOWNLOAD_TIMEOUT:-300}"
HF_HUB_ETAG_TIMEOUT="${HF_HUB_ETAG_TIMEOUT:-60}"
HF_HUB_DOWNLOAD_MAX_WORKERS="${HF_HUB_DOWNLOAD_MAX_WORKERS:-4}"
ODYSSEUS_DATA_DIR="${ODYSSEUS_DATA_DIR:-$PROJECT_DIR/data}"
MODEL_MANAGER_STATE_FILE="${MODEL_MANAGER_STATE_FILE:-$PROJECT_DIR/data/local/model-manager.json}"
MODEL_MANAGER_DEFAULT_LIMIT="${MODEL_MANAGER_DEFAULT_LIMIT:-20}"
MODEL_MANAGER_USE_CASE="${MODEL_MANAGER_USE_CASE:-general}"
MODEL_MANAGER_SORT="${MODEL_MANAGER_SORT:-score}"
FULL_INSTALL_MODEL_SELECTION_TIMEOUT="${FULL_INSTALL_MODEL_SELECTION_TIMEOUT:-30}"
FULL_INSTALL_MODE_SELECTION_TIMEOUT="${FULL_INSTALL_MODE_SELECTION_TIMEOUT:-${FULL_INSTALL_MODEL_SELECTION_TIMEOUT}}"

# Frictionless bootstrap: detect the OS/package manager first, refresh/upgrade
# the system before mutating install actions, and avoid re-running a full system
# upgrade on every TUI child command by caching a successful update for a while.
SYSTEM_AUTO_UPDATE="${SYSTEM_AUTO_UPDATE:-1}"
SYSTEM_UPDATE_TTL="${SYSTEM_UPDATE_TTL:-21600}"
SYSTEM_UPDATE_FORCE="${SYSTEM_UPDATE_FORCE:-0}"
SYSTEM_UPDATE_STRICT="${SYSTEM_UPDATE_STRICT:-1}"
SYSTEM_UPDATE_STAMP_DIR="${SYSTEM_UPDATE_STAMP_DIR:-$HOME/.cache/odysseus-installer}"
SYSTEM_UPDATE_DONE_THIS_RUN=0

# Agent Skills integration. The official skills CLI is available through npx,
# so no separate global npm package is required. Global/user scope keeps skills
# available across supported agents and survives an Zarzysseus project reinstall.
SKILLS_API_BASE="${SKILLS_API_BASE:-https://skills.sh}"
SKILLS_INSTALL_SCOPE="${SKILLS_INSTALL_SCOPE:--g}"
SKILLS_SEARCH_LIMIT="${SKILLS_SEARCH_LIMIT:-8}"
SKILLS_TUI_PAGE_SIZE="${SKILLS_TUI_PAGE_SIZE:-15}"
SKILLS_TUI_FETCH_LIMIT="${SKILLS_TUI_FETCH_LIMIT:-200}"
MODEL_TUI_PAGE_SIZE="${MODEL_TUI_PAGE_SIZE:-15}"
MODEL_TUI_FETCH_LIMIT="${MODEL_TUI_FETCH_LIMIT:-200}"

# Default local model. The supplied Dolphin-Mistral-24B-Venice-Edition model
# is published with vLLM and SGLang usage instructions on Hugging Face. Keep
# the Ollama default separate because Ollama model names are not Hugging Face
# repository IDs.
DEFAULT_MODEL_ID="${DEFAULT_MODEL_ID:-dphn/Dolphin-Mistral-24B-Venice-Edition}"
DEFAULT_MODEL_PROVIDER="${DEFAULT_MODEL_PROVIDER:-vllm}"
DEFAULT_MODEL_CONTEXT_LENGTH="${DEFAULT_MODEL_CONTEXT_LENGTH:-4096}"
DEFAULT_MODEL_CONFIGURED_FILE="${DEFAULT_MODEL_CONFIGURED_FILE:-$PROJECT_DIR/data/local/default-model.configured}"

# Hardware-aware compute stack.  "auto" detects the GPU vendor and selects
# ROCm/HIP for AMD or CUDA for NVIDIA.  This is intentionally OS-aware so the
# installer uses the native system package manager where possible.
ACCELERATOR_PREFERENCE="${ACCELERATOR_PREFERENCE:-auto}"
ACCELERATOR_BACKEND="${ACCELERATOR_BACKEND:-unknown}"
GPU_VENDOR="${GPU_VENDOR:-unknown}"
GPU_NAME="${GPU_NAME:-unknown}"
GPU_ARCH="${GPU_ARCH:-unknown}"
GPU_PCI_ID="${GPU_PCI_ID:-unknown}"
GPU_DRIVER_VERSION="${GPU_DRIVER_VERSION:-unknown}"
ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
CUDA_HOME="${CUDA_HOME:-}"
ROCM_VERSION="${ROCM_VERSION:-7.2.4}"
ROCM_INSTALL_VERSION="${ROCM_INSTALL_VERSION:-7.2.4.70204-1}"
PYTORCH_ROCM_VERSION="${PYTORCH_ROCM_VERSION:-2.14.0+rocm7.2}"
PYTORCH_ROCM_TORCHVISION_VERSION="${PYTORCH_ROCM_TORCHVISION_VERSION:-0.29.0+rocm7.2}"
PYTORCH_ROCM_INDEX_URL="${PYTORCH_ROCM_INDEX_URL:-https://download.pytorch.org/whl/rocm7.2}"
PYTORCH_CUDA_VERSION="${PYTORCH_CUDA_VERSION:-2.14.0+cu130}"
PYTORCH_CUDA_TORCHVISION_VERSION="${PYTORCH_CUDA_TORCHVISION_VERSION:-0.29.0+cu130}"
PYTORCH_CUDA_INDEX_URL="${PYTORCH_CUDA_INDEX_URL:-https://download.pytorch.org/whl/cu130}"
VLLM_ROCM_VERSION="${VLLM_ROCM_VERSION:-0.29.0+rocm723}"
VLLM_ROCM_INDEX_URL="${VLLM_ROCM_INDEX_URL:-https://wheels.vllm.ai/rocm/0.29.0/rocm723}"
VLLM_CUDA_VERSION="${VLLM_CUDA_VERSION:-0.29.0}"
NVIDIA_AUTO_DRIVER="${NVIDIA_AUTO_DRIVER:-1}"
# Do not guess an open/proprietary NVIDIA kernel module for unknown/legacy GPUs.
# An explicitly selected driver package overrides automatic architecture checks.
NVIDIA_DRIVER_PACKAGE="${NVIDIA_DRIVER_PACKAGE:-auto}"
PYTORCH_XPU_INDEX_URL="${PYTORCH_XPU_INDEX_URL:-https://download.pytorch.org/whl/xpu}"
PYTORCH_CPU_INDEX_URL="${PYTORCH_CPU_INDEX_URL:-https://download.pytorch.org/whl/cpu}"
ROCM_AUTO_DRIVER="${ROCM_AUTO_DRIVER:-0}"
ACCELERATOR_STATE_FILE="${ACCELERATOR_STATE_FILE:-$PROJECT_DIR/data/local/accelerator.json}"
ACCELERATOR_REBOOT_REQUIRED_FILE="${ACCELERATOR_REBOOT_REQUIRED_FILE:-$PROJECT_DIR/data/local/reboot-required}"

# Cookbook/local serving engines live outside the core Zarzysseus venv.
# Keep vLLM and SGLang isolated from each other because they pin different
# versions of shared packages such as torch, transformers, xgrammar, etc.
COOKBOOK_LOCAL_DIR="${COOKBOOK_LOCAL_DIR:-$PROJECT_DIR/data/local}"
COOKBOOK_BIN_DIR="${COOKBOOK_BIN_DIR:-$COOKBOOK_LOCAL_DIR/bin}"
VLLM_VENV_DIR="${VLLM_VENV_DIR:-$COOKBOOK_LOCAL_DIR/venvs/vllm}"
SGLANG_VENV_DIR="${SGLANG_VENV_DIR:-$COOKBOOK_LOCAL_DIR/venvs/sglang}"
MLX_LM_VENV_DIR="${MLX_LM_VENV_DIR:-$COOKBOOK_LOCAL_DIR/venvs/mlx_lm}"
MLX_LM_MODEL_DIR="${MLX_LM_MODEL_DIR:-$COOKBOOK_LOCAL_DIR/models/mlx_lm}"
LLAMA_CPP_ENDPOINT="${LLAMA_CPP_ENDPOINT:-http://127.0.0.1:8080/v1}"
VLLM_ENDPOINT="${VLLM_ENDPOINT:-http://127.0.0.1:8000/v1}"
SGLANG_ENDPOINT="${SGLANG_ENDPOINT:-http://127.0.0.1:30000/v1}"
MLX_LM_ENDPOINT="${MLX_LM_ENDPOINT:-http://127.0.0.1:8081/v1}"
MLX_LM_SERVICE_NAME="${MLX_LM_SERVICE_NAME:-mlx-lm-odysseus}"
MLX_LM_SERVICE_FILE="$HOME/.config/systemd/user/${MLX_LM_SERVICE_NAME}.service"
MLX_LM_PID_FILE="${MLX_LM_PID_FILE:-$COOKBOOK_LOCAL_DIR/mlx_lm.server.pid}"
MLX_LM_LOG_FILE="${MLX_LM_LOG_FILE:-$COOKBOOK_LOCAL_DIR/mlx_lm.server.log}"
MLX_LM_CURRENT_MODEL_FILE="${MLX_LM_CURRENT_MODEL_FILE:-$COOKBOOK_LOCAL_DIR/mlx_lm.current-model}"
LM_STUDIO_ENDPOINT="${LM_STUDIO_ENDPOINT:-http://127.0.0.1:1234/v1}"
LOCALAI_ENDPOINT="${LOCALAI_ENDPOINT:-http://127.0.0.1:8080/v1}"
KOBOLDCPP_ENDPOINT="${KOBOLDCPP_ENDPOINT:-http://127.0.0.1:5001/v1}"
# Install local serving engines and full SAM mask dependencies by default.
# Set any of these to 0 to skip that optional component during install.
INSTALL_VLLM="${INSTALL_VLLM:-1}"
INSTALL_SGLANG="${INSTALL_SGLANG:-1}"
INSTALL_MLX_LM="${INSTALL_MLX_LM:-1}"
INSTALL_SAM_MASK_FULL="${INSTALL_SAM_MASK_FULL:-1}"
PATCH_COOKBOOK_SAM_MASK_RECIPE="${PATCH_COOKBOOK_SAM_MASK_RECIPE:-1}"
VLLM_EXTRA_INDEX_URL="${VLLM_EXTRA_INDEX_URL:-}"
# Provider preference used by the full-install model resolver. Hardware/format
# rules below still take precedence for Ollama-style names and explicit prefixes.
MODEL_AUTO_PROVIDER_ORDER="${MODEL_AUTO_PROVIDER_ORDER:-vllm,sglang,mlx_lm,ollama}"

# vLLM ROCm wheels may load libmpi_cxx.so.40 from OpenMPI 4. OpenMPI 5
# removed the C++ bindings, so keep a private OpenMPI 4.1.8 compatibility
# build for the isolated serving engines instead of replacing system OpenMPI.
OPENMPI4_VERSION="${OPENMPI4_VERSION:-4.1.8}"
OPENMPI4_PREFIX="${OPENMPI4_PREFIX:-$COOKBOOK_LOCAL_DIR/openmpi4}"
OPENMPI4_URL="${OPENMPI4_URL:-https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-${OPENMPI4_VERSION}.tar.bz2}"
OPENMPI4_SHA256="${OPENMPI4_SHA256:-466f68e3132a1dc02710cc2011fafced8336d98359fa2dae4dddcfd5719f12a9}"

case "$SAM_MODEL_TYPE" in
    vit_b) SAM_CHECKPOINT="$SAM_MODEL_DIR/sam_vit_b_01ec64.pth"; SAM_CHECKPOINT_URL="https://dl.fbaipublicfiles.com/segment_anything/sam_vit_b_01ec64.pth" ;;
    vit_l) SAM_CHECKPOINT="$SAM_MODEL_DIR/sam_vit_l_0b3195.pth"; SAM_CHECKPOINT_URL="https://dl.fbaipublicfiles.com/segment_anything/sam_vit_l_0b3195.pth" ;;
    vit_h) SAM_CHECKPOINT="$SAM_MODEL_DIR/sam_vit_h_4b8939.pth"; SAM_CHECKPOINT_URL="https://dl.fbaipublicfiles.com/segment_anything/sam_vit_h_4b3195.pth" ;;
    *) echo "ERROR: Unsupported SAM_MODEL_TYPE: $SAM_MODEL_TYPE (use vit_b, vit_l, or vit_h)"; exit 2 ;;
esac
if [[ $# -eq 0 && -t 0 && -t 1 ]]; then
    ACTION="tui"
elif [[ $# -eq 0 ]]; then
    # Non-interactive invocations keep the historical install behavior.
    ACTION="install"
else
    ACTION="${1:-install}"
fi
MODEL_ARG="${2:-}"

# The parent TUI must open cleanly. Child invocations launched by the TUI keep
# normal command output for install/download operations but suppress startup
# diagnostics such as distro detection so they do not contaminate the UI.
TUI_MODE=0
[[ "$ACTION" == "tui" ]] && TUI_MODE=1
TUI_CHILD="${ODYSSEUS_TUI_CHILD:-0}"

CHANGES_MADE=0
# Keep the path used to launch this copy separate from the managed project copy.
# LAUNCH_SCRIPT_PATH was resolved during the early checkout-discovery bootstrap.
# Once a checkout exists we prefer the managed copy so services/Cookbook recipes
# do not depend on a temporary Downloads path or on the caller's current directory.
SCRIPT_PATH="$LAUNCH_SCRIPT_PATH"
PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
VENV_PY="$VENV_DIR/bin/python"

[[ "$EUID" -eq 0 ]] && {
    echo "Do not run this script as root."
    exit 1
}

# ------------------------------------------
# Helpers
# ------------------------------------------

info() { echo "==> $1"; }
installed() { echo "    [installed] $1"; }
installing() { echo "    [installing] $1"; CHANGES_MADE=1; }

show_link() {
    echo "Zarzysseus URL: http://localhost:${ODYSSEUS_PORT}"
}

service_systemctl() {
    systemctl --user "$@"
}

service_unit="${SERVICE_NAME}.service"

# ------------------------------------------
# Installation state detection
# ------------------------------------------

repo_installed() {
    [[ -d "$PROJECT_DIR/.git" || -f "$PROJECT_DIR/.git" ]] && [[ -f "$PROJECT_DIR/app.py" || -f "$PROJECT_DIR/pyproject.toml" ]]
}

venv_installed() {
    [[ -x "$VENV_DIR/bin/python" ]]
}

service_installed() {
    [[ -f "$SERVICE_FILE" ]]
}

application_installed() {
    repo_installed && venv_installed
}

# Fetch on interactive launch, and again for explicit install/update actions.
# Keep the current branch and local work intact: NEVER reset, rebase, or force-pull.
# Untracked generated files/managed installer copies do not by themselves block
# a safe fast-forward; Git will refuse the merge if an untracked path conflicts.
refresh_existing_odysseus_checkout() {
    if ! repo_installed; then
        echo "    [repo] No existing Odysseus checkout was found at $PROJECT_DIR."
        echo "           Open Install / Update Stack to clone it, or set PROJECT_DIR."
        return 0
    fi
    if ! command -v git >/dev/null 2>&1; then
        echo '    [warning] Git is unavailable; using the existing checkout without fetching.'
        return 0
    fi

    local remote branch upstream tracked_changes local_commit remote_commit fetch_rc=0
    remote="$(git -C "$PROJECT_DIR" config --get remote.origin.url 2>/dev/null || true)"
    if [[ ! "$remote" =~ github\.com[/:]odysseus-dev/odysseus(\.git)?/?$ ]]; then
        echo '    [warning] Existing checkout has a non-upstream origin; skipping automatic Git update.'
        [[ -n "$remote" ]] && echo "              origin: $remote"
        return 0
    fi

    echo "==> Checking Odysseus upstream for $PROJECT_DIR"
    # Never hang on interactive credential requests or an indefinitely stalled fetch.
    # Fetch timeout can be raised on slower networks without touching OS packages.
    if command -v timeout >/dev/null 2>&1; then
        GIT_TERMINAL_PROMPT=0 timeout "${ZARZYSSEUS_GIT_FETCH_TIMEOUT:-60}" \
            git -C "$PROJECT_DIR" fetch --prune origin || fetch_rc=$?
    else
        GIT_TERMINAL_PROMPT=0 git -C "$PROJECT_DIR" fetch --prune origin || fetch_rc=$?
    fi
    if (( fetch_rc != 0 )); then
        echo "    [warning] Upstream fetch failed (status $fetch_rc); opening with existing code."
        return 0
    fi

    branch="$(git -C "$PROJECT_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [[ -z "$branch" ]]; then
        echo '    [warning] Checkout is on a detached HEAD; fetched but did not change its files.'
        return 0
    fi
    # Respect the branch's configured origin upstream (if any), otherwise
    # follow origin/<current-branch>. Do not switch to an unrelated default branch.
    upstream="$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    [[ "$upstream" == origin/* ]] || upstream="origin/$branch"
    if ! git -C "$PROJECT_DIR" rev-parse --verify --quiet "refs/remotes/${upstream}^{commit}" >/dev/null; then
        echo "    [warning] $upstream does not exist; fetched but left local branch $branch unchanged."
        return 0
    fi
    local_commit="$(git -C "$PROJECT_DIR" rev-parse HEAD)" || return 0
    remote_commit="$(git -C "$PROJECT_DIR" rev-parse "$upstream")" || return 0
    if [[ "$local_commit" == "$remote_commit" ]]; then
        echo "    [ready] Odysseus $branch already up to date (${local_commit:0:12})."
        return 0
    fi
    tracked_changes="$(git -C "$PROJECT_DIR" status --porcelain --untracked-files=no 2>/dev/null)" || {
        echo '    [warning] Could not inspect local Git changes; skipping the merge.'
        return 0
    }
    if [[ -n "$tracked_changes" ]]; then
        echo '    [warning] Local tracked edits exist; fetched latest, but left your files untouched.'
        return 0
    fi
    if ! git -C "$PROJECT_DIR" merge-base --is-ancestor HEAD "$upstream"; then
        echo "    [warning] $branch is ahead/diverged from $upstream; no reset or forced merge."
        return 0
    fi
    echo "    [updating] Fast-forwarding $branch to $upstream ..."
    if git -C "$PROJECT_DIR" merge --ff-only "$upstream"; then
        echo "    [ready] Odysseus now at $(git -C "$PROJECT_DIR" rev-parse --short=12 HEAD)."
    else
        echo '    [warning] Fast-forward blocked (for example, by a conflicting untracked file).'
        echo '              Existing project files remain available; inspect Git before retrying.'
    fi
    return 0
}

discover_odysseus_clones() {
    # Print unique Zarzysseus checkouts that look like this project. Keep the
    # selected PROJECT_DIR first, then common/legacy locations and finally a
    # bounded home-directory scan for renamed clones.
    local -A seen=()
    local candidate cfg dir
    for candidate in \
        "$PROJECT_DIR" \
        "$HOME/odysseus" \
        "$HOME/Zarzysseus" \
        "$HOME/src/odysseus" \
        "$HOME/git/odysseus" \
        "$HOME/projects/odysseus" \
        "$HOME/Projects/odysseus" \
        "$HOME/Documents/odysseus" \
        "$HOME/Downloads/odysseus"
    do
        [[ -n "${seen[$candidate]:-}" ]] && continue
        if _bootstrap_is_odysseus_checkout "$candidate"; then
            seen["$candidate"]=1
            printf '%s\n' "$candidate"
        fi
    done

    command -v find >/dev/null 2>&1 || return 0
    while IFS= read -r -d '' cfg; do
        if [[ "$cfg" == */.git/config ]]; then dir="${cfg%/.git/config}"; else dir="${cfg%/.git}"; fi
        [[ -n "${seen[$dir]:-}" ]] && continue
        if _bootstrap_is_odysseus_checkout "$dir"; then
            seen["$dir"]=1
            printf '%s\n' "$dir"
        fi
    done < <(
        find "$HOME" -maxdepth "$ODYSSEUS_DISCOVERY_MAXDEPTH" \
            \( -path "$HOME/.cache" -o -path "$HOME/.local/share/Trash" -o -path "$HOME/.npm" \) -prune -o \
            -type f \( -path '*/.git/config' -o -name .git \) -print0 2>/dev/null
    )
}

discover_installer_scripts() {
    local -A seen=()
    local path
    for path in "$LAUNCH_SCRIPT_PATH" "$MANAGED_SCRIPT_PATH"; do
        [[ -f "$path" ]] || continue
        [[ -n "${seen[$path]:-}" ]] && continue
        seen["$path"]=1
        printf '%s\n' "$path"
    done

    command -v find >/dev/null 2>&1 || return 0
    while IFS= read -r -d '' path; do
        [[ -n "${seen[$path]:-}" ]] && continue
        seen["$path"]=1
        printf '%s\n' "$path"
    done < <(
        find "$HOME" -maxdepth "$ODYSSEUS_DISCOVERY_MAXDEPTH" \
            \( -path "$HOME/.cache" -o -path "$HOME/.local/share/Trash" -o -path "$HOME/.npm" \) -prune -o \
            -type f \( -name 'zarzysseus.sh' -o -name 'ai-installer.sh' \) -print0 2>/dev/null
    )
}

installation_discovery_status() {
    local clones scripts path
    echo "  Selected project:     $PROJECT_DIR"
    echo "  Selection source:     $PROJECT_DISCOVERY_SOURCE"
    if repo_installed; then
        echo "  Repository:           detected"
    else
        echo "  Repository:           not present yet"
    fi
    [[ -x "$VENV_DIR/bin/python" ]] && echo "  Python environment:   detected ($VENV_DIR)" || echo "  Python environment:   not detected"
    [[ -f "$MANAGED_SCRIPT_PATH" ]] && echo "  Managed installer:    $MANAGED_SCRIPT_PATH" || echo "  Managed installer:    will use $MANAGED_SCRIPT_PATH"
    echo "  Launching installer:  $LAUNCH_SCRIPT_PATH"

    clones="$(discover_odysseus_clones || true)"
    if [[ -n "$clones" ]]; then
        echo "  Detected checkout(s):"
        while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            echo "    - $path"
        done <<< "$clones"
    fi

    scripts="$(discover_installer_scripts || true)"
    if [[ -n "$scripts" ]]; then
        echo "  Detected installer copy/copies:"
        while IFS= read -r path; do
            [[ -n "$path" ]] || continue
            echo "    - $path"
        done <<< "$scripts"
    fi
}

sync_managed_installer_copy() {
    # Keep one stable installer inside the Zarzysseus checkout. This makes the
    # installer independent of the caller's current directory and prevents
    # user services/recipes from pointing at a disposable Downloads path.
    repo_installed || return 0

    local source_path="${1:-$LAUNCH_SCRIPT_PATH}"
    mkdir -p "$(dirname "$MANAGED_SCRIPT_PATH")"

    if [[ "$source_path" != "$MANAGED_SCRIPT_PATH" ]]; then
        if [[ ! -f "$MANAGED_SCRIPT_PATH" ]] || ! cmp -s "$source_path" "$MANAGED_SCRIPT_PATH" 2>/dev/null; then
            if cp -f -- "$source_path" "$MANAGED_SCRIPT_PATH"; then
                chmod 0755 "$MANAGED_SCRIPT_PATH" 2>/dev/null || true
                if (( ! TUI_MODE )) && [[ "$TUI_CHILD" != "1" ]]; then
                    echo "    [managed] Installer copy: $MANAGED_SCRIPT_PATH"
                fi
            else
                echo "    [warning] Could not refresh managed installer copy at $MANAGED_SCRIPT_PATH"
                echo "              Continuing with: $source_path"
                return 0
            fi
        else
            chmod 0755 "$MANAGED_SCRIPT_PATH" 2>/dev/null || true
        fi
    else
        chmod 0755 "$MANAGED_SCRIPT_PATH" 2>/dev/null || true
    fi

    # From this point on, child commands, systemd units, and generated recipes
    # should reference the stable project-local copy.
    if [[ -f "$MANAGED_SCRIPT_PATH" ]]; then
        SCRIPT_PATH="$MANAGED_SCRIPT_PATH"
    fi
}

enter_odysseus_project() {
    # Bash cannot change the parent terminal's cwd after the script exits, but
    # every action executed by this script can (and should) run from PROJECT_DIR.
    repo_installed || return 1
    cd "$PROJECT_DIR"
}

prepare_project_runtime_context() {
    # If Zarzysseus is already present, normalize the installer path and working
    # directory before dispatching ANY command. If it is not present yet,
    # install_odysseus() will clone it and call the same setup immediately.
    if repo_installed; then
        sync_managed_installer_copy "$LAUNCH_SCRIPT_PATH"
        enter_odysseus_project
    fi
}

ollama_service_installed() {
    [[ -f "$OLLAMA_SERVICE_FILE" ]]
}

mlx_lm_service_installed() {
    [[ -f "$MLX_LM_SERVICE_FILE" ]]
}

ollama_binary_installed() {
    command -v ollama >/dev/null 2>&1
}

ollama_running() {
    ollama_api_ready
}

ollama_api_ready() {
    command -v curl >/dev/null 2>&1 || return 1
    curl -fsS --max-time 3 "$OLLAMA_ENDPOINT/api/tags" >/dev/null 2>&1
}

ollama_model_names() {
    curl -fsS --max-time 5 "$OLLAMA_ENDPOINT/api/tags" | \
        python3 -c 'import json,sys; d=json.load(sys.stdin); print("\n".join(str(m.get("name","")).strip() for m in d.get("models",[]) if m.get("name")))'
}

ollama_has_model() {
    local wanted="$1"
    ollama_model_names | grep -Fxq "$wanted"
}

write_env_value() {
    local file="$1" key="$2" value="$3"
    touch "$file"
    if grep -qE "^[[:space:]]*${key}=" "$file"; then
        python3 - "$file" "$key" "$value" <<'PY'
from pathlib import Path
import sys
path_str, key, value = sys.argv[1:]
path = Path(path_str)
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
out = []
replaced = False
for line in lines:
    if line.lstrip().startswith(key + "="):
        out.append(f"{key}={value}")
        replaced = True
    else:
        out.append(line)
if not replaced:
    out.append(f"{key}={value}")
path.write_text("\n".join(out) + "\n", encoding="utf-8")
PY
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

configure_ollama_environment() {
    local env_file="$PROJECT_DIR/.env"
    info "Configuring Zarzysseus to use local Ollama..."
    write_env_value "$env_file" "ODYSSEUS_DATA_DIR" "$ODYSSEUS_DATA_DIR"
    write_env_value "$env_file" "LLM_HOST" "127.0.0.1"
    write_env_value "$env_file" "LLM_HOSTS" "127.0.0.1"
    write_env_value "$env_file" "OLLAMA_BASE_URL" "$OLLAMA_OPENAI_ENDPOINT"
    write_env_value "$env_file" "OLLAMA_HOST" "127.0.0.1:11434"
    write_env_value "$env_file" "OLLAMA_ORIGINS" "http://localhost,http://127.0.0.1"
    write_env_value "$env_file" "HF_HOME" "$HF_HOME"
    write_env_value "$env_file" "HUGGINGFACE_HUB_CACHE" "$HF_HUB_CACHE"
    write_env_value "$env_file" "HF_HUB_CACHE" "$HF_HUB_CACHE"
    write_env_value "$env_file" "HF_HUB_DISABLE_XET" "$HF_HUB_DISABLE_XET"
    write_env_value "$env_file" "HF_HUB_ENABLE_HF_TRANSFER" "0"
    write_env_value "$env_file" "HF_HUB_DOWNLOAD_TIMEOUT" "$HF_HUB_DOWNLOAD_TIMEOUT"
    write_env_value "$env_file" "HF_HUB_ETAG_TIMEOUT" "$HF_HUB_ETAG_TIMEOUT"
    write_env_value "$env_file" "HF_HUB_DOWNLOAD_MAX_WORKERS" "$HF_HUB_DOWNLOAD_MAX_WORKERS"
    installed "Ollama + Hugging Face endpoint configuration ($env_file)"
}

mask_hf_token() {
    local token="${1:-}"
    if [[ -z "$token" ]]; then
        echo "NOT SET"
    elif [[ ${#token} -le 8 ]]; then
        echo "stored"
    else
        echo "${token:0:4}...${token: -4}"
    fi
}

get_hf_token() {
    if [[ -f "$COOKBOOK_STATE_FILE" ]] && [[ -x "$VENV_DIR/bin/python" ]]; then
        ODYSSEUS_DATA_DIR="$ODYSSEUS_DATA_DIR" "$VENV_DIR/bin/python" - "$COOKBOOK_STATE_FILE" <<'PYHFGET' 2>/dev/null || true
import json, sys
from pathlib import Path
try:
    from src.secret_storage import decrypt
    p = Path(sys.argv[1])
    state = json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}
    env = state.get("env") if isinstance(state, dict) else {}
    raw = env.get("hfToken") if isinstance(env, dict) else ""
    print(decrypt(raw or ""))
except Exception:
    pass
PYHFGET
    fi
    if [[ -f "$PROJECT_DIR/.env" ]]; then
        awk -F= '$1=="HF_TOKEN" {sub(/^[^=]*=/,""); print; exit}' "$PROJECT_DIR/.env" 2>/dev/null || true
    fi
}

set_hf_token() {
    local token="${1:-}"
    echo "Hugging Face setup (recommended for Linux and Windows):"
    echo "  1. Sign in at https://huggingface.co/"
    echo "  2. Create a Read or fine-grained read token: https://huggingface.co/settings/tokens"
    echo "  3. Accept the model license/request access on gated model pages first."
    echo "  4. Paste your token below; input is hidden. Never add tokens to your GitHub repo."
    if [[ -z "$token" ]]; then
        read -r -s -p "Hugging Face token (input hidden): " token
        echo
    fi
    [[ -n "$token" ]] || { echo "ERROR: No Hugging Face token supplied."; return 2; }

    application_installed || install_odysseus
    mkdir -p "$PROJECT_DIR/data"
    write_env_value "$PROJECT_DIR/.env" "HF_TOKEN" "$token"
    write_env_value "$PROJECT_DIR/.env" "HUGGING_FACE_HUB_TOKEN" "$token"
    write_env_value "$PROJECT_DIR/.env" "HF_HOME" "$HF_HOME"
    write_env_value "$PROJECT_DIR/.env" "HUGGINGFACE_HUB_CACHE" "$HF_HUB_CACHE"
    write_env_value "$PROJECT_DIR/.env" "HF_HUB_CACHE" "$HF_HUB_CACHE"
    write_env_value "$PROJECT_DIR/.env" "HF_HUB_DISABLE_XET" "$HF_HUB_DISABLE_XET"
    write_env_value "$PROJECT_DIR/.env" "HF_HUB_ENABLE_HF_TRANSFER" "0"
    write_env_value "$PROJECT_DIR/.env" "HF_HUB_DOWNLOAD_TIMEOUT" "$HF_HUB_DOWNLOAD_TIMEOUT"
    write_env_value "$PROJECT_DIR/.env" "HF_HUB_ETAG_TIMEOUT" "$HF_HUB_ETAG_TIMEOUT"
    write_env_value "$PROJECT_DIR/.env" "HF_HUB_DOWNLOAD_MAX_WORKERS" "$HF_HUB_DOWNLOAD_MAX_WORKERS"
    chmod 600 "$PROJECT_DIR/.env" 2>/dev/null || true

    ODYSSEUS_DATA_DIR="$ODYSSEUS_DATA_DIR" "$VENV_DIR/bin/python" - "$COOKBOOK_STATE_FILE" "$token" <<'PYHFSET'
import json, sys
from pathlib import Path
from src.secret_storage import encrypt
path = Path(sys.argv[1]); token = sys.argv[2]
try:
    state = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
except Exception:
    state = {}
if not isinstance(state, dict): state = {}
env = state.get("env") if isinstance(state.get("env"), dict) else {}
env["hfToken"] = encrypt(token)
state["env"] = env
path.parent.mkdir(parents=True, exist_ok=True)
tmp = path.with_suffix(path.suffix + ".tmp")
tmp.write_text(json.dumps(state, indent=2), encoding="utf-8")
tmp.replace(path)
PYHFSET

    if service_installed && service_systemctl is-active --quiet "$service_unit" 2>/dev/null; then
        service_systemctl restart "$service_unit"
    fi
    echo "Hugging Face token stored: $(mask_hf_token "$token")"
    echo "Hugging Face token is persisted for Zarzysseus Cookbook downloads."
    show_link
}

clear_hf_token() {
    application_installed || { echo "Hugging Face token is not configured."; return 0; }
    [[ -f "$PROJECT_DIR/.env" ]] && {
        write_env_value "$PROJECT_DIR/.env" "HF_TOKEN" ""
        write_env_value "$PROJECT_DIR/.env" "HUGGING_FACE_HUB_TOKEN" ""
    }
    if [[ -x "$VENV_DIR/bin/python" ]]; then
        ODYSSEUS_DATA_DIR="$ODYSSEUS_DATA_DIR" "$VENV_DIR/bin/python" - "$COOKBOOK_STATE_FILE" <<'PYHFCLR'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
try:
    state = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
except Exception:
    state = {}
env = state.get("env") if isinstance(state, dict) else None
if isinstance(env, dict):
    env.pop("hfToken", None)
path.parent.mkdir(parents=True, exist_ok=True)
tmp = path.with_suffix(path.suffix + ".tmp")
tmp.write_text(json.dumps(state, indent=2), encoding="utf-8")
tmp.replace(path)
PYHFCLR
    fi
    if service_installed && service_systemctl is-active --quiet "$service_unit" 2>/dev/null; then
        service_systemctl restart "$service_unit"
    fi
    echo "Hugging Face token cleared."
    show_link
}

hf_token_status() {
    local token
    token="$(get_hf_token | sed '/^$/d' | head -n1 || true)"
    echo "Hugging Face token: $(mask_hf_token "$token")"
    echo "Hugging Face cache: $HF_HUB_CACHE"
    [[ -d "$HF_HUB_CACHE" ]] && echo "Cache directory:    EXISTS" || echo "Cache directory:    NOT CREATED"
    show_link
}

ensure_hf_cli() {
    [[ -x "$VENV_DIR/bin/python" ]] || { echo "ERROR: Zarzysseus virtual environment is missing."; return 1; }
    [[ -x "$VENV_DIR/bin/hf" ]] && return 0
    echo "    [installing] huggingface-hub CLI"
    "$VENV_DIR/bin/python" -m pip install -U "huggingface_hub[cli]"
    [[ -x "$VENV_DIR/bin/hf" ]]
}

hf_cache_repo_dir() {
    local repo="$1"
    echo "$HF_HUB_CACHE/models--${repo//\//--}"
}

hf_cache_complete() {
    local repo="$1" cache snap
    cache="$(hf_cache_repo_dir "$repo")"
    [[ -d "$cache/snapshots" ]] || return 1
    ! find "$cache/blobs" -type f -name '*.incomplete' -print -quit 2>/dev/null | grep -q . || return 1
    while IFS= read -r snap; do
        # A Diffusers pipeline has model_index.json plus component subfolders;
        # a GGUF repo may contain nothing but a .gguf weight. Follow Hub symlinks.
        if find -L "$snap" -type f \
             \( -name '*.safetensors' -o -name '*.bin' -o -name '*.gguf' -o -name '*.pt' \) \
             -print -quit 2>/dev/null | grep -q .; then
            if [[ -f "$snap/model_index.json" || -f "$snap/config.json" ]] || \
                find -L "$snap" -type f -name '*.gguf' -print -quit 2>/dev/null | grep -q .; then
                return 0
            fi
        fi
    done < <(find "$cache/snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
    return 1
}

repair_cookbook_download_tasks() {
    local repo="$1"
    [[ -f "$COOKBOOK_STATE_FILE" ]] || return 0
    ODYSSEUS_DATA_DIR="$ODYSSEUS_DATA_DIR" "$VENV_DIR/bin/python" - "$COOKBOOK_STATE_FILE" "$repo" <<'PYHFREPAIR'
import json, sys, subprocess, time
from pathlib import Path
path=Path(sys.argv[1]); repo=sys.argv[2]
try:
    state=json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
except Exception:
    state={}
if not isinstance(state,dict): sys.exit(0)
raw_tasks=state.get("tasks",[])
tasks=list(raw_tasks.values()) if isinstance(raw_tasks,dict) else raw_tasks
if not isinstance(tasks,list): tasks=[]
changed=False
now=int(time.time()*1000)
for task in tasks:
    if not isinstance(task,dict) or task.get("type","download") != "download" or task.get("remoteHost"): continue
    payload=task.get("payload") or {}
    model=(task.get("repoId") or task.get("modelId") or payload.get("repo_id") or task.get("name") or "").strip()
    if model != repo: continue
    sid=str(task.get("sessionId") or "")
    if sid.startswith("cookbook-"):
        subprocess.run(["tmux","kill-session","-t",sid],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    old=(task.get("output") or "").rstrip()
    marker=f"DOWNLOAD_OK\nCompleted externally by odysseusinstaller hf-pull for {repo}."
    task["status"]="done"
    task["output"]=(old+"\n"+marker).strip()
    task["ts"]=now
    changed=True
if changed: state["tasks"]=tasks
tmp=path.with_suffix(path.suffix+".tmp")
tmp.write_text(json.dumps(state,indent=2),encoding="utf-8")
tmp.replace(path)
if changed: print("Cookbook download tasks reconciled for",repo)
PYHFREPAIR
}

hf_pull_model() {
    local repo="$1"
    local include_pattern="${2:-}"
    [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]+/[A-Za-z0-9][A-Za-z0-9._-]+$ ]] || { echo "ERROR: Hugging Face model must be <org>/<model>"; return 2; }
    application_installed || install_odysseus
    ensure_hf_cli || return 1
    mkdir -p "$HF_HUB_CACHE"
    local token
    token="$(get_hf_token | sed '/^$/d' | head -n1 || true)"
    [[ -n "$token" ]] || echo "    [warning] HF token is not set; public models can still download, gated/private models cannot."
    export HF_HOME="$HF_HOME" HUGGINGFACE_HUB_CACHE="$HF_HUB_CACHE" HF_HUB_CACHE="$HF_HUB_CACHE"
    export HF_HUB_DISABLE_XET="$HF_HUB_DISABLE_XET" HF_HUB_ENABLE_HF_TRANSFER=0
    export HF_HUB_DOWNLOAD_TIMEOUT="$HF_HUB_DOWNLOAD_TIMEOUT" HF_HUB_ETAG_TIMEOUT="$HF_HUB_ETAG_TIMEOUT" HF_HUB_DOWNLOAD_MAX_WORKERS="$HF_HUB_DOWNLOAD_MAX_WORKERS"
    [[ -n "$token" ]] && export HF_TOKEN="$token" HUGGING_FACE_HUB_TOKEN="$token"

    info "Downloading Hugging Face model: $repo"
    echo "    Cache: $HF_HUB_CACHE"
    [[ -n "$include_pattern" ]] && echo "    Include: $include_pattern"
    echo "    Xet:   disabled (resumable HTTP cache mode)"
    local attempt=0 rc=1
    while (( attempt < 10 )); do
        ((attempt+=1))
        set +e
        if [[ -n "$include_pattern" ]]; then
            "$VENV_DIR/bin/hf" download "$repo" --include "$include_pattern"
        else
            "$VENV_DIR/bin/hf" download "$repo"
        fi
        rc=$?
        set -e
        (( rc == 0 )) && break
        echo "    [retry] Hugging Face download attempt $attempt failed (exit $rc)."
        (( attempt < 10 )) && sleep 15
    done
    (( rc == 0 )) || { echo "ERROR: Hugging Face download failed after $attempt attempts."; return "$rc"; }

    if ! hf_cache_complete "$repo"; then
        echo "ERROR: Hugging Face returned success but the cache is not complete for $repo."
        return 1
    fi
    repair_cookbook_download_tasks "$repo"
    echo "[complete] $repo is fully cached and Cookbook task state was reconciled."
    show_link
}


# ------------------------------------------
# Unified local model manager
# ------------------------------------------

model_manager_ensure() {
    # The manual picker must be read-only until a model is confirmed. In this
    # mode do not run install_odysseus, pip, mkdir or any system update.
    if [[ "${MODEL_MANAGER_BROWSE_ONLY:-0}" == 1 ]]; then
        [[ -x "$VENV_PY" ]] || return 1
        "$VENV_PY" -c 'import huggingface_hub' >/dev/null 2>&1 || return 1
        return 0
    fi
    application_installed || install_odysseus
    [[ -x "$VENV_DIR/bin/python" ]] || { echo "ERROR: Zarzysseus virtual environment is missing."; return 1; }
    ensure_hf_cli || return 1
    mkdir -p "$HF_HUB_CACHE" "$(dirname "$MODEL_MANAGER_STATE_FILE")"
}

model_manager_providers() {
    echo "=========================================="
    echo "Zarzysseus local model providers"
    echo "=========================================="
    printf '%-14s %-11s %-7s %s\n' "PROVIDER" "ROLE" "STATUS" "ENDPOINT / NOTES"
    printf '%-14s %-11s %-7s %s\n' "Ollama" "runtime" "$(ollama_api_ready && echo ONLINE || echo offline)" "$OLLAMA_OPENAI_ENDPOINT"
    printf '%-14s %-11s %-7s %s\n' "Hugging Face" "model hub" "READY" "$HF_HUB_CACHE"
    printf '%-14s %-11s %-7s %s\n' "llama.cpp" "runtime" "$(curl -fsS --max-time 2 "$LLAMA_CPP_ENDPOINT/models" >/dev/null 2>&1 && echo ONLINE || echo offline)" "$LLAMA_CPP_ENDPOINT"
    printf '%-14s %-11s %-7s %s\n' "vLLM" "runtime" "$(curl -fsS --max-time 2 "$VLLM_ENDPOINT/models" >/dev/null 2>&1 && echo ONLINE || echo offline)" "$VLLM_ENDPOINT"
    printf '%-14s %-11s %-7s %s\n' "SGLang" "runtime" "$(curl -fsS --max-time 2 "$SGLANG_ENDPOINT/models" >/dev/null 2>&1 && echo ONLINE || echo offline)" "$SGLANG_ENDPOINT"
    printf '%-14s %-11s %-7s %s\n' "MLX-LM" "runtime" "$(mlx_lm_api_ready && echo ONLINE || { "$VENV_PY" -c 'import importlib.metadata as m; m.version("mlx-lm")' >/dev/null 2>&1 && echo INSTALLED || echo offline; })" "$MLX_LM_ENDPOINT"
    printf '%-14s %-11s %-7s %s\n' "LM Studio" "runtime" "$(curl -fsS --max-time 2 "$LM_STUDIO_ENDPOINT/models" >/dev/null 2>&1 && echo ONLINE || echo offline)" "$LM_STUDIO_ENDPOINT"
    printf '%-14s %-11s %-7s %s\n' "LocalAI" "runtime" "$(curl -fsS --max-time 2 "$LOCALAI_ENDPOINT/models" >/dev/null 2>&1 && echo ONLINE || echo offline)" "$LOCALAI_ENDPOINT"
    printf '%-14s %-11s %-7s %s\n' "KoboldCpp" "runtime" "$(curl -fsS --max-time 2 "$KOBOLDCPP_ENDPOINT/models" >/dev/null 2>&1 && echo ONLINE || echo offline)" "$KOBOLDCPP_ENDPOINT"
    echo
    echo "HF = model source. The others are local inference runtimes exposing an OpenAI-style API."
    echo "Endpoint reachability is only a connectivity check; overlapping default ports can be overridden with env vars."
}

model_manager_rank() {
    local use_case="${1:-$MODEL_MANAGER_USE_CASE}"
    local limit="${2:-$MODEL_MANAGER_DEFAULT_LIMIT}"
    local search="${3:-}"
    local sort="${4:-$MODEL_MANAGER_SORT}"
    local fit_only="${5:-0}"

    model_manager_ensure || return 1
    "$VENV_DIR/bin/python" - "$use_case" "$limit" "$search" "$sort" "$fit_only" <<'PY_MODEL_LIST'
import sys
from services.hwfit.hardware import detect_system
from services.hwfit.fit import rank_models

use_case, limit, search, sort, fit_only = sys.argv[1:]
try:
    limit = max(1, min(int(limit), 200))
except Exception:
    limit = 20
fit_only = bool(int(fit_only or 0))
system = detect_system(fresh=True)
if system.get("error"):
    print("ERROR: " + str(system["error"]), file=sys.stderr)
    raise SystemExit(1)
print("Hardware: {} | RAM: {} GB | GPU: {} | VRAM: {} GB | backend: {}".format(
    system.get("cpu_name") or "unknown",
    system.get("total_ram_gb") or "?",
    system.get("gpu_name") or "CPU-only",
    system.get("gpu_vram_gb") or 0,
    system.get("backend") or "cpu",
))
print("Use case: {} | sort: {} | fit-only: {}".format(use_case or "general", sort or "score", fit_only))
print()
print(f"{'#':>3}  {'MODEL':<44} {'PARAMS':>8} {'QUANT':<12} {'NEED':>7} {'TOK/S':>8} {'FIT':<10} {'SCORE':>6}")
print("-" * 110)
rows = rank_models(system, use_case=(use_case or None), limit=limit, search=(search or None), sort=sort or "score", fit_only=fit_only)
for i, r in enumerate(rows, 1):
    name = str(r.get("name") or "-")
    if len(name) > 44: name = name[:41] + "..."
    params = str(r.get("parameter_count") or f"{r.get('params_b', 0):.1f}B")
    quant = str(r.get("quant") or "?")
    need = f"{float(r.get('required_gb') or 0):.1f}G"
    tps = f"{float(r.get('speed_tps') or 0):.1f}"
    fit = str(r.get("fit_level") or "?")
    score = f"{float(r.get('score') or 0):.1f}"
    print(f"{i:>3}  {name:<44} {params:>8} {quant:<12} {need:>7} {tps:>8} {fit:<10} {score:>6}")
print()
print("Score = Zarzysseus hardware-fit composite. TOK/S = Zarzysseus's estimate, not a live benchmark.")
print("Use 'model-pick' to choose a fitting row and download its HF source/quant automatically.")
PY_MODEL_LIST
}

model_manager_rank_json() {
    local use_case="${1:-$MODEL_MANAGER_USE_CASE}"
    local limit="${2:-$MODEL_MANAGER_DEFAULT_LIMIT}"
    local search="${3:-}"
    local sort="${4:-$MODEL_MANAGER_SORT}"
    local fit_only="${5:-0}"
    model_manager_ensure || return 1
    "$VENV_DIR/bin/python" - "$use_case" "$limit" "$search" "$sort" "$fit_only" <<'PY_MODEL_JSON'
import json, sys
from services.hwfit.hardware import detect_system
from services.hwfit.fit import rank_models
use_case, limit, search, sort, fit_only = sys.argv[1:]
limit = max(1, min(int(limit), 200))
system = detect_system(fresh=True)
if system.get("error"):
    raise SystemExit(str(system["error"]))
rows = rank_models(system, use_case=(use_case or None), limit=limit, search=(search or None), sort=sort or "score", fit_only=bool(int(fit_only or 0)))
print(json.dumps({"hardware": system, "models": rows}, ensure_ascii=False))
PY_MODEL_JSON
}

model_manager_image_json() {
    local limit="${1:-$MODEL_MANAGER_DEFAULT_LIMIT}"
    local search="${2:-}"

    model_manager_ensure || return 1
    "$VENV_DIR/bin/python" - "$limit" "$search" <<'PY_IMAGE_MODEL_JSON'
import json
import math
import re
import sys

from huggingface_hub import HfApi

try:
    from services.hwfit.hardware import detect_system
except Exception:
    detect_system = None

limit_raw, search = sys.argv[1:]
try:
    limit = max(1, min(int(limit_raw), 200))
except Exception:
    limit = 50

api = HfApi()
pipeline_specs = (
    ("text-to-image", "image"),
    ("image-to-image", "image"),
    ("unconditional-image-generation", "image"),
    ("text-to-video", "video"),
    ("image-to-video", "video"),
    ("video-to-video", "video"),
)
per_tag = max(10, min(200, math.ceil(limit * 1.6 / len(pipeline_specs)) + 6))
models = {}

system = {}
if detect_system is not None:
    try:
        system = detect_system(fresh=True) or {}
    except Exception:
        system = {}

gpu_vram = float(system.get("gpu_vram_gb") or 0.0)
ram_gb = float(system.get("system_ram_gb") or system.get("ram_gb") or system.get("memory_gb") or 0.0)
backend = str(system.get("backend") or ("gpu" if gpu_vram > 0 else "cpu")).lower()

def attr(obj, name, default=None):
    value = getattr(obj, name, default)
    return default if value is None else value

def get_used_storage(info):
    for name in ("used_storage", "usedStorage"):
        value = getattr(info, name, None)
        if value is not None:
            try:
                return int(value)
            except Exception:
                pass
    return None

def _value(obj, key, default=None):
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)

def safetensor_param_map(info):
    st = getattr(info, "safetensors", None)
    if st is None:
        return {}
    for key in ("parameters", "parameter_count"):
        value = _value(st, key)
        if isinstance(value, dict) and value:
            out = {}
            for dtype, count in value.items():
                try:
                    out[str(dtype).upper()] = float(count)
                except Exception:
                    pass
            if out:
                return out
    # Compatibility with older/newer SafeTensorsInfo serializers.
    if isinstance(st, dict):
        for value in st.values():
            if isinstance(value, dict) and value:
                try:
                    out = {str(k).upper(): float(v) for k, v in value.items()}
                except Exception:
                    continue
                if out and all(v >= 0 for v in out.values()):
                    return out
    return {}

def get_params(info):
    st = getattr(info, "safetensors", None)
    if st is None:
        return None
    for key in ("total", "parameter_count", "parameters"):
        value = _value(st, key)
        if isinstance(value, dict):
            try:
                return float(sum(float(v) for v in value.values()))
            except Exception:
                continue
        if value is not None:
            try:
                return float(value)
            except Exception:
                pass
    pmap = safetensor_param_map(info)
    if pmap:
        return float(sum(pmap.values()))
    return None

def precision_from_safetensors(info):
    pmap = safetensor_param_map(info)
    if not pmap:
        return None
    # Pick the dtype holding the largest share of parameters.
    dtype = max(pmap.items(), key=lambda kv: kv[1])[0].upper()
    aliases = {
        "F64": "FP64", "F32": "FP32", "F16": "FP16", "BF16": "BF16",
        "F8_E4M3": "FP8", "F8_E5M2": "FP8", "FP8": "FP8",
        "I8": "INT8", "U8": "INT8", "I4": "INT4", "U4": "INT4",
    }
    return aliases.get(dtype, dtype[:10])

def precision_from_tags(tags):
    joined = " ".join(str(t).lower() for t in tags)
    checks = (
        ("FP8", ("fp8", "float8")),
        ("BF16", ("bf16", "bfloat16")),
        ("FP16", ("fp16", "float16", "half")),
        ("INT8", ("int8", "8-bit", "8bit")),
        ("INT4", ("int4", "4-bit", "4bit")),
    )
    for label, needles in checks:
        if any(n in joined for n in needles):
            return label
    return "-"

def is_auxiliary(tags):
    lowered = {str(t).lower() for t in tags}
    bad_exact = {
        "lora", "adapter", "adapters", "controlnet", "textual-inversion",
        "ip-adapter", "vae", "upscaler"
    }
    return bool(lowered & bad_exact)

def quant_bits(label):
    q = str(label or "").upper()
    if any(token in q for token in ("F32", "FP32", "FLOAT32")):
        return 32.0
    if any(token in q for token in ("BF16", "F16", "FP16", "FLOAT16")):
        return 16.0
    if "FP8" in q or "INT8" in q:
        return 8.0
    if "INT4" in q:
        return 4.0
    return 16.0

def estimate_params_from_identity(repo, pipeline, tags, library_name, model_kind):
    """Best-effort fallback when the Hub does not expose safetensors counts.

    Keep estimates visibly marked with '~'.  Explicit parameter counts embedded
    in repo/tag names win; otherwise use conservative architecture-family
    estimates so the TUI never has to rank every media model as the same tiny
    1.8/5.2 GB placeholder.
    """
    text = " ".join([
        str(repo or ""), str(pipeline or ""), str(library_name or ""),
        " ".join(str(t) for t in (tags or [])),
    ]).lower()

    # Explicit counts in names/tags: 1.7B, 5B, 14B, 700M, etc.
    # Require the unit so resolution/version numbers (1024, v1.5, H3...) are
    # never mistaken for parameter counts.
    matches = re.findall(r"(?<![a-z0-9])([0-9]+(?:\.[0-9]+)?)\s*([bm])(?:[^a-z]|$)", text)
    if matches:
        values = []
        for number, unit in matches:
            try:
                value = float(number)
                if unit == "m":
                    value /= 1000.0
                if 0.03 <= value <= 250:
                    values.append(value)
            except Exception:
                pass
        if values:
            # Model names can mention several components; the largest count is
            # normally the main denoiser/transformer and best for VRAM fitting.
            return max(values), "name"

    # Well-known image-generation architecture families.  These are estimates
    # of the main generative network / effective model parameter scale, not an
    # assertion that every auxiliary VAE/text encoder is included.
    image_families = (
        (("flux",), 12.0),
        (("qwen-image", "qwen/image", "qwen_image"), 20.0),
        (("stable-diffusion-3", "sd3-medium", "sd3.5-medium"), 2.0),
        (("sd3.5-large", "stable-diffusion-3.5-large"), 8.1),
        (("sdxl", "stable-diffusion-xl", "playground-v2", "playground-v2.5", "juggernaut-xl"), 2.6),
        (("stable-diffusion-v1", "stable-diffusion-1", "sd-v1", "sd1.5", "dreamshaper", "realistic_vision", "realistic-vision", "revanimated", "revanimated"), 0.86),
        (("stable-diffusion-v2", "stable-diffusion-2", "sd-v2", "sd2.1"), 0.87),
        (("pixart",), 0.6),
        (("auraflow",), 6.8),
        (("kolors",), 2.6),
    )

    video_families = (
        (("hunyuanvideo", "hunyuan-video"), 13.0),
        (("mochi",), 10.0),
        (("cogvideox",), 5.0),
        (("ltx-video", "ltx_video"), 2.0),
        (("opensora", "open-sora"), 1.1),
        (("i2vgen",), 1.4),
        (("wan2.1", "wan-2.1", "wan2.2", "wan-2.2", "wan2", "wan-video"), 5.0),
        (("minimax-h3", "minimax_h3", "minimax h3"), 5.0),
        (("seedvr2",), 7.0),
        (("fastvideo",), 5.0),
    )

    families = video_families if model_kind == "video" else image_families
    for needles, estimate in families:
        if any(token in text for token in needles):
            return estimate, "family"

    # Final fallback is deliberately approximate but still useful for hardware
    # sorting. The '~' marker in the TUI makes it clear this is not Hub metadata.
    return (5.0, "generic") if model_kind == "video" else (0.9, "generic")

def estimate_required_gb(repo, pipeline, params_b, size_gb, quant, tags, library_name):
    bits = quant_bits(quant)
    weight_gb = 0.0
    if params_b:
        weight_gb = (float(params_b) * bits / 8.0) * 1.05
    elif size_gb:
        weight_gb = max(float(size_gb) * 0.72, 0.75)
    text = " ".join([str(repo or ""), str(pipeline or ""), str(library_name or ""), " ".join(str(t) for t in (tags or []))]).lower()
    is_video = "video" in str(pipeline or "").lower() or any(token in text for token in (
        "video", "wan", "hunyuanvideo", "cogvideo", "ltx-video", "mochi", "opensora", "genmo"
    ))
    if is_video:
        if any(token in text for token in ("hunyuanvideo", "wan2", "wan-2", "cogvideox-5b", "cogvideox5b", "mochi", "opensora")):
            overhead = 8.5
        elif any(token in text for token in ("ltx", "ltx-video", "cogvideo", "animate", "i2vgen")):
            overhead = 6.5
        elif "image-to-video" in str(pipeline or "").lower() or "video-to-video" in str(pipeline or "").lower():
            overhead = 5.8
        else:
            overhead = 5.2
    elif "flux" in text:
        overhead = 4.5
    elif any(token in text for token in ("sdxl", "stable-diffusion-xl", "xl-base", "xl-refiner", "kolors")):
        overhead = 3.0
    elif any(token in text for token in ("stable-diffusion-3", "sd3", "pixart", "auraflow", "hunyuan")):
        overhead = 3.8
    elif pipeline == "image-to-image":
        overhead = 2.3
    else:
        overhead = 1.8
    floor = (float(size_gb) * (0.98 if is_video else 0.92) + (2.0 if is_video else 1.1)) if size_gb else 0.0
    required = max(weight_gb + overhead, floor, 2.2 if is_video else 1.2)
    return round(required, 1)

def derive_fit(required):
    req = float(required or 0.0)
    if req <= 0:
        return "?"
    if gpu_vram > 0:
        if req <= gpu_vram * 0.65:
            return "perfect"
        if req <= gpu_vram * 0.85:
            return "good"
        if req <= gpu_vram * 1.0:
            return "tight"
        if ram_gb and req <= ram_gb * 0.60:
            return "cpu_offload"
        return "poor"
    if ram_gb > 0:
        if req <= ram_gb * 0.30:
            return "good"
        if req <= ram_gb * 0.45:
            return "tight"
        return "poor"
    return "manual"

def derive_score(required, fit_level, downloads, likes):
    fit_component = {
        "perfect": 55.0,
        "good": 46.0,
        "tight": 36.0,
        "cpu_offload": 28.0,
        "manual": 24.0,
        "poor": 12.0,
        "?": 18.0,
    }.get(fit_level, 18.0)
    req = max(float(required or 0.0), 0.1)
    efficiency = max(0.0, 18.0 - min(req, 24.0) * 0.45)
    popularity = min(20.0, math.log10(float(downloads or 0) + 10.0) * 5.5 + math.log10(float(likes or 0) + 10.0) * 2.5)
    backend_bonus = 6.0 if gpu_vram > 0 and backend != "cpu" else 0.0
    return round(fit_component + efficiency + popularity + backend_bonus, 1)

def fetch(tag):
    kwargs = dict(
        pipeline_tag=tag,
        search=(search or None),
        sort="downloads",
        limit=per_tag,
    )
    try:
        return list(api.list_models(
            **kwargs,
            expand=[
                "downloads", "likes", "pipeline_tag", "usedStorage",
                "safetensors", "tags", "library_name"
            ],
        ))
    except (TypeError, ValueError):
        # Older huggingface_hub releases do not support `expand`.  `full=True`
        # asks the Hub for the richer ModelInfo payload in those releases.
        try:
            return list(api.list_models(**kwargs, full=True))
        except (TypeError, ValueError):
            return list(api.list_models(**kwargs))

for tag, model_kind in pipeline_specs:
    try:
        infos = fetch(tag)
    except Exception:
        continue
    for info in infos:
        repo = str(attr(info, "id", "") or "").strip()
        if not repo or "/" not in repo:
            continue
        tags = list(attr(info, "tags", []) or [])
        if is_auxiliary(tags):
            continue
        pipeline = str(attr(info, "pipeline_tag", "") or tag)
        downloads = int(attr(info, "downloads", 0) or 0)
        likes = int(attr(info, "likes", 0) or 0)
        used_storage = get_used_storage(info)
        params = get_params(info)
        gated = attr(info, "gated", False)
        library_name = str(attr(info, "library_name", "") or "")
        quant = precision_from_safetensors(info) or precision_from_tags(tags)
        size_gb = (used_storage / (1024 ** 3) if used_storage else None)
        params_b = (params / 1e9 if params else None)

        # If Hub metadata does not include a parameter count (very common for
        # Diffusers/video repos with weights split across subdirectories), fall
        # back first to repo-size math and then to model-name/family heuristics.
        # Any fallback is marked with '~' in PARAMS so exact and estimated
        # values are never visually confused.
        estimated_params = False
        params_source = "hub" if params_b is not None else ""
        if params_b is None and size_gb:
            bits = quant_bits(quant)
            if bits > 0:
                params_b = max(0.05, (float(size_gb) * 0.72) / (bits / 8.0))
                estimated_params = True
                params_source = "repo-size"
        if params_b is None:
            params_b, params_source = estimate_params_from_identity(
                repo, pipeline, tags, library_name, model_kind
            )
            estimated_params = True

        # FORMAT should remain useful even when no dtype tag is published.
        if not quant or quant == "-":
            joined = " ".join([repo, library_name, *[str(t) for t in tags]]).lower()
            if "gguf" in joined:
                quant = "GGUF"
            elif "diffusers" in joined or library_name.lower() == "diffusers":
                quant = "DIFFUSERS"
            elif getattr(info, "safetensors", None) is not None:
                quant = "SAFETENSOR"
            elif library_name:
                quant = library_name.upper()[:10]
            else:
                quant = "MODEL"

        required_gb = estimate_required_gb(repo, pipeline, params_b, size_gb, quant, tags, library_name)
        fit_level = derive_fit(required_gb)
        score = derive_score(required_gb, fit_level, downloads, likes)
        row = {
            "name": repo,
            "repo": repo,
            "model_type": model_kind,
            "pipeline_tag": pipeline,
            "parameter_count": (("~" if estimated_params else "") + f"{params_b:.2f}B" if params_b is not None and params_b < 1 else ("~" if estimated_params else "") + f"{params_b:.1f}B" if params_b is not None else "?"),
            "params_b": params_b,
            "params_source": params_source,
            "size_gb": size_gb,
            "estimated_size_gb": ((params_b * quant_bits(quant) / 8.0 * 1.08) if (not size_gb and params_b) else None),
            "quant": quant,
            "required_gb": required_gb,
            "speed_tps": "?",
            "fit_level": fit_level,
            "score": score,
            "downloads": downloads,
            "likes": likes,
            "gated": gated,
            "library_name": str(attr(info, "library_name", "") or ""),
            "tags": tags,
        }
        old = models.get(repo)
        if old is None or score > float(old.get("score") or 0):
            models[repo] = row

rows = sorted(
    models.values(),
    key=lambda r: (float(r.get("score") or 0), int(r.get("downloads") or 0), int(r.get("likes") or 0)),
    reverse=True,
)[:limit]

print(json.dumps({"hardware": system, "models": rows}, ensure_ascii=False))
PY_IMAGE_MODEL_JSON
}

model_manager_pick_and_prepare() {

    local use_case="${1:-$MODEL_MANAGER_USE_CASE}"
    local limit="${2:-15}"
    local search="${3:-}"
    local tmp_json choice idx selected_json repo

    tmp_json="$(mktemp)"
    trap 'rm -f "$tmp_json"' RETURN

    model_manager_rank_json "$use_case" "$limit" "$search" score 1 > "$tmp_json"

    # IMPORTANT: model_manager_pick() invokes this function through command
    # substitution. Do not read menu input from the function's stdin because
    # that stream can be redirected by the caller. Always use the real TTY.
    # The previous implementation delegated both menu rendering and input to
    # Python. On some terminals that could consume an unexpected line and make
    # a perfectly valid number appear as "Invalid choice". Keep all interactive
    # input in bash, directly from /dev/tty, and use Python only for JSON data.
    if ! skills_have_controlling_tty; then
        echo "ERROR: Interactive model picker requires a writable terminal (/dev/tty)." >&2
        return 1
    fi

    "$VENV_DIR/bin/python" - "$tmp_json" <<'PY_PICK_MENU' > /dev/tty
import json
import sys
from pathlib import Path

p = Path(sys.argv[1])
rows = json.loads(p.read_text()).get("models", [])
if not rows:
    raise SystemExit("No fitting models found for this hardware/use-case.")

def derive_repo(r):
    for src in (r.get("gguf_sources") or []):
        if isinstance(src, str) and "/" in src:
            return src
        if isinstance(src, dict):
            repo = src.get("repo_id") or src.get("repo") or src.get("id") or ""
            if repo:
                return repo
    name = r.get("name") or ""
    return name if isinstance(name, str) and name.count("/") == 1 else ""

print()
print("Zarzysseus model picker")
print("Select a model that fits the detected hardware:")
print()
for i, r in enumerate(rows, 1):
    name = r.get("name") or "?"
    repo = derive_repo(r)
    params = r.get("parameter_count") or r.get("params_b")
    quant = r.get("quant") or "?"
    need = r.get("required_gb")
    speed = r.get("speed_tps")
    score = r.get("score")
    fit = r.get("fit_level") or "?"
    print(
        f"{i:>2}: {name} | repo={repo or '?'} | params={params} | "
        f"quant={quant} | VRAM={need}GB | est={speed} tok/s | fit={fit} | score={score}"
    )
print()
PY_PICK_MENU

    # Keep prompting until the user enters an actual number in range. Invalid
    # input is rejected without terminating the picker or being fed into the
    # next shell command.
    while true; do
        printf 'Enter a model number (q to cancel): ' > /dev/tty
        IFS= read -r choice < /dev/tty || {
            echo >&2
            echo "ERROR: Could not read model selection from /dev/tty." >&2
            return 1
        }

        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            echo "Model selection cancelled." > /dev/tty
            return 2
        fi

        if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
            echo "Invalid choice: enter a number from 1 to $limit, or q to cancel." > /dev/tty
            continue
        fi

        idx=$((10#$choice - 1))

        if ! selected_json="$($VENV_DIR/bin/python - "$tmp_json" "$idx" <<'PY_PICK_SELECT'
import json
import sys
from pathlib import Path

rows = json.loads(Path(sys.argv[1]).read_text()).get("models", [])
try:
    idx = int(sys.argv[2])
except Exception:
    raise SystemExit(2)
if idx < 0 or idx >= len(rows):
    raise SystemExit(3)

r = rows[idx]

def derive_repo(r):
    for src in (r.get("gguf_sources") or []):
        if isinstance(src, str) and "/" in src:
            return src
        if isinstance(src, dict):
            repo = src.get("repo_id") or src.get("repo") or src.get("id") or ""
            if repo:
                return repo
    name = r.get("name") or ""
    return name if isinstance(name, str) and name.count("/") == 1 else ""

repo = derive_repo(r)
q = str(r.get("quant") or "")
print(json.dumps({
    "name": r.get("name") or "",
    "repo": repo,
    "quant": q,
    "include": f"*{q}*" if (q.startswith("Q") or q.startswith("IQ")) else "",
    "score": r.get("score"),
    "params_b": r.get("params_b"),
    "speed_tps": r.get("speed_tps"),
    "required_gb": r.get("required_gb"),
    "fit_level": r.get("fit_level"),
}))
PY_PICK_SELECT
)"; then
            echo "Invalid choice: enter a number from 1 to $limit, or q to cancel." > /dev/tty
            continue
        fi
        break
    done

    repo="$(printf '%s' "$selected_json" | "$VENV_DIR/bin/python" -c 'import json,sys; print(json.load(sys.stdin).get("repo", ""))')"
    if [[ -z "$repo" ]]; then
        while true; do
            printf 'No Hugging Face repository was inferred. Enter org/model (q to cancel): ' > /dev/tty
            IFS= read -r repo < /dev/tty || return 1
            if [[ "$repo" == "q" || "$repo" == "Q" ]]; then
                echo "Model selection cancelled." > /dev/tty
                return 2
            fi
            if [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]+/[A-Za-z0-9][A-Za-z0-9._-]+$ ]]; then
                break
            fi
            echo "Invalid repository. Expected org/model." > /dev/tty
        done
        selected_json="$("$VENV_DIR/bin/python" - "$selected_json" "$repo" <<'PY_PICK_REPO'
import json
import sys
payload = json.loads(sys.argv[1])
payload["repo"] = sys.argv[2]
print(json.dumps(payload))
PY_PICK_REPO
)"
    fi

    # stdout remains exactly one JSON object so the caller can safely consume
    # the selection with tail -n1.
    printf '%s\n' "$selected_json"
}

model_manager_pick() {
    local selected
    selected="$(model_manager_pick_and_prepare "$@" | tail -n1)"
    [[ "$selected" == \{*\} ]] || { echo "ERROR: Model selection did not return a valid selection."; return 1; }
    local repo include
    repo="$(printf '%s' "$selected" | "$VENV_DIR/bin/python" -c 'import json,sys; print(json.load(sys.stdin)["repo"])')"
    include="$(printf '%s' "$selected" | "$VENV_DIR/bin/python" -c 'import json,sys; print(json.load(sys.stdin).get("include", ""))')"
    echo "$selected" > "$MODEL_MANAGER_STATE_FILE"
    echo "==> Selected local model: $repo"
    printf '%s' "$selected" | "$VENV_DIR/bin/python" -c 'import json,sys; x=json.load(sys.stdin); print("    params={}B quant={} need={}GB est={} tok/s score={}".format(x.get("params_b"), x.get("quant"), x.get("required_gb"), x.get("speed_tps"), x.get("score")))'
    hf_pull_model "$repo" "$include"
    echo "Selection saved to $MODEL_MANAGER_STATE_FILE"
}

model_manager_auto_pick() {
    local use_case="${1:-$MODEL_MANAGER_USE_CASE}"
    local limit="${2:-$MODEL_MANAGER_DEFAULT_LIMIT}"
    local search="${3:-}"
    local tmp_json="" selected_json="" repo="" include=""

    model_manager_ensure || return 1
    tmp_json="$(mktemp)"
    trap 'rm -f "$tmp_json"' RETURN

    info "Automatically selecting the highest-ranked PERFECT-fit model for this hardware..."
    model_manager_rank_json "$use_case" "200" "$search" score 1 > "$tmp_json"

    selected_json="$($VENV_DIR/bin/python - "$tmp_json" <<'PY_AUTO_PICK'
import json
import sys
from pathlib import Path

p=Path(sys.argv[1])
data=json.loads(p.read_text())
rows=data.get("models") or []
if not rows:
    raise SystemExit("No fitting models found for this hardware/use-case.")

def derive_repo(r):
    for src in (r.get("gguf_sources") or []):
        if isinstance(src, str) and "/" in src:
            return src
        if isinstance(src, dict):
            repo=src.get("repo_id") or src.get("repo") or src.get("id") or ""
            if repo:
                return repo
    name=r.get("name") or ""
    return name if isinstance(name, str) and name.count("/")==1 else ""

perfect = [r for r in rows if str(r.get("fit_level") or "").strip().lower() == "perfect"]
if not perfect:
    raise SystemExit("No model with fit=perfect was found for this hardware/use-case.")

# rank_models already returns rows in the requested sort order, so choose the
# highest-ranked model among the models explicitly marked perfect.
r=perfect[0]
repo=derive_repo(r)
q=str(r.get("quant") or "")
print(json.dumps({
    "name": r.get("name") or "",
    "repo": repo,
    "quant": q,
    "include": f"*{q}*" if (q.startswith("Q") or q.startswith("IQ")) else "",
    "score": r.get("score"),
    "params_b": r.get("params_b"),
    "speed_tps": r.get("speed_tps"),
    "required_gb": r.get("required_gb"),
    "fit_level": r.get("fit_level"),
}))
PY_AUTO_PICK
)"

    [[ -n "$selected_json" ]] || { echo "ERROR: Automatic model selection returned no model."; return 1; }
    repo="$(printf '%s' "$selected_json" | "$VENV_DIR/bin/python" -c 'import json,sys; print(json.load(sys.stdin).get("repo", ""))')"
    include="$(printf '%s' "$selected_json" | "$VENV_DIR/bin/python" -c 'import json,sys; print(json.load(sys.stdin).get("include", ""))')"

    [[ -n "$repo" ]] || {
        echo "ERROR: The top fitting model has no downloadable Hugging Face repository."
        return 1
    }

    echo "$selected_json" > "$MODEL_MANAGER_STATE_FILE"
    echo "==> Auto-selected PERFECT-fit model: $repo"
    printf '%s' "$selected_json" | "$VENV_DIR/bin/python" -c 'import json,sys; x=json.load(sys.stdin); print("    params={}B quant={} need={}GB est={} tok/s fit={} score={}".format(x.get("params_b"), x.get("quant"), x.get("required_gb"), x.get("speed_tps"), x.get("fit_level"), x.get("score")))'

    hf_pull_model "$repo" "$include" || return 1

    case "$ACCELERATOR_BACKEND" in
        amd_rocm|nvidia_cuda)
            if [[ "$INSTALL_VLLM" == "1" ]]; then
                configure_engine_default_model vllm "$repo" || true
            elif [[ "$INSTALL_SGLANG" == "1" ]]; then
                configure_engine_default_model sglang "$repo" || true
            fi
            ;;
        *)
            ;;
    esac

    echo "Automatic selection saved to $MODEL_MANAGER_STATE_FILE"
}

# Installed auto-fit skills are generated locally for the actual selected
# repositories, not guessed by matching untrusted skills.sh search results.
# They are model-specific, avoid executing arbitrary model-card shell snippets,
# and are imported into Zarzysseus using the existing SkillsManager validation.
AUTO_FIT_SKILL_DIR="${AUTO_FIT_SKILL_DIR:-$PROJECT_DIR/data/local/auto-fit-skills}"
AUTO_FIT_SKILL_STATE_DIR="${AUTO_FIT_SKILL_STATE_DIR:-$PROJECT_DIR/data/local/auto-fit}"
AUTO_FIT_SKILLS_SYNCED=0

# Repair known missing prerequisites, then RETRY the command that failed.
# Never execute package names or shell snippets extracted from model cards.
# All pip installs stay in the project's Python environment; do not alter torch.
DEPENDENCY_REPAIR_ATTEMPTS="${DEPENDENCY_REPAIR_ATTEMPTS:-3}"
[[ "$DEPENDENCY_REPAIR_ATTEMPTS" =~ ^[1-5]$ ]] || DEPENDENCY_REPAIR_ATTEMPTS=3

dependency_repair_from_error() {
    local log="$1" py="$2" missing module pkg lib translated
    missing="$(python3 - "$log" <<'PY_DEP_FAILURE'
import pathlib, re, sys
s=pathlib.Path(sys.argv[1]).read_text(errors='replace')
# Inspect the LAST error, not an example earlier in a long log.
modules=re.findall(r"(?:ModuleNotFoundError|ImportError): No module named ['\"]([^'\"]+)['\"]",s)
libs=re.findall(r'(lib[A-Za-z0-9_+.-]+\.so(?:\.[0-9]+)*): cannot open shared object file',s)
if modules: print('module:'+modules[-1].split('.')[0])
elif libs: print('library:'+libs[-1])
PY_DEP_FAILURE
)" || return 1
    case "$missing" in
        module:*)
            module="${missing#module:}"
            # Explicit mapping prevents typos or untrusted text from becoming
            # arbitrary pip package installs. Torch/GPU wheels are never replaced.
            case "$module" in
                diffusers|transformers|accelerate|safetensors|sentencepiece|ftfy|einops|peft|av|imageio|protobuf|numpy|scipy|cv2|PIL|huggingface_hub|imageio_ffmpeg|google|skimage|timm|omegaconf|compel|decord|bitsandbytes|tokenizers)
                    case "$module" in
                        PIL) pkg=pillow ;; cv2) pkg=opencv-python-headless ;;
                        google|protobuf) pkg=protobuf ;; huggingface_hub) pkg=huggingface_hub ;;
                        imageio_ffmpeg) pkg=imageio-ffmpeg ;; skimage) pkg=scikit-image ;;
                        *) pkg="$module" ;;
                    esac
                    echo "    [repair] Missing Python module '$module'; installing $pkg in the Zarzysseus environment."
                    "$py" -m pip install --upgrade-strategy only-if-needed "$pkg"
                    ;;
                *) echo "ERROR: Missing unrecognized Python module '$module'; will not guess a package to install."; return 1 ;;
            esac
            ;;
        library:*)
            lib="${missing#library:}"
            # Reuse existing ROCm repair (including a damaged installed package)
            # rather than installing the wrong GPU backend or a dummy .so.
            if [[ "$lib" == libMIOpen.so.1 && "${ACCELERATOR_BACKEND:-}" == amd_rocm ]]; then
                echo '    [repair] Restoring ROCm MIOpen runtime.'
                ensure_miopen_runtime
                return $?
            fi
            if [[ "$lib" == libroctx64.so.4 && "${ACCELERATOR_BACKEND:-}" == amd_rocm ]]; then
                echo '    [repair] Restoring ROCm tracing runtime.'
                ensure_roctx_runtime
                return $?
            fi
            case "$PKG:$lib" in
                pacman:libGL.so.1) pkg=libglvnd ;;
                apt:libGL.so.1) pkg=libgl1 ;;
                pacman:libgomp.so.1) pkg=gcc-libs ;;
                apt:libgomp.so.1) pkg=libgomp1 ;;
                pacman:libstdc++.so.6) pkg=gcc-libs ;;
                apt:libstdc++.so.6) pkg=libstdc++6 ;;
                *) echo "ERROR: Missing native library '$lib'; no safe distro-specific repair mapping. Check your driver/runtime."; return 1 ;;
            esac
            echo "    [repair] Missing library '$lib'; installing OS package $pkg (no full system upgrade)."
            install_missing_packages "$pkg"
            ;;
        *) return 1 ;;
    esac
}

dependency_repair_python_command() {
    # Usage: dependency_repair_python_command <python> <script.py> [args...]
    # stdin is NOT used, so verification can be retried without losing a heredoc.
    local py="$1" log attempt rc=0; shift
    log="$(mktemp)" || return 1
    for ((attempt=1; attempt<=DEPENDENCY_REPAIR_ATTEMPTS; attempt++)); do
        if "$py" "$@" >"$log" 2>&1; then
            cat "$log"
            rm -f "$log"
            return 0
        else
            rc=$?
        fi
        cat "$log" >&2
        if (( attempt >= DEPENDENCY_REPAIR_ATTEMPTS )) || ! dependency_repair_from_error "$log" "$py"; then
            echo "ERROR: Dependency check failed after $attempt attempt(s); see error above." >&2
            rm -f "$log"
            return "$rc"
        fi
        echo "    [retry] Rechecking dependencies ($((attempt+1))/$DEPENDENCY_REPAIR_ATTEMPTS)..."
    done
    rm -f "$log"
    return 1
}

dependency_repair_build_tools() {
    # Build tool installation is conditional on real compiler/header errors.
    local log="$1" mapped="" pkg
    if grep -Eiq '(gcc: command not found|g\+\+: command not found|unable to execute .*(gcc|g\+\+)|Python\.h: No such file|error: command .gcc.|Microsoft Visual C\+\+)' "$log"; then
        case "$PKG" in
            pacman) mapped='base-devel python' ;; apt) mapped='build-essential python3-dev' ;;
            dnf|dnf5|microdnf|yum|tdnf) mapped='gcc gcc-c++ make python3-devel' ;;
            zypper) mapped='gcc gcc-c++ make python3-devel' ;; apk) mapped='build-base python3-dev' ;;
            *) echo 'ERROR: Missing compiler/header prerequisites; package mapping unavailable.'; return 1 ;;
        esac
    elif grep -Eiq '(cmake: (command not found|not found)|Could not find CMAKE|CMake must be installed)' "$log"; then
        mapped='cmake'
    elif grep -Eiq '(cargo: command not found|Rust compiler.*not found)' "$log"; then
        case "$PKG" in
            pacman) mapped='rust' ;;
            apt|dnf|dnf5|microdnf|yum|tdnf|zypper|apk) mapped='rustc cargo' ;;
            *) echo 'ERROR: Rust toolchain package mapping unavailable.'; return 1 ;;
        esac
    elif grep -Eiq '(pkg-config: (command not found|not found))' "$log"; then
        case "$PKG" in pacman) mapped='pkgconf' ;; *) mapped='pkg-config' ;; esac
    fi
    [[ -n "$mapped" ]] || return 1
    local -a packages=()
    read -r -a packages <<< "$mapped"
    echo "    [repair] Installing missing build prerequisites: ${packages[*]} (no full system upgrade)."
    install_missing_packages "${packages[@]}"
}

dependency_repair_pip() {
    local py="$1" log rc=0; shift
    log="$(mktemp)" || return 1
    if "$py" -m pip install --upgrade-strategy only-if-needed "$@" >"$log" 2>&1; then
        cat "$log"; rm -f "$log"; return 0
    else
        rc=$?
    fi
    cat "$log" >&2
    if dependency_repair_build_tools "$log"; then
        echo '    [retry] Retrying pip installation after prerequisite repair.'
        if "$py" -m pip install --upgrade-strategy only-if-needed "$@"; then
            rm -f "$log"; return 0
        else rc=$?; fi
    fi
    rm -f "$log"
    return "$rc"
}

dependency_repair_npm() {
    local skill_root="$1" mode="$2" log rc=0; shift 2
    log="$(mktemp)" || return 1
    if (cd "$skill_root" && npm "$mode" --no-audit --no-fund "$@") >"$log" 2>&1; then
        cat "$log"; rm -f "$log"; return 0
    else
        rc=$?
    fi
    cat "$log" >&2
    # Don't guess at dependency versions or use npm audit fix --force.
    # A retry is worthwhile only when a known toolchain prerequisite is missing.
    if dependency_repair_build_tools "$log"; then
        echo '    [retry] Retrying npm dependency installation after prerequisite repair.'
        if (cd "$skill_root" && npm "$mode" --no-audit --no-fund "$@"); then
            rm -f "$log"; return 0
        else rc=$?; fi
    fi
    rm -f "$log"
    return "$rc"
}

# Install only dependencies declared by the selected mode; do not change OS-update scheduling.
auto_fit_prepare_dependencies() {
    local kind="${1:-}" packages missing
    case "$kind" in
        text)
            # Text skill uses the OpenAI-compatible service via stdlib urllib;
            # the stack installer has already installed the local LLM runtimes.
            [[ -x "$VENV_PY" ]] || { echo 'ERROR: Missing Zarzysseus Python.'; return 1; }
            return 0
            ;;
        image|video) ;;
        *) echo "ERROR: unknown auto-fit skill type: $kind"; return 2 ;;
    esac
    if [[ "$kind" == video ]] && ! command -v ffmpeg >/dev/null 2>&1; then
        echo '==> Video generation requires FFmpeg; installing it for this profile.'
        install_missing_packages ffmpeg || return 1
    fi
    # Do not reinstall or replace the ROCm/CUDA torch wheel installed by the
    # base stack; only install missing media libraries in that same environment.
    [[ -x "$VENV_PY" ]] || return 1
    missing="$("$VENV_PY" - "$kind" <<'PY_AUTO_SKILL_DEPS'
import importlib.util, sys
kind=sys.argv[1]
requirements={
    'diffusers':'diffusers', 'transformers':'transformers',
    'accelerate':'accelerate', 'safetensors':'safetensors',
    'PIL':'pillow', 'huggingface_hub':'huggingface_hub',
    'sentencepiece':'sentencepiece', 'google.protobuf':'protobuf',
    'ftfy':'ftfy', 'einops':'einops',
}
if kind == 'video':
    requirements.update({'imageio':'imageio', 'imageio_ffmpeg':'imageio-ffmpeg'})
for module, package in requirements.items():
    try: present=importlib.util.find_spec(module) is not None
    except (ImportError, ModuleNotFoundError, ValueError): present=False
    if not present: print(package)
PY_AUTO_SKILL_DEPS
)" || return 1
    if [[ -n "$missing" ]]; then
        local -a deps=()
        mapfile -t deps <<< "$missing"
        echo "==> Installing missing $kind skill dependencies: ${deps[*]}"
        dependency_repair_pip "$VENV_PY" "${deps[@]}" || return 1
    fi
    local verify_script verify_rc=0
    verify_script="$(mktemp --suffix=.py)" || return 1
    cat >"$verify_script" <<'PY_AUTO_SKILL_VERIFY_DEPS'
import importlib, sys
kind=sys.argv[1]
modules=['torch','diffusers','transformers','accelerate','safetensors','PIL','huggingface_hub']
if kind=='video': modules.extend(['imageio','imageio_ffmpeg'])
for module in modules:
    importlib.import_module(module)
print(f'    [ready] {kind} runtime dependencies import successfully')
PY_AUTO_SKILL_VERIFY_DEPS
    dependency_repair_python_command "$VENV_PY" "$verify_script" "$kind" || verify_rc=$?
    rm -f "$verify_script"
    (( verify_rc == 0 )) || return "$verify_rc"
}

# Inspect the actual downloaded Diffusers model_index.json and install vetted
# pipeline-specific extras. Never execute README/model-card install commands.
# The base runtime is installed above; these are supplemental dependencies only.
auto_fit_prepare_model_dependencies() {
    local kind="${1:-}" repo="${2:-}" missing pipeline snapshot
    case "$kind" in image|video) ;; *) return 0 ;; esac
    [[ -x "$VENV_PY" ]] || { echo 'ERROR: Python environment is not ready.'; return 1; }
    if [[ "$kind" == video ]] && ! command -v ffmpeg >/dev/null 2>&1; then
        install_missing_packages ffmpeg || return 1
    fi
    missing="$("$VENV_PY" - "$kind" "$repo" "$HF_HUB_CACHE" <<'PY_MODEL_EXTRA_DEPS'
import importlib.util, json, pathlib, re, sys
kind,repo,hub=sys.argv[1:]
if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*',repo):
    raise SystemExit('ERROR: invalid model repository')
snapshots=pathlib.Path(hub,'models--'+repo.replace('/','--'),'snapshots')
choices=sorted((p for p in snapshots.glob('*/model_index.json') if p.is_file()),key=lambda p:p.stat().st_mtime,reverse=True)
if not choices: raise SystemExit(f'ERROR: missing Diffusers model_index.json for {repo}')
config=json.loads(choices[0].read_text())
pipeline=str(config.get('_class_name') or '')
if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*Pipeline',pipeline):
    raise SystemExit(f'ERROR: unsupported pipeline class {pipeline!r}')
if config.get('custom_pipeline') or config.get('_custom_pipeline'):
    raise SystemExit('ERROR: custom model code requires explicit review; not executed automatically')
# No arbitrary package names from untrusted model files are sent to pip.
modules={
 'diffusers':'diffusers','transformers':'transformers','accelerate':'accelerate',
 'safetensors':'safetensors','PIL':'pillow','huggingface_hub':'huggingface_hub',
}
if kind=='video':
    modules.update({'imageio':'imageio','imageio_ffmpeg':'imageio-ffmpeg','av':'av'})
# Common pipeline families sometimes reference additional helpers.
components={v[0] for v in config.values() if isinstance(v,list) and len(v)==2 and isinstance(v[0],str)}
if any(part in pipeline for part in ('CogVideoX','HunyuanVideo','Wan','Flux')) or 'T5EncoderModel' in str(config):
    modules.update({'sentencepiece':'sentencepiece','google.protobuf':'protobuf'})
if 'StableDiffusion' in pipeline: modules['ftfy']='ftfy'
if 'ControlNet' in pipeline: modules['cv2']='opencv-python-headless'
if 'peft' in components: modules['peft']='peft'
if 'transformers' in components: modules['transformers']='transformers'
for module,spec in modules.items():
    try: present=importlib.util.find_spec(module) is not None
    except (ImportError,ModuleNotFoundError,ValueError): present=False
    if not present: print(spec)
PY_MODEL_EXTRA_DEPS
)" || return 1
    if [[ -n "$missing" ]]; then
        local -a packages=()
        mapfile -t packages <<< "$missing"
        echo "==> Installing model-specific $kind skill dependencies: ${packages[*]}"
        dependency_repair_pip "$VENV_PY" "${packages[@]}" || return 1
    fi
    # A successfully imported Diffusers package may still be too old for the
    # selected class. Upgrade Diffusers only, without replacing GPU torch.
    if ! "$VENV_PY" - "$repo" "$HF_HUB_CACHE" <<'PY_CLASS_PROBE'
import json, pathlib, sys, diffusers
repo,hub=sys.argv[1:]
root=pathlib.Path(hub,'models--'+repo.replace('/','--'),'snapshots')
configs=sorted(root.glob('*/model_index.json'),key=lambda p:p.stat().st_mtime,reverse=True)
name=json.loads(configs[0].read_text())['_class_name']
if getattr(diffusers,name,None) is None: raise SystemExit(f'Pipeline {name} unavailable in current Diffusers')
PY_CLASS_PROBE
    then
        echo '==> Installing newer Diffusers pipeline support without changing the GPU torch build.'
        "$VENV_PY" -m pip install --upgrade --no-deps diffusers || return 1
    fi
    local verify_script verify_rc=0
    verify_script="$(mktemp --suffix=.py)" || return 1
    cat >"$verify_script" <<'PY_VERIFY_MODEL_DEPS'
import importlib,json,pathlib,sys
import diffusers, torch
repo,hub,kind=sys.argv[1:]
root=pathlib.Path(hub,'models--'+repo.replace('/','--'),'snapshots')
configs=sorted(root.glob('*/model_index.json'),key=lambda p:p.stat().st_mtime,reverse=True)
name=json.loads(configs[0].read_text())['_class_name']
if getattr(diffusers,name,None) is None: raise SystemExit(f'ERROR: {name} still unavailable; selected model cannot be marked ready')
config=json.loads(configs[0].read_text())
for mod in ('transformers','accelerate','safetensors','PIL','huggingface_hub'):
    importlib.import_module(mod)
if kind=='video':
    for mod in ('imageio','imageio_ffmpeg','av'): importlib.import_module(mod)
if any(part in name for part in ('CogVideoX','HunyuanVideo','Wan','Flux')) or 'T5EncoderModel' in str(config):
    importlib.import_module('sentencepiece')
    importlib.import_module('google.protobuf')
if 'ControlNet' in name: importlib.import_module('cv2')
if 'peft' in {v[0] for v in config.values() if isinstance(v,list) and len(v)==2 and isinstance(v[0],str)}:
    importlib.import_module('peft')
print(f'    [ready] Model-specific {kind} dependencies and {name} are importable (inference not tested).')
PY_VERIFY_MODEL_DEPS
    dependency_repair_python_command "$VENV_PY" "$verify_script" "$repo" "$HF_HUB_CACHE" "$kind" || verify_rc=$?
    rm -f "$verify_script"
    (( verify_rc == 0 )) || return "$verify_rc"
}

auto_fit_install_selected_skill() {
    local kind="$1" selection="$2" skill_root name
    [[ -x "$VENV_PY" && -n "$selection" ]] || return 1
    mkdir -p "$AUTO_FIT_SKILL_DIR" "$AUTO_FIT_SKILL_STATE_DIR"
    # The helper prints only the generated skill path to stdout; its input is
    # persisted as a JSON file, never as executable shell interpolation.
    skill_root="$("$VENV_PY" - "$kind" "$selection" "$AUTO_FIT_SKILL_DIR" "$AUTO_FIT_SKILL_STATE_DIR" \
        "$HF_HUB_CACHE" "$VLLM_ENDPOINT" "$SGLANG_ENDPOINT" "$OLLAMA_OPENAI_ENDPOINT" \
        "$PROJECT_DIR" <<'PY_AUTO_SKILL_CREATE'
import json, re, sys
from pathlib import Path
(kind, raw, src_root, state_root, hub, vllm, sglang, ollama, project)=sys.argv[1:]
info=json.loads(raw)
repo=info.get('repo','')
if kind not in ('text','image','video') or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*',repo):
    raise SystemExit('ERROR: Invalid selected model metadata')
tag=(info.get('pipeline_tag') or '').lower()
if kind=='image' and tag!='text-to-image': raise SystemExit('ERROR: This image model does not take a text prompt')
if kind=='video' and tag!='text-to-video': raise SystemExit('ERROR: This video model does not take a text prompt')
slug=re.sub('[^a-z0-9-]+','-',repo.lower().replace('/','-')).strip('-')
name=f'zarzysseus-auto-{kind}-{slug}'
root=Path(src_root)/name
root.mkdir(parents=True,exist_ok=True)
state=Path(state_root)/f'{kind}.json'
state.parent.mkdir(parents=True,exist_ok=True)
state.write_text(json.dumps(info,indent=2)+'\n',encoding='utf-8')

snap=Path(hub)/('models--'+repo.replace('/','--'))/'snapshots'
if not snap.is_dir(): raise SystemExit(f'ERROR: No downloaded snapshot for {repo}')
choices=sorted((p for p in snap.iterdir() if p.is_dir()),key=lambda p:p.stat().st_mtime,reverse=True)
if not choices: raise SystemExit(f'ERROR: No downloaded snapshot for {repo}')
chosen=next((p for p in choices if (p/'model_index.json').is_file()),choices[0])
if kind!='text':
    config=chosen/'model_index.json'
    if not config.is_file():
        raise SystemExit(f'ERROR: {repo} is not a complete Diffusers pipeline (model_index.json missing); cannot make a runnable {kind} skill')
    try: pipeline=json.loads(config.read_text()).get('_class_name','')
    except (ValueError,OSError) as exc: raise SystemExit(f'ERROR: Invalid pipeline config for {repo}: {exc}')
    if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*Pipeline',pipeline):
        raise SystemExit(f'ERROR: Unsupported pipeline class for {repo}: {pipeline!r}')
    # Validate that the installed Diffusers actually exports the selected class.
    import diffusers
    if getattr(diffusers,pipeline,None) is None:
        raise SystemExit(f'ERROR: This Diffusers installation does not provide {pipeline}. Upgrade/install its model-specific runtime before use.')

metadata={**info,'kind':kind,'repo':repo,'snapshot':str(chosen),
          'vllm_endpoint':vllm,'sglang_endpoint':sglang,'ollama_endpoint':ollama}
(root/'model.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8')
runner=r"""#!/usr/bin/env python3
'Zarzysseus auto-fit local model skill. Generated for exactly one downloaded repo.'
import argparse, json, os, sys, urllib.request
from pathlib import Path
metadata=json.loads((Path(__file__).parent/'model.json').read_text())
repo=metadata['repo']; kind=metadata['kind']
p=argparse.ArgumentParser(description='Run the selected Zarzysseus auto-fit model')
p.add_argument('--check',action='store_true',help='Verify runtime, model cache and configured endpoint (no inference)')
p.add_argument('--prompt',help='Text prompt for generation')
p.add_argument('--output',help='Output image/video file')
p.add_argument('--steps',type=int,default=25)
p.add_argument('--endpoint',help='Override OpenAI-compatible text endpoint URL')
a=p.parse_args()
if kind=='text':
    endpoints=[a.endpoint, os.getenv('ZARZYSSEUS_TEXT_ENDPOINT'), metadata['vllm_endpoint'],
               metadata['sglang_endpoint'], metadata['ollama_endpoint']]
    endpoints=[u.rstrip('/') for u in endpoints if u]
    base=None
    for url in endpoints:
        try:
            with urllib.request.urlopen(url+'/models',timeout=3) as response:
                models=json.load(response).get('data',[])
            if any(m.get('id')==repo for m in models): base=url; break
        except (OSError,ValueError,KeyError): pass
    if base is None:
        raise SystemExit('Text model is downloaded, but no running OpenAI-compatible endpoint advertises '+repo+'. Start vLLM/SGLang for this model or supply --endpoint.')
    if a.check: print('READY: '+repo+' @ '+base); sys.exit(0)
    if not a.prompt: p.error('--prompt is required')
    data=json.dumps({'model':repo,'messages':[{'role':'user','content':a.prompt}]}).encode()
    request=urllib.request.Request(base+'/chat/completions',data=data,headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(request,timeout=600) as response: result=json.load(response)
    print(result['choices'][0]['message']['content'])
else:
    import torch
    from diffusers import DiffusionPipeline
    snapshot=Path(metadata['snapshot'])
    if not (snapshot/'model_index.json').is_file(): raise SystemExit('Model snapshot missing: '+str(snapshot))
    config=json.loads((snapshot/'model_index.json').read_text())
    pipeline_class=config.get('_class_name','')
    import diffusers
    if not getattr(diffusers,pipeline_class,None):
        raise SystemExit('Selected pipeline unavailable: '+str(pipeline_class))
    if kind=='video':
        import imageio, imageio_ffmpeg, av
        from diffusers.utils import export_to_video
    if a.check:
        print('DEPENDENCIES AND PIPELINE READY: '+repo+' ('+str(pipeline_class)+'; no inference performed)')
        sys.exit(0)
    if not a.prompt: p.error('--prompt is required')
    if a.steps < 1 or a.steps > 250: p.error('--steps must be between 1 and 250')
    dest=Path(a.output or ('generated.png' if kind=='image' else 'generated.mp4')).expanduser()
    if not dest.parent.is_dir(): dest.parent.mkdir(parents=True,exist_ok=True)
    dtype=torch.float16 if torch.cuda.is_available() else torch.float32
    pipe=DiffusionPipeline.from_pretrained(str(snapshot),torch_dtype=dtype,local_files_only=True)
    if torch.cuda.is_available(): pipe=pipe.to('cuda')
    # Generic prompt-only Diffusers pipelines; model-specific APIs can still vary.
    result=pipe(prompt=a.prompt,num_inference_steps=a.steps)
    if kind=='image':
        result.images[0].save(dest)
    else:
        from diffusers.utils import export_to_video
        frames=result.frames
        if frames and isinstance(frames[0],(list,tuple)): frames=frames[0]
        export_to_video(frames, str(dest), fps=8)
    print('Generated:',dest)
"""
(root/'run.py').write_text(runner,encoding='utf-8')
label={'text':'Text generation','image':'Photo generation','video':'Video generation'}[kind]
readiness=('Check the model server advertises this exact model before text inference.' if kind=='text'
           else 'The check verifies imports and the downloaded pipeline; it does NOT perform a GPU inference test.')
md=f"""---
name: {name}
description: Run the auto-fitted {label.lower()} model {repo} using local Zarzysseus runtimes.
---

# {label} — {repo}

Selected model: `{repo}`  
Hardware fit: `{info.get('fit_level','unknown')}` (estimate, not a benchmark).  
Pipeline: `{tag or 'chat-completion'}`

Use the exact locally downloaded model and existing Zarzysseus environment. Never claim an output
was generated unless the command succeeds and its file exists. Never swap in a different repo
without an explicit user instruction. The model must be serving for text requests.

## Verification

`{sys.executable} {Path(project)/'data/skills/imported'/name/'run.py'} --check`

{readiness}

## Generate

`{sys.executable} {Path(project)/'data/skills/imported'/name/'run.py'} --prompt "describe the requested result"{(' --output generated.png' if kind=='image' else ' --output generated.mp4' if kind=='video' else '')}`

If the pipeline requires extra inputs or unsupported remote code, report the limitation rather
than silently running an unrelated model. No arbitrary model-card install commands are run.
"""
(root/'SKILL.md').write_text(md,encoding='utf-8')
print(root)
PY_AUTO_SKILL_CREATE
)" || return 1
    [[ -n "$skill_root" && -f "$skill_root/SKILL.md" ]] || return 1
    echo "==> Registering $kind skill for model $("$VENV_PY" -c 'import json,sys; print(json.loads(sys.argv[1])["repo"])' "$selection")"
    # Install dependencies declared by this generated skill as well as the
    # pipeline-specific extras resolved above. Never silently skip failures.
    skills_install_skill_manifests "$skill_root" || return 1
    if ! SKILLS_SYNC_DEFER_RESTART=1 skills_sync_installed_skill_to_odysseus "$skill_root" ''; then
        echo "ERROR: Model skill was staged at $skill_root, but Zarzysseus skill registration failed."
        echo '       Log in once to create an owner, then rerun the chosen auto-fit mode.'
        return 1
    fi
    AUTO_FIT_SKILLS_SYNCED=1
    if [[ "$kind" == text ]]; then
        if dependency_repair_python_command "$VENV_PY" "$skill_root/run.py" --check; then
            echo '    [ready] Text skill registered and its exact model is serving.'
        else
            echo '    [note] Text skill registered; inference needs the selected model running on an OpenAI-compatible endpoint.'
        fi
    else
        dependency_repair_python_command "$VENV_PY" "$skill_root/run.py" --check || return 1
        echo '    [ready] Media skill registered, dependencies import, and model snapshot exists.'
        echo '    [note] Actual generation is not claimed until an inference test succeeds.'
    fi
}

auto_fit_finalize_skills() {
    if (( AUTO_FIT_SKILLS_SYNCED )) && [[ "${SERVICE_MANAGER:-}" == systemd ]] && service_installed; then
        # Do not restart for every separate selected model.
        if service_systemctl is-active --quiet "$service_unit" 2>/dev/null; then
            service_systemctl restart "$service_unit" || {
                echo 'ERROR: Skills were registered but Zarzysseus could not restart.'; return 1;
            }
            echo '    [ready] Zarzysseus restarted once with all selected auto-fit skills.'
        fi
    fi
}

# Select the best model that actually fits the current machine. Unlike the
# legacy PERFECT-only picker, this accepts perfect/good/tight/cpu_offload in
# that order and refuses "poor" models rather than pretending they fit.
model_manager_auto_fit_text() {
    local tmp_json selected_json repo include fit
    model_manager_ensure || return 1
    tmp_json="$(mktemp)"; trap 'rm -f "$tmp_json"' RETURN
    model_manager_rank_json "$MODEL_MANAGER_USE_CASE" 200 "" score 0 > "$tmp_json"

    selected_json="$($VENV_DIR/bin/python - "$tmp_json" <<'PY_AUTO_FIT_TEXT'
import json,sys
rows=(json.load(open(sys.argv[1])).get('models') or [])
order={'perfect':0,'good':1,'tight':2,'cpu_offload':3}

def repo_of(r):
    for src in (r.get('gguf_sources') or []):
        if isinstance(src,str) and '/' in src: return src
        if isinstance(src,dict):
            v=src.get('repo_id') or src.get('repo') or src.get('id') or ''
            if v: return v
    n=str(r.get('name') or '')
    return n if n.count('/')==1 else ''

c=[r for r in rows if str(r.get('fit_level') or '').lower() in order and repo_of(r)]
if not c: raise SystemExit('No text model with an acceptable hardware fit was found.')
c.sort(key=lambda r:(order[str(r.get('fit_level')).lower()], -float(r.get('score') or 0)))
r=c[0]; repo=repo_of(r); q=str(r.get('quant') or '')
print(json.dumps({'repo':repo,'quant':q,'include':f'*{q}*' if q.startswith(('Q','IQ')) else '',
                  'params_b':r.get('params_b'),'required_gb':r.get('required_gb'),
                  'speed_tps':r.get('speed_tps'),'fit_level':r.get('fit_level'),'score':r.get('score')}))
PY_AUTO_FIT_TEXT
)" || return 1
    repo="$(printf '%s' "$selected_json" | "$VENV_DIR/bin/python" -c 'import json,sys;print(json.load(sys.stdin)["repo"])')"
    include="$(printf '%s' "$selected_json" | "$VENV_DIR/bin/python" -c 'import json,sys;print(json.load(sys.stdin).get("include", ""))')"
    fit="$(printf '%s' "$selected_json" | "$VENV_DIR/bin/python" -c 'import json,sys;print(json.load(sys.stdin).get("fit_level", "?"))')"
    echo "==> AUTO FIT text model: $repo ($fit)"
    printf '%s' "$selected_json" | "$VENV_DIR/bin/python" -c 'import json,sys;x=json.load(sys.stdin);print("    params={}B need={}GB est={} tok/s score={}".format(x.get("params_b"),x.get("required_gb"),x.get("speed_tps"),x.get("score")))'
    echo "$selected_json" > "$MODEL_MANAGER_STATE_FILE"
    auto_fit_prepare_dependencies text || return 1
    hf_pull_model "$repo" "$include" || return 1
    case "$ACCELERATOR_BACKEND" in
        amd_rocm|nvidia_cuda)
            if [[ "$INSTALL_VLLM" == "1" ]]; then configure_engine_default_model vllm "$repo" || true
            elif [[ "$INSTALL_SGLANG" == "1" ]]; then configure_engine_default_model sglang "$repo" || true
            fi
            ;;
    esac
    auto_fit_install_selected_skill text "$selected_json" || return 1
}

model_manager_auto_fit_media() {
    local kind="${1:-}" tmp_json selected_json repo fit
    case "$kind" in image|video) ;; *) echo "ERROR: media auto-fit kind must be image or video"; return 2 ;; esac
    model_manager_ensure || return 1
    tmp_json="$(mktemp)"; trap 'rm -f "$tmp_json"' RETURN
    model_manager_image_json 200 "" > "$tmp_json"

    selected_json="$($VENV_DIR/bin/python - "$tmp_json" "$kind" <<'PY_AUTO_FIT_MEDIA'
import json,sys
rows=(json.load(open(sys.argv[1])).get('models') or [])
kind=sys.argv[2]
order={'perfect':0,'good':1,'tight':2,'cpu_offload':3}
rows=[r for r in rows if str(r.get('model_type') or '').lower()==kind and not bool(r.get('gated'))
      and str(r.get('fit_level') or '').lower() in order and str(r.get('repo') or r.get('name') or '').count('/')==1
      and str(r.get('pipeline_tag') or '').lower()==('text-to-image' if kind=='image' else 'text-to-video')
      and str(r.get('library_name') or '').lower() in ('', 'diffusers')]
if not rows: raise SystemExit(f'No ungated, prompt-driven Diffusers {kind} model with an acceptable hardware fit was found.')
pipeline_pref = ({'text-to-image':0,'image-to-image':1,'unconditional-image-generation':2}
                 if kind=='image' else {'text-to-video':0,'image-to-video':1,'video-to-video':2})
rows.sort(key=lambda r:(order[str(r.get('fit_level')).lower()],
                        pipeline_pref.get(str(r.get('pipeline_tag') or '').lower(), 9),
                        -float(r.get('score') or 0), -int(r.get('downloads') or 0)))
r=rows[0]
print(json.dumps({'repo':r.get('repo') or r.get('name'),'pipeline_tag':r.get('pipeline_tag'),
                  'parameter_count':r.get('parameter_count'),'required_gb':r.get('required_gb'),
                  'quant':r.get('quant'),'fit_level':r.get('fit_level'),'score':r.get('score'),
                  'downloads':r.get('downloads')}))
PY_AUTO_FIT_MEDIA
)" || return 1
    repo="$(printf '%s' "$selected_json" | "$VENV_DIR/bin/python" -c 'import json,sys;print(json.load(sys.stdin)["repo"])')"
    fit="$(printf '%s' "$selected_json" | "$VENV_DIR/bin/python" -c 'import json,sys;print(json.load(sys.stdin).get("fit_level", "?"))')"
    echo "==> AUTO FIT ${kind} generation model: $repo ($fit)"
    printf '%s' "$selected_json" | "$VENV_DIR/bin/python" -c 'import json,sys;x=json.load(sys.stdin);print("    params={} precision={} need={}GB pipeline={} score={}".format(x.get("parameter_count"),x.get("quant"),x.get("required_gb"),x.get("pipeline_tag"),x.get("score")))'
    # Media models are complete Diffusers/HF repositories. Do not route them to
    # vLLM/SGLang or replace the default chat model.
    auto_fit_prepare_dependencies "$kind" || return 1
    hf_pull_model "$repo" || return 1
    auto_fit_prepare_model_dependencies "$kind" "$repo" || return 1
    auto_fit_install_selected_skill "$kind" "$selected_json" || return 1
}

# Audio catalog uses the same explicit estimated-parameter / memory-fit convention as
# the image and video catalogue. A '~' means inferred, not a measured model spec.
model_manager_audio_json() {
    local limit="${1:-80}" search="${2:-}"
    model_manager_ensure || return 1
    "$VENV_PY" - "$limit" "$search" <<'PY_AUDIO_CATALOG'
import json, math, re, sys
from huggingface_hub import HfApi
try:
    from services.hwfit.hardware import detect_system
    hardware=detect_system(fresh=True) or {}
except Exception:
    hardware={}
limit=max(1,min(200,int(sys.argv[1] or 80))); query=sys.argv[2]
ram=float(hardware.get('system_ram_gb') or hardware.get('ram_gb') or hardware.get('memory_gb') or 0)
vram=float(hardware.get('gpu_vram_gb') or 0)
if ram<=0:
    try:
        ram=int(next(x.split()[1] for x in open('/proc/meminfo') if x.startswith('MemTotal:')))/1048576
    except Exception: ram=0
api=HfApi()
rows={}
for tag in ('automatic-speech-recognition','text-to-speech','text-to-audio','audio-to-audio'):
    try:
        kwargs=dict(pipeline_tag=tag,search=query or None,sort='downloads',limit=max(30,limit//2))
        try: infos=list(api.list_models(**kwargs,expand=['downloads','likes','usedStorage','safetensors','library_name','pipeline_tag','gated']))
        except Exception: infos=list(api.list_models(**kwargs,full=True))
    except Exception as exc:
        print(f'Audio model search for {tag}: {exc}',file=sys.stderr); continue
    for m in infos:
        repo=str(getattr(m,'id','') or '')
        if repo.count('/')!=1 or getattr(m,'gated',False): continue
        size=getattr(m,'used_storage',None) or getattr(m,'usedStorage',None)
        size_gb=round(int(size)/1073741824,3) if size else None
        st=getattr(m,'safetensors',None)
        counts=st.get('parameters') if isinstance(st,dict) else getattr(st,'parameters',None)
        params=sum(float(v) for v in counts.values())/1e9 if isinstance(counts,dict) else None
        approximated=params is None
        # Model repo size may include checkpoints, so weight/parameter estimates
        # are rough and never presented as measured facts.
        if params is None and size_gb: params=round(size_gb*0.65/2,3)
        if params is None:
            needle=repo.lower()
            known=(('tiny',0.04),('base',0.08),('small',0.25),('medium',0.8),('large',1.5),('mini',0.2))
            params=next((p for word,p in known if word in needle),None)
        if params is None and tag in ('text-to-audio','audio-to-audio'): continue
        if params is None: params=0.8
        required=round(max(0.5,(size_gb or params*2)*1.18+(0.55 if tag=='automatic-speech-recognition' else 1.0)),2)
        if vram:
            fit='perfect' if required<=vram*.65 else 'good' if required<=vram*.85 else 'tight' if required<=vram else 'cpu_offload' if ram and required<=ram*.45 else 'poor'
        elif ram:
            fit='good' if required<=ram*.30 else 'tight' if required<=ram*.45 else 'poor'
        else: fit='manual'
        dl=int(getattr(m,'downloads',0) or 0); likes=int(getattr(m,'likes',0) or 0)
        score=round({'perfect':65,'good':55,'tight':42,'cpu_offload':30,'manual':18,'poor':0}[fit]+min(20,math.log10(dl+1)*3),1)
        data=dict(name=repo,repo=repo,model_type='audio',pipeline_tag=tag,
                  parameter_count=('~' if approximated else '')+f'{params:.3g}B',
                  params_b=params,params_source='estimate' if approximated else 'hub',
                  size_gb=size_gb,estimated_size_gb=round(params*2.1,2) if not size_gb else None,
                  quant='~FP16' if approximated else 'FP16?',required_gb=required,
                  speed_tps='?',fit_level=fit,score=score,downloads=dl,likes=likes,
                  gated=False,library_name=getattr(m,'library_name','') or '')
        if repo not in rows or rows[repo]['score']<score: rows[repo]=data
print(json.dumps({'hardware':hardware,'models':sorted(rows.values(),key=lambda x:x['score'],reverse=True)[:limit]}))
PY_AUDIO_CATALOG
}

# Audio auto-fit provisions two distinct jobs: speech recognition and speech
# synthesis; general music generation appears in Manual Audio but is not falsely
# advertised as runnable through a generic Transformers pipeline.
auto_fit_audio_dependencies() {
    [[ -x "$VENV_PY" ]] || { echo 'ERROR: Zarzysseus Python missing.'; return 1; }
    command -v ffmpeg >/dev/null 2>&1 || install_missing_packages ffmpeg || return 1
    dependency_repair_pip "$VENV_PY" soundfile librosa || return 1
    "$VENV_PY" -c 'import torch,transformers, soundfile,librosa,huggingface_hub' || return 1
}

model_manager_auto_fit_audio() {
    local tmp_json selected_json task repo
    tmp_json="$(mktemp)" || return 1
    model_manager_audio_json 200 '' >"$tmp_json" || { rm -f "$tmp_json"; return 1; }
    for task in automatic-speech-recognition text-to-speech; do
        selected_json="$("$VENV_PY" - "$tmp_json" "$task" <<'PY_AUDIO_PICK'
import json,sys
rows=json.load(open(sys.argv[1])).get('models',[])
task=sys.argv[2]
order={'perfect':0,'good':1,'tight':2,'cpu_offload':3}
rows=[r for r in rows if r.get('pipeline_tag')==task and r.get('fit_level') in order
      and r.get('library_name','').lower() in ('','transformers')]
rows.sort(key=lambda r:(order[r['fit_level']],-float(r.get('score') or 0)))
if not rows: raise SystemExit('ERROR: No supported '+task+' model meets the detected hardware fit.')
print(json.dumps(rows[0]))
PY_AUDIO_PICK
)" || { rm -f "$tmp_json"; return 1; }
        repo="$(printf '%s' "$selected_json" | "$VENV_PY" -c 'import json,sys; print(json.load(sys.stdin)["repo"])')"
        echo "==> AUDIO AUTO-FIT [$task]: $repo"
        printf '%s\n' "$selected_json" | "$VENV_PY" -c 'import json,sys;x=json.load(sys.stdin);print("    parameters={}  memory~{}GB  fit={}  size~{}GB".format(x["parameter_count"],x["required_gb"],x["fit_level"], x.get("size_gb") or x.get("estimated_size_gb")))'
        auto_fit_audio_dependencies || { rm -f "$tmp_json"; return 1; }
        hf_pull_model "$repo" || { rm -f "$tmp_json"; return 1; }
        audio_create_skill "$selected_json" || { rm -f "$tmp_json"; return 1; }
    done
    rm -f "$tmp_json"
}

audio_create_skill() {
    local selection="$1" skill_root
    skill_root="$("$VENV_PY" - "$selection" "$AUTO_FIT_SKILL_DIR" "$HF_HUB_CACHE" "$VENV_PY" <<'PY_AUDIO_SKILL'
import json,re,sys
from pathlib import Path
info=json.loads(sys.argv[1]); root=Path(sys.argv[2]); hub=Path(sys.argv[3]); interpreter=sys.argv[4]; repo=info['repo']; task=info['pipeline_tag']
if task not in ('automatic-speech-recognition','text-to-speech'): raise SystemExit('Unsupported automated audio pipeline')
if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repo): raise SystemExit('Invalid repo')
snap=hub/('models--'+repo.replace('/','--'))/'snapshots'
choices=sorted((p for p in snap.glob('*') if p.is_dir()),key=lambda p:p.stat().st_mtime,reverse=True)
if not choices: raise SystemExit('Audio weights were not downloaded into the selected Hugging Face cache')
name='zarzysseus-audio-'+re.sub('[^a-z0-9-]+','-',repo.lower().replace('/','-')).strip('-')
dest=root/name;dest.mkdir(parents=True,exist_ok=True)
info.update(snapshot=str(choices[0]),kind='audio')
(dest/'model.json').write_text(json.dumps(info,indent=2)+'\n')
(dest/'SKILL.md').write_text('---\nname: '+name+'\ndescription: Offline '+task+' using '+repo+' on Zarzysseus.\n---\n\nUse the environment interpreter: `'+interpreter+' '+str(dest/'run.py')+' --check` before using. For recognition add `--file recording.wav`; for synthesis add `--text "..." --output speech.wav`. Never send audio to a cloud service without consent.\n')
(dest/'run.py').write_text('''#!/usr/bin/env python3
import argparse,json,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--file');p.add_argument('--text');p.add_argument('--output',default='speech.wav');a=p.parse_args()
meta=json.loads((Path(__file__).parent/'model.json').read_text());task=meta['pipeline_tag'];snap=Path(meta['snapshot'])
if not snap.exists(): raise SystemExit('Audio model cache missing')
import torch,soundfile as sf
from transformers import pipeline
if a.check:
    print('Audio runtime imports and model files present (inference not tested)');sys.exit(0)
pipe=pipeline(task,model=str(snap),device=0 if torch.cuda.is_available() else -1)
if task=='automatic-speech-recognition':
    if not a.file: p.error('--file required')
    print(pipe(a.file)['text'])
else:
    if not a.text: p.error('--text required')
    result=pipe(a.text)
    sf.write(a.output,result['audio'].squeeze(),result['sampling_rate'])
    print(a.output)
''')
print(dest)
PY_AUDIO_SKILL
)" || return 1
    skills_install_skill_manifests "$skill_root" || return 1
    SKILLS_SYNC_DEFER_RESTART=1 skills_sync_installed_skill_to_odysseus "$skill_root" '' || return 1
    AUTO_FIT_SKILLS_SYNCED=1
    dependency_repair_python_command "$VENV_PY" "$skill_root/run.py" --check || return 1
}

# Desert Ant is a collection of tiny task-specific on-device models, not a
# replacement for a general chat LLM or photo/video generator. The official
# Linux CLI cannot run Apple-only Voz/Uhm/Title; show honest capability gaps.
DESERTANT_INSTALL_URL='https://raw.githubusercontent.com/Desert-Ant-Labs/desert-ant-cli/main/install.sh'
DESERTANT_SKILL_DIR="${DESERTANT_SKILL_DIR:-$HOME/.local/share/zarzysseus/desert-ant-skills}"
desertant_ensure_cli() {
    if command -v desertant >/dev/null 2>&1 || command -v da >/dev/null 2>&1; then return 0; fi
    case "$(uname -m)" in x86_64|aarch64|arm64) ;; *) echo 'ERROR: Desert Ant CLI has no documented Linux release for this architecture.'; return 1 ;; esac
    command -v curl >/dev/null 2>&1 || install_missing_packages curl || return 1
    local script_file
    script_file="$(mktemp)" || return 1
    echo '==> Installing official Desert Ant Labs CLI; release hashes are checked by its installer.'
    if ! curl -fsSL --retry 3 "$DESERTANT_INSTALL_URL" -o "$script_file"; then
        rm -f "$script_file"; return 1
    fi
    if ! bash "$script_file"; then rm -f "$script_file"; return 1; fi
    rm -f "$script_file"
    export PATH="$HOME/.local/bin:$PATH"
    command -v desertant >/dev/null 2>&1 || command -v da >/dev/null 2>&1 || {
        echo 'ERROR: Desert Ant CLI installation did not yield a usable command.'; return 1;
    }
}

desertant_bin() {
    command -v desertant 2>/dev/null || command -v da 2>/dev/null
}

desertant_install_selected() {
    local model="$1" cli root slug
    case "$model" in
        redact|emo|gist|clear|ear|clips|tongue) ;;
        voz|uhm|title)
            echo "ERROR: $model is not available in the documented Linux Desert Ant CLI. It may be Apple-only."
            return 2 ;;
        *) echo "ERROR: Unknown/unsupported Desert Ant CLI model: $model"; return 2 ;;
    esac
    desertant_ensure_cli || return 1
    cli="$(desertant_bin)" || return 1
    "$cli" info "$model" || { echo "ERROR: $model is not advertised by this Desert Ant CLI build."; return 1; }
    root="$DESERTANT_SKILL_DIR/zarzysseus-low-spec-$model"
    mkdir -p "$root" || return 1
    cat >"$root/SKILL.md" <<EOF_DESERT_ANT_SKILL
---
name: zarzysseus-low-spec-$model
description: Use the local Desert Ant Labs $model specialist via the official CLI.
---

Run \`$cli info $model\` for capabilities, supported flags and limits.
Run \`$cli $model --help\` for the installed CLI's exact arguments.
Use \`bash run.sh ...\` from this skill directory, passing a file or text as documented by the CLI.
This is an on-device specialist. Do not advertise it as a general LLM, image generator or video generator.
The CLI caches weights on first inference; the installer verifies command availability and metadata, not an inference run.
EOF_DESERT_ANT_SKILL
    printf '#!/usr/bin/env bash\nset -euo pipefail\nexec %q %q "$@"\n' "$cli" "$model" >"$root/run.sh"
    chmod 0755 "$root/run.sh"
    if application_installed; then
        SKILLS_SYNC_DEFER_RESTART=1 skills_sync_installed_skill_to_odysseus "$root" '' || return 1
        AUTO_FIT_SKILLS_SYNCED=1
    else
        echo "    [note] Core Zarzysseus not installed: specialist skill staged at $root."
        echo '           Low-spec mode intentionally avoids forcing the heavyweight base stack.'
    fi
    echo "    [ready] Desert Ant specialist: $model (CLI + skill; weights may fetch on first run)"
}

desertant_auto_fit() {
    local profile="${1:-text-video-photo-audio}" kind failed=0
    local -A chosen=()
    local -a tokens=()
    profile="${profile//+/-}"
    IFS='-' read -r -a tokens <<< "$profile"
    for kind in "${tokens[@]}"; do
        case "$kind" in text|photo|video|audio) chosen[$kind]=1 ;; *) echo "Unknown low-spec kind: $kind"; return 2 ;; esac
    done
    if [[ -n "${chosen[photo]:-}" ]]; then
        echo 'NOT AVAILABLE: Desert Ant Labs does not offer a supported Linux photo GENERATOR in its documented CLI.'
        echo 'No unrelated model will be silently substituted. Pick a profile without photo or use regular auto-fit.'
        return 2
    fi
    desertant_ensure_cli || return 1
    AUTO_FIT_SKILLS_SYNCED=0
    if [[ -n "${chosen[text]:-}" ]]; then
        for kind in redact emo gist; do desertant_install_selected "$kind" || failed=1; done
    fi
    if [[ -n "${chosen[video]:-}" ]]; then
        echo 'NOTE: Desert Ant Clips is a local VIDEO EDITING/highlight tool, NOT a video generator.'
        desertant_install_selected clips || failed=1
    fi
    if [[ -n "${chosen[audio]:-}" ]]; then
        echo 'NOTE: Linux Desert Ant provides speech CLEANUP/IDENTIFICATION; Voz transcription is Apple-only.'
        for kind in clear ear; do desertant_install_selected "$kind" || failed=1; done
    fi
    auto_fit_finalize_skills || failed=1
    (( failed == 0 )) || { echo 'ERROR: One or more supported low-spec tools failed to install.'; return 1; }
    echo 'Low-spec specialist setup complete. Use normal audio auto-fit for Linux speech recognition.'
}

desertant_install_core_sdk() {
    desertant_ensure_cli || return 1
    install_node_if_missing || return 1
    local sdk_dir="$HOME/.local/share/zarzysseus/desert-ant-sdk"
    mkdir -p "$sdk_dir" || return 1
    # Tongue's documented npm package is pure JavaScript; this avoids
    # introducing heavyweight speculative native dependencies on low-end PCs.
    dependency_repair_npm "$sdk_dir" install '@desert-ant-labs/tongue' || return 1
    echo "    [ready] Desert Ant Tongue JS SDK installed: $sdk_dir"
}

# Low Power Spec (L.P.S.) is a distinct, curated generative model tier.
# Desert Ant Labs is kept separately for specialized (non-generative) tools.
LPS_ROOT="${LPS_ROOT:-$HOME/.local/share/zarzysseus/lps}"
LPS_VENV="${LPS_VENV:-$LPS_ROOT/venv}"
LPS_SKILLS_DIR="${LPS_SKILLS_DIR:-$LPS_ROOT/skills}"

lps_hardware_json() {
    python3 - <<'PY_LPS_HARDWARE'
import json,os,subprocess
from pathlib import Path
ram=0.;vram=0.
try:
    ram=round(int(next(x.split()[1] for x in Path('/proc/meminfo').read_text().splitlines() if x.startswith('MemTotal:')))/1048576,2)
except Exception: pass
for path in Path('/sys/class/drm').glob('card*/device/mem_info_vram_total'):
    try: vram=max(vram,round(int(path.read_text())/1073741824,2))
    except Exception: pass
if not vram:
    try:
        values=subprocess.check_output(['nvidia-smi','--query-gpu=memory.total','--format=csv,noheader,nounits'],stderr=subprocess.DEVNULL,timeout=3,text=True)
        vram=max(float(line.strip())/1024 for line in values.splitlines() if line.strip())
    except Exception: pass
print(json.dumps({'ram_gb':round(ram,2),'vram_gb':round(vram,2)}))
PY_LPS_HARDWARE
}

# Every entry has a *specific supported runtime*. Sizes and peak memory are
# indicative only; video is NOT promised to run on 2-4 GB machines.
lps_catalog_rows() {
    lps_hardware_json | python3 -c '
import sys,json
h=json.load(sys.stdin);ram=h["ram_gb"];vram=h["vram_gb"]
models=[
 ("SmolLM2 135M (minimum)","HuggingFaceTB/SmolLM2-135M-Instruct","text","text-generation","0.135B","~0.3G","FP16",0.8,0.,0.8),
 ("Qwen3 0.6B","Qwen/Qwen3-0.6B","text","text-generation","0.6B","~1.3G","BF16",2.0,0.,2.),
 # Coarse, explicitly labeled *model-equivalent* estimates from the
 # approximate repository sizes assuming mostly FP16 weights. These are not
 # published architecture counts: diffusers repos can contain multiple
 # components/checkpoints, making the estimates particularly uncertain.
 ("Tiny-SD","segmind/tiny-sd","image","text-to-image","~0.4B","~1.1G","FP16",6.,2.,3.),
 ("ZeroScope 576w (entry video)","cerspense/zeroscope_v2_576w","video","text-to-video","~3.0B","~8.5G","FP16",16.,8.,8.),
 ("Whisper Tiny (ASR)","openai/whisper-tiny","audio","automatic-speech-recognition","0.039B","~0.15G","FP16",2.,0.,1.),
]
for name,repo,kind,task,params,size,prec,ram_min,vram_min,est in models:
    # CPU/offload may be very slow; video auto-selection is deliberately GPU-only.
    if kind=="video": fit="good" if vram>=vram_min and ram>=ram_min else "poor"
    elif kind=="image": fit="good" if vram>=vram_min and ram>=4 else "cpu_offload" if ram>=ram_min else "poor"
    else: fit="good" if ram>=ram_min else "poor"
    cols=(name,repo,kind,task,params,size,prec,str(est),"?",fit,"LPS","-","?","?")
    print("\t".join(cols))
'
}

desertant_catalog_rows() {
    # Specialist CLI models are not generators. Runtime planning figures are
    # not published requirements, so use CPU/unknown rather than invented VRAM.
    local name id kind task size
    while IFS='|' read -r name id kind task size; do
        [[ -n "$id" ]] || continue
        # N/P is intentional: Desert Ant does not publish comparable model
        # parameter counts for all of these specialist CLI components.
        [[ "$size" == '?' ]] && size='unlisted'
        printf '%s\t%s\t%s\t%s\tN/P\t%s\tCPU\tCPU\tn/a\tspecialist\tDAL\t-\t?\t?\n' \
            "$name" "desertant:$id" "$kind" "$task" "$size"
    done <<'EOF_DESERTANT_CATALOG'
Clear|clear|audio|audio-cleanup|~24M
Ear|ear|audio|language-identification|?
Clips|clips|video|highlights-not-generation|?
Redact|redact|text|pii-redaction|?
Emo|emo|text|emoji-tagging|?
Gist|gist|text|topic-tagging|?
Tongue|tongue|text|language-identification|~2M
EOF_DESERTANT_CATALOG
}

lps_spec() {
    LPS_KIND='' LPS_REPO='' LPS_TASK='' LPS_MIN_RAM=0 LPS_MIN_VRAM=0
    case "$1" in
        'HuggingFaceTB/SmolLM2-135M-Instruct') LPS_KIND=text; LPS_TASK=text-generation; LPS_MIN_RAM=0.8 ;;
        'Qwen/Qwen3-0.6B') LPS_KIND=text; LPS_TASK=text-generation; LPS_MIN_RAM=2 ;;
        'segmind/tiny-sd') LPS_KIND=image; LPS_TASK=text-to-image; LPS_MIN_RAM=6 ;;
        'cerspense/zeroscope_v2_576w') LPS_KIND=video; LPS_TASK=text-to-video; LPS_MIN_RAM=16; LPS_MIN_VRAM=8 ;;
        'openai/whisper-tiny') LPS_KIND=audio; LPS_TASK=automatic-speech-recognition; LPS_MIN_RAM=2 ;;
        *) echo "ERROR: Unknown L.P.S. repository: $1"; return 2 ;;
    esac
    LPS_REPO="$1"
}

lps_require_fit() {
    local repo="$1" hardware
    lps_spec "$repo" || return 1
    hardware="$(lps_hardware_json)" || return 1
    python3 - "$hardware" "$LPS_KIND" "$LPS_MIN_RAM" "$LPS_MIN_VRAM" <<'PY_LPS_FIT'
import json,sys
h=json.loads(sys.argv[1]);kind=sys.argv[2];ram_min=float(sys.argv[3]);vram_min=float(sys.argv[4]);ram=h['ram_gb'];vram=h['vram_gb']
if kind=='video': ok=ram>=ram_min and vram>=vram_min
elif kind=='image': ok=ram>=ram_min or (ram>=4 and vram>=2)
else: ok=ram>=ram_min
if not ok:
 print(f'ERROR: L.P.S. {kind} requires approximately {ram_min:g} GB system RAM' + (f' and {vram_min:g} GB VRAM' if kind=='video' else ' (or image GPU offload where supported)') + f'; detected {ram:g} GB RAM / {vram:g} GB VRAM. No download started.',file=sys.stderr)
 raise SystemExit(1)
print(f'    [fit] {kind}: detected {ram:g} GB RAM / {vram:g} GB VRAM; estimated fit only, not a generation test.')
PY_LPS_FIT
}

lps_install_model() {
    local repo="$1" python_bin snapshot skill_root requirements rc=0
    lps_require_fit "$repo" || return 1
    mkdir -p "$LPS_ROOT" "$LPS_SKILLS_DIR" || return 1
    if [[ -x "${VENV_PY:-/nonexistent}" ]]; then python_bin="$VENV_PY"
    else
        if [[ ! -x "$LPS_VENV/bin/python" ]]; then
            command -v python3 >/dev/null || { echo 'ERROR: Python3 required for the L.P.S. environment'; return 1; }
            python3 -m venv "$LPS_VENV" || { echo 'ERROR: python3-venv missing. Install the system venv package and retry.'; return 1; }
        fi
        python_bin="$LPS_VENV/bin/python"
    fi
    # No heavyweight core stack is installed when the user picks L.P.S. only.
    dependency_repair_pip "$python_bin" huggingface_hub || return 1
    case "$LPS_KIND" in
        text|audio) requirements=(torch transformers accelerate safetensors);;
        image|video) requirements=(torch diffusers transformers accelerate safetensors pillow);;
    esac
    [[ "$LPS_KIND" == audio ]] && requirements+=(soundfile librosa)
    [[ "$LPS_KIND" == video ]] && requirements+=(imageio imageio-ffmpeg)
    dependency_repair_pip "$python_bin" "${requirements[@]}" || return 1
    if [[ "$LPS_KIND" == video ]]; then
        command -v ffmpeg >/dev/null 2>&1 || install_missing_packages ffmpeg || return 1
    fi
    echo "==> L.P.S. model: $repo ($LPS_KIND); downloading verified repository ID"
    snapshot="$("$python_bin" - "$repo" "$LPS_ROOT/models" <<'PY_LPS_DOWNLOAD'
import sys
from pathlib import Path
from huggingface_hub import snapshot_download
repo=sys.argv[1];base=Path(sys.argv[2]);base.mkdir(parents=True,exist_ok=True)
path=base/(repo.replace('/','--'))
print(snapshot_download(repo_id=repo,local_dir=str(path)))
PY_LPS_DOWNLOAD
)" || return 1
    [[ -d "$snapshot" ]] || { echo 'ERROR: Model snapshot missing after download.'; return 1; }
    skill_root="$LPS_SKILLS_DIR/zarzysseus-lps-${LPS_KIND}-${repo//\//--}"
    mkdir -p "$skill_root" || return 1
    "$python_bin" - "$repo" "$LPS_KIND" "$LPS_TASK" "$snapshot" "$skill_root" "$python_bin" <<'PY_LPS_SKILL'
import json,sys
from pathlib import Path
repo,kind,task,snapshot,folder,python=sys.argv[1:]
root=Path(folder);meta={'repo':repo,'kind':kind,'task':task,'snapshot':snapshot}
(root/'model.json').write_text(json.dumps(meta,indent=2)+'\n')
(root/'SKILL.md').write_text('---\nname: '+root.name+'\ndescription: Local Low Power Spec '+kind+' model '+repo+'.\n---\n\nRun `'+python+' '+str(root/'run.py')+' --check` to check dependencies, or `--prompt "..." --output result` for text, image and video; for ASR use `--file recording.wav`. Video is an entry-level video model, not guaranteed on all low-spec hardware. All memory estimates are approximate.\n')
(root/'run.py').write_text('''#!/usr/bin/env python3
import argparse,json,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--prompt');p.add_argument('--file');p.add_argument('--output',default='output');p.add_argument('--steps',type=int,default=20);a=p.parse_args()
m=json.loads((Path(__file__).parent/'model.json').read_text());snap=Path(m['snapshot']);kind=m['kind']
if not snap.is_dir(): raise SystemExit('Model files missing: '+str(snap))
import torch
if kind in ('text','audio'):
 from transformers import pipeline
else:
 from diffusers import DiffusionPipeline
if a.check:
 print('Dependencies import and files exist; inference not tested');sys.exit(0)
if kind=='text':
 if not a.prompt: p.error('--prompt required')
 pipe=pipeline('text-generation',model=str(snap),device=0 if torch.cuda.is_available() else -1)
 result=pipe(a.prompt,max_new_tokens=180)
 print(result[0].get('generated_text',''))
elif kind=='audio':
 if not a.file: p.error('--file required')
 pipe=pipeline('automatic-speech-recognition',model=str(snap),device=0 if torch.cuda.is_available() else -1)
 print(pipe(a.file)['text'])
else:
 if not a.prompt: p.error('--prompt required')
 dtype=torch.float16 if torch.cuda.is_available() else torch.float32
 pipe=DiffusionPipeline.from_pretrained(str(snap),torch_dtype=dtype)
 if torch.cuda.is_available():
  pipe.enable_model_cpu_offload()
 else:
  pipe.to('cpu')
 if kind=='image':
  result=pipe(prompt=a.prompt,num_inference_steps=a.steps,height=384,width=384)
  path=a.output if Path(a.output).suffix else a.output+'.png'
  result.images[0].save(path);print(path)
 else:
  from diffusers.utils import export_to_video
  result=pipe(prompt=a.prompt,num_frames=8,height=320,width=576,num_inference_steps=a.steps)
  path=a.output if Path(a.output).suffix else a.output+'.mp4'
  export_to_video(result.frames[0],path,fps=8);print(path)
''')
(root/'run.py').chmod(0o755)
PY_LPS_SKILL
    dependency_repair_python_command "$python_bin" "$skill_root/run.py" --check || return 1
    if application_installed; then
        SKILLS_SYNC_DEFER_RESTART=1 skills_sync_installed_skill_to_odysseus "$skill_root" '' || return 1
        AUTO_FIT_SKILLS_SYNCED=1
    fi
    echo "    [ready] L.P.S. skill: $skill_root (dependencies + files; inference not yet verified)."
}

lps_install_profile() {
    local profile="${1:-text-video-photo-audio}" part repo failed=0
    local -A picked=()
    profile="${profile//+/-}"
    IFS='-' read -r -a parts <<<"$profile"
    (( ${#parts[@]} )) || return 2
    for part in "${parts[@]}"; do
        case "$part" in text|photo|video|audio) ;; *) echo "ERROR: Unsupported L.P.S. type: $part"; return 2 ;; esac
        [[ -z "${picked[$part]:-}" ]] || return 2
        picked[$part]=1
    done
    echo "==> L.P.S. AUTO FIT: $profile (Desert Ant tools are a separate tier)."
    AUTO_FIT_SKILLS_SYNCED=0
    if [[ -n "${picked[text]:-}" ]]; then
        repo='Qwen/Qwen3-0.6B'
        lps_require_fit "$repo" >/dev/null 2>&1 || repo='HuggingFaceTB/SmolLM2-135M-Instruct'
        lps_install_model "$repo" || failed=1
    fi
    [[ -z "${picked[photo]:-}" ]] || lps_install_model 'segmind/tiny-sd' || failed=1
    [[ -z "${picked[video]:-}" ]] || lps_install_model 'cerspense/zeroscope_v2_576w' || failed=1
    [[ -z "${picked[audio]:-}" ]] || lps_install_model 'openai/whisper-tiny' || failed=1
    auto_fit_finalize_skills || failed=1
    (( failed == 0 )) || { echo 'ERROR: One or more L.P.S. models could not be prepared on this hardware.'; return 1; }
    echo '==> L.P.S. models and task-specific skills prepared; run a sample inference to verify end-to-end generation.'
}

full_install_auto_fit_profile() {
    local profile="${1:-text-video-photo-audio}" kind
    local -A picked=()
    local -a types=()
    case "$profile" in
        all|full) profile=text-video-photo-audio ;;
        image|photo-only) profile=photo ;;
        video-only) profile=video ;;
        text-only) profile=text ;;
        audio-only) profile=audio ;;
        text-image) profile=text-photo ;;
        image-video|photo-video) profile=video-photo ;;
    esac
    profile="${profile//+/-}"
    IFS='-' read -r -a types <<< "$profile"
    (( ${#types[@]} > 0 )) || { echo 'ERROR: Empty auto-fit profile.'; return 2; }
    for kind in "${types[@]}"; do
        case "$kind" in
            text|photo|video|audio) ;;
            *) echo "ERROR: Unsupported auto-fit category: $kind"; return 2 ;;
        esac
        [[ -z "${picked[$kind]:-}" ]] || { echo "ERROR: Duplicate category: $kind"; return 2; }
        picked[$kind]=1
    done
    install_odysseus || return 1
    echo "==> AUTO-FIT PROFILE: $profile"
    AUTO_FIT_SKILLS_SYNCED=0
    if [[ -n "${picked[text]:-}" ]]; then model_manager_auto_fit_text || return 1; fi
    if [[ -n "${picked[video]:-}" ]]; then model_manager_auto_fit_media video || return 1; fi
    if [[ -n "${picked[photo]:-}" ]]; then model_manager_auto_fit_media image || return 1; fi
    if [[ -n "${picked[audio]:-}" ]]; then model_manager_auto_fit_audio || return 1; fi
    auto_fit_finalize_skills || return 1
    echo "==> Auto-fit installation finished: $profile (models, dependencies, and skills)."
}

# ------------------------------------------
# Hardware-aware multi-provider model selection
# ------------------------------------------

normalize_model_input() {
    local raw="$1" value
    value="${raw#"${raw%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    case "${value,,}" in
        dolphin|dolphin-mistral|dphn/dolphin-mistral-24b-venice-edition)
            echo "dphn/Dolphin-Mistral-24B-Venice-Edition"
            ;;
        qwen3.8|qwen3.8:latest)
            echo "qwen3.8"
            ;;
        distill|qwen3.8-9b-distill|tobestyledintro/qwen3.8-9b-distill)
            echo "tobestyledintro/qwen3.8-9b-distill"
            ;;
        llama3.1|llama3.1:8b)
            echo "llama3.1:8b"
            ;;
        *)
            echo "$value"
            ;;
    esac
}

model_provider_ready() {
    local provider="${1,,}"
    case "$provider" in
        ollama)
            ollama_binary_installed
            ;;
        vllm)
            [[ "$INSTALL_VLLM" == "1" ]] && [[ -x "$VLLM_VENV_DIR/bin/python" ]] && test_engine_installed "vLLM" "$VLLM_VENV_DIR" vllm vllm
            ;;
        sglang)
            [[ "$INSTALL_SGLANG" == "1" ]] && [[ -x "$SGLANG_VENV_DIR/bin/python" ]] && test_engine_installed "SGLang" "$SGLANG_VENV_DIR" sglang sglang
            ;;
        mlx_lm|mlx|mlx-lm)
            # MLX-LM is an Apple/Metal runtime. Do not auto-select it on Linux.
            [[ "$(uname -s 2>/dev/null || true)" == "Darwin" ]] || return 1
            [[ "$INSTALL_MLX_LM" == "1" ]] && [[ -x "$MLX_LM_VENV_DIR/bin/python" ]] && "$MLX_LM_VENV_DIR/bin/python" -c 'import mlx,mlx_lm' >/dev/null 2>&1
            ;;
        *)
            return 1
            ;;
    esac
}

model_source_and_provider() {
    local raw="$1" model provider prefix
    raw="$(normalize_model_input "$raw")"
    [[ -n "$raw" ]] || { echo "ERROR|No model name supplied."; return 2; }

    # Explicit provider prefixes always win. Examples:
    #   ollama:qwen3.8
    #   vllm:org/model
    #   sglang:org/model
    #   mlx_lm:org/model
    if [[ "$raw" == *:* ]]; then
        prefix="${raw%%:*}"
        case "${prefix,,}" in
            ollama|vllm|sglang|mlx_lm|mlx|mlx-lm)
                provider="${prefix,,}"
                model="${raw#*:}"
                model="$(normalize_model_input "$model")"
                case "$provider" in
                    mlx|mlx-lm) provider="mlx_lm" ;;
                esac
                [[ -n "$model" ]] || { echo "ERROR|Model name is empty after provider prefix."; return 2; }
                echo "$provider|$model"
                return 0
                ;;
        esac
    fi

    model="$raw"

    # A model already known to Ollama is always treated as an Ollama model.
    # This catches tags such as :8b as well as custom locally-installed names.
    if ollama_api_ready && ollama_has_model "$model"; then
        echo "ollama|$model"
        return 0
    fi

    # Ollama-style names without an org/repo separator are pulled through
    # Ollama. This covers the curated qwen3.8 and llama3.1:8b choices.
    if [[ "$model" != */* ]]; then
        if model_provider_ready ollama; then
            echo "ollama|$model"
            return 0
        fi
        echo "ERROR|No Ollama runtime is available for '$model'. Use provider:model or org/model."
        return 1
    fi

    # Hugging Face-style org/model IDs prefer the fastest installed local
    # accelerator runtime for this machine, then fall back through the order.
    local entry normalized_order=""
    IFS=',' read -r -a provider_order <<< "$MODEL_AUTO_PROVIDER_ORDER"
    for entry in "${provider_order[@]}"; do
        normalized_order+="${entry,,},"
    done

    # On Apple Silicon MLX-LM is the native runtime; on Linux it is skipped by
    # model_provider_ready(). The order remains configurable for future stacks.
    IFS=',' read -r -a provider_order <<< "$normalized_order"
    for entry in "${provider_order[@]}"; do
        entry="${entry%,}"
        case "$entry" in
            vllm|sglang|mlx_lm|mlx|mlx-lm)
                if model_provider_ready "$entry"; then
                    [[ "$entry" == mlx || "$entry" == mlx-lm ]] && entry="mlx_lm"
                    echo "$entry|$model"
                    return 0
                fi
                ;;
            ollama)
                # An HF-style org/model is only routed to Ollama if that exact
                # model is already present there; otherwise accelerated HF
                # runtimes are more appropriate.
                if ollama_api_ready && ollama_has_model "$model"; then
                    echo "ollama|$model"
                    return 0
                fi
                ;;
        esac
    done

    echo "ERROR|No installed local provider can serve '$model'. Install/repair vLLM or SGLang, or use an explicit provider prefix."
    return 1
}

pull_model_auto() {
    local requested="${1:-}" include_pattern="${2:-}" resolved provider model
    [[ -n "$requested" ]] || { echo "ERROR: No model supplied."; return 2; }

    resolved="$(model_source_and_provider "$requested")" || {
        echo "$resolved" >&2
        return 1
    }
    if [[ "$resolved" == ERROR\|* ]]; then
        echo "${resolved#ERROR|}" >&2
        return 1
    fi

    provider="${resolved%%|*}"
    model="${resolved#*|}"
    echo "==> Auto provider selection: $requested -> $provider -> $model"

    case "$provider" in
        ollama)
            application_installed || install_odysseus
            if ! ollama_api_ready; then
                ollama_start
            fi
            ollama_api_ready || { echo "ERROR: Ollama API is not reachable at $OLLAMA_ENDPOINT"; return 1; }
            ollama pull "$model" || return 1
            sync_ollama_with_odysseus "$model" || return 1
            echo "Ollama model ready: $model"
            ;;
        vllm)
            pull_vllm_model "$model" "$include_pattern"
            ;;
        sglang)
            pull_sglang_model "$model" "$include_pattern"
            ;;
        mlx_lm)
            pull_mlx_model "$model" "$include_pattern"
            ;;
        *)
            echo "ERROR: Unsupported resolved provider '$provider'." >&2
            return 2
            ;;
    esac
}

pull_models_auto_batch() {
    local saved_default="" final_default="" final_provider="" selected="" model provider rest
    local preserve_default=0 auto_was_selected=0
    local -a selections=("$@")
    [[ ${#selections[@]} -gt 0 ]] || { echo "ERROR: No models were selected."; return 2; }

    if [[ -f "$DEFAULT_MODEL_CONFIGURED_FILE" ]]; then
        saved_default="$(head -n1 "$DEFAULT_MODEL_CONFIGURED_FILE" 2>/dev/null || true)"
    fi
    if [[ -z "$saved_default" && -n "$DEFAULT_MODEL_PROVIDER" && -n "$DEFAULT_MODEL_ID" ]]; then
        saved_default="${DEFAULT_MODEL_PROVIDER}:${DEFAULT_MODEL_ID}"
    fi

    for selected in "${selections[@]}"; do
        [[ -n "$selected" ]] || continue
        if [[ "$selected" == "__AUTO_BEST_FIT__" ]]; then
            auto_was_selected=1
            model_manager_auto_pick || return 1
            if [[ -f "$MODEL_MANAGER_STATE_FILE" ]]; then
                final_default="$($VENV_DIR/bin/python - "$MODEL_MANAGER_STATE_FILE" <<'PY_AUTO_STATE'
import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print(str(d.get("repo") or "").strip())
except Exception:
    print("")
PY_AUTO_STATE
)"
                final_provider="vllm"
            fi
            continue
        fi
        pull_model_auto "$selected" || return 1
    done

    # Pulling through the individual legacy commands can update Zarzysseus's
    # default model. Preserve the user's existing default for ordinary multi-
    # select installs, while an explicit PERFECT-fit auto-pick becomes the new
    # default because that option represents an intentional default choice.
    if (( auto_was_selected )) && [[ -n "$final_default" ]]; then
        configure_engine_default_model "$final_provider" "$final_default" || true
    elif [[ -n "$saved_default" && "$saved_default" == *:* ]]; then
        provider="${saved_default%%:*}"
        model="${saved_default#*:}"
        case "${provider,,}" in
            vllm|sglang|ollama|mlx_lm|mlx|mlx-lm)
                configure_engine_default_model "$provider" "$model" || true
                ;;
        esac
    fi

    echo
    echo "Selected model installation complete."
}

configure_full_local_model_defaults() {
    local endpoint_id="$1"
    local model="$2"
    local supports_tools="${3:-1}"
    [[ -n "$endpoint_id" && -n "$model" ]] || return 2
    "$VENV_DIR/bin/python" - "$endpoint_id" "$model" "$supports_tools" <<'PY_FULL_DEFAULTS'
import sys
from src.settings import load_settings, save_settings
endpoint_id, model, supports_tools = sys.argv[1:]
s=load_settings()
for prefix in ("default", "research", "utility", "task"):
    s[f"{prefix}_endpoint_id"] = endpoint_id
    s[f"{prefix}_model"] = model
name=model.lower()
if any(x in name for x in ("vision", "vlm", "multimodal", "qwen2-vl", "qwen3-vl", "gemma-3")):
    s["vision_endpoint_id"] = endpoint_id
    s["vision_model"] = model
    s["vision_enabled"] = True
s["search_provider"] = s.get("search_provider") or "searxng"
if not s.get("search_fallback_chain"):
    s["search_fallback_chain"] = ["duckduckgo"]
# Native function/tool schemas are opt-in at the endpoint layer. Zarzysseus's own
# tool permission/denylist remains separate and is deliberately not bypassed.
s["agent_tool_selection"] = "all"
save_settings(s)
print(f"Configured chat/research/utility/task -> {endpoint_id} / {model}")
print(f"Native tool calling: {'enabled' if supports_tools.lower() in ('1','true','yes','on') else 'disabled'}")
print("Web search defaults: SearXNG with DuckDuckGo fallback when available")
print("Tool permissions remain controlled by Zarzysseus's safety layer.")
PY_FULL_DEFAULTS
}

register_openai_compatible_endpoint() {
    local endpoint_id="$1" name="$2" base_url="$3" supports_tools="${4:-1}" preferred_model="${5:-}"
    [[ -n "$endpoint_id" && -n "$name" && -n "$base_url" ]] || return 2
    model_manager_ensure || return 1
    "$VENV_DIR/bin/python" - "$endpoint_id" "$name" "$base_url" "$supports_tools" "$preferred_model" <<'PY_REGISTER_EP'
import json, sys, urllib.request
from datetime import datetime, timezone
endpoint_id, name, base_url, supports_tools, preferred_model = sys.argv[1:]
base_url=base_url.rstrip('/')
models=[]
try:
    req=urllib.request.Request(base_url + '/models', headers={'Accept':'application/json'})
    with urllib.request.urlopen(req, timeout=5) as r:
        data=json.loads(r.read().decode('utf-8'))
    models=[str(x.get('id','')).strip() for x in (data.get('data') or data.get('models') or []) if x.get('id')]
except Exception as e:
    print(f"[warning] Could not probe {base_url}/models: {e}")
from core.database import SessionLocal, ModelEndpoint
from src.settings import load_settings, save_settings
now=datetime.now(timezone.utc)
db=SessionLocal()
try:
    ep=db.query(ModelEndpoint).filter(ModelEndpoint.id==endpoint_id).first()
    tools_on=supports_tools.lower() in ('1','true','yes','on')
    if ep is None:
        ep=ModelEndpoint(id=endpoint_id,name=name,base_url=base_url,api_key="",is_enabled=True,hidden_models="[]",cached_models=json.dumps(models),pinned_models="[]",model_type="llm",endpoint_kind="local",model_refresh_mode="manual",supports_tools=tools_on,created_at=now,updated_at=now)
        db.add(ep)
    else:
        ep.name=name; ep.base_url=base_url; ep.is_enabled=True; ep.hidden_models="[]"; ep.cached_models=json.dumps(models); ep.model_type="llm"; ep.endpoint_kind="local"; ep.model_refresh_mode="manual"; ep.supports_tools=tools_on; ep.updated_at=now
    db.commit()
    chosen=preferred_model if preferred_model in models else (models[0] if models else preferred_model)
    if chosen:
        s=load_settings()
        for prefix in ('default','research','utility','task'):
            s[f'{prefix}_endpoint_id']=endpoint_id
            s[f'{prefix}_model']=chosen
        s['search_provider']=s.get('search_provider') or 'searxng'
        if not s.get('search_fallback_chain'):
            s['search_fallback_chain']=['duckduckgo']
        s['agent_tool_selection']='all'
        save_settings(s)
    print(f"Registered endpoint: {endpoint_id}")
    print(f"Base URL: {base_url}")
    print(f"Models discovered: {len(models)}")
    print(f"Default model: {chosen or 'not discovered'}")
    print(f"Native tool calling: {'enabled' if ep.supports_tools else 'disabled'}")
finally:
    db.close()
PY_REGISTER_EP
}

configure_engine_default_model() {
    local provider="$1" model="$2"
    [[ -n "$model" ]] || { echo "ERROR: No model supplied."; return 2; }
    case "${provider,,}" in
        vllm)
            register_openai_compatible_endpoint "vllm-local" "vLLM (Local)" "$VLLM_ENDPOINT" 1 "$model"
            ;;
        sglang)
            register_openai_compatible_endpoint "sglang-local" "SGLang (Local)" "$SGLANG_ENDPOINT" 1 "$model"
            ;;
        ollama)
            [[ -n "$model" ]] || return 2
            if ! ollama_api_ready; then
                echo "ERROR: Ollama API is not reachable at $OLLAMA_ENDPOINT";
                return 1
            fi
            if ! ollama_has_model "$model"; then
                echo "ERROR: Ollama model '$model' is not installed. Use: $0 opull $model"
                return 1
            fi
            sync_ollama_with_odysseus "$model"
            ;;
        mlx_lm|mlx|mlx-lm)
            if ! mlx_lm_api_ready; then
                echo "ERROR: MLX-LM server is not reachable at $MLX_LM_ENDPOINT"
                echo "       Use: $0 mpull $model"
                return 1
            fi
            register_openai_compatible_endpoint "mlx-lm-local" "MLX-LM (Local)" "$MLX_LM_ENDPOINT" 1 "$model"
            ;;
        *)
            echo "ERROR: Unknown model provider '$provider'. Use vllm, sglang, ollama, or mlx_lm."
            return 2
            ;;
    esac
    mkdir -p "$(dirname "$DEFAULT_MODEL_CONFIGURED_FILE")"
    printf '%s\n' "${provider,,}:$model" > "$DEFAULT_MODEL_CONFIGURED_FILE"
    echo "Default model configured: $model via ${provider,,}"
}

pull_vllm_model() {
    local repo="$1" include_pattern="${2:-}"
    [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]+/[A-Za-z0-9][A-Za-z0-9._-]+$ ]] || { echo "ERROR: vLLM model must be <org/model>."; return 2; }
    application_installed || install_odysseus
    if [[ "$INSTALL_VLLM" != "1" ]]; then
        echo "ERROR: INSTALL_VLLM=0. Enable it before using vpull."
        return 1
    fi
    cd "$PROJECT_DIR"
    source "$VENV_DIR/bin/activate"
    install_llm_serve_engines
    verify_engine_runtime "$VLLM_VENV_DIR" vllm "vLLM" || return 1
    hf_pull_model "$repo" "$include_pattern" || return 1
    configure_engine_default_model vllm "$repo"
    echo "vLLM model cached: $repo"
}

pull_sglang_model() {
    local repo="$1" include_pattern="${2:-}"
    [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]+/[A-Za-z0-9][A-Za-z0-9._-]+$ ]] || { echo "ERROR: SGLang model must be <org/model>."; return 2; }
    application_installed || install_odysseus
    if [[ "$INSTALL_SGLANG" != "1" ]]; then
        echo "ERROR: INSTALL_SGLANG=0. Enable it before using spull."
        return 1
    fi
    cd "$PROJECT_DIR"
    source "$VENV_DIR/bin/activate"
    install_llm_serve_engines
    verify_engine_runtime "$SGLANG_VENV_DIR" sglang "SGLang" || return 1
    hf_pull_model "$repo" "$include_pattern" || return 1
    configure_engine_default_model sglang "$repo"
    echo "SGLang model cached: $repo"
}

mlx_lm_api_ready() {
    command -v curl >/dev/null 2>&1 || return 1
    curl -fsS --max-time 3 "$MLX_LM_ENDPOINT/models" >/dev/null 2>&1
}

mlx_lm_endpoint_port() {
    local endpoint="$MLX_LM_ENDPOINT" hostport
    hostport="${endpoint#*://}"
    hostport="${hostport%%/*}"
    if [[ "$hostport" == *:* ]]; then
        echo "${hostport##*:}"
    else
        echo "$hostport"
    fi
}

mlx_lm_stop_server() {
    if [[ "$SERVICE_MANAGER" == "systemd" ]] && mlx_lm_service_installed; then
        service_systemctl stop "${MLX_LM_SERVICE_NAME}.service" 2>/dev/null || true
    fi
    if [[ -f "$MLX_LM_PID_FILE" ]]; then
        local pid
        pid="$(cat "$MLX_LM_PID_FILE" 2>/dev/null || true)"
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            for _ in {1..20}; do
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.25
            done
            kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$MLX_LM_PID_FILE"
    fi
}

mlx_lm_start_server() {
    local repo="$1"
    [[ -n "$repo" ]] || { echo "ERROR: No MLX-LM model supplied."; return 2; }
    application_installed || install_odysseus
    install_mlx_lm || return 1
    [[ -x "$MLX_LM_VENV_DIR/bin/python" ]] || { echo "ERROR: MLX-LM isolated Python environment is missing."; return 1; }

    mkdir -p "$COOKBOOK_LOCAL_DIR" "$(dirname "$MLX_LM_SERVICE_FILE")"
    mlx_lm_stop_server

    local token
    token="$(get_hf_token | sed '/^$/d' | head -n1 || true)"

    if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
        cat > "$MLX_LM_SERVICE_FILE" <<EOF_MLX_SERVICE
[Unit]
Description=MLX-LM OpenAI-Compatible Server (Zarzysseus)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=-$PROJECT_DIR/.env
Environment=HF_HOME=$HF_HOME
Environment=HF_HUB_CACHE=$MLX_LM_MODEL_DIR
Environment=HF_HUB_DISABLE_XET=$HF_HUB_DISABLE_XET
Environment=HF_HUB_DOWNLOAD_TIMEOUT=$HF_HUB_DOWNLOAD_TIMEOUT
Environment=HF_HUB_ETAG_TIMEOUT=$HF_HUB_ETAG_TIMEOUT
Environment=HF_HUB_DOWNLOAD_MAX_WORKERS=$HF_HUB_DOWNLOAD_MAX_WORKERS
Environment=PYTHONUNBUFFERED=1
ExecStart=$MLX_LM_VENV_DIR/bin/python -m mlx_lm.server --model $repo --host 127.0.0.1 --port $(mlx_lm_endpoint_port)
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF_MLX_SERVICE
        service_systemctl daemon-reload
        service_systemctl enable "${MLX_LM_SERVICE_NAME}.service" >/dev/null 2>&1 || true
        service_systemctl start "${MLX_LM_SERVICE_NAME}.service"
    else
        local port
        port="$(mlx_lm_endpoint_port)"
        export HF_HOME HF_HUB_CACHE="$MLX_LM_MODEL_DIR" HF_HUB_DISABLE_XET HF_HUB_DOWNLOAD_TIMEOUT HF_HUB_ETAG_TIMEOUT HF_HUB_DOWNLOAD_MAX_WORKERS
        [[ -n "$token" ]] && export HF_TOKEN="$token" HUGGING_FACE_HUB_TOKEN="$token"
        nohup "$MLX_LM_VENV_DIR/bin/python" -m mlx_lm.server --model "$repo" --host 127.0.0.1 --port "$port" >>"$MLX_LM_LOG_FILE" 2>&1 &
        echo $! > "$MLX_LM_PID_FILE"
    fi

    printf '%s\n' "$repo" > "$MLX_LM_CURRENT_MODEL_FILE"
    echo "MLX-LM server starting: $repo ($MLX_LM_ENDPOINT)"

    local ready=0
    for _ in {1..60}; do
        if mlx_lm_api_ready; then
            ready=1
            break
        fi
        sleep 1
    done
    if (( ready )); then
        echo "MLX-LM server ready: $repo"
        return 0
    fi
    echo "ERROR: MLX-LM server did not become ready at $MLX_LM_ENDPOINT"
    if [[ "$SERVICE_MANAGER" == "systemd" ]] && mlx_lm_service_installed; then
        service_systemctl status "${MLX_LM_SERVICE_NAME}.service" --no-pager --full 2>&1 | tail -n 30 || true
    elif [[ -f "$MLX_LM_LOG_FILE" ]]; then
        tail -n 40 "$MLX_LM_LOG_FILE" || true
    fi
    return 1
}

pull_mlx_model() {
    local repo="$1" include_pattern="${2:-}"
    [[ "$repo" =~ ^[A-Za-z0-9][A-Za-z0-9._-]+/[A-Za-z0-9][A-Za-z0-9._-]+$ ]] || { echo "ERROR: MLX-LM model must be <org/model>."; return 2; }
    application_installed || install_odysseus
    if [[ "$INSTALL_MLX_LM" != "1" ]]; then
        echo "ERROR: INSTALL_MLX_LM=0. Enable it before using mpull."
        return 1
    fi

    cd "$PROJECT_DIR"
    source "$VENV_DIR/bin/activate"
    install_mlx_lm || return 1

    # MLX-LM uses Hugging Face's cache. Keep its model cache separate from the
    # main vLLM/SGLang cache so the MLX server can scan only its own models.
    local HF_HUB_CACHE="$MLX_LM_MODEL_DIR"
    mkdir -p "$HF_HUB_CACHE"
    hf_pull_model "$repo" "$include_pattern" || return 1

    mlx_lm_start_server "$repo" || return 1
    configure_engine_default_model mlx_lm "$repo"
    echo "MLX-LM model cached: $repo"
}

linux_status() {
    detect_linux_install
    echo "  Kernel:              $(uname -srmo 2>/dev/null || uname -s)"
    echo "  Architecture:       $(uname -m)"
    echo "  /etc/os-release:    ${DISTRO_PRETTY_NAME:-unknown}"
    echo "  Distro family:      ${DISTRO_FAMILY:-unknown}"
    echo "  Package manager:    $PKG (${PKG_COMMAND:-unknown})"
    echo "  Package model:      ${PACKAGE_MODEL:-unknown}"
    echo "  Service manager:    $SERVICE_MANAGER"
    echo
    echo "Zarzysseus installation discovery:"
    installation_discovery_status
    echo
    if [[ -d /opt/rocm ]]; then echo "  ROCm prefix:        /opt/rocm"; elif [[ -d /usr/lib/rocm ]]; then echo "  ROCm prefix:        /usr/lib/rocm"; else echo "  ROCm prefix:        not detected"; fi
    if [[ -n "${PYENV_ROOT:-}" ]]; then echo "  pyenv root:         $PYENV_ROOT"; fi
}

sync_ollama_with_odysseus() {
    local sync_preferred_model="${1:-$OLLAMA_DEFAULT_MODEL}"
    if ! ollama_api_ready; then
        echo "ERROR: Ollama API is not reachable at $OLLAMA_ENDPOINT"
        return 1
    fi

    (
        cd "$PROJECT_DIR"
        "$VENV_DIR/bin/python" - "$PROJECT_DIR" "$OLLAMA_OPENAI_ENDPOINT" "$OLLAMA_SUPPORTS_TOOLS" "$sync_preferred_model" <<'PY'
import json, sys, uuid
from datetime import datetime, timezone
from pathlib import Path

project_dir, endpoint_url, supports_tools, preferred_model = sys.argv[1:]

import urllib.request
raw = urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=5).read()
data = json.loads(raw)
models = [str(m.get("name", "")).strip() for m in data.get("models", []) if m.get("name")]

from core.database import SessionLocal, ModelEndpoint
from src.settings import load_settings, save_settings

db = SessionLocal()
try:
    endpoint = (
        db.query(ModelEndpoint)
        .filter(ModelEndpoint.id == "ollama-local")
        .first()
    )
    now = datetime.now(timezone.utc)
    if endpoint is None:
        endpoint = ModelEndpoint(
            id="ollama-local",
            name="Ollama (Local)",
            base_url=endpoint_url,
            api_key="",
            is_enabled=True,
            hidden_models="[]",
            cached_models=json.dumps(models),
            pinned_models="[]",
            model_type="llm",
            endpoint_kind="local",
            model_refresh_mode="manual",
            supports_tools=(supports_tools.lower() in ("1", "true", "yes", "on")),
            created_at=now,
            updated_at=now,
        )
        db.add(endpoint)
    else:
        endpoint.name = "Ollama (Local)"
        endpoint.base_url = endpoint_url
        endpoint.is_enabled = True
        # Reconcile the live Ollama inventory. A model that is really present
        # in Ollama must not remain hidden/stale in Zarzysseus.
        endpoint.hidden_models = "[]"
        endpoint.cached_models = json.dumps(models)
        endpoint.model_type = "llm"
        endpoint.endpoint_kind = "local"
        endpoint.model_refresh_mode = "manual"
        endpoint.supports_tools = supports_tools.lower() in ("1", "true", "yes", "on")
        endpoint.updated_at = now
    db.commit()

    settings = load_settings()
    current_default = str(settings.get("default_model") or "").strip()
    if current_default in models:
        chosen = current_default
    elif preferred_model in models:
        chosen = preferred_model
    else:
        chosen = models[0] if models else ""
    settings["default_endpoint_id"] = endpoint.id
    if chosen:
        settings["default_model"] = chosen
    save_settings(settings)

    # Keep a content hash so the background sync timer can restart Zarzysseus
    # only when Ollama's model inventory actually changed.
    state_path = Path(project_dir) / "data" / "local" / "ollama-models.sha256"
    state_path.parent.mkdir(parents=True, exist_ok=True)
    import hashlib
    digest = hashlib.sha256("\n".join(models).encode("utf-8")).hexdigest()
    previous = state_path.read_text(encoding="utf-8").strip() if state_path.exists() else ""
    state_path.write_text(digest + "\n", encoding="utf-8")
    changed = digest != previous

    print(f"Ollama endpoint synced: {endpoint_url}")
    print(f"Ollama models discovered: {len(models)}")
    if chosen:
        print(f"Zarzysseus default LLM: {chosen}")
    else:
        print("Zarzysseus default LLM: not set (Ollama has no models yet)")
    print(f"Ollama native tool calling: {'enabled' if endpoint.supports_tools else 'disabled'}")
    print(f"Ollama model inventory changed: {'yes' if changed else 'no'}")
finally:
    db.close()
PY
    )
}

installation_complete() {
    application_installed && \
    ollama_binary_installed && \
    test_playwright_installed && \
    test_sam_mask_installed && \
    { [[ "$SERVICE_MANAGER" != "systemd" ]] || { service_installed && ollama_service_installed; }; }
}

print_status() {
    echo "=========================================="
    echo "Zarzysseus installation status"
    echo "=========================================="

    # Status is intentionally read-only: detect hardware/runtime state but do not
    # install drivers, ROCm, CUDA, or Python packages.
    accelerator_status
    echo ""

    if repo_installed; then
        echo "Repository:        INSTALLED ($PROJECT_DIR)"
    else
        echo "Repository:        NOT INSTALLED ($PROJECT_DIR)"
    fi

    if venv_installed; then
        echo "Virtual environment: INSTALLED ($VENV_DIR)"
        echo "Python:             $($VENV_DIR/bin/python --version 2>&1 || true)"
    else
        echo "Virtual environment: NOT INSTALLED ($VENV_DIR)"
    fi

    if service_installed; then
        echo "Startup service:    INSTALLED ($SERVICE_FILE)"
    else
        echo "Startup service:    NOT INSTALLED ($SERVICE_FILE)"
    fi

    if command -v systemctl >/dev/null 2>&1 && service_installed; then
        echo "Startup enabled:    $(service_systemctl is-enabled "$service_unit" 2>/dev/null || echo no)"
        echo "Service state:      $(service_systemctl is-active "$service_unit" 2>/dev/null || echo inactive)"
    else
        echo "Startup enabled:    unknown"
        echo "Service state:      unknown"
    fi

    echo ""
    if ollama_binary_installed; then
        echo "Ollama:              INSTALLED ($(command -v ollama))"
    else
        echo "Ollama:              NOT INSTALLED"
    fi
    if ollama_service_installed; then
        echo "Ollama startup:      INSTALLED ($OLLAMA_SERVICE_FILE)"
        echo "Ollama enabled:      $(systemctl --user is-enabled "${OLLAMA_SERVICE_NAME}.service" 2>/dev/null || echo no)"
        echo "Ollama state:        $(systemctl --user is-active "${OLLAMA_SERVICE_NAME}.service" 2>/dev/null || echo inactive)"
    else
        echo "Ollama startup:      NOT INSTALLED"
    fi
    if [[ -f "$OLLAMA_SYNC_TIMER_FILE" ]]; then
        echo "Ollama model sync:   $(systemctl --user is-active "${OLLAMA_SYNC_SERVICE_NAME}.timer" 2>/dev/null || echo inactive)"
    else
        echo "Ollama model sync:   NOT INSTALLED"
    fi
    if ollama_api_ready; then
        echo "Ollama API:          ONLINE ($OLLAMA_ENDPOINT)"
        if venv_installed && [[ -f "$PROJECT_DIR/core/database.py" ]]; then
            "$VENV_DIR/bin/python" - "$PROJECT_DIR" <<'PY' 2>/dev/null || true
from src.settings import load_settings
s = load_settings()
print("Ollama LLM endpoint: " + str(s.get("default_endpoint_id", "") or "not set"))
print("Ollama default model: " + str(s.get("default_model", "") or "not set"))
PY
        fi
    else
        echo "Ollama API:          OFFLINE ($OLLAMA_ENDPOINT)"
    fi

    echo ""
    if test_playwright_installed; then
        echo "Playwright MCP:     INSTALLED"
    else
        echo "Playwright MCP:     NOT INSTALLED"
    fi
    if [[ -d "$PLAYWRIGHT_BROWSERS_DIR" ]]; then
        echo "Playwright browsers: INSTALLED ($PLAYWRIGHT_BROWSERS_DIR)"
    else
        echo "Playwright browsers: NOT INSTALLED"
    fi
    if test_sam_mask_installed; then
        echo "SAM mask stack:     INSTALLED"
    elif sam_mask_dependencies_ready; then
        echo "SAM mask stack:     PARTIAL (checkpoint missing/incomplete)"
    else
        echo "SAM mask stack:     NOT READY"
    fi
    echo "SAM checkpoint:     $SAM_CHECKPOINT"
    if test_engine_installed "vLLM" "$VLLM_VENV_DIR" "vllm" "vllm"; then
        echo "vLLM runtime:       INSTALLED ($VLLM_VENV_DIR)"
    else
        echo "vLLM runtime:       NOT READY"
    fi
    if test_engine_installed "SGLang" "$SGLANG_VENV_DIR" "sglang" "sglang"; then
        echo "SGLang runtime:     INSTALLED ($SGLANG_VENV_DIR)"
    else
        echo "SGLang runtime:     NOT READY"
    fi
    if [[ -x "$MLX_LM_VENV_DIR/bin/python" ]] && "$MLX_LM_VENV_DIR/bin/python" -c 'import mlx,mlx_lm' >/dev/null 2>&1; then
        echo "MLX-LM runtime:     INSTALLED ($MLX_LM_VENV_DIR)"
    else
        echo "MLX-LM runtime:     NOT READY / SKIPPED"
    fi
    if mlx_lm_service_installed; then
        echo "MLX-LM server:      INSTALLED ($MLX_LM_SERVICE_FILE)"
        if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
            echo "MLX-LM enabled:     $(service_systemctl is-enabled "${MLX_LM_SERVICE_NAME}.service" 2>/dev/null || echo no)"
            echo "MLX-LM state:       $(service_systemctl is-active "${MLX_LM_SERVICE_NAME}.service" 2>/dev/null || echo inactive)"
        fi
        echo "MLX-LM API:         $(mlx_lm_api_ready && echo ONLINE || echo OFFLINE) ($MLX_LM_ENDPOINT)"
        [[ -f "$MLX_LM_CURRENT_MODEL_FILE" ]] && echo "MLX-LM model:       $(cat "$MLX_LM_CURRENT_MODEL_FILE")"
    else
        echo "MLX-LM server:      NOT INSTALLED"
    fi
    echo ""
    if installation_complete; then
        echo "Overall:            INSTALLED"
    else
        echo "Overall:            NOT FULLY INSTALLED"
    fi
    show_link
    echo "=========================================="
}

# ------------------------------------------
# Ollama service management
# ------------------------------------------

install_ollama_service() {
    require_systemctl
    local ollama_bin
    ollama_bin="$(command -v ollama 2>/dev/null || true)"
    [[ -n "$ollama_bin" ]] || { echo "ERROR: Ollama binary not found."; return 1; }

    mkdir -p "$(dirname "$OLLAMA_SERVICE_FILE")"
    cat > "$OLLAMA_SERVICE_FILE" <<EOF_OLLAMA
[Unit]
Description=Ollama AI Server (Zarzysseus)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=$ollama_bin serve
Environment=OLLAMA_HOST=127.0.0.1:11434
Environment=OLLAMA_MODELS=$HOME/.ollama/models
Environment=OLLAMA_MAX_LOADED_MODELS=$OLLAMA_MAX_LOADED_MODELS
Environment=OLLAMA_CONTEXT_LENGTH=$OLLAMA_CONTEXT_LENGTH
Environment=OLLAMA_VULKAN=1
Environment=OLLAMA_ORIGINS=http://localhost,http://127.0.0.1
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF_OLLAMA

    service_systemctl daemon-reload

    if systemctl is-active --quiet ollama.service 2>/dev/null; then
        echo "    [note] Existing system-level Ollama service is already active; not starting a second Ollama server."
        return 0
    fi

    if command -v loginctl >/dev/null 2>&1; then
        loginctl enable-linger "$USER" >/dev/null 2>&1 || $SUDO loginctl enable-linger "$USER" >/dev/null 2>&1 || true
    fi

    service_systemctl enable "${OLLAMA_SERVICE_NAME}.service"
    ensure_ollama_sync_timer
    if ollama_api_ready; then
        echo "    [installed] Ollama startup service (${OLLAMA_SERVICE_NAME}); existing Ollama server detected, so it was not started again."
    else
        service_systemctl start "${OLLAMA_SERVICE_NAME}.service"
        echo "    [installed] Ollama startup service (${OLLAMA_SERVICE_NAME})"
    fi
}

install_ollama_sync_timer() {
    require_systemctl
    [[ -x "$VENV_DIR/bin/python" ]] || { echo "ERROR: Zarzysseus virtual environment is not ready for Ollama sync."; return 1; }
    mkdir -p "$(dirname "$OLLAMA_SYNC_SERVICE_FILE")"
    cat > "$OLLAMA_SYNC_SERVICE_FILE" <<EOF_OLLAMA_SYNC
[Unit]
Description=Synchronize Ollama models with Zarzysseus
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=$PROJECT_DIR
ExecStart=$SCRIPT_PATH ollama-sync
EOF_OLLAMA_SYNC

    cat > "$OLLAMA_SYNC_TIMER_FILE" <<EOF_OLLAMA_TIMER
[Unit]
Description=Keep Zarzysseus Ollama model inventory synchronized

[Timer]
OnBootSec=30s
OnUnitActiveSec=60s
Persistent=true
Unit=${OLLAMA_SYNC_SERVICE_NAME}.service

[Install]
WantedBy=timers.target
EOF_OLLAMA_TIMER

    service_systemctl daemon-reload
    service_systemctl enable --now "${OLLAMA_SYNC_SERVICE_NAME}.timer"
    installed "Ollama/Zarzysseus model sync timer (every 60s)"
}

uninstall_ollama_sync_timer() {
    require_systemctl
    service_systemctl disable --now "${OLLAMA_SYNC_SERVICE_NAME}.timer" 2>/dev/null || true
    rm -f "$OLLAMA_SYNC_TIMER_FILE" "$OLLAMA_SYNC_SERVICE_FILE"
    service_systemctl daemon-reload
    echo "Ollama/Zarzysseus model sync timer removed."
}

ensure_ollama_sync_timer() {
    # Non-systemd Linux installations can still use Ollama manually; the
    # background synchronization timer is only available with systemd.
    [[ "${SERVICE_MANAGER:-unknown}" == "systemd" ]] || return 0
    require_systemctl
    if [[ -x "$VENV_DIR/bin/python" ]]; then
        if [[ ! -f "$OLLAMA_SYNC_TIMER_FILE" ]]; then
            install_ollama_sync_timer
        else
            service_systemctl enable --now "${OLLAMA_SYNC_SERVICE_NAME}.timer"
        fi
    fi
}

ollama_enable() {
    require_systemctl
    if ! ollama_service_installed; then
        echo "Ollama startup service is not installed."
        return 1
    fi
    service_systemctl enable "${OLLAMA_SERVICE_NAME}.service"
    ensure_ollama_sync_timer
    if ollama_api_ready; then
        echo "Ollama API is already online; startup service enabled without starting a second server."
    else
        service_systemctl start "${OLLAMA_SERVICE_NAME}.service"
        echo "Ollama startup service enabled and started."
    fi
}

ollama_disable() {
    require_systemctl
    if ! ollama_service_installed; then
        echo "Ollama startup service is not installed. Nothing to disable."
        return 0
    fi
    service_systemctl disable --now "${OLLAMA_SERVICE_NAME}.service" 2>/dev/null || true
    if [[ -f "$OLLAMA_SYNC_TIMER_FILE" ]]; then
        service_systemctl disable --now "${OLLAMA_SYNC_SERVICE_NAME}.timer" 2>/dev/null || true
    fi
    echo "Ollama startup service disabled and stopped."
}

ollama_start() {
    require_systemctl
    if ! ollama_service_installed; then
        echo "ERROR: Ollama startup service is not installed."
        return 1
    fi
    ensure_ollama_sync_timer
    if ollama_api_ready; then
        echo "Ollama is already running at $OLLAMA_ENDPOINT."
        return 0
    fi
    service_systemctl start "${OLLAMA_SERVICE_NAME}.service"
    echo "Ollama started."
}

ollama_stop() {
    require_systemctl
    if ! ollama_service_installed; then
        echo "Ollama startup service is not installed. Nothing to stop."
        return 0
    fi
    service_systemctl stop "${OLLAMA_SERVICE_NAME}.service" 2>/dev/null || true
    echo "Ollama stopped."
}

ollama_restart() {
    require_systemctl
    if ! ollama_service_installed; then
        echo "ERROR: Ollama startup service is not installed."
        return 1
    fi
    ensure_ollama_sync_timer
    service_systemctl restart "${OLLAMA_SERVICE_NAME}.service"
    echo "Ollama restarted."
}

ollama_uninstall_service() {
    require_systemctl
    if ! ollama_service_installed; then
        echo "Ollama startup service is already not installed."
        return 0
    fi
    service_systemctl disable --now "${OLLAMA_SERVICE_NAME}.service" 2>/dev/null || true
    rm -f "$OLLAMA_SERVICE_FILE"
    service_systemctl daemon-reload
    echo "Ollama startup service removed."
}

# ------------------------------------------
# Service management
# ------------------------------------------

require_systemctl() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "ERROR: systemctl is required for service management."
        exit 1
    fi
}

service_enable() {
    require_systemctl
    service_systemctl daemon-reload

    if ollama_service_installed; then
        ollama_enable
        if [[ -f "$VENV_DIR/bin/python" ]]; then
            if [[ ! -f "$OLLAMA_SYNC_TIMER_FILE" ]]; then
                install_ollama_sync_timer
            else
                service_systemctl enable --now "${OLLAMA_SYNC_SERVICE_NAME}.timer"
            fi
        fi
    fi

    if command -v loginctl >/dev/null 2>&1; then
        if loginctl enable-linger "$USER" >/dev/null 2>&1 || $SUDO loginctl enable-linger "$USER" >/dev/null 2>&1; then
            echo "    [configured] user lingering enabled for startup"
        else
            echo "    [note] Could not enable user lingering automatically."
            echo "           The service will still start when your user session starts."
        fi
    fi

    service_systemctl enable --now "$service_unit"
    echo "Zarzysseus startup service enabled and started."
    show_link
}

service_disable() {
    require_systemctl
    if ! service_installed; then
        echo "Zarzysseus startup service is not installed. Nothing to disable."
        return 0
    fi
    service_systemctl disable --now "$service_unit" 2>/dev/null || true
    if ollama_service_installed; then ollama_disable; elif [[ -f "$OLLAMA_SYNC_TIMER_FILE" ]]; then service_systemctl disable --now "${OLLAMA_SYNC_SERVICE_NAME}.timer" 2>/dev/null || true; fi
    echo "Zarzysseus startup service disabled and stopped."
    show_link
}

service_start() {
    require_systemctl
    if ! service_installed; then
        echo "ERROR: Zarzysseus startup service is not installed."
        exit 1
    fi
    if ollama_service_installed; then ollama_start; fi
    service_systemctl start "$service_unit"
    echo "Zarzysseus started."
    show_link
}

service_stop() {
    require_systemctl
    if ! service_installed; then
        echo "Zarzysseus startup service is not installed. Nothing to stop."
        return 0
    fi
    service_systemctl stop "$service_unit" 2>/dev/null || true
    if ollama_service_installed; then ollama_stop; fi
    echo "Zarzysseus stopped."
    show_link
}

service_restart() {
    require_systemctl
    if ! service_installed; then
        echo "ERROR: Zarzysseus startup service is not installed."
        exit 1
    fi
    if ollama_service_installed; then ollama_restart; fi
    service_systemctl restart "$service_unit"
    echo "Zarzysseus restarted."
    show_link
}

service_uninstall() {
    require_systemctl
    if ! service_installed; then
        echo "Zarzysseus startup service is already not installed."
        return 0
    fi

    service_systemctl disable --now "$service_unit" 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    if mlx_lm_service_installed; then
        service_systemctl disable --now "${MLX_LM_SERVICE_NAME}.service" 2>/dev/null || true
        rm -f "$MLX_LM_SERVICE_FILE"
    fi
    if [[ -f "$OLLAMA_SYNC_TIMER_FILE" || -f "$OLLAMA_SYNC_SERVICE_FILE" ]]; then uninstall_ollama_sync_timer; fi
    if ollama_service_installed; then ollama_uninstall_service; fi
    service_systemctl daemon-reload
    echo "Zarzysseus startup service removed."
    show_link
}

uninstall_odysseus() {
    # Full Zarzysseus uninstall: remove the project tree and all user services
    # created by this installer. Leave shared system dependencies and the
    # standalone Ollama installation/models untouched.
    if [[ "${ODYSSEUS_UNINSTALL_CONFIRMED:-0}" != "1" ]]; then
        echo "WARNING: This will remove the entire Zarzysseus project at:"
        echo "  $PROJECT_DIR"
        echo
        echo "It will also remove the Zarzysseus, MLX-LM, Ollama integration, and"
        echo "Ollama↔Zarzysseus sync user services created by this installer."
        echo
        echo "It will NOT remove ROCm/CUDA system packages, pyenv, tmux, yay,"
        echo "or the standalone Ollama binary/models."
        echo
        read -r -p "Type UNINSTALL to continue: " confirm
        [[ "$confirm" == "UNINSTALL" ]] || {
            echo "Uninstall cancelled."
            return 0
        }
    fi

    if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
        service_systemctl disable --now "$service_unit" 2>/dev/null || true
        service_systemctl disable --now "${MLX_LM_SERVICE_NAME}.service" 2>/dev/null || true
        service_systemctl disable --now "${OLLAMA_SERVICE_NAME}.service" 2>/dev/null || true
        service_systemctl disable --now "${OLLAMA_SYNC_SERVICE_NAME}.timer" 2>/dev/null || true
        service_systemctl disable --now "${OLLAMA_SYNC_SERVICE_NAME}.service" 2>/dev/null || true

        rm -f \
            "$SERVICE_FILE" \
            "$MLX_LM_SERVICE_FILE" \
            "$OLLAMA_SERVICE_FILE" \
            "$OLLAMA_SYNC_TIMER_FILE" \
            "$OLLAMA_SYNC_SERVICE_FILE"
        service_systemctl daemon-reload 2>/dev/null || true
        echo "    [removed] Zarzysseus-related user services"
    else
        echo "    [skipped] systemd user services (no systemd detected)"
    fi

    if [[ -d "$PROJECT_DIR" || -f "$PROJECT_DIR" ]]; then
        echo "    [removing] $PROJECT_DIR"
        rm -rf -- "$PROJECT_DIR"
    else
        echo "    [already absent] $PROJECT_DIR"
    fi

    echo
    echo "=========================================="
    echo "Zarzysseus uninstall complete."
    echo "=========================================="
}

# ------------------------------------------
# System dependency helpers
# ------------------------------------------

if (( EUID == 0 )); then
    # Root does not need a privilege wrapper.  Keeping SUDO empty lets all of
    # the package-manager helpers work on minimal/root-only distributions too.
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
elif command -v doas >/dev/null 2>&1; then
    SUDO="doas"
else
    echo "ERROR: Root privileges are required for system package operations."
    echo "Install sudo/doas, or rerun this installer as root."
    exit 1
fi

detect_linux_install() {
    DISTRO_ID="unknown"
    DISTRO_PRETTY_NAME="unknown"
    DISTRO_VERSION_ID="unknown"
    DISTRO_VERSION_CODENAME=""
    DISTRO_ID_LIKE=""
    DISTRO_FAMILY="unknown"
    PKG="unknown"
    PKG_COMMAND="unknown"
    PACKAGE_MODEL="mutable"

    # /etc/os-release is the cross-distribution standard.  Fall back to the
    # older lsb_release command or release files only when a distro omits it.
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_PRETTY_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
        DISTRO_VERSION_ID="${VERSION_ID:-unknown}"
        DISTRO_VERSION_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
        DISTRO_ID_LIKE="${ID_LIKE:-}"
    elif command -v lsb_release >/dev/null 2>&1; then
        DISTRO_ID="$(lsb_release -si 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr ' ' '_' || echo unknown)"
        DISTRO_PRETTY_NAME="$(lsb_release -sd 2>/dev/null | sed 's/^\"//;s/\"$//' || echo Linux)"
        DISTRO_VERSION_ID="$(lsb_release -sr 2>/dev/null || echo unknown)"
        DISTRO_VERSION_CODENAME="$(lsb_release -sc 2>/dev/null || true)"
    elif [[ -r /etc/redhat-release ]]; then
        DISTRO_ID="rhel-like"
        DISTRO_PRETTY_NAME="$(cat /etc/redhat-release)"
        DISTRO_FAMILY="fedora"
    elif [[ -r /etc/arch-release ]]; then
        DISTRO_ID="arch"
        DISTRO_PRETTY_NAME="Arch Linux"
        DISTRO_FAMILY="arch"
    elif [[ -r /etc/debian_version ]]; then
        DISTRO_ID="debian"
        DISTRO_PRETTY_NAME="Debian-like Linux"
        DISTRO_VERSION_ID="$(cat /etc/debian_version)"
        DISTRO_FAMILY="debian"
    fi

    if [[ "$DISTRO_FAMILY" == "unknown" ]]; then
        case "${DISTRO_ID_LIKE,,} ${DISTRO_ID,,}" in
            *arch*|*manjaro*|*cachyos*|*endeavouros*|*garuda*) DISTRO_FAMILY="arch" ;;
            *debian*|*ubuntu*|*mint*|*pop*|*kali*|*mx*) DISTRO_FAMILY="debian" ;;
            *fedora*|*rhel*|*centos*|*rocky*|*alma*|*amzn*|*oracle*|*nobara*) DISTRO_FAMILY="fedora" ;;
            *suse*|*opensuse*) DISTRO_FAMILY="suse" ;;
            *alpine*) DISTRO_FAMILY="alpine" ;;
            *void*) DISTRO_FAMILY="void" ;;
            *gentoo*|*funtoo*) DISTRO_FAMILY="gentoo" ;;
            *solus*) DISTRO_FAMILY="solus" ;;
            *clear-linux*|*clear_linux*|*clearlinux*) DISTRO_FAMILY="clearlinux" ;;
            *mageia*|*openmandriva*) DISTRO_FAMILY="mandriva" ;;
            *slackware*) DISTRO_FAMILY="slackware" ;;
            *nixos*) DISTRO_FAMILY="nixos" ;;
            *guix*) DISTRO_FAMILY="guix" ;;
            *photon*) DISTRO_FAMILY="photon" ;;
            *) DISTRO_FAMILY="${DISTRO_ID,,}" ;;
        esac
    fi

    # Detect by actual package-manager capability rather than distro name.
    # This makes derivatives work automatically and also covers distributions
    # whose ID is unfamiliar to the installer.
    if [[ -e /run/ostree-booted ]] && command -v rpm-ostree >/dev/null 2>&1; then
        PKG="rpm-ostree"; PKG_COMMAND="rpm-ostree"; PACKAGE_MODEL="immutable"
    elif command -v pacman >/dev/null 2>&1; then
        PKG="pacman"; PKG_COMMAND="pacman"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG="apt"; PKG_COMMAND="apt-get"
    elif command -v dnf5 >/dev/null 2>&1; then
        PKG="dnf5"; PKG_COMMAND="dnf5"
    elif command -v dnf >/dev/null 2>&1; then
        PKG="dnf"; PKG_COMMAND="dnf"
    elif command -v microdnf >/dev/null 2>&1; then
        PKG="microdnf"; PKG_COMMAND="microdnf"
    elif command -v yum >/dev/null 2>&1; then
        PKG="yum"; PKG_COMMAND="yum"
    elif command -v zypper >/dev/null 2>&1; then
        PKG="zypper"; PKG_COMMAND="zypper"
    elif command -v apk >/dev/null 2>&1; then
        PKG="apk"; PKG_COMMAND="apk"
    elif command -v xbps-install >/dev/null 2>&1; then
        PKG="xbps"; PKG_COMMAND="xbps-install"
    elif command -v emerge >/dev/null 2>&1; then
        PKG="emerge"; PKG_COMMAND="emerge"
    elif command -v eopkg >/dev/null 2>&1; then
        PKG="eopkg"; PKG_COMMAND="eopkg"
    elif command -v swupd >/dev/null 2>&1; then
        PKG="swupd"; PKG_COMMAND="swupd"
    elif command -v urpmi >/dev/null 2>&1; then
        PKG="urpmi"; PKG_COMMAND="urpmi"
    elif command -v tdnf >/dev/null 2>&1; then
        PKG="tdnf"; PKG_COMMAND="tdnf"
    elif command -v slackpkg >/dev/null 2>&1; then
        PKG="slackpkg"; PKG_COMMAND="slackpkg"
    elif [[ "${DISTRO_ID,,}" == "nixos" ]] && command -v nix >/dev/null 2>&1; then
        PKG="nix"; PKG_COMMAND="nix"; PACKAGE_MODEL="declarative"
    elif command -v guix >/dev/null 2>&1; then
        PKG="guix"; PKG_COMMAND="guix"; PACKAGE_MODEL="declarative"
    else
        PKG="unknown"; PKG_COMMAND="unknown"
    fi

    if command -v systemctl >/dev/null 2>&1; then
        SERVICE_MANAGER="systemd"
    elif command -v rc-service >/dev/null 2>&1; then
        SERVICE_MANAGER="openrc"
    elif command -v sv >/dev/null 2>&1; then
        SERVICE_MANAGER="runit"
    elif command -v s6-svc >/dev/null 2>&1; then
        SERVICE_MANAGER="s6"
    else
        SERVICE_MANAGER="unknown"
    fi

    if (( ! TUI_MODE )) && [[ "$TUI_CHILD" != "1" ]]; then
        echo "    Linux distribution: $DISTRO_PRETTY_NAME"
        echo "    Distribution family: $DISTRO_FAMILY"
        echo "    Package manager:     $PKG"
        echo "    Package model:       $PACKAGE_MODEL"
        echo "    Service manager:     $SERVICE_MANAGER"
    fi

    if [[ "$PKG" == "unknown" && ( "$ACTION" == "install" || "$ACTION" == "start" || "$ACTION" == "enable" || "$ACTION" == "restart" ) ]]; then
        echo "ERROR: Could not detect a supported Linux package manager."
        echo "Supported ecosystems include Arch/pacman, Debian/apt, Fedora/RHEL dnf/dnf5/yum/microdnf,"
        echo "openSUSE/zypper, Alpine/apk, Void/xbps, Gentoo/emerge, Solus/eopkg, Clear Linux/swupd,"
        echo "Mageia/urpmi, Photon/tdnf, Slackware/slackpkg, NixOS/nix, Guix, and rpm-ostree systems."
        echo "The installer keys off the package manager itself, so derivatives are included automatically."
        exit 1
    fi
}

detect_linux_install

system_update_stamp_file() {
    local distro="${DISTRO_ID:-unknown}" pkg="${PKG:-unknown}"
    printf '%s/system-update.%s.%s.stamp\n' "$SYSTEM_UPDATE_STAMP_DIR" "${distro//[^A-Za-z0-9_.-]/_}" "${pkg//[^A-Za-z0-9_.-]/_}"
}

system_update_is_fresh() {
    [[ "$SYSTEM_UPDATE_FORCE" != "1" ]] || return 1
    [[ "$SYSTEM_UPDATE_TTL" =~ ^[0-9]+$ ]] || return 1
    (( SYSTEM_UPDATE_TTL > 0 )) || return 1
    local stamp now mtime age
    stamp="$(system_update_stamp_file)"
    [[ -f "$stamp" ]] || return 1
    now="$(date +%s)"
    mtime="$(stat -c %Y "$stamp" 2>/dev/null || echo 0)"
    [[ "$mtime" =~ ^[0-9]+$ ]] || return 1
    age=$(( now - mtime ))
    (( age >= 0 && age < SYSTEM_UPDATE_TTL ))
}

system_update_once() {
    (( SYSTEM_UPDATE_DONE_THIS_RUN == 0 )) || return 0
    [[ "$SYSTEM_AUTO_UPDATE" == "1" ]] || {
        echo "    [skipped] Automatic system update disabled (SYSTEM_AUTO_UPDATE=$SYSTEM_AUTO_UPDATE)"
        SYSTEM_UPDATE_DONE_THIS_RUN=1
        return 0
    }

    detect_linux_install
    if [[ "$PKG" == "unknown" ]]; then
        echo "ERROR: Cannot update the system because no supported package manager was detected."
        return 1
    fi

    if system_update_is_fresh; then
        local stamp age_minutes
        stamp="$(system_update_stamp_file)"
        age_minutes=$(( ($(date +%s) - $(stat -c %Y "$stamp" 2>/dev/null || echo 0)) / 60 ))
        echo "    [ready] System update already completed ${age_minutes} minute(s) ago; skipping duplicate update."
        SYSTEM_UPDATE_DONE_THIS_RUN=1
        return 0
    fi

    info "Updating ${DISTRO_PRETTY_NAME:-Linux} before Zarzysseus changes..."
    echo "    Package manager: $PKG"

    local rc=0
    set +e
    case "$PKG" in
        pacman)
            $SUDO pacman -Syu --noconfirm
            rc=$?
            ;;
        apt)
            $SUDO apt-get update && $SUDO env DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
            rc=$?
            ;;
        dnf)
            $SUDO dnf upgrade --refresh -y
            rc=$?
            ;;
        dnf5)
            $SUDO dnf5 upgrade --refresh -y
            rc=$?
            ;;
        microdnf)
            $SUDO microdnf upgrade -y
            rc=$?
            ;;
        yum)
            $SUDO yum update -y
            rc=$?
            ;;
        zypper)
            $SUDO zypper --non-interactive refresh && $SUDO zypper --non-interactive update
            rc=$?
            ;;
        apk)
            $SUDO apk update && $SUDO apk upgrade
            rc=$?
            ;;
        xbps)
            $SUDO xbps-install -Syu
            rc=$?
            ;;
        emerge)
            $SUDO emerge --sync && $SUDO emerge --update --deep --newuse @world
            rc=$?
            ;;
        eopkg)
            $SUDO eopkg update-repo && $SUDO eopkg upgrade -y
            rc=$?
            ;;
        swupd)
            $SUDO swupd update
            rc=$?
            ;;
        urpmi)
            $SUDO urpmi.update -a && $SUDO urpmi --auto-select --auto
            rc=$?
            ;;
        tdnf)
            $SUDO tdnf makecache && $SUDO tdnf upgrade -y
            rc=$?
            ;;
        slackpkg)
            $SUDO slackpkg -batch=on -default_answer=y update && \
            $SUDO slackpkg -batch=on -default_answer=y upgrade-all
            rc=$?
            ;;
        nix)
            if command -v nixos-rebuild >/dev/null 2>&1; then
                $SUDO nixos-rebuild switch --upgrade
            else
                nix-channel --update && nix-env -u '*'
            fi
            rc=$?
            ;;
        guix)
            guix pull
            rc=$?
            if (( rc == 0 )); then
                if [[ -r /etc/config.scm ]] && command -v guix >/dev/null 2>&1; then
                    $SUDO guix system reconfigure /etc/config.scm
                    rc=$?
                else
                    guix package -u
                    rc=$?
                fi
            fi
            ;;
        rpm-ostree)
            $SUDO rpm-ostree upgrade
            rc=$?
            ;;
        *)
            rc=1
            ;;
    esac
    set -e

    if (( rc != 0 )); then
        echo "    [warning] System update exited with status $rc."
        if [[ "$SYSTEM_UPDATE_STRICT" == "1" ]]; then
            echo "ERROR: Stopping before Zarzysseus makes system/project changes."
            return "$rc"
        fi
        echo "    [warning] SYSTEM_UPDATE_STRICT=0, continuing despite the update failure."
        SYSTEM_UPDATE_DONE_THIS_RUN=1
        return 0
    fi

    mkdir -p "$SYSTEM_UPDATE_STAMP_DIR"
    : > "$(system_update_stamp_file)"
    SYSTEM_UPDATE_DONE_THIS_RUN=1
    echo "    [ready] System update completed."
}

bootstrap_action_needs_system_update() {
    # A manual full-stack batch must have explicitly selected at least one NORMAL
    # model. L.P.S. / Desert Ant selections keep their independent lightweight
    # installation paths and browsing never runs the system updater.
    if [[ "$ACTION" == install-manual-batch ]]; then
        [[ "${MANUAL_BATCH_UPDATE_REQUIRED:-0}" == 1 ]]
        return $?
    fi
    # Automatic full-system upgrades are intentionally limited to Zarzysseus
    # installation/update flows. Model pulls, skills, service controls,
    # accelerator repair, MLX/SAM setup, and other maintenance actions must
    # never trigger an OS upgrade just because they were launched.
    # `system-update` remains available as an explicit user-requested action.
    case "$ACTION" in
        install|install-full|install-auto-fit|install-lps|install-personal-faves|install-personal-skills|system-update)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

bootstrap_system_update_for_action() {
    [[ "$ACTION" != "tui" ]] || return 0
    bootstrap_action_needs_system_update || return 0
    # An explicit `system-update` command means "run it now", not "honor the
    # automatic-update TTL". Automatic install preflights still use the cache.
    [[ "$ACTION" == "system-update" ]] && SYSTEM_UPDATE_FORCE=1
    system_update_once
}

pkg_installed() {
    local pkg="$1"
    case "$PKG" in
        pacman) pacman -Q "$pkg" >/dev/null 2>&1 ;;
        apt) dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' ;;
        dnf|dnf5|microdnf|yum|zypper|urpmi|tdnf|rpm-ostree) rpm -q "$pkg" >/dev/null 2>&1 ;;
        apk) apk info -e "$pkg" >/dev/null 2>&1 ;;
        xbps) xbps-query -l "$pkg" 2>/dev/null | grep -q "^ii $pkg-" ;;
        eopkg) eopkg list-installed 2>/dev/null | awk '{print $1}' | grep -Fxq "$pkg" ;;
        slackpkg) compgen -G "/var/log/packages/${pkg}-*" >/dev/null 2>&1 ;;
        guix) guix package -I 2>/dev/null | awk '{print $1}' | grep -Fxq "$pkg" ;;
        nix) nix profile list 2>/dev/null | grep -Eq "(^|[[:space:]])${pkg}([[:space:]]|$)" ;;
        swupd) swupd bundle-list 2>/dev/null | grep -Fxq "$pkg" ;;
        emerge)
            if command -v portageq >/dev/null 2>&1; then
                portageq has_version / "$pkg" >/dev/null 2>&1
            elif command -v qlist >/dev/null 2>&1; then
                qlist -IC "$pkg" >/dev/null 2>&1
            else
                return 1
            fi
            ;;
        *) return 1 ;;
    esac
}

install_missing_packages() {
    local packages=()
    local pkg

    for pkg in "$@"; do
        if pkg_installed "$pkg"; then
            installed "$pkg"
        else
            installing "$pkg"
            packages+=("$pkg")
        fi
    done

    [[ ${#packages[@]} -eq 0 ]] && return 0

    case "$PKG" in
        pacman) $SUDO pacman -S --needed --noconfirm "${packages[@]}" ;;
        apt) $SUDO apt-get install -y "${packages[@]}" ;;
        dnf) $SUDO dnf install -y "${packages[@]}" ;;
        dnf5) $SUDO dnf5 install -y "${packages[@]}" ;;
        microdnf) $SUDO microdnf install -y "${packages[@]}" ;;
        yum) $SUDO yum install -y "${packages[@]}" ;;
        zypper) $SUDO zypper --non-interactive install "${packages[@]}" ;;
        apk) $SUDO apk add --no-cache "${packages[@]}" ;;
        xbps) $SUDO xbps-install -Sy "${packages[@]}" ;;
        emerge) $SUDO emerge --noreplace "${packages[@]}" ;;
        eopkg) $SUDO eopkg install -y "${packages[@]}" ;;
        urpmi) $SUDO urpmi --auto "${packages[@]}" ;;
        tdnf) $SUDO tdnf install -y "${packages[@]}" ;;
        slackpkg) $SUDO slackpkg -batch=on -default_answer=y install "${packages[@]}" ;;
        guix) guix install "${packages[@]}" ;;
        nix)
            local -a nix_specs=()
            for pkg in "${packages[@]}"; do nix_specs+=("nixpkgs#$pkg"); done
            nix profile install "${nix_specs[@]}"
            ;;
        rpm-ostree)
            $SUDO rpm-ostree install --idempotent "${packages[@]}"
            echo "ERROR: rpm-ostree layered new dependencies. Reboot into the new deployment, then rerun the installer."
            return 75
            ;;
        swupd)
            $SUDO swupd bundle-add "${packages[@]}"
            ;;
        *)
            echo "ERROR: No package installation adapter is available for '$PKG'."
            return 1
            ;;
    esac
}

# ------------------------------------------
# skills.sh / Agent Skills integration
# ------------------------------------------

skills_cli_npx() {
    local npx_bin
    npx_bin="$(find_npx)"
    if [[ -z "$npx_bin" ]]; then
        install_node_if_missing
        npx_bin="$(find_npx)"
    fi
    [[ -n "$npx_bin" ]] || { echo "ERROR: Node.js/npx is required for skills.sh."; return 1; }
    printf '%s\n' "$npx_bin"
}

skills_cli_check() {
    local npx_bin
    npx_bin="$(skills_cli_npx)" || return 1
    if ! "$npx_bin" -y skills --version >/dev/null 2>&1; then
        echo "ERROR: Unable to run the skills CLI through npx."
        echo "       Try: $npx_bin -y skills --version"
        return 1
    fi
    echo "    [ready] skills.sh CLI via npx ($npx_bin)"
}

skills_api_search_json() {
    local query="$1"
    local limit="${2:-$SKILLS_SEARCH_LIMIT}"
    local owner="${3:-}"

    # The public skills CLI uses the unauthenticated /api/search endpoint.
    # /api/v1/skills/search now requires Vercel OIDC and returns 401 for a
    # normal local installer, so do not use that authenticated endpoint here.
    if [[ -n "$owner" ]]; then
        curl -fsSL --max-time 20 -G \
            --data-urlencode "q=$query" \
            --data-urlencode "limit=$limit" \
            --data-urlencode "owner=$owner" \
            "$SKILLS_API_BASE/api/search"
    else
        curl -fsSL --max-time 20 -G \
            --data-urlencode "q=$query" \
            --data-urlencode "limit=$limit" \
            "$SKILLS_API_BASE/api/search"
    fi
}

skills_summary_from_text() {
    local text_file="$1" fallback_name="${2:-}" fallback_source="${3:-}" fallback_installs="${4:-0}"
    python3 - "$text_file" "$fallback_name" "$fallback_source" "$fallback_installs" <<'PY_SKILL_TEXT_SUMMARY'
import re, sys, html
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
name = sys.argv[2]
source = sys.argv[3]
installs = sys.argv[4]

# Prefer a description from embedded SKILL.md/frontmatter or page metadata.
summary = ""
m = re.search(r'(?im)^description\s*:\s*["\']?(.+?)["\']?\s*$', text)
if m:
    summary = m.group(1).strip()

if not summary:
    for pat in [
        r'<meta[^>]+(?:name|property)=["\'](?:description|og:description)["\'][^>]+content=["\']([^"\']+)',
        r'<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:name|property)=["\'](?:description|og:description)["\']',
    ]:
        m = re.search(pat, text, re.I)
        if m:
            summary = html.unescape(m.group(1)).strip()
            break

if not summary:
    # skills.sh pages expose the rendered SKILL.md below the 'SKILL.md' label.
    plain = re.sub(r'<script\b[^>]*>.*?</script>', ' ', text, flags=re.I|re.S)
    plain = re.sub(r'<style\b[^>]*>.*?</style>', ' ', plain, flags=re.I|re.S)
    plain = re.sub(r'<[^>]+>', '\n', plain)
    plain = html.unescape(plain)
    plain = plain.replace('\r', '')
    lines = [' '.join(x.split()) for x in plain.split('\n') if ' '.join(x.split())]
    try:
        idx = next(i for i, x in enumerate(lines) if x.strip().lower() == 'skill.md')
    except StopIteration:
        idx = -1
    if idx >= 0:
        for x in lines[idx+1:idx+12]:
            if x and x.lower() not in {'installation', 'commands', 'workflows', 'usage', 'instructions'} and not x.startswith('$ npx skills add'):
                summary = x
                break

summary = re.sub(r'[`*_>#]', '', summary)
summary = ' '.join(summary.split())
if len(summary) > 220:
    summary = summary[:217].rstrip() + '...'

print('\t'.join([name, source, str(installs), summary or 'No summary available.']))
PY_SKILL_TEXT_SUMMARY
}

skills_summary_by_id() {
    local skill_id="$1" payload_file page_file result
    [[ -n "$skill_id" ]] || return 1

    # First try the current detail API. It may be unavailable to unauthenticated
    # clients, so a 401 is expected on some installations.
    payload_file="$(mktemp)"
    if curl -fsSL --max-time 20 "$SKILLS_API_BASE/api/v1/skills/$skill_id" >"$payload_file" 2>/dev/null; then
        if python3 - "$payload_file" <<'PY_SKILL_SUMMARY'
import json, sys, re
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
summary = ""
name = payload.get("slug") or ""
source = payload.get("source") or ""
installs = payload.get("installs") or 0

for item in payload.get("files", []) or []:
    if item.get("path", "").lower() != "skill.md":
        continue
    text = item.get("contents", "") or ""
    fm = re.search(r"^---\s*(.*?)\s*---", text, re.M | re.S)
    if fm:
        for line in fm.group(1).splitlines():
            match = re.match(r"^description\s*:\s*(.*)$", line, re.I)
            if match:
                summary = match.group(1).strip().strip('"\'')
                break
    if not summary:
        body = re.sub(r"^---.*?---\s*", "", text, count=1, flags=re.S).strip()
        paragraphs = [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip()]
        if paragraphs:
            summary = paragraphs[0]
    break

summary = re.sub(r"[`*_>#]", "", summary)
summary = " ".join(summary.split())
if len(summary) > 220:
    summary = summary[:217].rstrip() + "..."
print("\t".join([name, source, str(installs), summary or "No summary available."]))
PY_SKILL_SUMMARY
        then
            rm -f "$payload_file"
            return 0
        fi
    fi
    rm -f "$payload_file"

    # Public fallback: scrape the skills.sh skill page, which is accessible
    # without Vercel OIDC and visibly contains the rendered SKILL.md.
    page_file="$(mktemp)"
    if curl -fsSL --max-time 20 "$SKILLS_API_BASE/${skill_id#/}" >"$page_file" 2>/dev/null; then
        result="$(skills_summary_from_text "$page_file" "${skill_id##*/}" "${skill_id%/*}" "0" 2>/dev/null || true)"
        rm -f "$page_file"
        [[ -n "$result" ]] && { printf '%s\n' "$result"; return 0; }
    else
        rm -f "$page_file"
    fi
    return 1
}

skills_extract_search_rows() {
    local json_file="$1"
    python3 - "$json_file" <<'PY_SKILL_SEARCH'
import json, sys
from pathlib import Path

payload = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
items = payload.get("skills") or payload.get("data") or []
for item in items:
    skill_id = item.get("id") or ""
    slug = item.get("slug") or skill_id
    name = item.get("name") or skill_id.rsplit('/', 1)[-1]
    source = item.get("source") or ""
    installs = item.get("installs") or 0
    url = item.get("url") or ""
    install_url = item.get("installUrl") or ""
    description = item.get("description") or ""
    print("\t".join([str(skill_id), str(slug), str(name), str(source), str(installs), str(url), str(install_url), str(description)]))
PY_SKILL_SEARCH
}

skills_search() {
    local query="${1:-}"
    local payload_file rows skill_id slug name source installs url install_url description summary
    [[ -n "$query" ]] || { echo "Usage: $0 skills-search <query>"; return 2; }
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required for skills.sh search."; return 1; }
    command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required for skills.sh search."; return 1; }

    payload_file="$(mktemp)"
    echo "==> Searching skills.sh for: $query"
    if ! skills_api_search_json "$query" "$SKILLS_SEARCH_LIMIT" >"$payload_file"; then
        rm -f "$payload_file"
        echo "ERROR: skills.sh search failed."
        return 1
    fi
    if ! rows="$(skills_extract_search_rows "$payload_file")"; then
        rm -f "$payload_file"
        echo "ERROR: Unable to parse skills.sh search results."
        return 1
    fi
    rm -f "$payload_file"

    if [[ -z "$rows" ]]; then
        echo "No skills found for: $query"
        return 0
    fi

    printf '\n%-3s %-30s %-22s %10s  %s\n' '#' 'SKILL' 'SOURCE' 'INSTALLS' 'SUMMARY'
    printf '%-3s %-30s %-22s %10s  %s\n' '---' '------------------------------' '----------------------' '----------' '------------------------------'
    local index=0
    while IFS=$'\t' read -r skill_id slug name source installs url install_url description; do
        [[ -n "$skill_id" ]] || continue
        ((index+=1))
        if [[ -n "$description" ]]; then
            summary=$description
        elif ! summary="$(skills_summary_by_id "$skill_id" 2>/dev/null)"; then
            summary=$'\t\t\tNo summary available.'
        fi
        local summary_name summary_source summary_installs summary_text
        IFS=$'\t' read -r summary_name summary_source summary_installs summary_text <<< "$summary"
        [[ -n "$summary_text" ]] || summary_text="${description:-No summary available.}"
        printf '%-3s %-30.30s %-22.22s %10s  %.110s\n' \
            "$index" "$name" "$source" "$installs" "$summary_text"
        printf '    ID: %s\n' "$skill_id"
        [[ -n "$url" ]] && printf '    %s\n' "$url"
    done <<< "$rows"
    printf '\nInstall examples:\n'
    printf '  %s skills-install <source/repo@skill>\n' "$0"
    printf '  %s skills-install <skills.sh URL>\n' "$0"
    printf '  %s skills-install <GitHub repo or skill URL>\n' "$0"
}

skills_search_install() {
    local query="${1:-}" payload_file rows
    local index=0 choice selected_line skill_id slug name source installs url install_url description summary
    [[ -n "$query" ]] || { echo "Usage: $0 skills-search-install <query>"; return 2; }
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required for skills.sh search."; return 1; }
    command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required for skills.sh search."; return 1; }

    payload_file="$(mktemp)"
    echo "==> Searching skills.sh for: $query"
    if ! skills_api_search_json "$query" "$SKILLS_SEARCH_LIMIT" >"$payload_file"; then
        rm -f "$payload_file"
        echo "ERROR: skills.sh search failed."
        return 1
    fi
    if ! rows="$(skills_extract_search_rows "$payload_file")"; then
        rm -f "$payload_file"
        echo "ERROR: Unable to parse skills.sh search results."
        return 1
    fi
    rm -f "$payload_file"

    if [[ -z "$rows" ]]; then
        echo "No skills found for: $query"
        return 0
    fi

    # Save the parsed rows so the user can choose a numbered result without
    # having to copy/paste a package identifier from the search output.
    local rows_file
    rows_file="$(mktemp)"
    printf '%s\n' "$rows" >"$rows_file"

    echo
    echo "SKILLS.SH SEARCH RESULTS"
    echo "========================"
    while IFS=$'\t' read -r skill_id slug name source installs url install_url description; do
        [[ -n "$skill_id" ]] || continue
        ((index+=1))
        if [[ -n "$description" ]]; then
            summary="$description"
        elif ! summary="$(skills_summary_by_id "$skill_id" 2>/dev/null)"; then
            summary=$'\t\t\tNo summary available.'
        fi
        local summary_name summary_source summary_installs summary_text
        IFS=$'\t' read -r summary_name summary_source summary_installs summary_text <<< "$summary"
        [[ -n "$summary_text" ]] || summary_text="${description:-No summary available.}"
        printf '\n[%d] %s\n' "$index" "$name"
        printf '    Source:   %s\n' "$source"
        printf '    Installs: %s\n' "$installs"
        printf '    Summary:  %s\n' "$summary_text"
        printf '    Install:  %s@%s\n' "$source" "$name"
        [[ -n "$url" ]] && printf '    Page:     %s\n' "$url"
    done <"$rows_file"

    echo
    echo "Choose a result number to install."
    echo "Use 's N' to show the full summary for result N, or 'q' to cancel."
    while true; do
        printf 'Selection: '
        IFS= read -r choice || choice='q'
        choice="${choice#${choice%%[![:space:]]*}}"
        choice="${choice%${choice##*[![:space:]]}}"
        [[ -n "$choice" ]] || { rm -f "$rows_file"; echo "Install cancelled."; return 0; }
        case "${choice,,}" in
            q|quit|back)
                rm -f "$rows_file"
                echo "Install cancelled."
                return 0
                ;;
            s\ [0-9]*|summary\ [0-9]*)
                local num="${choice#* }"
                if [[ ! "$num" =~ ^[0-9]+$ ]]; then
                    echo "Enter a valid result number."
                    continue
                fi
                selected_line="$(sed -n "${num}p" "$rows_file")"
                if [[ -z "$selected_line" ]]; then
                    echo "No result #$num."
                    continue
                fi
                IFS=$'\t' read -r skill_id slug name source installs url install_url description <<< "$selected_line"
                if summary="$(skills_summary_by_id "$skill_id" 2>/dev/null)"; then
                    IFS=$'\t' read -r summary_name summary_source summary_installs summary_text <<< "$summary"
                else
                    summary_text="${description:-No summary available.}"
                fi
                echo
                echo "SKILL SUMMARY — $name"
                echo "======================"
                echo "Name:      $name"
                echo "Source:    $source"
                echo "Installs:  $installs"
                echo "Skill ID:  $skill_id"
                echo "Summary:"
                printf '  %s\n' "${summary_text:-No summary available.}"
                echo
                ;;
            *)
                if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
                    echo "Enter a result number, 's N', or 'q'."
                    continue
                fi
                selected_line="$(sed -n "${choice}p" "$rows_file")"
                if [[ -z "$selected_line" ]]; then
                    echo "No result #$choice."
                    continue
                fi
                IFS=$'\t' read -r skill_id slug name source installs url install_url description <<< "$selected_line"
                summary_text="${description:-No summary available.}"
                if summary="$(skills_summary_by_id "$skill_id" 2>/dev/null)"; then
                    IFS=$'\t' read -r summary_name summary_source summary_installs summary_text <<< "$summary"
                fi
                echo
                echo "SELECTED SKILL"
                echo "=============="
                echo "Name:      $name"
                echo "Source:    $source"
                echo "Installs:  $installs"
                echo "Summary:"
                printf '  %s\n' "${summary_text:-No summary available.}"
                echo
                printf 'Install %s@%s now? [Y/n]: ' "$source" "$name"
                local confirm
                IFS= read -r confirm || confirm=''
                confirm="${confirm:-Y}"
                case "${confirm,,}" in
                    y|yes)
                        rm -f "$rows_file"
                        skills_install "$source@$name"
                        return $?
                        ;;
                    *)
                        echo "Install cancelled."
                        ;;
                esac
                ;;
        esac
    done
}

skills_resolve_sh_url() {
    local input="$1" path
    path="${input#https://skills.sh/}"
    path="${path#http://skills.sh/}"
    path="${path#/}"
    [[ "$path" == p/* ]] && { printf 'PACK\t%s\n' "https://skills.sh/$path"; return 0; }
    IFS='/' read -r -a parts <<< "$path"
    if (( ${#parts[@]} >= 3 )) && [[ -n "${parts[0]}" && -n "${parts[1]}" && -n "${parts[2]}" ]]; then
        printf 'GITHUB_SKILL\t%s/%s\t%s\n' "${parts[0]}" "${parts[1]}" "${parts[2]}"
        return 0
    fi
    if (( ${#parts[@]} == 2 )) && [[ -n "${parts[0]}" && -n "${parts[1]}" ]]; then
        printf 'SOURCE_SKILL\t%s\t%s\n' "${parts[0]}" "${parts[1]}"
        return 0
    fi
    return 1
}

skills_resolve_name_to_id() {
    local query="$1" payload_file rows skill_id slug name source installs url install_url
    payload_file="$(mktemp)"
    if ! skills_api_search_json "$query" "$SKILLS_SEARCH_LIMIT" >"$payload_file"; then
        rm -f "$payload_file"
        return 1
    fi
    if ! rows="$(skills_extract_search_rows "$payload_file")"; then
        rm -f "$payload_file"
        return 1
    fi
    rm -f "$payload_file"
    [[ -n "$rows" ]] || return 1

    # Prefer an exact slug/name/id match (case-insensitive).
    while IFS=$'\t' read -r skill_id slug name source installs url install_url description; do
        if [[ "${slug,,}" == "${query,,}" || "${name,,}" == "${query,,}" || "${skill_id,,}" == "${query,,}" ]]; then
            printf '%s\n' "$skill_id"
            return 0
        fi
    done <<< "$rows"

    # A single result is safe to resolve automatically.
    local count=0 first_id=''
    while IFS=$'\t' read -r skill_id slug name source installs url install_url description; do
        [[ -n "$skill_id" ]] || continue
        ((count+=1))
        [[ -n "$first_id" ]] || first_id="$skill_id"
    done <<< "$rows"
    if (( count == 1 )); then
        printf '%s\n' "$first_id"
        return 0
    fi

    echo "No exact skill match for '$query'. Search results:" >&2
    skills_search "$query" >&2 || true
    return 2
}

skills_detect_global_agents() {
    # The upstream CLI currently has a known global-install edge case where
    # PromptScript can be selected even though it does not support --global.
    # Supplying only agents that are actually present on this machine avoids
    # that target entirely while preserving global installs for real agents.
    local -a agents=()
    local agent path
    declare -A seen=()

    # Global config roots from the official skills CLI agent table. Detection is
    # based on the parent application/config directory, not the skills folder,
    # so an empty skills folder does not count as an installed agent.
    local -a checks=(
        'aider-desk|$HOME/.aider-desk'
        'amp|$HOME/.amp'
        'antigravity|$HOME/.gemini/antigravity'
        'antigravity-cli|$HOME/.gemini/antigravity-cli'
        'astrbot|$HOME/.astrbot'
        'autohand-code|$HOME/.autohand-code'
        'augment|$HOME/.augment'
        'bob|$HOME/.bob'
        'claude-code|$HOME/.claude'
        'openclaw|$HOME/.openclaw'
        'codearts-agent|$HOME/.codeartsdoer'
        'hermes-agent|$HOME/.hermes'
        'inference-sh|$HOME/.inferencesh'
        'jazz|$HOME/.jazz'
        'junie|$HOME/.junie'
        'iflow-cli|$HOME/.iflow'
        'kilo|$HOME/.kilo'
        'kimchi|$HOME/.kimchi'
        'kiro-cli|$HOME/.kiro'
        'kode|$HOME/.kode'
        'lingma|$HOME/.lingma'
        'mcpjam|$HOME/.mcpjam'
        'minimax-code|$HOME/.minimax'
        'mistral-vibe|$HOME/.vibe'
        'moxby|$HOME/.moxby'
        'mux|$HOME/.mux'
        'opencode|$HOME/.config/opencode'
        'openhands|$HOME/.openhands'
        'ona|$HOME/.ona'
        'pi|$HOME/.pi'
        'qoder|$HOME/.qoder'
        'roo|$HOME/.roo'
        'zed|$HOME/.config/zed'
        'zencoder|$HOME/.zencoder'
        'zenflow|$HOME/.zenflow'
        'neovate|$HOME/.neovate'
        'pochi|$HOME/.pochi'
        'dexto|$HOME/.dexto'
        'cline|$HOME/.cline'
        'kimi-code-cli|$HOME/.kimi'
        'warp|$HOME/.warp'
    )

    for entry in "${checks[@]}"; do
        agent="${entry%%|*}"
        path="${entry#*|}"
        path="${path//\$HOME/$HOME}"
        if [[ -e "$path" || -d "$path" ]]; then
            [[ -n "${seen[$agent]:-}" ]] || agents+=("$agent")
            seen["$agent"]=1
        fi
    done

    # If no concrete agent is installed, use the CLI's universal global store.
    if (( ${#agents[@]} == 0 )); then
        printf '%s\n' universal
    else
        printf '%s\n' "${agents[@]}"
    fi
}

skills_cli_global_add() {
    local npx_bin="$1"
    shift
    local -a agents=() args=()
    local agent
    mapfile -t agents < <(skills_detect_global_agents)
    args=(skills add "$@")
    for agent in "${agents[@]}"; do
        args+=(--agent "$agent")
    done
    args+=("$SKILLS_INSTALL_SCOPE" -y)
    echo "    [targets] Global skill agents: ${agents[*]}"
    "$npx_bin" -y "${args[@]}"
}

skills_translate_package_name() {
    local pkg="$1" manager="$PKG"
    case "$manager:$pkg" in
        # Arch-family translations from Debian-ish package names commonly found
        # in third-party skill documentation.
        pacman:build-essential) echo "base-devel" ;;
        pacman:python3-pip|pacman:python-pip) echo "python-pip" ;;
        pacman:python3-dev|pacman:python-dev|pacman:python-is-python3) echo "python" ;;
        pacman:poppler-utils) echo "poppler" ;;
        pacman:libsm6) echo "libsm" ;;
        pacman:libxext6) echo "libxext" ;;
        pacman:libxrender1) echo "libxrender" ;;
        pacman:libglib2.0-0) echo "glib2" ;;
        pacman:libssl-dev) echo "openssl" ;;
        pacman:zlib1g-dev) echo "zlib" ;;

        # Debian/Ubuntu-family translations from Arch/RPM naming.
        apt:base-devel) echo "build-essential" ;;
        apt:python-pip) echo "python3-pip" ;;
        apt:python) echo "python3" ;;
        apt:python-devel|apt:python-dev) echo "python3-dev" ;;
        apt:poppler) echo "poppler-utils" ;;
        apt:openssl-devel) echo "libssl-dev" ;;
        apt:zlib-devel) echo "zlib1g-dev" ;;
        apt:bzip2-devel) echo "libbz2-dev" ;;
        apt:readline-devel) echo "libreadline-dev" ;;
        apt:sqlite-devel) echo "libsqlite3-dev" ;;
        apt:ncurses-devel) echo "libncurses-dev" ;;
        apt:libffi-devel) echo "libffi-dev" ;;

        # RPM-family translations (Fedora/RHEL/Mageia/Photon and derivatives).
        dnf:build-essential|dnf5:build-essential|microdnf:build-essential|yum:build-essential|tdnf:build-essential|urpmi:build-essential) echo "gcc gcc-c++ make" ;;
        dnf:python3-dev|dnf5:python3-dev|microdnf:python3-dev|yum:python3-dev|tdnf:python3-dev|urpmi:python3-dev) echo "python3-devel" ;;
        dnf:libssl-dev|dnf5:libssl-dev|microdnf:libssl-dev|yum:libssl-dev|tdnf:libssl-dev|urpmi:libssl-dev) echo "openssl-devel" ;;
        dnf:zlib1g-dev|dnf5:zlib1g-dev|microdnf:zlib1g-dev|yum:zlib1g-dev|tdnf:zlib1g-dev|urpmi:zlib1g-dev) echo "zlib-devel" ;;
        dnf:poppler-utils|dnf5:poppler-utils|microdnf:poppler-utils|yum:poppler-utils|tdnf:poppler-utils|urpmi:poppler-utils) echo "poppler-utils" ;;

        # openSUSE.
        zypper:build-essential) echo "gcc gcc-c++ make" ;;
        zypper:python3-dev) echo "python3-devel" ;;
        zypper:libssl-dev) echo "libopenssl-devel" ;;
        zypper:zlib1g-dev) echo "zlib-devel" ;;

        # Alpine.
        apk:build-essential) echo "build-base" ;;
        apk:python3-dev) echo "python3-dev" ;;
        apk:libssl-dev) echo "openssl-dev" ;;
        apk:zlib1g-dev) echo "zlib-dev" ;;
        apk:poppler-utils) echo "poppler-utils" ;;

        # Void Linux.
        xbps:build-essential) echo "base-devel" ;;
        xbps:python3-dev) echo "python3-devel" ;;
        xbps:libssl-dev) echo "openssl-devel" ;;
        xbps:zlib1g-dev) echo "zlib-devel" ;;

        # Nix/Guix package naming differences used by common skills.
        nix:build-essential) echo "gcc gnumake" ;;
        nix:python3-dev|nix:python3-pip) echo "python3" ;;
        guix:build-essential) echo "gcc-toolchain make" ;;
        guix:python3-dev|guix:python3-pip) echo "python" ;;

        *) echo "$pkg" ;;
    esac
}

skills_find_installed_root() {
    local requested="${1:-}" slug="${2:-}" root file front_name
    local -a search_roots=()
    [[ -d "$HOME/.agents/skills" ]] && search_roots+=("$HOME/.agents/skills")
    [[ -d "$HOME/.config/agents/skills" ]] && search_roots+=("$HOME/.config/agents/skills")
    [[ -d "$HOME/.claude/skills" ]] && search_roots+=("$HOME/.claude/skills")
    [[ -d "$HOME/.cursor/skills" ]] && search_roots+=("$HOME/.cursor/skills")
    [[ -d "$HOME/.codex/skills" ]] && search_roots+=("$HOME/.codex/skills")
    [[ -d "$HOME/.config/opencode/skills" ]] && search_roots+=("$HOME/.config/opencode/skills")
    [[ -d "$HOME/.zencoder/skills" ]] && search_roots+=("$HOME/.zencoder/skills")

    for root in "${search_roots[@]}"; do
        while IFS= read -r -d '' file; do
            front_name="$(python3 - "$file" <<'PY_SKILL_NAME' 2>/dev/null || true
import re, sys
from pathlib import Path
text=Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')
m=re.search(r'^---\s*(.*?)\s*---', text, re.M|re.S)
if m:
    for line in m.group(1).splitlines():
        x=re.match(r'^name\s*:\s*["\']?(.*?)["\']?\s*$', line, re.I)
        if x:
            print(x.group(1).strip())
            raise SystemExit
PY_SKILL_NAME
)"
            if [[ "${front_name,,}" == "${requested,,}" || "$(basename "$(dirname "$file")")" == "$slug" ]]; then
                dirname "$file"
                return 0
            fi
        done < <(find "$root" -mindepth 2 -maxdepth 4 -type f -name SKILL.md -print0 2>/dev/null)
    done
    return 1
}

skills_install_declared_system_packages() {
    local skill_root="$1" skill_md
    skill_md="$skill_root/SKILL.md"
    [[ -f "$skill_md" ]] || return 0

    # Read explicit package-manager install examples from the skill. We only
    # convert package names; we never execute arbitrary shell from SKILL.md.
    local -a packages=() tokens translated pkg_line manager_hint
    mapfile -t tokens < <(python3 - "$skill_md" <<'PY_SKILL_PKGS'
import re, sys
from pathlib import Path
text=Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')
patterns = [
    r'\b(?:sudo\s+)?apt(?:-get)?\s+(?:install|install\.sh)\s+([^\n;|&]+)',
    r'\b(?:sudo\s+)?pacman\s+-S(?:\s+--[^\s]+)*\s+([^\n;|&]+)',
    r'\b(?:sudo\s+)?(?:dnf5?|microdnf|yum|tdnf)\s+(?:install|localinstall)\s+([^\n;|&]+)',
    r'\b(?:sudo\s+)?zypper\s+(?:--non-interactive\s+)?install\s+([^\n;|&]+)',
    r'\b(?:sudo\s+)?apk\s+add\s+([^\n;|&]+)',
    r'\b(?:sudo\s+)?xbps-install\s+-S(?:y)?\s+([^\n;|&]+)',
    r'\b(?:sudo\s+)?eopkg\s+(?:install|it)\s+([^\n;|&]+)',
    r'\b(?:sudo\s+)?urpmi\s+(?:--auto\s+)?([^\n;|&]+)',
    r'\b(?:sudo\s+)?emerge\s+(?:--noreplace\s+)?([^\n;|&]+)',
]
seen=set()
for pat in patterns:
    for m in re.finditer(pat, text, re.I):
        for tok in m.group(1).split():
            tok=tok.strip('`\"\'(),[]')
            if not tok or tok.startswith('-') or '$' in tok or '/' in tok and tok.startswith('http'):
                continue
            # Ignore shell control fragments and variable placeholders.
            if tok in {'\\', '&&', '||', ';'} or tok.startswith('<') or tok.startswith('>'):
                continue
            if re.match(r'^[A-Za-z0-9_.+:@/-]+$', tok) and tok not in seen:
                seen.add(tok); print(tok)
PY_SKILL_PKGS
)
    for pkg in "${tokens[@]}"; do
        translated="$(skills_translate_package_name "$pkg")"
        if [[ -n "$translated" ]]; then
            local -a translated_parts=()
            read -r -a translated_parts <<< "$translated"
            packages+=("${translated_parts[@]}")
        fi
    done

    # Also detect common executable prerequisites named by the skill. This is
    # intentionally a conservative allow-list so arbitrary words in a skill
    # description cannot become sudo package-install commands.
    local command_name package_name
    local -A command_map=(
        [curl]="curl" [wget]="wget" [git]="git" [jq]="jq" [yq]="yq"
        [ffmpeg]="ffmpeg" [convert]="imagemagick" [magick]="imagemagick"
        [pandoc]="pandoc" [pdftotext]="poppler-utils" [chromium]="chromium"
        [node]="nodejs" [npm]="npm" [npx]="npm" [gh]="github-cli"
        [docker]="docker" [docker-compose]="docker-compose" [unzip]="unzip"
        [zip]="zip" [7z]="p7zip" [cmake]="cmake" [gcc]="gcc" [g++]="gcc"
        [make]="make" [cargo]="rust" [go]="go"
    )
    for command_name in "${!command_map[@]}"; do
        if grep -Eiq "(^|[^[:alnum:]_-])${command_name}([^[:alnum:]_-]|$)" "$skill_md"; then
            if ! command -v "$command_name" >/dev/null 2>&1; then
                package_name="${command_map[$command_name]}"
                package_name="$(skills_translate_package_name "$package_name")"
                if [[ -n "$package_name" ]]; then
                    local -a command_package_parts=()
                    read -r -a command_package_parts <<< "$package_name"
                    packages+=("${command_package_parts[@]}")
                fi
            fi
        fi
    done

    # De-duplicate before handing the list to the distro-aware installer.
    if (( ${#packages[@]} )); then
        mapfile -t packages < <(printf '%s\n' "${packages[@]}" | awk 'NF && !seen[$0]++')
        echo "==> Resolving OS packages declared/referenced by skill ($PKG)"
        install_missing_packages "${packages[@]}"
    else
        echo "    [ready] No additional OS packages detected for this skill"
    fi
}

# Resolve a small, reviewed set of Python imports from *actual skill-local
# scripts*, rather than treating text in SKILL.md as executable instructions.
# Never auto-install torch/CUDA/ROCm or other accelerator-specific wheels here:
# those are owned by the runtime installer and must not be overwritten by pip.
skills_install_known_script_imports() {
    local root="$1" py="$2" requirement failed=0
    [[ -x "$py" ]] || return 0
    local -a missing=()
    mapfile -t missing < <("$py" - "$root" <<'PY_SKILL_SCRIPT_IMPORTS'
import ast, importlib.util, sys
from pathlib import Path
root = Path(sys.argv[1])
packages = {
    'PIL': 'pillow', 'docx': 'python-docx', 'pptx': 'python-pptx',
    'openpyxl': 'openpyxl', 'pypdf': 'pypdf', 'reportlab': 'reportlab',
    'yaml': 'PyYAML', 'dotenv': 'python-dotenv', 'fitz': 'pymupdf',
    'cv2': 'opencv-python-headless', 'numpy': 'numpy', 'scipy': 'scipy',
    'pandas': 'pandas', 'requests': 'requests', 'httpx': 'httpx',
    'bs4': 'beautifulsoup4', 'faster_whisper': 'faster-whisper',
    'speech_recognition': 'SpeechRecognition', 'librosa': 'librosa',
    'soundfile': 'soundfile', 'pydub': 'pydub', 'moviepy': 'moviepy',
    'sklearn': 'scikit-learn', 'rich': 'rich', 'typer': 'typer',
}
files = [root / 'run.py'] + list((root / 'scripts').glob('*.py'))
found = set()
for file in files[:33]:
    if not file.is_file() or file.is_symlink() or file.stat().st_size > 512_000:
        continue
    try:
        code = ast.parse(file.read_text(encoding='utf-8', errors='replace'))
    except (OSError, SyntaxError):
        continue
    for node in ast.walk(code):
        if isinstance(node, ast.Import):
            names = (part.name for part in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0:
            names = (node.module or '',)
        else:
            continue
        for name in names:
            mod = name.split('.', 1)[0]
            if mod in packages:
                found.add(mod)
for mod in sorted(found):
    try:
        installed = importlib.util.find_spec(mod) is not None
    except (ValueError, ImportError, AttributeError):
        installed = False
    if not installed:
        print(packages[mod])
PY_SKILL_SCRIPT_IMPORTS
    ) || return 1
    for requirement in "${missing[@]}"; do
        [[ -n "$requirement" ]] || continue
        echo "==> Repairing inferred script import: $requirement"
        dependency_repair_pip "$py" "$requirement" || failed=1
    done
    ((failed==0))
}

# agent-browser's npm package is only the CLI: Chrome and its Linux shared
# libraries need a separate upstream installer. Invoke this only for the
# actual agent-browser skill or a skill that explicitly documents that setup.
skills_install_browser_prerequisites() {
    local root="$1"
    [[ "$(basename "$root")" == agent-browser ]] ||
        grep -Eiq 'agent-browser[[:space:]]+install([[:space:]]|$)' "$root/SKILL.md" || return 0
    if ! command -v agent-browser >/dev/null 2>&1; then
        skills_npm_global_install_documented agent-browser || return 1
    fi
    if agent-browser doctor --offline --quick >/dev/null 2>&1; then
        echo '    [ready] agent-browser Chrome runtime already passes the local health check.'
        return 0
    fi
    echo '==> Repairing agent-browser Chrome runtime and Linux libraries.'
    if agent-browser install --with-deps && agent-browser doctor --offline --quick; then
        echo '    [ready] agent-browser Chrome runtime repaired and verified.'
        return 0
    fi
    echo '    [warning] Upstream --with-deps failed; attempting browser download without privileged library changes.'
    if agent-browser install && agent-browser doctor --offline --quick; then
        echo '    [ready] agent-browser browser runtime repaired and verified.'
        return 0
    fi
    echo '    [error] Chrome/browser runtime remains incomplete; inspect agent-browser doctor.'
    return 1
}

skills_install_skill_manifests() {
    local skill_root="$1" failure=0
    local py="${VENV_PY:-}"
    [[ -x "$py" ]] || py="$(command -v python3 2>/dev/null || true)"

    if [[ -f "$skill_root/package.json" ]]; then
        if command -v npm >/dev/null 2>&1; then
            if [[ -f "$skill_root/package-lock.json" ]]; then
                echo "==> Installing locked Node dependencies for $skill_root"
                dependency_repair_npm "$skill_root" ci || failure=1
            else
                echo "==> Installing Node dependencies for $skill_root"
                dependency_repair_npm "$skill_root" install || failure=1
            fi
        else
            echo '==> npm missing; installing Node.js/npm for declared skill dependencies.'
            if install_node_if_missing && command -v npm >/dev/null 2>&1; then
                if [[ -f "$skill_root/package-lock.json" ]]; then
                    dependency_repair_npm "$skill_root" ci || failure=1
                else
                    dependency_repair_npm "$skill_root" install || failure=1
                fi
            else
                echo "    [error] package.json exists but Node.js/npm installation failed."
                failure=1
            fi
        fi
    fi

    if [[ -f "$skill_root/requirements.txt" ]]; then
        if [[ -n "$py" ]]; then
            echo "==> Installing Python dependencies from $skill_root/requirements.txt"
            if ! dependency_repair_pip "$py" -r "$skill_root/requirements.txt"; then
                echo "    [error] Skill Python requirements failed to install."
                failure=1
            fi
        else
            echo "    [error] requirements.txt found but Python is unavailable."
            failure=1
        fi
    fi

    if [[ -f "$skill_root/pyproject.toml" && ! -f "$skill_root/requirements.txt" && -n "$py" ]]; then
        # Only install a local Python project when it declares a build target.
        if grep -Eq '^\s*\[(project|build-system)(\.|])' "$skill_root/pyproject.toml"; then
            echo "==> Installing Python project dependencies from pyproject.toml"
            if ! dependency_repair_pip "$py" "$skill_root"; then
                echo "    [error] Skill Python project dependencies failed to install."
                failure=1
            fi
        fi
    fi

    # Repair only the documented npx prerequisite for prompt-based Skills CLI
    # workflows (such as find-skills); never execute the skill itself.
    if grep -Eq '(^|`)[[:space:]]*(\$[[:space:]]*)?npx[[:space:]]+(--yes[[:space:]]+)?skills([[:space:]`]|$)' "$skill_root/SKILL.md"; then
        if ! command -v npx >/dev/null 2>&1; then
            echo '==> Installing missing Node/npx prerequisite documented by skill.'
            install_node_if_missing || failure=1
        fi
        command -v npx >/dev/null 2>&1 || failure=1
    fi

    # Some skills provide runnable scripts but omit requirements.txt. Resolve
    # only reviewed imports from those scripts, with no arbitrary code execution.
    skills_install_known_script_imports "$skill_root" "$py" || failure=1

    # A few skills document globally-installed CLIs directly in SKILL.md. Run
    # only explicit npm/pip install commands found in the skill document.
    local line spec
    while IFS= read -r line; do
        if [[ "$line" =~ npm[[:space:]]+(install|i)[[:space:]]+-g[[:space:]]+([^[:space:]\`\;\|]+) ]]; then
            spec="${BASH_REMATCH[2]}"
            if command -v npm >/dev/null 2>&1; then
                skills_npm_global_install_documented "$spec" || { echo "    [error] npm dependency unavailable: $spec"; failure=1; }
            fi
        elif [[ "$line" =~ pip[3]?[[:space:]]+install[[:space:]]+([^[:space:]\`\;\|]+) ]]; then
            spec="${BASH_REMATCH[1]}"
            if [[ -n "$py" ]]; then
                echo "==> Installing documented Python dependency: $spec"
                dependency_repair_pip "$py" "$spec" || { echo "    [error] Python dependency unavailable: $spec"; failure=1; }
            fi
        fi
    done < "$skill_root/SKILL.md"
    if (( failure )); then
        echo "ERROR: Skill dependencies incomplete: $skill_root"
        return 1
    fi
    echo "    [ready] Declared skill dependencies installed: $skill_root"
}

# Known identity providers own login and token storage. Never read passwords or
# echo tokens. Device/browser verification URLs and one-time codes are rendered
# by the official provider CLI on the controlling terminal, including over SSH.
# Provider prompts are never hidden in redirected Fix All output.
declare -A SKILLS_AUTH_READY=() SKILLS_AUTH_PENDING=()
skills_have_controlling_tty() {
    ( : </dev/tty >/dev/tty ) 2>/dev/null
}
skills_auth_device_instructions() {
    local provider="${1:-}"
    printf '\n%s\n' '============================================================'
    case "$provider" in
        runcomfy)
            echo 'RUNCOMFY — AUTHORIZE FROM THIS COMPUTER OR ANOTHER DEVICE'
            echo 'The official RunComfy CLI prints the current authorization URL/code below.'
            echo 'Type that exact URL on your phone or another computer; authorize there.'
            echo 'Keep this terminal open while the CLI waits; no server browser required.'
            echo 'Do not enter your RunComfy password into this installer.'
            ;;
        github)
            echo 'GITHUB — AUTHORIZE FROM ANOTHER DEVICE'
            echo 'Verification URL: https://github.com/login/device'
            echo 'The official gh CLI will print your ONE-TIME code on this terminal.'
            echo 'Type the code into that page on another device and authorize.'
            ;;
        huggingface|hf)
            echo 'HUGGING FACE — CREATE A TOKEN ON ANOTHER DEVICE'
            echo 'Token creation URL: https://huggingface.co/settings/tokens'
            echo 'Generate a token with the required scope on your other device.'
            echo 'Return to this terminal and paste the token into the official hf CLI.'
            echo 'Hugging Face does not use a CLI device-code flow here.'
            ;;
    esac
    printf '%s\n\n' '============================================================'
}
skills_auth_no_tty() {
    local provider="${1:-provider}"
    echo "    [AUTH] No interactive terminal is attached for $provider."
    echo '    [NEXT] Open an SSH session with a TTY (ssh -t), then run:'
    printf '           ./zarzysseus.sh auth %s\n' "$provider"
    echo '    [NOTE] Credentials cannot be supplied automatically by Fix All.'
    return 1
}
skills_auth_runcomfy_login() {
    skills_auth_device_instructions runcomfy
    skills_have_controlling_tty || { skills_auth_no_tty runcomfy; return 1; }
    # Keep native CLI output (including a transient link/code) on the actual
    # tty. It is not silently swallowed by the TUI's redirected command log.
    runcomfy login </dev/tty >/dev/tty 2>&1 || return 1
    runcomfy whoami >/dev/null 2>&1
}
skills_auth_github_login() {
    skills_auth_device_instructions github
    skills_have_controlling_tty || { skills_auth_no_tty github; return 1; }
    gh auth login --web --git-protocol https --skip-ssh-key </dev/tty >/dev/tty 2>&1 || return 1
    gh auth status >/dev/null 2>&1
}
skills_auth_hf_login() {
    skills_auth_device_instructions huggingface
    skills_have_controlling_tty || { skills_auth_no_tty huggingface; return 1; }
    if command -v hf >/dev/null 2>&1; then
        hf auth login </dev/tty >/dev/tty 2>&1 || return 1
        hf auth whoami >/dev/null 2>&1
    else
        "$VENV_PY" -m huggingface_hub.commands.huggingface_cli login </dev/tty >/dev/tty 2>&1
    fi
}
skills_auth_prerequisites() {
    local skill_root="${1:-}" md
    md="$skill_root/SKILL.md"
    [[ -f "$md" ]] || return 0
    if grep -Eiq '(@runcomfy/cli|runcomfy[[:space:]]+(login|run|whoami))' "$md"; then
        echo '    [AUTH CHECK] RunComfy is required by this skill.'
        install_node_if_missing || return 1
        if ! command -v runcomfy >/dev/null 2>&1; then
            echo '    [INSTALL] Installing the official RunComfy CLI from npm.'
            skills_npm_global_install_documented '@runcomfy/cli' || return 1
        fi
        if [[ -n "${SKILLS_AUTH_PENDING[runcomfy]:-}" ]]; then
            echo '    [AUTH] RunComfy sign-in was attempted earlier in this run; not prompting again.'
            echo '    [NEXT] ./zarzysseus.sh auth runcomfy'
            return 1
        fi
        if [[ -z "${SKILLS_AUTH_READY[runcomfy]:-}" ]] && ! runcomfy whoami >/dev/null 2>&1; then
            echo '    [AUTH] CLI installed; waiting for provider authorization (not a missing package).'
            if ! skills_auth_runcomfy_login; then
                echo '    [AUTH] RunComfy authorization incomplete. See the verification link/code above.'
                SKILLS_AUTH_PENDING[runcomfy]=1
                return 1
            fi
        fi
        SKILLS_AUTH_READY[runcomfy]=1
        echo '    [READY] RunComfy CLI installed and account authorization verified.'
    fi
    if grep -Eiq '\bgh[[:space:]]+auth[[:space:]]+login\b' "$md"; then
        echo '    [AUTH CHECK] GitHub CLI is required by this skill.'
        command -v gh >/dev/null 2>&1 || install_missing_packages "$(skills_translate_package_name github-cli)" || return 1
        if ! gh auth status >/dev/null 2>&1; then
            if ! skills_auth_github_login; then
                echo '    [AUTH] GitHub sign-in incomplete; verification page: https://github.com/login/device'
                return 1
            fi
        fi
        echo '    [READY] GitHub CLI authorization verified.'
    fi
    if grep -Eiq '\bhf[[:space:]]+auth[[:space:]]+login\b' "$md"; then
        echo '    [AUTH CHECK] Hugging Face CLI is required by this skill.'
        [[ -x "$VENV_PY" ]] || { echo 'ERROR: Python environment needed for Hugging Face login.'; return 1; }
        if ! (command -v hf >/dev/null 2>&1 && hf auth whoami >/dev/null 2>&1); then
            if ! skills_auth_hf_login; then
                echo '    [AUTH] Hugging Face login incomplete; token page: https://huggingface.co/settings/tokens'
                return 1
            fi
        fi
        echo '    [READY] Hugging Face authorization verified.'
    fi
    return 0
}
zarzysseus_auth() {
    local provider="${1:-}"
    case "$provider" in
        runcomfy)
            install_node_if_missing || return 1
            command -v runcomfy >/dev/null 2>&1 || skills_npm_global_install_documented '@runcomfy/cli' || return 1
            if runcomfy whoami >/dev/null 2>&1; then echo 'RunComfy: already authorized.'; return 0; fi
            skills_auth_runcomfy_login
            ;;
        github)
            command -v gh >/dev/null 2>&1 || install_missing_packages "$(skills_translate_package_name github-cli)" || return 1
            if gh auth status >/dev/null 2>&1; then echo 'GitHub: already authorized.'; return 0; fi
            skills_auth_github_login
            ;;
        huggingface|hf)
            [[ -x "$VENV_PY" ]] || { echo 'Install the Zarzysseus core first for HF authentication.'; return 1; }
            skills_auth_hf_login
            ;;
        *) echo 'Usage: zarzysseus.sh auth runcomfy|github|huggingface'; return 2 ;;
    esac
}

# Locally usable personal skills. Skill markdown is paired with a real, checked
# runner rather than creating empty prompt-only stubs.
personal_fave_skills_install() {
    local group="${1:-}" root packages rc=0
    case "$group" in
        all-local|office|photo-edit|video-edit|scripting|transcription|speech-to-text|cloud-photo|cloud-video) ;;
        *) echo "Unknown favorite skill group: $group"; return 2 ;;
    esac
    install_odysseus || return 1
    if [[ "$group" == all-local ]]; then
        local one
        for one in office photo-edit video-edit scripting transcription; do
            personal_fave_skills_install_prepared "$one" || rc=1
        done
    else
        personal_fave_skills_install_prepared "$group" || rc=1
    fi
    auto_fit_finalize_skills || rc=1
    return "$rc"
}

personal_fave_skills_install_prepared() {
    local group="${1:-}" root="$AUTO_FIT_SKILL_DIR/zarzysseus-fave-${1:-}" name
    case "$group" in
        cloud-photo|cloud-video)
            local slug='image-edit'
            [[ "$group" == cloud-video ]] && slug='ai-video-generation'
            echo "==> Installing selected RunComfy $group skill and its CLI/browser authorization."
            # This is a hosted OPTIONAL workflow. It is not substituted for any
            # offline photo/video option and may need account credits.
            skills_install "https://github.com/runcomfy-com/skills/tree/main/$slug"
            return $?
            ;;
        office)
            dependency_repair_pip "$VENV_PY" python-docx python-pptx openpyxl pypdf reportlab || return 1
            ;;
        photo-edit)
            dependency_repair_pip "$VENV_PY" pillow || return 1
            ;;
        video-edit)
            command -v ffmpeg >/dev/null 2>&1 || install_missing_packages ffmpeg || return 1
            ;;
        scripting)
            dependency_repair_pip "$VENV_PY" ruff || return 1
            command -v shellcheck >/dev/null 2>&1 || install_missing_packages shellcheck || return 1
            ;;
        transcription|speech-to-text)
            group=transcription
            root="$AUTO_FIT_SKILL_DIR/zarzysseus-fave-transcription"
            command -v ffmpeg >/dev/null 2>&1 || install_missing_packages ffmpeg || return 1
            dependency_repair_pip "$VENV_PY" faster-whisper || return 1
            # tiny is CPU-capable even on machines without CUDA; downloading its
            # weights now avoids an unexpected first-use model download.
            "$VENV_PY" -c 'from faster_whisper import WhisperModel; WhisperModel("tiny",device="cpu",compute_type="int8")' || return 1
            ;;
        *) return 2 ;;
    esac
    mkdir -p "$root" || return 1
    name="$(basename "$root")"
    "$VENV_PY" - "$group" "$root" "$name" "$VENV_PY" <<'PY_FAVE_SKILL'
import sys
from pathlib import Path
group,root,name,interpreter=sys.argv[1:]; d=Path(root)
info={
'office':('Local Word, spreadsheet, slides, and PDF creation/extraction', 'Create using --text CONTENT --output file.docx / file.xlsx / file.pptx / file.pdf. Extract text with --input file.docx --output file.txt. All files remain local; use the installed libraries for advanced edits.'),
'photo-edit':('Local image editing', 'Use run.py --input image.png --output edited.png --width 1200 to resize using Pillow; preserve original unless explicitly overwriting.'),
'video-edit':('Local video editing and cutting', 'Use run.py --input clip.mp4 --output clip-cut.mp4 --start 3 --duration 10 with ffmpeg. Use explicit output paths.'),
'scripting':('Shell and Python scripting, linting and verification', 'Use run.py --file script.sh or run.py --file script.py to check syntax. Never execute untrusted scripts merely to lint.'),
'transcription':('Local audio transcription and speech-to-text', 'Use run.py --file audio.wav --output transcript.txt; the preinstalled tiny Faster-Whisper model works on CPU.'),
}
desc,body=info[group]
(d/'SKILL.md').write_text(f'---\nname: {name}\ndescription: {desc}.\n---\n\n{body}\nExecute with the checked environment: `{interpreter} {d / "run.py"} --check`, then replace `--check` with the flags above.\n',encoding='utf-8')
(d/'run.py').write_text('''#!/usr/bin/env python3
import argparse,subprocess,sys
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--file');p.add_argument('--input');p.add_argument('--output');p.add_argument('--text');p.add_argument('--width',type=int);p.add_argument('--start',type=float,default=0);p.add_argument('--duration',type=float)
a=p.parse_args();group='''+repr(group)+'''
if group=='office':
    import docx,pptx,openpyxl,pypdf,reportlab
    if a.check: print('Office document libraries ready');sys.exit(0)
    if not a.output: p.error('--output required')
    out=Path(a.output)
    if a.input:
        inp=Path(a.input)
        if out.suffix.lower()!='.txt': p.error('extraction output must be .txt')
        if inp.suffix.lower()=='.docx': content='\\n'.join(q.text for q in docx.Document(inp).paragraphs)
        elif inp.suffix.lower()=='.pdf': content='\\n'.join(pg.extract_text() or '' for pg in pypdf.PdfReader(inp).pages)
        elif inp.suffix.lower()=='.pptx': content='\\n'.join(shape.text for slide in pptx.Presentation(inp).slides for shape in slide.shapes if shape.has_text_frame)
        elif inp.suffix.lower()=='.xlsx':
            wb=openpyxl.load_workbook(inp,read_only=True,data_only=True)
            content='\\n'.join('\\t'.join('' if cell is None else str(cell) for cell in row) for sh in wb for row in sh.values)
            wb.close()
        else: p.error('supported input: .docx/.pdf/.pptx/.xlsx')
        out.write_text(content+'\\n',encoding='utf-8')
    else:
        if a.text is None: p.error('provide --text or --input')
        lines=a.text.splitlines() or [a.text]
        if out.suffix.lower()=='.docx':
            d=docx.Document()
            for line in lines: d.add_paragraph(line)
            d.save(out)
        elif out.suffix.lower()=='.xlsx':
            wb=openpyxl.Workbook();ws=wb.active
            for line in lines: ws.append(line.split('\\t'))
            wb.save(out)
        elif out.suffix.lower()=='.pptx':
            deck=pptx.Presentation()
            for line in lines:
                slide=deck.slides.add_slide(deck.slide_layouts[5]);slide.shapes.title.text=line
            deck.save(out)
        elif out.suffix.lower()=='.pdf':
            from reportlab.pdfgen import canvas
            page=canvas.Canvas(str(out)); y=page._pagesize[1]-72
            for line in lines:
                if y<72: page.showPage();y=page._pagesize[1]-72
                page.drawString(72,y,line[:120]);y-=18
            page.save()
        else: p.error('supported output: .docx/.xlsx/.pptx/.pdf')
    print(out)
elif group=='photo-edit':
    from PIL import Image
    if a.check: print('Pillow ready');sys.exit(0)
    if not a.input or not a.output: p.error('--input and --output required')
    with Image.open(a.input) as im:
        if a.width: im=im.resize((a.width,round(im.height*a.width/im.width)))
        im.save(a.output)
    print(a.output)
elif group=='video-edit':
    import shutil
    if not shutil.which('ffmpeg'): raise SystemExit('ffmpeg missing')
    if a.check: print('FFmpeg ready');sys.exit(0)
    if not a.input or not a.output: p.error('--input and --output required')
    cmd=['ffmpeg','-hide_banner','-y','-ss',str(a.start),'-i',a.input]
    if a.duration: cmd+=['-t',str(a.duration)]
    subprocess.run(cmd+['-c:v','libx264','-c:a','aac',a.output],check=True)
    print(a.output)
elif group=='scripting':
    import shutil
    if not shutil.which('shellcheck'): raise SystemExit('shellcheck missing')
    if a.check: print('Scripting tools ready');sys.exit(0)
    if not a.file: p.error('--file required')
    if a.file.endswith(('.sh','.bash')): subprocess.run(['shellcheck',a.file],check=True)
    elif a.file.endswith('.py'): subprocess.run([sys.executable,'-m','py_compile',a.file],check=True)
    else: p.error('supported: .sh/.bash/.py')
else:
    from faster_whisper import WhisperModel
    if a.check: print('Faster-Whisper installed; tiny weights downloaded during setup');sys.exit(0)
    if not a.file: p.error('--file required')
    model=WhisperModel('tiny',device='cpu',compute_type='int8')
    segments,_=model.transcribe(a.file)
    text='\\n'.join(s.text.strip() for s in segments)
    if a.output: Path(a.output).write_text(text+'\\n',encoding='utf-8')
    else: print(text)
''',encoding='utf-8')
PY_FAVE_SKILL
    dependency_repair_python_command "$VENV_PY" "$root/run.py" --check || return 1
    SKILLS_SYNC_DEFER_RESTART=1 skills_sync_installed_skill_to_odysseus "$root" '' || return 1
    AUTO_FIT_SKILLS_SYNCED=1
    echo "    [ready] Personal favorite skill: $group"
}

skills_auto_resolve_dependencies() {
    local requested="${1:-}" skill_root="" slug="${2:-}" deps_rc=0
    [[ -n "$requested" ]] || return 0
    skill_root="$(skills_find_installed_root "$requested" "$slug" 2>/dev/null || true)"
    if [[ -z "$skill_root" || ! -f "$skill_root/SKILL.md" ]]; then
        echo "    [error] Could not locate installed SKILL.md for dependency inspection."
        return 1
    fi

    echo
    echo "SKILL DEPENDENCY AUTO-SETUP"
    echo "============================"
    echo "Skill path: $skill_root"
    skills_install_declared_system_packages "$skill_root" || deps_rc=$?
    skills_install_skill_manifests "$skill_root" || deps_rc=$?
    skills_auth_prerequisites "$skill_root" || deps_rc=$?

    # Playwright skills commonly need browsers after their Node package is
    # present. Install Chromium only when the skill explicitly mentions the
    # Playwright browser installer command.
    if grep -Eiq 'playwright[[:space:]]+install' "$skill_root/SKILL.md" && command -v npx >/dev/null 2>&1; then
        if ! npx playwright install chromium; then
            echo "    [warning] Playwright Chromium installation failed."
            deps_rc=1
        fi
    fi

    if (( deps_rc == 0 )); then
        echo "    [ready] Skill dependency checks completed."
    else
        echo "    [error] One or more declared skill dependencies could not be installed."
    fi
    return "$deps_rc"
}


skills_repair_audit_runtime() {
    # Skills testing/auditing uses Zarzysseus's Utility model, not necessarily the
    # model visible in the active chat. If Utility still points at a dead local
    # runtime (for example an old vLLM endpoint on :8000) while Default is live,
    # audits fail with a 503 even though the skill itself is valid. Repair only
    # that stale Utility mapping; never change the user's Default model here.
    local py="$VENV_DIR/bin/python"
    [[ -x "$py" ]] || return 0
    [[ -d "$PROJECT_DIR" ]] || return 0

    (cd "$PROJECT_DIR" && "$py" - "$ODYSSEUS_DATA_DIR" <<'PY_SKILL_AUDIT_RUNTIME'
import json
import os
import sys
from pathlib import Path

data_dir = Path(sys.argv[1]).expanduser().resolve()

owner = ""
auth_path = data_dir / "auth.json"
try:
    auth = json.loads(auth_path.read_text(encoding="utf-8"))
    users = auth.get("users", {}) if isinstance(auth, dict) else {}
    if isinstance(users, dict):
        admins = [str(u) for u, row in users.items() if isinstance(row, dict) and row.get("is_admin")]
        owner = (admins[0] if admins else (next(iter(users), ""))).strip()
except Exception:
    pass

try:
    from src.endpoint_resolver import resolve_endpoint
    from src.llm_core import list_model_ids
    from src.settings import load_settings, save_settings
except Exception as exc:
    print(f"    [note] Skill audit runtime check skipped: {exc}")
    raise SystemExit(0)

def probe(kind):
    try:
        url, model, headers = resolve_endpoint(kind, owner=owner or None)
    except Exception as exc:
        return False, "", "", f"resolve failed: {exc}"
    if not url or not model:
        return False, url or "", model or "", "not configured"
    try:
        models = list_model_ids(url, headers=headers) or []
    except Exception as exc:
        return False, url, model, str(exc)
    if not models:
        return False, url, model, "endpoint returned no models"
    if model in models:
        return True, url, model, ""
    base = os.path.basename(str(model).rstrip("/"))
    if any(os.path.basename(str(m).rstrip("/")) == base for m in models):
        return True, url, model, ""
    # The endpoint is reachable, even if its configured alias differs. Do not
    # rewrite a healthy Utility mapping just because model IDs are normalized.
    return True, url, model, ""

u_ok, u_url, u_model, u_err = probe("utility")
if u_ok:
    print(f"    [ready] Skill audit model is reachable: {u_model} @ {u_url}")
    raise SystemExit(0)

d_ok, d_url, d_model, d_err = probe("default")
if not d_ok:
    print(f"    [warning] Skill audit Utility model is unreachable: {u_model or '(unset)'} @ {u_url or '(unset)'}")
    print(f"    [warning] Default model is also unavailable, so audit routing was not changed: {d_err}")
    raise SystemExit(0)

settings = load_settings()
def_ep = str(settings.get("default_endpoint_id") or "").strip()
def_model = str(settings.get("default_model") or d_model or "").strip()
if not def_ep or not def_model:
    print("    [warning] Default endpoint is reachable but its settings entry could not be resolved; audit routing unchanged.")
    raise SystemExit(0)
settings["utility_endpoint_id"] = def_ep
settings["utility_model"] = def_model
save_settings(settings)
print(f"    [repair] Skill audit Utility model was stale/unreachable ({u_model or 'unset'} @ {u_url or 'unset'}).")
print(f"    [ready] Utility now follows the live Default model: {def_model} @ {d_url}")
PY_SKILL_AUDIT_RUNTIME
    ) || true
}

skills_sync_installed_skill_to_odysseus() {
    local skill_root="${1:-}" source_url="${2:-}"
    [[ -n "$skill_root" && -f "$skill_root/SKILL.md" ]] || {
        echo "    [warning] Installed skill path not found; Zarzysseus sync skipped."
        return 1
    }
    [[ -d "$PROJECT_DIR" ]] || {
        echo "    [warning] Zarzysseus project is not installed; Zarzysseus skill sync skipped."
        return 1
    }

    local py="$VENV_DIR/bin/python"
    if [[ ! -x "$py" ]]; then
        py="$(command -v python3 || true)"
    fi
    [[ -n "$py" ]] || {
        echo "    [warning] Python is unavailable; Zarzysseus skill sync skipped."
        return 1
    }

    echo
    echo "ZARZYSSEUS SKILL SYNC"
    echo "===================="
    echo "    Source skill: $skill_root"
    echo "    Destination: $ODYSSEUS_DATA_DIR/skills/imported/"

    # IMPORTANT: keep the external skill body byte-for-byte instead of round-
    # tripping it through Skill.to_markdown(). Zarzysseus's parser intentionally
    # understands a small set of headings; re-serializing an arbitrary skills.sh
    # document would otherwise erase unknown section headings and make complex
    # skills much less useful. We replace only the frontmatter needed by
    # Zarzysseus, preserve Agent Skills fields such as allowed-tools, copy the full
    # bundle, then validate through the real SkillsManager + prompt index.
    if "$py" - "$PROJECT_DIR" "$skill_root" "$ODYSSEUS_DATA_DIR" "$source_url" <<'PY_SYNC_SKILL'
from pathlib import Path
from datetime import datetime, timezone
import json
import os
import re
import shutil
import sys
import tempfile

project_dir = Path(sys.argv[1]).expanduser().resolve()
root = Path(sys.argv[2]).expanduser().resolve()
data_dir = Path(sys.argv[3]).expanduser().resolve()
source_url = sys.argv[4] if len(sys.argv) > 4 else ""
skill_md_path = root / "SKILL.md"
if not skill_md_path.is_file():
    raise RuntimeError(f"SKILL.md not found: {skill_md_path}")

# Import Zarzysseus exactly as the application does. This catches integration
# errors that a stand-alone skill_format import would miss.
sys.path.insert(0, str(project_dir))
os.chdir(project_dir)
from services.memory.skill_format import Skill, emit_frontmatter, parse_frontmatter, slugify
from services.memory.skills import SkillsManager

text = skill_md_path.read_text(encoding="utf-8", errors="replace")
fm, body = parse_frontmatter(text)
raw_name = fm.get("name") or root.name
name = slugify(raw_name, fallback="skill")
description = str(fm.get("description") or "").strip()
if not description:
    # Keep the index useful even for minimal Agent Skills.
    m = re.search(r"(?m)^#\s+(.+?)\s*$", body)
    description = (m.group(1).strip() if m else name.replace("-", " ").title())

def as_list(v):
    if v is None:
        return []
    if isinstance(v, list):
        return [str(x) for x in v if x not in (None, "")]
    return [str(v)]

owner = (os.environ.get("ZARZYSSEUS_SKILL_OWNER", "") or os.environ.get("ODYSSEUS_SKILL_OWNER", "")).strip()
if not owner:
    auth_path = data_dir / "auth.json"
    try:
        auth = json.loads(auth_path.read_text(encoding="utf-8"))
        users = auth.get("users", {}) if isinstance(auth, dict) else {}
        if isinstance(users, dict):
            admins = [str(u) for u, row in users.items() if isinstance(row, dict) and row.get("is_admin")]
            owner = (admins[0] if admins else (next(iter(users), ""))).strip()
    except Exception:
        owner = ""
if not owner:
    raise RuntimeError(
        "Could not determine the Zarzysseus account owner from data/auth.json. "
        "Log in once or set ZARZYSSEUS_SKILL_OWNER=<username>."
    )

try:
    confidence = float(fm.get("confidence", 1.0) or 1.0)
except (TypeError, ValueError):
    confidence = 1.0
confidence = max(0.0, min(1.0, confidence))

native_fm = {
    "name": name,
    "description": description,
    "version": str(fm.get("version", "1.0.0") or "1.0.0"),
    "category": "imported",
    "tags": as_list(fm.get("tags")),
    "platforms": as_list(fm.get("platforms")),
    "requires_toolsets": as_list(fm.get("requires_toolsets")),
    "fallback_for_toolsets": as_list(fm.get("fallback_for_toolsets")),
    "status": "published",
    "confidence": max(confidence, 1.0),
    "source": "imported",
    "owner": owner,
    "created": str(fm.get("created") or datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")),
}

# Preserve selected Agent Skills metadata that Zarzysseus does not model yet.
# Its parser safely ignores unknown keys, while other agents can still honor
# allowed-tools/compatibility when the same SKILL.md is inspected elsewhere.
raw_fm = ""
if text.startswith("---"):
    end = text.find("\n---", 3)
    if end >= 0:
        raw_fm = text[3:end].lstrip("\n")

preserved = []
lines = raw_fm.splitlines()
i = 0
while i < len(lines):
    line = lines[i]
    key_m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$", line)
    key = key_m.group(1).lower() if key_m else ""
    if key in {"allowed-tools", "allowed_tools", "compatibility", "license"}:
        preserved.append(line.rstrip())
        i += 1
        while i < len(lines):
            nxt = lines[i]
            if re.match(r"^[A-Za-z_][A-Za-z0-9_-]*\s*:", nxt) and not nxt.startswith((" ", "\t")):
                break
            preserved.append(nxt.rstrip())
            i += 1
        continue
    i += 1

front = emit_frontmatter(native_fm)
if preserved:
    front += "\n" + "\n".join(preserved)
native_md = f"---\n{front}\n---\n\n{body.rstrip()}\n"

# Parse once before touching the existing imported copy.
parsed = Skill.from_markdown(native_md)
if parsed.name != name or parsed.status != "published" or parsed.owner != owner:
    raise RuntimeError(
        f"Generated skill failed parser validation: name={parsed.name!r}, "
        f"status={parsed.status!r}, owner={parsed.owner!r}"
    )

imported_root = data_dir / "skills" / "imported"
imported_root.mkdir(parents=True, exist_ok=True)
final_dir = imported_root / name

# Repair transaction artifacts left by older installer versions. Those versions
# placed .<skill>.previous and .<skill>.import-* INSIDE data/skills/imported,
# which Zarzysseus recursively scans as real skills. A backup could therefore win
# name resolution over the live directory and make a perfectly good import look
# invalid. Recover a missing live copy from its backup, otherwise remove only the
# installer-owned legacy artifact.
def remove_path(path: Path):
    if not (path.exists() or path.is_symlink()):
        return
    if path.is_dir() and not path.is_symlink():
        shutil.rmtree(path)
    else:
        path.unlink()

for legacy_backup in list(imported_root.glob(".*.previous")):
    legacy_name = legacy_backup.name[1:-len(".previous")]
    if not legacy_name:
        continue
    live = imported_root / legacy_name
    if live.exists() or live.is_symlink():
        remove_path(legacy_backup)
    else:
        os.replace(legacy_backup, live)
for legacy_tmp in list(imported_root.glob(".*.import-*")):
    remove_path(legacy_tmp)

# Keep BOTH the staging copy and rollback copy completely outside data/skills.
# SkillsManager walks that tree recursively, so transaction directories must
# never live beneath it. data_dir is on the same filesystem in normal installs,
# preserving the atomic os.replace behavior used below.
txn_root = Path(tempfile.mkdtemp(prefix=f".skill-sync-{name}-", dir=str(data_dir)))
tmp_dir = txn_root / "new"
backup_dir = txn_root / "previous"
tmp_dir.mkdir(parents=True, exist_ok=True)
skipped_symlinks = 0
try:
    (tmp_dir / "SKILL.md").write_text(native_md, encoding="utf-8")
    for src in root.rglob("*"):
        rel = src.relative_to(root)
        if rel.as_posix().lower() == "skill.md":
            continue
        if src.is_symlink():
            skipped_symlinks += 1
            continue
        if src.is_dir():
            (tmp_dir / rel).mkdir(parents=True, exist_ok=True)
        elif src.is_file():
            dest = tmp_dir / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)

    # Atomic-ish replace with rollback. The backup is outside data/skills so it
    # is invisible to SkillsManager while the new copy is being validated.
    had_previous = final_dir.exists() or final_dir.is_symlink()
    if had_previous:
        os.replace(final_dir, backup_dir)
    os.replace(tmp_dir, final_dir)

    try:
        manager = SkillsManager(str(data_dir))
        visible = [s for s in manager.load(owner=owner) if s.get("name") == name]
        indexed = [s for s in manager.index_for(owner=owner) if s.get("name") == name]
        if not visible:
            raise RuntimeError("SkillsManager.load(owner=...) cannot see the imported skill")
        if not indexed:
            raise RuntimeError("SkillsManager.index_for(owner=...) did not publish the skill to the agent prompt index")
        stored_path = Path(visible[0].get("path") or "").resolve()
        expected = (final_dir / "SKILL.md").resolve()
        if stored_path != expected:
            raise RuntimeError(f"Zarzysseus resolved the skill from an unexpected path: {stored_path}")
        # Also prove that the full raw document — not a lossy reserialization —
        # is what skill_view will read from disk.
        raw_loaded = manager.read_skill_md(name, owner=owner)
        if not raw_loaded or body.strip() not in raw_loaded:
            raise RuntimeError("Zarzysseus could not read back the imported SKILL.md body")
    except Exception:
        remove_path(final_dir)
        if had_previous and (backup_dir.exists() or backup_dir.is_symlink()):
            os.replace(backup_dir, final_dir)
        raise
    else:
        remove_path(backup_dir)
finally:
    # Always remove the out-of-tree transaction directory. This also cleans the
    # staged copy if validation/copying failed before it was promoted.
    shutil.rmtree(txn_root, ignore_errors=True)

print(f"name={name}")
print("category=imported")
print(f"path={final_dir / 'SKILL.md'}")
print(f"owner={owner}")
print("status=published")
print("visible_in_zarzysseus=yes")
print("agent_prompt_index=yes")
if skipped_symlinks:
    print(f"note=skipped {skipped_symlinks} external symlink(s) for safety")
if source_url:
    print(f"source={source_url}")
PY_SYNC_SKILL
    then
        echo "    [ready] Skill is installed, visible to Zarzysseus, and present in the agent skill index."
        if [[ "${SKILLS_SYNC_DEFER_RESTART:-0}" != "1" ]]; then
            skills_repair_audit_runtime || true
            if service_installed 2>/dev/null && [[ "${SERVICE_MANAGER:-unknown}" == "systemd" ]]; then
                echo "    [odysseus] Restarting Zarzysseus so the new skill is loaded."
                if service_systemctl restart "$service_unit" >/dev/null 2>&1; then
                    echo "    [ready] Zarzysseus restarted; the imported skill is live."
                else
                    echo "    [warning] Zarzysseus restart failed. Restart it manually to reload the skill."
                fi
            else
                echo "    [note] Zarzysseus service is not installed/running; the skill will be picked up on next start."
            fi
        fi
    else
        echo "    [warning] Could not import the skill into Zarzysseus."
        echo "    [hint] The external skills.sh installation remains intact; the Python error above is the actual import failure."
        return 1
    fi
    return 0
}

skills_sync_all_installed_to_odysseus() {
    local root file skill_name skill_root real_file
    local -a roots=()
    [[ -d "$HOME/.agents/skills" ]] && roots+=("$HOME/.agents/skills")
    [[ -d "$HOME/.config/agents/skills" ]] && roots+=("$HOME/.config/agents/skills")
    [[ -d "$HOME/.claude/skills" ]] && roots+=("$HOME/.claude/skills")
    [[ -d "$HOME/.cursor/skills" ]] && roots+=("$HOME/.cursor/skills")
    [[ -d "$HOME/.codex/skills" ]] && roots+=("$HOME/.codex/skills")
    [[ -d "$HOME/.config/opencode/skills" ]] && roots+=("$HOME/.config/opencode/skills")
    [[ -d "$HOME/.astrbot/data/skills" ]] && roots+=("$HOME/.astrbot/data/skills")
    [[ -d "$HOME/.hermes/skills" ]] && roots+=("$HOME/.hermes/skills")
    [[ -d "$HOME/.config/zed/skills" ]] && roots+=("$HOME/.config/zed/skills")

    local count=0 failed=0
    declare -A seen_skill_paths=()
    for root in "${roots[@]}"; do
        while IFS= read -r -d '' file; do
            real_file="$(readlink -f "$file" 2>/dev/null || printf '%s' "$file")"
            [[ -n "${seen_skill_paths[$real_file]:-}" ]] && continue
            seen_skill_paths["$real_file"]=1

            skill_root="$(dirname "$file")"
            skill_name="$(python3 - "$file" <<'PY_SYNC_NAME' 2>/dev/null || true
import re, sys
from pathlib import Path
text=Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')
m=re.search(r'^---\s*(.*?)\s*---', text, re.M|re.S)
if m:
    x=re.search(r'^name\s*:\s*["\']?(.*?)["\']?\s*$', m.group(1), re.M|re.I)
    if x: print(x.group(1).strip())
PY_SYNC_NAME
)"
            skill_name="${skill_name:-$(basename "$skill_root")}"
            if SKILLS_SYNC_DEFER_RESTART=1 skills_sync_installed_skill_to_odysseus "$skill_root" ""; then
                ((count+=1))
            else
                ((failed+=1))
            fi
        done < <(find "$root" -mindepth 2 -maxdepth 4 -type f -name SKILL.md -print0 2>/dev/null)
    done

    if (( count > 0 )); then
        skills_repair_audit_runtime || true
        if service_installed 2>/dev/null && [[ "${SERVICE_MANAGER:-unknown}" == "systemd" ]]; then
            echo "    [odysseus] Restarting Zarzysseus once after skill synchronization."
            if service_systemctl restart "$service_unit" >/dev/null 2>&1; then
                echo "    [ready] Zarzysseus restarted; synchronized skills are live."
            else
                echo "    [warning] Zarzysseus restart failed. Restart it manually to reload synchronized skills."
            fi
        fi
    fi

    echo "    [ready] Resynced $count installed skill(s) into Zarzysseus."
    if (( failed > 0 )); then
        echo "    [warning] $failed skill(s) failed Zarzysseus validation/import. See the errors above."
        return 1
    fi
    return 0
}

skills_repair_generated_auto_fit_dependencies() {
    # Generated skills live under project data, not the global skills CLI store.
    # Re-evaluate the real model metadata; never install from arbitrary model cards.
    local file kind repo root failed=0
    [[ -d "$AUTO_FIT_SKILL_DIR" ]] || return 0
    [[ -x "$VENV_PY" ]] || { echo 'ERROR: Zarzysseus Python environment is missing; install the stack first.'; return 1; }
    while IFS= read -r -d '' file; do
        root="$(dirname "$file")"
        [[ -f "$root/SKILL.md" && -f "$root/run.py" ]] || continue
        kind="$("$VENV_PY" -c 'import json,sys;print(json.load(open(sys.argv[1])).get("kind",""))' "$file")" || { failed=1; continue; }
        repo="$("$VENV_PY" -c 'import json,sys;print(json.load(open(sys.argv[1])).get("repo",""))' "$file")" || { failed=1; continue; }
        echo "==> Repairing selected $kind model skill: $repo"
        if [[ "$kind" == audio ]]; then
            auto_fit_audio_dependencies || { failed=1; continue; }
        else
            auto_fit_prepare_dependencies "$kind" || { failed=1; continue; }
            auto_fit_prepare_model_dependencies "$kind" "$repo" || { failed=1; continue; }
        fi
        skills_install_skill_manifests "$root" || { failed=1; continue; }
        if [[ "$kind" == text ]]; then
            dependency_repair_python_command "$VENV_PY" "$root/run.py" --check ||
                echo "    [note] Text model requires its local endpoint to be running."
        else
            dependency_repair_python_command "$VENV_PY" "$root/run.py" --check || failed=1
        fi
    done < <(find "$AUTO_FIT_SKILL_DIR" -mindepth 2 -maxdepth 2 -type f -name model.json -print0 2>/dev/null)
    (( failed == 0 ))
}

skills_auto_resolve_all_installed_dependencies() {
    local root file skill_name failed=0
    local -a roots=()
    [[ -d "$HOME/.agents/skills" ]] && roots+=("$HOME/.agents/skills")
    [[ -d "$HOME/.config/agents/skills" ]] && roots+=("$HOME/.config/agents/skills")
    [[ -d "$HOME/.astrbot/data/skills" ]] && roots+=("$HOME/.astrbot/data/skills")
    [[ -d "$HOME/.hermes/skills" ]] && roots+=("$HOME/.hermes/skills")
    [[ -d "$HOME/.config/zed/skills" ]] && roots+=("$HOME/.config/zed/skills")
    for root in "${roots[@]}"; do
        while IFS= read -r -d '' file; do
            skill_name="$(python3 - "$file" <<'PY_SKILL_NAME_ALL' 2>/dev/null || true
import re, sys
from pathlib import Path
text=Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')
m=re.search(r'^---\s*(.*?)\s*---', text, re.M|re.S)
if m:
    x=re.search(r'^name\s*:\s*["\']?(.*?)["\']?\s*$', m.group(1), re.M|re.I)
    if x:
        print(x.group(1).strip())
PY_SKILL_NAME_ALL
)"
            skill_name="${skill_name:-$(basename "$(dirname "$file")")}"
            skills_auto_resolve_dependencies "$skill_name" "$(basename "$(dirname "$file")")" || failed=1
        done < <(find "$root" -mindepth 2 -maxdepth 4 -type f -name SKILL.md -print0 2>/dev/null)
    done
    skills_repair_generated_auto_fit_dependencies || failed=1
    if [[ -d "$AUTO_FIT_SKILL_DIR" ]]; then
        while IFS= read -r -d '' file; do
            root="$(dirname "$file")"
            [[ -f "$root/run.py" ]] || continue
            [[ -f "$root/model.json" ]] && continue
            skills_install_skill_manifests "$root" || failed=1
            skills_auth_prerequisites "$root" || failed=1
            dependency_repair_python_command "$VENV_PY" "$root/run.py" --check || failed=1
        done < <(find "$AUTO_FIT_SKILL_DIR" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print0 2>/dev/null)
    fi
    if (( failed )); then
        echo 'ERROR: One or more installed skills have incomplete dependencies.'
        return 1
    fi
}

skills_run_install() {
    local npx_bin="$1" slug_hint="${2:-}"
    shift 2
    local rc skill_root
    skills_cli_global_add "$npx_bin" "$@"
    rc=$?
    if (( rc == 0 )); then
        if ! skills_auto_resolve_dependencies "$slug_hint" "$slug_hint"; then
            echo 'ERROR: Skill installed, but its dependencies are incomplete; refusing ready/synced status.'
            return 1
        fi
        skill_root="$(skills_find_installed_root "$slug_hint" "$slug_hint" 2>/dev/null || true)"
        if [[ -n "$skill_root" ]]; then
            skills_sync_installed_skill_to_odysseus "$skill_root" "${SKILLS_CURRENT_SOURCE_URL:-}" || return 1
        else
            echo "ERROR: Installed skill path could not be found for Zarzysseus sync."
            return 1
        fi
    fi
    return "$rc"
}

skills_install() {
    local input="${1:-}" npx_bin parsed kind source slug repo_url skill_id
    SKILLS_CURRENT_SOURCE_URL=""
    [[ -n "$input" ]] || { echo "Usage: $0 skills-install <skill-name|skills.sh URL|GitHub repo|skill URL>"; return 2; }
    skills_cli_check >/dev/null || return 1
    npx_bin="$(skills_cli_npx)" || return 1

    if [[ "$input" =~ ^https?://skills\.sh/ ]]; then
        parsed="$(skills_resolve_sh_url "$input" 2>/dev/null || true)"
        if [[ "$parsed" == PACK$'\t'* ]]; then
            local pack_url="${parsed#*$'\t'}"
            echo "==> Installing skills pack: $pack_url"
            skills_cli_global_add "$npx_bin" "$pack_url" || return 1
            skills_auto_resolve_all_installed_dependencies || return 1
            skills_sync_all_installed_to_odysseus
        fi
        if [[ "$parsed" == GITHUB_SKILL$'\t'* ]]; then
            IFS=$'\t' read -r kind repo_url slug <<< "$parsed"
            repo_url="https://github.com/$repo_url"
            echo "==> Installing skill '$slug' from $repo_url"
            SKILLS_CURRENT_SOURCE_URL="$repo_url" skills_run_install "$npx_bin" "$slug" "$repo_url" --skill "$slug" "$SKILLS_INSTALL_SCOPE" -y
            return $?
        fi
        if [[ "$parsed" == SOURCE_SKILL$'\t'* ]]; then
            IFS=$'\t' read -r kind source slug <<< "$parsed"
            echo "==> Installing skill '$slug' from source $source"
            SKILLS_CURRENT_SOURCE_URL="https://github.com/$source" skills_run_install "$npx_bin" "$slug" "$source" --skill "$slug" "$SKILLS_INSTALL_SCOPE" -y
            return $?
        fi
        echo "ERROR: Unrecognized skills.sh URL: $input"
        return 2
    fi

    if [[ "$input" =~ ^https?://github\.com/ ]]; then
        if [[ "$input" == */tree/* || "$input" == */blob/* ]]; then
            echo "==> Installing GitHub skill/path: $input"
            SKILLS_CURRENT_SOURCE_URL="$input" skills_run_install "$npx_bin" "$(basename "${input%/}")" "$input" "$SKILLS_INSTALL_SCOPE" -y
        else
            echo "==> Installing all skills from GitHub repository: $input"
            skills_cli_global_add "$npx_bin" "$input" --skill "*" || return 1
            skills_auto_resolve_all_installed_dependencies || return 1
            skills_sync_all_installed_to_odysseus
        fi
        return $?
    fi

    if [[ "$input" =~ ^[^/[:space:]]+/[^/[:space:]]+@[^[:space:]]+$ ]]; then
        echo "==> Installing skill source: $input"
        slug="${input##*@}"
        SKILLS_CURRENT_SOURCE_URL="https://github.com/${input%%@*}" skills_run_install "$npx_bin" "$slug" "$input" "$SKILLS_INSTALL_SCOPE" -y
        return $?
    fi

    if [[ "$input" =~ ^[^/[:space:]]+/[^/[:space:]]+/[^/[:space:]]+$ ]]; then
        IFS='/' read -r source repo slug <<< "$input"
        echo "==> Installing indexed skill: $input"
        SKILLS_CURRENT_SOURCE_URL="https://github.com/$source/$repo" skills_run_install "$npx_bin" "$slug" "$source/$repo" --skill "$slug" "$SKILLS_INSTALL_SCOPE" -y
        return $?
    fi

    if [[ "$input" =~ ^[^/[:space:]]+/[^/[:space:]]+$ ]]; then
        echo "==> Installing all skills from GitHub repository: $input"
        skills_cli_global_add "$npx_bin" "$input" --skill "*"
        local rc=$?
        if (( rc == 0 )); then
            skills_auto_resolve_all_installed_dependencies || return 1
            skills_sync_all_installed_to_odysseus || return 1
        fi
        return "$rc"
    fi

    # Bare skill name: resolve it through the skills.sh registry first.
    if skill_id="$(skills_resolve_name_to_id "$input")"; then
        :
    else
        local resolve_rc=$?
        if (( resolve_rc == 2 )); then
            echo "Enter the exact skills.sh ID (source/repo/skill) to install, or press Enter to cancel:"
            read -r skill_id
            [[ -n "$skill_id" ]] || { echo "Install cancelled."; return 0; }
            if [[ "$skill_id" =~ ^[^/[:space:]]+/[^/[:space:]]+/[^/[:space:]]+$ ]]; then
                IFS='/' read -r source repo slug <<< "$skill_id"
                SKILLS_CURRENT_SOURCE_URL="https://github.com/$source/$repo" skills_run_install "$npx_bin" "$slug" "$source/$repo" --skill "$slug" "$SKILLS_INSTALL_SCOPE" -y
            else
                echo "ERROR: Expected source/repo/skill."
                return 2
            fi
            return $?
        fi
        echo "ERROR: Skill '$input' was not found on skills.sh."
        return 1
    fi

    IFS='/' read -r source repo slug <<< "$skill_id"
    if [[ -n "$repo" && -n "$slug" ]]; then
        echo "==> Installing '$slug' from $source/$repo"
        SKILLS_CURRENT_SOURCE_URL="https://github.com/$source/$repo" skills_run_install "$npx_bin" "$slug" "$source/$repo" --skill "$slug" "$SKILLS_INSTALL_SCOPE" -y
    else
        IFS='/' read -r source slug <<< "$skill_id"
        echo "==> Installing '$slug' from source $source"
        SKILLS_CURRENT_SOURCE_URL="https://github.com/$source" skills_run_install "$npx_bin" "$slug" "$source" --skill "$slug" "$SKILLS_INSTALL_SCOPE" -y
    fi
}

skills_summary() {
    local input="${1:-}" parsed kind source slug skill_id summary name installs summary_text
    [[ -n "$input" ]] || { echo "Usage: $0 skills-summary <skill-name|skills.sh URL|source/slug>"; return 2; }
    command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required for skills.sh summary lookup."; return 1; }
    command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required for skills.sh summary lookup."; return 1; }

    if [[ "$input" =~ ^https?://skills\.sh/ ]]; then
        parsed="$(skills_resolve_sh_url "$input" 2>/dev/null || true)"
        if [[ "$parsed" == GITHUB_SKILL$'\t'* || "$parsed" == SOURCE_SKILL$'\t'* ]]; then
            skill_id="${input#https://skills.sh/}"
            skill_id="${skill_id#http://skills.sh/}"
            skill_id="${skill_id#/}"
        else
            echo "A pack does not have a single skill summary: $input"
            return 0
        fi
    elif [[ "$input" =~ ^[^/[:space:]]+/[^/[:space:]]+@[^[:space:]]+$ ]]; then
        skill_id="${input/@//}"
    elif [[ "$input" =~ ^[^/[:space:]]+/[^/[:space:]]+/[^/[:space:]]+$ ]]; then
        skill_id="$input"
    else
        skill_id="$(skills_resolve_name_to_id "$input")" || true
    fi

    [[ -n "$skill_id" ]] || { echo "ERROR: Could not resolve skill '$input'."; return 1; }
    if ! summary="$(skills_summary_by_id "$skill_id")"; then
        echo "ERROR: Could not retrieve skill details for: $skill_id"
        return 1
    fi
    IFS=$'\t' read -r name source installs summary_text <<< "$summary"
    echo "SKILLS.SH SKILL SUMMARY"
    echo "========================"
    echo "Name:       $name"
    echo "Source:     $source"
    echo "Installs:   $installs"
    echo "Skill ID:   $skill_id"
    echo "Page:       $SKILLS_API_BASE/$skill_id"
    echo "Summary:"
    echo "  ${summary_text:-No summary available.}"
}

skills_list() {
    local npx_bin
    npx_bin="$(skills_cli_npx)" || return 1
    "$npx_bin" -y skills list
}

skills_update() {
    local npx_bin
    npx_bin="$(skills_cli_npx)" || return 1
    echo "==> Updating installed skills"
    "$npx_bin" -y skills update
}

skills_skill_global_roots() {
    cat <<EOF_SKILL_ROOTS
$HOME/.agents/skills
$HOME/.config/agents/skills
$HOME/.gemini/antigravity/skills
$HOME/.gemini/antigravity-cli/skills
$HOME/.astrbot/data/skills
$HOME/.autohand-code/skills
$HOME/.augment/skills
$HOME/.bob/skills
$HOME/.claude/skills
$HOME/.openclaw/skills
$HOME/.codeartsdoer/skills
$HOME/.hermes/skills
$HOME/.inferencesh/skills
$HOME/.jazz/skills
$HOME/.junie/skills
$HOME/.iflow/skills
$HOME/.kilo/skills
$HOME/.kimchi/skills
$HOME/.kiro/skills
$HOME/.kode/skills
$HOME/.lingma/skills
$HOME/.mcpjam/skills
$HOME/.minimax/skills
$HOME/.vibe/skills
$HOME/.moxby/skills
$HOME/.mux/skills
$HOME/.config/opencode/skills
$HOME/.openhands/skills
$HOME/.ona/skills
$HOME/.pi/skills
$HOME/.qoder/skills
$HOME/.roo/skills
$HOME/.zencoder/skills
$HOME/.zen/skills
$HOME/.neovate/skills
$HOME/.pochi/skills
$HOME/.dexto/skills
$HOME/.cline/skills
$HOME/.kimi/skills
$HOME/.warp/skills
EOF_SKILL_ROOTS
}

skills_installed_catalog() {
    local -a roots=()
    mapfile -t roots < <(skills_skill_global_roots)
    python3 - "${roots[@]}" <<'PY_SKILLS_CATALOG'
import re, sys
from pathlib import Path

roots = [Path(x).expanduser() for x in sys.argv[1:] if x]
seen = set()

def frontmatter(text):
    m = re.match(r"(?s)^---\s*\n(.*?)\n---\s*\n?", text)
    if not m:
        return "", "", ""
    fm = m.group(1)
    name = desc = allowed = ""
    nm = re.search(r"(?im)^name\s*:\s*(?:['\"]([^'\"]+)['\"]|([^\n]+))$", fm)
    if nm: name = (nm.group(1) or nm.group(2) or "").strip()
    dm = re.search(r"(?im)^description\s*:\s*(?:['\"](.*?)['\"]|([^\n]+))$", fm)
    if dm: desc = (dm.group(1) or dm.group(2) or "").strip()
    am = re.search(r"(?im)^allowed-tools\s*:\s*(.*)$", fm)
    if am:
        allowed = am.group(1).strip()
        if allowed.startswith("["):
            allowed = " ".join(x.strip().strip('\\\"\\\'') for x in allowed.strip('[]').split(',') if x.strip())
    else:
        bm = re.search(r"(?ims)^allowed-tools\s*:\s*\n((?:\s+-\s+[^\n]+\n?)+)", fm)
        if bm:
            allowed = " ".join(re.sub(r"^\s*-\s*", "", x.strip()) for x in bm.group(1).splitlines() if x.strip())
    return name, desc, allowed

def clean(x):
    return " ".join(str(x).replace("\t", " ").replace("\r", " ").replace("\n", " ").split())

for root in roots:
    if not root.is_dir():
        continue
    try:
        for skill_md in root.glob("*/SKILL.md"):
            try:
                real = skill_md.resolve()
                key = str(real)
                if key in seen or not real.is_file():
                    continue
                text = real.read_text(encoding="utf-8", errors="replace")
                name, desc, allowed = frontmatter(text)
                name = name or skill_md.parent.name
                seen.add(key)
                print("\t".join([clean(name), str(real.parent), clean(desc), clean(allowed)]))
            except OSError:
                pass
    except OSError:
        pass
PY_SKILLS_CATALOG
}

skills_permission_find_root() {
    local requested="${1:-}" name path desc allowed
    [[ -n "$requested" ]] || return 1
    while IFS=$'\t' read -r name path desc allowed; do
        [[ -n "$name" && -n "$path" ]] || continue
        if [[ "${name,,}" == "${requested,,}" || "$(basename "$path")" == "$requested" ]]; then
            printf '%s\n' "$path"
            return 0
        fi
    done < <(skills_installed_catalog)
    return 1
}

skills_permission_read() {
    local skill_root="$1" skill_md="$1/SKILL.md"
    [[ -f "$skill_md" ]] || return 1
    python3 - "$skill_md" <<'PY_SKILL_PERM_READ'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
m = re.match(r"(?s)^---\s*\n(.*?)\n---", text)
if not m:
    print("NOT DECLARED")
    raise SystemExit
fm = m.group(1)
am = re.search(r"(?im)^allowed-tools\s*:\s*(.*)$", fm)
if am:
    v = am.group(1).strip()
    if not v or v == "[]":
        print("NOT DECLARED")
    elif v.startswith("["):
        print(" ".join(x.strip().strip('\\\"\\\'') for x in v.strip('[]').split(',') if x.strip()))
    else:
        print(v)
    raise SystemExit
bm = re.search(r"(?ims)^allowed-tools\s*:\s*\n((?:\s+-\s+[^\n]+\n?)+)", fm)
if bm:
    print(" ".join(re.sub(r"^\s*-\s*", "", x.strip()) for x in bm.group(1).splitlines() if x.strip()))
else:
    print("NOT DECLARED")
PY_SKILL_PERM_READ
}

skills_permission_show() {
    local input="${1:-}" root name desc allowed
    [[ -n "$input" ]] || { echo "Usage: $0 skills-permissions <skill-name>"; return 2; }
    root="$(skills_permission_find_root "$input" 2>/dev/null || true)"
    [[ -n "$root" ]] || { echo "ERROR: Installed skill not found: $input"; return 1; }
    name="$(basename "$root")"
    while IFS=$'\t' read -r _name _path _desc _allowed; do
        if [[ "$_path" == "$root" ]]; then
            name="$_name"; desc="$_desc"; break
        fi
    done < <(skills_installed_catalog)
    allowed="$(skills_permission_read "$root")"
    echo "SKILL PERMISSIONS"
    echo "================="
    echo "Skill:       $name"
    echo "Path:        $root"
    echo "Description: ${desc:-No description available.}"
    if [[ "$allowed" == "NOT DECLARED" || -z "$allowed" ]]; then
        echo "Allowed:     NOT DECLARED (agent default behavior)"
    else
        echo "Allowed:     $allowed"
    fi
    echo
    echo "NOTE: allowed-tools is an experimental Agent Skills field; support varies by agent."
}

skills_permission_set() {
    local input="${1:-}" tools_raw="" root backup_dir backup_file
    [[ -n "$input" ]] || { echo "Usage: $0 skills-permissions-set <skill-name> <tool...>"; return 2; }
    shift
    tools_raw="$*"
    root="$(skills_permission_find_root "$input" 2>/dev/null || true)"
    [[ -n "$root" ]] || { echo "ERROR: Installed skill not found: $input"; return 1; }
    [[ -f "$root/SKILL.md" ]] || { echo "ERROR: Missing SKILL.md: $root"; return 1; }
    if [[ "$tools_raw" == *$'\n'* || "$tools_raw" == *$'\r'* || "$tools_raw" == *"---"* ]]; then
        echo "ERROR: Invalid permission value."; return 2
    fi
    backup_dir="${SKILLS_PERMISSION_BACKUP_DIR:-$HOME/.config/odysseus/skill-backups}"
    mkdir -p "$backup_dir"
    backup_file="$backup_dir/$(basename "$root")-$(date +%Y%m%d-%H%M%S).SKILL.md"
    cp -a "$root/SKILL.md" "$backup_file"
    python3 - "$root/SKILL.md" "$tools_raw" <<'PY_SKILL_PERM_SET'
import re, sys
from pathlib import Path
path = Path(sys.argv[1])
tools = sys.argv[2].strip()
text = path.read_text(encoding="utf-8", errors="replace")
m = re.match(r"(?s)^(---\s*\n)(.*?)(\n---\s*\n?)(.*)$", text)
if not m:
    raise SystemExit("SKILL.md does not have valid YAML frontmatter")
open_line, fm, close_line, body = m.groups()
fm = re.sub(r"(?im)^allowed-tools\s*:\s*[^\n]*\n?", "", fm)
fm = re.sub(r"(?ims)^allowed-tools\s*:\s*\n(?:\s+-\s+[^\n]*\n?)+", "", fm)
fm = fm.rstrip() + "\n"
if tools:
    fm += "allowed-tools: " + tools + "\n"
path.write_text(open_line + fm + close_line + body, encoding="utf-8")
PY_SKILL_PERM_SET
    echo "[saved] $root/SKILL.md"
    echo "[backup] $backup_file"
    echo "Allowed tools: ${tools_raw:-NOT DECLARED}"
}

skills_permission_clear() {
    skills_permission_set "$1"
}

skills_manage_list() {
    local rows count=0 name path desc allowed
    rows="$(skills_installed_catalog)"
    echo "INSTALLED AGENT SKILLS"
    echo "======================"
    if [[ -z "$rows" ]]; then
        echo "No globally installed skills were found."
        return 0
    fi
    printf '%-3s %-28s %-58s %-32s\n' '#' 'SKILL' 'PATH' 'ALLOWED TOOLS'
    printf '%-3s %-28s %-58s %-32s\n' '---' '----------------------------' '----------------------------------------------------------' '--------------------------------'
    while IFS=$'\t' read -r name path desc allowed; do
        [[ -n "$name" ]] || continue
        ((count+=1))
        [[ -n "$allowed" ]] || allowed='(not declared)'
        printf '%-3s %-28.28s %-58.58s %-32.32s\n' "$count" "$name" "$path" "$allowed"
    done <<< "$rows"
}

skills_manage_remove() {
    local input="${1:-}" npx_bin
    [[ -n "$input" ]] || { echo "Usage: $0 skills-remove <skill-name>"; return 2; }
    skills_cli_check >/dev/null || return 1
    npx_bin="$(skills_cli_npx)" || return 1
    echo "==> Removing installed skill: $input"
    "$npx_bin" -y skills remove --global "$input" -y
}

skills_manage_update_one() {
    local input="${1:-}" npx_bin rc
    [[ -n "$input" ]] || { echo "Usage: $0 skills-update-one <skill-name>"; return 2; }
    skills_cli_check >/dev/null || return 1
    npx_bin="$(skills_cli_npx)" || return 1
    echo "==> Updating installed skill: $input"
    "$npx_bin" -y skills update -g "$input" -y
    rc=$?
    if (( rc == 0 )); then
        skills_auto_resolve_dependencies "$input" "$input" || return 1
    fi
    return "$rc"
}

skills_manage_summary_installed() {
    local input="${1:-}" root desc allowed
    [[ -n "$input" ]] || { echo "Usage: $0 skills-summary-installed <skill-name>"; return 2; }
    root="$(skills_permission_find_root "$input" 2>/dev/null || true)"
    [[ -n "$root" ]] || { echo "ERROR: Installed skill not found: $input"; return 1; }
    desc="$(python3 - "$root/SKILL.md" <<'PY_SKILL_DESC' 2>/dev/null || true
import re,sys
from pathlib import Path
text=Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
m=re.match(r"(?s)^---\s*\n(.*?)\n---", text)
if m:
    x=re.search(r"(?im)^description\s*:\s*(?:['\"](.*?)['\"]|([^\n]+))$", m.group(1))
    if x: print((x.group(1) or x.group(2) or "").strip())
PY_SKILL_DESC
)"
    allowed="$(skills_permission_read "$root")"
    echo "INSTALLED SKILL DETAILS"
    echo "======================="
    echo "Name:        $(basename "$root")"
    echo "Path:        $root"
    echo "Summary:     ${desc:-No description available.}"
    echo "Permissions: ${allowed:-NOT DECLARED}"
    echo "Files:       $(find "$root" -type f 2>/dev/null | wc -l | tr -d ' ')"
}

declare -A SKILLS_NPM_READY=()
skills_npm_global_install_documented() {
    local spec="$1" package_name output rc=0
    [[ -n "$spec" ]] || return 0
    package_name="$spec"
    if [[ "$package_name" != @*/* ]]; then
        package_name="${package_name%%@*}"
    elif [[ "$package_name" == @*/*@* ]]; then
        package_name="${package_name%@*}"
    fi
    if [[ -n "${SKILLS_NPM_READY[$spec]:-}" ]]; then
        echo "    [ready] Already resolved this run: $spec"
        return 0
    fi
    # Reuse an existing fully installed CLI rather than reinstalling the same
    # npm package for each skill that documents it.
    if npm ls -g --depth=0 "$package_name" >/dev/null 2>&1; then
        case "$package_name" in
            @runcomfy/cli) command -v runcomfy >/dev/null 2>&1 || rc=1 ;;
            agent-browser) command -v agent-browser >/dev/null 2>&1 || rc=1 ;;
        esac
        if (( rc == 0 )); then
            SKILLS_NPM_READY["$spec"]=1
            echo "    [ready] Global npm dependency already installed: $spec"
            return 0
        fi
    fi
    rc=0
    echo "==> Installing documented global npm dependency: $spec"
    output="$(npm install -g "$spec" --no-audit --no-fund 2>&1)" || rc=$?
    printf '%s\n' "$output"
    if grep -Eiq 'install scripts blocked|postinstall:' <<< "$output"; then
        echo "==> npm blocked lifecycle scripts for $package_name; retrying only this documented dependency with --allow-scripts"
        if ! npm install -g --allow-scripts="$package_name" "$spec" --no-audit --no-fund; then
            echo "    [error] npm lifecycle repair failed for $package_name"
            return 1
        fi
        rc=0
    fi
    (( rc == 0 )) || return "$rc"
    if ! npm ls -g --depth=0 "$package_name" >/dev/null 2>&1; then
        echo "    [error] npm package missing after installation: $package_name"
        return 1
    fi
    SKILLS_NPM_READY["$spec"]=1
    return 0
}

# ------------------------------------------
# Full installation
# ------------------------------------------


find_npx() {
    command -v npx 2>/dev/null || command -v npx.cmd 2>/dev/null || true
}

install_node_if_missing() {
    local npx_bin
    npx_bin="$(find_npx)"
    if [[ -n "$npx_bin" ]]; then
        echo "    [installed] Node.js / npx ($npx_bin)"
        return 0
    fi

    if ! command -v npm >/dev/null 2>&1; then
        detect_linux_install
        installing "Node.js/npm"
        case "$PKG" in
            pacman|apt|dnf|dnf5|microdnf|yum|zypper|apk|xbps|eopkg|urpmi|tdnf|slackpkg|rpm-ostree)
                install_missing_packages nodejs npm
                ;;
            emerge)
                install_missing_packages net-libs/nodejs
                ;;
            nix)
                install_missing_packages nodejs
                ;;
            guix)
                install_missing_packages node
                ;;
            swupd)
                install_missing_packages nodejs-basic
                ;;
            *)
                echo "ERROR: Node.js/npm is required, but no supported package manager was detected."
                return 1
                ;;
        esac
    fi

    npx_bin="$(find_npx)"
    [[ -n "$npx_bin" ]] || { echo "ERROR: Node.js installed but npx was not found."; return 1; }
}

install_playwright_tool() {
    info "Checking Playwright browser tool..."
    mkdir -p "$PLAYWRIGHT_BROWSERS_DIR"
    export ODYSSEUS_BROWSER_MCP_CACHE="$PLAYWRIGHT_CACHE_DIR"
    export XDG_CACHE_HOME="$PLAYWRIGHT_CACHE_DIR"
    export PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_DIR"
    install_node_if_missing
    local npx_bin
    npx_bin="$(find_npx)"
    "$npx_bin" -y @playwright/mcp@latest --version
    info "Checking Playwright Chromium browser..."
    "$npx_bin" -y playwright install chromium
    echo "    [installed] Playwright MCP + Chromium"
}

# ------------------------------------------
# Hardware / accelerator detection + provisioning
# ------------------------------------------

read_os_release() {
    OS_ID="${DISTRO_ID:-unknown}"
    OS_VERSION_ID="${DISTRO_VERSION_ID:-unknown}"
    OS_CODENAME="${DISTRO_VERSION_CODENAME:-}"
    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-${DISTRO_ID:-unknown}}"
        OS_VERSION_ID="${VERSION_ID:-${DISTRO_VERSION_ID:-unknown}}"
        OS_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-${DISTRO_VERSION_CODENAME:-}}}"
    fi
}

lspci_gpu_lines() {
    if command -v lspci >/dev/null 2>&1; then
        lspci -nn 2>/dev/null | grep -Ei 'VGA compatible controller|3D controller|Display controller' || true
    fi
}

map_amd_gfx_arch() {
    local name="${1,,}"
    case "$name" in
        *"rx 7900 xtx"*|*"rx 7900 xt"*|*"rx 7900 gre"*|*"rx 7900"*) echo "gfx1100" ;;
        *"rx 7800 xt"*|*"rx 7700 xt"*|*"rx 7700"*) echo "gfx1101" ;;
        *"rx 7600"*) echo "gfx1102" ;;
        *"rx 9070 xt"*) echo "gfx1201" ;;
        *"rx 9070"*) echo "gfx1201" ;;
        *"rx 9060 xt"*|*"rx 9060"*) echo "gfx1200" ;;
        *"rx 6800"*|*"rx 6900"*|*"rx 6700"*|*"rx 6600"*) echo "gfx1030" ;;
        *"radeon pro w7900"*|*"radeon pro w7800"*) echo "gfx1100" ;;
        *) echo "unknown" ;;
    esac
}

detect_accelerator() {
    read_os_release
    GPU_VENDOR="unknown"
    GPU_NAME="unknown"
    GPU_ARCH="unknown"
    GPU_PCI_ID="unknown"
    GPU_DRIVER_VERSION="unknown"
    ACCELERATOR_BACKEND="cpu"

    local lines nline amd_line nvidia_line intel_line preference
    lines="$(lspci_gpu_lines)"
    amd_line="$(printf '%s\n' "$lines" | grep -Ei 'AMD/ATI|Advanced Micro Devices' | head -n1 || true)"
    nvidia_line="$(printf '%s\n' "$lines" | grep -Ei 'NVIDIA' | head -n1 || true)"
    intel_line="$(printf '%s\n' "$lines" | grep -Ei 'Intel Corporation|Intel\(R\)|Intel Graphics|Intel Arc' | head -n1 || true)"
    preference="${ACCELERATOR_PREFERENCE,,}"
    case "$preference" in
        cpu) ACCELERATOR_BACKEND="cpu" ;;
        amd|rocm) [[ -z "$amd_line" ]] || ACCELERATOR_BACKEND="amd_rocm" ;;
        nvidia|cuda) [[ -z "$nvidia_line" ]] || ACCELERATOR_BACKEND="nvidia_cuda" ;;
        intel|xpu|oneapi) [[ -z "$intel_line" ]] || ACCELERATOR_BACKEND="intel_xpu" ;;
        auto|"")
            # Prefer discrete GPUs; an Intel iGPU does not mask NVIDIA/AMD.
            if [[ -n "$nvidia_line" ]]; then ACCELERATOR_BACKEND="nvidia_cuda"
            elif [[ -n "$amd_line" ]]; then ACCELERATOR_BACKEND="amd_rocm"
            elif [[ -n "$intel_line" ]]; then ACCELERATOR_BACKEND="intel_xpu"
            fi ;;
        *) echo "    [warning] Unknown ACCELERATOR_PREFERENCE=$ACCELERATOR_PREFERENCE; using CPU." >&2 ;;
    esac

    case "$ACCELERATOR_BACKEND" in
        amd_rocm) GPU_VENDOR="AMD"; nline="$amd_line"; GPU_ARCH="$(map_amd_gfx_arch "$nline")" ;;
        nvidia_cuda) GPU_VENDOR="NVIDIA"; nline="$nvidia_line" ;;
        intel_xpu) GPU_VENDOR="Intel"; nline="$intel_line" ;;
        *) nline="" ;;
    esac
    if [[ -n "$nline" ]]; then
        GPU_NAME="$(printf '%s\n' "$nline" | sed 's/^[[:space:]]*//')"
        GPU_PCI_ID="$(printf '%s\n' "$nline" | grep -oE '\[[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}\]' | tail -n1 | tr -d '[]' || true)"
    fi
    if [[ "$ACCELERATOR_BACKEND" == "nvidia_cuda" ]] && command -v nvidia-smi >/dev/null 2>&1; then
        GPU_DRIVER_VERSION="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -n1 || true)"
    elif [[ "$ACCELERATOR_BACKEND" == "amd_rocm" ]] && command -v rocminfo >/dev/null 2>&1; then
        GPU_DRIVER_VERSION="$(rocminfo 2>/dev/null | awk -F': ' '/^  Runtime Version:/ {print $2; exit}')"
    fi
}

rocm_full_stack_packages() {
    cat <<'EOF_ROCM_PKGS'
hip-runtime-amd
rocminfo
rocm-hip-runtime
rocm-hip-sdk
rocm-hip-libraries
rocm-ml-libraries
rocm-ml-sdk
miopen-hip
rocprofiler
rocprofiler-register
roctracer
hipfft
hipblas
hipblaslt
hiprand
hipcub
hipsolver
hipsparse
hipsparselt
rccl
rocrand
rocblas
rocfft
rocalution
rocsolver
rocsparse
rocprim
rocthrust
EOF_ROCM_PKGS
}

rocm_library_ready() {
    local root="${ROCM_PATH:-/opt/rocm}"
    [[ -e "$root/lib/libamdhip64.so" || -e "$root/lib/libamdhip64.so.6" || -e "$root/lib64/libamdhip64.so" ]] && return 0
    if command -v ldconfig >/dev/null 2>&1; then
        ldconfig -p 2>/dev/null | grep -q 'libamdhip64\.so' && return 0
    fi
    return 1
}

rocprofiler_sdk_runtime_ready() {
    local root="${ROCM_PATH:-/opt/rocm}"
    [[ -e "$root/lib/librocprofiler-sdk.so.1" ]] && return 0
    [[ -e "$root/lib64/librocprofiler-sdk.so.1" ]] && return 0
    if command -v ldconfig >/dev/null 2>&1; then
        ldconfig -p 2>/dev/null | grep -q 'librocprofiler-sdk\.so\.1 ' && return 0
    fi
    return 1
}

hipfft_runtime_ready() {
    local root="${ROCM_PATH:-/opt/rocm}"
    [[ -e "$root/lib/libhipfft.so.0" ]] && return 0
    [[ -e "$root/lib64/libhipfft.so.0" ]] && return 0
    if command -v ldconfig >/dev/null 2>&1; then
        ldconfig -p 2>/dev/null | grep -q 'libhipfft\.so\.0 ' && return 0
    fi
    return 1
}

rocm_critical_libraries_ready() {
    rocm_runtime_ready &&
    rocm_library_ready &&
    miopen_runtime_ready &&
    rocprofiler_sdk_runtime_ready &&
    hipfft_runtime_ready
}

install_arch_rocm_full_stack() {
    [[ "$PKG" == "pacman" ]] || return 0
    info "Checking complete AMD ROCm/HIP/ML userspace stack..."
    local packages=()
    mapfile -t packages < <(rocm_full_stack_packages)
    install_missing_packages "${packages[@]}"
    if command -v ldconfig >/dev/null 2>&1; then
        $SUDO ldconfig >/dev/null 2>&1 || true
    fi
}

rocm_runtime_ready() {
    local ri="${ROCM_PATH:-/opt/rocm}/bin/rocminfo"
    [[ -x "$ri" ]] || ri="$(command -v rocminfo 2>/dev/null || true)"
    [[ -n "$ri" ]] || return 1
    "$ri" >/dev/null 2>&1
}

roctx_runtime_ready() {
    local root="${ROCM_PATH:-/opt/rocm}" candidate=""
    for candidate in \
        "$root/lib/libroctx64.so.4" \
        "$root/lib64/libroctx64.so.4" \
        "/opt/rocm/lib/libroctx64.so.4" \
        "/opt/rocm/lib64/libroctx64.so.4"; do
        [[ -e "$candidate" ]] && return 0
    done
    if command -v ldconfig >/dev/null 2>&1; then
        ldconfig -p 2>/dev/null | grep -q 'libroctx64\.so\.4 ' && return 0
    fi
    return 1
}

miopen_runtime_ready() {
    local root="${ROCM_PATH:-/opt/rocm}" candidate=""
    for candidate in \
        "$root/lib/libMIOpen.so.1" \
        "$root/lib64/libMIOpen.so.1" \
        "/opt/rocm/lib/libMIOpen.so.1" \
        "/opt/rocm/lib64/libMIOpen.so.1"; do
        [[ -e "$candidate" ]] && return 0
    done
    if command -v ldconfig >/dev/null 2>&1; then
        ldconfig -p 2>/dev/null | grep -q 'libMIOpen\.so\.1 ' && return 0
    fi
    return 1
}

ensure_miopen_runtime() {
    [[ "$ACCELERATOR_BACKEND" == "amd_rocm" ]] || return 0
    if miopen_runtime_ready; then
        echo "    [installed] ROCm MIOpen (libMIOpen.so.1)"
        return 0
    fi

    info "Checking ROCm MIOpen runtime library..."
    case "$PKG" in
        pacman)
            # Arch packages AMD's HIP backend of MIOpen as miopen-hip.  When the
            # package database says it is installed but the SONAME is physically
            # missing, reinstall it instead of treating the package as healthy.
            if pkg_installed miopen-hip; then
                echo "    [repair] miopen-hip is installed but libMIOpen.so.1 is missing; reinstalling package files."
                $SUDO pacman -S --noconfirm miopen-hip || return 1
            else
                installing "miopen-hip"
                $SUDO pacman -S --needed --noconfirm miopen-hip || return 1
            fi
            ;;
        apt)
            # AMD's ROCm repositories expose the package as miopen-hip.
            if apt-cache show miopen-hip >/dev/null 2>&1; then
                install_missing_packages miopen-hip || return 1
            elif apt-cache show miopen-hip7.2 >/dev/null 2>&1; then
                install_missing_packages miopen-hip7.2 || return 1
            else
                echo "    [warning] No installable MIOpen package was found in the configured APT repositories."
                return 1
            fi
            ;;
        dnf|dnf5|microdnf|yum|zypper|tdnf)
            install_missing_packages miopen-hip || return 1
            ;;
        *)
            echo "    [warning] Cannot provision ROCm MIOpen automatically for package manager '$PKG'."
            return 1
            ;;
    esac

    # Refresh the dynamic linker cache when this machine manages /opt/rocm via
    # ld.so configuration. Do not require ldconfig to succeed; LD_LIBRARY_PATH
    # is also supplied to the isolated serving engines below.
    if command -v ldconfig >/dev/null 2>&1; then
        $SUDO ldconfig >/dev/null 2>&1 || true
    fi

    if miopen_runtime_ready; then
        echo "    [ready] ROCm MIOpen (libMIOpen.so.1)"
        return 0
    fi
    echo "    [failed] ROCm MIOpen library is still missing after package installation."
    return 1
}

ensure_roctx_runtime() {
    [[ "$ACCELERATOR_BACKEND" == "amd_rocm" ]] || return 0
    if roctx_runtime_ready; then
        echo "    [installed] ROCm tracer/ROCTX (libroctx64.so.4)"
        return 0
    fi

    info "Checking ROCm tracer/ROCTX runtime library..."
    case "$PKG" in
        pacman)
            # Arch ships libroctx64.so.4 in the roctracer package. If the
            # package is registered but the file is gone, reinstall it so the
            # installer can repair a partial ROCm upgrade.
            if pkg_installed roctracer; then
                echo "    [repair] roctracer is installed but libroctx64.so.4 is missing; reinstalling package files."
                $SUDO pacman -S --noconfirm roctracer || return 1
            else
                installing "roctracer"
                $SUDO pacman -S --needed --noconfirm roctracer || return 1
            fi
            ;;
        apt)
            # Ubuntu/Debian expose the runtime library as libroctx64-4 in
            # distro packages; AMD's ROCm repo may also provide roctracer.
            if apt-cache show libroctx64-4 >/dev/null 2>&1; then
                install_missing_packages libroctx64-4 || return 1
            elif apt-cache show roctracer >/dev/null 2>&1; then
                install_missing_packages roctracer || return 1
            else
                echo "    [warning] No installable ROCTX package was found in the configured APT repositories."
                return 1
            fi
            ;;
        dnf|dnf5|microdnf|yum|zypper|tdnf)
            install_missing_packages roctracer || return 1
            ;;
        *)
            echo "    [warning] Cannot provision ROCm tracer/ROCTX automatically for package manager '$PKG'."
            return 1
            ;;
    esac

    if command -v ldconfig >/dev/null 2>&1; then
        $SUDO ldconfig >/dev/null 2>&1 || true
    fi
    if roctx_runtime_ready; then
        echo "    [ready] ROCm tracer/ROCTX (libroctx64.so.4)"
        return 0
    fi
    echo "    [failed] ROCm tracer/ROCTX library is still missing after package installation."
    return 1
}

nvidia_driver_ready() {
    command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1
}

cuda_toolkit_ready() {
    local nvcc=""
    if [[ -n "${CUDA_HOME:-}" && -x "$CUDA_HOME/bin/nvcc" ]]; then
        nvcc="$CUDA_HOME/bin/nvcc"
    else
        nvcc="$(command -v nvcc 2>/dev/null || true)"
    fi
    [[ -n "$nvcc" ]] || return 1
    "$nvcc" --version >/dev/null 2>&1
}

# Level Zero + Intel compute runtime are required for native PyTorch XPU.
# Merely detecting an Intel display controller does not establish compute support.
intel_runtime_ready() {
    [[ "$ACCELERATOR_BACKEND" == "intel_xpu" ]] || return 1
    [[ -e /dev/dri/renderD128 || -n "$(find /dev/dri -maxdepth 1 -name 'renderD*' -print -quit 2>/dev/null)" ]] || return 1
    local loader=0 driver=0 path
    for path in /usr/lib/libze_loader.so.1 /usr/lib64/libze_loader.so.1 /usr/lib/x86_64-linux-gnu/libze_loader.so.1; do
        [[ ! -e "$path" ]] || loader=1
    done
    for path in /usr/lib/libze_intel_gpu.so.1 /usr/lib64/libze_intel_gpu.so.1 /usr/lib/x86_64-linux-gnu/libze_intel_gpu.so.1; do
        [[ ! -e "$path" ]] || driver=1
    done
    if command -v ldconfig >/dev/null 2>&1; then
        local cache
        cache="$(ldconfig -p 2>/dev/null || true)"
        [[ "$cache" != *libze_loader.so* ]] || loader=1
        [[ "$cache" != *libze_intel_gpu.so* ]] || driver=1
    fi
    (( loader && driver ))
}

ensure_accelerator_access() {
    local group
    for group in render video; do
        if getent group "$group" >/dev/null 2>&1; then
            if ! id -nG "$USER" 2>/dev/null | tr ' ' '\n' | grep -Fxq "$group"; then
                $SUDO usermod -aG "$group" "$USER" || return 1
                echo "    [login required] Added $USER to $group; log out and back in before GPU verification."
                mkdir -p "$(dirname "$ACCELERATOR_REBOOT_REQUIRED_FILE")"
                touch "$ACCELERATOR_REBOOT_REQUIRED_FILE"
            fi
        fi
    done
}

install_intel_system_stack() {
    info "Checking Intel GPU Level Zero / oneAPI compute runtime..."
    case "$PKG" in
        pacman)
            install_missing_packages intel-compute-runtime level-zero-loader intel-gmmlib intel-graphics-compiler || return 1
            ;;
        apt)
            # Never add an arbitrary/incorrect Intel repository to an unsupported distro.
            local pkg
            for pkg in intel-opencl-icd intel-level-zero-gpu level-zero; do
                if ! pkg_installed "$pkg" && ! apt-cache show "$pkg" >/dev/null 2>&1; then
                    echo "ERROR: $pkg is not available in the configured APT repositories."
                    echo "       Enable Intel's GPU compute repository for $OS_ID $OS_VERSION_ID, then retry."
                    return 1
                fi
            done
            install_missing_packages intel-opencl-icd intel-level-zero-gpu level-zero || return 1
            ;;
        dnf|dnf5|yum|zypper|microdnf|tdnf)
            echo "ERROR: Intel Level Zero package names/repositories for $OS_ID are not verified by this installer."
            echo "       Install your distro's Intel compute runtime and Level Zero loader, then retry."
            return 1
            ;;
        *)
            echo "ERROR: Automatic Intel XPU provisioning is unsupported by package manager '$PKG'."
            return 1
            ;;
    esac
    ensure_accelerator_access || return 1
    if intel_runtime_ready; then
        echo "    [ready] Intel Level Zero loader + compute driver + render device"
    else
        echo "ERROR: Intel Level Zero runtime not usable; check driver, supported GPU and render permissions."
        return 1
    fi
}

# Test a real allocation rather than trusting package metadata or just import torch.
# Exit nonzero for a missing driver, a wrong wheel, or a backend that cannot allocate.
accelerator_torch_test() {
    local py="${1:-$VENV_PY}" backend="${2:-$ACCELERATOR_BACKEND}"
    [[ -x "$py" ]] || return 1
    "$py" - "$backend" <<'PY_ACCEL_TORCH_TEST'
import sys
import torch
backend=sys.argv[1]
if backend == 'intel_xpu':
    assert hasattr(torch,'xpu') and torch.xpu.is_available(), 'XPU not available'
    device='xpu'
elif backend in ('amd_rocm','nvidia_cuda'):
    assert torch.cuda.is_available(), 'CUDA/HIP not available'
    if backend=='amd_rocm': assert torch.version.hip, 'Not an ROCm torch wheel'
    if backend=='nvidia_cuda': assert torch.version.cuda, 'Not a CUDA torch wheel'
    device='cuda'
else:
    device='cpu'
x=torch.ones(1, device=device)
assert float(x.sum().item())==1.0
print('    [verified] PyTorch',torch.__version__,device,'real tensor allocation')
PY_ACCEL_TORCH_TEST
}

configure_accelerator_environment() {
    detect_accelerator
    case "$ACCELERATOR_BACKEND" in
        amd_rocm)
            export ROCM_PATH="${ROCM_PATH:-/opt/rocm}"
            export HIP_PATH="$ROCM_PATH"
            export PATH="$ROCM_PATH/bin:$PATH"
            export LD_LIBRARY_PATH="$ROCM_PATH/lib:$ROCM_PATH/lib64:${LD_LIBRARY_PATH:-}"
            [[ "$GPU_ARCH" != "unknown" ]] && export PYTORCH_ROCM_ARCH="$GPU_ARCH"
            ;;
        nvidia_cuda)
            if [[ -z "${CUDA_HOME:-}" ]]; then
                for d in /usr/local/cuda /opt/cuda /opt/cuda-*; do
                    [[ -x "$d/bin/nvcc" ]] && { CUDA_HOME="$d"; break; }
                done
            fi
            export CUDA_HOME="${CUDA_HOME:-/usr/local/cuda}"
            export PATH="$CUDA_HOME/bin:$PATH"
            if [[ -d "$CUDA_HOME/lib64" ]]; then
                export LD_LIBRARY_PATH="$CUDA_HOME/lib64:${LD_LIBRARY_PATH:-}"
            fi
            ;;
    esac
}

install_rocm_system_stack() {
    info "Checking AMD ROCm system stack..."
    case "$PKG" in
        pacman)
            install_arch_rocm_full_stack
            ensure_accelerator_access || return 1
            ;;
        apt)
            local deb_url="" deb_file="/tmp/amdgpu-install_${ROCM_INSTALL_VERSION}_all.deb" codename=""
            case "$OS_ID:$OS_VERSION_ID" in
                ubuntu:24.04*) codename="noble" ;;
                ubuntu:22.04*) codename="jammy" ;;
                *) codename="" ;;
            esac
            if [[ -n "$codename" ]]; then
                deb_url="https://repo.radeon.com/amdgpu-install/${ROCM_VERSION}/ubuntu/${codename}/amdgpu-install_${ROCM_INSTALL_VERSION}_all.deb"
                info "Installing AMD amdgpu-install from $deb_url"
                curl -fL --retry 4 --retry-delay 2 -o "$deb_file" "$deb_url"
                $SUDO apt-get install -y "$deb_file"
                if [[ "$ROCM_AUTO_DRIVER" == "1" ]]; then
                    $SUDO amdgpu-install -y --usecase=graphics,rocm
                else
                    $SUDO amdgpu-install -y --usecase=rocm --no-dkms
                fi
            elif command -v amdgpu-install >/dev/null 2>&1; then
                $SUDO amdgpu-install -y --usecase=rocm --no-dkms
            else
                echo "    [warning] Automatic ROCm repo selection is not implemented for $OS_ID $OS_VERSION_ID."
                echo "              Install AMD's amdgpu-install package, then rerun: $0 accelerator-setup"
                return 1
            fi
            if getent group render >/dev/null 2>&1; then $SUDO usermod -aG render "$USER" || true; fi
            if getent group video >/dev/null 2>&1; then $SUDO usermod -aG video "$USER" || true; fi
            ;;
        dnf|dnf5|microdnf|yum|zypper|tdnf)
            if command -v amdgpu-install >/dev/null 2>&1; then
                $SUDO amdgpu-install -y --usecase=rocm --no-dkms
            else
                echo "    [warning] Please install AMD's official amdgpu-install package for $OS_ID $OS_VERSION_ID."
                return 1
            fi
            ;;
        *)
            echo "    [warning] ROCm system installation is unsupported on package manager '$PKG'."
            return 1
            ;;
    esac
    mkdir -p "$(dirname "$ACCELERATOR_STATE_FILE")"
    if rocm_critical_libraries_ready; then
        echo "    [ready] ROCm runtime + HIP + MIOpen + ROCprofiler SDK + HIPFFT detected"
        return 0
    fi
    echo "    [warning] ROCm packages installed but rocminfo is not usable yet. A reboot/login may be required."
    touch "$ACCELERATOR_REBOOT_REQUIRED_FILE"
    return 1
}

install_cuda_system_stack() {
    info "Checking NVIDIA CUDA system stack..."
    case "$PKG" in
        pacman)
            local kernel_headers=()
            case "$(uname -r)" in
                *-zen*) kernel_headers+=(linux-zen-headers) ;;
                *-lts*) kernel_headers+=(linux-lts-headers) ;;
                *-hardened*) kernel_headers+=(linux-hardened-headers) ;;
                *) kernel_headers+=(linux-headers) ;;
            esac
            # Do not force open kernel modules on Pascal/Maxwell/unknown GPUs.
            # Keep a working installed driver intact; only add toolkit components.
            if ! nvidia_driver_ready; then
                local driver_pkg="$NVIDIA_DRIVER_PACKAGE"
                if [[ "$driver_pkg" == auto ]]; then
                    case "${GPU_NAME,,}" in
                        *"geforce rtx"*|*"quadro rtx"*|*"rtx a"*|*"geforce gtx 16"*|*"tesla t4"*|*"nvidia a100"*|*"nvidia h100"*|*"nvidia l4"*) driver_pkg="nvidia-open-dkms" ;;
                        *)
                            echo "ERROR: No safe automatic NVIDIA driver choice for '$GPU_NAME'."
                            echo "       Install the appropriate legacy/current driver, or set NVIDIA_DRIVER_PACKAGE explicitly."
                            return 1 ;;
                    esac
                fi
                [[ "$driver_pkg" =~ ^[a-zA-Z0-9+._-]+$ ]] || { echo "ERROR: Invalid NVIDIA_DRIVER_PACKAGE."; return 1; }
                install_missing_packages dkms "${kernel_headers[@]}" "$driver_pkg" nvidia-utils || return 1
            fi
            install_missing_packages cuda || return 1
            ensure_accelerator_access || return 1
            ;;
        apt)
            install_missing_packages build-essential dkms || return 1
            # Do not reinstall a working display driver merely because nvcc
            # is missing. CUDA wheels additionally verify real GPU allocation.
            if ! nvidia_driver_ready; then
                if command -v ubuntu-drivers >/dev/null 2>&1 && [[ "$NVIDIA_AUTO_DRIVER" == "1" ]]; then
                    info "Installing recommended NVIDIA driver with ubuntu-drivers"
                    $SUDO ubuntu-drivers install || return 1
                else
                    echo "ERROR: NVIDIA driver missing; use your distro's supported driver installer first."
                    return 1
                fi
            fi
            if ! cuda_toolkit_ready; then
                if apt-cache show cuda-toolkit >/dev/null 2>&1; then
                    $SUDO apt-get install -y cuda-toolkit || return 1
                elif apt-cache show nvidia-cuda-toolkit >/dev/null 2>&1; then
                    install_missing_packages nvidia-cuda-toolkit || return 1
                else
                    echo "ERROR: CUDA toolkit not found in configured APT repositories."
                    echo "       Enable a compatible official CUDA repository and rerun accelerator-setup."
                    return 1
                fi
            fi
            ;;
        dnf|dnf5|microdnf|yum|tdnf)
            echo "    [note] NVIDIA driver/repository setup is distribution-specific."
            if command -v nvidia-smi >/dev/null 2>&1 && ! cuda_toolkit_ready; then
                install_missing_packages cuda-toolkit || return 1
            else
                echo "    [warning] Configure NVIDIA's CUDA repository first, then rerun: $0 accelerator-setup"
                return 1
            fi
            ;;
        zypper)
            echo "    [note] NVIDIA driver/repository setup is distribution-specific."
            if command -v nvidia-smi >/dev/null 2>&1 && ! cuda_toolkit_ready; then
                $SUDO zypper --non-interactive install cuda-toolkit || return 1
            else
                echo "    [warning] Configure NVIDIA's CUDA repository first, then rerun: $0 accelerator-setup"
                return 1
            fi
            ;;
        *)
            echo "    [warning] CUDA system installation is unsupported on package manager '$PKG'."
            return 1
            ;;
    esac
    if nvidia_driver_ready && cuda_toolkit_ready; then
        echo "    [ready] NVIDIA driver + CUDA toolkit detected"
        return 0
    fi
    echo "    [warning] CUDA packages installed but driver/toolkit verification is incomplete."
    mkdir -p "$(dirname "$ACCELERATOR_REBOOT_REQUIRED_FILE")"
    touch "$ACCELERATOR_REBOOT_REQUIRED_FILE"
    return 1
}

accelerator_write_state() {
    [[ -x "$VENV_PY" ]] || return 0
    mkdir -p "$(dirname "$ACCELERATOR_STATE_FILE")"
    "$VENV_PY" - "$ACCELERATOR_STATE_FILE" "$ACCELERATOR_BACKEND" "$GPU_VENDOR" "$GPU_NAME" "$GPU_ARCH" "$OS_ID" "$OS_VERSION_ID" "$(rocm_critical_libraries_ready && roctx_runtime_ready && echo true || echo false)" "$(nvidia_driver_ready && echo true || echo false)" "$(cuda_toolkit_ready && echo true || echo false)" "$(intel_runtime_ready && echo true || echo false)" "$(accelerator_torch_test "$VENV_PY" "$ACCELERATOR_BACKEND" >/dev/null 2>&1 && echo true || echo false)" <<'PY_ACCEL_STATE'
import json,sys,time
from pathlib import Path
p=Path(sys.argv[1]); keys=('backend','vendor','gpu','arch','os','os_version')
payload=dict(zip(keys,sys.argv[2:8])); payload['checked_at']=int(time.time())
for key,val in zip(('rocm_ready','cuda_driver_ready','cuda_toolkit_ready','intel_xpu_ready','torch_allocation_ready'),sys.argv[8:]):
    payload[key]=val=='true'
p.parent.mkdir(parents=True,exist_ok=True)
p.write_text(json.dumps(payload,indent=2)+'\n',encoding='utf-8')
PY_ACCEL_STATE
}

ensure_accelerator_stack() {
    configure_accelerator_environment
    info "Detected OS: $OS_ID ${OS_VERSION_ID:-} ${OS_CODENAME:-}"
    info "Detected GPU: $GPU_VENDOR $GPU_NAME"
    echo "    Backend:        $ACCELERATOR_BACKEND"
    echo "    GPU architecture: $GPU_ARCH"
    local result=0
    case "$ACCELERATOR_BACKEND" in
        amd_rocm)
            if ! rocm_critical_libraries_ready; then
                install_rocm_system_stack || result=1
                [[ "$PKG" != pacman ]] || install_arch_rocm_full_stack || result=1
                configure_accelerator_environment
            else
                installed "ROCm runtime + HIP/ML libraries ($ROCM_PATH)"
            fi
            ensure_roctx_runtime || result=1
            ensure_miopen_runtime || result=1
            rocm_critical_libraries_ready || result=1
            ;;
        nvidia_cuda)
            if ! nvidia_driver_ready || ! cuda_toolkit_ready; then
                install_cuda_system_stack || result=1
                configure_accelerator_environment
            else
                installed "NVIDIA driver + CUDA toolkit"
            fi
            nvidia_driver_ready && cuda_toolkit_ready || result=1
            ;;
        intel_xpu)
            if ! intel_runtime_ready; then
                install_intel_system_stack || result=1
                configure_accelerator_environment
            else
                installed "Intel Level Zero + GPU compute runtime"
            fi
            intel_runtime_ready || result=1
            ;;
        cpu)
            echo "    [note] CPU backend selected; no GPU driver will be changed."
            ;;
    esac
    accelerator_write_state
    if (( result != 0 )); then
        echo "ERROR: $ACCELERATOR_BACKEND provisioning is incomplete; see warnings above and accelerator-status."
        return 1
    fi
}

ensure_pytorch_backend() {
    [[ -x "$VENV_PY" ]] || { echo "ERROR: Core Zarzysseus Python environment is unavailable."; return 1; }
    configure_accelerator_environment
    if accelerator_torch_test "$VENV_PY" "$ACCELERATOR_BACKEND" >/dev/null 2>&1; then
        installed "$ACCELERATOR_BACKEND PyTorch runtime (real device allocation passed)"
        accelerator_write_state
        return 0
    fi
    case "$ACCELERATOR_BACKEND" in
        amd_rocm)
            installing "ROCm PyTorch $PYTORCH_ROCM_VERSION + TorchVision $PYTORCH_ROCM_TORCHVISION_VERSION"
            "$VENV_PY" -m pip install -U --force-reinstall "torch==${PYTORCH_ROCM_VERSION}" "torchvision==${PYTORCH_ROCM_TORCHVISION_VERSION}" --index-url "$PYTORCH_ROCM_INDEX_URL" --extra-index-url https://pypi.org/simple || return 1
            ;;
        nvidia_cuda)
            installing "CUDA PyTorch $PYTORCH_CUDA_VERSION + TorchVision $PYTORCH_CUDA_TORCHVISION_VERSION"
            "$VENV_PY" -m pip install -U --force-reinstall "torch==${PYTORCH_CUDA_VERSION}" "torchvision==${PYTORCH_CUDA_TORCHVISION_VERSION}" --index-url "$PYTORCH_CUDA_INDEX_URL" --extra-index-url https://pypi.org/simple || return 1
            ;;
        intel_xpu)
            installing "Intel XPU PyTorch + TorchVision + TorchAudio (official XPU wheels)"
            "$VENV_PY" -m pip install -U --force-reinstall torch torchvision torchaudio --index-url "$PYTORCH_XPU_INDEX_URL" || return 1
            ;;
        cpu)
            installing "CPU PyTorch + TorchVision"
            "$VENV_PY" -m pip install -U torch torchvision --index-url "$PYTORCH_CPU_INDEX_URL" || return 1
            ;;
    esac
    if ! accelerator_torch_test "$VENV_PY" "$ACCELERATOR_BACKEND"; then
        echo "ERROR: $ACCELERATOR_BACKEND PyTorch still cannot allocate a tensor after dependency repair."
        accelerator_write_state
        return 1
    fi
    accelerator_write_state
}

accelerator_status() {
    detect_accelerator
    echo "Accelerator status"
    echo "  OS:              $OS_ID ${OS_VERSION_ID:-} ${OS_CODENAME:-}"
    echo "  GPU vendor:      $GPU_VENDOR"
    echo "  GPU:             $GPU_NAME"
    echo "  Architecture:    $GPU_ARCH"
    echo "  Backend:         $ACCELERATOR_BACKEND"
    case "$ACCELERATOR_BACKEND" in
        amd_rocm)
            echo "  ROCm runtime:    $(rocm_runtime_ready && echo READY || echo MISSING)"
            echo "  HIP runtime:     $(rocm_library_ready && echo READY || echo MISSING)"
            echo "  MIOpen runtime:  $(miopen_runtime_ready && echo READY || echo MISSING)"
            echo "  ROCprofiler SDK: $(rocprofiler_sdk_runtime_ready && echo READY || echo MISSING)"
            echo "  HIPFFT:          $(hipfft_runtime_ready && echo READY || echo MISSING)"
            echo "  ROC-TX / ROCTX:  $(roctx_runtime_ready && echo READY || echo MISSING)"
            echo "  OpenMPI C++ ABI: $(openmpi4_cxx_ready && echo READY || echo MISSING)"
            ;;
        nvidia_cuda)
            echo "  NVIDIA driver:   $(nvidia_driver_ready && echo READY || echo MISSING)"
            echo "  CUDA toolkit:    $(cuda_toolkit_ready && echo READY || echo MISSING)"
            ;;
        intel_xpu)
            echo "  Intel Level Zero:$(intel_runtime_ready && echo ' READY' || echo ' MISSING / PERMISSIONS')"
            echo "  Render device:   $(find /dev/dri -maxdepth 1 -name 'renderD*' -print -quit 2>/dev/null | grep -q . && echo PRESENT || echo MISSING)"
            ;;
        cpu) echo "  CPU backend:     ACTIVE" ;;
    esac
    if [[ -x "$VENV_PY" ]]; then
        accelerator_torch_test "$VENV_PY" "$ACCELERATOR_BACKEND" || echo "  PyTorch tensor:  NOT READY"
    else
        echo "  PyTorch:         NOT INSTALLED"
    fi
    [[ -f "$ACCELERATOR_REBOOT_REQUIRED_FILE" ]] && echo "  Reboot/relogin:  MAY BE REQUIRED (check user groups and loaded driver)"
}

patch_cookbook_sam_mask_status_probe() {
    [[ "$PATCH_COOKBOOK_SAM_MASK_RECIPE" == "1" ]] || return 0
    local route_file="$PROJECT_DIR/routes/shell_routes.py"
    [[ -f "$route_file" ]] || {
        echo "    [note] Cookbook shell route file not found: $route_file"
        return 0
    }

    # The Cookbook dependency key is `sam_mask`, but the real Python package
    # exposes the `segment_anything` module. The generic status probe otherwise
    # imports `sam_mask`, fails, and leaves the UI's Install button red.
    "$VENV_PY" - "$route_file" <<'PY_SAM_STATUS_PATCH'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """def _import_optional_dependency_for_status(name: str):
    prepare_optional_dependency_import(name)
    return importlib.import_module(name)
"""
new = """def _import_optional_dependency_for_status(name: str):
    # Cookbook dependency key `sam_mask` maps to Meta's segment-anything
    # distribution, whose actual Python import is `segment_anything`.
    if name == "sam_mask":
        return importlib.import_module("segment_anything")
    prepare_optional_dependency_import(name)
    return importlib.import_module(name)
"""
if old in text:
    text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8")
    print("    [patched] Cookbook sam_mask status probe now imports segment_anything")
elif 'if name == "sam_mask":\n        return importlib.import_module("segment_anything")' in text:
    print("    [installed] Cookbook sam_mask status probe already understands segment_anything")
else:
    raise SystemExit("Could not locate Cookbook optional-dependency status probe")
PY_SAM_STATUS_PATCH

    if grep -Fq 'if name == "sam_mask":' "$route_file" && \
       grep -Fq 'importlib.import_module("segment_anything")' "$route_file"; then
        echo "    [verified] Cookbook backend sam_mask -> segment_anything mapping"
    else
        echo "    [warning] Cookbook backend SAM status mapping could not be verified"
        return 1
    fi
}

patch_cookbook_sam_mask_recipe() {
    [[ "$PATCH_COOKBOOK_SAM_MASK_RECIPE" == "1" ]] || return 0
    local recipe_file="$PROJECT_DIR/static/js/cookbook-deps-recipes.js"
    [[ -f "$recipe_file" ]] || {
        echo "    [note] Cookbook recipe file not found: $recipe_file"
        return 0
    }

    # The Cookbook Dependencies tab has a dedicated `sam_mask` recipe. The
    # upstream recipe only installs generic Python packages; it does not install
    # Meta's Segment Anything package, a checkpoint, or verify that the feature
    # is actually usable on this host. Replace the COMPLETE sam_mask recipe with
    # a call back into this installer so the UI button and the CLI use the same
    # verified installation path.
    "$PYENV_ROOT/versions/$PYTHON_VERSION/bin/python" - "$recipe_file" "$SCRIPT_PATH" <<'PY_SAM_RECIPE'
from pathlib import Path
import json, re, shlex, sys

path = Path(sys.argv[1])
installer = Path(sys.argv[2])
text = path.read_text(encoding="utf-8")

# Use a JSON string literal for the JS command so paths containing spaces or
# quotes remain valid JavaScript.
cmd = f"bash {shlex.quote(str(installer))} sam-mask-install"
cmd_js = json.dumps(cmd)

entry = """
  {
  backend: 'sam_mask',
  label: 'SAM object mask tools',
  match: () => true,
  variants: {
  pip: { commands: [CMD] },
  },
  },
""".replace("CMD", cmd_js)

# Locate the sam_mask object by backend key rather than relying on one exact
# upstream pip command. This survives formatting and dependency-list changes.
marker = re.search(r"\{\s*backend:\s*['\"]sam_mask['\"]\s*,", text)
if marker:
    obj_start = marker.start()
    # Find the next top-level object boundary. The recipe catalog is a flat
    # array and each object begins with a two-space '{'.
    next_obj = re.search(r"\n\s*\{\s*\n\s*backend:\s*['\"]", text[marker.end():])
    if next_obj:
        obj_end = marker.end() + next_obj.start()
    else:
        arr_end = text.find("\n];", marker.end())
        if arr_end < 0:
            raise SystemExit("Could not determine end of sam_mask recipe object")
        obj_end = arr_end
    text = text[:obj_start] + entry + text[obj_end:]
    action = "replaced"
else:
    # Keep the installer robust against older/newer branches where the recipe
    # object does not exist yet. Insert before the final catalog terminator.
    arr_end = text.rfind("\n];")
    if arr_end < 0:
        raise SystemExit("Could not find Cookbook recipe catalog terminator")
    text = text[:arr_end] + "\n" + entry + text[arr_end:]
    action = "added"

path.write_text(text, encoding="utf-8")

# Verify what was written. Do not claim the UI recipe is patched unless the
# file actually contains the exact installer command.
verify = path.read_text(encoding="utf-8")
expected_backend = bool(re.search(r"backend:\s*['\"]sam_mask['\"]", verify))
expected_cmd = cmd in verify
if not (expected_backend and expected_cmd):
    raise SystemExit("Cookbook sam_mask recipe verification failed")

print(f"    [patched] Cookbook sam_mask recipe {action}: {cmd}")
print("    [verified] Cookbook Dependencies -> SAM object mask now invokes this installer")
PY_SAM_RECIPE
}


bump_cookbook_frontend_cache() {
    local sw_file="$PROJECT_DIR/static/sw.js"
    [[ -f "$sw_file" ]] || return 0

    # Zarzysseus's service worker caches frontend JS/CSS. A changed recipe file can
    # remain invisible to the browser until the cache version changes. Bump the
    # first conventional cache version token when present.
    "$VENV_PY" - "$sw_file" <<'PY_SW_BUMP'
from pathlib import Path
import re, sys

path=Path(sys.argv[1])
text=path.read_text(encoding="utf-8")
patterns=[
    re.compile(r"(CACHE_NAME\s*=\s*['\"][^'\"]*?)(?:v|V)(\d+)(['\"])") ,
    re.compile(r"(['\"][^'\"]*?[-_]v)(\d+)(['\"])") ,
]
for pat in patterns:
    m=pat.search(text)
    if not m:
        continue
    current=int(m.group(2))
    replacement=m.group(1)+str(current+1)+m.group(3)
    text=text[:m.start()]+replacement+text[m.end():]
    path.write_text(text,encoding="utf-8")
    print(f"    [updated] frontend service-worker cache version {current} -> {current+1}")
    break
else:
    # Still touch the file so the app/server sees a modified asset timestamp;
    # do not invent a cache-name format we have not found.
    print("    [note] Could not find a conventional CACHE_NAME version token in static/sw.js")
PY_SW_BUMP
}


install_sam_mask_tool() {
    info "Checking SAM mask tool dependencies..."

    # Patch the Cookbook recipe first so the UI button is guaranteed to invoke
    # this verified installer instead of the generic upstream pip command.
    patch_cookbook_sam_mask_status_probe
    patch_cookbook_sam_mask_recipe
    bump_cookbook_frontend_cache

    # Keep SAM in the core Zarzysseus venv: the image editor runs SAM in-process.
    # First provision the correct accelerator stack, then install SAM against
    # that backend. AMD uses ROCm/HIP; NVIDIA uses CUDA; CPU remains supported.
    ensure_accelerator_stack
    ensure_pytorch_backend

    if python -c 'import torch, torchvision' >/dev/null 2>&1; then
        installed "Torch + TorchVision for SAM"
    else
        echo "ERROR: Torch/TorchVision is not importable after backend provisioning."
        return 1
    fi

    # Install the actual SAM package and its image/post-processing dependencies
    # explicitly. Do not rely on the Cookbook recipe alone: its upstream recipe
    # currently omits segment-anything and the checkpoint.
    pip_install_if_missing segment-anything
    pip_install_if_missing transformers
    pip_install_if_missing accelerate
    pip_install_if_missing pillow

    if [[ "$INSTALL_SAM_MASK_FULL" == "1" ]]; then
        pip_install_if_missing opencv-python
        pip_install_if_missing pycocotools
        pip_install_if_missing matplotlib
        pip_install_if_missing onnx
        pip_install_if_missing onnxruntime
    fi

    mkdir -p "$SAM_MODEL_DIR"

    if [[ -f "$SAM_CHECKPOINT" ]] && [[ $(stat -c%s "$SAM_CHECKPOINT" 2>/dev/null || echo 0) -gt 50000000 ]]; then
        installed "SAM $SAM_MODEL_TYPE checkpoint ($SAM_CHECKPOINT)"
    else
        if [[ -f "$SAM_CHECKPOINT" ]]; then rm -f "$SAM_CHECKPOINT"; fi
        installing "SAM $SAM_MODEL_TYPE checkpoint"
        curl -fL --retry 5 --retry-delay 3 -o "$SAM_CHECKPOINT" "$SAM_CHECKPOINT_URL"
    fi

    [[ -f "$SAM_CHECKPOINT" ]] && [[ $(stat -c%s "$SAM_CHECKPOINT" 2>/dev/null || echo 0) -gt 50000000 ]] || {
        echo "ERROR: SAM checkpoint download did not complete: $SAM_CHECKPOINT"
        return 1
    }

    # Import test: prove the package and checkpoint are present, independent of
    # whatever the Cookbook UI currently displays.
    if ! python - "$SAM_CHECKPOINT" <<'PY_SAMVERIFY'
import sys
from pathlib import Path
checkpoint = Path(sys.argv[1])
import torch
from segment_anything import sam_model_registry
assert "vit_b" in sam_model_registry
assert checkpoint.is_file() and checkpoint.stat().st_size > 50_000_000
print("    [verified] segment_anything import + SAM checkpoint")
print(f"    [verified] torch={torch.__version__} hip={getattr(torch.version, 'hip', None)}")
PY_SAMVERIFY
    then
        echo "ERROR: SAM import/checkpoint verification failed."
        return 1
    fi

    # Leave an explicit machine-readable marker. This is useful for the
    # installer status command and documents exactly what was verified.
    mkdir -p "$(dirname "$SAM_MARKER_FILE")"
    "$VENV_DIR/bin/python" - "$SAM_MARKER_FILE" "$SAM_CHECKPOINT" <<'PY_SAM_MARKER'
import json, sys, time
from pathlib import Path
path = Path(sys.argv[1])
checkpoint = Path(sys.argv[2])
payload = {
    "installed": True,
    "verified_at": int(time.time()),
    "python": sys.version.split()[0],
    "checkpoint": str(checkpoint),
    "checkpoint_bytes": checkpoint.stat().st_size,
    "component": "sam_mask",
    "backend": "cpu_or_rocm",
}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY_SAM_MARKER
    echo "    [ready] sam_mask: Python package + full extras + checkpoint"
    echo "    [marker] $SAM_MARKER_FILE"
}

sam_mask_dependencies_ready() {
    venv_installed || return 1
    "$VENV_DIR/bin/python" - <<'PY_SAMCHECK' >/dev/null 2>&1
import importlib.metadata as metadata
import importlib.util
mods = [
    "torch", "torchvision", "segment_anything", "transformers", "accelerate", "PIL",
    "cv2", "pycocotools", "matplotlib", "onnx", "onnxruntime"
]
if not all(importlib.util.find_spec(m) for m in mods):
    raise SystemExit(1)
metadata.version("segment-anything")
PY_SAMCHECK
}

openmpi4_cxx_lib() {
    local candidate=""
    for candidate in "$OPENMPI4_PREFIX/lib/libmpi_cxx.so.40" "$OPENMPI4_PREFIX/lib/libmpi_cxx.so"; do
        [[ -e "$candidate" ]] && { echo "$candidate"; return 0; }
    done
    if command -v ldconfig >/dev/null 2>&1; then
        ldconfig -p 2>/dev/null | awk '/libmpi_cxx\.so\.40 / {print $NF; exit}' || true
    fi
}

openmpi4_cxx_ready() {
    [[ -n "$(openmpi4_cxx_lib)" ]]
}

openmpi4_libdir() {
    local lib="$(openmpi4_cxx_lib || true)"
    [[ -n "$lib" ]] || return 1
    dirname "$lib"
}

engine_ld_library_path() {
    local paths=()
    [[ -d "$OPENMPI4_PREFIX/lib" ]] && paths+=("$OPENMPI4_PREFIX/lib")
    if [[ -n "${ROCM_PATH:-}" ]]; then
        [[ -d "$ROCM_PATH/lib" ]] && paths+=("$ROCM_PATH/lib")
        [[ -d "$ROCM_PATH/lib64" ]] && paths+=("$ROCM_PATH/lib64")
    fi
    # Also cover distro-managed ROCm prefixes, which some Arch-derived or
    # manually provisioned installations expose alongside /opt/rocm.
    [[ -d /usr/lib/rocm/lib ]] && paths+=(/usr/lib/rocm/lib)
    [[ -d /usr/lib/rocm/lib64 ]] && paths+=(/usr/lib/rocm/lib64)
    if [[ -n "${CUDA_HOME:-}" ]]; then
        [[ -d "$CUDA_HOME/lib64" ]] && paths+=("$CUDA_HOME/lib64")
    fi
    local out="" p
    for p in "${paths[@]}"; do
        [[ -n "$p" ]] || continue
        case ":$out:" in *":$p:"*) ;; *) out="${out:+$out:}$p" ;; esac
    done
    printf '%s' "$out"
}

install_openmpi4_compat() {
    [[ "$ACCELERATOR_BACKEND" == "amd_rocm" ]] || return 0
    if openmpi4_cxx_ready; then
        echo "    [installed] OpenMPI 4 compatibility (libmpi_cxx.so.40)"
        return 0
    fi

    info "Checking OpenMPI 4 compatibility for ROCm/vLLM..."
    echo "    vLLM ROCm may require the OpenMPI 4 C++ ABI; OpenMPI 5 removed libmpi_cxx.so.40."
    mkdir -p "$OPENMPI4_PREFIX"

    case "$PKG" in
        pacman|apt|dnf|dnf5|microdnf|yum|zypper|apk|xbps|eopkg|urpmi|tdnf|slackpkg|nix|guix)
            install_missing_packages gcc make perl tar bzip2 || return 1
            ;;
        *)
            echo "    [warning] Cannot provision OpenMPI 4 automatically for package manager '$PKG'."
            return 1
            ;;
    esac

    local build_root tarball src_dir jobs
    build_root="$(mktemp -d)"
    tarball="$build_root/openmpi-${OPENMPI4_VERSION}.tar.bz2"
    info "Downloading official OpenMPI ${OPENMPI4_VERSION} source..."
    curl -fL --retry 4 --retry-delay 2 -o "$tarball" "$OPENMPI4_URL"
    printf '%s  %s\n' "$OPENMPI4_SHA256" "$tarball" | sha256sum -c -
    tar -xjf "$tarball" -C "$build_root"
    src_dir="$build_root/openmpi-${OPENMPI4_VERSION}"
    [[ -d "$src_dir" ]] || { rm -rf "$build_root"; return 1; }

    jobs="${OPENMPI4_MAKE_JOBS:-$(nproc 2>/dev/null || echo 2)}"
    info "Building private OpenMPI ${OPENMPI4_VERSION} with MPI C++ bindings..."
    (
        cd "$src_dir"
        ./configure \
            --prefix="$OPENMPI4_PREFIX" \
            --enable-mpi-cxx \
            --disable-mpi-fortran \
            --disable-mpi-java \
            --disable-oshmem \
            --disable-debug \
            --with-hwloc=internal \
            --with-libevent=internal \
            --with-pmix=internal
        make -j"$jobs"
        make install
    )
    rm -rf "$build_root"

    if openmpi4_cxx_ready; then
        echo "    [ready] Private OpenMPI ${OPENMPI4_VERSION}: $(openmpi4_libdir)"
        return 0
    fi
    echo "    [failed] OpenMPI 4 compatibility library was not produced."
    return 1
}

mlx_lm_platform_mode() {
    case "$(uname -s)" in
        Darwin)
            case "$(uname -m)" in
                arm64|aarch64) echo "apple" ;;
                *) echo "unsupported" ;;
            esac
            ;;
        Linux)
            if [[ "$ACCELERATOR_BACKEND" == "nvidia_cuda" ]]; then
                echo "cuda"
            else
                echo "cpu"
            fi
            ;;
        *)
            echo "unsupported"
            ;;
    esac
}

ensure_mlx_lm_core_dependency() {
    [[ "$INSTALL_MLX_LM" == "1" ]] || return 0
    [[ -x "$VENV_PY" ]] || { echo "ERROR: Core Zarzysseus Python environment is unavailable."; return 1; }

    # The Cookbook dependency status probe runs inside Zarzysseus's main Python
    # environment. Installing MLX-LM only in data/local/venvs/mlx_lm leaves the
    # UI showing "Install" forever even though the isolated runtime works.
    # Keep the isolated runtime for serving, but also install the distribution
    # in the core venv so Cookbook can detect it.
    local mode core_spec="mlx-lm"
    mode="$(mlx_lm_platform_mode)"
    case "$mode" in
        apple)
            echo "    MLX-LM core backend: Apple Silicon / Metal"
            core_spec="mlx-lm"
            ;;
        cuda)
            echo "    MLX-LM core backend: Linux NVIDIA / CUDA"
            # Prefer CUDA 13 when available; fall back to CPU if the matching
            # MLX CUDA wheel is not available for this host.
            if ! "$VENV_PY" -m pip install -U "mlx[cuda13]" "mlx-lm"; then
                echo "    [fallback] MLX CUDA 13 package unavailable; installing MLX CPU + MLX-LM in core venv."
                "$VENV_PY" -m pip install -U "mlx[cpu]" "mlx-lm" || return 1
            fi
            ;;
        cpu)
            echo "    MLX-LM core backend: Linux CPU (AMD/CPU host)"
            core_spec="mlx[cpu]"
            "$VENV_PY" -m pip install -U "$core_spec" "mlx-lm" || return 1
            ;;
        unsupported)
            echo "    [skipped] Core MLX-LM package on $(uname -s)/$(uname -m)"
            return 0
            ;;
    esac

    # Apple and the successful CUDA path reach here with mlx-lm installed.
    if "$VENV_PY" -c 'import importlib.metadata as md; md.version("mlx-lm"); import mlx_lm' >/dev/null 2>&1; then
        local v
        v="$($VENV_PY -c 'import importlib.metadata as md; print(md.version("mlx-lm"))')"
        installed "MLX-LM core dependency (Cookbook-visible, $v)"
    else
        echo "    [failed] MLX-LM core dependency is not importable in $VENV_DIR"
        return 1
    fi
}

install_mlx_lm() {
    info "Checking MLX-LM..."

    [[ "$INSTALL_MLX_LM" == "1" ]] || {
        echo "    [skipped] MLX-LM (INSTALL_MLX_LM=0)"
        return 0
    }

    mkdir -p "$COOKBOOK_LOCAL_DIR/venvs" "$MLX_LM_MODEL_DIR" "$COOKBOOK_BIN_DIR"

    local mode py
    mode="$(mlx_lm_platform_mode)"
    if [[ "$mode" == "unsupported" ]]; then
        echo "    [skipped] MLX-LM on $(uname -s)/$(uname -m)"
        echo "              Supported automatic modes: Apple Silicon macOS, Linux CPU, Linux NVIDIA CUDA."
        return 0
    fi

    # First install the distribution into the core Zarzysseus venv because the
    # Cookbook Dependencies status endpoint probes that environment.
    ensure_mlx_lm_core_dependency || return 1

    # Keep an isolated MLX-LM environment for its CLI/server dependencies so it
    # cannot interfere with ROCm vLLM, SGLang, SAM, or the core application's
    # pinned packages.
    ensure_engine_venv "$MLX_LM_VENV_DIR" "MLX-LM" || return 1
    py="$MLX_LM_VENV_DIR/bin/python"

    case "$mode" in
        apple)
            echo "    MLX-LM isolated backend: Apple Silicon / Metal"
            "$py" -m pip install -U "mlx-lm" || return 1
            ;;
        cuda)
            echo "    MLX-LM isolated backend: Linux NVIDIA / CUDA"
            if ! "$py" -m pip install -U "mlx[cuda13]" "mlx-lm"; then
                echo "    [fallback] MLX CUDA 13 isolated package unavailable; using MLX CPU + MLX-LM."
                "$py" -m pip install -U "mlx[cpu]" "mlx-lm" || return 1
            fi
            ;;
        cpu)
            echo "    MLX-LM isolated backend: Linux CPU"
            "$py" -m pip install -U "mlx[cpu]" "mlx-lm" || return 1
            ;;
    esac

    if "$py" -c 'import mlx, mlx_lm; print("MLX:", getattr(mlx, "__version__", "installed")); print("MLX-LM:", getattr(mlx_lm, "__version__", "installed"))' 2>/dev/null; then
        installed "MLX-LM isolated runtime ($MLX_LM_VENV_DIR)"
    else
        echo "    [warning] MLX-LM isolated packages installed but import verification failed."
        return 1
    fi

    cat > "$COOKBOOK_BIN_DIR/mlx_lm" <<EOF_MLX_WRAPPER
#!/usr/bin/env bash
exec "$py" -m mlx_lm "\$@"
EOF_MLX_WRAPPER
    chmod +x "$COOKBOOK_BIN_DIR/mlx_lm"
    echo "    [ready] MLX-LM command: $COOKBOOK_BIN_DIR/mlx_lm"
    echo "    [ready] MLX-LM model cache: $MLX_LM_MODEL_DIR"
}

mlx_lm_status() {
    echo "MLX-LM status"
    echo "  Core venv:         $VENV_DIR"
    echo "  Isolated venv:     $MLX_LM_VENV_DIR"
    echo "  Model cache:       $MLX_LM_MODEL_DIR"
    echo "  Platform mode:     $(mlx_lm_platform_mode)"
    local core_ok=0 isolated_ok=0
    if [[ -x "$VENV_PY" ]] && "$VENV_PY" -c 'import importlib.metadata as md; md.version("mlx-lm"); import mlx_lm' >/dev/null 2>&1; then
        core_ok=1
        "$VENV_PY" -c 'import importlib.metadata as md; print("  Core MLX-LM:       " + md.version("mlx-lm"))' 2>/dev/null || true
    else
        echo "  Core MLX-LM:       NOT VISIBLE TO COOKBOOK"
    fi
    if [[ -x "$MLX_LM_VENV_DIR/bin/python" ]] && "$MLX_LM_VENV_DIR/bin/python" -c 'import mlx, mlx_lm' >/dev/null 2>&1; then
        isolated_ok=1
        "$MLX_LM_VENV_DIR/bin/python" -c 'import mlx, mlx_lm; print("  Isolated MLX:      " + str(getattr(mlx, "__version__", "installed"))); print("  Isolated MLX-LM:   " + str(getattr(mlx_lm, "__version__", "installed")))' 2>/dev/null || true
    else
        echo "  Isolated MLX-LM:   NOT READY"
    fi
    if (( core_ok && isolated_ok )); then
        echo "  Status:             READY + COOKBOOK VISIBLE"
    elif (( core_ok )); then
        echo "  Status:             CORE READY / ISOLATED NOT READY"
    elif (( isolated_ok )); then
        echo "  Status:             ISOLATED READY / COOKBOOK NOT VISIBLE"
        return 1
    else
        echo "  Status:             NOT INSTALLED"
        return 1
    fi
}

engine_venv_python() {
    local dir="$1"
    echo "$dir/bin/python"
}

ensure_engine_venv() {
    local dir="$1" label="$2" base_python
    mkdir -p "$COOKBOOK_LOCAL_DIR/venvs" "$COOKBOOK_BIN_DIR"
    if [[ -x "$dir/bin/python" ]]; then
        installed "$label isolated environment ($dir)"
        return 0
    fi
    base_python="${PYENV_ROOT:-$HOME/.pyenv}/versions/$PYTHON_VERSION/bin/python"
    [[ -x "$base_python" ]] || base_python="$VENV_DIR/bin/python"
    [[ -x "$base_python" ]] || { echo "ERROR: Python $PYTHON_VERSION is unavailable for $label."; return 1; }
    installing "$label isolated environment ($dir)"
    "$base_python" -m venv "$dir"
    "$dir/bin/python" -m pip install --upgrade pip setuptools wheel
}

engine_install_spec() {
    local dir="$1" label="$2" spec="$3"
    local py="$dir/bin/python"
    local log_rc=0

    # Do not install generic CUDA-oriented serving engines on Intel/CPU.
    # The Intel XPU Torch backend is verified independently; engine builds need
    # their own tested XPU wheels rather than an accidental NVIDIA runtime.
    if [[ "$ACCELERATOR_BACKEND" == intel_xpu || "$ACCELERATOR_BACKEND" == cpu ]]; then
        echo "    [skipped] $label: no verified accelerated wheel for $ACCELERATOR_BACKEND in this installer."
        return 0
    fi
    # vLLM uses a dedicated ROCm wheel build on AMD and CUDA on NVIDIA.
    if [[ "$label" == "vLLM" ]]; then
        case "$ACCELERATOR_BACKEND" in
            amd_rocm)
                spec="vllm==${VLLM_ROCM_VERSION}"
                ;;
            nvidia_cuda)
                spec="vllm==${VLLM_CUDA_VERSION}"
                ;;
            *)
                spec="vllm"
                ;;
        esac
    fi

    local installed_version=""
    installed_version="$($py -c 'import importlib.metadata as m,sys; print(m.version(sys.argv[1]))' "${spec%%\[*}" 2>/dev/null || true)"

    if [[ -n "$installed_version" ]]; then
        if [[ "$label" == "vLLM" && "$ACCELERATOR_BACKEND" == "amd_rocm" && "$installed_version" != *+rocm* ]]; then
            echo "    [reconfigure] Existing vLLM $installed_version is not a ROCm build; replacing it."
            "$py" -m pip uninstall -y vllm >/dev/null 2>&1 || true
            installed_version=""
        else
            installed "$label package $installed_version"
            return 0
        fi
    fi

    installing "$label package: $spec"
    set +e
    local ldpath="$(engine_ld_library_path)"
    if [[ "$label" == "vLLM" && "$ACCELERATOR_BACKEND" == "amd_rocm" ]]; then
        LD_LIBRARY_PATH="${ldpath}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" PYTORCH_ROCM_ARCH="${GPU_ARCH:-unknown}" "$py" -m pip install -U "$spec" --extra-index-url "$VLLM_ROCM_INDEX_URL"
    elif [[ "$label" == "vLLM" && -n "$VLLM_EXTRA_INDEX_URL" ]]; then
        LD_LIBRARY_PATH="${ldpath}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$py" -m pip install -U "$spec" --extra-index-url "$VLLM_EXTRA_INDEX_URL"
    else
        LD_LIBRARY_PATH="${ldpath}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$py" -m pip install -U "$spec"
    fi
    log_rc=$?
    set -e
    if (( log_rc != 0 )); then
        echo "    [warning] $label installation failed (exit $log_rc)."
        return "$log_rc"
    fi
    return 0
}

link_engine_binary() {
    local dir="$1" binary="$2"
    [[ -x "$dir/bin/$binary" ]] || { echo "ERROR: $binary executable was not produced in $dir."; return 1; }
    mkdir -p "$COOKBOOK_BIN_DIR"
    local ldpath="$(engine_ld_library_path)"
    cat > "$COOKBOOK_BIN_DIR/$binary" <<EOF_ENGINE_WRAPPER
#!/usr/bin/env bash
export LD_LIBRARY_PATH="${ldpath}"'${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}'
exec "$dir/bin/$binary" "\$@"
EOF_ENGINE_WRAPPER
    chmod +x "$COOKBOOK_BIN_DIR/$binary"
}

verify_engine_runtime() {
    local dir="$1" module="$2" label="$3"
    local py="$dir/bin/python"
    [[ -x "$py" ]] || return 1
    local ldpath="$(engine_ld_library_path)"
    local runtime_ld="${ldpath}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    if [[ "$label" == "vLLM" && "$ACCELERATOR_BACKEND" == "amd_rocm" ]]; then
        if ! rocm_library_ready; then echo "    [failed] vLLM prerequisite: libamdhip64.so is missing"; fi
        if ! miopen_runtime_ready; then echo "    [failed] vLLM prerequisite: libMIOpen.so.1 is missing"; fi
        if ! rocprofiler_sdk_runtime_ready; then echo "    [failed] vLLM prerequisite: librocprofiler-sdk.so.1 is missing"; fi
        if ! hipfft_runtime_ready; then echo "    [failed] vLLM prerequisite: libhipfft.so.0 is missing"; fi
    fi
    if ! LD_LIBRARY_PATH="$runtime_ld" "$py" -c "import $module" >/dev/null 2>&1; then
        echo "    [failed] $label import check"
        if [[ "$label" == "vLLM" && -d "$dir/lib/python3.12/site-packages/torch" ]]; then
            local torch_core
            torch_core="$(find "$dir/lib/python3.12/site-packages/torch" -maxdepth 2 -type f -name '_C*.so' -print -quit 2>/dev/null || true)"
            if [[ -n "$torch_core" ]] && command -v ldd >/dev/null 2>&1; then
                echo "    [diagnostic] Unresolved native libraries in vLLM Torch:"
                LD_LIBRARY_PATH="$runtime_ld" ldd "$torch_core" 2>/dev/null | awk '/not found$/ {print "      - " $1}' | sort -u || true
            fi
        fi
        return 1
    fi
    local version
    version="$(LD_LIBRARY_PATH="${ldpath}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$py" -c "import importlib.metadata as m; print(m.version('${module//_/-}'))" 2>/dev/null || true)"
    [[ -n "$version" ]] && echo "    [ready] $label $version ($dir)" || echo "    [ready] $label ($dir)"
    return 0
}

install_llm_serve_engines() {
    info "Checking isolated local LLM serving engines (vLLM + SGLang)..."

    case "$(uname -s)" in
        Linux) ;;
        *)
            echo "    [skipped] vLLM/SGLang on $(uname -s)"
            return 0
            ;;
    esac

    mkdir -p "$COOKBOOK_LOCAL_DIR" "$COOKBOOK_BIN_DIR" "$COOKBOOK_LOCAL_DIR/venvs"
    configure_accelerator_environment
    if [[ "$ACCELERATOR_BACKEND" == intel_xpu || "$ACCELERATOR_BACKEND" == cpu ]]; then
        echo "    [skipped] vLLM/SGLang GPU engines: no backend-specific build verified for $ACCELERATOR_BACKEND."
        return 0
    fi

    local failures=0
    if [[ "$ACCELERATOR_BACKEND" == "amd_rocm" ]]; then
        # Do not rely on SAM installation having run first. 'tools' and future
        # engine-only flows independently provision the full ROCm userspace set.
        if ! rocm_critical_libraries_ready; then
            echo "    [repair] Required ROCm libraries are missing; installing the complete HIP/ML bundle..."
            install_rocm_system_stack || true
            install_arch_rocm_full_stack || true
            configure_accelerator_environment
        fi
        ensure_roctx_runtime || failures=$((failures+1))
        ensure_miopen_runtime || failures=$((failures+1))
        configure_accelerator_environment
        # Verify the exact native libraries needed by the isolated vLLM Torch
        # build are loadable through the same loader path used below.
        local engine_ld="$(engine_ld_library_path)"
        if ! LD_LIBRARY_PATH="${engine_ld}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"             "$VENV_DIR/bin/python" - <<'PY_ROCM_ENGINE_LIBS' >/dev/null 2>&1
import ctypes
for lib in (
    "libamdhip64.so",
    "libroctx64.so.4",
    "libMIOpen.so.1",
    "librocprofiler-sdk.so.1",
    "libhipfft.so.0",
):
    ctypes.CDLL(lib)
PY_ROCM_ENGINE_LIBS
        then
            echo "    [warning] One or more ROCm engine libraries are not loadable from the configured vLLM library path."
            ensure_roctx_runtime || true
            ensure_miopen_runtime || true
            if command -v ldconfig >/dev/null 2>&1; then
                $SUDO ldconfig >/dev/null 2>&1 || true
            fi
        fi
        if ! install_openmpi4_compat; then
            echo "    [warning] libmpi_cxx.so.40 is still unavailable; vLLM import may fail."
            failures=$((failures+1))
        fi
    fi

    if [[ "$INSTALL_VLLM" == "1" ]]; then
        ensure_engine_venv "$VLLM_VENV_DIR" "vLLM" || failures=$((failures+1))
        if [[ -x "$VLLM_VENV_DIR/bin/python" ]]; then
            engine_install_spec "$VLLM_VENV_DIR" "vLLM" "vllm" || failures=$((failures+1))
            if verify_engine_runtime "$VLLM_VENV_DIR" "vllm" "vLLM"; then
                link_engine_binary "$VLLM_VENV_DIR" "vllm" || failures=$((failures+1))
            else
                # One remediation pass catches libraries installed by the
                # package manager after the first vLLM verification.
                if [[ "$ACCELERATOR_BACKEND" == "amd_rocm" ]]; then
                    echo "    [retry] Refreshing ROCm native runtime libraries and retrying vLLM verification..."
                    ensure_roctx_runtime || true
                    ensure_miopen_runtime || true
                    if command -v ldconfig >/dev/null 2>&1; then
                        $SUDO ldconfig >/dev/null 2>&1 || true
                    fi
                fi
                if verify_engine_runtime "$VLLM_VENV_DIR" "vllm" "vLLM"; then
                    link_engine_binary "$VLLM_VENV_DIR" "vllm" || failures=$((failures+1))
                else
                    failures=$((failures+1))
                fi
            fi
        fi
    else
        echo "    [skipped] vLLM (INSTALL_VLLM=0)"
    fi

    if [[ "$INSTALL_SGLANG" == "1" ]]; then
        ensure_engine_venv "$SGLANG_VENV_DIR" "SGLang" || failures=$((failures+1))
        if [[ -x "$SGLANG_VENV_DIR/bin/python" ]]; then
            engine_install_spec "$SGLANG_VENV_DIR" "SGLang" 'sglang[all]' || failures=$((failures+1))
            if verify_engine_runtime "$SGLANG_VENV_DIR" "sglang" "SGLang"; then
                link_engine_binary "$SGLANG_VENV_DIR" "sglang" || failures=$((failures+1))
            else
                failures=$((failures+1))
            fi
        fi
    else
        echo "    [skipped] SGLang (INSTALL_SGLANG=0)"
    fi

    if ! install_mlx_lm; then
        echo "    [warning] MLX-LM installation/verification failed."
        failures=$((failures+1))
    fi

    if (( failures > 0 )); then
        echo "    [warning] $failures local serving engine checks failed."
        echo "              The engines are isolated under $COOKBOOK_LOCAL_DIR/venvs and can be retried with '$0 tools'."
    else
        echo "    [ready] vLLM and SGLang isolated runtimes are available under $COOKBOOK_LOCAL_DIR."
    fi

    # Let the long-running Zarzysseus process discover the freshly-created local
    # engine executables. This also clears stale dependency state in the UI.
    if service_installed && service_systemctl is-active --quiet "$service_unit" 2>/dev/null; then
        service_systemctl restart "$service_unit" || true
        echo "    [restarted] Zarzysseus service after local engine installation"
    fi

    return 0
}



test_playwright_installed() {
    local npx_bin
    npx_bin="$(find_npx)"
    [[ -n "$npx_bin" ]] || return 1
    export ODYSSEUS_BROWSER_MCP_CACHE="$PLAYWRIGHT_CACHE_DIR"
    export XDG_CACHE_HOME="$PLAYWRIGHT_CACHE_DIR"
    export PLAYWRIGHT_BROWSERS_PATH="$PLAYWRIGHT_BROWSERS_DIR"
    "$npx_bin" --no-install @playwright/mcp@latest --version >/dev/null 2>&1 || return 1
    [[ -d "$PLAYWRIGHT_BROWSERS_DIR" ]] && find "$PLAYWRIGHT_BROWSERS_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .
}

sam_mask_status() {
    echo "SAM mask status"
    echo "  Venv:       $VENV_DIR"
    echo "  Checkpoint: $SAM_CHECKPOINT"
    echo "  Marker:     $SAM_MARKER_FILE"
    echo "  Cookbook:   $PROJECT_DIR/static/js/cookbook-deps-recipes.js"
    if [[ -f "$PROJECT_DIR/static/js/cookbook-deps-recipes.js" ]] && grep -qF "sam-mask-install" "$PROJECT_DIR/static/js/cookbook-deps-recipes.js"; then
        echo "  UI recipe:  INSTALLED"
    else
        echo "  UI recipe:  NOT PATCHED"
    fi
    if test_sam_mask_installed; then
        echo "  Status:     INSTALLED + VERIFIED"
        "$VENV_DIR/bin/python" - <<'PY_SAM_STATUS' 2>/dev/null || true
import torch
from segment_anything import sam_model_registry
print("  segment-anything: OK")
print("  Torch:", torch.__version__)
print("  HIP/ROCm:", getattr(torch.version, "hip", None))
print("  GPU API:", torch.cuda.is_available())
PY_SAM_STATUS
        return 0
    fi
    echo "  Status:     NOT READY"
    echo "  Missing one or more SAM requirements or checkpoint."
    return 1
}


test_sam_mask_installed() {
    sam_mask_dependencies_ready && [[ -f "$SAM_CHECKPOINT" ]] && [[ $(stat -c%s "$SAM_CHECKPOINT" 2>/dev/null || echo 0) -gt 50000000 ]]
}

test_engine_installed() {
    local label="$1" dir="$2" module="$3" binary="$4"
    [[ -x "$dir/bin/python" ]] || return 1
    [[ -x "$COOKBOOK_BIN_DIR/$binary" ]] || return 1
    local ldpath="$(engine_ld_library_path)"
    local runtime_ld="${ldpath}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    LD_LIBRARY_PATH="$runtime_ld" "$dir/bin/python" -c "import $module" >/dev/null 2>&1
}

install_odysseus() {
    if [[ "$PKG" == "unknown" ]]; then
        echo "ERROR: Unsupported Linux distribution."
        exit 1
    fi

    # Always perform the OS-aware system update before package installation or
    # Git cloning. The helper is idempotent within this run and TTL-cached
    # across TUI child invocations so it does not upgrade repeatedly.
    system_update_once

    info "Detected package manager: $PKG"
    info "Resolved Zarzysseus installation context..."
    echo "    Project directory: $PROJECT_DIR"
    echo "    Detection source:  $PROJECT_DISCOVERY_SOURCE"
    if repo_installed; then
        echo "    Existing clone:    yes"
    else
        echo "    Existing clone:    no (will clone to the resolved project directory)"
    fi
    [[ -f "$MANAGED_SCRIPT_PATH" ]] && echo "    Managed script:    $MANAGED_SCRIPT_PATH" || echo "    Managed script:    will create $MANAGED_SCRIPT_PATH"

    info "Checking system dependencies..."

    case "$PKG" in
        pacman)
            PACMAN_PKGS=(git curl base-devel openssl xz tk bzip2 readline sqlite ncurses libffi numactl pciutils)
            if pkg_installed zlib-ng-compat; then
                installed "zlib-ng-compat (using instead of zlib)"
                filtered=()
                for pkg in "${PACMAN_PKGS[@]}"; do
                    [[ "$pkg" == "zlib" ]] || filtered+=("$pkg")
                done
                PACMAN_PKGS=("${filtered[@]}")
            fi
            install_missing_packages "${PACMAN_PKGS[@]}"
            ;;
        apt)
            install_missing_packages build-essential curl git ca-certificates pciutils libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev libffi-dev liblzma-dev libnuma1 libnuma-dev
            ;;
        dnf|dnf5|microdnf|yum|tdnf|rpm-ostree)
            install_missing_packages gcc gcc-c++ make patch curl git ca-certificates pciutils openssl-devel zlib-devel bzip2-devel readline-devel sqlite-devel ncurses-devel xz-devel tk-devel libffi-devel
            ;;
        zypper)
            install_missing_packages gcc gcc-c++ make patch curl git ca-certificates pciutils libopenssl-devel zlib-devel libbz2-devel readline-devel sqlite3-devel ncurses-devel xz tk-devel libffi-devel
            ;;
        apk)
            install_missing_packages build-base curl git ca-certificates pciutils openssl-dev zlib-dev bzip2-dev readline-dev sqlite-dev ncurses-dev xz-dev tk-dev libffi-dev
            ;;
        xbps)
            install_missing_packages base-devel curl git ca-certificates pciutils openssl-devel zlib-devel bzip2-devel readline-devel sqlite-devel ncurses-devel xz-devel tk-devel libffi-devel
            ;;
        emerge)
            install_missing_packages dev-vcs/git net-misc/curl sys-devel/gcc sys-devel/make dev-libs/openssl sys-libs/zlib app-arch/bzip2 sys-libs/readline dev-db/sqlite sys-libs/ncurses app-arch/xz dev-lang/tk dev-libs/libffi sys-apps/pciutils
            ;;
        eopkg)
            # Solus exposes its compiler toolchain through the system.devel component.
            $SUDO eopkg install -y -c system.devel
            install_missing_packages git curl ca-certs pciutils openssl-devel zlib-devel bzip2-devel readline-devel sqlite3-devel ncurses-devel xz-devel tk-devel libffi-devel
            ;;
        urpmi)
            install_missing_packages gcc gcc-c++ make patch curl git ca-certificates pciutils openssl-devel zlib-devel bzip2-devel readline-devel sqlite3-devel ncurses-devel xz-devel tk-devel libffi-devel
            ;;
        slackpkg)
            install_missing_packages gcc gcc-g++ make patch curl git ca-certificates pciutils openssl zlib bzip2 readline sqlite ncurses xz tk libffi
            ;;
        nix)
            install_missing_packages git curl gcc gnumake patch openssl zlib bzip2 readline sqlite ncurses xz tk libffi pciutils numactl
            ;;
        guix)
            install_missing_packages git curl gcc-toolchain make patch openssl zlib bzip2 readline sqlite ncurses xz tk libffi pciutils numactl
            ;;
        swupd)
            # Clear Linux installs bundles rather than individual RPM-style packages.
            install_missing_packages os-clr-on-clr dev-utils devpkg-openssl devpkg-zlib devpkg-bzip2 devpkg-readline devpkg-sqlite devpkg-ncurses devpkg-xz devpkg-tcl devpkg-libffi
            ;;
    esac

    # --------------------------------------
    # Clone / locate Zarzysseus
    # --------------------------------------

    info "Checking Zarzysseus source tree..."
    if repo_installed; then
        installed "Zarzysseus repository ($PROJECT_DIR)"
        refresh_existing_odysseus_checkout
    elif [[ -e "$PROJECT_DIR" ]]; then
        echo "ERROR: $PROJECT_DIR exists but is not an Zarzysseus Git repository."
        echo "Move/remove it, or set PROJECT_DIR to another location."
        exit 1
    else
        installing "Zarzysseus repository ($PROJECT_DIR)"
        echo "    Source: $REPO_URL"
        echo "    Target: $PROJECT_DIR"
        mkdir -p "$(dirname "$PROJECT_DIR")"
        git clone "$REPO_URL" "$PROJECT_DIR"
    fi

    # From here forward the installation is completely cwd-independent.
    # Store a stable copy of the installer in the checkout, point generated
    # services/recipes at it, and execute the remainder from PROJECT_DIR.
    sync_managed_installer_copy "$LAUNCH_SCRIPT_PATH"
    enter_odysseus_project

    # --------------------------------------
    # tmux
    # --------------------------------------

    info "Checking tmux..."
    if command -v tmux >/dev/null 2>&1; then
        installed "tmux"
    else
        installing "tmux"
        case "$PKG" in
            pacman|apt|dnf|dnf5|microdnf|yum|zypper|apk|xbps|emerge|eopkg|urpmi|tdnf|slackpkg|nix|guix|rpm-ostree)
                install_missing_packages tmux
                ;;
            swupd)
                install_missing_packages sysadmin-basic
                ;;
        esac
    fi

    # --------------------------------------
    # yay (Arch only)
    # --------------------------------------

    if [[ "$PKG" == "pacman" ]]; then
        info "Checking yay..."
        if command -v yay >/dev/null 2>&1; then
            installed "yay"
        else
            installing "yay"
            BUILD_DIR="$(mktemp -d)"
            trap 'rm -rf "$BUILD_DIR"' EXIT
            git clone https://aur.archlinux.org/yay-bin.git "$BUILD_DIR/yay-bin"
            cd "$BUILD_DIR/yay-bin"
            makepkg -si --noconfirm
            cd "$PROJECT_DIR"
        fi
    fi

    # --------------------------------------
    # Ollama
    # --------------------------------------

    info "Checking Ollama..."
    if command -v ollama >/dev/null 2>&1; then
        installed "Ollama"
    else
        installing "Ollama"
        if [[ "$PKG" == "pacman" ]] && command -v yay >/dev/null 2>&1; then
            if yay -S --needed --noconfirm ollama; then
                echo "    [installed] Ollama via yay"
            else
                echo "    [fallback] yay/mirror failed, using official Ollama installer..."
                curl -fsSL https://ollama.com/install.sh | sh
            fi
        else
            curl -fsSL https://ollama.com/install.sh | sh
        fi
    fi


    # --------------------------------------
    # Ollama startup service
    # --------------------------------------

    info "Checking Ollama startup service..."
    if [[ "$SERVICE_MANAGER" != "systemd" ]]; then
        echo "    [skipped] Ollama systemd startup service (no systemd detected)"
        echo "              Start Ollama manually with: ollama serve"
    elif ollama_binary_installed; then
        if ollama_service_installed; then
            installed "Ollama startup service"
            ollama_enable
        else
            installing "Ollama startup service"
            install_ollama_service
        fi
    else
        echo "    [warning] Ollama binary is not available; skipping Ollama service setup."
    fi

    # --------------------------------------
    # Configure Ollama as Zarzysseus LLM
    # --------------------------------------

    configure_ollama_environment

    # Give Ollama a moment to become ready, then optionally ensure there is
    # at least one model available for the default LLM selection.
    info "Checking Ollama models..."
    for _ in $(seq 1 20); do
        ollama_api_ready && break
        sleep 1
    done

    if ollama_api_ready; then
        if ! ollama_model_names | grep -q .; then
            if [[ "$OLLAMA_PULL_DEFAULT_MODEL" == "1" ]]; then
                installing "Ollama default model: $OLLAMA_DEFAULT_MODEL"
                ollama pull "$OLLAMA_DEFAULT_MODEL"
            else
                echo "    [warning] Ollama has no models installed."
            fi
        elif ollama_has_model "$OLLAMA_DEFAULT_MODEL"; then
            installed "Ollama default model: $OLLAMA_DEFAULT_MODEL"
        else
            echo "    [note] $OLLAMA_DEFAULT_MODEL is not installed; keeping existing Ollama models."
            echo "           Use: $0 ollama-pull <model> to install an Ollama model."
        fi
    fi

    # The live Ollama ↔ Zarzysseus database sync runs after the Python environment
    # exists, then continues automatically through a systemd timer.

    # --------------------------------------
    # pyenv
    # --------------------------------------

    info "Checking pyenv..."
    if [[ -d "$HOME/.pyenv" ]]; then
        installed "pyenv"
    else
        installing "pyenv"
        curl -fsSL https://pyenv.run | bash
    fi

    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"

    if ! grep -Fq 'eval "$(pyenv init - bash)"' "$HOME/.bashrc" 2>/dev/null; then
        cat >> "$HOME/.bashrc" <<'EOF_BASHRC'

export PYENV_ROOT="$HOME/.pyenv"
[[ -d "$PYENV_ROOT/bin" ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init - bash)"
EOF_BASHRC
        CHANGES_MADE=1
        echo "    [configured] pyenv in ~/.bashrc"
    else
        echo "    [configured] pyenv in ~/.bashrc"
    fi

    eval "$(pyenv init - bash)"

    info "Checking Python $PYTHON_VERSION..."
    if pyenv versions --bare | grep -qx "$PYTHON_VERSION"; then
        installed "Python $PYTHON_VERSION"
    else
        installing "Python $PYTHON_VERSION"
        pyenv install "$PYTHON_VERSION"
    fi

    pyenv local "$PYTHON_VERSION"

    # --------------------------------------
    # Virtual environment
    # --------------------------------------

    info "Checking virtual environment..."
    if venv_installed; then
        VENV_PYTHON="$($VENV_DIR/bin/python --version 2>&1)"
        if [[ "$VENV_PYTHON" == "Python 3.12."* ]]; then
            installed "Python virtual environment ($VENV_DIR)"
        else
            installing "Python virtual environment ($VENV_DIR)"
            rm -rf "$VENV_DIR"
            "$PYENV_ROOT/versions/$PYTHON_VERSION/bin/python" -m venv "$VENV_DIR"
        fi
    else
        installing "Python virtual environment ($VENV_DIR)"
        "$PYENV_ROOT/versions/$PYTHON_VERSION/bin/python" -m venv "$VENV_DIR"
    fi

    VENV_PY="$VENV_DIR/bin/python"
    source "$VENV_DIR/bin/activate"

    pip_package_installed() {
        python - "$1" <<'PY'
import importlib.metadata
import sys
try:
    importlib.metadata.version(sys.argv[1])
    raise SystemExit(0)
except importlib.metadata.PackageNotFoundError:
    raise SystemExit(1)
PY
    }

    pip_install_if_missing() {
        local package="$1"
        if pip_package_installed "$package"; then
            installed "Python package: $package"
        else
            installing "Python package: $package"
            python -m pip install "$package"
        fi
    }

    pip_install_spec_if_missing() {
        local import_name="$1" spec="$2"
        if pip_package_installed "$import_name"; then
            installed "Python package: $import_name"
        else
            installing "Python package: $spec"
            python -m pip install "$spec"
        fi
    }

    pip_install_best_effort() {
        local label="$1"
        shift
        set +e
        "$@"
        local rc=$?
        set -e
        if (( rc == 0 )); then
            echo "    [installed] $label"
            return 0
        fi
        echo "    [warning] $label installation failed (exit $rc)."
        echo "              Core Zarzysseus installation will continue; retry with '$0 tools'."
        return 0
    }

    # Select ROCm/HIP or CUDA before optional dependencies can pull a generic Torch build.
    ensure_accelerator_stack
    ensure_pytorch_backend

    info "Checking pip..."
    CURRENT_PIP="$(python -m pip --version | awk '{print $2}')"
    python -m pip install --upgrade pip >/dev/null
    NEW_PIP="$(python -m pip --version | awk '{print $2}')"
    if [[ "$CURRENT_PIP" == "$NEW_PIP" ]]; then
        installed "pip $CURRENT_PIP"
    else
        CHANGES_MADE=1
        echo "    [updated] pip $CURRENT_PIP -> $NEW_PIP"
    fi

    info "Installing core requirements..."
    python -m pip install -r requirements.txt

    if [[ -f requirements-optional.txt ]]; then
        info "Installing optional requirements..."
        python -m pip install -r requirements-optional.txt
    else
        echo "    [skipped] requirements-optional.txt not present"
    fi

    info "Checking additional AI/ML packages..."
    pip_install_if_missing huggingface_hub
    pip_install_if_missing hf_transfer
    pip_install_if_missing diffusers
    pip_install_if_missing llama-cpp-python
    pip_install_if_missing rembg
    pip_install_if_missing segment-anything

    info "Checking BasicSR..."
    if python -c 'import basicsr' >/dev/null 2>&1; then
        installed "BasicSR"
    else
        installing "BasicSR"
        python -m pip install 'basicsr @ git+https://github.com/XPixelGroup/BasicSR.git'
    fi

    info "Checking Real-ESRGAN..."
    pip_install_if_missing realesrgan

    info "Checking Real-ESRGAN dependencies..."
    pip_install_if_missing facexlib
    pip_install_if_missing gfpgan

    # --------------------------------------
    # Built-in/optional tools
    # --------------------------------------

    install_playwright_tool
    install_sam_mask_tool
    install_llm_serve_engines

    # --------------------------------------
    # Zarzysseus first-run setup
    # --------------------------------------

    info "Running Zarzysseus setup.py..."
    ODYSSEUS_SKIP_RUN_HINT=1 "$VENV_PY" setup.py

    # --------------------------------------
    # Register Ollama as Zarzysseus's LLM endpoint
    # --------------------------------------

    if ollama_api_ready; then
        sync_ollama_with_odysseus
        [[ -f "$OLLAMA_SYNC_STATE_FILE" ]] && cp "$OLLAMA_SYNC_STATE_FILE" "$OLLAMA_SYNC_STATE_FILE.applied" || true
    else
        echo "    [warning] Ollama API is not reachable; endpoint will be synchronized on the next successful sync."
    fi
    ensure_ollama_sync_timer

    # Do not overwrite a user's later opull/spull/vpull choice on every rerun.
    # Configure the requested Dolphin model once unless the state file already exists.
    if [[ ! -f "$DEFAULT_MODEL_CONFIGURED_FILE" && "$DEFAULT_MODEL_PROVIDER" == "vllm" && "$INSTALL_VLLM" == "1" ]]; then
        configure_engine_default_model vllm "$DEFAULT_MODEL_ID" || true
    fi

    # --------------------------------------
    # Verification
    # --------------------------------------

    info "Verifying installation..."
    "$VENV_PY" - <<'PY'
import sys
print("  Python:", sys.version.split()[0])
for module, label in [("fastapi", "FastAPI"), ("uvicorn", "Uvicorn"), ("basicsr", "BasicSR"), ("realesrgan", "RealESRGAN"), ("facexlib", "FaceXLib"), ("gfpgan", "GFPGAN")]:
    try:
        mod = __import__(module)
        print(f"  {label}:", getattr(mod, "__version__", "installed"))
    except Exception as exc:
        print(f"  {label}: unavailable ({exc})")
try:
    import torch
    print("  PyTorch:", torch.__version__)
    print("  CUDA API available:", torch.cuda.is_available())
    print("  HIP/ROCm:", torch.version.hip)
    if torch.cuda.is_available():
        print("  GPU:", torch.cuda.get_device_name(0))
except Exception as exc:
    print("  PyTorch: unavailable or failed to import:", exc)
try:
    from segment_anything import sam_model_registry
    print("  SAM package: installed")
except Exception as exc:
    print("  SAM package: unavailable:", exc)
from pathlib import Path
import os
project = Path.cwd()
for name, runtime, module in [("vLLM", project / "data/local/venvs/vllm/bin/python", "vllm"), ("SGLang", project / "data/local/venvs/sglang/bin/python", "sglang")]:
    if runtime.exists():
        import subprocess
        try:
            env = dict(os.environ)
            extra_ld = os.environ.get("LD_LIBRARY_PATH", "")
            private_mpi = str(project / "data/local/openmpi4/lib")
            env["LD_LIBRARY_PATH"] = private_mpi + ((":" + extra_ld) if extra_ld else "")
            code = f"import {module}; import importlib.metadata as m; print(m.version({module!r}))"
            out = subprocess.check_output([str(runtime), "-c", code], text=True, env=env).strip()
            print(f"  {name} isolated runtime:", out)
        except Exception as exc:
            print(f"  {name} isolated runtime: unavailable ({exc})")
    else:
        print(f"  {name} isolated runtime: MISSING")
PY

    export APP_PORT="$ODYSSEUS_PORT"

    # --------------------------------------
    # systemd user service
    # --------------------------------------

    if [[ "$SERVICE_MANAGER" != "systemd" ]]; then
        echo "    [warning] systemd is not available; skipping systemd user service creation on this Linux installation."
        echo "              Core Zarzysseus, Ollama, SAM, vLLM and SGLang installation can still continue."
    else
        require_systemctl
        info "Installing/updating systemd user service..."
    mkdir -p "$(dirname "$SERVICE_FILE")"

    ACCEL_ENV_LINES=""
    case "$ACCELERATOR_BACKEND" in
        amd_rocm)
            ACCEL_ENV_LINES=$'Environment=ROCM_PATH='"$ROCM_PATH"$'\nEnvironment=HIP_PATH='"$ROCM_PATH"$'\nEnvironment=PYTORCH_ROCM_ARCH='"$GPU_ARCH"
            ;;
        nvidia_cuda)
            ACCEL_ENV_LINES="Environment=CUDA_HOME=$CUDA_HOME"
            ;;
    esac

    cat > "$SERVICE_FILE" <<EOF_SERVICE
[Unit]
Description=Zarzysseus AI Server
After=network-online.target ${OLLAMA_SERVICE_NAME}.service
Wants=network-online.target ${OLLAMA_SERVICE_NAME}.service

[Service]
Type=simple
WorkingDirectory=$PROJECT_DIR
EnvironmentFile=-$PROJECT_DIR/.env
Environment=APP_PORT=$ODYSSEUS_PORT
Environment=PYTHONUNBUFFERED=1
Environment=LLM_HOST=127.0.0.1
Environment=LLM_HOSTS=127.0.0.1
Environment=OLLAMA_BASE_URL=$OLLAMA_OPENAI_ENDPOINT
Environment=HF_HOME=$HF_HOME
Environment=HUGGINGFACE_HUB_CACHE=$HF_HUB_CACHE
Environment=HF_HUB_CACHE=$HF_HUB_CACHE
Environment=HF_HUB_DISABLE_XET=$HF_HUB_DISABLE_XET
Environment=HF_HUB_ENABLE_HF_TRANSFER=0
Environment=HF_HUB_DOWNLOAD_TIMEOUT=$HF_HUB_DOWNLOAD_TIMEOUT
Environment=HF_HUB_ETAG_TIMEOUT=$HF_HUB_ETAG_TIMEOUT
Environment=HF_HUB_DOWNLOAD_MAX_WORKERS=$HF_HUB_DOWNLOAD_MAX_WORKERS
Environment=PATH=$COOKBOOK_BIN_DIR:$VLLM_VENV_DIR/bin:$SGLANG_VENV_DIR/bin:${ROCM_PATH:-/opt/rocm}/bin:${CUDA_HOME:-/usr/local/cuda}/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
Environment=LD_LIBRARY_PATH=$OPENMPI4_PREFIX/lib:${ROCM_PATH:-/opt/rocm}/lib:${ROCM_PATH:-/opt/rocm}/lib64:/usr/lib/rocm/lib:/usr/lib/rocm/lib64:${CUDA_HOME:-/usr/local/cuda}/lib64
$ACCEL_ENV_LINES
ExecStart=$VENV_PY -m uvicorn app:app --host $ODYSSEUS_HOST --port $ODYSSEUS_PORT
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF_SERVICE

    service_systemctl daemon-reload

    if command -v loginctl >/dev/null 2>&1; then
        if loginctl enable-linger "$USER" >/dev/null 2>&1 || $SUDO loginctl enable-linger "$USER" >/dev/null 2>&1; then
            echo "    [configured] user lingering enabled for startup"
        else
            echo "    [note] Could not enable user lingering automatically."
            echo "           The service will still start when your user session starts."
        fi
    fi

        service_systemctl enable --now "$service_unit"
    fi

    echo "=========================================="
    if [[ "$CHANGES_MADE" -eq 0 ]]; then
        echo "Everything was already installed."
    else
        echo "Zarzysseus setup complete."
        echo "Missing components were installed."
    fi
    if [[ "$SERVICE_MANAGER" == "systemd" ]]; then
        echo "Zarzysseus service is enabled and running."
    else
        echo "No systemd service was created; run the app with your distro's service manager or manually."
    fi
    echo "=========================================="
    echo
    echo "Use this same script to manage Zarzysseus:"
    echo "  $0 status"
    echo "  $0 start"
    echo "  $0 stop"
    echo "  $0 restart"
    echo "  $0 enable"
    echo "  $0 disable"
    echo "  $0 uninstall-service"
    echo
    show_link
    echo
}

# ------------------------------------------
# Interactive terminal UI
# ------------------------------------------

TUI_INPUT=""
TUI_CHOICE=""
TUI_HEADER_HEIGHT=24
TUI_COLS=80
TUI_LINES=24
TUI_STTY_STATE=""
TUI_ACTIVE=0

_tui_size() {
    # Read the *real* terminal dimensions once per frame. Do not clamp a small
    # terminal upward: doing that makes the renderer believe it has columns or
    # rows that do not exist, which is exactly how labels/logo art get cut off.
    local cols lines
    cols="$(tput cols 2>/dev/null || echo 80)"
    lines="$(tput lines 2>/dev/null || echo 24)"
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=24
    (( cols < 12 )) && cols=12
    (( lines < 8 )) && lines=8
    TUI_COLS="$cols"
    TUI_LINES="$lines"
}

_tui_clear() {
    # Clear the visible alternate-screen buffer and return to true home.
    # OPOST is disabled while the TUI is active, so LF cannot be translated
    # into extra CR characters and corrupt cursor positioning.
    printf '\033[2J\033[H'
}

_tui_cursor_show() {
    printf '\033[?25h'
}

_tui_cursor_hide() {
    printf '\033[?25l'
}

# Read one byte from the controlling terminal in non-canonical mode.
# This preserves immediate Enter/arrow-key input without readline buffering.
_tui_read_key() {
    local __var="$1" __key=""
    IFS= read -rsN 1 __key < /dev/tty || __key=""
    printf -v "$__var" '%s' "$__key"
}

# Timed one-byte terminal input used by the full-install model selector.
# Returns 0 when a key was received and 1 when the timeout elapsed.
_tui_read_key_timeout() {
    local __var="$1" __timeout="$2" __key=""
    if IFS= read -rsN 1 -t "$__timeout" __key < /dev/tty; then
        printf -v "$__var" '%s' "$__key"
        return 0
    fi
    printf -v "$__var" '%s' ''
    return 1
}

_tui_begin() {
    [[ "$TUI_ACTIVE" == "1" ]] && return 0
    _tui_size
    if [[ -t 0 && -t 1 ]]; then
        TUI_STTY_STATE="$(stty -g < /dev/tty 2>/dev/null || true)"
        # Disable output post-processing too. Otherwise the terminal may
        # rewrite LF while the menu is being redrawn and cause drift/duplication.
        stty -icanon -echo -opost min 1 time 0 < /dev/tty 2>/dev/null || true
    fi
    # Use the terminal alternate screen. The menu can redraw freely without
    # disturbing the normal shell scrollback, and command output can temporarily
    # return to the normal screen when an operation is launched.
    printf '\033[?1049h\033[H\033[J'
    _tui_cursor_hide
    TUI_ACTIVE=1
}

_tui_end() {
    [[ "$TUI_ACTIVE" == "1" ]] || return 0
    _tui_cursor_show
    if [[ -n "$TUI_STTY_STATE" ]]; then
        stty "$TUI_STTY_STATE" < /dev/tty 2>/dev/null || true
    else
        stty echo icanon opost < /dev/tty 2>/dev/null || true
    fi
    printf '\033[?1049l'
    TUI_STTY_STATE=""
    TUI_ACTIVE=0
}

_tui_cleanup() {
    _tui_end
}

_tui_print_center() {
    local text="$1" max_width width pad chunk
    max_width=$((TUI_COLS - 4))
    (( max_width < 8 )) && max_width=$TUI_COLS

    # Terminal fonts cannot be scaled safely, so "auto fit" means wrapping at
    # word boundaries and centering every wrapped row. This keeps the complete
    # message visible on narrow displays rather than silently clipping it.
    if (( ${#text} <= max_width )); then
        width=${#text}
        pad=$(( (TUI_COLS - width) / 2 )); (( pad < 0 )) && pad=0
        printf '%*s%s\n' "$pad" '' "$text"
        return 0
    fi

    if command -v fold >/dev/null 2>&1; then
        while IFS= read -r chunk; do
            width=${#chunk}
            pad=$(( (TUI_COLS - width) / 2 )); (( pad < 0 )) && pad=0
            printf '%*s%s\n' "$pad" '' "$chunk"
        done < <(printf '%s\n' "$text" | fold -s -w "$max_width")
    else
        while [[ -n "$text" ]]; do
            chunk="${text:0:max_width}"
            text="${text:max_width}"
            width=${#chunk}
            pad=$(( (TUI_COLS - width) / 2 )); (( pad < 0 )) && pad=0
            printf '%*s%s\n' "$pad" '' "$chunk"
        done
    fi
}

_tui_print_block_center() {
    local block="$1" line
    while IFS= read -r line; do
        _tui_print_center "$line"
    done <<< "$block"
}

_tui_fit_one_line() {
    # Fit status/help text that must remain on one physical row. Prefer compact
    # wording at call sites; this is the last-resort guard against line wrap.
    local text="$1" max_width="${2:-$((TUI_COLS - 2))}"
    (( max_width < 4 )) && max_width=4
    if (( ${#text} <= max_width )); then
        printf '%s' "$text"
    elif (( max_width <= 3 )); then
        printf '%.*s' "$max_width" "$text"
    else
        printf '%s...' "${text:0:max_width-3}"
    fi
}

_tui_logo_block() {
    # Zarzysseus binary logo supplied by the user. Keep the delimiter at column 1.
    # The payload stores literal \\033 escapes so the script remains plain text;
    # printf %b expands them only when the TUI is actually rendered.
    while IFS= read -r line; do
        printf '%b\n' "$line"
    done <<'EOF_TUI_LOGO'
\033[38;2;12;12;12m0\033[38;2;13;13;13m00\033[38;2;14;14;14m01\033[38;2;14;14;13m0\033[38;2;14;14;14m00\033[38;2;15;15;15m00\033[38;2;16;16;16m10\033[38;2;17;17;17m1\033[38;2;18;18;18m01\033[38;2;19;19;19m11\033[38;2;20;20;20m1\033[38;2;20;21;20m0\033[38;2;20;20;20m0\033[38;2;21;21;21m00110100101\033[38;2;22;22;22m0010\033[38;2;21;21;21m011001\033[38;2;20;20;20m0\033[38;2;19;19;19m001\033[38;2;18;18;18m1\033[38;2;17;17;17m010101\033[38;2;16;16;16m00111010\033[0m
\033[38;2;13;13;13m10\033[38;2;14;14;14m001\033[38;2;14;14;13m1\033[38;2;14;14;14m1\033[38;2;15;15;15m0\033[38;2;16;16;16m1\033[38;2;17;17;17m1\033[38;2;18;18;18m1\033[38;2;19;19;19m1\033[38;2;20;20;20m0\033[38;2;21;22;20m1\033[38;2;22;22;22m1\033[38;2;23;23;23m0\033[38;2;24;24;24m1\033[38;2;25;25;25m10\033[38;2;26;26;26m01100\033[38;2;25;25;25m0000\033[38;2;26;26;26m11\033[38;2;27;26;26m0\033[38;2;27;27;27m0\033[38;2;28;28;28m0\033[38;2;27;27;27m0\033[38;2;26;26;26m1\033[38;2;26;27;26m0\033[38;2;27;27;27m1\033[38;2;27;27;26m0\033[38;2;27;27;27m1\033[38;2;28;28;28m0\033[38;2;27;27;27m0\033[38;2;26;26;26m1\033[38;2;24;24;24m1\033[38;2;23;23;23m0\033[38;2;21;21;21m1\033[38;2;20;19;19m1\033[38;2;19;19;19m1110\033[38;2;18;18;18m00\033[38;2;18;18;17m0\033[38;2;17;17;17m111\033[38;2;16;17;17m0\033[38;2;16;16;16m0\033[38;2;17;17;17m01\033[0m
\033[38;2;13;13;13m010\033[38;2;13;14;14m1\033[38;2;14;14;14m00\033[38;2;15;15;15m1\033[38;2;16;16;16m1\033[38;2;18;18;18m1\033[38;2;21;21;20m1\033[38;2;23;23;23m0\033[38;2;27;27;27m0\033[38;2;29;29;29m1\033[38;2;30;30;30m0\033[38;2;34;34;34m0\033[38;2;36;36;36m1\033[38;2;37;38;38m1\033[38;2;39;39;39m1\033[38;2;40;40;40m0\033[38;2;41;41;41m0\033[38;2;42;42;42m11\033[38;2;41;41;41m1\033[38;2;40;40;40m000001\033[38;2;41;41;41m0\033[38;2;41;42;42m0\033[38;2;42;43;42m0\033[38;2;42;43;43m1\033[38;2;41;42;42m0\033[38;2;41;41;41m00\033[38;2;41;41;42m1\033[38;2;42;42;42m0\033[38;2;43;43;43m1\033[38;2;44;44;44m0\033[38;2;43;43;42m0\033[38;2;39;39;39m1\033[38;2;34;34;34m0\033[38;2;33;33;33m0\033[38;2;28;28;29m1\033[38;2;24;24;24m0\033[38;2;21;21;21m10\033[38;2;20;20;20m110\033[38;2;19;19;19m1\033[38;2;19;19;20m1\033[38;2;19;19;19m10\033[38;2;19;19;18m1\033[38;2;18;18;18m000\033[38;2;18;17;18m0\033[0m
\033[38;2;13;13;13m0\033[38;2;12;12;12m0\033[38;2;13;13;13m1\033[38;2;13;14;13m0\033[38;2;14;14;14m0\033[38;2;15;15;15m1\033[38;2;17;17;17m0\033[38;2;20;20;20m0\033[38;2;25;25;25m0\033[38;2;29;29;28m0\033[38;2;32;33;32m1\033[38;2;44;46;45m1\033[38;2;83;83;82m0\033[38;2;123;123;122m1\033[38;2;132;132;130m0\033[38;2;135;135;134m0\033[38;2;137;137;136m0\033[38;2;138;139;138m1\033[38;2;140;141;139m1\033[38;2;141;141;140m1\033[38;2;143;143;142m0\033[38;2;143;143;141m0\033[38;2;141;142;140m1\033[38;2;141;142;141m1\033[38;2;141;141;140m1\033[38;2;142;142;141m01\033[38;2;142;142;140m1\033[38;2;141;141;140m10\033[38;2;141;141;141m1\033[38;2;142;142;141m1\033[38;2;141;142;142m1\033[38;2;142;143;142m0\033[38;2;142;142;142m0\033[38;2;141;142;141m0\033[38;2;143;143;143m1\033[38;2;144;144;144m1\033[38;2;144;145;145m1\033[38;2;153;154;153m0\033[38;2;169;169;168m0\033[38;2;152;152;151m0\033[38;2;115;115;113m0\033[38;2;58;58;59m0\033[38;2;41;41;42m1\033[38;2;35;36;36m1\033[38;2;32;34;35m1\033[38;2;24;25;25m0\033[38;2;23;23;23m1\033[38;2;22;22;22m10\033[38;2;21;21;21m1\033[38;2;21;21;22m0\033[38;2;20;20;21m0\033[38;2;20;20;20m101\033[38;2;20;20;19m1\033[38;2;19;19;19m0\033[38;2;19;19;20m0\033[0m
\033[38;2;12;12;12m1\033[38;2;13;13;13m1\033[38;2;14;14;14m01\033[38;2;16;16;16m0\033[38;2;19;19;19m0\033[38;2;24;24;23m0\033[38;2;32;32;31m1\033[38;2;44;44;44m1\033[38;2;78;78;78m0\033[38;2;131;133;133m1\033[38;2;109;110;108m0\033[38;2;104;105;104m1\033[38;2;156;155;154m1\033[38;2;167;167;166m1\033[38;2;172;173;172m1\033[38;2;176;176;176m1\033[38;2;177;177;176m1\033[38;2;179;179;177m1\033[38;2;180;180;178m11\033[38;2;180;181;179m0\033[38;2;182;182;180m0\033[38;2;180;180;179m1\033[38;2;178;178;177m1\033[38;2;176;177;176m0\033[38;2;176;176;175m00\033[38;2;177;176;175m1\033[38;2;178;178;176m1\033[38;2;178;178;177m0\033[38;2;178;178;176m11\033[38;2;180;179;178m1\033[38;2;180;180;179m1\033[38;2;181;181;181m1\033[38;2;179;180;180m1\033[38;2;182;182;181m0\033[38;2;183;183;181m1\033[38;2;181;180;177m0\033[38;2;211;210;207m0\033[38;2;186;186;183m0\033[38;2;149;149;147m0\033[38;2;98;99;98m1\033[38;2;90;92;92m1\033[38;2;62;66;67m1\033[38;2;49;54;57m1\033[38;2;30;31;32m0\033[38;2;30;29;31m0\033[38;2;28;27;28m1\033[38;2;25;25;27m0\033[38;2;23;24;26m0\033[38;2;23;22;24m1\033[38;2;21;21;22m000\033[38;2;20;20;20m0111\033[0m
\033[38;2;13;13;13m11\033[38;2;14;14;14m0\033[38;2;15;15;15m0\033[38;2;18;18;18m0\033[38;2;24;24;24m1\033[38;2;34;34;34m1\033[38;2;51;51;51m1\033[38;2;93;94;93m1\033[38;2;211;211;210m1\033[38;2;211;212;210m1\033[38;2;131;131;130m0\033[38;2;70;71;71m0\033[38;2;63;63;63m0\033[38;2;68;68;69m1\033[38;2;71;71;71m1\033[38;2;74;74;74m1\033[38;2;76;76;76m1\033[38;2;78;77;78m1\033[38;2;80;80;80m0\033[38;2;80;80;79m1\033[38;2;79;79;79m1\033[38;2;80;80;80m1\033[38;2;81;80;81m1\033[38;2;80;79;79m0\033[38;2;78;78;78m1\033[38;2;77;77;77m00\033[38;2;77;76;75m0\033[38;2;78;77;75m1\033[38;2;77;77;77m0\033[38;2;76;76;76m1\033[38;2;76;76;75m0\033[38;2;75;75;74m01\033[38;2;76;77;75m0\033[38;2;78;78;76m0\033[38;2;81;81;79m0\033[38;2;87;86;84m1\033[38;2;85;84;82m0\033[38;2;98;97;95m1\033[38;2;143;142;141m0\033[38;2;201;201;200m0\033[38;2;198;200;199m0\033[38;2;104;106;107m0\033[38;2;58;60;61m0\033[38;2;46;48;48m1\033[38;2;43;45;46m1\033[38;2;40;41;43m0\033[38;2;37;38;40m0\033[38;2;33;34;36m0\033[38;2;30;31;33m0\033[38;2;28;28;30m0\033[38;2;26;25;27m0\033[38;2;24;24;26m0\033[38;2;22;22;24m1\033[38;2;21;21;21m0110\033[0m
\033[38;2;13;13;12m0\033[38;2;13;13;13m0\033[38;2;15;15;15m0\033[38;2;17;17;17m1\033[38;2;21;21;21m1\033[38;2;28;28;28m0\033[38;2;44;44;44m1\033[38;2;79;79;78m1\033[38;2;199;198;197m1\033[38;2;213;213;212m0\033[38;2;147;148;147m0\033[38;2;109;110;109m0\033[38;2;59;59;58m0\033[38;2;45;46;44m1\033[38;2;42;42;42m1\033[38;2;42;42;41m0\033[38;2;44;43;42m1\033[38;2;48;47;46m1\033[38;2;52;50;50m1\033[38;2;55;54;54m0\033[38;2;56;55;55m01\033[38;2;55;54;55m0\033[38;2;53;52;52m1\033[38;2;50;49;49m0\033[38;2;49;47;48m1\033[38;2;47;46;46m1\033[38;2;43;43;43m0\033[38;2;43;43;42m0\033[38;2;43;42;41m0\033[38;2;42;41;41m0\033[38;2;41;40;40m01\033[38;2;40;40;38m1\033[38;2;41;41;39m1\033[38;2;44;44;42m1\033[38;2;49;48;46m1\033[38;2;55;55;53m0\033[38;2;66;66;64m0\033[38;2;104;104;102m1\033[38;2;179;179;177m1\033[38;2;232;232;231m0\033[38;2;207;207;205m0\033[38;2;143;143;141m0\033[38;2;88;89;89m1\033[38;2;82;84;84m0\033[38;2;101;103;103m1\033[38;2;97;99;100m1\033[38;2;85;88;90m1\033[38;2;62;64;66m0\033[38;2;49;51;52m0\033[38;2;43;45;46m1\033[38;2;37;38;40m1\033[38;2;32;33;35m0\033[38;2;28;29;30m0\033[38;2;26;26;26m1\033[38;2;23;23;24m0\033[38;2;22;22;22m1\033[38;2;21;21;22m0\033[38;2;21;21;21m0\033[0m
\033[38;2;13;13;12m1\033[38;2;14;14;14m0\033[38;2;15;15;15m0\033[38;2;17;17;17m1\033[38;2;21;21;21m1\033[38;2;28;28;28m1\033[38;2;42;42;42m0\033[38;2;68;68;68m0\033[38;2;154;155;155m0\033[38;2;153;154;153m1\033[38;2;115;115;113m1\033[38;2;67;67;66m1\033[38;2;55;55;54m0\033[38;2;50;50;48m0\033[38;2;50;51;49m0\033[38;2;67;67;65m0\033[38;2;102;102;100m1\033[38;2;133;132;130m1\033[38;2;146;145;143m0\033[38;2;149;149;147m0\033[38;2;151;151;149m0\033[38;2;152;151;150m1\033[38;2;151;151;149m0\033[38;2;155;155;153m1\033[38;2;162;162;161m1\033[38;2;116;115;113m0\033[38;2;83;82;79m0\033[38;2;79;79;75m0\033[38;2;54;55;52m1\033[38;2;43;42;42m0\033[38;2;41;40;41m0\033[38;2;40;40;40m11\033[38;2;42;42;40m1\033[38;2;45;46;44m1\033[38;2;52;52;51m1\033[38;2;62;62;60m1\033[38;2;93;93;91m0\033[38;2;165;166;164m1\033[38;2;220;220;219m0\033[38;2;195;195;193m1\033[38;2;131;130;128m0\033[38;2;93;92;90m1\033[38;2;93;93;90m1\033[38;2;131;132;129m0\033[38;2;197;198;196m1\033[38;2;233;233;230m1\033[38;2;190;190;189m0\033[38;2;187;189;189m0\033[38;2;182;184;184m0\033[38;2;101;104;105m1\033[38;2;63;65;66m1\033[38;2;50;52;53m0\033[38;2;40;42;44m1\033[38;2;33;35;36m0\033[38;2;28;29;31m1\033[38;2;26;26;26m0\033[38;2;24;24;24m1\033[38;2;23;23;23m0\033[38;2;22;22;22m0\033[0m
\033[38;2;13;13;13m0\033[38;2;14;14;14m0\033[38;2;15;15;15m1\033[38;2;17;17;17m0\033[38;2;19;19;20m0\033[38;2;25;25;25m1\033[38;2;33;33;33m0\033[38;2;44;44;45m0\033[38;2;89;90;90m1\033[38;2;203;203;202m1\033[38;2;177;176;176m1\033[38;2;102;102;101m0\033[38;2;69;67;66m1\033[38;2;65;64;63m0\033[38;2;70;69;68m1\033[38;2;139;139;136m0\033[38;2;243;244;243m0\033[38;2;223;222;220m1\033[38;2;191;190;187m0\033[38;2;188;188;186m0\033[38;2;187;187;186m1\033[38;2;188;188;185m0\033[38;2;190;190;188m0\033[38;2;191;190;187m1\033[38;2;198;197;193m1\033[38;2;195;194;191m0\033[38;2;212;211;208m0\033[38;2;154;154;150m1\033[38;2;73;73;70m1\033[38;2;49;48;47m1\033[38;2;45;44;44m1\033[38;2;44;44;43m1\033[38;2;47;47;45m1\033[38;2;52;52;50m1\033[38;2;61;61;59m1\033[38;2;93;92;90m0\033[38;2;164;164;161m1\033[38;2;227;227;225m0\033[38;2;202;203;200m1\033[38;2;121;120;118m1\033[38;2;78;77;75m0\033[38;2;77;76;75m0\033[38;2;82;81;79m0\033[38;2;122;122;117m1\033[38;2;170;170;166m1\033[38;2;186;186;184m1\033[38;2;126;127;126m0\033[38;2;126;127;127m0\033[38;2;148;149;149m1\033[38;2;179;180;179m1\033[38;2;220;222;222m0\033[38;2;146;152;155m1\033[38;2;71;74;76m0\033[38;2;53;55;57m1\033[38;2;41;43;44m0\033[38;2;33;35;36m0\033[38;2;29;29;29m0\033[38;2;25;25;25m1\033[38;2;23;23;24m1\033[38;2;22;22;23m0\033[0m
\033[38;2;13;13;13m0\033[38;2;14;14;14m1\033[38;2;15;15;15m0\033[38;2;17;17;17m0\033[38;2;19;19;18m0\033[38;2;21;21;20m1\033[38;2;26;26;25m1\033[38;2;35;35;35m1\033[38;2;52;52;51m1\033[38;2;91;91;88m1\033[38;2;172;172;171m1\033[38;2;216;216;215m0\033[38;2;173;172;170m0\033[38;2;111;109;107m1\033[38;2;89;88;84m1\033[38;2;110;109;106m0\033[38;2;201;201;199m0\033[38;2;201;200;197m0\033[38;2;112;111;108m1\033[38;2;92;90;89m0\033[38;2;89;88;86m1\033[38;2;91;89;87m1\033[38;2;103;101;99m1\033[38;2;154;152;150m1\033[38;2;220;219;217m0\033[38;2;224;224;221m1\033[38;2;165;165;163m1\033[38;2;96;95;93m0\033[38;2;64;62;61m1\033[38;2;55;54;53m0\033[38;2;53;53;51m1\033[38;2;56;56;54m1\033[38;2;64;64;61m0\033[38;2;93;92;90m0\033[38;2;161;160;158m1\033[38;2;220;221;218m1\033[38;2;197;197;195m1\033[38;2;131;130;128m0\033[38;2;82;82;80m0\033[38;2;72;71;69m0\033[38;2;104;104;101m0\033[38;2;142;144;142m0\033[38;2;149;150;148m0\033[38;2;109;111;109m0\033[38;2;83;83;82m1\033[38;2;70;70;69m0\033[38;2;64;65;65m0\033[38;2;70;71;71m0\033[38;2;106;107;107m1\033[38;2;143;144;143m0\033[38;2;169;170;168m1\033[38;2;233;235;235m1\033[38;2;135;141;145m1\033[38;2;68;70;71m0\033[38;2;50;52;54m0\033[38;2;39;40;41m0\033[38;2;32;32;32m1\033[38;2;27;27;27m1\033[38;2;25;25;25m0\033[38;2;23;23;23m0\033[0m
\033[38;2;13;13;13m0\033[38;2;14;14;13m1\033[38;2;15;15;14m0\033[38;2;16;17;16m0\033[38;2;17;17;17m1\033[38;2;19;19;18m1\033[38;2;21;22;20m0\033[38;2;26;26;26m1\033[38;2;33;33;32m0\033[38;2;43;43;41m0\033[38;2;61;61;59m0\033[38;2;108;108;107m0\033[38;2;184;184;182m0\033[38;2;221;221;220m1\033[38;2;180;180;177m0\033[38;2;182;181;178m0\033[38;2;223;224;221m0\033[38;2;183;184;180m1\033[38;2;117;116;113m0\033[38;2;86;84;82m0\033[38;2;88;87;85m1\033[38;2;133;131;130m1\033[38;2;207;207;205m1\033[38;2;230;230;228m1\033[38;2;175;175;172m1\033[38;2;107;107;105m0\033[38;2;74;73;71m0\033[38;2;64;62;61m0\033[38;2;61;59;58m1\033[38;2;63;61;60m1\033[38;2;70;69;67m0\033[38;2;95;95;92m1\033[38;2;160;160;157m1\033[38;2;222;221;220m0\033[38;2;202;203;201m0\033[38;2;126;126;124m1\033[38;2;77;76;74m1\033[38;2;64;62;61m0\033[38;2;63;62;61m0\033[38;2;69;68;66m1\033[38;2;104;103;99m0\033[38;2;175;175;171m1\033[38;2;219;219;216m0\033[38;2;226;228;228m1\033[38;2;121;123;124m1\033[38;2;71;70;70m0\033[38;2;61;61;61m10\033[38;2;70;72;72m0\033[38;2;125;126;125m1\033[38;2;144;144;143m1\033[38;2;208;208;206m0\033[38;2;205;210;213m1\033[38;2;90;94;96m0\033[38;2;56;58;59m0\033[38;2;43;44;45m0\033[38;2;35;35;35m0\033[38;2;29;29;29m0\033[38;2;25;25;25m0\033[38;2;24;24;24m1\033[0m
\033[38;2;13;13;13m0\033[38;2;14;14;13m1\033[38;2;15;15;14m1\033[38;2;15;15;15m1\033[38;2;16;16;16m0\033[38;2;17;17;17m0\033[38;2;19;20;18m1\033[38;2;22;22;20m0\033[38;2;25;25;23m1\033[38;2;29;30;28m1\033[38;2;37;37;35m0\033[38;2;47;47;45m1\033[38;2;64;64;62m0\033[38;2;109;109;107m0\033[38;2;157;157;155m0\033[38;2;172;172;169m1\033[38;2;150;150;147m1\033[38;2;115;114;110m0\033[38;2;104;102;99m1\033[38;2;139;137;134m1\033[38;2;199;199;196m0\033[38;2;229;229;227m0\033[38;2;181;181;179m0\033[38;2;112;111;109m1\033[38;2;76;75;73m0\033[38;2;64;63;61m1\033[38;2;61;60;58m0\033[38;2;63;62;60m1\033[38;2;70;70;68m0\033[38;2;96;96;93m0\033[38;2;160;159;156m1\033[38;2;225;225;222m0\033[38;2;218;218;216m0\033[38;2;141;140;138m1\033[38;2;84;83;82m0\033[38;2;68;67;65m1\033[38;2;64;63;60m0\033[38;2;62;62;59m1\033[38;2;64;63;62m1\033[38;2;70;69;68m0\033[38;2;81;80;77m0\033[38;2;111;110;107m1\033[38;2;174;174;170m1\033[38;2;245;245;243m0\033[38;2;176;178;178m1\033[38;2;73;73;72m1\033[38;2;60;60;60m0\033[38;2;57;59;59m0\033[38;2;65;67;67m1\033[38;2;101;102;103m0\033[38;2;148;148;149m1\033[38;2;186;187;186m1\033[38;2;227;230;231m1\033[38;2;104;109;111m1\033[38;2;61;63;64m0\033[38;2;46;47;49m1\033[38;2;36;36;36m1\033[38;2;29;29;29m1\033[38;2;26;26;26m0\033[38;2;24;24;24m0\033[0m
\033[38;2;14;14;14m101\033[38;2;15;15;14m0\033[38;2;15;15;15m1\033[38;2;17;17;17m1\033[38;2;19;19;17m0\033[38;2;20;20;18m1\033[38;2;22;22;20m0\033[38;2;25;25;23m1\033[38;2;29;29;27m1\033[38;2;34;35;32m1\033[38;2;41;41;39m0\033[38;2;49;48;46m0\033[38;2;59;58;56m1\033[38;2;71;70;68m0\033[38;2;85;83;82m0\033[38;2;126;125;122m0\033[38;2;202;202;199m1\033[38;2;236;236;233m0\033[38;2;187;188;185m0\033[38;2;118;117;113m0\033[38;2;78;77;74m1\033[38;2;64;63;61m0\033[38;2;60;59;58m0\033[38;2;63;62;60m0\033[38;2;70;69;67m1\033[38;2;95;94;91m1\033[38;2;157;156;153m0\033[38;2;224;223;221m1\033[38;2;222;222;219m1\033[38;2;156;155;153m0\033[38;2;101;100;98m0\033[38;2;82;81;79m0\033[38;2;86;85;83m0\033[38;2;105;103;102m0\033[38;2;114;114;112m0\033[38;2;107;107;105m0\033[38;2;105;105;103m1\033[38;2;109;109;107m1\033[38;2;120;120;118m0\033[38;2;152;152;150m1\033[38;2;206;206;203m1\033[38;2;223;223;221m0\033[38;2;124;124;122m0\033[38;2;63;63;62m0\033[38;2;56;56;56m0\033[38;2;57;57;57m1\033[38;2;65;67;67m1\033[38;2;111;111;111m0\033[38;2;149;150;149m1\033[38;2;208;209;208m1\033[38;2;201;202;202m0\033[38;2;88;91;92m0\033[38;2;58;61;62m0\033[38;2;44;45;47m1\033[38;2;35;35;36m0\033[38;2;29;29;29m1\033[38;2;26;26;26m1\033[38;2;24;24;24m1\033[0m
\033[38;2;15;15;15m0\033[38;2;14;14;15m1\033[38;2;15;15;14m01\033[38;2;16;16;16m1\033[38;2;17;17;17m1\033[38;2;19;19;18m1\033[38;2;21;21;19m1\033[38;2;23;23;21m0\033[38;2;26;26;25m0\033[38;2;29;30;28m0\033[38;2;35;36;33m1\033[38;2;44;43;41m0\033[38;2;54;53;51m0\033[38;2;70;69;67m0\033[38;2;112;112;111m0\033[38;2;185;185;183m1\033[38;2;230;230;229m0\033[38;2;193;194;191m0\033[38;2;122;122;119m0\033[38;2;80;79;77m1\033[38;2;65;63;61m1\033[38;2;60;58;57m1\033[38;2;61;61;58m0\033[38;2;68;68;66m0\033[38;2;92;92;90m1\033[38;2;154;153;151m0\033[38;2;219;219;217m0\033[38;2;221;222;219m0\033[38;2;163;163;160m1\033[38;2;109;108;105m0\033[38;2;92;91;88m0\033[38;2;102;99;98m0\033[38;2;141;140;137m1\033[38;2;202;202;200m0\033[38;2;218;218;216m1\033[38;2;206;205;204m0\033[38;2;205;204;202m1\033[38;2;209;209;207m0\033[38;2;209;209;208m0\033[38;2;203;203;201m1\033[38;2;194;195;193m1\033[38;2;169;169;167m1\033[38;2;106;106;104m0\033[38;2;63;63;63m1\033[38;2;57;57;57m11\033[38;2;63;63;63m1\033[38;2;86;89;88m0\033[38;2;141;141;140m0\033[38;2;167;168;166m0\033[38;2;233;233;231m0\033[38;2;133;134;133m1\033[38;2;71;73;74m0\033[38;2;52;54;56m1\033[38;2;40;41;43m0\033[38;2;33;33;33m0\033[38;2;28;28;28m0\033[38;2;25;25;25m0\033[38;2;23;23;23m1\033[0m
\033[38;2;15;15;15m00\033[38;2;16;16;16m0\033[38;2;16;16;15m0\033[38;2;17;17;16m0\033[38;2;19;19;18m0\033[38;2;20;20;20m0\033[38;2;22;23;21m0\033[38;2;26;26;24m0\033[38;2;31;31;30m1\033[38;2;38;38;36m1\033[38;2;48;48;46m0\033[38;2;65;64;62m0\033[38;2;107;105;103m0\033[38;2;181;181;178m1\033[38;2;230;231;229m1\033[38;2;199;199;196m0\033[38;2;127;127;124m0\033[38;2;79;78;76m0\033[38;2;63;62;61m1\033[38;2;60;58;56m1\033[38;2;62;60;59m0\033[38;2;68;68;66m1\033[38;2;90;91;88m0\033[38;2;150;150;147m0\033[38;2;217;218;215m0\033[38;2;218;218;215m1\033[38;2;153;152;149m1\033[38;2;99;98;96m0\033[38;2;84;82;80m1\033[38;2;91;89;87m0\033[38;2;135;134;131m1\033[38;2;209;208;206m0\033[38;2;234;234;232m0\033[38;2;189;189;187m1\033[38;2;124;124;121m1\033[38;2;98;96;95m1\033[38;2;94;92;91m1\033[38;2;92;91;89m0\033[38;2;88;87;86m1\033[38;2;79;79;77m0\033[38;2;69;69;67m1\033[38;2;60;60;58m1\033[38;2;56;56;56m1\033[38;2;57;57;57m0\033[38;2;59;59;59m1\033[38;2;67;67;67m1\033[38;2;92;92;92m0\033[38;2;140;142;140m0\033[38;2;182;183;181m0\033[38;2;227;228;225m0\033[38;2;154;154;153m1\033[38;2;77;79;79m1\033[38;2;56;58;59m0\033[38;2;44;46;47m1\033[38;2;35;36;38m1\033[38;2;30;30;31m0\033[38;2;27;27;27m1\033[38;2;25;25;25m0\033[38;2;23;23;23m1\033[0m
\033[38;2;15;15;15m0\033[38;2;16;16;16m11\033[38;2;17;17;17m0\033[38;2;18;19;18m0\033[38;2;21;21;21m0\033[38;2;24;24;22m1\033[38;2;29;29;27m1\033[38;2;36;36;34m0\033[38;2;45;45;43m1\033[38;2;60;60;58m0\033[38;2;98;99;97m0\033[38;2;175;175;173m0\033[38;2;230;230;227m1\033[38;2;201;201;198m0\033[38;2;129;129;126m1\033[38;2;80;79;77m0\033[38;2;62;61;59m0\033[38;2;58;56;55m0\033[38;2;60;60;58m1\033[38;2;69;69;66m0\033[38;2;90;90;87m1\033[38;2;146;146;143m0\033[38;2;217;218;216m0\033[38;2;225;225;223m1\033[38;2;155;156;154m0\033[38;2;94;94;92m0\033[38;2;73;71;70m1\033[38;2;68;67;66m1\033[38;2;72;70;68m1\033[38;2;83;82;81m1\033[38;2;148;148;146m0\033[38;2;243;243;241m0\033[38;2;219;220;218m0\033[38;2;130;129;127m1\033[38;2;90;88;87m1\033[38;2;75;73;72m0\033[38;2;64;62;61m0\033[38;2;57;56;54m1\033[38;2;53;53;51m1\033[38;2;50;50;49m0\033[38;2;49;49;48m0\033[38;2;50;50;49m1\033[38;2;54;54;54m0\033[38;2;64;64;64m1\033[38;2;88;88;87m1\033[38;2;129;129;128m0\033[38;2;174;175;174m1\033[38;2;208;209;208m1\033[38;2;208;208;207m1\033[38;2;133;134;133m0\033[38;2;73;74;75m1\033[38;2;55;57;58m1\033[38;2;45;46;47m1\033[38;2;37;39;40m1\033[38;2;32;33;33m0\033[38;2;29;29;29m1\033[38;2;26;26;26m0\033[38;2;24;24;24m1\033[38;2;23;23;22m0\033[0m
\033[38;2;15;15;16m1\033[38;2;16;16;16m0\033[38;2;17;17;17m1\033[38;2;19;19;19m1\033[38;2;21;22;20m1\033[38;2;25;26;24m1\033[38;2;32;32;30m1\033[38;2;42;42;40m0\033[38;2;56;56;54m1\033[38;2;93;93;91m0\033[38;2;169;169;167m0\033[38;2;227;227;226m0\033[38;2;203;204;202m0\033[38;2;132;132;129m1\033[38;2;80;79;77m0\033[38;2;62;60;58m0\033[38;2;56;55;53m0\033[38;2;58;56;55m1\033[38;2;66;65;63m1\033[38;2;88;88;86m0\033[38;2;143;142;140m1\033[38;2;213;213;212m0\033[38;2;230;231;229m0\033[38;2;170;171;169m0\033[38;2;103;102;100m0\033[38;2;75;73;72m0\033[38;2;67;65;64m1\033[38;2;62;61;59m0\033[38;2;61;59;58m0\033[38;2;62;60;59m1\033[38;2;67;65;64m0\033[38;2;78;77;75m0\033[38;2;108;107;105m1\033[38;2;147;146;143m0\033[38;2;169;169;166m0\033[38;2;137;137;134m1\033[38;2;101;100;98m0\033[38;2;74;73;71m1\033[38;2;62;62;61m1\033[38;2;56;56;56m1\033[38;2;51;51;51m0\033[38;2;49;49;49m10\033[38;2;54;55;54m0\033[38;2;87;87;86m1\033[38;2;139;140;137m0\033[38;2;196;197;195m1\033[38;2;190;192;191m0\033[38;2;140;142;142m0\033[38;2;92;93;93m0\033[38;2;67;67;67m0\033[38;2;55;55;57m0\033[38;2;46;47;49m0\033[38;2;40;40;42m1\033[38;2;35;35;36m1\033[38;2;31;31;31m0\033[38;2;28;28;28m0\033[38;2;26;26;26m0\033[38;2;24;24;24m1\033[38;2;23;23;23m0\033[0m
\033[38;2;16;16;16m1\033[38;2;17;17;17m0\033[38;2;19;19;18m0\033[38;2;21;22;20m1\033[38;2;25;26;24m1\033[38;2;34;35;33m0\033[38;2;48;49;48m0\033[38;2;73;73;72m1\033[38;2;149;148;146m0\033[38;2;222;221;219m0\033[38;2;206;206;204m1\033[38;2;131;131;129m0\033[38;2;75;75;73m0\033[38;2;55;54;53m0\033[38;2;50;48;47m11\033[38;2;58;57;55m1\033[38;2;78;78;76m1\033[38;2;134;134;132m1\033[38;2;209;209;207m0\033[38;2;230;230;228m1\033[38;2;178;179;176m1\033[38;2;115;114;113m0\033[38;2;87;85;83m0\033[38;2;78;77;76m0\033[38;2;74;73;72m0\033[38;2;71;70;68m0\033[38;2;69;68;67m0\033[38;2;68;68;65m0\033[38;2;67;67;65m0\033[38;2;67;66;64m0\033[38;2;69;67;65m0\033[38;2;72;70;69m1\033[38;2;81;79;77m0\033[38;2;112;111;107m1\033[38;2;198;197;195m1\033[38;2;232;232;230m1\033[38;2;179;179;177m1\033[38;2;105;106;104m0\033[38;2;78;77;77m0\033[38;2;67;67;66m0\033[38;2;59;59;58m1\033[38;2;57;57;57m1\033[38;2;61;61;60m1\033[38;2;83;83;82m1\033[38;2;124;124;122m1\033[38;2;187;186;184m0\033[38;2;201;202;202m1\033[38;2;134;136;137m0\033[38;2;88;90;90m0\033[38;2;68;69;70m1\033[38;2;56;58;59m0\033[38;2;48;50;51m1\033[38;2;42;42;42m0\033[38;2;37;37;37m1\033[38;2;33;33;33m1\033[38;2;30;30;30m0\033[38;2;28;28;28m1\033[38;2;27;27;27m0\033[38;2;25;25;26m0\033[0m
\033[38;2;17;17;17m1\033[38;2;19;19;19m0\033[38;2;21;21;20m0\033[38;2;25;25;23m0\033[38;2;34;34;32m1\033[38;2;50;50;49m0\033[38;2;82;82;81m1\033[38;2;182;182;180m0\033[38;2;224;224;221m1\033[38;2;149;149;146m1\033[38;2;77;77;76m1\033[38;2;52;51;49m0\033[38;2;43;42;40m1\033[38;2;38;38;36m11\033[38;2;43;43;41m0\033[38;2;62;61;59m1\033[38;2;164;164;160m0\033[38;2;233;232;230m1\033[38;2;176;175;170m0\033[38;2;149;147;143m1\033[38;2;171;170;168m1\033[38;2;182;181;180m0\033[38;2;181;180;179m0\033[38;2;179;179;177m1\033[38;2;177;177;175m1\033[38;2;176;176;174m0\033[38;2;175;175;173m0\033[38;2;175;175;174m0\033[38;2;174;174;173m01\033[38;2;172;172;170m1\033[38;2;150;150;148m1\033[38;2;113;113;110m0\033[38;2;93;93;90m1\033[38;2;108;106;104m1\033[38;2;154;154;151m1\033[38;2;220;220;218m1\033[38;2;227;227;226m1\033[38;2;169;169;169m1\033[38;2;110;110;109m1\033[38;2;80;80;79m1\033[38;2;70;70;68m1\033[38;2;65;65;64m0\033[38;2;64;64;64m0\033[38;2;75;75;74m1\033[38;2;108;108;106m1\033[38;2;174;175;173m1\033[38;2;229;229;228m1\033[38;2;205;206;206m0\033[38;2;132;134;135m1\033[38;2;82;84;85m1\033[38;2;63;64;65m0\033[38;2;52;54;54m1\033[38;2;44;46;45m0\033[38;2;39;40;40m0\033[38;2;34;35;36m1\033[38;2;31;31;33m0\033[38;2;29;29;31m1\033[38;2;27;27;27m1\033[0m
\033[38;2;18;18;17m0\033[38;2;20;20;20m0\033[38;2;24;25;24m1\033[38;2;33;33;31m0\033[38;2;48;48;46m0\033[38;2;74;74;73m1\033[38;2;166;165;164m0\033[38;2;239;240;237m1\033[38;2;152;153;150m0\033[38;2;78;78;76m1\033[38;2;50;49;47m1\033[38;2;39;39;37m0\033[38;2;34;34;32m0\033[38;2;33;34;32m1\033[38;2;34;35;32m0\033[38;2;38;38;36m0\033[38;2;47;46;45m0\033[38;2;80;79;77m1\033[38;2;88;87;84m1\033[38;2;75;73;70m1\033[38;2;127;126;124m1\033[38;2;161;161;159m1\033[38;2;154;153;152m0\033[38;2;157;156;154m0\033[38;2;157;157;155m1\033[38;2;156;156;154m00\033[38;2;157;157;154m0\033[38;2;157;156;155m0\033[38;2;158;157;155m1\033[38;2;159;158;157m0\033[38;2;168;167;166m0\033[38;2;204;204;202m0\033[38;2;231;232;230m1\033[38;2;184;185;183m1\033[38;2;121;120;118m0\033[38;2;98;96;95m0\033[38;2;110;109;107m1\033[38;2;162;162;160m1\033[38;2;225;225;224m1\033[38;2;228;229;228m1\033[38;2;165;166;165m1\033[38;2;107;106;105m0\033[38;2;81;81;79m1\033[38;2;70;70;69m0\033[38;2;66;66;66m0\033[38;2;67;68;68m1\033[38;2;80;80;80m0\033[38;2;120;120;118m1\033[38;2;188;187;185m0\033[38;2;230;231;230m0\033[38;2;197;198;198m1\033[38;2;123;125;126m1\033[38;2;78;80;81m0\033[38;2;60;62;63m1\033[38;2;49;50;52m1\033[38;2;41;43;44m0\033[38;2;36;37;39m0\033[38;2;32;33;35m1\033[38;2;29;29;30m1\033[0m
\033[38;2;19;19;17m1\033[38;2;22;22;21m1\033[38;2;29;29;27m1\033[38;2;43;43;41m0\033[38;2;69;69;67m1\033[38;2;153;153;151m0\033[38;2;246;246;245m0\033[38;2;182;181;178m1\033[38;2;97;95;93m0\033[38;2;56;55;53m0\033[38;2;44;43;41m0\033[38;2;37;37;35m0\033[38;2;35;35;33m0\033[38;2;36;36;34m0\033[38;2;37;37;34m1\033[38;2;37;38;35m1\033[38;2;39;39;37m0\033[38;2;38;38;36m1\033[38;2;41;40;39m1\033[38;2;47;45;46m0\033[38;2;49;47;48m0\033[38;2;51;50;49m1\033[38;2;56;55;53m1\033[38;2;59;58;56m0\033[38;2;61;59;58m0\033[38;2;62;60;59m1\033[38;2;63;61;60m1\033[38;2;64;62;61m0\033[38;2;65;63;62m1\033[38;2;66;64;63m0\033[38;2;70;68;67m1\033[38;2;77;76;74m0\033[38;2;94;93;91m0\033[38;2;143;142;141m1\033[38;2;214;213;211m0\033[38;2;233;233;232m0\033[38;2;178;178;177m0\033[38;2;117;116;114m1\033[38;2;96;95;93m0\033[38;2;111;109;108m0\033[38;2;164;163;161m0\033[38;2;221;221;219m1\033[38;2;221;222;221m1\033[38;2;159;159;159m1\033[38;2;109;110;108m0\033[38;2;80;80;78m0\033[38;2;70;69;69m0\033[38;2;67;67;67m0\033[38;2;74;74;74m1\033[38;2;91;91;90m0\033[38;2;132;133;132m0\033[38;2;201;201;200m0\033[38;2;236;236;236m0\033[38;2;189;190;191m0\033[38;2;116;118;119m0\033[38;2;72;74;75m0\033[38;2;55;57;58m1\033[38;2;44;45;47m1\033[38;2;36;37;39m0\033[38;2;31;32;34m0\033[0m
\033[38;2;18;18;16m0\033[38;2;22;22;20m0\033[38;2;31;31;29m1\033[38;2;45;44;43m0\033[38;2;110;109;107m0\033[38;2;243;243;241m1\033[38;2;204;204;201m1\033[38;2;108;107;103m0\033[38;2;66;64;61m0\033[38;2;56;54;52m1\033[38;2;54;52;51m0\033[38;2;52;51;49m1\033[38;2;53;52;51m1\033[38;2;55;54;52m1\033[38;2;56;56;54m1\033[38;2;57;58;55m1\033[38;2;59;59;57m11\033[38;2;60;60;58m1\033[38;2;62;62;60m1\033[38;2;65;64;63m0\033[38;2;67;66;65m0\033[38;2;69;68;66m1\033[38;2;70;69;67m1\033[38;2;72;70;69m010\033[38;2;72;71;69m1\033[38;2;74;73;71m0\033[38;2;75;74;73m0\033[38;2;78;77;75m1\033[38;2;81;80;78m1\033[38;2;84;83;80m1\033[38;2;90;87;85m1\033[38;2;107;105;102m1\033[38;2;158;156;153m0\033[38;2;224;225;223m1\033[38;2;226;226;226m0\033[38;2;148;147;145m0\033[38;2;94;92;91m0\033[38;2;85;83;82m0\033[38;2;104;103;101m0\033[38;2;171;172;169m1\033[38;2;238;239;238m1\033[38;2;224;225;224m1\033[38;2;142;143;142m1\033[38;2;95;96;95m0\033[38;2;85;85;84m1\033[38;2;82;82;82m0\033[38;2;87;87;87m0\033[38;2;97;97;97m1\033[38;2;113;115;115m0\033[38;2;156;158;158m1\033[38;2;205;206;205m1\033[38;2;222;223;223m1\033[38;2;155;158;158m1\033[38;2;73;77;80m0\033[38;2;48;50;54m1\033[38;2;37;39;42m1\033[38;2;31;33;35m1\033[0m
\033[38;2;17;17;15m1\033[38;2;20;19;18m0\033[38;2;24;23;21m1\033[38;2;50;49;46m1\033[38;2;110;110;106m1\033[38;2;125;125;122m1\033[38;2;73;72;68m0\033[38;2;100;98;95m0\033[38;2;183;182;179m1\033[38;2;175;174;171m0\033[38;2;160;160;158m1\033[38;2;170;170;168m1\033[38;2;165;164;162m1\033[38;2;166;164;163m0\033[38;2;167;166;165m0\033[38;2;168;168;167m1\033[38;2;169;169;168m0\033[38;2;170;170;169m0\033[38;2;172;171;170m00\033[38;2;173;172;171m1\033[38;2;175;175;174m1\033[38;2;175;175;173m010\033[38;2;174;174;172m0\033[38;2;175;174;173m01\033[38;2;175;175;173m1\033[38;2;175;175;174m1\033[38;2;177;177;176m1\033[38;2;178;178;177m0\033[38;2;178;178;176m0\033[38;2;180;179;177m0\033[38;2;197;196;194m1\033[38;2;186;185;183m0\033[38;2;143;141;137m1\033[38;2;149;147;144m0\033[38;2;130;130;126m0\033[38;2;101;101;98m1\033[38;2;69;69;68m0\033[38;2;63;62;62m1\033[38;2;73;73;72m1\033[38;2;99;99;98m1\033[38;2;130;131;130m0\033[38;2;144;146;146m0\033[38;2;138;140;142m0\033[38;2;171;171;171m1\033[38;2;174;174;173m1\033[38;2;180;180;178m0\033[38;2;207;207;207m0\033[38;2;200;201;201m1\033[38;2;184;185;185m0\033[38;2;173;175;175m1\033[38;2;181;183;184m0\033[38;2;168;173;177m1\033[38;2;86;94;101m0\033[38;2;56;61;65m0\033[38;2;32;34;37m0\033[38;2;29;30;33m0\033[0m
\033[38;2;15;14;13m0\033[38;2;16;15;14m0\033[38;2;16;16;14m1\033[38;2;37;37;34m1\033[38;2;38;37;34m0\033[38;2;34;32;29m0\033[38;2;51;49;46m1\033[38;2;66;65;62m1\033[38;2;131;130;129m0\033[38;2;142;143;142m1\033[38;2;137;137;136m0\033[38;2;140;140;139m0\033[38;2;141;141;140m0\033[38;2;143;143;142m0\033[38;2;145;144;144m0\033[38;2;145;145;144m1\033[38;2;147;147;147m0\033[38;2;150;151;150m0\033[38;2;153;153;152m011\033[38;2;155;155;154m1\033[38;2;156;156;155m0\033[38;2;155;155;154m0\033[38;2;155;155;153m1\033[38;2;154;154;153m0\033[38;2;154;155;154m1\033[38;2;155;155;154m1\033[38;2;154;154;154m1\033[38;2;154;153;153m0\033[38;2;153;153;152m0\033[38;2;153;152;152m1\033[38;2;151;151;150m00\033[38;2;160;160;159m0\033[38;2;131;131;131m1\033[38;2;72;71;69m1\033[38;2;57;56;54m0\033[38;2;55;55;55m1\033[38;2;51;52;51m0\033[38;2;41;41;41m0\033[38;2;39;39;39m00\033[38;2;40;40;40m1\033[38;2;43;43;43m1\033[38;2;51;51;51m0\033[38;2;70;71;71m1\033[38;2;112;114;114m1\033[38;2;139;140;139m1\033[38;2;151;152;152m1\033[38;2;165;165;165m1\033[38;2;158;159;160m0\033[38;2;142;143;144m0\033[38;2;137;138;139m0\033[38;2;122;124;125m0\033[38;2;83;87;91m0\033[38;2;49;52;56m0\033[38;2;34;36;39m1\033[38;2;29;30;32m0\033[38;2;25;26;29m1\033[0m
\033[38;2;13;12;12m0\033[38;2;13;13;12m1\033[38;2;15;15;14m1\033[38;2;14;15;14m0\033[38;2;16;16;15m0\033[38;2;18;17;17m0\033[38;2;19;19;18m0\033[38;2;22;21;20m10\033[38;2;24;24;23m0\033[38;2;28;28;27m1\033[38;2;30;30;29m1\033[38;2;31;31;30m1\033[38;2;32;32;32m1\033[38;2;33;33;33m1\033[38;2;34;34;34m0\033[38;2;35;35;35m0\033[38;2;36;36;36m1\033[38;2;37;38;38m0\033[38;2;39;39;39m1\033[38;2;40;40;40m00\033[38;2;41;41;40m1\033[38;2;41;42;41m0\033[38;2;42;42;41m1\033[38;2;42;42;42m1101\033[38;2;42;42;41m1\033[38;2;41;41;41m0\033[38;2;41;41;40m1\033[38;2;40;40;39m1\033[38;2;38;38;37m0\033[38;2;34;34;34m0\033[38;2;31;31;31m1\033[38;2;33;33;32m1\033[38;2;32;32;31m1\033[38;2;30;30;29m1\033[38;2;28;28;28m01\033[38;2;27;27;27m111\033[38;2;28;28;28m1\033[38;2;29;29;29m0\033[38;2;32;32;32m1\033[38;2;33;34;34m1\033[38;2;35;35;35m0\033[38;2;37;37;37m1\033[38;2;38;38;38m0\033[38;2;39;39;39m1\033[38;2;38;39;39m1\033[38;2;36;36;37m1\033[38;2;32;32;33m1\033[38;2;30;30;31m1\033[38;2;29;29;29m0\033[38;2;27;27;27m0\033[38;2;25;25;25m0\033[38;2;23;23;24m0\033[0m
\033[38;2;12;12;12m0\033[38;2;13;13;13m0\033[38;2;14;14;14m1\033[38;2;14;14;15m1\033[38;2;15;15;15m1\033[38;2;16;16;16m00\033[38;2;17;17;17m0\033[38;2;18;18;18m1\033[38;2;19;19;18m1\033[38;2;19;19;19m1\033[38;2;20;20;20m0\033[38;2;20;21;19m0\033[38;2;20;20;20m1\033[38;2;21;21;21m0\033[38;2;21;22;21m1\033[38;2;21;21;21m0\033[38;2;22;22;22m00\033[38;2;23;23;22m0\033[38;2;23;23;23m1\033[38;2;23;24;23m1\033[38;2;24;24;22m1\033[38;2;24;24;23m0\033[38;2;24;24;24m001\033[38;2;25;25;25m01\033[38;2;24;24;24m1\033[38;2;25;25;24m1\033[38;2;24;25;24m1\033[38;2;24;24;24m0\033[38;2;25;25;25m01\033[38;2;24;24;24m01\033[38;2;24;24;23m1\033[38;2;23;23;23m1\033[38;2;22;22;22m10100100\033[38;2;23;23;23m1\033[38;2;24;24;24m1010\033[38;2;25;25;25m0\033[38;2;25;24;24m0\033[38;2;23;24;24m1\033[38;2;23;23;22m0\033[38;2;22;22;22m0\033[38;2;21;21;21m0\033[38;2;21;21;20m0\033[38;2;20;20;20m1\033[0m
\033[38;2;12;12;12m01\033[38;2;13;13;13m00\033[38;2;13;14;13m1\033[38;2;14;14;14m0\033[38;2;15;15;15m10\033[38;2;16;16;16m001\033[38;2;16;17;17m1\033[38;2;17;17;17m11\033[38;2;18;18;18m001\033[38;2;19;19;19m1100\033[38;2;19;20;20m0\033[38;2;20;20;19m0\033[38;2;20;20;20m110\033[38;2;21;21;21m1\033[38;2;20;20;20m010\033[38;2;20;20;21m1\033[38;2;21;21;21m1\033[38;2;20;20;20m1\033[38;2;21;21;21m0\033[38;2;20;20;20m01011101\033[38;2;19;20;19m1\033[38;2;19;19;19m1\033[38;2;20;20;20m00\033[38;2;19;19;20m1\033[38;2;20;20;20m00001\033[38;2;21;21;21m0\033[38;2;20;21;20m0\033[38;2;20;20;20m10\033[38;2;19;20;19m1\033[38;2;19;19;19m00\033[38;2;18;18;18m0\033[0m
EOF_TUI_LOGO
}
_tui_logo_medium_block() {
    while IFS= read -r line; do printf '%b\n' "$line"; done <<'EOF_TUI_LOGO_MEDIUM'
\033[38;2;12;12;12m0\033[38;2;14;14;14m010\033[38;2;15;15;15m0\033[38;2;16;16;16m1\033[38;2;18;18;18m01\033[38;2;20;20;20m10\033[38;2;21;21;21m01001\033[38;2;22;22;22m000\033[38;2;21;21;21m10\033[38;2;20;20;20m1\033[38;2;19;19;19m0\033[38;2;18;18;18m1\033[38;2;17;17;17m000\033[38;2;16;16;16m0111\033[0m
\033[38;2;13;13;13m1\033[38;2;14;14;14m01\033[38;2;15;15;15m1\033[38;2;18;18;18m1\033[38;2;22;22;22m0\033[38;2;25;25;25m0\033[38;2;29;29;29m1\033[38;2;31;32;32m1\033[38;2;33;33;33m0\033[38;2;34;34;34m1\033[38;2;33;33;33m1\033[38;2;32;32;32m00\033[38;2;33;33;33m0\033[38;2;34;34;34m0\033[38;2;34;35;35m1\033[38;2;34;34;34m00\033[38;2;36;36;36m0\033[38;2;34;34;34m0\033[38;2;28;28;28m0\033[38;2;23;23;23m1\033[38;2;20;20;20m11\033[38;2;19;19;19m0\033[38;2;18;18;18m10\033[38;2;17;17;17m0\033[38;2;18;17;18m0\033[0m
\033[38;2;12;12;12m0\033[38;2;14;14;14m0\033[38;2;16;16;16m0\033[38;2;23;23;23m1\033[38;2;44;44;44m0\033[38;2;79;80;80m1\033[38;2;116;116;116m1\033[38;2;152;152;150m1\033[38;2;157;157;156m1\033[38;2;160;160;158m1\033[38;2;162;162;160m0\033[38;2;161;162;160m0\033[38;2;159;160;158m1\033[38;2;159;159;158m01\033[38;2;160;160;159m0\033[38;2;160;160;160m1\033[38;2;161;161;161m1\033[38;2;162;162;162m0\033[38;2;165;166;164m1\033[38;2;180;179;177m0\033[38;2;105;105;104m0\033[38;2;57;59;59m1\033[38;2;34;36;37m1\033[38;2;26;25;26m0\033[38;2;23;23;24m0\033[38;2;21;21;22m1\033[38;2;20;20;21m0\033[38;2;20;20;20m11\033[0m
\033[38;2;13;13;13m1\033[38;2;15;15;15m1\033[38;2;23;23;23m0\033[38;2;52;52;52m1\033[38;2;179;179;178m0\033[38;2;150;150;149m1\033[38;2;59;60;59m0\033[38;2;56;56;56m1\033[38;2;60;60;60m1\033[38;2;66;65;66m0\033[38;2;68;67;67m1\033[38;2;67;66;67m1\033[38;2;64;63;64m0\033[38;2;61;61;61m0\033[38;2;60;60;58m1\033[38;2;59;58;58m0\033[38;2;58;58;57m0\033[38;2;59;59;58m0\033[38;2;66;66;64m0\033[38;2;86;85;83m1\033[38;2;163;162;161m0\033[38;2;187;188;186m0\033[38;2;83;85;85m0\033[38;2;72;74;74m1\033[38;2;56;58;60m1\033[38;2;39;40;42m0\033[38;2;31;31;33m1\033[38;2;25;25;26m0\033[38;2;22;22;22m0\033[38;2;21;21;21m0\033[0m
\033[38;2;14;14;13m0\033[38;2;16;16;16m1\033[38;2;23;23;24m1\033[38;2;47;47;47m0\033[38;2;150;150;150m1\033[38;2;115;115;114m1\033[38;2;60;59;58m1\033[38;2;82;82;80m0\033[38;2;175;175;173m0\033[38;2;168;168;166m0\033[38;2;170;169;168m0\033[38;2;172;172;169m0\033[38;2;168;167;164m1\033[38;2;132;132;128m0\033[38;2;55;54;53m1\033[38;2;42;42;42m1\033[38;2;45;45;44m1\033[38;2;63;63;61m0\033[38;2;136;136;134m0\033[38;2;177;177;175m0\033[38;2;120;120;118m1\033[38;2;98;97;94m1\033[38;2;171;172;169m1\033[38;2;169;169;168m1\033[38;2;174;176;175m0\033[38;2;132;136;137m0\033[38;2;54;56;58m0\033[38;2;34;36;37m0\033[38;2;26;26;26m0\033[38;2;22;22;23m1\033[0m
\033[38;2;14;14;13m1\033[38;2;16;16;16m0\033[38;2;19;19;18m1\033[38;2;27;27;26m1\033[38;2;55;55;53m1\033[38;2;139;139;138m0\033[38;2;172;172;170m1\033[38;2;140;140;136m0\033[38;2;202;202;199m0\033[38;2;102;100;98m0\033[38;2;100;99;97m1\033[38;2;174;172;170m1\033[38;2;182;181;179m1\033[38;2;100;99;97m1\033[38;2;61;59;58m1\033[38;2;68;68;66m1\033[38;2;135;134;132m0\033[38;2;177;178;175m1\033[38;2;117;116;114m1\033[38;2;72;71;69m0\033[38;2;131;132;128m1\033[38;2;176;177;175m1\033[38;2;86;86;86m1\033[38;2;64;64;64m0\033[38;2;111;112;112m0\033[38;2;188;189;188m1\033[38;2;124;129;131m1\033[38;2;47;48;50m0\033[38;2;31;31;31m0\033[38;2;24;24;24m0\033[0m
\033[38;2;14;14;14m1\033[38;2;15;15;14m1\033[38;2;16;16;16m0\033[38;2;20;20;18m0\033[38;2;25;26;24m1\033[38;2;37;37;35m1\033[38;2;66;66;64m0\033[38;2;115;114;112m1\033[38;2;119;118;115m1\033[38;2;170;169;166m0\033[38;2;183;183;180m0\033[38;2;109;108;106m0\033[38;2;66;65;63m0\033[38;2;72;71;69m1\033[38;2;137;136;134m1\033[38;2;191;190;188m0\033[38;2;136;135;133m0\033[38;2;86;84;83m0\033[38;2;87;86;84m0\033[38;2;87;86;85m1\033[38;2;116;116;113m1\033[38;2;212;212;209m0\033[38;2;109;110;108m1\033[38;2;58;58;58m0\033[38;2;86;87;87m0\033[38;2;173;174;173m1\033[38;2;155;158;159m1\033[38;2;52;54;56m0\033[38;2;32;32;32m1\033[38;2;25;25;25m0\033[0m
\033[38;2;15;15;15m0\033[38;2;16;16;15m0\033[38;2;17;17;17m0\033[38;2;20;21;20m0\033[38;2;26;26;25m1\033[38;2;38;38;36m0\033[38;2;68;66;64m0\033[38;2;148;148;146m1\033[38;2;185;185;183m0\033[38;2;114;114;112m0\033[38;2;67;65;63m1\033[38;2;70;70;67m0\033[38;2;132;132;130m0\033[38;2;186;186;183m0\033[38;2;142;141;139m0\033[38;2;107;106;103m1\033[38;2;172;170;168m0\033[38;2;183;183;181m1\033[38;2;151;149;148m0\033[38;2;150;149;148m0\033[38;2;136;136;134m1\033[38;2;98;98;96m1\033[38;2;59;59;59m1\033[38;2;70;70;70m0\033[38;2;137;139;137m0\033[38;2;195;196;194m0\033[38;2;84;86;86m1\033[38;2;43;44;46m1\033[38;2;30;30;30m0\033[38;2;24;24;24m0\033[0m
\033[38;2;16;16;16m1\033[38;2;17;17;17m1\033[38;2;21;22;21m1\033[38;2;32;32;30m0\033[38;2;58;58;56m0\033[38;2;138;139;137m0\033[38;2;185;185;183m1\033[38;2;118;117;115m0\033[38;2;64;63;61m0\033[38;2;68;67;66m0\033[38;2;129;128;126m0\033[38;2;191;192;189m0\033[38;2;140;139;137m1\033[38;2;74;73;71m0\033[38;2;66;64;63m1\033[38;2;94;93;92m0\033[38;2;179;179;177m0\033[38;2;132;131;128m0\033[38;2;78;77;76m0\033[38;2;57;57;56m1\033[38;2;50;50;49m0\033[38;2;52;52;52m0\033[38;2;94;95;94m0\033[38;2;172;173;172m1\033[38;2;162;163;162m1\033[38;2;82;82;83m0\033[38;2;46;48;49m1\033[38;2;34;34;35m1\033[38;2;27;27;27m1\033[38;2;24;24;23m1\033[0m
\033[38;2;17;17;17m0\033[38;2;22;22;20m0\033[38;2;36;36;34m0\033[38;2;96;96;95m0\033[38;2;186;186;183m1\033[38;2;116;116;114m1\033[38;2;53;52;50m0\033[38;2;45;44;43m1\033[38;2;90;90;88m0\033[38;2;188;188;185m1\033[38;2;182;182;179m1\033[38;2;141;140;139m0\033[38;2;127;126;125m1\033[38;2;123;122;120m0\033[38;2;121;121;119m0\033[38;2;120;120;118m1\033[38;2;104;103;101m1\033[38;2;128;127;124m1\033[38;2;196;196;194m1\033[38;2;145;145;144m1\033[38;2;79;79;78m1\033[38;2;63;63;62m1\033[38;2;86;86;86m1\033[38;2;168;168;166m1\033[38;2;164;165;165m1\033[38;2;84;86;87m1\033[38;2;51;52;53m0\033[38;2;38;39;39m0\033[38;2;31;31;32m1\033[38;2;27;27;28m1\033[0m
\033[38;2;20;20;19m1\033[38;2;32;32;31m0\033[38;2;86;86;84m0\033[38;2;208;208;206m0\033[38;2;96;95;93m0\033[38;2;42;42;40m1\033[38;2;34;35;33m0\033[38;2;36;37;34m0\033[38;2;51;50;49m1\033[38;2;63;61;60m1\033[38;2;97;96;95m1\033[38;2;106;106;104m0\033[38;2;109;108;106m1\033[38;2;110;109;107m0\033[38;2;112;110;109m1\033[38;2;118;117;116m0\033[38;2;168;168;166m1\033[38;2;188;188;186m0\033[38;2;126;125;123m0\033[38;2;148;148;146m1\033[38;2;194;195;193m1\033[38;2;142;142;141m1\033[38;2;81;82;80m0\033[38;2;71;71;71m0\033[38;2;118;118;117m0\033[38;2;190;191;190m0\033[38;2;156;158;158m0\033[38;2;74;76;77m0\033[38;2;44;46;47m1\033[38;2;32;33;34m0\033[0m
\033[38;2;19;19;17m0\033[38;2;38;37;35m1\033[38;2;147;147;144m1\033[38;2;121;120;117m1\033[38;2;120;118;116m1\033[38;2;109;108;106m1\033[38;2;110;108;107m0\033[38;2;112;112;110m1\033[38;2;114;114;113m0\033[38;2;116;116;114m0\033[38;2;120;119;118m1\033[38;2;122;122;120m0\033[38;2;123;122;121m0\033[38;2;124;122;121m0\033[38;2;125;124;123m1\033[38;2;128;128;126m0\033[38;2;133;132;130m0\033[38;2;162;160;158m1\033[38;2;186;185;182m0\033[38;2;118;118;115m0\033[38;2;80;79;78m0\033[38;2;145;146;144m1\033[38;2;160;161;160m1\033[38;2;122;123;123m1\033[38;2;131;131;130m0\033[38;2;154;155;155m0\033[38;2;180;181;181m1\033[38;2;182;184;186m1\033[38;2;66;70;75m0\033[38;2;32;34;37m1\033[0m
\033[38;2;14;14;13m0\033[38;2;20;21;19m1\033[38;2;26;26;24m0\033[38;2;40;38;36m1\033[38;2;80;80;78m1\033[38;2;84;84;83m0\033[38;2;87;87;86m0\033[38;2;89;89;89m1\033[38;2;92;92;92m0\033[38;2;96;96;95m0\033[38;2;97;97;96m1\033[38;2;98;98;98m0\033[38;2;98;98;97m1\033[38;2;98;98;98m11\033[38;2;97;97;96m0\033[38;2;95;95;94m0\033[38;2;89;89;89m0\033[38;2;48;48;46m1\033[38;2;41;41;41m1\033[38;2;34;34;34m0\033[38;2;33;33;33m1\033[38;2;38;38;38m0\033[38;2;62;63;63m1\033[38;2;90;91;91m1\033[38;2;100;100;100m1\033[38;2;88;89;90m0\033[38;2;67;68;70m0\033[38;2;35;36;38m0\033[38;2;26;26;28m0\033[0m
\033[38;2;12;12;12m0\033[38;2;14;14;14m1\033[38;2;14;15;14m0\033[38;2;16;16;16m0\033[38;2;17;17;17m1\033[38;2;18;18;18m0\033[38;2;18;19;18m0\033[38;2;20;20;20m10\033[38;2;21;21;20m0\033[38;2;21;22;21m1\033[38;2;22;22;21m0\033[38;2;22;22;22m001\033[38;2;22;23;22m1\033[38;2;22;22;22m011\033[38;2;21;21;21m10\033[38;2;20;21;20m0\033[38;2;21;21;21m11\033[38;2;22;22;22m11\033[38;2;23;23;22m0\033[38;2;22;22;22m1\033[38;2;20;20;20m0\033[38;2;20;20;19m0\033[0m
EOF_TUI_LOGO_MEDIUM
}

_tui_logo_small_block() {
    while IFS= read -r line; do printf '%b\n' "$line"; done <<'EOF_TUI_LOGO_SMALL'
\033[38;2;13;13;13m0\033[38;2;14;14;14m0\033[38;2;15;15;15m1\033[38;2;19;19;19m0\033[38;2;23;23;23m0\033[38;2;27;27;27m1\033[38;2;29;29;29m1100\033[38;2;30;30;30m1010\033[38;2;24;24;25m0\033[38;2;20;19;19m0\033[38;2;19;19;19m1\033[38;2;18;18;18m1\033[38;2;17;17;17m00\033[0m
\033[38;2;13;13;13m0\033[38;2;16;17;16m1\033[38;2;38;38;38m1\033[38;2;108;109;108m1\033[38;2;107;107;107m1\033[38;2;128;129;128m1\033[38;2;133;133;132m1\033[38;2;134;134;133m0\033[38;2;132;132;132m1\033[38;2;132;132;130m1\033[38;2;132;132;131m0\033[38;2;132;133;132m1\033[38;2;136;136;135m1\033[38;2;153;153;151m0\033[38;2;117;118;117m0\033[38;2;42;44;45m1\033[38;2;29;29;30m0\033[38;2;24;24;25m0\033[38;2;21;21;22m0\033[38;2;20;20;20m1\033[0m
\033[38;2;14;14;14m0\033[38;2;21;21;22m0\033[38;2;84;84;84m1\033[38;2;143;143;142m0\033[38;2;56;56;55m1\033[38;2;116;115;114m0\033[38;2;131;130;129m0\033[38;2;132;132;130m0\033[38;2;124;123;121m0\033[38;2;65;64;62m1\033[38;2;42;42;42m1\033[38;2;52;52;50m0\033[38;2;120;120;118m0\033[38;2;149;148;146m0\033[38;2;125;125;123m0\033[38;2;149;150;149m1\033[38;2;135;137;137m0\033[38;2;59;62;64m1\033[38;2;30;31;31m0\033[38;2;23;23;23m1\033[0m
\033[38;2;14;14;14m0\033[38;2;17;18;17m1\033[38;2;29;29;28m1\033[38;2;89;89;88m0\033[38;2;143;143;140m1\033[38;2;171;171;167m0\033[38;2;114;113;110m0\033[38;2;160;159;157m1\033[38;2;130;129;127m1\033[38;2;70;69;67m0\033[38;2;122;122;120m0\033[38;2;146;146;144m0\033[38;2;89;89;87m1\033[38;2;103;103;100m1\033[38;2;167;168;166m0\033[38;2;65;66;65m1\033[38;2;119;120;120m1\033[38;2;162;165;166m1\033[38;2;44;45;46m0\033[38;2;26;26;26m0\033[0m
\033[38;2;15;15;15m0\033[38;2;16;16;16m0\033[38;2;21;21;20m0\033[38;2;33;33;31m0\033[38;2;74;74;71m1\033[38;2;152;151;149m1\033[38;2;136;135;133m0\033[38;2;74;73;71m0\033[38;2;121;121;119m1\033[38;2;157;157;154m1\033[38;2;135;134;132m1\033[38;2;153;153;151m0\033[38;2;137;136;134m0\033[38;2;136;136;134m0\033[38;2;118;118;117m0\033[38;2;63;63;63m0\033[38;2;141;142;141m0\033[38;2;136;137;137m0\033[38;2;41;42;44m0\033[38;2;26;26;26m1\033[0m
\033[38;2;16;16;16m0\033[38;2;22;23;22m0\033[38;2;54;54;53m0\033[38;2;139;139;137m0\033[38;2;133;133;131m1\033[38;2;70;69;67m1\033[38;2;117;117;115m1\033[38;2;161;161;159m0\033[38;2;105;104;102m1\033[38;2;67;66;64m1\033[38;2;104;103;101m0\033[38;2;143;142;139m0\033[38;2;105;105;103m1\033[38;2;57;57;56m0\033[38;2;62;62;62m1\033[38;2;159;159;158m1\033[38;2;126;128;127m1\033[38;2;51;52;53m1\033[38;2;32;33;33m1\033[38;2;25;25;25m1\033[0m
\033[38;2;21;21;20m1\033[38;2;59;59;57m0\033[38;2;174;174;172m0\033[38;2;65;64;62m1\033[38;2;36;37;34m1\033[38;2;61;61;58m0\033[38;2;109;108;106m1\033[38;2;130;129;128m0\033[38;2;132;131;130m10\033[38;2;141;140;139m0\033[38;2;160;160;158m0\033[38;2;151;151;149m1\033[38;2;164;164;162m1\033[38;2;105;105;104m1\033[38;2;87;88;87m1\033[38;2;156;156;155m0\033[38;2;136;137;137m0\033[38;2;57;58;59m0\033[38;2;33;33;35m1\033[0m
\033[38;2;20;19;18m1\033[38;2;88;87;85m1\033[38;2;109;108;105m1\033[38;2;121;120;118m0\033[38;2;121;120;119m0\033[38;2;125;125;124m0\033[38;2;129;129;128m1\033[38;2;133;133;131m1\033[38;2;134;133;132m0\033[38;2;134;134;133m1\033[38;2;137;137;135m0\033[38;2;151;150;148m1\033[38;2;134;133;131m0\033[38;2;72;71;70m0\033[38;2;117;118;117m1\033[38;2;112;113;113m1\033[38;2;142;143;142m0\033[38;2;163;164;165m1\033[38;2;127;130;133m1\033[38;2;36;38;41m0\033[0m
\033[38;2;13;13;13m1\033[38;2;15;15;15m0\033[38;2;18;18;17m1\033[38;2;21;21;21m1\033[38;2;23;23;23m1\033[38;2;25;25;25m1\033[38;2;27;27;27m0\033[38;2;28;28;28m0\033[38;2;29;29;29m10\033[38;2;28;29;28m0\033[38;2;26;26;26m0\033[38;2;25;25;25m1\033[38;2;23;23;23m01\033[38;2;24;25;25m1\033[38;2;27;27;27m0\033[38;2;28;28;28m1\033[38;2;24;24;24m1\033[38;2;21;21;21m0\033[0m
EOF_TUI_LOGO_SMALL
}

_tui_logo_tiny_block() {
    while IFS= read -r line; do printf '%b\n' "$line"; done <<'EOF_TUI_LOGO_TINY'
\033[38;2;13;13;13m0\033[38;2;17;17;17m0\033[38;2;37;37;37m0\033[38;2;55;55;55m1\033[38;2;57;58;57m0\033[38;2;57;57;57m0\033[38;2;58;58;58m0\033[38;2;59;59;59m0\033[38;2;47;47;46m0\033[38;2;21;21;21m1\033[38;2;18;18;19m0\033[38;2;18;18;18m0\033[0m
\033[38;2;15;15;15m1\033[38;2;80;81;80m0\033[38;2;97;97;96m1\033[38;2;123;123;122m0\033[38;2;132;131;130m1\033[38;2;102;102;100m0\033[38;2;77;77;76m1\033[38;2;121;121;119m0\033[38;2;140;140;138m0\033[38;2;104;106;106m1\033[38;2;50;52;53m0\033[38;2;23;23;24m0\033[0m
\033[38;2;15;15;15m0\033[38;2;29;29;28m1\033[38;2;107;107;105m1\033[38;2;145;145;142m0\033[38;2;140;139;137m1\033[38;2;97;96;94m1\033[38;2;133;132;130m0\033[38;2;98;98;96m1\033[38;2;152;153;150m0\033[38;2;77;78;78m0\033[38;2;139;142;142m1\033[38;2;31;31;32m1\033[0m
\033[38;2;17;17;17m1\033[38;2;46;46;45m0\033[38;2;111;110;108m1\033[38;2;112;111;109m1\033[38;2;122;122;120m0\033[38;2;110;110;108m0\033[38;2;132;131;129m0\033[38;2;124;123;122m1\033[38;2;78;78;77m1\033[38;2;130;130;130m1\033[38;2;82;83;83m0\033[38;2;28;28;28m0\033[0m
\033[38;2;33;33;32m0\033[38;2;140;140;138m0\033[38;2;45;44;43m1\033[38;2;75;75;73m1\033[38;2;112;111;109m0\033[38;2;117;116;115m1\033[38;2;134;134;132m1\033[38;2;159;158;157m0\033[38;2;137;137;136m1\033[38;2;109;109;109m1\033[38;2;136;138;138m0\033[38;2;46;48;49m1\033[0m
\033[38;2;22;22;21m1\033[38;2;54;53;52m1\033[38;2;75;75;74m1\033[38;2;79;79;79m0\033[38;2;83;83;82m1\033[38;2;83;83;83m1\033[38;2;84;84;83m1\033[38;2;58;58;57m0\033[38;2;39;39;39m0\033[38;2;68;69;69m0\033[38;2;83;83;84m0\033[38;2;37;38;40m1\033[0m
EOF_TUI_LOGO_TINY
}

_tui_draw_header() {
    # Pick a logo size from BOTH width and height. A 60x27 logo is beautiful on
    # a large terminal but leaves no room for menus on a normal 80x24 display.
    # Compact variants preserve the artwork while keeping the controls visible.
    local logo line logo_width logo_pad header_mode
    if (( TUI_COLS >= 64 && TUI_LINES >= 42 )); then
        logo="$(_tui_logo_block)"; logo_width=60; header_mode=full
    elif (( TUI_COLS >= 36 && TUI_LINES >= 30 )); then
        logo="$(_tui_logo_medium_block)"; logo_width=30; header_mode=medium
    elif (( TUI_COLS >= 24 && TUI_LINES >= 19 )); then
        logo="$(_tui_logo_small_block)"; logo_width=20; header_mode=small
    else
        logo="$(_tui_logo_tiny_block)"; logo_width=12; header_mode=tiny
    fi

    logo_pad=$(( (TUI_COLS - logo_width) / 2 )); (( logo_pad < 0 )) && logo_pad=0
    while IFS= read -r line; do
        printf '%*s%s\n' "$logo_pad" '' "$line"
    done <<< "$logo"

    if [[ "$header_mode" == full || "$header_mode" == medium ]]; then
        printf '\n'
        _tui_print_center 'ZARZYSSEUS'
        _tui_print_center 'AI INSTALLER / SERVICE MANAGER'
    elif [[ "$header_mode" == small ]]; then
        _tui_print_center 'ZARZYSSEUS — AI INSTALLER'
    else
        if (( TUI_LINES >= 12 )); then
            _tui_print_center 'ZARZYSSEUS'
        fi
    fi
}

_tui_redraw() {
    _tui_size
    _tui_clear
    _tui_draw_header
}

_tui_pause() {
    _tui_cursor_show
    printf '\n'
    _tui_print_center 'Press Enter to return to the menu...'
    local key=""
    while true; do
        _tui_read_key key
        [[ -n "$key" ]] || break
        case "$key" in
            $'\n'|$'\r'|q|Q) break ;;
        esac
    done
    _tui_cursor_hide
}

_tui_prompt() {
    local prompt="$1" default="${2:-}" value=""
    local box_width box_pad input_row label_row default_row
    local header="" header_lines=0 line row
    local header_room prompt_height top_pad

    _tui_size
    _tui_clear

    # Render the full header onto an absolute row/column grid first. The
    # prompt box is placed only after the complete logo/title block, so it
    # can never overwrite or collide with the ASCII art.
    header="$(_tui_draw_header)"
    while IFS= read -r line; do
        ((header_lines+=1))
    done <<< "$header"
    (( header_lines > 0 )) && header_lines=$((header_lines - 1))

    row=1
    while IFS= read -r line; do
        line="${line%$'\r'}"
        printf '\033[%d;1H%s' "$row" "$line"
        ((row+=1))
        (( row > header_lines )) && break
    done <<< "$header"

    # Every input screen uses this exact same fixed-width box and columns.
    box_width=64
    (( TUI_COLS - 2 < box_width )) && box_width=$((TUI_COLS - 2))
    (( box_width < 10 )) && box_width=10
    box_pad=$(( (TUI_COLS - box_width) / 2 ))
    (( box_pad < 0 )) && box_pad=0

    prompt_height=6
    header_room=$((TUI_LINES - header_lines - 1))
    top_pad=$(( (header_room - prompt_height) / 2 ))
    (( top_pad < 1 )) && top_pad=1

    label_row=$((header_lines + top_pad + 1))
    (( label_row + prompt_height - 1 > TUI_LINES )) && label_row=$((TUI_LINES - prompt_height + 1))
    (( label_row <= header_lines )) && label_row=$((header_lines + 1))

    default_row=$((label_row + 2))
    input_row=$((label_row + 4))

    printf '\033[%d;%dH+%*s+' "$label_row" "$((box_pad + 1))" "$((box_width - 2))" ''
    local inner_width=$((box_width - 4))
    local prompt_fit="$(_tui_fit_one_line "$prompt" "$inner_width")"
    printf '\033[%d;%dH| %-'"$inner_width"'s |' "$((label_row + 1))" "$((box_pad + 1))" "$prompt_fit"

    if [[ -n "$default" ]]; then
        local default_fit="$(_tui_fit_one_line "Default: $default" "$inner_width")"
        printf '\033[%d;%dH| %-'"$inner_width"'s |' "$default_row" "$((box_pad + 1))" "$default_fit"
    else
        printf '\033[%d;%dH| %-'"$((box_width - 4))"'s |' "$default_row" "$((box_pad + 1))" ''
    fi

    printf '\033[%d;%dH+%*s+' "$((input_row - 1))" "$((box_pad + 1))" "$((box_width - 2))" ''
    printf '\033[%d;%dH| %-'"$((box_width - 4))"'s |' "$input_row" "$((box_pad + 1))" 'Input: '
    printf '\033[%d;%dH+%*s+' "$((input_row + 1))" "$((box_pad + 1))" "$((box_width - 2))" ''

    _tui_cursor_show
    printf '\033[%d;%dH' "$input_row" "$((box_pad + 10))"

    # The TUI keeps the terminal in raw/no-echo mode globally. For a normal
    # text field, briefly switch only the input line back to canonical+echo
    # mode so the characters the user types are actually visible and line
    # editing behaves naturally. Restore the exact TUI mode immediately after.
    stty icanon echo opost < /dev/tty 2>/dev/null || true
    IFS= read -r value < /dev/tty || value=""
    if [[ -n "$TUI_STTY_STATE" ]]; then
        stty "$TUI_STTY_STATE" < /dev/tty 2>/dev/null || true
    else
        stty -icanon -echo -opost min 1 time 0 < /dev/tty 2>/dev/null || true
    fi
    [[ -z "$value" && -n "$default" ]] && value="$default"
    TUI_INPUT="$value"
    _tui_cursor_hide
}

# Generic arrow-key menu with centered rendering and scrolling for small terminals.
# Sets TUI_CHOICE to a zero-based index. Return 1 on Back/Quit.
_tui_menu() {
    local title="$1"
    shift
    local -a items=("$@")
    local selected=0 window_start=0 key key2
    local i end_index visible_items menu_height remaining top_pad row
    local frame="" header="" line="" line_width line_pad
    local header_lines=0 footer_row menu_row indicator_lines

    _tui_begin
    while true; do
        _tui_size

        # Build the static header once per frame and count its actual terminal
        # rows. The previous implementation used a guessed header height;
        # when the real logo was taller than that guess, the frame could extend
        # past the bottom of the terminal and every redraw would scroll the
        # screen, producing duplicated menu entries.
        header="$(_tui_draw_header)"
        header_lines=0
        while IFS= read -r line; do
            ((header_lines+=1))
        done <<< "$header"
        # read above includes the final empty line from the here-string.
        (( header_lines > 0 )) && header_lines=$((header_lines - 1))

        # Reserve one row for the footer and fit as many menu entries as the
        # terminal can safely display. The selected row is always kept visible.
        visible_items=${#items[@]}
        (( visible_items < 1 )) && visible_items=1
        end_index=$((window_start + visible_items - 1))
        (( end_index >= ${#items[@]} )) && end_index=$((${#items[@]} - 1))
        while true; do
            indicator_lines=0
            (( window_start > 0 )) && ((indicator_lines+=1))
            (( end_index < ${#items[@]} - 1 )) && ((indicator_lines+=1))
            menu_height=$((3 + 1 + visible_items + indicator_lines))
            remaining=$((TUI_LINES - header_lines - menu_height - 1))
            if (( remaining >= 0 || visible_items <= 1 )); then
                break
            fi
            ((visible_items-=1))
        done

        if (( selected < window_start )); then
            window_start=$selected
        elif (( selected >= window_start + visible_items )); then
            window_start=$((selected - visible_items + 1))
        fi
        end_index=$((window_start + visible_items - 1))
        (( end_index >= ${#items[@]} )) && end_index=$((${#items[@]} - 1))

        indicator_lines=0
        (( window_start > 0 )) && ((indicator_lines+=1))
        (( end_index < ${#items[@]} - 1 )) && ((indicator_lines+=1))
        menu_height=$((3 + 1 + (end_index - window_start + 1) + indicator_lines))
        remaining=$((TUI_LINES - header_lines - menu_height - 1))
        (( remaining < 0 )) && remaining=0
        top_pad=$((remaining / 2))
        menu_row=$((header_lines + top_pad + 1))
        footer_row=$TUI_LINES

        # Absolute cursor addressing is deliberately used for the menu instead
        # of newline-based drawing. This guarantees that rendering can never
        # wrap or scroll the terminal, even when a frame reaches the last row.
        # One complete printf keeps navigation smooth without flicker.
        frame=$'\033[?2026h\033[H\033[2J'

        row=1
        while IFS= read -r line; do
            [[ -z "$line" && $row -gt $header_lines ]] && break
            line="${line%$'\r'}"
            # _tui_draw_header already centers the complete ASCII logo block
            # and centers the text labels individually. Preserve those spaces.
            frame+=$(printf '\033[%d;1H%s' "$row" "$line")
            ((row+=1))
            (( row > header_lines )) && break
        done <<< "$header"

        row=$menu_row
        local sep_width=$((TUI_COLS - 4)); (( sep_width > 42 )) && sep_width=42; (( sep_width < 8 )) && sep_width=8
        printf -v line '%*s' "$sep_width" ''; line="${line// /-}"
        line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
        frame+=$(printf '\033[%d;%dH%s' "$row" "$((line_pad + 1))" "$line")
        ((row+=1))

        line="$(_tui_fit_one_line "$title" "$((TUI_COLS - 2))")"
        line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
        frame+=$(printf '\033[%d;%dH%s' "$row" "$((line_pad + 1))" "$line")
        ((row+=1))

        if (( TUI_COLS >= 46 )); then
            line='[UP/DOWN] Move   [ENTER] Select   [Q] Back'
        elif (( TUI_COLS >= 32 )); then
            line='UP/DOWN Move | ENTER Select | Q Back'
        else
            line='UP/DOWN | ENTER | Q'
        fi
        line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
        frame+=$(printf '\033[%d;%dH%s' "$row" "$((line_pad + 1))" "$line")
        ((row+=2))

        for ((i=window_start; i<=end_index; i++)); do
            # Center the actual label, then place the selection marker just to
            # its left. Centering the whole " > label" string shifts the label
            # itself to the right by half the marker width.
            local item_text="${items[$i]}" item_pad max_item_width
            max_item_width=$((TUI_COLS - 6)); (( max_item_width < 8 )) && max_item_width=8
            item_text="$(_tui_fit_one_line "$item_text" "$max_item_width")"
            item_pad=$(( (TUI_COLS - ${#item_text}) / 2 ))
            (( item_pad < 2 )) && item_pad=2
            if (( i == selected )); then
                line="> $item_text"
                frame+=$(printf '\033[%d;%dH%s' "$row" "$((item_pad - 2 + 1))" "$line")
            else
                line="$item_text"
                frame+=$(printf '\033[%d;%dH%s' "$row" "$((item_pad + 1))" "$line")
            fi
            ((row+=1))
        done

        if (( window_start > 0 )); then
            line='[more above]'
            line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
            frame+=$(printf '\033[%d;%dH%s' "$row" "$((line_pad + 1))" "$line")
            ((row+=1))
        fi
        if (( end_index < ${#items[@]} - 1 )); then
            line='[more below]'
            line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
            frame+=$(printf '\033[%d;%dH%s' "$row" "$((line_pad + 1))" "$line")
        fi

        line="$(_tui_fit_one_line 'Zarzysseus Installer' "$((TUI_COLS - 2))")"
        line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
        frame+=$(printf '\033[%d;%dH%s' "$footer_row" "$((line_pad + 1))" "$line")

        frame+=$'\033[?2026l'
        printf '%s' "$frame"

        key=""
        _tui_read_key key
        [[ -n "$key" ]] || continue
        case "$key" in
            $'\e')
                key2=""
                IFS= read -rsN 2 -t 0.08 key2 < /dev/tty || true
                case "$key2" in
                    '[A') selected=$((selected - 1)) ;;
                    '[B') selected=$((selected + 1)) ;;
                    '[5~') selected=$((selected - visible_items)) ;;
                    '[6~') selected=$((selected + visible_items)) ;;
                    *) ;;
                esac
                ;;
            $'\n'|$'\r')
                TUI_CHOICE="$selected"
                return 0
                ;;
            j|J) selected=$((selected + 1)) ;;
            k|K) selected=$((selected - 1)) ;;
            q|Q) return 1 ;;
        esac

        if (( selected < 0 )); then selected=$((${#items[@]} - 1)); fi
        if (( selected >= ${#items[@]} )); then selected=0; fi
    done
}

_tui_run_command() {
    local title="$1"
    shift
    local rc=0 action="${1:-}" stream_output=0 log_file=""

    case "$action" in
        install|install-auto-fit|install-full|install-personal-faves|install-personal-skills|install-low-spec|install-low-spec-manual|install-lps|install-lps-manual|install-desert-sdk|model-install-audio|auth|tools|accelerator-setup|mlx-install|sam-mask-install|sam-mask|system-update|\
        opull|vpull|spull|mpull|hf-pull|model-install|model-pick|model-auto|\
        install-manual-batch|model-pick-interactive|model-pull-batch|hf-token|ollama-pull|pull|skills-search-install|skills-install|skills-remove|skills-update|skills-update-one|skills-permissions-set|skills-permissions-clear|skills-sync-all)
            stream_output=1
            ;;
    esac

    # Return to the normal terminal for child commands. This means downloads and
    # installs can scroll naturally, while the TUI itself remains stable.
    _tui_end
    _tui_size
    _tui_clear
    _tui_print_center "$title"
    printf '\n'

    if (( stream_output )); then
        if ODYSSEUS_TUI_CHILD=1 bash "$SCRIPT_PATH" "$@"; then
            rc=0
        else
            rc=$?
        fi
    else
        log_file="$(mktemp)"
        if ODYSSEUS_TUI_CHILD=1 bash "$SCRIPT_PATH" "$@" >"$log_file" 2>&1; then
            rc=0
        else
            rc=$?
        fi
        if [[ -s "$log_file" ]]; then
            cat "$log_file"
        fi
        rm -f "$log_file"
    fi

    # A first-run install may have created PROJECT_DIR while the parent TUI was
    # launched from somewhere else (Downloads, /tmp, etc.). Adopt the new
    # managed installer immediately so every subsequent TUI action runs from
    # the Zarzysseus checkout without the user ever needing to cd manually.
    if repo_installed; then
        sync_managed_installer_copy "$LAUNCH_SCRIPT_PATH"
        enter_odysseus_project || true
    fi

    printf '\n==============================================\n'
    if (( rc == 0 )); then
        _tui_print_center 'Command completed successfully.'
    else
        _tui_print_center "Command exited with status $rc."
    fi
    printf '==============================================\n'
    _tui_pause
    _tui_begin
    # Keep the child's actual status for callers with a prerequisite phase.
    # In particular, never download the selected manual model after a failed
    # base-stack/system-update preflight.
    TUI_LAST_COMMAND_RC="$rc"
    return 0
}

tui_full_install_model_select() {
    local -a labels=(
        'dphn/Dolphin-Mistral-24B-Venice-Edition | BEST UNCENSORED'
        'qwen3.8 | SMARTEST / CENSORED (OLLAMA)'
        'tobestyledintro/qwen3.8-9b-distill | LIGHTER / SMART / CENSORED'
        'llama3.1:8b | LIGHTER / LESS SMART (OLLAMA)'
        'AUTO CHOOSE BEST FIT | PERFECT-FIT HARDWARE PICK'
        'INPUT MODEL FROM ANY PROVIDER | AUTO-PICK PROVIDER'
    )
    local -a model_values=(
        'dphn/Dolphin-Mistral-24B-Venice-Edition'
        'qwen3.8'
        'tobestyledintro/qwen3.8-9b-distill'
        'llama3.1:8b'
        '__AUTO_BEST_FIT__'
        ''
    )
    local -a checked=(0 0 0 0 0 0)
    local selected=0 window_start=0 visible_items=8 end_index=7 total_items=8
    local key='' key2='' header='' line='' frame='' display=''
    local header_lines=0 row=0 i=0 marker='' pad=0 max_width=0 footer=''
    local custom_model=''
    local timeout_total="${FULL_INSTALL_MODEL_SELECTION_TIMEOUT:-30}"
    local timeout_start=$SECONDS timeout_remaining=0 countdown_line='' countdown_row=0
    local last_countdown=-1 needs_draw=1 read_timeout=0.25 old_cols=0 old_lines=0

    [[ "$timeout_total" =~ ^[0-9]+$ ]] || timeout_total=30
    (( timeout_total < 1 )) && timeout_total=30

    _tui_begin
    while true; do
        _tui_size
        if (( TUI_COLS != old_cols || TUI_LINES != old_lines )); then
            old_cols=$TUI_COLS
            old_lines=$TUI_LINES
            needs_draw=1
        fi

        timeout_remaining=$(( timeout_total - (SECONDS - timeout_start) ))
        if (( timeout_remaining <= 0 )); then
            # Preserve the original recommendation-picker timeout: inactivity
            # confirms the hardware-perfect automatic text-model choice.
            TUI_MODEL_SELECTIONS='__AUTO_BEST_FIT__'
            _tui_end
            return 0
        fi

        if (( needs_draw )); then
            header="$(_tui_draw_header)"
            header_lines=0
            while IFS= read -r line; do ((header_lines+=1)); done <<< "$header"
            (( header_lines > 0 )) && header_lines=$((header_lines - 1))

            # title + countdown + footer consume three rows. Everything else is
            # a scrolling window, so Confirm/Back remain reachable on short or
            # unusual-aspect-ratio terminals without hiding the logo.
            visible_items=$((TUI_LINES - header_lines - 3))
            (( visible_items > total_items )) && visible_items=$total_items
            (( visible_items < 1 )) && visible_items=1

            if (( selected < window_start )); then
                window_start=$selected
            elif (( selected >= window_start + visible_items )); then
                window_start=$((selected - visible_items + 1))
            fi
            (( window_start < 0 )) && window_start=0
            if (( window_start + visible_items > total_items )); then
                window_start=$((total_items - visible_items))
                (( window_start < 0 )) && window_start=0
            fi
            end_index=$((window_start + visible_items - 1))
            (( end_index >= total_items )) && end_index=$((total_items - 1))

            frame=$'\033[2J\033[H'
            row=1
            while IFS= read -r line; do
                line="${line%$'\r'}"
                frame+=$(printf '\033[%d;1H%s' "$row" "$line")
                ((row+=1))
                (( row > header_lines )) && break
            done <<< "$header"

            row=$((header_lines + 1))
            line="$(_tui_fit_one_line 'PERSONAL FAVE TEXT MODELS' "$((TUI_COLS - 2))")"
            pad=$(( (TUI_COLS - ${#line}) / 2 )); (( pad < 0 )) && pad=0
            frame+=$(printf '\033[%d;%dH%s' "$row" "$((pad + 1))" "$line")
            ((row+=1))

            countdown_row=$row
            if (( TUI_COLS >= 52 )); then
                countdown_line="AUTO-PICK IN ${timeout_remaining}s | SPACE toggle | ENTER confirm"
            elif (( TUI_COLS >= 30 )); then
                countdown_line="AUTO-PICK ${timeout_remaining}s | SPACE | ENTER"
            else
                countdown_line="AUTO ${timeout_remaining}s | SPACE/ENTER"
            fi
            countdown_line="$(_tui_fit_one_line "$countdown_line" "$((TUI_COLS - 2))")"
            pad=$(( (TUI_COLS - ${#countdown_line}) / 2 )); (( pad < 0 )) && pad=0
            frame+=$(printf '\033[%d;%dH%s' "$row" "$((pad + 1))" "$countdown_line")
            ((row+=1))

            max_width=$((TUI_COLS - 6)); (( max_width < 6 )) && max_width=6
            for ((i=window_start; i<=end_index; i++)); do
                if (( i < 6 )); then
                    if (( checked[i] )); then marker='[X]'; else marker='[ ]'; fi
                    if (( i == 5 )) && [[ -n "$custom_model" ]]; then
                        display="$marker  CUSTOM: $custom_model"
                    else
                        display="$marker  ${labels[$i]}"
                    fi
                elif (( i == 6 )); then
                    display='>> CONFIRM SELECTION <<'
                else
                    display='BACK'
                fi

                display="$(_tui_fit_one_line "$display" "$max_width")"
                pad=$(( (TUI_COLS - ${#display}) / 2 )); (( pad < 2 )) && pad=2
                if (( i == selected )); then
                    frame+=$(printf '\033[%d;%dH> %s' "$row" "$((pad - 1))" "$display")
                else
                    frame+=$(printf '\033[%d;%dH%s' "$row" "$((pad + 1))" "$display")
                fi
                ((row+=1))
            done

            if (( TUI_COLS >= 42 )); then
                footer="UP/DOWN move | $((selected + 1))/8 | Q back"
            else
                footer="MOVE $((selected + 1))/8 | Q back"
            fi
            if (( window_start > 0 )); then footer="↑ more | $footer"; fi
            if (( end_index < total_items - 1 )); then footer="$footer | ↓ more"; fi
            footer="$(_tui_fit_one_line "$footer" "$((TUI_COLS - 2))")"
            pad=$(( (TUI_COLS - ${#footer}) / 2 )); (( pad < 0 )) && pad=0
            frame+=$(printf '\033[%d;%dH%s' "$TUI_LINES" "$((pad + 1))" "$footer")

            printf '%s' "$frame"
            last_countdown=$timeout_remaining
            needs_draw=0
        elif (( timeout_remaining != last_countdown )); then
            # Timer ticks update only this row: no full-screen clear/redraw.
            if (( TUI_COLS >= 52 )); then
                countdown_line="AUTO-PICK IN ${timeout_remaining}s | SPACE toggle | ENTER confirm"
            elif (( TUI_COLS >= 30 )); then
                countdown_line="AUTO-PICK ${timeout_remaining}s | SPACE | ENTER"
            else
                countdown_line="AUTO ${timeout_remaining}s | SPACE/ENTER"
            fi
            countdown_line="$(_tui_fit_one_line "$countdown_line" "$((TUI_COLS - 2))")"
            pad=$(( (TUI_COLS - ${#countdown_line}) / 2 )); (( pad < 0 )) && pad=0
            printf '\033[%d;1H\033[2K\033[%d;%dH%s' "$countdown_row" "$countdown_row" "$((pad + 1))" "$countdown_line"
            last_countdown=$timeout_remaining
        fi

        key=''
        if _tui_read_key_timeout key "$read_timeout"; then
            timeout_start=$SECONDS
            last_countdown=-1
            case "$key" in
                $'\e')
                    key2=''
                    IFS= read -rsN 2 -t 0.08 key2 < /dev/tty || true
                    case "$key2" in
                        '[A'|'[5~') selected=$((selected - 1)); needs_draw=1 ;;
                        '[B'|'[6~') selected=$((selected + 1)); needs_draw=1 ;;
                    esac
                    ;;
                j|J) selected=$((selected + 1)); needs_draw=1 ;;
                k|K) selected=$((selected - 1)); needs_draw=1 ;;
                ' ')
                    if (( selected < 6 )); then
                        if (( selected == 5 )); then
                            _tui_prompt 'INPUT MODEL (provider:model or org/model) — AUTO PROVIDER'
                            custom_model="$TUI_INPUT"
                            if [[ -n "$custom_model" ]]; then checked[5]=1; else checked[5]=0; fi
                        else
                            checked[selected]=$((1 - checked[selected]))
                        fi
                        needs_draw=1
                    fi
                    ;;
                $'\n'|$'\r')
                    if (( selected < 5 )); then
                        checked[selected]=$((1 - checked[selected]))
                        needs_draw=1
                    elif (( selected == 5 )); then
                        _tui_prompt 'INPUT MODEL (provider:model or org/model) — AUTO PROVIDER'
                        custom_model="$TUI_INPUT"
                        if [[ -n "$custom_model" ]]; then checked[5]=1; else checked[5]=0; fi
                        needs_draw=1
                    elif (( selected == 6 )); then
                        local count=0
                        for ((i=0; i<6; i++)); do (( checked[i] )) && ((count+=1)); done
                        if (( count == 0 )); then
                            _tui_end
                            _tui_size
                            _tui_clear
                            _tui_print_center 'Select at least one model before confirming.'
                            _tui_pause
                            _tui_begin
                            timeout_start=$SECONDS
                            last_countdown=-1
                            needs_draw=1
                        else
                            TUI_MODEL_SELECTIONS=''
                            for ((i=0; i<5; i++)); do
                                if (( checked[i] )); then
                                    TUI_MODEL_SELECTIONS+="${model_values[$i]}"$'\n'
                                fi
                            done
                            if (( checked[5] )) && [[ -n "$custom_model" ]]; then
                                TUI_MODEL_SELECTIONS+="${custom_model}"$'\n'
                            fi
                            TUI_MODEL_SELECTIONS="${TUI_MODEL_SELECTIONS%$'\n'}"
                            _tui_end
                            return 0
                        fi
                    else
                        _tui_end
                        return 1
                    fi
                    ;;
                q|Q)
                    _tui_end
                    return 1
                    ;;
            esac
        fi

        (( selected < 0 )) && selected=$((total_items - 1))
        (( selected >= total_items )) && selected=0
        if (( selected < window_start || selected >= window_start + visible_items )); then
            needs_draw=1
        fi
    done
}

tui_full_install_auto() {
    local profile="$1" title="$2"
    # The child install action performs the normal install preflight, including
    # the one-time OS update. Merely opening the mode chooser never updates the
    # system; the update starts only after the user commits to a mode.
    _tui_run_command "$title" install-auto-fit "$profile"
}

# An explicitly confirmed manual queue. In --full-stack mode only NORMAL model
# selections run the one-time OS-update preflight and install the Zarzysseus stack.
# --models-only is the Model Manager route; it never requests an OS upgrade.
manual_model_install_batch() {
    local scope="${1:-}" record family kind task repo include selected_json had_skills=0
    local complete=0 failed=0
    [[ "$scope" == '--full-stack' || "$scope" == '--models-only' ]] || {
        echo 'ERROR: Expected --full-stack or --models-only.'; return 2;
    }
    shift
    (( $# > 0 )) || { echo 'ERROR: No models selected. Nothing installed or updated.'; return 2; }
    local -a items=("$@")
    local have_normal=0
    for record in "${items[@]}"; do
        IFS='|' read -r family kind task repo include <<< "$record"
        [[ "$family" == normal || "$family" == lps || "$family" == desert ]] || { echo "ERROR: Invalid model family: $family"; return 2; }
        [[ -n "$repo" && -n "$kind" ]] || { echo 'ERROR: Invalid model selection.'; return 2; }
        [[ "$family" == normal ]] && have_normal=1
    done
    if [[ "$scope" == '--full-stack' && "$have_normal" == 1 ]]; then
        echo '==> Manual selections confirmed. Preparing the full stack once.'
        install_odysseus || return 1
    fi
    echo "==> Installing ${#items[@]} selected model(s); system preparation has finished."
    local n=0
    for record in "${items[@]}"; do
        n=$((n+1))
        IFS='|' read -r family kind task repo include <<< "$record"
        printf '\n==> [%d/%d] %s / %s / %s\n' "$n" "${#items[@]}" "$family" "$kind" "$repo"
        case "$family" in
            lps)
                if lps_spec "$repo" && lps_install_model "$repo"; then had_skills=1; else failed=$((failed+1)); fi
                ;;
            desert)
                if [[ "$repo" == desertant:tongue ]]; then
                    if desertant_install_core_sdk; then had_skills=1; else failed=$((failed+1)); fi
                elif desertant_install_selected "${repo#desertant:}"; then
                    had_skills=1
                else failed=$((failed+1)); fi
                ;;
            normal)
                if [[ "$kind" == audio && ( "$task" == automatic-speech-recognition || "$task" == text-to-speech ) ]]; then
                    if model_manager_ensure && auto_fit_audio_dependencies && hf_pull_model "$repo"; then
                        selected_json="$("$VENV_PY" - "$repo" "$task" <<'PY_MANUAL_BATCH_AUDIO'
import json,sys
print(json.dumps({'repo':sys.argv[1],'pipeline_tag':sys.argv[2],'model_type':'audio','fit_level':'manual'}))
PY_MANUAL_BATCH_AUDIO
)"
                        if audio_create_skill "$selected_json"; then had_skills=1; else failed=$((failed+1)); fi
                    else failed=$((failed+1)); fi
                elif [[ "$kind" == image || "$kind" == video ]]; then
                    if model_manager_ensure && auto_fit_prepare_dependencies "$kind" \
                       && hf_pull_model "$repo" && auto_fit_prepare_model_dependencies "$kind" "$repo"; then
                        selected_json="$("$VENV_PY" - "$repo" "$task" "$kind" <<'PY_MANUAL_BATCH_MEDIA'
import json,sys
print(json.dumps({'repo':sys.argv[1],'pipeline_tag':sys.argv[2],'model_type':sys.argv[3],'fit_level':'manual'}))
PY_MANUAL_BATCH_MEDIA
)"
                        if auto_fit_install_selected_skill "$kind" "$selected_json"; then had_skills=1; else failed=$((failed+1)); fi
                    else failed=$((failed+1)); fi
                elif model_manager_ensure && hf_pull_model "$repo" "$include"; then
                    complete=$((complete+1))
                else
                    failed=$((failed+1))
                fi
                ;;
        esac
    done
    if (( had_skills )); then
        auto_fit_finalize_skills || failed=$((failed+1))
    fi
    if (( failed )); then
        echo "ERROR: $failed installation step(s) failed. Review the per-model messages above."
        return 1
    fi
    echo "[ready] Selected manual batch finished: ${#items[@]} models."
}

tui_full_install_manual() {
    # Browse, switch families, search, inspect and cancel without ever starting
    # a package update. The full-stack preflight is deferred until a NORMAL
    # model is explicitly confirmed for installation. L.P.S./Desert Ant keep
    # their lightweight, independent installation paths.
    tui_model_manual_browser normal install-on-select
}

tui_personal_fave_text_models() {
    local selections_text model
    local -a selections=()

    # Reuse the original curated recommendation picker. Merely opening this
    # picker does not touch the OS. The one-time install/update preflight starts
    # only after the user confirms one or more recommended/custom text models.
    if ! tui_full_install_model_select; then
        return 0
    fi

    selections_text="${TUI_MODEL_SELECTIONS:-}"
    while IFS= read -r model; do
        [[ -n "$model" ]] && selections+=("$model")
    done <<< "$selections_text"
    (( ${#selections[@]} > 0 )) || return 0

    _tui_run_command 'FULL INSTALL — PERSONAL FAVE TEXT MODELS' install-personal-faves "${selections[@]}"
}

# Legacy entry point: default to the complete automatic profile.
tui_full_install() {
    tui_full_install_auto text-video-photo-audio 'FULL INSTALL — AUTO FIT TEXT + VIDEO + PHOTO + AUDIO'
}

# Timed chooser nested under "Install / Update Zarzysseus Stack".  It keeps the
# original inactivity timer behavior, but only the countdown row changes once
# per second so the logo/menu do not flicker.  Timeout selects the complete
# text + video + photo + audio profile.
tui_full_install_mode_menu() {
    local -a items mode_profiles=(
        'text-video-photo-audio'
        'text-video-photo'
        'text-video-audio'
        'text-photo-audio'
        'video-photo-audio'
        'text-video'
        'text-photo'
        'text-audio'
        'video-photo'
        'video-audio'
        'photo-audio'
        'text'
        'video'
        'photo'
        'audio'
    )
    local selected=0 window_start=0 visible_items end_index
    local key='' key2='' line='' header='' frame=''
    local header_lines row i menu_row footer_row indicator_lines remaining top_pad
    local max_item_width item_text item_pad line_pad sep_width
    local timeout_total="${FULL_INSTALL_MODE_SELECTION_TIMEOUT:-30}"
    local timeout_start=$SECONDS timeout_remaining last_countdown=-1
    local countdown_row=0 countdown_line='' read_timeout=0.25
    local needs_draw=1 old_cols=0 old_lines=0

    [[ "$timeout_total" =~ ^[0-9]+$ ]] || timeout_total=30
    (( timeout_total < 1 )) && timeout_total=30

    _tui_begin
    while true; do
        _tui_size
        if (( TUI_COLS != old_cols || TUI_LINES != old_lines )); then
            old_cols=$TUI_COLS
            old_lines=$TUI_LINES
            needs_draw=1
        fi

        # All 15 non-empty combinations, then favorites, manual and Back.
        # Narrow terminals display abbreviated names while retaining identity.
        items=()
        local mode_label
        for mode_label in "${mode_profiles[@]}"; do
            mode_label="${mode_label//-/ + }"
            if (( TUI_COLS >= 50 )); then
                items+=("AUTO FIT: ${mode_label^^}")
            else
                items+=("${mode_label^^}")
            fi
        done
        items+=(
            'PERSONAL FAVE TEXT MODELS'
            'PERSONAL FAVE SKILLS'
            'REALLY LOW SPEC — L.P.S. + DESERT ANT LABS'
            'MANUAL MODEL SELECTION'
            'BACK'
        )

        timeout_remaining=$(( timeout_total - (SECONDS - timeout_start) ))
        if (( timeout_remaining <= 0 )); then
            tui_full_install_auto text-video-photo-audio 'FULL INSTALL — AUTO FIT TEXT + VIDEO + PHOTO + AUDIO'
            return 0
        fi

        if (( needs_draw )); then
            header="$(_tui_draw_header)"
            header_lines=0
            while IFS= read -r line; do ((header_lines+=1)); done <<< "$header"
            (( header_lines > 0 )) && header_lines=$((header_lines - 1))

            # Fit the menu into the remaining rows while keeping the responsive
            # logo visible.  As on the generic menu, the current selection stays
            # inside a scroll window on very short displays.
            visible_items=${#items[@]}
            (( visible_items < 1 )) && visible_items=1
            while true; do
                end_index=$((window_start + visible_items - 1))
                (( end_index >= ${#items[@]} )) && end_index=$((${#items[@]} - 1))
                indicator_lines=0
                (( window_start > 0 )) && ((indicator_lines+=1))
                (( end_index < ${#items[@]} - 1 )) && ((indicator_lines+=1))
                # separator + title + help + countdown + gap + items + indicators
                local menu_height=$((5 + (end_index - window_start + 1) + indicator_lines))
                remaining=$((TUI_LINES - header_lines - menu_height - 1))
                if (( remaining >= 0 || visible_items <= 1 )); then break; fi
                ((visible_items-=1))
            done

            if (( selected < window_start )); then
                window_start=$selected
            elif (( selected >= window_start + visible_items )); then
                window_start=$((selected - visible_items + 1))
            fi
            (( window_start < 0 )) && window_start=0
            end_index=$((window_start + visible_items - 1))
            (( end_index >= ${#items[@]} )) && end_index=$((${#items[@]} - 1))

            indicator_lines=0
            (( window_start > 0 )) && ((indicator_lines+=1))
            (( end_index < ${#items[@]} - 1 )) && ((indicator_lines+=1))
            local menu_height=$((5 + (end_index - window_start + 1) + indicator_lines))
            remaining=$((TUI_LINES - header_lines - menu_height - 1))
            (( remaining < 0 )) && remaining=0
            top_pad=$((remaining / 2))
            menu_row=$((header_lines + top_pad + 1))
            footer_row=$TUI_LINES

            frame=$'\033[?2026h\033[H\033[2J'
            row=1
            while IFS= read -r line; do
                line="${line%$'\r'}"
                frame+=$(printf '\033[%d;1H%s' "$row" "$line")
                ((row+=1))
                (( row > header_lines )) && break
            done <<< "$header"

            row=$menu_row
            sep_width=$((TUI_COLS - 4)); (( sep_width > 52 )) && sep_width=52; (( sep_width < 8 )) && sep_width=8
            printf -v line '%*s' "$sep_width" ''; line="${line// /-}"
            line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
            frame+=$(printf '\033[%d;%dH%s' "$row" "$((line_pad + 1))" "$line")
            ((row+=1))

            line="$(_tui_fit_one_line 'INSTALL / UPDATE ZARZYSSEUS STACK' "$((TUI_COLS - 2))")"
            line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
            frame+=$(printf '\033[%d;%dH%s' "$row" "$((line_pad + 1))" "$line")
            ((row+=1))

            if (( TUI_COLS >= 48 )); then
                line='UP/DOWN Move | ENTER Select | Q Back'
            elif (( TUI_COLS >= 30 )); then
                line='UP/DOWN | ENTER | Q Back'
            else
                line='MOVE | ENTER | Q'
            fi
            line="$(_tui_fit_one_line "$line" "$((TUI_COLS - 2))")"
            line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
            frame+=$(printf '\033[%d;%dH%s' "$row" "$((line_pad + 1))" "$line")
            ((row+=1))

            countdown_row=$row
            if (( TUI_COLS >= 44 )); then
                countdown_line="AUTO FULL INSTALL IN ${timeout_remaining}s — any key resets timer"
            elif (( TUI_COLS >= 28 )); then
                countdown_line="AUTO FULL IN ${timeout_remaining}s — key resets"
            else
                countdown_line="AUTO ${timeout_remaining}s"
            fi
            countdown_line="$(_tui_fit_one_line "$countdown_line" "$((TUI_COLS - 2))")"
            line_pad=$(( (TUI_COLS - ${#countdown_line}) / 2 )); (( line_pad < 0 )) && line_pad=0
            frame+=$(printf '\033[%d;%dH%s' "$row" "$((line_pad + 1))" "$countdown_line")
            ((row+=2))

            for ((i=window_start; i<=end_index; i++)); do
                max_item_width=$((TUI_COLS - 6)); (( max_item_width < 6 )) && max_item_width=6
                item_text="$(_tui_fit_one_line "${items[$i]}" "$max_item_width")"
                item_pad=$(( (TUI_COLS - ${#item_text}) / 2 )); (( item_pad < 2 )) && item_pad=2
                if (( i == selected )); then
                    frame+=$(printf '\033[%d;%dH> %s' "$row" "$((item_pad - 1))" "$item_text")
                else
                    frame+=$(printf '\033[%d;%dH%s' "$row" "$((item_pad + 1))" "$item_text")
                fi
                ((row+=1))
            done

            if (( window_start > 0 )); then
                line='[more above]'; line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
                frame+=$(printf '\033[%d;%dH%s' "$row" "$((line_pad + 1))" "$line"); ((row+=1))
            fi
            if (( end_index < ${#items[@]} - 1 )); then
                line='[more below]'; line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
                frame+=$(printf '\033[%d;%dH%s' "$row" "$((line_pad + 1))" "$line")
            fi

            line="$(_tui_fit_one_line 'System update starts only after you choose a mode.' "$((TUI_COLS - 2))")"
            line_pad=$(( (TUI_COLS - ${#line}) / 2 )); (( line_pad < 0 )) && line_pad=0
            frame+=$(printf '\033[%d;%dH%s' "$footer_row" "$((line_pad + 1))" "$line")

            frame+=$'\033[?2026l'
            printf '%s' "$frame"
            last_countdown=$timeout_remaining
            needs_draw=0
        elif (( timeout_remaining != last_countdown )); then
            # Update only the timer row; do not clear/redraw the logo or menu.
            if (( TUI_COLS >= 44 )); then
                countdown_line="AUTO FULL INSTALL IN ${timeout_remaining}s — any key resets timer"
            elif (( TUI_COLS >= 28 )); then
                countdown_line="AUTO FULL IN ${timeout_remaining}s — key resets"
            else
                countdown_line="AUTO ${timeout_remaining}s"
            fi
            countdown_line="$(_tui_fit_one_line "$countdown_line" "$((TUI_COLS - 2))")"
            line_pad=$(( (TUI_COLS - ${#countdown_line}) / 2 )); (( line_pad < 0 )) && line_pad=0
            printf '\033[%d;1H\033[2K\033[%d;%dH%s' "$countdown_row" "$countdown_row" "$((line_pad + 1))" "$countdown_line"
            last_countdown=$timeout_remaining
        fi

        key=''
        if _tui_read_key_timeout key "$read_timeout"; then
            timeout_start=$SECONDS
            last_countdown=-1
            case "$key" in
                $'\e')
                    key2=''
                    IFS= read -rsN 2 -t 0.08 key2 < /dev/tty || true
                    case "$key2" in
                        '[A'|'[5~') selected=$((selected - 1)) ;;
                        '[B'|'[6~') selected=$((selected + 1)) ;;
                        *) return 1 ;;
                    esac
                    needs_draw=1
                    ;;
                j|J|k|K)
                    [[ "$key" == j || "$key" == J ]] && selected=$((selected + 1)) || selected=$((selected - 1))
                    needs_draw=1
                    ;;
                $'\n'|$'\r')
                    if (( selected < ${#mode_profiles[@]} )); then
                        tui_full_install_auto "${mode_profiles[$selected]}" "AUTO FIT: ${mode_profiles[$selected]}"
                    else
                        case "$((selected - ${#mode_profiles[@]}))" in
                            0) tui_personal_fave_text_models ;;
                            1) tui_personal_fave_skills ;;
                            2) tui_low_spec_mode_menu ;;
                            3) tui_full_install_manual ;;
                            4) return 0 ;;
                        esac
                    fi
                    return 0
                    ;;
                q|Q)
                    return 0
                    ;;
                *)
                    # Any other real key still resets the inactivity timer, as
                    # the original selector did, without forcing a redraw.
                    ;;
            esac
        fi

        (( selected < 0 )) && selected=$((${#items[@]} - 1))
        (( selected >= ${#items[@]} )) && selected=0
        if (( selected < window_start || selected >= window_start + visible_items )); then
            needs_draw=1
        fi
    done
}

tui_personal_fave_skills() {
    local choice
    while true; do
        if _tui_menu 'PERSONAL FAVE SKILLS' \
            'ALL LOCAL: OFFICE + PHOTO + VIDEO + SCRIPTING + TRANSCRIPTION' \
            'OFFICE: WORD / EXCEL / POWERPOINT / PDF' \
            'PHOTO EDITING: PILLOW' \
            'VIDEO EDITING: FFMPEG' \
            'SCRIPTING: PYTHON + SHELLCHECK + RUFF' \
            'AUDIO TRANSCRIPTION / SPEECH TO TEXT (LOCAL)' \
            'RUNCOMFY PHOTO EDIT (BROWSER LOGIN)' \
            'RUNCOMFY VIDEO GENERATION (BROWSER LOGIN)' \
            'BACK'; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) _tui_run_command 'Installing all local personal-favorite skills' install-personal-skills all-local ;;
                1) _tui_run_command 'Installing Office personal-favorite skills' install-personal-skills office ;;
                2) _tui_run_command 'Installing local photo-editing skill' install-personal-skills photo-edit ;;
                3) _tui_run_command 'Installing local video-editing skill' install-personal-skills video-edit ;;
                4) _tui_run_command 'Installing scripting skill' install-personal-skills scripting ;;
                5) _tui_run_command 'Installing local transcription skill' install-personal-skills transcription ;;
                6) _tui_run_command 'Installing RunComfy photo skill and authorizing account' install-personal-skills cloud-photo ;;
                7) _tui_run_command 'Installing RunComfy video skill and authorizing account' install-personal-skills cloud-video ;;
                8) return 0 ;;
            esac
        else return 0; fi
    done
}

tui_low_spec_manual_picker() {
    # Desert Ant publishes specialized CLI tasks rather than one shared HF model
    # metadata schema. Search known supported tasks; inspect vendor-supplied model
    # info for exact platform/size details, and never fabricate parameter counts.
    local query='' choice id title lower_query
    local -a ids=(clear ear clips redact emo gist tongue)
    local -a labels=(
        'CLEAR | AUDIO CLEANUP | ~24 MB LINUX ONNX'
        'EAR | LANGUAGE ID | PARAMETERS UNKNOWN'
        'CLIPS | VIDEO/AUDIO HIGHLIGHTS | NOT GENERATION'
        'REDACT | TEXT PII REDACTION | PARAMETERS UNKNOWN'
        'EMO | TEXT EMOJI TAGS | PARAMETERS UNKNOWN'
        'GIST | TEXT TOPIC TAGS | PARAMETERS UNKNOWN'
        'TONGUE | JAVASCRIPT SDK | ~2 MB (VENDOR SIZE)'
    )
    local -a choices=() mapped=()
    local i
    while true; do
        choices=(); mapped=(); lower_query="${query,,}"
        for i in "${!ids[@]}"; do
            title="${labels[$i]}"
            if [[ -z "$lower_query" || "${title,,}" == *"$lower_query"* || "${ids[$i]}" == *"$lower_query"* ]]; then
                choices+=("$title")
                mapped+=("${ids[$i]}")
            fi
        done
        choices+=("SEARCH / FILTER: ${query:-ALL}" 'CLEAR FILTER' 'SHOW SUPPORTED MODELS + PROJECTS' 'BACK')
        if ! _tui_menu 'LOW SPEC MANUAL — DESERT ANT LABS' "${choices[@]}"; then return 0; fi
        choice="$TUI_CHOICE"
        if (( choice < ${#mapped[@]} )); then
            id="${mapped[$choice]}"
            if [[ "$id" == tongue ]]; then
                _tui_run_command 'Installing Desert Ant Tongue JavaScript SDK' install-desert-sdk
            else
                _tui_run_command "Installing Desert Ant $id (vendor info printed first)" install-low-spec-manual "$id"
            fi
        else
            case "$((choice - ${#mapped[@]}))" in
                0) _tui_prompt 'FILTER LOW-SPEC TOOLS BY NAME/TASK' "$query"; query="$TUI_INPUT" ;;
                1) query='' ;;
                2) _tui_run_command 'Listing Desert Ant CLI models and vendor specs' low-spec-status ;;
                3) return 0 ;;
            esac
        fi
    done
}

tui_lps_mode_menu() {
    local -a profiles=(
        text-video-photo-audio text-video-photo text-video-audio text-photo-audio video-photo-audio
        text-video text-photo text-audio video-photo video-audio photo-audio text video photo audio
    ) items=()
    local profile selected label
    while true; do
        items=()
        for profile in "${profiles[@]}"; do
            label="${profile//-/ + }"
            items+=("AUTO FIT L.P.S.: ${label^^}")
        done
        items+=('MANUAL L.P.S. MODEL PICKER [TAB SWITCHES GROUP]' 'BACK')
        if ! _tui_menu 'LOW POWER SPEC — L.P.S. MODELS' "${items[@]}"; then return 0; fi
        selected="$TUI_CHOICE"
        if (( selected < ${#profiles[@]} )); then
            _tui_run_command "L.P.S. AUTO FIT: ${profiles[$selected]}" install-lps "${profiles[$selected]}"
        elif (( selected == ${#profiles[@]} )); then
            tui_model_manual_browser lps
        else return 0; fi
    done
}

tui_low_spec_mode_menu() {
    local choice
    while true; do
        if ! _tui_menu 'REALLY LOW SPEC — PICK A DISTINCT FAMILY' \
            'L.P.S. — TEXT / PHOTO / VIDEO / AUDIO GENERATION' \
            'DESERT ANT LABS — SPECIALIST TASK MODELS' \
            'MANUAL MODEL PICKER — TAB CYCLES FAMILIES' \
            'BACK'; then return 0; fi
        choice="$TUI_CHOICE"
        case "$choice" in
            0) tui_lps_mode_menu ;;
            1) tui_desertant_mode_menu ;;
            2) tui_model_manual_browser lps ;;
            *) return 0 ;;
        esac
    done
}

tui_desertant_mode_menu() {
    local -a profiles=(
        text-video-photo-audio text-video-photo text-video-audio text-photo-audio video-photo-audio
        text-video text-photo text-audio video-photo video-audio photo-audio text video photo audio
    ) items=()
    local choice profile label
    while true; do
        items=()
        for profile in "${profiles[@]}"; do
            label="${profile//-/ + }"
            if [[ "$profile" == *photo* ]]; then
                items+=("${label^^} — PHOTO GENERATOR NOT AVAILABLE")
            else
                items+=("${label^^} — SPECIALIST TOOLS (NOT GENERATORS)")
            fi
        done
        items+=('DESERT ANT MANUAL PICKER [TAB SWITCHES GROUP]' 'BACK')
        if ! _tui_menu 'DESERT ANT LABS — SPECIALIST MODELS' "${items[@]}"; then return 0; fi
        choice="$TUI_CHOICE"
        if (( choice < ${#profiles[@]} )); then
            profile="${profiles[$choice]}"
            if [[ "$profile" == *photo* ]]; then
                _tui_run_command 'Photo generation is not offered by Desert Ant CLI' low-spec-unsupported photo
            else
                _tui_run_command "Desert Ant specialist tools: $profile" install-low-spec "$profile"
            fi
        elif (( choice == ${#profiles[@]} )); then
            tui_model_manual_browser desert
        else return 0; fi
    done
}

tui_install_menu() {
    local choice
    local -a install_items
    while true; do
        _tui_size
        if (( TUI_COLS >= 40 )); then
            install_items=(
                'INSTALL / UPDATE ZARZYSSEUS STACK'
                'RUN SYSTEM UPDATE NOW'
                'INSTALL TOOLS'
                'REPAIR ACCELERATOR STACK'
                'INSTALL / VERIFY MLX-LM'
                'UNINSTALL ZARZYSSEUS'
                'BACK'
            )
        elif (( TUI_COLS >= 26 )); then
            install_items=(
                'INSTALL / UPDATE STACK'
                'SYSTEM UPDATE'
                'TOOLS'
                'GPU / ACCELERATOR'
                'MLX-LM'
                'UNINSTALL'
                'BACK'
            )
        else
            install_items=(
                'INSTALL'
                'OS UPDATE'
                'TOOLS'
                'GPU'
                'MLX'
                'REMOVE'
                'BACK'
            )
        fi

        if _tui_menu 'INSTALL / UPDATE' "${install_items[@]}"; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) tui_full_install_mode_menu ;;
                1) _tui_run_command 'Updating operating system' system-update ;;
                2) _tui_run_command 'Installing Zarzysseus tools' tools ;;
                3) _tui_run_command 'Installing / repairing accelerator stack' accelerator-setup ;;
                4) _tui_run_command 'Installing / verifying MLX-LM' mlx-install ;;
                5)
                    _tui_end
                    _tui_size
                    _tui_clear
                    _tui_draw_header
                    printf '\n'
                    _tui_print_center 'UNINSTALL ZARZYSSEUS'
                    printf '\n'
                    _tui_print_center 'Removes the Zarzysseus project and its user services.'
                    _tui_print_center 'ROCm/CUDA, pyenv, tmux, yay, and Ollama models remain.'
                    printf '\n'
                    _tui_print_center 'Type UNINSTALL to continue. Anything else cancels.'
                    _tui_print_center 'Confirmation:'
                    _tui_cursor_show
                    local uninstall_confirm=''
                    IFS= read -r uninstall_confirm < /dev/tty || uninstall_confirm=''
                    _tui_cursor_hide
                    if [[ "$uninstall_confirm" == 'UNINSTALL' ]]; then
                        ODYSSEUS_UNINSTALL_CONFIRMED=1 _tui_run_command 'Uninstalling Zarzysseus' uninstall
                        _tui_cleanup
                        exit 0
                    else
                        _tui_begin
                        _tui_print_center 'Uninstall cancelled.'
                        _tui_pause
                    fi
                    ;;
                6) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

tui_service_menu() {
    local choice
    while true; do
        if _tui_menu 'SERVICE MANAGEMENT' \
            'START ZARZYSSEUS' \
            'STOP ZARZYSSEUS' \
            'RESTART ZARZYSSEUS' \
            'ENABLE AUTO-START' \
            'DISABLE AUTO-START' \
            'SHOW STATUS' \
            'REMOVE STARTUP SERVICE' \
            'BACK'; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) _tui_run_command 'Starting Zarzysseus' start ;;
                1) _tui_run_command 'Stopping Zarzysseus' stop ;;
                2) _tui_run_command 'Restarting Zarzysseus' restart ;;
                3) _tui_run_command 'Enabling Zarzysseus automatic startup' enable ;;
                4) _tui_run_command 'Disabling Zarzysseus automatic startup' disable ;;
                5) _tui_run_command 'Zarzysseus status' status ;;
                6) _tui_run_command 'Removing Zarzysseus startup service' uninstall-service ;;
                7) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

tui_pull_with_optional_include() {
    local command="$1" label="$2" model include
    _tui_prompt 'MODEL ID (org/model)'
    model="$TUI_INPUT"
    [[ -n "$model" ]] || return 0
    _tui_prompt 'FILE FILTER (optional; blank = full repo)'
    include="$TUI_INPUT"
    if [[ -n "$include" ]]; then
        _tui_run_command "$label: $model" "$command" "$model" "$include"
    else
        _tui_run_command "$label: $model" "$command" "$model"
    fi
}

tui_opull() {
    local model
    _tui_prompt 'OLLAMA MODEL (name[:tag])'
    model="$TUI_INPUT"
    [[ -n "$model" ]] || return 0
    _tui_run_command "Ollama pull: $model" opull "$model"
}

tui_model_default() {
    local provider model
    _tui_prompt 'Provider (vllm, sglang, ollama, mlx_lm)' "$DEFAULT_MODEL_PROVIDER"
    provider="$TUI_INPUT"
    [[ -n "$provider" ]] || return 0
    _tui_prompt 'Model' "$DEFAULT_MODEL_ID"
    model="$TUI_INPUT"
    [[ -n "$model" ]] || return 0
    _tui_run_command "Setting default model: $model via $provider" model-default "$provider" "$model"
}


model_approx_specs() {
    local family="${1:-normal}" raw="${2:-}"
    MODEL_SPEC_ROW="$raw" python3 - "$family" <<'PY_APPROX_SPECS'
import math, os, re, sys
family=sys.argv[1]
row=os.environ.get('MODEL_SPEC_ROW','').split('\t')
row=(row+['?']*14)[:14]
name,repo,kind,task,params,size,quant,need,speed,fit,score,include,downloads,likes=row

def number(raw):
    match=re.search(r'([0-9]+(?:\.[0-9]+)?)',raw or '')
    return float(match.group(1)) if match else None

def gigabytes(raw):
    x=number(raw)
    if x is None: return None
    if re.search(r'\bM(?:B)?\b',raw or '',re.I): return x/1024
    if re.search(r'\bK(?:B)?\b',raw or '',re.I): return x/1024**2
    return x

sized= gigabytes(size)
need_gb=number(need) if need not in ('?','CPU','-') else None
params_note=('very rough repo-size/FP16 equivalent; NOT published parameter count'
             if family=='lps' and repo in ('segmind/tiny-sd','cerspense/zeroscope_v2_576w')
             else 'estimated/inferred' if params.startswith('~') else
             'not published in this catalog' if params in ('?','N/P','n/a') else
             'catalog value; verify on model card')
size_note=('approximate repository/weight size' if size.startswith('~') else
           'catalog repository size (may contain multiple files)' if sized is not None else
           'not available; check model repository')
print('APPROXIMATE SPECS / PLANNING ONLY (not a measured benchmark)')
if params.endswith('*'):
    params_note='VERY ROUGH weight-equivalent from repo size; NOT an actual architecture count'
print(f'Parameters: {params} ({params_note})')
print(f'Disk/weights: {size} ({size_note})')
if family=='desert':
    # No uniform parameter/memory metadata published across CLI models.
    # CPU working-set bands are conservative planning allowances, not verified
    # vendor requirements; actual weights are downloaded/cached by its CLI.
    ram=('~2-4 GB CPU RAM' if repo=='desertant:clips' else '~0.5-2 GB CPU RAM')
    print('Runtime RAM allowance: '+ram+' (unverified planning estimate)')
    print('GPU VRAM: not required by the documented CLI workflow; CPU runtime')
    print('Performance: no comparable tok/s, frames/s or realtime-factor benchmark')
    print('Specialist task: '+task+'; NOT a general-purpose generative model')
else:
    lps_ram={
        'HuggingFaceTB/SmolLM2-135M-Instruct':0.8,
        'Qwen/Qwen3-0.6B':2.,
        'segmind/tiny-sd':6.,
        'cerspense/zeroscope_v2_576w':16.,
        'openai/whisper-tiny':2.,
    }
    lps_vram={
        'segmind/tiny-sd':2.,
        'cerspense/zeroscope_v2_576w':8.,
    }
    if family=='lps' and repo in lps_ram:
        print(f'Estimated system RAM floor: ~{lps_ram[repo]:g} GB (installer fit heuristic)')
        if repo in lps_vram:
            print(f'Estimated GPU VRAM floor: ~{lps_vram[repo]:g} GB (offload may differ)')
        else:
            print('GPU VRAM: optional/CPU-capable; speed depends on backend')
    elif need_gb is not None:
        # These are planning allowances, not tested minimum requirements.
        # GPU context size and CPU offload can change peak memory substantially.
        host_budget=max(4.,need_gb*1.3+2.)
        print(f'Estimated GPU VRAM / accelerator memory: ~{need_gb:g} GB (catalog fit heuristic)')
        print(f'Estimated host RAM budget: ~{host_budget:.1f} GB (rough; offload/context varies)')
    else:
        print('RAM / VRAM: insufficient metadata for a defensible numeric estimate')
    print(f'Fit estimate: {fit}; verify with an actual inference after installation')
    if kind=='text':
        print(f'Estimated text throughput: {speed} tok/s (not measured)' if number(speed) is not None else
              'Text throughput: no estimated speed available')
    else:
        print('Generation/transcription speed: unknown until benchmarked on this hardware')
print('Actual peak memory and download can exceed these estimates.')
PY_APPROX_SPECS
}

tui_model_browser_parse_rows() {
    local json_file="$1"
    "$VENV_DIR/bin/python" - "$json_file" <<'PY_MODEL_BROWSER_ROWS'
import json, re, sys
from pathlib import Path
rows = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")).get("models", [])

def repo_for(r):
    explicit = str(r.get("repo") or r.get("repo_id") or "").strip()
    if explicit:
        return explicit
    for src in (r.get("gguf_sources") or []):
        if isinstance(src, str) and "/" in src:
            return src
        if isinstance(src, dict):
            repo = src.get("repo_id") or src.get("repo") or src.get("id") or ""
            if repo:
                return repo
    name = str(r.get("name") or "")
    return name if name.count("/") == 1 else ""

def first_value(r, keys):
    for key in keys:
        value = r.get(key)
        if value is not None and str(value).strip() not in ("", "?"):
            return value
    return None

def model_size_display(r):
    exact = first_value(r, [
        "size_gb", "model_size_gb", "download_gb", "download_size_gb",
        "disk_gb", "file_size_gb", "estimated_size_gb", "artifact_size_gb",
        "size", "model_size", "download_size",
    ])
    if exact is not None:
        text = str(exact).strip()
        if re.search(r"[A-Za-z]", text):
            return text
        try:
            return f"{float(text):.1f}G"
        except ValueError:
            return text[:9]

    raw_params = first_value(r, [
        "parameter_count", "params_b", "parameters_b", "total_params_b",
        "parameter_count_billions",
    ])
    try:
        text = str(raw_params).strip().lower().replace(",", "")
        match = re.search(r"([0-9]+(?:\.[0-9]+)?)", text)
        params_b = float(match.group(1)) if match else None
    except (TypeError, ValueError):
        params_b = None

    if params_b is None:
        return "?"

    quant = str(r.get("quant") or "").upper()
    if any(token in quant for token in ("F32", "FP32", "FLOAT32")):
        bits = 32.0
    elif any(token in quant for token in ("F16", "FP16", "BF16", "FLOAT16")):
        bits = 16.0
    elif "FP8" in quant or "INT8" in quant:
        bits = 8.0
    else:
        match = re.search(r"(?:^|[-_])(?:Q|IQ)([0-9])", quant)
        bits = float(match.group(1)) + 0.5 if match else None

    if bits is None:
        return "?"
    size_gb = params_b * bits / 8.0 * 1.08
    return f"~{size_gb:.1f}G"

def compact_number(value):
    try:
        n = int(float(value or 0))
    except Exception:
        return "?"
    if n >= 1_000_000_000:
        return f"{n/1_000_000_000:.1f}B"
    if n >= 1_000_000:
        return f"{n/1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n/1_000:.1f}K"
    return str(n)

def clean(v):
    return str(v if v is not None else "").replace("\t", " ").replace("\n", " ").replace("\r", " ")

for r in rows:
    repo = repo_for(r)
    q = str(r.get("quant") or "")
    kind = str(r.get("model_type") or "text").lower()
    if kind not in ("text", "image", "video", "audio"):
        kind = "text"
    default_task = {
        "text": "text-generation",
        "image": "text-to-image",
        "video": "text-to-video",
        "audio": "automatic-speech-recognition",
    }.get(kind, "text-generation")
    task = str(r.get("pipeline_tag") or default_task)
    include = f"*{q}*" if kind == "text" and (q.startswith("Q") or q.startswith("IQ")) else ""
    downloads = r.get("downloads") if r.get("downloads") is not None else ""
    likes = r.get("likes") if r.get("likes") is not None else ""
    media_score = r.get("score")
    if kind in ("image", "video", "audio"):
        if media_score is not None and str(media_score).strip() not in ("", "?"):
            try:
                metric = f"{float(media_score):.1f}"
            except Exception:
                metric = str(media_score)
        else:
            metric = compact_number(downloads)
    else:
        metric = str(r.get("score") if r.get("score") is not None else "?")
    parameter_label = first_value(r, ["parameter_count", "parameter_label"])
    if parameter_label is None:
        raw_b = r.get("params_b")
        try:
            raw_b = float(raw_b)
            if raw_b > 0:
                parameter_label = ("~" if str(r.get("params_source") or "").lower() == "estimate" else "") + f"{raw_b:.3g}B"
        except (TypeError, ValueError):
            pass
    if parameter_label is None and kind in ("image", "video", "audio"):
        # Weight-equivalent ONLY; repositories may hold multiple checkpoints,
        # adapters, and auxiliary files. Not an architecture parameter count.
        size_label = model_size_display(r)
        if size_label not in ("?", "-"):
            try:
                raw_gb = float(re.search(r"([0-9]+(?:\.[0-9]+)?)", size_label).group(1))
                if raw_gb > 0:
                    parameter_label = f"~{raw_gb / 2:.2g}B*"
            except (AttributeError, ValueError):
                pass
    if parameter_label is None:
        parameter_label = "N/P"
    fields = [
        clean(r.get("name") or "?"),
        clean(repo),
        clean(kind),
        clean(task),
        clean(parameter_label),
        clean(model_size_display(r)),
        clean(q or "?"),
        clean(r.get("required_gb") if r.get("required_gb") is not None else "?"),
        clean(r.get("speed_tps") if r.get("speed_tps") is not None else "?"),
        clean(r.get("fit_level") or ("manual" if kind in ("image", "video", "audio") else "?")),
        clean(metric),
        clean(include),
        clean(downloads),
        clean(likes),
    ]
    print("\t".join(fields))
PY_MODEL_BROWSER_ROWS
}

tui_model_manual_browser() {
    local page_size="${MODEL_TUI_PAGE_SIZE:-15}" fetch_limit="${MODEL_TUI_FETCH_LIMIT:-200}"
    local query="" model_kind="all" model_group="${1:-normal}" page=0 selected=0 key key2 line row
    local status="Loading models..." total=0 pages=1 start end i idx visible old_selected
    local name repo kind task params size_display quant need speed fit metric include downloads likes
    local display_kind vram_display confirm skip_install marked_key record install_scope
    local manual_stack_pending="${2:-}" mark_count=0
    local -A marked_models=()
    local -a install_records=()
    local content_top=1 list_row=1 table_col=1 model_w=36 table_width=0
    local header header_lines=0
    local search_dirty=0 idle_ticks=0 remote_pid=0 remote_query="" remote_kind="" normal_loaded=0
    local catalog_file remote_rows_file remote_status_file initial_status_file
    local -a catalog_rows=() rows=() normal_catalog_rows=() lps_catalog_rows=() desert_catalog_rows=()
    local normal_catalog_seeded=0

    catalog_file="$(mktemp)"
    remote_rows_file="$(mktemp)"
    remote_status_file="$(mktemp)"
    initial_status_file="$(mktemp)"

    case "$model_group" in normal|lps|desert) ;; *) model_group=normal ;; esac

    # Fetching is deliberately separated from rendering.  Earlier versions did
    # a synchronous Hugging Face / hardware-fit request for *every character*
    # typed into the search field, which made typing and arrow-key navigation
    # feel sticky.  The browser now filters its cached catalogue immediately and
    # refreshes from the network only after a short idle debounce.
    tui_model_browser_fetch_to() {
        local q="$1" wanted_kind="$2" out_file="$3" status_file="$4"
        local tmpdir text_json image_json audio_json err_file text_rows_file image_rows_file audio_rows_file
        local text_ok=1 image_ok=1 video_ok=1 audio_ok=1 text_count=0 image_count=0 video_count=0 audio_count=0 j max_count
        local -a text_rows=() image_rows=() video_rows=() audio_rows=()
        # Bash dynamic scope makes all three model-manager fetch functions
        # read-only for the duration of this browser refresh.
        local MODEL_MANAGER_BROWSE_ONLY=1

        tmpdir="$(mktemp -d)" || return 1
        text_json="$tmpdir/text.json"
        image_json="$tmpdir/image.json"
        audio_json="$tmpdir/audio.json"
        err_file="$tmpdir/errors.log"
        text_rows_file="$tmpdir/text.rows"
        image_rows_file="$tmpdir/image.rows"
        audio_rows_file="$tmpdir/audio.rows"
        : >"$out_file"
        : >"$status_file"

        if [[ "$wanted_kind" == "all" || "$wanted_kind" == "text" ]]; then
            if model_manager_rank_json "$MODEL_MANAGER_USE_CASE" "$fetch_limit" "$q" score 1 >"$text_json" 2>>"$err_file"                && tui_model_browser_parse_rows "$text_json" >"$text_rows_file" 2>>"$err_file"; then
                mapfile -t text_rows <"$text_rows_file"
            else
                text_ok=0
            fi
        fi

        if [[ "$wanted_kind" == "all" || "$wanted_kind" == "image" || "$wanted_kind" == "video" ]]; then
            if model_manager_image_json "$fetch_limit" "$q" >"$image_json" 2>>"$err_file"                && tui_model_browser_parse_rows "$image_json" >"$image_rows_file" 2>>"$err_file"; then
                mapfile -t image_rows < <(awk -F'	' '$3=="image"{print}' "$image_rows_file")
                mapfile -t video_rows < <(awk -F'	' '$3=="video"{print}' "$image_rows_file")
            else
                image_ok=0
                video_ok=0
            fi
        fi

        if [[ "$wanted_kind" == "all" || "$wanted_kind" == "audio" ]]; then
            if model_manager_audio_json "$fetch_limit" "$q" >"$audio_json" 2>>"$err_file" \
               && tui_model_browser_parse_rows "$audio_json" >"$audio_rows_file" 2>>"$err_file"; then
                mapfile -t audio_rows <"$audio_rows_file"
            else
                audio_ok=0
            fi
        fi
        audio_count=${#audio_rows[@]}

        text_count=${#text_rows[@]}
        image_count=${#image_rows[@]}
        video_count=${#video_rows[@]}
        case "$wanted_kind" in
            text)
                ((${#text_rows[@]})) && printf '%s
' "${text_rows[@]}" >"$out_file"
                ;;
            image)
                ((${#image_rows[@]})) && printf '%s
' "${image_rows[@]}" >"$out_file"
                ;;
            video)
                ((${#video_rows[@]})) && printf '%s
' "${video_rows[@]}" >"$out_file"
                ;;
            audio)
                ((${#audio_rows[@]})) && printf '%s\n' "${audio_rows[@]}" >"$out_file"
                ;;
            all)
                max_count=$text_count
                (( image_count > max_count )) && max_count=$image_count
                (( video_count > max_count )) && max_count=$video_count
                (( audio_count > max_count )) && max_count=$audio_count
                for ((j=0; j<max_count; j++)); do
                    (( j < text_count )) && printf '%s
' "${text_rows[$j]}" >>"$out_file"
                    (( j < image_count )) && printf '%s
' "${image_rows[$j]}" >>"$out_file"
                    (( j < video_count )) && printf '%s
' "${video_rows[$j]}" >>"$out_file"
                    (( j < audio_count )) && printf '%s\n' "${audio_rows[$j]}" >>"$out_file"
                done
                ;;
        esac
        sed -i '/^$/d' "$out_file" 2>/dev/null || true

        case "$wanted_kind" in
            text)
                (( text_ok )) && printf '%s hardware-fitting language models
' "$text_count" >"$status_file"                     || printf 'Language-model source unavailable
' >"$status_file"
                ;;
            image)
                (( image_ok )) && printf '%s Hugging Face image-generation models
' "$image_count" >"$status_file"                     || printf 'Image-model source unavailable
' >"$status_file"
                ;;
            video)
                (( video_ok )) && printf '%s Hugging Face video-generation models
' "$video_count" >"$status_file"                     || printf 'Video-model source unavailable
' >"$status_file"
                ;;
            audio)
                (( audio_ok )) && printf '%s Hugging Face audio models\n' "$audio_count" >"$status_file" || printf 'Audio-model source unavailable\n' >"$status_file"
                ;;
            all)
                printf '%s models  |  %s text + %s image + %s video + %s audio' "$((text_count+image_count+video_count+audio_count))" "$text_count" "$image_count" "$video_count" "$audio_count" >"$status_file"
                (( ! text_ok )) && printf '  |  text source unavailable' >>"$status_file"
                (( ! image_ok )) && printf '  |  image source unavailable' >>"$status_file"
                (( ! video_ok )) && printf '  |  video source unavailable' >>"$status_file"
                (( ! audio_ok )) && printf '  |  audio source unavailable' >>"$status_file"
                printf '
' >>"$status_file"
                ;;
        esac
        rm -rf "$tmpdir"
        return 0
    }

    tui_model_browser_seed_normal() {
        # Local starter catalog for first-run/offline browsing. These are not
        # remotely verified search results; each estimate is visibly marked.
        # Selecting a model still requires explicit confirmation before the
        # full-stack install/system-update preflight runs.
        normal_catalog_seeded=1
        normal_catalog_rows=(
            $'Qwen2.5 7B Instruct\tQwen/Qwen2.5-7B-Instruct\ttext\ttext-generation\t~7.0B\t~15G\tBF16\t18\t?\tmanual\tstarter\t-\t?\t?'
            $'Stable Diffusion 1.5\tstable-diffusion-v1-5/stable-diffusion-v1-5\timage\ttext-to-image\t~0.9B\t~5G\tFP16\t6\t?\tmanual\tstarter\t-\t?\t?'
            $'ZeroScope 576w\tcerspense/zeroscope_v2_576w\tvideo\ttext-to-video\t~3.0B\t~8.5G\tFP16\t8\t?\tmanual\tstarter\t-\t?\t?'
            $'Whisper Small\topenai/whisper-small\taudio\tautomatic-speech-recognition\t~0.24B\t~0.5G\tFP16\t2\t?\tmanual\tstarter\t-\t?\t?'
        )
        return 0
    }

    tui_model_browser_ensure_normal_coverage() {
        # A partially online catalog must not hide whole model categories.
        # Add known, labelled offline examples only for absent types.
        local raw k kind seen_text=0 seen_image=0 seen_video=0 seen_audio=0
        local -a existing=("${normal_catalog_rows[@]}")
        for raw in "${existing[@]}"; do
            IFS=$'\t' read -r _ _ kind _ <<< "$raw"
            case "$kind" in
                text) seen_text=1 ;; image) seen_image=1 ;;
                video) seen_video=1 ;; audio) seen_audio=1 ;;
            esac
        done
        local -a starter=(
            $'Qwen2.5 7B Instruct\tQwen/Qwen2.5-7B-Instruct\ttext\ttext-generation\t~7.0B\t~15G\tBF16\t18\t?\tmanual\tstarter\t-\t?\t?'
            $'Stable Diffusion 1.5\tstable-diffusion-v1-5/stable-diffusion-v1-5\timage\ttext-to-image\t~0.9B\t~5G\tFP16\t6\t?\tmanual\tstarter\t-\t?\t?'
            $'ZeroScope 576w\tcerspense/zeroscope_v2_576w\tvideo\ttext-to-video\t~3.0B\t~8.5G\tFP16\t8\t?\tmanual\tstarter\t-\t?\t?'
            $'Whisper Small\topenai/whisper-small\taudio\tautomatic-speech-recognition\t~0.24B\t~0.5G\tFP16\t2\t?\tmanual\tstarter\t-\t?\t?'
        )
        if (( !seen_text )); then normal_catalog_rows+=("${starter[0]}"); normal_catalog_seeded=1; fi
        if (( !seen_image )); then normal_catalog_rows+=("${starter[1]}"); normal_catalog_seeded=1; fi
        if (( !seen_video )); then normal_catalog_rows+=("${starter[2]}"); normal_catalog_seeded=1; fi
        if (( !seen_audio )); then normal_catalog_rows+=("${starter[3]}"); normal_catalog_seeded=1; fi
        return 0
    }

    tui_model_browser_set_group() {
        # Keep each group independent: no Desert Ant tool is ever treated as
        # a text/image/video generator or sent to a Hugging Face downloader.
        if (( remote_pid > 0 )); then
            kill "$remote_pid" 2>/dev/null || true
            wait "$remote_pid" 2>/dev/null || true
            remote_pid=0
        fi
        if [[ "$model_group" == normal ]] && (( ! normal_loaded )); then
            normal_loaded=1
            if tui_model_browser_fetch_to "" "all" "$catalog_file" "$initial_status_file"; then
                mapfile -t normal_catalog_rows <"$catalog_file"
            fi
            tui_model_browser_ensure_normal_coverage
        fi
        case "$model_group" in
            normal) catalog_rows=("${normal_catalog_rows[@]}") ;;
            lps) catalog_rows=("${lps_catalog_rows[@]}") ;;
            desert) catalog_rows=("${desert_catalog_rows[@]}") ;;
        esac
        page=0; selected=0; search_dirty=0; idle_ticks=0
        tui_model_browser_apply_local
        return 0
    }

    tui_model_browser_recount() {
        total=${#rows[@]}
        pages=$(( (total + page_size - 1) / page_size ))
        (( pages < 1 )) && pages=1
        (( page >= pages )) && page=$((pages-1))
        (( page < 0 )) && page=0
        start=$((page*page_size))
        visible=$((total-start))
        (( visible > page_size )) && visible=$page_size
        (( visible < 0 )) && visible=0
        if (( visible == 0 )); then
            selected=0
        else
            (( selected >= visible )) && selected=$((visible-1))
            (( selected < 0 )) && selected=0
        fi
        # Browser helpers are called under `set -e`.  A false arithmetic test
        # such as `(( selected < 0 ))` returns status 1, so always end helpers
        # with an explicit success status instead of letting a harmless bounds
        # check terminate the whole TUI.
        return 0
    }

    tui_model_browser_apply_local() {
        local ql="${query,,}" raw row_kind
        rows=()
        for raw in "${catalog_rows[@]}"; do
            IFS=$'\t' read -r _ _ row_kind _ <<< "$raw"
            [[ "$model_kind" == "all" || "$row_kind" == "$model_kind" ]] || continue
            if [[ -n "$ql" && "${raw,,}" != *"$ql"* ]]; then
                continue
            fi
            rows+=("$raw")
        done
        tui_model_browser_recount
        if [[ -n "$query" ]]; then
            if (( total == 1 )); then status="1 instant cached match"; else status="$total instant cached matches"; fi
            (( search_dirty )) && status+="  |  live online refresh pending"
        else
            status="$total cached models"
        fi
        if [[ "$model_group" == normal ]] && (( normal_catalog_seeded )); then
            status+=' | offline/first-run starter list; specs approximate'
        fi
        return 0
    }

    tui_model_browser_merge_catalog() {
        local raw key
        local -A seen=()
        for raw in "${catalog_rows[@]}"; do
            key="${raw%%$'\t'*}"
            seen["$key"]=1
        done
        while IFS= read -r raw; do
            [[ -n "$raw" ]] || continue
            key="${raw%%$'\t'*}"
            [[ -n "${seen[$key]:-}" ]] && continue
            seen["$key"]=1
            catalog_rows+=("$raw")
        done <"$remote_rows_file"
        return 0
    }

    tui_model_browser_calc_table() {
        local probe
        if (( TUI_COLS < 62 )); then
            model_w=$((TUI_COLS - 30))
            (( model_w < 8 )) && model_w=8
            table_width=$((TUI_COLS - 2)); table_col=1
        elif (( TUI_COLS < 100 )); then
            model_w=$((TUI_COLS - 42))
            (( model_w < 12 )) && model_w=12
            table_width=$((TUI_COLS - 2)); table_col=1
        else
            model_w=36
            printf -v probe '       %-4s %-*s | %8s | %9s | %-10s | %8s | %-10s | %10s' \
                'TYPE' "$model_w" 'MODEL' 'PARAMS' 'SIZE' 'FORMAT' 'VRAM' 'FIT' 'SCORE/DL'
            table_width=${#probe}
            table_col=$(( (TUI_COLS-table_width)/2 + 1 ))
            (( table_col < 1 )) && table_col=1
        fi
        return 0
    }

    tui_model_browser_format_row() {
        local local_index="$1" is_selected="$2" absolute_index raw prefix
        absolute_index=$((page*page_size+local_index))
        raw="${rows[$absolute_index]:-}"
        IFS=$'\t' read -r name repo kind task params size_display quant need speed fit metric include downloads likes <<< "$raw"
        case "$kind" in
            image) display_kind='IMG' ;;
            video) display_kind='VID' ;;
            audio) display_kind='AUD' ;;
            *) display_kind='LLM' ;;
        esac
        vram_display="$need"
        if [[ "$kind" != "image" && "$vram_display" != '?' && "$vram_display" != 'CPU' && "$vram_display" != *[Gg] ]]; then
            vram_display+="G"
        fi
        local row_repo mark_key
        row_repo="$repo"
        mark_key="$model_group|$row_repo"
        if (( is_selected )); then
            [[ -n "${marked_models[$mark_key]:-}" ]] && prefix='>+' || prefix='> '
        else
            [[ -n "${marked_models[$mark_key]:-}" ]] && prefix=' +' || prefix='  '
        fi
        if (( TUI_COLS < 62 )); then
            printf -v line '%s%2d %-3.3s %-*.*s | %-5.5s | %-4.4s' \
                "$prefix" "$((local_index+1))" "$display_kind" "$model_w" "$model_w" "$name" "$params" "$fit"
        elif (( TUI_COLS < 100 )); then
            printf -v line '%s%2d %-3.3s %-*.*s | %-7.7s | %-6.6s | %-5.5s' \
                "$prefix" "$((local_index+1))" "$display_kind" "$model_w" "$model_w" "$name" "$params" "$size_display" "$fit"
        else
            printf -v line '%s%3d. %-4.4s %-*.*s | %8.8s | %9.9s | %-10.10s | %8.8s | %-10.10s | %10.10s' \
                "$prefix" "$((local_index+1))" "$display_kind" "$model_w" "$model_w" "$name" \
                "$params" "$size_display" "$quant" "$vram_display" "$fit" "$metric"
        fi
        return 0
    }

    tui_model_browser_draw_header_once() {
        _tui_size
        _tui_clear
        header="$(_tui_draw_header)"
        header_lines=0
        row=1
        while IFS= read -r line; do
            ((header_lines+=1))
            printf '\033[%d;1H%s' "$row" "$line"
            ((row+=1))
        done <<< "$header"
        (( header_lines > 0 )) && ((header_lines-=1))
        content_top=$((header_lines+2))
        # Extra rows for independent family and modality selectors.
        page_size=$((TUI_LINES - content_top - 8))
        (( page_size < 1 )) && page_size=1
        return 0
    }

    tui_model_browser_draw_content() {
        local controls mode_label header_line local_index family_line category_line pad
        controls='Space: mark | Enter: details/mark | Shift+I: INSTALL MARKED | Esc: back | Type: search'
        controls="$(_tui_fit_one_line "$controls" "$((TUI_COLS-2))")"
        mode_label="${model_group^^} / ${model_kind^^}"
        tui_model_browser_calc_table

        # Draw families and categories on separate rows, keeping both selectors
        # visible for ALL three model groups on every page.
        printf '\033[%d;1H\033[J' "$content_top"
        row=$content_top
        line="$(_tui_fit_one_line "MODEL MANUAL INSTALL | $mode_label | SEARCH: ${query:-<none>}" "$((TUI_COLS-2))")"
        pad=$(( (TUI_COLS-${#line})/2 )); ((pad<0)) && pad=0
        printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$line"; ((row+=1))
        line="$(_tui_fit_one_line "PAGE $((page+1))/$pages | $status | MARKED: $mark_count" "$((TUI_COLS-2))")"
        pad=$(( (TUI_COLS-${#line})/2 )); ((pad<0)) && pad=0
        printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$line"; ((row+=1))
        family_line="FAMILY [TAB]: NORMAL / L.P.S. / DESERT ANT | NOW: ${model_group^^}"
        category_line="TYPE [SHIFT+TAB]: [1] ALL [2] TEXT [3] PHOTO [4] VIDEO [5] AUDIO | NOW: ${model_kind^^}"
        line="$(_tui_fit_one_line "$family_line" "$((TUI_COLS-2))")"
        pad=$(( (TUI_COLS-${#line})/2 )); ((pad<0)) && pad=0
        printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$line"; ((row+=1))
        line="$(_tui_fit_one_line "$category_line" "$((TUI_COLS-2))")"
        pad=$(( (TUI_COLS-${#line})/2 )); ((pad<0)) && pad=0
        printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$line"; ((row+=2))

        if (( total > 0 )); then
            if (( TUI_COLS < 62 )); then
                printf -v header_line '    %-3s %-*s | %-5s | %-4s' 'TYPE' "$model_w" 'MODEL' 'PARAM' 'FIT'
            elif (( TUI_COLS < 100 )); then
                printf -v header_line '    %-3s %-*s | %-7s | %-6s | %-5s' 'TYPE' "$model_w" 'MODEL' 'PARAMS' 'SIZE' 'FIT'
            else
                printf -v header_line '       %-4s %-*s | %8s | %9s | %-10s | %8s | %-10s | %10s' \
                    'TYPE' "$model_w" 'MODEL' 'PARAMS' 'SIZE' 'FORMAT' 'VRAM' 'FIT' 'SCORE/DL'
            fi
            printf '\033[%d;%dH%s' "$row" "$table_col" "$header_line"
            ((row+=1))
            list_row=$row
            visible=$((total-page*page_size)); ((visible>page_size)) && visible=$page_size
            for ((local_index=0; local_index<visible; local_index++)); do
                tui_model_browser_format_row "$local_index" "$((local_index==selected))"
                printf '\033[%d;1H\033[2K\033[%d;%dH%s' "$((list_row+local_index))" "$((list_row+local_index))" "$table_col" "$line"
            done
            row=$((list_row+visible))
        else
            line='No matching models.'
            pad=$(( (TUI_COLS-${#line})/2 )); ((pad<0)) && pad=0
            printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$line"
            list_row=$((row+1)); ((row+=2))
        fi

        ((row+=1))
        line="SEARCH: ${query:-}"
        pad=$(( (TUI_COLS-${#line})/2 )); ((pad<0)) && pad=0
        printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$line"; ((row+=1))
        pad=$(( (TUI_COLS-${#controls})/2 )); ((pad<0)) && pad=0
        printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$controls"
        return 0
    }

    tui_model_browser_redraw_selection() {
        local old="$1" new="$2"
        (( total > 0 )) || return 0
        if (( old >= 0 && old < visible )); then
            tui_model_browser_format_row "$old" 0
            printf '\033[%d;1H\033[2K\033[%d;%dH%s' "$((list_row+old))" "$((list_row+old))" "$table_col" "$line"
        fi
        if (( new >= 0 && new < visible )); then
            tui_model_browser_format_row "$new" 1
            printf '\033[%d;1H\033[2K\033[%d;%dH%s' "$((list_row+new))" "$((list_row+new))" "$table_col" "$line"
        fi
        return 0
    }

    tui_model_browser_start_remote() {
        (( remote_pid == 0 )) || return 0
        [[ "$model_group" == normal && -n "$query" ]] || { search_dirty=0; return 0; }
        remote_query="$query"
        remote_kind="$model_kind"
        : >"$remote_rows_file"; : >"$remote_status_file"
        ( tui_model_browser_fetch_to "$remote_query" "$remote_kind" "$remote_rows_file" "$remote_status_file" ) >/dev/null 2>&1 &
        remote_pid=$!
        search_dirty=0
        idle_ticks=0
        status="Searching online for '$remote_query'…"
        tui_model_browser_draw_content
        return 0
    }

    tui_model_browser_collect_remote() {
        local rc=0 remote_status
        (( remote_pid > 0 )) || return 1
        kill -0 "$remote_pid" 2>/dev/null && return 1
        wait "$remote_pid" || rc=$?
        remote_pid=0
        if (( rc == 0 )); then
            tui_model_browser_merge_catalog
            normal_catalog_rows=("${catalog_rows[@]}")
            if [[ -s "$remote_rows_file" ]]; then
                normal_catalog_seeded=0
            fi
            if [[ "$model_group" == normal && "$query" == "$remote_query" && "$model_kind" == "$remote_kind" ]]; then
                mapfile -t rows <"$remote_rows_file"
                remote_status="$(cat "$remote_status_file" 2>/dev/null || true)"
                status="${remote_status:-Online search complete}"
                page=0; selected=0
                tui_model_browser_recount
                tui_model_browser_draw_content
            fi
        elif [[ "$query" == "$remote_query" && "$model_kind" == "$remote_kind" ]]; then
            status="Online refresh failed; showing cached matches"
            tui_model_browser_draw_content
        fi
        return 0
    }

    tui_model_browser_toggle_mark() {
        local raw target_group="$model_group" target_index="${1:-}" k
        (( target_index >= 0 && target_index < total )) || return 0
        raw="${rows[$target_index]}"
        IFS=$'\t' read -r name repo kind task params size_display quant need speed fit metric include downloads likes <<< "$raw"
        [[ -n "$repo" ]] || { status='Cannot select a model without a repository or tool ID'; return 0; }
        k="$target_group|$repo"
        if [[ -n "${marked_models[$k]:-}" ]]; then
            unset 'marked_models[$k]'
            mark_count=$((mark_count-1))
        else
            marked_models["$k"]="$target_group|$kind|$task|$repo|$include"
            mark_count=$((mark_count+1))
        fi
        return 0
    }

    _tui_begin
    tui_model_browser_draw_header_once

    # One initial catalogue load.  Everything after this is instant local
    # filtering plus a debounced asynchronous refresh.
    mapfile -t lps_catalog_rows < <(lps_catalog_rows)
    mapfile -t desert_catalog_rows < <(desertant_catalog_rows)
    if [[ "$model_group" == normal ]]; then
        normal_loaded=1
        if tui_model_browser_fetch_to "" "all" "$catalog_file" "$initial_status_file"; then
            mapfile -t normal_catalog_rows <"$catalog_file"
            status="$(cat "$initial_status_file" 2>/dev/null || true)"
        fi
        tui_model_browser_ensure_normal_coverage
    fi
    tui_model_browser_set_group
    tui_model_browser_draw_content

    while true; do
        # Harvest a completed background search without blocking navigation.
        tui_model_browser_collect_remote || true

        key=""
        if _tui_read_key_timeout key 0.08; then
            [[ -n "$key" ]] || continue
            case "$key" in
                $'\e')
                    key2=""
                    IFS= read -rsN 2 -t 0.04 key2 < /dev/tty || true
                    case "$key2" in
                        '') break ;;
                        '[A')
                            if (( visible > 0 )); then
                                old_selected=$selected; selected=$((selected-1)); ((selected<0)) && selected=$((visible-1))
                                tui_model_browser_redraw_selection "$old_selected" "$selected"
                            fi
                            ;;
                        '[B')
                            if (( visible > 0 )); then
                                old_selected=$selected; selected=$((selected+1)); ((selected>=visible)) && selected=0
                                tui_model_browser_redraw_selection "$old_selected" "$selected"
                            fi
                            ;;
                        '[D')
                            if (( pages > 1 )); then page=$((page-1)); ((page<0)) && page=$((pages-1)); selected=0; tui_model_browser_recount; tui_model_browser_draw_content; fi
                            ;;
                        '[C')
                            if (( pages > 1 )); then page=$((page+1)); ((page>=pages)) && page=0; selected=0; tui_model_browser_recount; tui_model_browser_draw_content; fi
                            ;;
                        '[Z')
                            # Shift+Tab cycles the category independently of
                            # plain Tab (which cycles the model family).
                            case "$model_kind" in
                                all) model_kind=text ;; text) model_kind=image ;;
                                image) model_kind=video ;; video) model_kind=audio ;;
                                audio) model_kind=all ;;
                            esac
                            page=0; selected=0; idle_ticks=0
                            [[ "$model_group" == normal && -n "$query" ]] && search_dirty=1 || search_dirty=0
                            tui_model_browser_apply_local; tui_model_browser_draw_content
                            ;;
                    esac
                    ;;
                $'\t')
                    case "$model_group" in normal) model_group=lps ;; lps) model_group=desert ;; desert) model_group=normal ;; esac
                    tui_model_browser_set_group; tui_model_browser_draw_content
                    ;;
                [1-5])
                    case "$key" in 1) model_kind=all ;; 2) model_kind=text ;; 3) model_kind=image ;; 4) model_kind=video ;; 5) model_kind=audio ;; esac
                    page=0; selected=0; idle_ticks=0
                    search_dirty=$([[ "$model_group" == normal && -n "$query" ]] && echo 1 || echo 0)
                    tui_model_browser_apply_local; tui_model_browser_draw_content
                    ;;
                $'\177'|$'\b')
                    if [[ -n "$query" ]]; then
                        query="${query:0:${#query}-1}"; page=0; selected=0; idle_ticks=0
                        [[ "$model_group" == normal && -n "$query" ]] && search_dirty=1 || search_dirty=0
                        tui_model_browser_apply_local; tui_model_browser_draw_content
                    fi
                    ;;
                $'\025')
                    query=''; page=0; selected=0; search_dirty=0; idle_ticks=0
                    tui_model_browser_apply_local; tui_model_browser_draw_content
                    ;;
                ' ')
                    if (( total > 0 )); then
                        idx=$((page*page_size+selected))
                        tui_model_browser_toggle_mark "$idx"
                        tui_model_browser_draw_content
                    fi
                    ;;
                I)
                    if (( mark_count == 0 )); then
                        status='Mark models with Space before requesting installation.'
                        tui_model_browser_draw_content
                    else
                        _tui_end; _tui_size; _tui_clear
                        _tui_print_center "INSTALL $mark_count SELECTED MODEL(S)? [y/N]"
                        _tui_print_center 'No OS update or installation has run while browsing.'
                        _tui_cursor_show; confirm=''; IFS= read -r confirm < /dev/tty || confirm=''; _tui_cursor_hide
                        _tui_begin
                        if [[ "${confirm,,}" == y || "${confirm,,}" == yes ]]; then
                            install_records=()
                            for marked_key in "${!marked_models[@]}"; do
                                install_records+=("${marked_models[$marked_key]}")
                            done
                            install_scope='--models-only'
                            [[ "$manual_stack_pending" == install-on-select ]] && install_scope='--full-stack'
                            _tui_run_command "INSTALLING $mark_count CONFIRMED MODELS" install-manual-batch "$install_scope" "${install_records[@]}"
                            if (( TUI_LAST_COMMAND_RC == 0 )); then
                                marked_models=(); mark_count=0
                            fi
                        fi
                        tui_model_browser_draw_header_once; tui_model_browser_draw_content
                    fi
                    ;;
                $'\n'|$'\r')
                    if (( total > 0 )); then
                        idx=$((page*page_size+selected))
                        if (( idx < total )); then
                            IFS=$'\t' read -r name repo kind task params size_display quant need speed fit metric include downloads likes <<< "${rows[$idx]}"
                            _tui_end; _tui_size; _tui_clear; printf '\n'
                            _tui_print_center "MODEL: $name"
                            _tui_print_center "Group: ${model_group^^}   Repository/Tool: ${repo:-unknown}"
                            if [[ "$model_group" == desert ]]; then
                                _tui_print_center "Desert Ant specialist: ${task:-?} (NOT a generative model)."
                                _tui_print_center "Parameters: not published (N/P); disk size: $size_display"
                            elif [[ "$kind" == "image" || "$kind" == "video" || "$kind" == "audio" ]]; then
                                if [[ "$kind" == "audio" ]]; then
                                    _tui_print_center "Type: AUDIO   Task: ${task:-?}"
                                elif [[ "$kind" == "video" ]]; then
                                    _tui_print_center "Type: VIDEO GENERATION   Pipeline: ${task:-text-to-video}"
                                else
                                    _tui_print_center "Type: IMAGE GENERATION   Pipeline: ${task:-text-to-image}"
                                fi
                                _tui_print_center "Parameters: $params   Repository size: $size_display   Precision: $quant"
                                _tui_print_center "Estimated VRAM: ${need:-?}G   Fit: ${fit:-?}   Hardware score: ${metric:-?}"
                                _tui_print_center "Downloads: ${downloads:-?}   Likes: ${likes:-?}"
                                printf '
'
                                if [[ "$kind" == "audio" ]]; then
                                    _tui_print_center 'Speech recognition and text-to-speech use a local Transformers pipeline.'
                                    _tui_print_center 'Other audio tasks may need a model-specific runtime and are download-only.'
                                elif [[ "$kind" == "video" ]]; then
                                    _tui_print_center 'Video models are downloaded as the complete Hugging Face repository.'
                                    _tui_print_center 'They can be used by supported image/video workflows; they are not set as the chat LLM.'
                                else
                                    _tui_print_center 'Image models are downloaded as the complete Hugging Face repository.'
                                    _tui_print_center 'Diffusers/Cookbook can use the cached model; it is not set as the chat LLM.'
                                fi
                            else
                                _tui_print_center "Type: LANGUAGE MODEL   Task: ${task:-text-generation}"
                                _tui_print_center "Parameters: $params   Size: $size_display   Quant: $quant   VRAM: ${need}G"
                                _tui_print_center "Estimated speed: ${speed} tok/s   Fit: $fit   Score: $metric"
                            fi
                            printf '\n'
                            model_approx_specs "$model_group" "${rows[$idx]}" | while IFS= read -r line; do
                                _tui_print_center "$line"
                            done
                            printf '\n'
                            _tui_print_center 'Add / remove this model from install queue? [y/N]'
                            _tui_cursor_show; confirm=''; IFS= read -r confirm < /dev/tty || confirm=''; _tui_cursor_hide
                            if [[ "${confirm,,}" == y || "${confirm,,}" == yes ]]; then
                                tui_model_browser_toggle_mark "$idx"
                            fi
                            _tui_begin
                            # Rebuild only after leaving the details screen.
                            tui_model_browser_draw_header_once; tui_model_browser_draw_content
                        fi
                    fi
                    ;;
                *)
                    if [[ "$key" == [[:print:]] ]]; then
                        query+="$key"; page=0; selected=0; idle_ticks=0
                        [[ "$model_group" == normal ]] && search_dirty=1 || search_dirty=0
                        tui_model_browser_apply_local; tui_model_browser_draw_content
                    fi
                    ;;
            esac
        else
            if [[ "$model_group" == normal ]] && (( search_dirty )); then
                ((idle_ticks+=1))
                # ~320 ms debounce: typing stays instant, remote results still
                # arrive automatically without requiring Enter.
                (( idle_ticks >= 4 )) && tui_model_browser_start_remote
            fi
        fi
    done

    if (( remote_pid > 0 )); then
        # Do not leave a search subshell attached to the terminal after exit.
        kill "$remote_pid" 2>/dev/null || true
        wait "$remote_pid" 2>/dev/null || true
    fi
    rm -f "$catalog_file" "$remote_rows_file" "$remote_status_file" "$initial_status_file"
    _tui_end
    return 0
}

tui_skills_market_default_rows() {
    local tmp="$1"
    curl -fsSL --max-time 20 "$SKILLS_API_BASE/" >"$tmp" || return 1
    python3 - "$tmp" <<'PY_SKILLS_DEFAULT_ROWS'
from html.parser import HTMLParser
from pathlib import Path
import re, sys

class Parser(HTMLParser):
    def __init__(self):
        super().__init__(); self.active=False; self.href=''; self.text=[]; self.rows=[]
    def handle_starttag(self, tag, attrs):
        if tag != 'a': return
        href=dict(attrs).get('href','')
        if re.fullmatch(r'/[^/?#]+/[^/?#]+/[^/?#]+', href):
            self.active=True; self.href=href; self.text=[]
    def handle_data(self, data):
        if self.active: self.text.append(data)
    def handle_endtag(self, tag):
        if tag != 'a' or not self.active: return
        path=self.href.strip('/')
        parts=path.split('/')
        if len(parts)==3:
            source=f"{parts[0]}/{parts[1]}"
            name=parts[2]
            # Ignore obvious non-skill navigation entries.
            if name not in {'docs','topics','packs','official','audits','api'}:
                text=' '.join(' '.join(self.text).split())
                installs='-'
                m=re.search(r'([0-9][0-9,.]*\s*[KMB]?)\s*(?:installs?|uses?)', text, re.I)
                if m: installs=m.group(1)
                self.rows.append((f"{source}/{name}", name, name, source, installs, f"https://skills.sh/{path}", '', ''))
        self.active=False; self.href=''; self.text=[]

html=Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace')
p=Parser(); p.feed(html)
seen=set()
for row in p.rows:
    if row[0] in seen: continue
    seen.add(row[0]); print('\t'.join(row))
PY_SKILLS_DEFAULT_ROWS
}

tui_skills_market_browser() {
    local page_size="${SKILLS_TUI_PAGE_SIZE:-15}" fetch_limit="${SKILLS_TUI_FETCH_LIMIT:-200}"
    local query="" page=0 selected=0 key key2 line row
    local status="Loading skills..." total=0 pages=1 start end i idx visible old_selected
    local skill_id slug name source installs url install_url description summary_text confirm
    local content_top=1 list_row=1 table_col=1 name_w=32 source_w=28 table_width=0
    local header header_lines=0
    local search_dirty=0 idle_ticks=0 remote_pid=0 remote_query=""
    local catalog_file html_file remote_rows_file remote_status_file json_file
    local -a catalog_rows=() rows=()

    catalog_file="$(mktemp)"
    html_file="$(mktemp)"
    remote_rows_file="$(mktemp)"
    remote_status_file="$(mktemp)"
    json_file="$(mktemp)"

    tui_skills_browser_recount() {
        total=${#rows[@]}
        pages=$(( (total + page_size - 1) / page_size ))
        (( pages < 1 )) && pages=1
        (( page >= pages )) && page=$((pages-1))
        (( page < 0 )) && page=0
        start=$((page*page_size))
        visible=$((total-start)); ((visible>page_size)) && visible=$page_size; ((visible<0)) && visible=0
        if (( visible == 0 )); then selected=0; else ((selected>=visible)) && selected=$((visible-1)); ((selected<0)) && selected=0; fi
        return 0
    }

    tui_skills_browser_apply_local() {
        local ql="${query,,}" raw
        rows=()
        for raw in "${catalog_rows[@]}"; do
            [[ -n "$ql" && "${raw,,}" != *"$ql"* ]] && continue
            rows+=("$raw")
        done
        tui_skills_browser_recount
        if [[ -n "$query" ]]; then
            if (( total == 1 )); then status="1 instant cached match"; else status="$total instant cached matches"; fi
            (( search_dirty )) && status+="  |  live online refresh pending"
        else
            status="$total cached skills"
        fi
        return 0
    }

    tui_skills_browser_fetch_to() {
        local q="$1" out="$2" stat="$3" tmpjson
        tmpjson="$(mktemp)" || return 1
        : >"$out"; : >"$stat"
        if ! skills_api_search_json "$q" "$fetch_limit" >"$tmpjson" 2>/dev/null; then
            rm -f "$tmpjson"; return 1
        fi
        if ! skills_extract_search_rows "$tmpjson" >"$out" 2>/dev/null; then
            rm -f "$tmpjson"; return 1
        fi
        local count
        count="$(awk 'NF{n++} END{print n+0}' "$out" 2>/dev/null)"
        printf '%s online search results\n' "$count" >"$stat"
        rm -f "$tmpjson"
        return 0
    }

    tui_skills_browser_merge_catalog() {
        local raw key
        local -A seen=()
        for raw in "${catalog_rows[@]}"; do key="${raw%%$'\t'*}"; seen["$key"]=1; done
        while IFS= read -r raw; do
            [[ -n "$raw" ]] || continue
            key="${raw%%$'\t'*}"
            [[ -n "${seen[$key]:-}" ]] && continue
            seen["$key"]=1; catalog_rows+=("$raw")
        done <"$remote_rows_file"
        return 0
    }

    tui_skills_browser_calc_table() {
        local probe excess
        name_w=32; source_w=28
        printf -v probe '       %-*s | %-*s | %10s' "$name_w" 'SKILL' "$source_w" 'SOURCE' 'INSTALLS'
        table_width=${#probe}
        if (( table_width > TUI_COLS - 2 )); then
            excess=$((table_width-(TUI_COLS-2)))
            if (( source_w > 18 )); then
                local cut=$excess; ((cut>source_w-18)) && cut=$((source_w-18)); source_w=$((source_w-cut)); excess=$((excess-cut))
            fi
            if (( excess > 0 )); then name_w=$((name_w-excess)); ((name_w<18)) && name_w=18; fi
            printf -v probe '       %-*s | %-*s | %10s' "$name_w" 'SKILL' "$source_w" 'SOURCE' 'INSTALLS'
            table_width=${#probe}
        fi
        table_col=$(( (TUI_COLS-table_width)/2 + 1 )); ((table_col<1)) && table_col=1
        return 0
    }

    tui_skills_browser_format_row() {
        local local_index="$1" is_selected="$2" absolute_index raw prefix
        absolute_index=$((page*page_size+local_index)); raw="${rows[$absolute_index]:-}"
        IFS=$'\t' read -r skill_id slug name source installs url install_url description <<< "$raw"
        (( is_selected )) && prefix='> ' || prefix='  '
        printf -v line '%s%3d. %-*.*s | %-*.*s | %10.10s' \
            "$prefix" "$((local_index+1))" "$name_w" "$name_w" "$name" "$source_w" "$source_w" "$source" "$installs"
        return 0
    }

    tui_skills_browser_draw_header_once() {
        _tui_size; _tui_clear
        header="$(_tui_draw_header)"; header_lines=0; row=1
        while IFS= read -r line; do ((header_lines+=1)); printf '\033[%d;1H%s' "$row" "$line"; ((row+=1)); done <<< "$header"
        ((header_lines>0)) && ((header_lines-=1)); content_top=$((header_lines+2))
        return 0
    }

    tui_skills_browser_draw_content() {
        local controls header_line local_index pad
        controls='[UP/DOWN] Select   [LEFT/RIGHT] Page   [ENTER] Summary / Install   [BACKSPACE] Search   [CTRL+U] Clear   [ESC] Back'
        tui_skills_browser_calc_table
        printf '\033[%d;1H\033[J' "$content_top"
        row=$content_top
        line="SKILLS.SH BROWSER  |  SEARCH: ${query:-<none>}"
        pad=$(( (TUI_COLS-${#line})/2 )); ((pad<0)) && pad=0; printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$line"; ((row+=1))
        line="PAGE $((page+1))/$pages  |  $status"
        pad=$(( (TUI_COLS-${#line})/2 )); ((pad<0)) && pad=0; printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$line"; ((row+=2))

        if (( total > 0 )); then
            printf -v header_line '       %-*s | %-*s | %10s' "$name_w" 'SKILL' "$source_w" 'SOURCE' 'INSTALLS'
            printf '\033[%d;%dH%s' "$row" "$table_col" "$header_line"; ((row+=1)); list_row=$row
            visible=$((total-page*page_size)); ((visible>page_size)) && visible=$page_size
            for ((local_index=0; local_index<visible; local_index++)); do
                tui_skills_browser_format_row "$local_index" "$((local_index==selected))"
                printf '\033[%d;1H\033[2K\033[%d;%dH%s' "$((list_row+local_index))" "$((list_row+local_index))" "$table_col" "$line"
            done
            row=$((list_row+visible))
        else
            line='No matching skills.'; pad=$(( (TUI_COLS-${#line})/2 )); ((pad<0)) && pad=0
            printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$line"; list_row=$((row+1)); ((row+=2))
        fi
        ((row+=1)); line="SEARCH: ${query:-}"; pad=$(( (TUI_COLS-${#line})/2 )); ((pad<0)) && pad=0
        printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$line"; ((row+=1)); pad=$(( (TUI_COLS-${#controls})/2 )); ((pad<0)) && pad=0
        printf '\033[%d;%dH%s' "$row" "$((pad+1))" "$controls"
        return 0
    }

    tui_skills_browser_redraw_selection() {
        local old="$1" new="$2"
        (( total > 0 )) || return 0
        if ((old>=0 && old<visible)); then
            tui_skills_browser_format_row "$old" 0
            printf '\033[%d;1H\033[2K\033[%d;%dH%s' "$((list_row+old))" "$((list_row+old))" "$table_col" "$line"
        fi
        if ((new>=0 && new<visible)); then
            tui_skills_browser_format_row "$new" 1
            printf '\033[%d;1H\033[2K\033[%d;%dH%s' "$((list_row+new))" "$((list_row+new))" "$table_col" "$line"
        fi
        return 0
    }

    tui_skills_browser_start_remote() {
        ((remote_pid==0)) || return 0
        [[ -n "$query" ]] || { search_dirty=0; return 0; }
        remote_query="$query"; : >"$remote_rows_file"; : >"$remote_status_file"
        ( tui_skills_browser_fetch_to "$remote_query" "$remote_rows_file" "$remote_status_file" ) >/dev/null 2>&1 &
        remote_pid=$!; search_dirty=0; idle_ticks=0
        status="Searching skills.sh for '$remote_query'…"; tui_skills_browser_draw_content
        return 0
    }

    tui_skills_browser_collect_remote() {
        local rc=0 remote_status
        ((remote_pid>0)) || return 1
        kill -0 "$remote_pid" 2>/dev/null && return 1
        wait "$remote_pid" || rc=$?; remote_pid=0
        if ((rc==0)); then
            tui_skills_browser_merge_catalog
            if [[ "$query" == "$remote_query" ]]; then
                mapfile -t rows <"$remote_rows_file"; remote_status="$(cat "$remote_status_file" 2>/dev/null || true)"
                status="${remote_status:-Online search complete}"; page=0; selected=0; tui_skills_browser_recount; tui_skills_browser_draw_content
            fi
        elif [[ "$query" == "$remote_query" ]]; then
            status='Online refresh failed; showing cached matches'; tui_skills_browser_draw_content
        fi
        return 0
    }

    _tui_begin
    tui_skills_browser_draw_header_once
    if tui_skills_market_default_rows "$html_file" >"$catalog_file" 2>/dev/null; then
        mapfile -t catalog_rows <"$catalog_file"; rows=("${catalog_rows[@]}"); status="${#rows[@]} cached skills"
    else
        catalog_rows=(); rows=(); status='Unable to load skills.sh catalogue.'
    fi
    tui_skills_browser_recount; tui_skills_browser_draw_content

    while true; do
        tui_skills_browser_collect_remote || true
        key=''
        if _tui_read_key_timeout key 0.08; then
            [[ -n "$key" ]] || continue
            case "$key" in
                $'\e')
                    key2=''; IFS= read -rsN 2 -t 0.04 key2 < /dev/tty || true
                    case "$key2" in
                        '') break ;;
                        '[A') if ((visible>0)); then old_selected=$selected; selected=$((selected-1)); ((selected<0)) && selected=$((visible-1)); tui_skills_browser_redraw_selection "$old_selected" "$selected"; fi ;;
                        '[B') if ((visible>0)); then old_selected=$selected; selected=$((selected+1)); ((selected>=visible)) && selected=0; tui_skills_browser_redraw_selection "$old_selected" "$selected"; fi ;;
                        '[D') if ((pages>1)); then page=$((page-1)); ((page<0)) && page=$((pages-1)); selected=0; tui_skills_browser_recount; tui_skills_browser_draw_content; fi ;;
                        '[C') if ((pages>1)); then page=$((page+1)); ((page>=pages)) && page=0; selected=0; tui_skills_browser_recount; tui_skills_browser_draw_content; fi ;;
                    esac
                    ;;
                $'\177'|$'\b')
                    if [[ -n "$query" ]]; then query="${query:0:${#query}-1}"; page=0; selected=0; idle_ticks=0; [[ -n "$query" ]] && search_dirty=1 || search_dirty=0; tui_skills_browser_apply_local; tui_skills_browser_draw_content; fi
                    ;;
                $'\025') query=''; page=0; selected=0; search_dirty=0; idle_ticks=0; tui_skills_browser_apply_local; tui_skills_browser_draw_content ;;
                $'\n'|$'\r')
                    if ((total>0)); then
                        idx=$((page*page_size+selected))
                        if ((idx<total)); then
                            IFS=$'\t' read -r skill_id slug name source installs url install_url description <<< "${rows[$idx]}"
                            _tui_end; _tui_size; _tui_clear; printf '\n'; _tui_print_center "SKILL: $name"; _tui_print_center "Source: $source"; _tui_print_center "Installs: $installs"; printf '\n'
                            summary_text="${description:-}"
                            if [[ -z "$summary_text" && -n "$skill_id" ]]; then summary_text="$(skills_summary_by_id "$skill_id" 2>/dev/null | awk -F '\t' 'NR==1{print $4}')"; fi
                            _tui_print_center 'SUMMARY'; printf '  %s\n' "${summary_text:-No summary available.}" | cut -c1-180
                            printf '\n'; _tui_print_center 'Install this skill? [Y/n]'; _tui_cursor_show; confirm=''; IFS= read -r confirm < /dev/tty || confirm=''; _tui_cursor_hide
                            if [[ -z "$confirm" || "${confirm,,}" == y || "${confirm,,}" == yes ]]; then
                                _tui_run_command "Installing skill: $source/$name" skills-install "$source/$name"
                            else
                                _tui_begin
                            fi
                            tui_skills_browser_draw_header_once; tui_skills_browser_draw_content
                        fi
                    fi
                    ;;
                *)
                    if [[ "$key" == [[:print:]] ]]; then query+="$key"; page=0; selected=0; search_dirty=1; idle_ticks=0; tui_skills_browser_apply_local; tui_skills_browser_draw_content; fi
                    ;;
            esac
        else
            if ((search_dirty)); then ((idle_ticks+=1)); ((idle_ticks>=4)) && tui_skills_browser_start_remote; fi
        fi
    done

    if ((remote_pid>0)); then kill "$remote_pid" 2>/dev/null || true; wait "$remote_pid" 2>/dev/null || true; fi
    rm -f "$catalog_file" "$html_file" "$remote_rows_file" "$remote_status_file" "$json_file"
    _tui_end
    return 0
}

tui_model_manager_menu() {
    local choice
    while true; do
        if _tui_menu 'MODEL MANAGER / HARDWARE FIT' \
            'SHOW LOCAL MODEL PROVIDERS' \
            'RANK MODELS (TABLE)' \
            'RANK MODELS (JSON)' \
            'AUTO-PICK PERFECT-FIT MODEL' \
            'MANUAL MODEL PICKER' \
            'SET DEFAULT PROVIDER + MODEL' \
            'BACK'; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) _tui_run_command 'Local model providers' providers ;;
                1) _tui_run_command 'Ranking models for detected hardware' model-list ;;
                2) _tui_run_command 'Ranking models as JSON' model-list-json ;;
                3) _tui_run_command 'Automatically selecting a PERFECT-fit model' model-pick ;;
                4) tui_model_manual_browser ;;
                5) tui_model_default ;;
                6) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

tui_ollama_menu() {
    local choice model
    while true; do
        if _tui_menu 'OLLAMA MANAGEMENT' \
            'START OLLAMA' \
            'STOP OLLAMA' \
            'RESTART OLLAMA' \
            'SHOW STATUS / MODELS' \
            'ENABLE AUTO-START' \
            'DISABLE AUTO-START' \
            'SYNC MODELS INTO ZARZYSSEUS' \
            'PULL MODEL            [opull]' \
            'PULL MODEL            [ollama-pull]' \
            'PULL MODEL            [pull]' \
            'BACK'; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) _tui_run_command 'Starting Ollama' ollama-start ;;
                1) _tui_run_command 'Stopping Ollama' ollama-stop ;;
                2) _tui_run_command 'Restarting Ollama' ollama-restart ;;
                3) _tui_run_command 'Ollama status' ollama-status ;;
                4) _tui_run_command 'Enabling Ollama automatic startup' ollama-enable ;;
                5) _tui_run_command 'Disabling Ollama automatic startup' ollama-disable ;;
                6) _tui_run_command 'Synchronizing Ollama models' ollama-sync ;;
                7) tui_opull ;;
                8)
                    _tui_prompt 'Ollama model (for example llama3.1:8b)'
                    model="$TUI_INPUT"
                    [[ -n "$model" ]] && _tui_run_command "Ollama pull: $model" ollama-pull "$model"
                    ;;
                9)
                    _tui_prompt 'Ollama model (for example llama3.1:8b)'
                    model="$TUI_INPUT"
                    [[ -n "$model" ]] && _tui_run_command "Ollama pull alias: $model" pull "$model"
                    ;;
                10) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

tui_mlx_menu() {
    local choice model
    while true; do
        if _tui_menu 'MLX-LM MANAGEMENT' \
            'INSTALL / VERIFY MLX-LM' \
            'SHOW MLX-LM STATUS' \
            'PULL MODEL + START SERVER   [mpull]' \
            'SET MLX-LM MODEL AS DEFAULT' \
            'BACK'; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) _tui_run_command 'Installing / verifying MLX-LM' mlx-install ;;
                1) _tui_run_command 'MLX-LM status' mlx-status ;;
                2) tui_pull_with_optional_include mpull 'MLX-LM pull' ;;
                3)
                    _tui_prompt 'MLX-LM MODEL (org/model)'
                    model="$TUI_INPUT"
                    [[ -n "$model" ]] && _tui_run_command "Setting MLX-LM default: $model" model-default mlx_lm "$model"
                    ;;
                4) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

tui_hf_menu() {
    local choice model include
    while true; do
        if _tui_menu 'HUGGING FACE / MODEL FILES' \
            'SET / INSPECT / CLEAR HF TOKEN' \
            'HF TOKEN STATUS' \
            'CLEAR HF TOKEN' \
            'DOWNLOAD MODEL              [hf-pull]' \
            'REPAIR COMPLETED HF DOWNLOAD' \
            'DOWNLOAD MODEL              [model-install]' \
            'BACK'; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) _tui_run_command 'Hugging Face token setup' hf-token ;;
                1) _tui_run_command 'Hugging Face token status' hf-token status ;;
                2) _tui_run_command 'Clearing Hugging Face token' hf-token clear ;;
                3) tui_pull_with_optional_include hf-pull 'Hugging Face pull' ;;
                4)
                    _tui_prompt 'MODEL ID (org/model)'
                    model="$TUI_INPUT"
                    [[ -n "$model" ]] && _tui_run_command "Repairing HF download: $model" hf-repair "$model"
                    ;;
                5) tui_pull_with_optional_include model-install 'Model install' ;;
                6) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

tui_runtime_menu() {
    local choice
    while true; do
        if _tui_menu 'MODEL RUNTIME DOWNLOADS' \
            'OLLAMA    |  opull  |  PULL MODEL' \
            'VLLM      |  vpull  |  PULL MODEL' \
            'SGLANG    |  spull  |  PULL MODEL' \
            'MLX-LM    |  mpull  |  PULL MODEL' \
            'BACK'; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) tui_opull ;;
                1) tui_pull_with_optional_include vpull 'vLLM pull' ;;
                2) tui_pull_with_optional_include spull 'SGLang pull' ;;
                3) tui_pull_with_optional_include mpull 'MLX-LM pull' ;;
                4) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

# --------------------------------------------------------------------------
# Installed-skill health inspector and explicitly selected dependency repair.
# Read-only inspection never executes untrusted SKILL.md commands or installs.
# --------------------------------------------------------------------------
skills_health_roots() {
    local name path rest file root real slug
    local -A seen=() seen_names=()
    while IFS=$'\t' read -r name path rest; do
        [[ -f "$path/SKILL.md" ]] || continue
        real="$(readlink -f -- "$path" 2>/dev/null || printf '%s' "$path")"
        [[ -n "${seen[$real]:-}" ]] && continue
        seen["$real"]=1
        seen_names["$(basename "$real")"]=1
        printf '%s\n' "$real"
    done < <(skills_installed_catalog)
    for root in "$AUTO_FIT_SKILL_DIR" "$LPS_SKILLS_DIR" "$DESERTANT_SKILL_DIR" "$ODYSSEUS_DATA_DIR/skills/imported"; do
        [[ -d "$root" ]] || continue
        while IFS= read -r -d '' file; do
            path="$(dirname "$file")"
            real="$(readlink -f -- "$path" 2>/dev/null || printf '%s' "$path")"
            [[ -n "${seen[$real]:-}" ]] && continue
            slug="$(basename "$real")"
            # Imported copies are mirrors; prefer the editable global/generated
            # source. Do not repair the same skill twice under two paths.
            if [[ "$root" == "$ODYSSEUS_DATA_DIR/skills/imported" && -n "${seen_names[$slug]:-}" ]]; then
                continue
            fi
            seen["$real"]=1
            seen_names["$slug"]=1
            printf '%s\n' "$real"
        done < <(find "$root" -mindepth 2 -maxdepth 2 -type f -name SKILL.md -print0 2>/dev/null)
    done
}

skills_health_snapshot() {
    # Args: [one optional selected root to run an actual --check on].
    # TSV: canonical path, display name, status, specific measured reason.
    local focused="${1:-}" py="${VENV_PY:-}" root
    local -a roots=()
    mapfile -t roots < <(skills_health_roots)
    [[ -x "$py" ]] || py="$(command -v python3 || true)"
    [[ -n "$py" ]] || { echo 'ERROR: Python is required to inspect installed skills.' >&2; return 1; }
    "$py" - "$focused" "$LPS_SKILLS_DIR" "$LPS_VENV/bin/python" "$DESERTANT_SKILL_DIR" "${roots[@]}" <<'PY_SKILL_HEALTH'
import importlib.metadata as metadata
import json, os, re, shutil, subprocess, sys
from pathlib import Path
try:
    from packaging.requirements import Requirement
    from packaging.markers import default_environment
except ImportError:
    from pip._vendor.packaging.requirements import Requirement
    from pip._vendor.packaging.markers import default_environment

focus = sys.argv[1]
lps_dir, lps_python, desert_dir = map(Path, sys.argv[2:5])
roots = [Path(p) for p in sys.argv[5:]]

def safe(s):
    return ' '.join(str(s).replace('\t', ' ').replace('\n', ' ').replace('\r', ' ').split())

probe_cache = {}
def probe(argv, timeout=3):
    key = tuple(argv)
    if key not in probe_cache:
        try:
            probe_cache[key] = subprocess.run(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                stdin=subprocess.DEVNULL, timeout=timeout, check=False).returncode == 0
        except (OSError, subprocess.TimeoutExpired):
            probe_cache[key] = False
    return probe_cache[key]

def req_check(raw):
    try:
        r = Requirement(raw)
        if r.marker and not r.marker.evaluate(default_environment()):
            return None
        version = metadata.version(r.name)
        if r.specifier and version not in r.specifier:
            return f'{r.name} {version} (needs {r.specifier})'
    except metadata.PackageNotFoundError:
        return f'{raw} (not installed)'
    except (ValueError, Exception) as exc:
        return f'unverified requirement {raw}: {safe(exc)}'
    return None

for root in roots:
    problems, warnings, auth = [], [], []
    md = root / 'SKILL.md'
    try:
        body = md.read_text(encoding='utf-8', errors='replace')
    except OSError as exc:
        print('\t'.join(map(safe, (str(root), root.name, 'MISSING', f'SKILL.md: {exc}'))))
        continue
    match = re.search(r'(?im)^name\s*:\s*["\']?([^\n"\']+)', body)
    name = match.group(1).strip() if match else root.name
    declared = False
    reqs = root / 'requirements.txt'
    if reqs.is_file():
        declared = True
        for line in reqs.read_text(errors='replace').splitlines():
            line = line.split('#', 1)[0].strip()
            if not line: continue
            if line.startswith(('-r ', '--requirement', '-e ', '--editable', '-c ', '--constraint')):
                warnings.append(f'Nested/editable requirement needs manual verification: {line}')
                continue
            if line.startswith('-'): continue
            missing = req_check(line)
            if missing: problems.append('Python: ' + missing)
    project = root / 'pyproject.toml'
    if project.is_file() and not reqs.is_file():
        declared = True
        try:
            import tomllib
            data = tomllib.loads(project.read_text(encoding='utf-8'))
            specs = data.get('project', {}).get('dependencies', [])
            for raw in specs:
                missing = req_check(raw)
                if missing: problems.append('Python: ' + missing)
            if data.get('project', {}).get('dynamic') and 'dependencies' in data['project']['dynamic']:
                warnings.append('Dynamic pyproject dependencies cannot be fully checked')
        except (OSError, ValueError) as exc:
            warnings.append('pyproject parse failed: ' + safe(exc))
    # Static AST only; never execute untrusted skill scripts in the health poll.
    reviewed = {
        'PIL': 'pillow', 'docx': 'python-docx', 'pptx': 'python-pptx',
        'openpyxl': 'openpyxl', 'pypdf': 'pypdf', 'reportlab': 'reportlab',
        'yaml': 'PyYAML', 'dotenv': 'python-dotenv', 'fitz': 'pymupdf',
        'cv2': 'opencv-python-headless', 'numpy': 'numpy', 'scipy': 'scipy',
        'pandas': 'pandas', 'requests': 'requests', 'httpx': 'httpx',
        'bs4': 'beautifulsoup4', 'faster_whisper': 'faster-whisper',
        'speech_recognition': 'SpeechRecognition', 'librosa': 'librosa',
        'soundfile': 'soundfile', 'pydub': 'pydub', 'moviepy': 'moviepy',
        'sklearn': 'scikit-learn', 'rich': 'rich', 'typer': 'typer',
    }
    import ast, importlib.util
    local_scripts = [root / 'run.py'] + list((root / 'scripts').glob('*.py'))
    referenced = set()
    for file in local_scripts[:33]:
        if not file.is_file() or file.is_symlink() or file.stat().st_size > 512_000:
            continue
        try:
            code = ast.parse(file.read_text(encoding='utf-8', errors='replace'))
        except (OSError, SyntaxError):
            continue
        for node in ast.walk(code):
            if isinstance(node, ast.Import):
                names = (n.name for n in node.names)
            elif isinstance(node, ast.ImportFrom) and node.level == 0:
                names = (node.module or '',)
            else:
                continue
            for import_name in names:
                mod = import_name.split('.', 1)[0]
                if mod in reviewed: referenced.add(mod)
    if referenced:
        declared = True
    for mod in sorted(referenced):
        try:
            installed = importlib.util.find_spec(mod) is not None
        except (ValueError, ImportError, AttributeError):
            installed = False
        if not installed:
            problems.append(f'Python script import: {mod} ({reviewed[mod]}) missing')
    package = root / 'package.json'
    if package.is_file():
        declared = True
        if not shutil.which('npm'):
            problems.append('npm executable missing')
        try:
            manifest = json.loads(package.read_text(encoding='utf-8'))
            deps = {**manifest.get('dependencies', {}), **manifest.get('optionalDependencies', {})}
            for dep in deps:
                node_root = root / 'node_modules' / dep / 'package.json'
                if not node_root.is_file():
                    problems.append(f'Node: {dep} missing from node_modules')
            if deps and str(root) == focus and not probe(['npm', 'ls', '--omit=dev', '--depth=0', '--prefix', str(root)], 5):
                warnings.append('npm dependency tree check failed')
        except (OSError, ValueError, TypeError) as exc:
            problems.append('Invalid package.json: ' + safe(exc))
    # A prompt skill may invoke the Skills CLI through npx, without package.json.
    if re.search(r'(?m)(?:^|`)[ \t]*(?:\$[ \t]*)?npx[ \t]+(?:--yes[ \t]+)?skills(?:[ \t]|`|$)', body):
        declared = True
        if not shutil.which('npx'):
            problems.append('CLI: npx missing (needed by npx skills)')

    # Only inspect explicit executable requirements; prose mentions alone do not
    # turn a command into a required dependency.
    for binary in sorted(set(re.findall(r'(?m)\bcommand\s+-v\s+([a-zA-Z][a-zA-Z0-9_-]*)', body))):
        declared = True
        if not shutil.which(binary): problems.append('CLI: ' + binary + ' missing')
    if root.name == 'agent-browser' or re.search(r'\bagent-browser\s+install\b', body):
        declared = True
        if not shutil.which('agent-browser'):
            problems.append('agent-browser CLI missing')
        elif not probe(['agent-browser', 'doctor', '--offline', '--quick'], 5):
            warnings.append('Browser runtime check failed; F repairs Chrome and Linux libraries')
    if re.search(r'@runcomfy/cli|\bruncomfy\s+(?:login|run|whoami)', body, re.I):
        declared = True
        if not shutil.which('runcomfy'): problems.append('RunComfy CLI missing')
        elif not probe(['runcomfy', 'whoami'], 4): auth.append('RunComfy browser authorization required')
    if re.search(r'\bgh\s+auth\s+login\b', body):
        declared = True
        if not shutil.which('gh'): problems.append('GitHub CLI missing')
        elif not probe(['gh', 'auth', 'status'], 4): auth.append('GitHub authorization required')
    if re.search(r'\bhf\s+auth\s+login\b', body):
        declared = True
        hf = shutil.which('hf')
        if not hf: problems.append('Hugging Face CLI missing')
        elif not probe([hf, 'auth', 'whoami'], 4): auth.append('Hugging Face authorization required')
    meta = root / 'model.json'
    if meta.is_file():
        declared = True
        try:
            info = json.loads(meta.read_text(encoding='utf-8'))
            snapshot = info.get('snapshot')
            if snapshot and not Path(snapshot).is_dir():
                problems.append('Model snapshot missing: ' + snapshot)
            if not snapshot and not info.get('repo'):
                warnings.append('Model metadata has no repo/snapshot')
        except (ValueError, OSError) as exc:
            problems.append('Invalid model metadata: ' + safe(exc))
    if root.parent == desert_dir:
        declared = True
        model = root.name.removeprefix('zarzysseus-low-spec-')
        cli = shutil.which('desertant') or shutil.which('da')
        if not cli:
            for candidate in (Path.home()/'.local/bin/desertant', Path.home()/'.local/bin/da'):
                if candidate.is_file() and os.access(candidate, os.X_OK):
                    cli = str(candidate); break
        if not cli: problems.append('Desert Ant Linux CLI missing')
        elif str(root) == focus and not probe([cli, 'info', model], 6):
            problems.append('Desert Ant model info check failed: ' + model)
    # The selected generated runner implements --check without producing media.
    # Other third-party scripts are not executed just to obtain a health score.
    runner = root / 'run.py'
    if str(root) == focus and runner.is_file() and (
        'auto-fit-skills' in root.parts or root.parent == lps_dir
    ) and not problems:
        declared = True
        runner_py = str(lps_python) if root.parent == lps_dir and lps_python.is_file() else sys.executable
        try:
            result = subprocess.run([runner_py, str(runner), '--check'],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                stdin=subprocess.DEVNULL, text=True, timeout=12, check=False)
            if result.returncode:
                problems.append('Runtime --check failed: ' + safe(result.stdout)[-220:])
        except (OSError, subprocess.TimeoutExpired) as exc:
            problems.append('Runtime --check failed: ' + safe(exc))
    # Prompt-only skills need no invented package manifest. Verify readable
    # instructions and check for executable payloads before declaring that
    # dependencies are simply "unknown". This is not an end-to-end test.
    if not declared and not problems and not warnings and not auth:
        prose = re.sub(r'(?s)\A---\s*\n.*?\n---\s*\n?', '', body).strip()
        runnable = []
        for pattern in ('*.py', '*.sh', '*.bash', '*.js', '*.mjs', '*.cjs', '*.ts',
                        'scripts/*', 'bin/*', 'tools/*', 'Dockerfile', 'Makefile', 'environment.yml'):
            for candidate in root.glob(pattern):
                if candidate.is_file() and not candidate.is_symlink():
                    runnable.append(candidate.relative_to(root).as_posix())
                    if len(runnable) >= 3: break
            if len(runnable) >= 3: break
        if runnable:
            warnings.append('Undeclared executable files: ' + ', '.join(runnable))
        elif len(prose) < 40:
            warnings.append('SKILL.md has too little instruction content to check')
        else:
            declared = 'prompt-only'
    if problems:
        status = 'MISSING'
        details = '; '.join(problems[:3])
    elif auth:
        status = 'AUTH'
        details = '; '.join(auth[:3])
    elif warnings:
        status = 'REVIEW'
        details = '; '.join(warnings[:3])
    elif declared == 'prompt-only':
        status = 'PROMPT'
        details = 'Instruction-only skill: SKILL.md checked, no runnable payload or package dependencies detected; behavior untested'
    elif declared:
        status = 'CHECKED'
        details = 'Declared dependencies available; end-to-end inference not tested'
    else:
        status = 'UNDECLARED'
        details = 'No declared dependencies found; not evidence of missing packages or working functionality'
    print('\t'.join(map(safe, (str(root), name, status, details))))
PY_SKILL_HEALTH
}

skills_repair_selected_roots() {
    # The selected/Fix All engine uses the same validated paths, bounded
    # dependency repair, and single deferred application restart. No OS upgrade.
    (( $# > 0 )) || { echo 'Select skills with Space before pressing F.'; return 2; }
    local root repo kind specialist cli health_row health_state health_detail
    local rc=0 synced=0 count=0 total=$# start_time skill_start elapsed
    local stage='' outcome='' note='' name='' snapshot='' snapshot_path
    local passed=0 prompt_only=0 unverified=0 needs_auth=0 review=0 failed=0
    local -A known=() seen=() initial_state=() initial_detail=()
    local -a passed_names=() prompt_names=() unverified_names=() auth_names=() review_names=() failed_names=()
    while IFS= read -r root; do known["$root"]=1; done < <(skills_health_roots)
    start_time="$(date +%s)"
    printf '\n%s\n' '================================================================'
    printf '  ZARZYSSEUS SKILL REPAIR | %d selected | %s\n' "$total" "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '%s\n' '================================================================'
    echo '[PLAN] 1. Inspect installed skill health (read-only).'
    echo '[PLAN] 2. Restore model-specific / OS / Python / Node prerequisites.'
    echo '[PLAN] 3. Handle provider authorization and browser dependencies.'
    echo '[PLAN] 4. Verify runtime, sync skills, then summarize results.'
    echo '[NOTE] CHECKED = prerequisites available, not a complete inference test.'
    echo '[NOTE] PROMPT = instructions and structure checked, no installable runtime found; not a behavior test.'
    echo '[NOTE] UNDECLARED = executable/runtime prerequisites are not machine-checkable.'
    echo '[NOTE] Provider login needs your authorization; passwords are never collected here.'
    echo '[NOTE] No full operating-system update will run during skill repair.'
    snapshot_path="$(mktemp)" || return 1
    if skills_health_snapshot >"$snapshot_path"; then
        while IFS=$'\t' read -r root name health_state health_detail; do
            [[ -n "$root" ]] || continue
            initial_state["$root"]="$health_state"
            initial_detail["$root"]="$health_detail"
        done <"$snapshot_path"
        echo '[SCAN] Initial health snapshot obtained.'
    else
        echo '[SCAN] Initial probe failed; continuing with individual checks.'
    fi
    rm -f -- "$snapshot_path"
    for root in "$@"; do
        ((count+=1))
        name="$(basename "$root")"
        skill_start="$(date +%s)"
        outcome='FAILED'; note=''; stage='validation'
        printf '\n%s\n' '----------------------------------------------------------------'
        printf '[%d/%d] %s\n' "$count" "$total" "$name"
        printf '    [PATH] %s\n' "$root"
        printf '    [BEFORE] %s — %s\n' "${initial_state[$root]:-NOT SCANNED}" "${initial_detail[$root]:-No initial detail available}"
        if [[ -z "${known[$root]:-}" || -n "${seen[$root]:-}" ]]; then
            note='Invalid, unavailable or repeated skill root; no changes made.'
            echo "    [FAILED] $note"
            failed_names+=("$name: $note"); ((failed+=1)); rc=1
            continue
        fi
        seen["$root"]=1
        # A one-iteration block allows stage failure to proceed to the shared
        # per-skill result report rather than bypassing it with `continue`.
        while :; do
            stage='model/runtime preparation'
            echo '    [1/6] Checking model-specific runtime or specialist CLI...'
            if [[ "$root" == "$DESERTANT_SKILL_DIR"/* ]]; then
                specialist="${root##*/zarzysseus-low-spec-}"
                if ! desertant_ensure_cli || ! cli="$(desertant_bin)" || ! "$cli" info "$specialist"; then
                    note="Desert Ant CLI/model unavailable: $specialist"; break
                fi
            elif [[ "$root" == "$LPS_SKILLS_DIR"/* && -f "$root/model.json" ]]; then
                if ! repo="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("repo",""))' "$root/model.json")" || ! lps_install_model "$repo"; then
                    note="L.P.S. model/runtime repair failed: ${repo:-unknown}"; break
                fi
            elif [[ -f "$root/model.json" && "$root" == "$AUTO_FIT_SKILL_DIR"/* ]]; then
                kind="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("kind",""))' "$root/model.json")" || { note='Invalid auto-fit model kind'; break; }
                repo="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("repo",""))' "$root/model.json")" || { note='Invalid auto-fit model repository'; break; }
                case "$kind" in
                    audio) auto_fit_audio_dependencies || { note='Audio dependencies incomplete'; break; } ;;
                    image|video)
                        auto_fit_prepare_dependencies "$kind" && auto_fit_prepare_model_dependencies "$kind" "$repo" || { note="$kind model dependencies incomplete"; break; }
                        ;;
                    text) echo '    [SKIP] Existing text model preserved; no unrelated pull.' ;;
                esac
            else
                echo '    [SKIP] No special model runtime to prepare.'
            fi
            stage='system/package prerequisites'
            echo '    [2/6] Checking OS packages, Python requirements and Node dependencies...'
            if ! skills_install_declared_system_packages "$root" || ! skills_install_skill_manifests "$root"; then
                note='A declared or discoverable package prerequisite could not be installed'; break
            fi
            stage='provider authorization'
            echo '    [3/6] Checking provider CLI availability and authorization...'
            if ! skills_auth_prerequisites "$root"; then
                outcome='AUTH'; note='Provider login or provider CLI still needs attention'; break
            fi
            stage='browser runtime'
            echo '    [4/6] Checking/installing browser runtime when required...'
            if ! skills_install_browser_prerequisites "$root"; then
                note='Browser runtime/dependencies remain incomplete'; break
            fi
            stage='model runtime verification'
            echo '    [5/6] Checking generated model runner when available...'
            if [[ -f "$root/run.py" && "$root" == "$AUTO_FIT_SKILL_DIR"/* ]]; then
                if [[ -x "$VENV_PY" ]]; then
                    if ! dependency_repair_python_command "$VENV_PY" "$root/run.py" --check; then
                        note='Model runner --check failed'; break
                    fi
                else
                    note='Zarzysseus runtime Python missing'; break
                fi
            else
                echo '    [SKIP] No generated model runner to check.'
            fi
            stage='skill registration and health check'
            echo '    [6/6] Syncing skill and rechecking its current health...'
            if [[ "$root" == "$ODYSSEUS_DATA_DIR/skills/imported/"* ]]; then
                echo '    [SKIP] Already present in imported skills; no duplicate sync.'
            elif [[ -d "$PROJECT_DIR" && -x "$VENV_PY" ]]; then
                if SKILLS_SYNC_DEFER_RESTART=1 skills_sync_installed_skill_to_odysseus "$root" ''; then
                    synced=1
                else
                    note='Skill registration failed'; break
                fi
            else
                echo '    [NOTE] Core not installed; dependencies repaired but skill not synced.'
            fi
            snapshot_path="$(mktemp)" || { note='Cannot create health-check scratch file'; break; }
            if ! skills_health_snapshot "$root" >"$snapshot_path"; then
                note='Health recheck failed'; rm -f -- "$snapshot_path"; break
            fi
            health_row="$(awk -F '\t' -v p="$root" '$1 == p {print $3 "\t" $4}' "$snapshot_path")"
            rm -f -- "$snapshot_path"
            if [[ -z "$health_row" ]]; then
                note='Skill missing from health recheck'; break
            fi
            health_state="${health_row%%$'\t'*}"
            health_detail="${health_row#*$'\t'}"
            printf '    [AFTER] %s — %s\n' "$health_state" "$health_detail"
            case "$health_state" in
                CHECKED) outcome='CHECKED'; note='Declared/discoverable prerequisites passed.' ;;
                PROMPT) outcome='PROMPT'; note='Instruction-only skill checked; no package prerequisites to install.' ;;
                UNDECLARED) outcome='UNDECLARED'; note='Runtime requirements not fully declared; no unverified packages installed.' ;;
                AUTH) outcome='AUTH'; note='Provider authorization still required.' ;;
                REVIEW) outcome='REVIEW'; note='Warnings need review; see health details.' ;;
                *) outcome='FAILED'; note='Prerequisites remain missing or unverified.' ;;
            esac
            break
        done
        elapsed=$(( $(date +%s) - skill_start ))
        printf '    [RESULT] %s | %s | %ds | stage: %s\n' "$outcome" "$note" "$elapsed" "$stage"
        case "$outcome" in
            CHECKED) ((passed+=1)); passed_names+=("$name") ;;
            PROMPT) ((prompt_only+=1)); prompt_names+=("$name") ;;
            UNDECLARED) ((unverified+=1)); unverified_names+=("$name"); rc=1 ;;
            AUTH) ((needs_auth+=1)); auth_names+=("$name") ; rc=1 ;;
            REVIEW) ((review+=1)); review_names+=("$name") ; rc=1 ;;
            *) ((failed+=1)); failed_names+=("$name: $note") ; rc=1 ;;
        esac
    done
    echo
    echo '[FINALIZE] Checking application configuration and applying one deferred restart, if needed...'
    if ((synced)); then
        skills_repair_audit_runtime || true
        if service_installed 2>/dev/null && [[ "${SERVICE_MANAGER:-unknown}" == systemd ]]; then
            if service_systemctl restart "$service_unit"; then
                echo '[READY] Zarzysseus restarted once after skill synchronization.'
            else
                echo '[FAILED] Zarzysseus restart failed; check the user service logs.'
                rc=1
            fi
        fi
    else
        echo '[SKIP] No new skill sync; no service restart necessary.'
    fi
    printf '\n%s\n' '================================================================'
    echo '                       SKILL REPAIR SUMMARY'
    printf '%s\n' '================================================================'
    printf 'Selected: %-4d | Checked: %-4d | Prompt-only: %-4d | Undeclared: %-4d | Auth: %-4d | Review: %-4d | Failed: %d\n' \
        "$total" "$passed" "$prompt_only" "$unverified" "$needs_auth" "$review" "$failed"
    printf 'Elapsed: %ds\n' "$(( $(date +%s) - start_time ))"
    if ((${#auth_names[@]})); then
        echo '[AUTH REQUIRED] Complete official sign-in, then rerun Fix All:'
        printf '    - %s\n' "${auth_names[@]}"
    fi
    if ((${#review_names[@]})); then
        echo '[REVIEW] Installed prerequisites have outstanding warnings:'
        printf '    - %s\n' "${review_names[@]}"
    fi
    if ((${#failed_names[@]})); then
        echo '[FAILED] Items still needing repair:'
        printf '    - %s\n' "${failed_names[@]}"
    fi
    if ((${#prompt_names[@]})); then
        echo '[PROMPT-ONLY] SKILL.md and structure checked; no installable runtime dependency detected:'
        printf '    - %s\n' "${prompt_names[@]}"
    fi
    if ((${#unverified_names[@]})); then
        echo '[UNDECLARED] Executable/runtime prerequisites need a manifest or explicit check:'
        printf '    - %s\n' "${unverified_names[@]}"
    fi
    ((rc==0)) && echo '[COMPLETE] Detectable prerequisites passed; PROMPT does not establish end-to-end behavior.' || \
        echo '[INCOMPLETE] Inspect remaining AUTH/REVIEW/UNDECLARED/FAILED items; do not assume readiness.'
    return "$rc"
}

skills_repair_all_roots() {
    # Reuse the same per-skill engine; one repair job, one final summary.
    local -a all_roots=()
    mapfile -t all_roots < <(skills_health_roots)
    if ((${#all_roots[@]} == 0)); then
        echo 'No installed skills were found to repair.'
        return 0
    fi
    printf '==> Fix All Skills: %d installed skill(s) queued.\n' "${#all_roots[@]}"
    skills_repair_selected_roots "${all_roots[@]}"
}

tui_skills_dependency_fixer() {
    # A health probe is read-only and may fail independently of the menu. Never
    # let a failed poll escape to the top-level set -e/pipefail TUI dispatcher.
    local selected=0 offset=0 i row visible cols lines header header_lines
    local root name status detail key extra now last_scan=0 focus='' frame line
    local panel_width panel_left row_col error_text='' redraw=1 drawn=0 wipe_row
    local last_cols=0 last_lines=0 scan_ok=0 force_focus=0
    local -a paths=() names=() states=() details=() header_rows=()
    local -A marked=()
    local -a checked_paths=()
    local snapshot_file scan_error_file
    snapshot_file="$(mktemp)" || return 1
    scan_error_file="$(mktemp)" || { rm -f -- "$snapshot_file"; return 1; }
    _tui_begin
    while true; do
        _tui_size
        cols=$TUI_COLS; lines=$TUI_LINES
        if (( cols != last_cols || lines != last_lines )); then
            last_cols=$cols; last_lines=$lines; redraw=1; drawn=0
        fi
        now="$(date +%s)"
        if (( last_scan == 0 || now - last_scan >= 5 )); then
            focus=''
            if (( force_focus )) && ((${#paths[@]})); then focus="${paths[$selected]}"; fi
            force_focus=0
            # Store probe stderr and retain old rows when a transient probe
            # fails. Scan failures are HEALTH issues, never fatal TUI errors.
            if skills_health_snapshot "$focus" >"$snapshot_file" 2>"$scan_error_file"; then
                paths=(); names=(); states=(); details=()
                while IFS=$'\t' read -r root name status detail; do
                    [[ -n "$root" ]] || continue
                    paths+=("$root"); names+=("$name"); states+=("$status"); details+=("$detail")
                done < "$snapshot_file"
                (( selected >= ${#paths[@]} )) && selected=$(( ${#paths[@]} - 1 ))
                (( selected < 0 )) && selected=0
                error_text=''; scan_ok=1
            else
                error_text="$(head -n 1 "$scan_error_file" 2>/dev/null || true)"
                [[ -n "$error_text" ]] || error_text='Health scan failed; press R to retry. Old results kept.'
                scan_ok=0
            fi
            last_scan="$now"; redraw=1
        fi
        # Do not rebuild/clear the whole frame on each 0.5s read timeout.
        if (( redraw )); then
            header="$(_tui_draw_header)"
            header_rows=()
            mapfile -t header_rows <<< "$header"
            header_lines=${#header_rows[@]}
            panel_width=$(( cols - 4 ))
            (( panel_width > 82 )) && panel_width=82
            (( panel_width < 8 )) && panel_width=8
            panel_left=$(( (cols - panel_width) / 2 + 1 ))
            visible=$(( lines - header_lines - 7 ))
            (( visible < 0 )) && visible=0
            (( visible > ${#paths[@]} )) && visible=${#paths[@]}
            (( selected < offset )) && offset=$selected
            if (( visible > 0 && selected >= offset + visible )); then
                offset=$(( selected - visible + 1 ))
            fi
            frame=$'\033[?2026h'
            if (( ! drawn )); then
                # Initial render (or a genuine terminal resize) needs a clear.
                frame+=$'\033[H\033[2J'
            else
                # Recurring health polls refresh only the content below the
                # static logo: never flash the entire alternate screen.
                for ((wipe_row=header_lines+1; wipe_row<=lines; wipe_row++)); do
                    frame+="$(printf '\033[%d;1H\033[2K' "$wipe_row")"
                done
            fi
            row=1
            for line in "${header_rows[@]}"; do
                (( row > lines )) && break
                frame+="$(printf '\033[%d;1H%s' "$row" "$line")"
                ((row+=1))
            done
            row=$(( header_lines + 1 ))
            line="$(_tui_fit_one_line 'SKILLS DEPENDENCY FIXER  •  LIVE HEALTH' "$panel_width")"
            row_col=$(( (cols - ${#line}) / 2 + 1 ))
            if (( row <= lines )); then frame+="$(printf '\033[%d;%dH%s' "$row" "$row_col" "$line")"; fi
            ((row+=1))
            line="$(_tui_fit_one_line 'SPACE Mark | F Fix Marked | A Fix All | D Details | R Refresh | Q Back' "$panel_width")"
            row_col=$(( (cols - ${#line}) / 2 + 1 ))
            if (( row <= lines )); then frame+="$(printf '\033[%d;%dH%s' "$row" "$row_col" "$line")"; fi
            ((row+=1))
            if ((${#paths[@]} == 0)); then
                line='No installed skills found.'
                ((scan_ok)) || line='Health scan unavailable (R to retry).'
                line="$(_tui_fit_one_line "$line" "$panel_width")"
                row_col=$(( (cols - ${#line}) / 2 + 1 ))
                if (( row <= lines )); then frame+="$(printf '\033[%d;%dH%s' "$row" "$row_col" "$line")"; fi
            else
                for ((i=offset; i<offset+visible; i++)); do
                    [[ -n "${paths[$i]:-}" ]] || break
                    if [[ -n "${marked[${paths[$i]}]:-}" ]]; then
                        line="[x] ${names[$i]}  [${states[$i]}]"
                    else
                        line="[ ] ${names[$i]}  [${states[$i]}]"
                    fi
                    line="$(_tui_fit_one_line "$line" "$(( panel_width - 2 ))")"
                    if (( i == selected )); then line="> $line"; else line="  $line"; fi
                    if (( row <= lines - 5 )); then
                        frame+="$(printf '\033[%d;%dH%s' "$row" "$panel_left" "$line")"
                    fi
                    ((row+=1))
                done
                row=$((lines-4))
                if (( row > header_lines + 2 )); then
                    line="$(_tui_fit_one_line "Selected: ${names[$selected]} [${states[$selected]}]" "$panel_width")"
                    row_col=$(( (cols - ${#line}) / 2 + 1 ))
                    frame+="$(printf '\033[%d;%dH%s' "$row" "$row_col" "$line")"
                    ((row+=1))
                    line="$(_tui_fit_one_line "${details[$selected]}" "$panel_width")"
                    row_col=$(( (cols - ${#line}) / 2 + 1 ))
                    frame+="$(printf '\033[%d;%dH%s' "$row" "$row_col" "$line")"
                fi
            fi
            row=$((lines-2)); (( row < 1 )) && row=1
            if [[ -n "$error_text" ]]; then
                line="Scan error: $error_text"
            else
                line="${#paths[@]} installed • health refreshed every 5s • F marked / A all"
            fi
            line="$(_tui_fit_one_line "$line" "$panel_width")"
            row_col=$(( (cols - ${#line}) / 2 + 1 ))
            frame+="$(printf '\033[%d;%dH%s' "$row" "$row_col" "$line")"
            frame+=$'\033[?2026l'
            printf '%s' "$frame"
            redraw=0; drawn=1
        fi
        key=''
        if ! _tui_read_key_timeout key 0.5; then continue; fi
        case "$key" in
            $'\e')
                extra=''
                IFS= read -rsN 2 -t 0.08 extra < /dev/tty || true
                case "$extra" in
                    '[A') if ((selected>0)); then selected=$((selected-1)); redraw=1; fi ;;
                    '[B') if ((selected+1<${#paths[@]})); then selected=$((selected+1)); redraw=1; fi ;;
                esac ;;
            j|J) if ((selected+1<${#paths[@]})); then selected=$((selected+1)); redraw=1; fi ;;
            k|K) if ((selected>0)); then selected=$((selected-1)); redraw=1; fi ;;
            ' '|$'\r'|$'\n')
                if ((${#paths[@]})); then
                    root="${paths[$selected]}"
                    if [[ -n "${marked[$root]:-}" ]]; then unset 'marked[$root]'; else marked["$root"]=1; fi
                    redraw=1
                fi ;;
            r|R) last_scan=0; force_focus=1; redraw=1 ;;
            d|D)
                if ((${#paths[@]})); then
                    _tui_end
                    printf '\nSkill: %s\nPath: %s\n\n' "${names[$selected]}" "${paths[$selected]}"
                    # The read-only detail scan can fail too; contain pipefail.
                    if ! skills_health_snapshot "${paths[$selected]}" 2>"$scan_error_file" | \
                            awk -F '\t' -v p="${paths[$selected]}" '$1 == p {print "Health: " $3 "\nDetails: " $4}'; then
                        printf 'Health probe failed: %s\n' "$(head -n 1 "$scan_error_file" || true)"
                    fi
                    printf '\nCHECKED = prerequisites found; PROMPT = instruction-only structure checked. Neither proves behavior.\n'
                    _tui_pause
                    _tui_begin
                    drawn=0; last_scan=0; redraw=1; drawn=0
                fi ;;
            a|A)
                if ((${#paths[@]})); then
                    _tui_end
                    printf '\nFix dependencies for ALL %d installed skill(s)? [y/N] ' "${#paths[@]}"
                    _tui_cursor_show
                    extra=''
                    IFS= read -r extra < /dev/tty || extra=''
                    _tui_cursor_hide
                    if [[ "${extra,,}" == y || "${extra,,}" == yes ]]; then
                        printf '\nRepairing every installed skill; no system-wide upgrade.\n'
                        if ODYSSEUS_TUI_CHILD=1 bash "$SCRIPT_PATH" skills-repair-all; then
                            printf '\nAll installed skills passed the declared prerequisite checks.\n'
                        else
                            printf '\nSome skills still need review; inspect their individual health details.\n'
                        fi
                        _tui_pause
                        marked=()
                    fi
                    _tui_begin
                    drawn=0; last_scan=0; redraw=1; drawn=0
                fi ;;
            f|F)
                checked_paths=()
                for root in "${paths[@]}"; do
                    [[ -n "${marked[$root]:-}" ]] && checked_paths+=("$root")
                done
                if ((${#checked_paths[@]})); then
                    _tui_end
                    printf '\nRepairing %d checked skill(s); no system-wide upgrade.\n' "${#checked_paths[@]}"
                    ODYSSEUS_TUI_CHILD=1 bash "$SCRIPT_PATH" skills-repair-selected "${checked_paths[@]}" || true
                    _tui_pause
                    _tui_begin
                    marked=(); last_scan=0; redraw=1; drawn=0
                fi ;;
            q|Q) rm -f -- "$snapshot_file" "$scan_error_file"; return 0 ;;
        esac
    done
}

tui_skills_manage_menu() {
    local choice skill_input tools_input
    while true; do
        if _tui_menu 'MANAGE INSTALLED SKILLS' \
            'LIST INSTALLED SKILLS' \
            'SKILL DETAILS / SUMMARY' \
            'SYNC INSTALLED SKILLS INTO ZARZYSSEUS' \
            'UPDATE ALL INSTALLED SKILLS' \
            'UPDATE ONE INSTALLED SKILL' \
            'REMOVE / UNINSTALL ONE SKILL' \
            'VIEW SKILL PERMISSIONS' \
            'SET ALLOWED-TOOLS PERMISSIONS' \
            'RESET ALLOWED-TOOLS PERMISSIONS' \
            'BACK'; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) _tui_run_command 'Installed agent skills' skills-manage-list ;;
                1)
                    _tui_prompt 'INSTALLED SKILL NAME'
                    skill_input="$TUI_INPUT"
                    [[ -n "$skill_input" ]] && _tui_run_command "Skill details: $skill_input" skills-summary-installed "$skill_input"
                    ;;
                2) _tui_run_command 'Syncing installed skills into Zarzysseus' skills-sync-all ;;
                3) _tui_run_command 'Updating all installed agent skills' skills-update ;;
                4)
                    _tui_prompt 'INSTALLED SKILL NAME'
                    skill_input="$TUI_INPUT"
                    [[ -n "$skill_input" ]] && _tui_run_command "Updating skill: $skill_input" skills-update-one "$skill_input"
                    ;;
                5)
                    _tui_prompt 'INSTALLED SKILL NAME TO REMOVE'
                    skill_input="$TUI_INPUT"
                    [[ -n "$skill_input" ]] && _tui_run_command "Removing skill: $skill_input" skills-remove "$skill_input"
                    ;;
                6)
                    _tui_prompt 'INSTALLED SKILL NAME'
                    skill_input="$TUI_INPUT"
                    [[ -n "$skill_input" ]] && _tui_run_command "Skill permissions: $skill_input" skills-permissions "$skill_input"
                    ;;
                7)
                    _tui_prompt 'INSTALLED SKILL NAME'
                    skill_input="$TUI_INPUT"
                    [[ -z "$skill_input" ]] && continue
                    _tui_prompt 'ALLOWED TOOLS (space-separated)'
                    tools_input="$TUI_INPUT"
                    _tui_run_command "Setting permissions: $skill_input" skills-permissions-set "$skill_input" $tools_input
                    ;;
                8)
                    _tui_prompt 'INSTALLED SKILL NAME'
                    skill_input="$TUI_INPUT"
                    [[ -n "$skill_input" ]] && _tui_run_command "Resetting permissions: $skill_input" skills-permissions-clear "$skill_input"
                    ;;
                9) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

tui_skills_menu() {
    local choice query skill_input
    while true; do
        if _tui_menu 'SKILLS.SH / AGENT SKILLS' \
            'PERSONAL FAVE SKILLS' \
            'SEARCH SKILLS.SH + INSTALL RESULT' \
            'INSTALL BY NAME / LINK / GITHUB REPO' \
            'MANAGE INSTALLED SKILLS' \
            'SKILLS DEPENDENCY FIXER (LIVE HEALTH + F TO FIX)' \
            'FIX ALL SKILLS (REPAIR EVERY INSTALLED SKILL)' \
            'SHOW SKILL SUMMARY' \
            'BACK'; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) tui_personal_fave_skills ;;
                1) tui_skills_market_browser ;;
                2)
                    _tui_prompt 'SKILL NAME / SKILLS.SH URL / GITHUB REPO'
                    skill_input="$TUI_INPUT"
                    [[ -n "$skill_input" ]] && _tui_run_command "Installing agent skill: $skill_input" skills-install "$skill_input"
                    ;;
                3) tui_skills_manage_menu ;;
                4) tui_skills_dependency_fixer ;;
                5)
                    _tui_prompt 'Fix dependencies for ALL installed skills? Type YES to confirm'
                    if [[ "${TUI_INPUT^^}" == YES ]]; then
                        _tui_run_command 'Fixing all installed skill dependencies' skills-repair-all
                    fi
                    ;;
                6)
                    _tui_prompt 'SKILL NAME / SKILLS.SH URL / SOURCE ID'
                    skill_input="$TUI_INPUT"
                    [[ -n "$skill_input" ]] && _tui_run_command "Skill summary: $skill_input" skills-summary "$skill_input"
                    ;;
                7) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

tui_diagnostics_menu() {
    local choice
    while true; do
        if _tui_menu 'DIAGNOSTICS / TOOLS / ADVANCED' \
            'LINUX / DISTRO / INSTALLATION DISCOVERY' \
            'RUN SYSTEM UPDATE NOW' \
            'ACCELERATOR STATUS' \
            'ACCELERATOR SETUP / REPAIR' \
            'VLLM STATUS' \
            'SAM MASK STATUS' \
            'SAM MASK INSTALL / REPAIR' \
            'INSTALL TOOLS' \
            'GENERAL ZARZYSSEUS STATUS' \
            'REGISTER OPENAI-COMPATIBLE ENDPOINT' \
            'SHOW LOCAL MODEL PROVIDERS' \
            'SET DEFAULT PROVIDER + MODEL' \
            'SHOW FULL COMMAND HELP' \
            'BACK'; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) _tui_run_command 'Linux / installation discovery' linux-status ;;
                1) _tui_run_command 'Updating operating system' system-update ;;
                2) _tui_run_command 'Accelerator status' accelerator-status ;;
                3) _tui_run_command 'Accelerator setup / repair' accelerator-setup ;;
                4) _tui_run_command 'vLLM status' vllm-status ;;
                5) _tui_run_command 'SAM mask status' sam-mask-status ;;
                6) _tui_run_command 'SAM mask install / repair' sam-mask-install ;;
                7) _tui_run_command 'Installing tools' tools ;;
                8) _tui_run_command 'Zarzysseus status' status ;;
                9) tui_endpoint_menu ;;
                10) _tui_run_command 'Local model providers' providers ;;
                11) tui_model_default ;;
                12) tui_help_screen ;;
                13) return 0 ;;
            esac
        else
            return 0
        fi
    done
}

tui_endpoint_menu() {
    local endpoint_id name base_url model tools
    _tui_prompt 'Endpoint ID'
    endpoint_id="$TUI_INPUT"
    [[ -n "$endpoint_id" ]] || return 0
    _tui_prompt 'Endpoint name'
    name="$TUI_INPUT"
    [[ -n "$name" ]] || return 0
    _tui_prompt 'Base URL (for example http://127.0.0.1:8000/v1)'
    base_url="$TUI_INPUT"
    [[ -n "$base_url" ]] || return 0
    _tui_prompt 'Preferred model (optional)'
    model="$TUI_INPUT"
    _tui_prompt 'Native tool calling? (1=yes, 0=no)' '1'
    tools="$TUI_INPUT"
    [[ -z "$model" ]] && model=""
    _tui_run_command "Registering endpoint: $endpoint_id" endpoint-add "$endpoint_id" "$name" "$base_url" "$model" "$tools"
}

tui_help_screen() {
    _tui_end
    _tui_size
    _tui_clear
    _tui_draw_header
    printf '\n'
    if ! ODYSSEUS_TUI_CHILD=1 bash "$SCRIPT_PATH" help 2>/dev/null; then
        _tui_print_center 'Unable to display help.'
    fi
    _tui_pause
    _tui_begin
}

odysseus_tui() {
    local choice
    trap '_tui_cleanup; exit 130' INT TERM
    _tui_begin
    while true; do
        if _tui_menu 'ZARZYSSEUS MAIN MENU' \
            'INSTALL / UPDATE' \
            'SERVICE MANAGEMENT' \
            'MODEL RUNTIMES' \
            'MODEL MANAGER / HARDWARE FIT' \
            'OLLAMA MANAGEMENT' \
            'MLX-LM MANAGEMENT' \
            'HUGGING FACE / MODEL FILES' \
            'SKILLS.SH / AGENT SKILLS' \
            'DIAGNOSTICS / TOOLS / ADVANCED' \
            'EXIT'; then
            choice="$TUI_CHOICE"
            case "$choice" in
                0) tui_install_menu ;;
                1) tui_service_menu ;;
                2) tui_runtime_menu ;;
                3) tui_model_manager_menu ;;
                4) tui_ollama_menu ;;
                5) tui_mlx_menu ;;
                6) tui_hf_menu ;;
                7) tui_skills_menu ;;
                8) tui_diagnostics_menu ;;
                9) break ;;
            esac
        else
            break
        fi
    done
    _tui_cleanup
    trap - INT TERM
    printf '\n'
    echo 'Zarzysseus TUI closed.'
}

# ------------------------------------------
# Command dispatcher
# ------------------------------------------

# Start-up repo check happens before entering the alternate-screen TUI, so
# fetch/progress messages never flicker inside the interactive interface.
# Child commands and the other noninteractive actions keep their own behavior.
if [[ "$ACTION" == "tui" && "$TUI_CHILD" != "1" ]]; then
    refresh_existing_odysseus_checkout
fi

# Do not run a system update for an invalid or empty direct manual batch.
MANUAL_BATCH_UPDATE_REQUIRED=0
if [[ "$ACTION" == install-manual-batch ]]; then
    [[ "${2:-}" == --full-stack || "${2:-}" == --models-only ]] || { echo 'Usage: install-manual-batch <--full-stack|--models-only> <selection...>'; exit 2; }
    (( $# >= 3 )) || { echo 'ERROR: A manual batch needs a confirmed model.'; exit 2; }
    for record in "${@:3}"; do
        IFS='|' read -r family kind task repo include <<< "$record"
        case "$family" in normal|lps|desert) ;; *) echo "ERROR: Invalid model family: $family"; exit 2 ;; esac
        [[ -n "$repo" && -n "$kind" ]] || { echo 'ERROR: Model selection lacks an ID or modality.'; exit 2; }
        if [[ "${2:-}" == --full-stack && "$family" == normal ]]; then
            MANUAL_BATCH_UPDATE_REQUIRED=1
        fi
    done
fi

# Only Zarzysseus install/update flows automatically run the OS-aware system
# updater. All other actions (models, skills, services, diagnostics, runtimes,
# accelerator repair, etc.) skip system upgrades. `system-update` is still an
# explicit manual command when the user chooses it.
bootstrap_system_update_for_action

# Normalize cwd for every action when the repository already exists. This is
# what makes `bash /path/to/zarzysseus.sh ...` behave the same whether
# launched from Downloads, $HOME, /tmp, or from inside the repo itself.
prepare_project_runtime_context

case "$ACTION" in
    tui)
        odysseus_tui
        ;;
    repo-update)
        if repo_installed; then
            refresh_existing_odysseus_checkout
        else
            echo "ERROR: No checkout found. Open Install / Update Stack or set PROJECT_DIR."
            exit 1
        fi
        ;;
    accelerator-status)
        accelerator_status
        ;;
    accelerator-setup)
        application_installed || install_odysseus
        cd "$PROJECT_DIR"
        source "$VENV_DIR/bin/activate"
        ensure_accelerator_stack
        ensure_pytorch_backend
        accelerator_status
        ;;
    providers|model-providers)
        model_manager_providers
        ;;
    model-list|models)
        model_manager_rank "${2:-$MODEL_MANAGER_USE_CASE}" "${3:-$MODEL_MANAGER_DEFAULT_LIMIT}" "${4:-}" "${5:-$MODEL_MANAGER_SORT}" "${6:-0}"
        ;;
    model-list-json)
        model_manager_rank_json "${2:-$MODEL_MANAGER_USE_CASE}" "${3:-$MODEL_MANAGER_DEFAULT_LIMIT}" "${4:-}" "${5:-$MODEL_MANAGER_SORT}" "${6:-0}"
        ;;
    model-pick|model-auto|auto-model)
        model_manager_auto_pick "${2:-$MODEL_MANAGER_USE_CASE}" "${3:-$MODEL_MANAGER_DEFAULT_LIMIT}" "${4:-}"
        ;;
    model-pick-interactive)
        model_manager_pick "${2:-$MODEL_MANAGER_USE_CASE}" "${3:-15}" "${4:-}"
        ;;
    install-manual-batch)
        manual_model_install_batch "${@:2}"
        ;;
    model-install)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 model-install <org/model> [include-glob]"; exit 2; }
        hf_pull_model "$MODEL_ARG" "${3:-}"
        ;;
    model-pull-batch)
        shift
        [[ $# -gt 0 ]] || { echo "Usage: $0 model-pull-batch <model> [model ...]"; exit 2; }
        pull_models_auto_batch "$@"
        ;;
    endpoint-add)
        [[ -n "$MODEL_ARG" && -n "${3:-}" && -n "${4:-}" ]] || { echo "Usage: $0 endpoint-add <id> <name> <base_url> [model] [tools]"; exit 2; }
        register_openai_compatible_endpoint "$MODEL_ARG" "$3" "$4" "${6:-1}" "${5:-}"
        ;;
    skills-search)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 skills-search <query>"; exit 2; }
        skills_search "$MODEL_ARG"
        ;;
    skills-search-install)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 skills-search-install <query>"; exit 2; }
        skills_search_install "$MODEL_ARG"
        ;;
    skills-repair-deps)
        skills_auto_resolve_all_installed_dependencies
        ;;
    skills-health)
        skills_health_snapshot "${2:-}"
        ;;
    skills-repair-selected)
        shift
        skills_repair_selected_roots "$@"
        ;;
    skills-repair-all)
        skills_repair_all_roots
        ;;
    skills-install|skill-install)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 skills-install <skill-name|skills.sh URL|GitHub repo|skill URL>"; exit 2; }
        skills_install "$MODEL_ARG"
        ;;
    skills-sync-all)
        skills_sync_all_installed_to_odysseus
        ;;
    skills-summary|skill-summary)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 skills-summary <skill-name|skills.sh URL|source/slug>"; exit 2; }
        skills_summary "$MODEL_ARG"
        ;;
    skills-list)
        skills_list
        ;;
    skills-update)
        skills_update
        ;;
    skills-manage-list)
        skills_manage_list
        ;;
    skills-summary-installed)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 skills-summary-installed <skill-name>"; exit 2; }
        skills_manage_summary_installed "$MODEL_ARG"
        ;;
    skills-update-one)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 skills-update-one <skill-name>"; exit 2; }
        skills_manage_update_one "$MODEL_ARG"
        ;;
    skills-remove)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 skills-remove <skill-name>"; exit 2; }
        skills_manage_remove "$MODEL_ARG"
        ;;
    skills-permissions)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 skills-permissions <skill-name>"; exit 2; }
        skills_permission_show "$MODEL_ARG"
        ;;
    skills-permissions-set)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 skills-permissions-set <skill-name> <tool...>"; exit 2; }
        skills_permission_set "$MODEL_ARG" "${@:3}"
        ;;
    skills-permissions-clear)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 skills-permissions-clear <skill-name>"; exit 2; }
        skills_permission_clear "$MODEL_ARG"
        ;;
    auth)
        zarzysseus_auth "${2:-}"
        ;;
    install-personal-skills)
        personal_fave_skills_install "${2:-all-local}"
        ;;
    install-lps)
        lps_install_profile "${2:-text-video-photo-audio}"
        ;;
    install-lps-manual)
        [[ -n "${2:-}" ]] || { echo "Usage: $0 install-lps-manual <curated org/model>"; exit 2; }
        AUTO_FIT_SKILLS_SYNCED=0
        lps_install_model "$2" && auto_fit_finalize_skills
        ;;
    lps-list)
        lps_catalog_rows
        ;;
    install-low-spec)
        desertant_auto_fit "${2:-text-video-audio}"
        ;;
    install-low-spec-manual)
        desertant_install_selected "${2:-}"
        auto_fit_finalize_skills
        ;;
    install-desert-sdk)
        desertant_install_core_sdk
        ;;
    low-spec-status)
        desertant_ensure_cli && "$(desertant_bin)" models --all
        ;;
    low-spec-unsupported)
        echo 'Desert Ant Labs does not document a Linux photo-generation CLI; no model was installed.'
        ;;
    model-list-audio-json)
        model_manager_audio_json "${2:-80}" "${3:-}"
        ;;
    model-install-audio)
        [[ -n "${2:-}" && -n "${3:-}" ]] || { echo 'Usage: model-install-audio <repo> <automatic-speech-recognition|text-to-speech>'; exit 2; }
        case "$3" in automatic-speech-recognition|text-to-speech) ;; *) echo 'ERROR: Selected audio pipeline is not yet supported for automatic inference.'; exit 2 ;; esac
        model_manager_ensure || exit 1
        auto_fit_audio_dependencies || exit 1
        hf_pull_model "$2" || exit 1
        AUDIO_SELECTION_JSON="$("$VENV_PY" - "$2" "$3" <<'PY_MANUAL_AUDIO_METADATA'
import json,sys
print(json.dumps({'repo':sys.argv[1],'pipeline_tag':sys.argv[2],'model_type':'audio','fit_level':'manual'}))
PY_MANUAL_AUDIO_METADATA
)"
        audio_create_skill "$AUDIO_SELECTION_JSON" || exit 1
        auto_fit_finalize_skills
        ;;
    install)
        install_odysseus
        ;;
    install-full)
        # "Full" now means the complete automatic profile requested by the TUI:
        # fitted text + video + photo + audio models in one selected profile.
        full_install_auto_fit_profile text-video-photo-audio
        ;;
    install-auto-fit)
        full_install_auto_fit_profile "${2:-text-video-photo-audio}"
        ;;
    install-personal-faves)
        shift
        [[ $# -gt 0 ]] || { echo "ERROR: No Personal Fave text models were selected."; exit 2; }
        install_odysseus || exit $?
        pull_models_auto_batch "$@"
        ;;
    linux-status)
        linux_status
        ;;
    system-update)
        # The dispatcher preflight already ran this action. Calling it again is
        # intentionally harmless and makes direct function reuse predictable.
        system_update_once
        ;;
    model-default|default-model)
        provider="${2:-$DEFAULT_MODEL_PROVIDER}"
        model="${3:-$DEFAULT_MODEL_ID}"
        configure_engine_default_model "$provider" "$model"
        show_link
        ;;
    opull)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 opull <ollama-model[:tag]>"; exit 2; }
        if ! ollama_binary_installed || ! ollama_service_installed || ! application_installed; then
            info "Ollama/Zarzysseus is not fully installed; installing first..."
            install_odysseus
        else
            ollama_start
        fi
        echo "==> Pulling Ollama model: $MODEL_ARG"
        ollama pull "$MODEL_ARG"
        sync_ollama_with_odysseus "$MODEL_ARG"
        configure_engine_default_model ollama "$MODEL_ARG"
        show_link
        ;;
    vpull)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 vpull <org/model> [include-glob]"; exit 2; }
        pull_vllm_model "$MODEL_ARG" "${3:-}"
        show_link
        ;;
    spull)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 spull <org/model> [include-glob]"; exit 2; }
        pull_sglang_model "$MODEL_ARG" "${3:-}"
        show_link
        ;;
    mpull)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 mpull <org/model> [include-glob]"; exit 2; }
        pull_mlx_model "$MODEL_ARG" "${3:-}"
        show_link
        ;;
    mlx-install)
        application_installed || install_odysseus
        cd "$PROJECT_DIR"
        source "$VENV_DIR/bin/activate"
        install_mlx_lm
        ;;
    mlx-status)
        mlx_lm_status
        ;;
    ollama-start|ollama-enable|ollama-restart)
        if ! ollama_binary_installed || ! ollama_service_installed || ! application_installed; then
            info "Ollama/Zarzysseus is not fully installed; installing first..."
            install_odysseus
        fi
        case "$ACTION" in
            ollama-start) ollama_start ;;
            ollama-enable) ollama_enable ;;
            ollama-restart) ollama_restart ;;
        esac
        if ollama_api_ready && application_installed; then sync_ollama_with_odysseus; fi
        show_link
        ;;
    sam-mask|sam-mask-install)
        application_installed || install_odysseus
        cd "$PROJECT_DIR"
        source "$VENV_DIR/bin/activate"
        install_sam_mask_tool
        if service_installed && service_systemctl is-active --quiet "$service_unit" 2>/dev/null; then
            service_systemctl restart "$service_unit"
            echo "    [restarted] Zarzysseus service after SAM installation"
        fi
        show_link
        ;;
    vllm-status)
        echo "vLLM status"
        echo "  Environment:      $VLLM_VENV_DIR"
        echo "  HIP runtime:      $(rocm_library_ready && echo READY || echo MISSING)"
        echo "  MIOpen:           $(miopen_runtime_ready && echo READY || echo MISSING)"
        echo "  ROCprofiler SDK:  $(rocprofiler_sdk_runtime_ready && echo READY || echo MISSING)"
        echo "  HIPFFT:           $(hipfft_runtime_ready && echo READY || echo MISSING)"
        echo "  OpenMPI C++ ABI:  $(openmpi4_cxx_ready && echo READY || echo MISSING)"
        if [[ -x "$VLLM_VENV_DIR/bin/python" ]]; then
            verify_engine_runtime "$VLLM_VENV_DIR" "vllm" "vLLM" || true
        else
            echo "  vLLM package:     NOT INSTALLED"
        fi
        ;;
    sam-mask-status)
        application_installed || { echo "ERROR: Zarzysseus is not installed. Run: $0 install"; exit 1; }
        sam_mask_status
        ;;
    hf-token|token)
        case "$MODEL_ARG" in
            status) hf_token_status ;;
            clear) clear_hf_token ;;
            "") set_hf_token ;;
            *) set_hf_token "$MODEL_ARG" ;;
        esac
        ;;
    hf-pull)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 hf-pull <org/model> [include-glob]"; exit 2; }
        hf_pull_model "$MODEL_ARG" "${3:-}"
        ;;
    hf-repair)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 hf-repair <org/model>"; exit 2; }
        application_installed || install_odysseus
        if hf_cache_complete "$MODEL_ARG"; then
            repair_cookbook_download_tasks "$MODEL_ARG"
            echo "Hugging Face cache is complete; Cookbook state repaired for $MODEL_ARG."
        else
            echo "ERROR: Complete cache not found for $MODEL_ARG. Use: $0 hf-pull $MODEL_ARG"
            exit 1
        fi
        show_link
        ;;
    pull)
        [[ -n "$MODEL_ARG" ]] || { echo "Usage: $0 pull <ollama-model:tag>"; exit 2; }
        if ! ollama_binary_installed || ! ollama_service_installed || ! application_installed; then
            info "Ollama/Zarzysseus is not fully installed; installing first..."
            install_odysseus
        else
            ollama_start
        fi
        echo "==> Pulling Ollama model: $MODEL_ARG"
        ollama pull "$MODEL_ARG"
        sync_ollama_with_odysseus "$MODEL_ARG"
        show_link
        ;;
    ollama-pull)
        if [[ -z "$MODEL_ARG" ]]; then
            echo "Usage: $0 ollama-pull <model>"
            exit 2
        fi
        if ! ollama_binary_installed || ! ollama_service_installed || ! application_installed; then
            info "Ollama/Zarzysseus is not fully installed; installing first..."
            install_odysseus
        else
            ollama_start
        fi
        echo "==> Pulling Ollama model: $MODEL_ARG"
        ollama pull "$MODEL_ARG"
        sync_ollama_with_odysseus "$MODEL_ARG"
        if service_installed && service_systemctl is-active --quiet "$service_unit" 2>/dev/null; then
            if [[ -f "$OLLAMA_SYNC_STATE_FILE" ]] && { [[ ! -f "$OLLAMA_SYNC_STATE_FILE.applied" ]] || ! cmp -s "$OLLAMA_SYNC_STATE_FILE" "$OLLAMA_SYNC_STATE_FILE.applied"; }; then
                cp "$OLLAMA_SYNC_STATE_FILE" "$OLLAMA_SYNC_STATE_FILE.applied"
                service_systemctl restart "$service_unit"
                echo "Zarzysseus restarted so '$MODEL_ARG' is immediately available."
            fi
        fi
        show_link
        ;;
    ollama-sync)
        if ! application_installed; then
            info "Zarzysseus is not fully installed; installing before Ollama sync..."
            install_odysseus
        else
            if ! ollama_api_ready; then
                echo "    [note] Ollama API is offline; skipping background model sync."
                echo "           Start it with: $0 ollama-start"
                show_link
                exit 0
            fi
            sync_ollama_with_odysseus
            if [[ -f "$OLLAMA_SYNC_STATE_FILE" ]] && service_systemctl is-active --quiet "$service_unit" 2>/dev/null; then
                # The sync helper updates the state file before returning. The
                # service only needs a restart when the inventory changed; the
                # timer handles the same path for background model downloads.
                if [[ ! -f "$OLLAMA_SYNC_STATE_FILE.applied" ]] || ! cmp -s "$OLLAMA_SYNC_STATE_FILE" "$OLLAMA_SYNC_STATE_FILE.applied"; then
                    cp "$OLLAMA_SYNC_STATE_FILE" "$OLLAMA_SYNC_STATE_FILE.applied"
                    service_systemctl restart "$service_unit"
                    echo "Zarzysseus restarted so the refreshed Ollama model inventory is live."
                fi
            fi
            show_link
        fi
        ;;
    ollama-stop)
        ollama_stop
        show_link
        ;;
    ollama-disable)
        ollama_disable
        show_link
        ;;
    ollama-status)
        if ollama_binary_installed; then
            echo "Ollama: installed ($(command -v ollama))"
        else
            echo "Ollama: not installed"
        fi
        if ollama_service_installed; then
            echo "Ollama startup: installed ($OLLAMA_SERVICE_FILE)"
            echo "Ollama enabled: $(systemctl --user is-enabled "${OLLAMA_SERVICE_NAME}.service" 2>/dev/null || echo no)"
            echo "Ollama state: $(systemctl --user is-active "${OLLAMA_SERVICE_NAME}.service" 2>/dev/null || echo inactive)"
        else
            echo "Ollama startup: not installed"
        fi
        if ollama_api_ready; then
            echo "Ollama API: ONLINE ($OLLAMA_ENDPOINT)"
            if venv_installed && [[ -f "$PROJECT_DIR/data/settings.json" || -f "$PROJECT_DIR/settings.json" ]]; then
                "$VENV_DIR/bin/python" - <<'PY_STATUS' 2>/dev/null || true
from src.settings import load_settings
s = load_settings()
print("Ollama configured endpoint: " + str(s.get("default_endpoint_id") or "not set"))
print("Ollama configured default LLM: " + str(s.get("default_model") or "not set"))
PY_STATUS
            fi
            echo "Ollama models:"
            ollama_model_names | sed 's/^/  - /' || true
        else
            echo "Ollama API: OFFLINE ($OLLAMA_ENDPOINT)"
        fi
        if [[ -f "$OLLAMA_SYNC_TIMER_FILE" ]]; then
            echo "Ollama model sync: $(systemctl --user is-active "${OLLAMA_SYNC_SERVICE_NAME}.timer" 2>/dev/null || echo inactive)"
        else
            echo "Ollama model sync: not installed"
        fi
        show_link
        ;;
    tools)
        if ! application_installed; then
            info "Zarzysseus is not fully installed; installing it before 'tools'..."
            install_odysseus
        else
            cd "$PROJECT_DIR"
            source "$VENV_DIR/bin/activate"
            install_playwright_tool
            install_sam_mask_tool
            install_llm_serve_engines
            echo "Requested Zarzysseus tools and local LLM serving engines are installed."
            show_link
        fi
        ;;
    start|enable|restart)
        # These are convenience actions: when Zarzysseus is missing, install it first.
        if ! installation_complete; then
            info "Zarzysseus is not fully installed; installing it before '$ACTION'..."
            install_odysseus
        fi

        case "$ACTION" in
            start) service_start ;;
            enable) service_enable ;;
            restart) service_restart ;;
        esac
        ;;
    stop)
        service_stop
        ;;
    disable)
        service_disable
        ;;
    status)
        print_status
        ;;
    uninstall)
        uninstall_odysseus
        ;;
    uninstall-service)
        service_uninstall
        ;;
    help|-h|--help)
        cat <<EOF_HELP
Zarzysseus Installer / Service Manager

Run this script from any directory. It automatically uses PROJECT_DIR
(default: ~/odysseus) as the working directory and clones the repo on install.

Usage:
  $0                             Launch the interactive TUI
  $0 tui                         Launch the interactive TUI
  $0 hf-token [token|status|clear]
  $0 hf-pull <org/model> [include]  Reliable Hugging Face cache download + task repair
  $0 hf-repair <org/model>         Repair a completed local HF model in Cookbook state
  $0 token [token|status|clear]    Alias for hf-token
  $0 pull <model:tag>              Alias for ollama-pull
  $0 opull <model:tag>              Short alias: pull with Ollama + make it default
  $0 vpull <org/model> [include]    Short alias: cache HF model for vLLM + make it default
  $0 spull <org/model> [include]    Short alias: cache HF model for SGLang + make it default
  $0 mpull <org/model> [include]    Short alias: cache HF model for MLX-LM + make it default
  $0 mlx-install                    Install/verify MLX-LM in an isolated environment
  $0 mlx-status                     Show MLX/MLX-LM environment and backend status
  $0 model-default [provider] [model]  Set the default local model endpoint/model
  $0 linux-status                   Detect Linux distro, package manager, clones and installer locations
  $0 system-update                  Run the detected OS package manager updater immediately
  $0 repo-update        Fetch and fast-forward the existing Odysseus checkout; no OS upgrade
  $0 install             Clone (if needed), install, enable and start Zarzysseus
  $0 tools               Install Playwright + full SAM mask + vLLM + SGLang dependencies
  $0 install-full        Full install + auto-fit text, video, photo and audio models + dependencies/skills
  $0 install-auto-fit <profile>  Profiles: any combination of text, video, photo, audio (hyphen separated)
  $0 providers           Show local model runtimes + endpoint reachability
  $0 model-list [usecase] [limit] [search] [sort] [fit-only]  Rank models for this hardware
  $0 model-list-json [usecase] [limit] [search] [sort] [fit-only]  Emit ranked model JSON
  $0 model-pick [usecase] [limit] [search]  Automatically choose/download the top hardware-fit HF model
  $0 model-auto [usecase] [limit] [search]  Alias for automatic model selection
  $0 model-pick-interactive [usecase] [limit] [search]  Manual model selection menu
  $0 model-install <org/model> [include-glob]  Download a HF model/quant
  $0 endpoint-add <id> <name> <base_url> [model] [tools]  Register an OpenAI-compatible local runtime
  $0 skills-search <query>  Search the skills.sh registry and show skill summaries
  $0 skills-search-install <query>  Search, choose a result, show its summary, and install it
  $0 skills-install <name|skills.sh URL|GitHub repo|skill URL>  Download/install an agent skill via the official skills CLI
  $0 skills-sync-all        Sync installed skills into Zarzysseus data/skills and refresh the running service
  $0 skills-summary <name|skills.sh URL|source/slug>  Show a skill summary and registry metadata
  $0 install-personal-skills all-local|office|photo-edit|video-edit|scripting|transcription|cloud-photo|cloud-video
  $0 install-low-spec text-video-audio  Desert Ant task-specific tools (not photo/video generation)
  $0 install-lps <profile>          Low Power Spec generative text/photo/video and audio
  $0 install-lps-manual <org/model> Install one curated L.P.S. model, dependencies and skill
  $0 lps-list                       List curated L.P.S. models and estimated hardware fit
  $0 model-list-audio-json 80 [search] Audio catalog, approximate parameters and memory fit
  $0 auth runcomfy|github|huggingface   Authenticate in provider-owned login interface
  $0 skills-repair-deps      Repair dependencies of installed agent skills (no OS upgrade)
  $0 skills-health [root]    Inspect installed skill prerequisites and auth (read-only)
  $0 skills-repair-selected <installed-root>...  Repair only selected installed skills
  $0 skills-repair-all       Repair every installed skill using validated paths (no OS upgrade)
  $0 skills-list             List installed agent skills
  $0 skills-manage-list      List installed global skills with permission metadata
  $0 skills-update           Update installed agent skills
  $0 skills-update-one <name> Update one installed skill and re-check dependencies
  $0 skills-remove <name>    Remove one installed global skill
  $0 skills-summary-installed <name>  Show installed skill details and permissions
  $0 skills-permissions <name>        Show allowed-tools permissions
  $0 skills-permissions-set <name> <tool...>  Set allowed-tools (space-separated)
  $0 skills-permissions-clear <name>  Reset allowed-tools to agent defaults
  $0 accelerator-status   Detect GPU/OS and report ROCm/CUDA readiness
  $0 accelerator-setup   Install/verify ROCm, CUDA, Intel XPU, or CPU torch stack
  $0 sam-mask-install     Install/verify SAM mask + checkpoint
  $0 sam-mask-status      Show independent SAM mask verification status
  $0 vllm-status          Show vLLM ROCm dependency/library status
  $0 ollama-start        Start Ollama; install first if needed
  $0 ollama-stop         Stop Ollama
  $0 ollama-restart      Restart Ollama; install first if needed
  $0 ollama-status       Show Ollama service/API status and configured LLM
  $0 ollama-enable       Enable Ollama automatic startup and start
  $0 ollama-disable      Disable Ollama automatic startup and stop
  $0 ollama-sync         Reconcile all Ollama models into Zarzysseus immediately
  $0 ollama-pull <model> Pull a model with Ollama, make it the default LLM, then register it
  $0 opull <model> Pull with Ollama (short alias)
  $0 vpull <org/model> [include-glob] Download/cache a Hugging Face model for vLLM and make it default
  $0 spull <org/model> [include-glob] Download/cache a Hugging Face model for SGLang and make it default
  $0 mpull <org/model> [include-glob] Download/cache a Hugging Face model for MLX-LM, start its OpenAI-compatible server, and make it default
  $0 start               Start Zarzysseus; install first if needed
  $0 stop                Stop Zarzysseus
  $0 restart             Restart Zarzysseus; install first if needed
  $0 status              Show whether Zarzysseus/service are installed and running
  $0 enable              Enable automatic startup and start; install first if needed
  $0 disable             Disable automatic startup and stop
  $0 uninstall           Remove Zarzysseus project + Zarzysseus-related user services
  $0 uninstall-service   Remove the automatic startup service only
  $0 help                Show this help

Environment overrides:
  PYTHON_VERSION
  PROJECT_DIR                              Zarzysseus checkout (auto-discovered; default fallback: ~/odysseus)
  ZARZYSSEUS_AUTO_DISCOVER (default: 1)      Auto-detect existing clones/services/script locations
  ZARZYSSEUS_DISCOVERY_MAXDEPTH (default: 5) Home-directory search depth for old/renamed clones
  ZARZYSSEUS_GIT_FETCH_TIMEOUT (default: 60) Seconds before a stalled upstream fetch times out
  SYSTEM_AUTO_UPDATE (default: 1)          Update the OS before mutating install actions
  SYSTEM_UPDATE_TTL (default: 21600)       Cache window for install/update-triggered system upgrades
  SYSTEM_UPDATE_FORCE (default: 0)         Force an update even when the TTL stamp is fresh
  SYSTEM_UPDATE_STRICT (default: 1)        Stop before project changes if the OS update fails
  MANAGED_SCRIPT_PATH                       Stable installer copy (default: PROJECT_DIR/zarzysseus.sh)
  VENV_DIR
  ZARZYSSEUS_HOST
  ZARZYSSEUS_PORT
  SAM_MODEL_TYPE (vit_b, vit_l, vit_h)
  SAM_MODEL_DIR
  PLAYWRIGHT_CACHE_DIR
  OLLAMA_SERVICE_NAME
  OLLAMA_DEFAULT_MODEL (default: llama3.1:8b)
  DEFAULT_MODEL_ID (default: dphn/Dolphin-Mistral-24B-Venice-Edition)
  DEFAULT_MODEL_PROVIDER (default: vllm; supports vllm, sglang, ollama, mlx_lm)
  DEFAULT_MODEL_CONTEXT_LENGTH (default: 4096; ROCm vLLM 0.29 Mistral limitation)
  OLLAMA_PULL_DEFAULT_MODEL (default: 1)
  OLLAMA_MAX_LOADED_MODELS (default: 1)
  OLLAMA_CONTEXT_LENGTH (default: 32768)
  OLLAMA_SUPPORTS_TOOLS (default: 1; native tool calling for Qwen/tool-capable Ollama models)
  INSTALL_VLLM (default: 1)              Install vLLM during setup
  INSTALL_SGLANG (default: 1)            Install SGLang during setup
  INSTALL_MLX_LM (default: 1)            Install MLX-LM during setup
  PATCH_COOKBOOK_SAM_MASK_RECIPE (default: 1) Patch Cookbook sam_mask recipe to full deps
  ACCELERATOR_PREFERENCE (default: auto)  auto|amd|nvidia|intel|cpu
  NVIDIA_DRIVER_PACKAGE (default: auto)  override only with a verified driver package
  NVIDIA_AUTO_DRIVER (default: 1)         Allow supported distros to install NVIDIA drivers
  ROCM_AUTO_DRIVER (default: 0)            Allow Ubuntu/Debian amdgpu-install to manage the driver
  ROCM_VERSION (default: 7.2.4)             AMD ROCm release used by the system installer
  ROCM_PATH (default: /opt/rocm)             ROCm installation prefix
  PYTORCH_ROCM_VERSION (default: 2.14.0+rocm7.2)
  VLLM_ROCM_VERSION (default: 0.29.0+rocm723)
  INSTALL_SAM_MASK_FULL (default: 1)     Install full SAM mask extras
  VLLM_EXTRA_INDEX_URL                   Optional extra wheel index for vLLM (e.g. ROCm)
  MODEL_AUTO_PROVIDER_ORDER               Provider order for automatic HF model routing (default: vllm,sglang,mlx_lm,ollama)
  COOKBOOK_LOCAL_DIR                     Persistent local serving-engine root (default: PROJECT_DIR/data/local)
  VLLM_VENV_DIR                          Isolated vLLM environment
  OPENMPI4_VERSION (default: 4.1.8)       OpenMPI 4 C++ ABI compatibility version
  OPENMPI4_PREFIX                          Private OpenMPI 4 prefix for serving engines
  OPENMPI4_MAKE_JOBS                       Parallel OpenMPI compatibility build jobs
  SGLANG_VENV_DIR                        Isolated SGLang environment
  MLX_LM_VENV_DIR                        Isolated MLX-LM environment
  MLX_LM_MODEL_DIR                       Persistent MLX-LM model cache
  MLX_LM_ENDPOINT                        MLX-LM OpenAI-compatible endpoint (default: http://127.0.0.1:8081/v1)
  MLX_LM_SERVICE_NAME                    MLX-LM user service name
  MLX_LM_SERVICE_FILE                    MLX-LM user service file
  COOKBOOK_BIN_DIR                       Engine executable directory
EOF_HELP
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo "Run '$0 help' for usage."
        exit 2
        ;;
esac
