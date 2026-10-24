# Fish auto-update launcher (native Linux)

The `zarzysseus` command can **check `main` on GitHub on every launch**, adopt a validated update, then open the native TUI, regardless of the current directory.

## First-time setup on CachyOS / fish

```fish
set -l checkout "$HOME/.local/share/zarzysseus/repo"
if not test -d "$checkout/.git"
    git clone --depth 1 --single-branch --branch main https://github.com/zarzorr69/zarzyssues.git "$checkout"
end
bash "$checkout/scripts/install-fish-launcher.sh"
```

Open a new fish terminal (or run `source ~/.config/fish/functions/zarzysseus.fish`) and type:

```fish
zarzysseus
```

From any working directory, this checks the official `main` branch and fast-forwards the **dedicated Zarzysseus checkout** (`~/.local/share/zarzysseus/repo`). If the new `zarzysseus.sh` passes `bash -n`, it atomically replaces the active installer at `~/.local/share/zarzysseus/zarzysseus.sh`, backing up the previous version. The updater also refreshes its own launcher file.

```fish
zarzysseus --update-only
zarzysseus status
zarzysseus install-all-fixes
```

GitHub outages or an interrupted pull do not overwrite the last working script. The checkout must remain on `main`, have the expected remote, and have no local tracked changes; updates are **fast-forward-only**. Local changes are never force-reset.

**Scope and safety:** This updates the source checkout and the native installer/launcher. It does **not** automatically run an OS upgrade, pull models, replace your `~/odysseus` working tree or data, update the Docker toolkit, or recreate containers. Install/Update or Docker-kit synchronization remains explicitly initiated. Every invocation requires a GitHub network check (up to 25 seconds on an existing checkout); offline launches use the last validated installer. The first clone can take longer.

**Fish startup:** Installer generates `~/.config/fish/functions/zarzysseus.fish` and keeps a dated backup of any earlier function. This is different from merely defining a temporary fish function in the current terminal.

## Install all fixes

The `INSTALL ALL FIXES / OPTIMIZATIONS` option lives in **Install / Update** for both native and Docker TUIs.

- **Native:** `zarzysseus install-all-fixes`. Uses existing agent, chat-continuity and Cookbook repair helpers, reconciles Ollama endpoint inventories if Ollama is online, and runs Full-only endpoint diagnostics. It may restart the managed Odysseus service as part of the agent repair; it does not run an OS upgrade or pull model weights.
- **Docker:** use **Install / Update → Install All Fixes** inside the Docker-mode TUI or `bash docker/zarzysseus-docker.sh install-all-fixes` from the Docker kit. Requires an existing running Odysseus and toolkit; asks for `FIX_ALL` confirmation, runs only container-compatible helpers, checks model visibility, and restarts only Odysseus on successful repair. It never configures host GPU drivers or removes volumes.

These repair paths are intentionally not a promise that every optional integration works on every upstream release. Inspect warnings and health checks before relying on a component.
