# Zarzysseus V4.3 — browser workflow selection (native Linux candidate)

**Status:** Tested offline, NOT deployed or live-verified on your host, NOT merged to GitHub.

## What V4.3 changes

Replaces only the recognized V4.1/V4.2 `_zar_browser_targets_v4` *relevance* helper in the existing nested Odysseus agent. It repairs selection for:

- `Open example.com` → `browser_navigate`
- `Open example.com screenshot the page and describe it` → `browser_navigate`, `browser_snapshot`, `browser_take_screenshot`
- `Describe the page for me` / `describe it` after browser context → `browser_snapshot`
- `Now screenshot it` / `CSS is fine` after browser context → `browser_take_screenshot`
- `Yes` immediately after an explicit browser page-description or screenshot request → matching read-only tool relevance

No background browsing, no forced execution, no bypass of per-tool policy, no changes to authentication, approval, transport, dispatch, model selection, or permissions. The existing V4.2 focus code remains responsible for intersecting targets with actual permitted MCP inventory and preserving authorized forced tools. It does **not** guarantee an agent will use every offered tool.

## CachyOS (fish) validation

Extract archive downloaded to ~/Downloads:

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4.3-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
mkdir -p "$kit"
unzip -o "$HOME/Downloads/zarzysseus_v4_3_candidate.zip" -d "$kit"
python3 -m unittest discover -s "$kit" -p 'test_browser_workflow_v43.py' -v
python3 "$kit/zarzysseus_browser_workflow_v43.py" dry-run "$agent"
```

**Stop if the dry-run refuses.** This exact-source guard intentionally rejects unknown layouts rather than modifying live agent code blindly.

If the offline tests AND dry-run pass, install when there is no active agent task:

```fish
python3 "$kit/zarzysseus_browser_workflow_v43.py" install "$agent"
python3 "$kit/zarzysseus_browser_workflow_v43.py" status "$agent"
systemctl --user restart odysseus.service
```

Use plain systemd restart, **not** the Zarzysseus TUI restart/repair workflow, which previously triggered an unrelated V8 source-integrity warning.

## Live acceptance tests

Use a **fresh Agent chat** with Dolphin:

1. `Open example.com`
2. `Describe the page for me`
3. `Now screenshot it`

Verify there are actual tool UI blocks and execution events for `browser_navigate`, `browser_snapshot`, and `browser_take_screenshot`, not prose promises.

Then separately test a fresh one-shot workflow:

`Open example.com screenshot the page and send it back and describe the page to me`

Check agent logs:

```fish
journalctl --user -u odysseus.service --since "10 minutes ago" --no-pager -o cat | grep -E 'zarzysseus-focus-v4|agent-debug|round_stream_done|Tool executed|tool_calls=' | tail -n 75
```

**Important:** The Dolphin-Mistral GGUF model in use is not a vision model. It can describe *accessible page text from `browser_snapshot`*, but an image screenshot cannot be interpreted as pixels without proper vision model and image transport. The screenshot UI may still show captured pixels.

## Rollback

If no other patch has modified `agent_loop.py` since V4.3 installation:

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4.3-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
python3 "$kit/zarzysseus_browser_workflow_v43.py" rollback "$agent"
systemctl --user restart odysseus.service
```

Rollback refuses if the installed source or backup has changed. This is deliberate.

## Boundaries

- Patch expects the original V4.1 browser helper, plus V4.2 marker and V2 context marker. The previous V4 gate diagnostic may remain installed; it is not edited by this patch.
- V4.3 only improves *tool selection*. If `tool_calls=0` when the matching schema is focused, the remaining issue is function calling, prompts, continuation logic, or context delivery, and should be diagnosed separately.
- A `Yes` follow-up is resolved from recent **user** messages; the patch does not implement a durable pending-action state machine or incorporate assistant proposals into authorization.
- Do not update or restart via any workflow that silently re-runs V8 repair against the intentionally modified source.
