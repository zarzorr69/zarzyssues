#!/usr/bin/env bash
# ZARZYSSEUS_FISH_AUTO_UPDATE_V1
# Dedicated checkout; never reset upstream Odysseus or persistent model data.
set -Eeuo pipefail
ROOT="${HOME:?}/.local/share/zarzysseus"
REPO="$ROOT/repo"
ACTIVE="$ROOT/zarzysseus.sh"
RUNNER="$ROOT/auto-update.sh"
REMOTE='https://github.com/zarzorr69/zarzyssues.git'
mkdir -p -- "$ROOT"
notice() { printf '[zarzysseus] %s\n' "$*" >&2; }

if command -v flock >/dev/null 2>&1; then
    exec 9>"$ROOT/.update.lock"
    if ! flock -w 20 9; then
        notice 'Update lock busy; using last working copy.'
        if [[ -f "$ACTIVE" ]] && bash -n "$ACTIVE"; then
            [[ "${1:-}" == --update-only ]] && exit 0
            (( $# > 0 )) || set -- tui
            exec bash "$ACTIVE" "$@"
        fi
        exit 2
    fi
fi

if [[ ! -d "$REPO/.git" ]]; then
    if ! command -v git >/dev/null 2>&1; then
        notice 'Git unavailable; cannot initialize automatic updates.'
    else
        tmp_repo="$(mktemp -d "$ROOT/.clone.XXXXXXXX")"
        if GIT_TERMINAL_PROMPT=0 timeout -k 2s 75s git clone --quiet --depth 1 --single-branch --branch main "$REMOTE" "$tmp_repo"; then
            mv -- "$tmp_repo" "$REPO"
            notice 'Cloned official Zarzysseus main branch.'
        else
            rm -rf -- "$tmp_repo"
            notice 'Could not clone GitHub; will try the existing local installer.'
        fi
    fi
else
    if [[ "$(git -C "$REPO" remote get-url origin 2>/dev/null || :)" != "$REMOTE" ]]; then
        notice 'Unexpected Git remote; refusing to update managed checkout.'
    elif [[ -n "$(git -C "$REPO" status --porcelain --untracked-files=no 2>/dev/null || echo '?')" ]]; then
        notice 'Managed checkout has local edits; refusing to overwrite.'
    elif [[ "$(git -C "$REPO" branch --show-current 2>/dev/null || :)" != main ]]; then
        notice 'Managed checkout is not on main; refusing to switch branches.'
    elif ! GIT_TERMINAL_PROMPT=0 timeout -k 2s 25s git -C "$REPO" pull --quiet --ff-only origin main; then
        notice 'Could not fast-forward from GitHub; retaining verified version.'
    fi
fi

# Install only validated repository-owned scripts; never touch .env, Docker
# volumes, model weights, or the separate upstream Odysseus checkout.
if [[ -d "$REPO/.git" && -f "$REPO/zarzysseus.sh" ]]; then
    if bash -n "$REPO/zarzysseus.sh"; then
        if [[ ! -f "$ACTIVE" ]] || ! cmp -s -- "$REPO/zarzysseus.sh" "$ACTIVE"; then
            if [[ -f "$ACTIVE" ]]; then
                cp -p -- "$ACTIVE" "$ACTIVE.before-autoupdate-$(date +%Y%m%d-%H%M%S)-$$"
            fi
            tmp_file="$(mktemp "$ROOT/.installer.XXXXXXXX")"
            install -m 0755 -- "$REPO/zarzysseus.sh" "$tmp_file"
            mv -f -- "$tmp_file" "$ACTIVE"
            notice "Updated installer to $(git -C "$REPO" rev-parse --short HEAD)."
        fi
    else
        notice 'Repository installer failed Bash syntax check; retained last working copy.'
    fi
    if [[ -f "$REPO/scripts/zarzysseus-auto-update.sh" ]] && bash -n "$REPO/scripts/zarzysseus-auto-update.sh"; then
        if [[ ! -f "$RUNNER" ]] || ! cmp -s "$REPO/scripts/zarzysseus-auto-update.sh" "$RUNNER"; then
            tmp_file="$(mktemp "$ROOT/.runner.XXXXXXXX")"
            install -m 0755 -- "$REPO/scripts/zarzysseus-auto-update.sh" "$tmp_file"
            mv -f -- "$tmp_file" "$RUNNER"
        fi
    fi
fi

if [[ ! -f "$ACTIVE" ]] || ! bash -n "$ACTIVE"; then
    notice 'No validated Zarzysseus installer is available.'
    exit 1
fi
if [[ "${1:-}" == --update-only ]]; then
    notice 'Update check complete.'
    exit 0
fi
(( $# > 0 )) || set -- tui
exec bash "$ACTIVE" "$@"
