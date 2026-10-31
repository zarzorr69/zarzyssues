# Zarzysseus V4.6 — Navigate → inline screenshot continuation

This is a **candidate patch**, not a deployed or GitHub-merged release.

## What the October 27 screenshots demonstrated

The first request requested navigation, screenshot, and description. `browser_navigate` succeeded; Dolphin replied that it *would* take a screenshot, but did not issue the call. A later request mistakenly used `browser_snapshot` as if it produced a PNG and then described the “Learn more” link speculatively.

V4.5 only recovers the **screenshot → browser_snapshot** part *after a screenshot has already succeeded.* V4.6 handles the earlier **successful navigation → missing screenshot** part.

## Scope

- One model-generated structured screenshot proposal **only** after successful navigation from an explicit user-authored URL + screenshot request, when the model stops without a call.
- Requires `browser_take_screenshot` to already appear in the schemas Odysseus authorized for that round. Does **not** add new tools, override `disabled_tools` or `tool_policy`, or change approvals. All tool calls are processed by Odysseus's normal conversion/dispatch/approval pipeline.
- Screenshot proposals with `filename`, `target`, `element`, unsupported schema fields or invalid parameter values are discarded. Omit filename so Playwright can return an inline image.
- At most one additional proposal per agent run. Any already-attempted screenshot, even a failed one, prevents another proposal.
- V4.5 can still recover a missing `browser_snapshot` call after screenshot success.
- This is *not* image reuse across chats, actual visual image understanding, complete generic planning, or a guarantee that Dolphin will call a tool.

## Install on CachyOS (fish)

Put `zarzysseus_v4_6_candidate.zip` in `~/Downloads` and run:

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4.6-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
mkdir -p "$kit"
unzip -o "$HOME/Downloads/zarzysseus_v4_6_candidate.zip" -d "$kit"
python3 -m unittest discover -s "$kit" -p 'test_screenshot_continuation_v46.py' -v
python3 "$kit/zarzysseus_screenshot_continuation_v46.py" dry-run "$agent"
```

Only if the tests and dry-run pass, and no agent run is active:

```fish
python3 "$kit/zarzysseus_screenshot_continuation_v46.py" install "$agent"
python3 "$kit/zarzysseus_screenshot_continuation_v46.py" status "$agent"
systemctl --user restart odysseus.service
```

**Don't use the broad 'Install All Fixes' or `agent-repair` operation** to restart the service; those pathways have previously rejected later valid agent patches through the V8 whole-file checksum check.

## Live acceptance test

In a fresh Odysseus Agent conversation:

> Open https://example.com, take a screenshot, display it inline, then read and describe the page. Complete the steps in one request, only saying an action succeeded after it actually executes.

Inspect logs:

```fish
journalctl --user -u odysseus.service --since '15 minutes ago' --no-pager -o cat | grep -Ei 'zarzysseus-v46|zarzysseus-v45|browser_navigate|browser_take_screenshot|browser_snapshot|Tool executed|round_stream_done' | tail -n 80
```

A successful result must show all three `Tool executed` events with exit code 0 and a screenshot rendered in the chat. A visible model plan does not qualify as completion. If V4.6 logs `no valid screenshot proposal`, report that exact message and **don't force a tool call**.

## Rollback

Only if no later patch modified the source:

```fish
python3 "$kit/zarzysseus_screenshot_continuation_v46.py" rollback "$agent"
systemctl --user restart odysseus.service
```

Rollback compares SHA-256 of the full source and backup, and refuses if they have changed. No cleanup or overwrite of the earlier V4.5 backup.

## Limitations and next development

“Show me the screenshot again” cannot reuse a screenshot that was never captured. Even after this patch, true artifact reuse across turns needs an explicit persisted screenshot reference, independent of keyword routing. `browser_snapshot` produces readable page content, not a PNG. For link descriptions, the agent must rely on the actual retrieved link URL/content, not assumptions about `example.com`.
