# Zarzysseus V4.7.1 — AST-scoped approval replay repair

This is a revised candidate for the **failed V4.7 dry-run**. The V4.7 candidate required an exact multiline source string for the V4.6 guard and refused the user's modified `agent_loop.py`. V4.7.1 instead locates that guard by Python AST structure, requires all V4.6 original safety conditions to remain, changes only the explicit `relevant_tools is not None` clause, and forwards `approval_replay=exact_approval is not None` to the V4.6 helper.

**Security and functional limits:** This patch does not execute tools, create schemas, bypass disabled tools, ignore explicit scopes, or approve a call. It allows a screenshot *proposal* only if the approved replay has a scope that already includes the screenshot schema and the tool is already available and permitted under tool policy. Native dispatcher and approval remain in control. It does not implement a general agent task planner, nor guarantee the model will propose a call.

The kit was tested offline on synthetic source fixtures. It has **not** yet been tested against the user's full locally modified Odysseus source. If `dry-run` refuses a different layout, **do not force the patch**; inspect the actual source and adjust only after verification.

## On CachyOS (fish)

Download `zarzysseus_v4_7_1_candidate.zip` into `~/Downloads`.

```fish
set -l kit "$HOME/.local/share/zarzysseus/v4.7.1-test"
set -l agent "$HOME/odysseus/src/agent_loop.py"
mkdir -p "$kit"
unzip -o "$HOME/Downloads/zarzysseus_v4_7_1_candidate.zip" -d "$kit"
python3 -m unittest discover -s "$kit" -p 'test_approved_replay_v471.py' -v
python3 "$kit/zarzysseus_approved_replay_v471.py" dry-run "$agent"
```

Expected end of dry-run:

```
[pass] V4.6 helper and scoped call checked with AST; no file changes
[status] upgrade applicable
```

If—and only if—tests and dry-run pass, and no agent task is running:

```fish
python3 "$kit/zarzysseus_approved_replay_v471.py" install "$agent"
python3 "$kit/zarzysseus_approved_replay_v471.py" status "$agent"
systemctl --user restart odysseus.service
```

## Live acceptance test

In a fresh **Agent** conversation:

> Open https://example.com, take a screenshot and display it inline, then describe what the page says. Complete every requested step; don't claim a tool ran unless it succeeded.

Confirm that the UI shows `browser_navigate`, `browser_take_screenshot`, and `browser_snapshot` **all completed** and the screenshot image actually appeared. The ordering between screenshot and snapshot can vary.

Review logs (check for secrets before sharing):

```fish
journalctl --user -u odysseus.service --since '15 minutes ago' --no-pager -o cat | grep -Ei 'zarzysseus-v46|zarzysseus-v45|browser_navigate|browser_take_screenshot|browser_snapshot|Tool executed|round_stream_done' | tail -n 80
```

## Rollback

Only when the original installed source has not been modified by any later patch:

```fish
python3 "$kit/zarzysseus_approved_replay_v471.py" rollback "$agent"
systemctl --user restart odysseus.service
```

The installer places its restricted backup and checksum manifest under `~/odysseus/data/local/patch-backups/`. It refuses checksum mismatches, unknown layouts, symlinked sources, and an existing legacy V4.7 patch.

Do **not** run the TUI `agent-repair` or `Install All Fixes` workflow for this targeted repair; those may attempt to reinstall legacy patches and trigger the unrelated V8 checksum warning.
