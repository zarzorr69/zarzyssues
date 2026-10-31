# Zarzysseus V4.2 — additive forced-tool focusing

## Why this patch exists

On the user's native CachyOS Odysseus installation (V8 + MCP V3 + V4.1 + gate trace), the browser MCP server connected and `Open example.com` matched the V4 target (`browser_navigate`), but the agent received 44 schemas and returned zero native tool calls. The gate diagnostic showed `forced=True`. Inspecting the installed source at lines 4281–4289 showed that `forced_tools` **adds** names to the retrieval result instead of constraining the tool surface exclusively. V4.1 incorrectly treated it as an early-return condition.

V4.2 changes **only** the known V4.1 `_zar_focus_schemas_v4()` helper:

- Still refuses to focus under explicit `relevant_tools` caller scope, guide/plan/force-answer mode, approval replay, non-API or finetune modes, and invalid tool policy/disabled-list types.
- Selects browser targets from **currently connected MCP inventory** after the existing disabled-list and policy checks.
- Preserves every **already-offered, permitted** schema whose name is in additive `forced_tools`, even if unrelated to the browser target; it does not invent a forced schema or treat these hints as new authorization.
- Deduplicates names and logs the final small schema list (no prompts, URLs, arguments or secrets).
- Adds a source-guarded new marker, backing up before install; rollback is SHA-256 guarded.

**Not a proven live fix.** It does not force Dolphin to emit tool-call JSON, fix streaming tool-call parsing, execute tools, or fix unrelated `describe it` conversation-history errors. The patch should make live tool-call behavior easier to isolate.

## Install instructions (fish)

Save the ZIP to `~/Downloads` and run:

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4.2-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
mkdir -p "$kit"
unzip -o "$HOME/Downloads/zarzysseus_v4_2_candidate.zip" -d "$kit"
python3 -m unittest discover -s "$kit" -p 'test_forced_focus_v42.py' -v
python3 "$kit/zarzysseus_forced_focus_v42.py" dry-run "$agent"
```

**Only after both tests pass**, and with no agent task active:

```fish
python3 "$kit/zarzysseus_forced_focus_v42.py" install "$agent"
python3 "$kit/zarzysseus_forced_focus_v42.py" status "$agent"
systemctl --user restart odysseus.service
```

Do **not** use the Zarzysseus TUI's broad restart/repair workflow for this step; previous restart logs showed an unrelated V8 integrity guard refusing reinstallation after the custom source modifications. Plain systemd service restart reloads the existing source without repeating installer repair actions.

In a fresh Odysseus **Agent** chat, test `Open example.com`. Then inspect:

```fish
journalctl --user -u odysseus.service --since '10 minutes ago' --no-pager -o cat | \
  grep -E 'zarzysseus-focus-v4|zarzysseus-v4-gate|agent-debug|round_stream_done|Tool executed|tool_calls=' | \
  tail -n 60
```

Expected routing pattern (the exact numbers depend on `forced_tools`):

```
[zarzysseus-focus-v4] tool_schemas=44->2 browser=1 forced_kept=1 tools=['mcp__builtin_browser__browser_navigate', 'web_search']
[agent-debug] ... tools_sent=2 ...
```

Do **not** consider the test a success unless `tool_calls>0` and a real execution event appears. If it still narrates with a small tool set, investigate the agent streaming/tool-call path rather than issuing more routing patches.

## Rollback

With no agent task active:

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4.2-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
python3 "$kit/zarzysseus_forced_focus_v42.py" rollback "$agent"
systemctl --user restart odysseus.service
```

Rollback restores the exact pre-V4.2 V4.1 + diagnostic source. It refuses if the source changed afterward. Previous V4.1 and gate-trace rollback manifests cannot safely be used until V4.2 is rolled back first. **Do not manually force a stale rollback**.

## Tests and caveats

The ZIP contains self-contained copies of the original V4.1 patch and gate-trace scripts under `test_fixtures/`. They are imported only by the V4.2 tests and are **not installed** into Odysseus. The ZIP has no changes to GitHub or Docker.

Offline suite: 17/17 tests passed in an isolated container for V4.1+trace upgrade, additive forced tool retention, denied/disabled tools, caller scope, approval replay, screenshots, idempotence, fail-closed unknown source, rollback integrity. We could not execute the patch against the actual user's full `agent_loop.py`; the guarded dry-run on their machine is still required.
