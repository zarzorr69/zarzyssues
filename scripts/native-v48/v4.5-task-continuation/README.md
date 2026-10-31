# Zarzysseus V4.5 — Bounded Browser Snapshot Continuation

**Status:** Offline-tested candidate; **not yet live-tested** on the user's modified native Odysseus. Do **not** merge into PR #3 or assume the fix works until its guarded dry-run and live acceptance test pass.

## What it fixes

Previously verified live behavior:

1. Dolphin-Mistral navigated with `mcp__builtin_browser__browser_navigate`.
2. It captured and displayed an inline image with `mcp__builtin_browser__browser_take_screenshot`.
3. Although `browser_snapshot` was offered in the following round, Dolphin returned only: "For a readable analysis of the page content, I'll call browser_snapshot to capture the page's text." (`tool_calls=0`).

V4.5 allows **one model-generated, structured `browser_snapshot` proposal** when a user-requested combined *open / screenshot / describe* task has a successful screenshot tool event, no snapshot tool event, and the current round otherwise produced no tool calls. Only the already-offered schema can be used, and `browser_snapshot` must be callable with zero arguments. The proposal enters Odysseus' normal `_resolve_tool_blocks` and existing dispatcher/approval path. If the model returns prose or invalid args instead of a real structured call, no new tool is executed.

It intentionally does **not** dispatch a browser tool directly, add tools to the authorized set, bypass approvals, override the denied tool list or policies, or turn untrusted page text into user authorization.

For now the code is restricted to the tested **Dolphin-Mistral** model family. V4.2–V4.4 browser routing and image handling are left intact.

## Install (fish shell, CachyOS)

Download `zarzysseus_v4_5_candidate.zip` into `~/Downloads`.

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4.5-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
mkdir -p "$kit"
unzip -o "$HOME/Downloads/zarzysseus_v4_5_candidate.zip" -d "$kit"
python3 -m unittest discover -s "$kit" -p 'test_task_continuation_v45.py' -v
python3 "$kit/zarzysseus_task_continuation_v45.py" dry-run "$agent"
```

If the tests AND dry-run pass, with no current agent action running:

```fish
python3 "$kit/zarzysseus_task_continuation_v45.py" install "$agent"
python3 "$kit/zarzysseus_task_continuation_v45.py" status "$agent"
systemctl --user restart odysseus.service
```

Use direct systemd restart, **not** TUI restart/repair: the legacy V8 repair manifest previously refused the additionally patched agent source. If dry-run refuses, stop and share the exact output; don't force changes.

## Live acceptance check

Use **fresh Agent chat**, same Dolphin model, normal language:

> Open https://example.com, take a screenshot and describe the page.

Expected if successful: native navigate and screenshot (with approvals as normally needed), an actual `browser_snapshot` call, and a grounded description of the page's readable content. Screenshot pixels still belong in the UI; Dolphin is text-only and must not attempt raw image interpretation.

Inspect:

```fish
journalctl --user -u odysseus.service --since '15 minutes ago' --no-pager -o cat | grep -E 'zarzysseus-v45|browser_snapshot|browser_take_screenshot|Tool executed|round_stream_done|tool_calls=' | tail -n 75
```

Look for `pending_snapshot=True`, `snapshot_proposal_accepted=True`, and `Tool executed: mcp: mcp__builtin_browser__browser_snapshot -> exit_code=0`. Merely mentioning `browser_snapshot` in prose is **not** proof.

If the model supplies no structured call, the V4.5 attempt ends without fabricating one. This build does not prevent repeated bad screenshot calls in the *earlier* workflow; that is a separate dispatcher-level improvement.

## Rollback

If no other patch has changed `agent_loop.py` since V4.5 installation:

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4.5-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
python3 "$kit/zarzysseus_task_continuation_v45.py" rollback "$agent"
systemctl --user restart odysseus.service
```

Manifest stored in `~/odysseus/data/local/patch-backups/task-continuation-v45.json`. Both the source and original backup are checked by SHA-256 before rollback. Do not manually delete the manifest to bypass a checksum mismatch.

## Boundaries

- Requires installed V4.2, V4.3, V4.4 and legacy V3 markers and an expected nested round loop. Fail-closed source guard rejects unknown layouts.
- Does not create a general persistent workflow planner or long-term memory. It is a **single bounded recovery step** for the reproduced snapshot omission.
- Does not call `browser_snapshot` directly. It retries once through the selected local model, and only an actual structured tool-call proposal can proceed to the normal authorized dispatcher.
- Does not re-run or modify the V8 source repair workflow.
- Offline tests are synthetic, not a full `agent_loop.py` integration run. A successful dry-run on the native installation is a necessary next check.
