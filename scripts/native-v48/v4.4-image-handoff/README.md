# Zarzysseus V4.4 — screenshot handoff for text-only Dolphin

**Candidate, not merged or deployed.** Built for the existing V4.2/V4.3 native Odysseus agent patch lineage. Tested with source-layout mocks, not yet against your actual installed `agent_loop.py`.

## What it fixes

An inline screenshot from Playwright MCP is already rendered properly in the Odysseus tool UI. The follow-up model turn also receives its Base64 image content. Dolphin-Mistral-24B-Venice-Edition is a **text-only** model, so it treats pixel data as a blob of text and produces irrelevant explanations about encoded data.

This patch changes only the **model-facing** tool-result record at the existing `_append_tool_results(...)` call site:

- For `mcp__builtin_browser__browser_take_screenshot` when the model name contains `dolphin-mistral`, omit the `images` payload from the copy sent into model context.
- Replace the tool's model-facing text with a short statement that the screenshot has been captured and rendered, but the model cannot inspect its pixels, and that `browser_snapshot` can be used for readable page content.
- **Do not** remove screenshot data from the original tool result, UI SSE events, approval policy, or any persisted tool event. Vision-capable models are unchanged.
- Leave successful MCP routing, approval gates, external/untrusted tool-result metadata, and all other tools unchanged. No tool execution is added or forced.

This is deliberately a narrow compatibility fix, **not** automatic visual understanding. The requested longer-term improvement is to route image observation to a verified vision-capable model with correct image transport. For page text, `browser_snapshot` works with Dolphin.

## CachyOS + fish

Place `zarzysseus_image_handoff_v44.zip` into `~/Downloads`. It contains one guarded patcher and offline regression tests.

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4.4-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
mkdir -p "$kit"
unzip -o "$HOME/Downloads/zarzysseus_image_handoff_v44.zip" -d "$kit"
python3 -m unittest discover -s "$kit" -p 'test_image_handoff_v44.py' -v
python3 "$kit/zarzysseus_image_handoff_v44.py" dry-run "$agent"
```

**If the dry-run refuses, stop.** The installed Odysseus source is heavily patched; no injection should occur if the real source shape differs from the expected one.

If the tests and dry-run both pass and no agent task is running:

```fish
python3 "$kit/zarzysseus_image_handoff_v44.py" install "$agent"
python3 "$kit/zarzysseus_image_handoff_v44.py" status "$agent"
systemctl --user restart odysseus.service
```

Use the direct systemd restart; Zarzysseus TUI restart was previously observed to attempt an unrelated V8 repair and refuse modified source.

## Acceptance test

1. In a **fresh Agent chat** with Dolphin: `Open example.com`. Confirm actual Playwright navigation tool block.
2. `Now screenshot it.` Screenshot should render inline in the browser tool panel, with no filename required.
3. The assistant's text should **not** attempt to interpret Base64/image bytes. It may explain that the selected model cannot see pixels.
4. `Describe the page using its accessible contents.` Confirm `browser_snapshot` executes and the response is grounded in its readable text.
5. Inspect logs for `[zarzysseus-image-v44] text_only_screenshot_sanitized=1`.

```fish
journalctl --user -u odysseus.service --since '10 minutes ago' --no-pager -o cat | grep -E 'zarzysseus-image-v44|Tool executed|round_stream_done|tool_calls=' | tail -n 40
```

Do **not** claim this is solved unless the live screenshot still displays, the model is no longer fed image bytes, and the snapshot follow-up actually executes. If the model still tries to interpret encoded text, inspect the actual model-message assembly path rather than stacking another regex.

## Rollback

If no later patch has changed `agent_loop.py`:

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4.4-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
python3 "$kit/zarzysseus_image_handoff_v44.py" rollback "$agent"
systemctl --user restart odysseus.service
```

The original source is backed up to `~/odysseus/data/local/patch-backups/` and a SHA-256 manifest is checked before rollback. Rollback refuses modifications made after this installation.

**Note:** Changing source files can trigger the earlier Zarzysseus V8 source-hash guard on a future TUI repair. This test patch does not rewrite that guard. Integrate the fix into the managed repair baseline after live validation.
