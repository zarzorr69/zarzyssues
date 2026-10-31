# Native Zarzysseus V4.8 — verified local patch source archive

These are the **original development patch kits** which were applied and incrementally verified on the owner's CachyOS Odysseus runtime (2026-10-31). Keep the kits' checksum-guarded installers, tests and fixtures intact. These files are not a copy of the owner's installed `agent_loop.py`.

**Important:** This is a source-archival upstream staging step, not yet a unified, clean-install V4.8 integration. Several source guards intentionally depend on earlier patches. Do not claim V4.8 is installed from `main` until a clean-install integration and regression test pass. The tracked `scripts/zarzysseus_seamless_mcp.py` in PR #3 covers an earlier V3 patch series.

## Offline tests

```bash
python3 -m unittest discover -s scripts/native-v48/v4.1-schema-focus -p 'test_*.py' -v
# Repeat for each versioned subdirectory with tests, or run python3 scripts/native-v48/run_tests.py
```

## Deployment rules

- The working local native agent contains these patches. Never commit `~/odysseus/src/agent_loop.py`, database paths, manifests, backups, model caches, or credentials.
- Every patch's `README.md` explains its prerequisites and guarded `dry-run`/`install`/`rollback` commands.
- Use a plain `systemctl --user restart odysseus.service` after applying a validated patch; don't run the broad legacy TUI repair flow.
- Each independent backup manifest is checksum guarded. Roll back newest-first only if the current file matches its manifest.
- `restart-guard` addresses the TUI repair-on-restart regression separately.

## Verified native acceptance, 2026-10-31

Live tested Dolphin-Mistral 24B: `mcp__builtin_browser__browser_navigate` exit 0; `browser_snapshot` exit 0; V4.8 fallback with `explicit_user_screenshot_plan=True`, `normal_dispatch_only=True`, `screenshot_proposal_accepted=True`; `browser_take_screenshot` exit 0; image inline and page description grounded in snapshot. Tested scenario: one natural-language request open, capture, display, and describe example.com. This does not verify generic workflows, cross-chat recall, CPU-only Docker, or fresh native installs.

## Next work before treating this as shipped

1. Consolidate patch behavior into one maintained installer (and remove obsolete replacement kits after preserving rollback lineage).
2. Test new native checkout/bootstrap and then upgrade an existing V3 install; prove parity with verified local V4.8 result.
3. Check approvals, tool scopes, repeat-call prevention, screenshot inline results, text-only/vision routing, and no false success claims in CI.
4. Revisit cross-chat `search_chats` and `manage_memory` and persistent artifact references as the next feature milestone.
