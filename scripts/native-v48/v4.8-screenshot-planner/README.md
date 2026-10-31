# Zarzysseus V4.8 — Bounded Screenshot Plan Fallback

## What this fixes

Your October 31 live logs showed:

- `browser_navigate` successfully executed (`exit_code=0`)
- screenshot tool was offered in the policy-scoped agent turn
- Dolphin produced prose (`tool_calls=0`)
- V4.6 noticed the outstanding screenshot
- its extra one-tool model request returned `no valid screenshot proposal`

V4.8 changes only what happens **after** that existing bounded proposal fails. It generates minimal `browser_take_screenshot` arguments from the actual advertised MCP schema for the screenshot explicitly requested by the user, and passes the proposal back through `_resolve_tool_blocks` and the **unchanged** Odysseus permission/approval/execution path.

This is a *deterministic user-requested plan*, not a claim that the model issued a tool call or that a screenshot executed. The assistant must still report actual execution success/failure based on normal tool results.

## Constraints

- Requires the installed V4.6 and V4.7.1 source markers, plus V4.5 snapshot continuation.
- Only activates if V4.6 already found **explicit user screenshot intent, a successful navigation, an advertised and policy-permitted screenshot tool**, no previous screenshot attempt and sufficient remaining tool rounds.
- V4.7.1's approved replay caller-scope guard still applies.
- At most one attempt via the existing V4.6 `_zar_shot_attempted_v46` flag.
- Never passes filename (inline-image rendering), `target`, `element`, arbitrary code or page-derived arguments.
- Rejects unknown required fields and unfamiliar schema constraints.
- Does not bypass approvals, unlock disabled tools, or perform a browser action directly.
- Does not modify V4.4 image handling or V4.5 snapshot routing.

## CachyOS / fish installation

Download `zarzysseus_v4_8_candidate.zip` into `~/Downloads`.

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4.8-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
mkdir -p "$kit"
unzip -o "$HOME/Downloads/zarzysseus_v4_8_candidate.zip" -d "$kit"
python3 -m unittest discover -s "$kit" -p 'test_screenshot_planner_v48.py' -v
python3 "$kit/zarzysseus_screenshot_planner_v48.py" dry-run "$agent"
```

Only when **all tests and the source-specific dry-run pass**, with no running agent task:

```fish
python3 "$kit/zarzysseus_screenshot_planner_v48.py" install "$agent"
python3 "$kit/zarzysseus_screenshot_planner_v48.py" status "$agent"
systemctl --user restart odysseus.service
```

**Do not** use the TUI's Install All Fixes / Agent Repair to activate this patch; earlier V8 checksum integrity checks do not account for later independently installed runtime patches.

## Live acceptance test

In a new Agent conversation:

> Open https://example.com, capture and display a screenshot inline, then read and describe the page. Finish the steps before reporting success.

If the Odysseus approval card appears, use **Allow for this task**; do not substitute a separate typed `Yes`.

```fish
journalctl --user -u odysseus.service --since '15 minutes ago' --no-pager -o cat |
    grep -Ei 'zarzysseus-v48|zarzysseus-v46|zarzysseus-v45|browser_navigate|browser_take_screenshot|browser_snapshot|Tool executed|round_stream_done' |
    tail -n 90
```

**Pass only if** the screenshot tool actually executes with `exit_code=0`, the screenshot renders inline, the page snapshot executes, and the final text is grounded in that snapshot.

## Rollback

Only if source is unchanged since this patch:

```fish
python3 "$kit/zarzysseus_screenshot_planner_v48.py" rollback "$agent"
systemctl --user restart odysseus.service
```

Rollback is checksum protected and restores the exact pre-V4.8 `agent_loop.py` backup.

## Honest scope

Offline test coverage is synthetic. It has not been installed or live-tested on your local Odysseus instance, and it is not merged into PR #3. It does not implement general cross-chat memory or long-lived task state. If the dry-run refuses, stop and share the refusal; do not force the patch.
