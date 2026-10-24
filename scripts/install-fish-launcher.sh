#!/usr/bin/env bash
# Install the updater as a permanent fish function.
set -Eeuo pipefail
ROOT="${HOME:?}/.local/share/zarzysseus"
SOURCE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)/zarzysseus-auto-update.sh"
DEST="$ROOT/auto-update.sh"
FISH_FILE="$HOME/.config/fish/functions/zarzysseus.fish"
command -v fish >/dev/null || { echo 'Fish is not installed.' >&2; exit 2; }
command -v git >/dev/null || { echo 'Git is required for updates.' >&2; exit 2; }
[[ -f "$SOURCE" ]] && bash -n "$SOURCE" || { echo 'Bundled updater has invalid syntax.' >&2; exit 2; }
mkdir -p -- "$ROOT" "$(dirname -- "$FISH_FILE")"
tmp="$(mktemp "$ROOT/.runner.XXXXXXXX")"
trap 'rm -f -- "${tmp:-}" "${fish_tmp:-}"' EXIT
install -m 0755 "$SOURCE" "$tmp"
mv -f -- "$tmp" "$DEST"
fish_tmp="$(mktemp "$(dirname -- "$FISH_FILE")/.zarzysseus.XXXXXXXX")"
cat > "$fish_tmp" <<'FISH'
function zarzysseus --description 'Update Zarzysseus from main and launch its TUI'
    command bash "$HOME/.local/share/zarzysseus/auto-update.sh" $argv
end
FISH
fish -n "$fish_tmp"
if [[ -f "$FISH_FILE" ]] && ! cmp -s -- "$fish_tmp" "$FISH_FILE"; then
    cp -p "$FISH_FILE" "$FISH_FILE.before-autoupdate-$(date +%Y%m%d-%H%M%S)-$$"
fi
mv -f -- "$fish_tmp" "$FISH_FILE"
echo "Installed persistent fish launcher: $FISH_FILE"
echo 'Run: zarzysseus    (check updates and open TUI anywhere)'
echo 'Run: zarzysseus --update-only  (check without opening TUI)'
