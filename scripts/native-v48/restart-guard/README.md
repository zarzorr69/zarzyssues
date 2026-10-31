# Zarzysseus Restart Guard V1

Fixes the native launcher behavior where **Service Management → Restart** runs agent, Cookbook, and MCP-skill repair installers before restarting, causing `Existing V8 source was modified; installation refused` after legitimate V4.5 changes. This kit touches **only `~/odysseus/zarzysseus.sh`**, never `src/agent_loop.py`, model weights, MCP configuration or project branches.

The restart action now restarts the existing service without auto-provisioning. `start`, `enable`, and explicit `agent-repair` / `install-all-fixes` paths remain unchanged. The existing `service_restart` function still restarts Ollama when managed and checks ChromaDB/workspace according to the launcher; use `systemctl --user restart odysseus.service` for an Odysseus-only restart.

## Fish commands

Download the ZIP to `~/Downloads`, then:

```fish
set -l kit "$HOME/.local/share/zarzysseus/restart-guard"
set -l sh "$HOME/odysseus/zarzysseus.sh"
mkdir -p "$kit"
unzip -o "$HOME/Downloads/zarzysseus_restart_guard_v1.zip" -d "$kit"
python3 -m unittest discover -s "$kit" -p 'test_restart_guard.py' -v
python3 "$kit/zarzysseus_restart_guard.py" dry-run "$sh"
```

If and only if the checks pass:

```fish
python3 "$kit/zarzysseus_restart_guard.py" install "$sh"
python3 "$kit/zarzysseus_restart_guard.py" status "$sh"
```

Restart through the Zarzysseus TUI and confirm no automatic V8 repair message appears. No service restart is needed to activate this **shell launcher** patch. A future `git pull` or managed launcher update may overwrite this local edit; the checksum guard prevents unsafe blind rollback.

## Rollback

```fish
python3 "$kit/zarzysseus_restart_guard.py" rollback "$sh"
```

Rollback refuses if someone changed `zarzysseus.sh` since patch installation. Always inspect divergent edits before manually reconciling.

## Scope

This avoids the **false automatic V8 reinstall check during restart**. It does **not** change the V8 integrity rules for explicit repairs, and does not incorporate V4.5 into the PR #3 installer. Longer term, fix managed patch composition in the repository and merge only after live runtime tests.
