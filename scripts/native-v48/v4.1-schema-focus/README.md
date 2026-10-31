# Zarzysseus V4.1 — guarded compact MCP schema focus

This **replaces the failed V4 candidate ZIP**. The first V4 candidate's `dry-run` incorrectly counted the eight-space `return _filter_route_tool_schemas(schemas)` substring inside the twelve-space API return, so it refused the user's V3 source before making any changes. V4.1 fixes that source-guard bug using exact line matches inside the nested Odysseus router and AST return validation. It keeps the actual installed patch marker `ZARZYSSEUS_MODEL_INDEPENDENT_MCP_FOCUS_V4` because the *behavior* is still the V4 feature.

## What it does

- Prefer just the enabled, policy-permitted `mcp__builtin_browser__browser_navigate` schema for `Open example.com`, or `browser_take_screenshot` for `Now screenshot it`, including bounded same-chat follow-ups.
- Run on both Dolphin and Qwen-capable API model routes without changing the existing Qwen focus implementation.
- Recover from tool-RAG cold starts only using an existing MCP schema from `route_mcp_schemas`; never install or execute a tool by itself.
- Preserve disabled tools, caller-selected scopes, forced tools, guide/plan mode, approval replay, and existing MCP permission checks.
- Leave unrelated requests alone. Do not force tools or bypass approvals.

## Fish commands (native CachyOS)

Unzip `zarzysseus_v4_1_candidate.zip` **over the previous** `~/.local/share/zarzysseus/v4-test` files. Then:

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
python3 -m unittest discover -s "$kit" -p 'test_schema_focus_v4.py' -v
python3 "$kit/zarzysseus_schema_focus_v4.py" dry-run "$agent"
```

Only if the dry-run passes and no Odysseus task is active:

```fish
python3 "$kit/zarzysseus_schema_focus_v4.py" install "$agent"
python3 "$kit/zarzysseus_schema_focus_v4.py" status "$agent"
```

Restart Odysseus using Zarzysseus Service Management. In **Agent** mode, test `Open example.com` followed by `Now screenshot it`. Inspect:

```fish
journalctl --user -u odysseus.service --since '10 minutes ago' --no-pager -o cat | grep -E 'zarzysseus-focus-v4|agent-debug|round_stream_done|Tool executed|tool_calls=' | tail -n 65
```

The compact-schema log proves *offering*, not *execution*. A successful end-to-end test must show a real structured `browser_navigate` and `browser_take_screenshot` tool call and actual tool execution.

## Rollback

When no task is active:

```fish
python3 "$kit/zarzysseus_schema_focus_v4.py" rollback "$agent"
```

Rollback is checksum-guarded. Installation creates a timestamped source backup and a manifest in `~/odysseus/data/local/patch-backups`. It refuses to overwrite a subsequently modified source file. Restart Odysseus after rollback.

## Validation boundary

20 offline Python tests pass, including new realistic V3 dual-return regression, unrelated-return scoping, AST guard, permission checks, and install/rollback. The user's complete installed `agent_loop.py` is not available here, so the *actual* local dry-run and browser MCP live execution remain pending. This ZIP has not been committed to PR #3 or merged into `main`.
