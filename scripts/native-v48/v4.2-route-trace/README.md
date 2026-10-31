# Zarzysseus V4.1 gate trace — diagnostic only

This is **not another behavioral patch**. It adds one metadata-only logging statement at the start of the already-installed V4.1 `_zar_focus_schemas_v4()` helper, before early-return gates. It does not edit any gating condition, add a tool, call a tool, change prompts, or change the endpoint/model/approval state.

The October 25 native run reported V4.1 as installed but sent 44 schemas for `open example.com`; `zarzysseus-focus-v4` messages were absent. We need to tell apart **no intent match** from **a deliberate early-return guard** (explicit scope, plan mode, approval replay, model mode, unknown policy, disabled tools).

## Install (fish shell, on CachyOS)

Unzip the package into the **existing** V4 test kit directory so the five tests can import the V4.1 baseline test fixture:

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
unzip -o "$HOME/Downloads/zarzysseus_v4_gate_trace.zip" -d "$kit"
python3 -m unittest discover -s "$kit" -p 'test_v4_route_trace.py' -v
python3 "$kit/zarzysseus_v4_route_trace.py" dry-run "$agent"
```

Only if all tests and dry-run succeed, and no agent task is running:

```fish
python3 "$kit/zarzysseus_v4_route_trace.py" install "$agent"
```

Restart Odysseus through the existing Service Management UI. In a NEW Agent chat, send only `Open example.com`. Read:

```fish
journalctl --user -u odysseus.service --since '10 minutes ago' --no-pager -o cat | \
    grep -E 'zarzysseus-v4-gate|zarzysseus-focus-v4|agent-debug|round_stream_done|tool_calls=' | tail -n 40
```

The `[zarzysseus-v4-gate]` log contains **only booleans, function names, and counts**. It does not include the text of user prompts, URLs, tool arguments, or secrets. Check other log lines before sharing.

If `targets=[]`, intent classification is failing on the live `_last_user`/context. If `targets` lists `browser_navigate` but `scope=True`, `plan=True`, `approval=True`, `forced=True`, `finetune=True`, `guide=True`, or `policy_blocks_all=True`, that explains the bypass. If gates are false and `mcp_inventory=0`, the MCP inventory is missing at that moment. If all guards clear and `existing_targets` has navigation but no focus log, inspect the remaining policy/disabled logic.

## Rollback (after logging, with no agent task running)

```fish
python3 "$kit/zarzysseus_v4_route_trace.py" rollback "$agent"
```

Restart the service to load rollback. Rollback is checksum-guarded and refuses if the agent source was modified after the instrumentation. It restores V4.1, **not** pre-V4.1 source. Never force rollback.

## Validation

Five synthetic offline tests pass (source and AST guard, unchanged tool behavior, privacy-minimal logs, install/status/rollback, changed-source refusal). They do NOT prove live routing or MCP execution. This diagnostic is not committed to PR #3.
