#!/usr/bin/env python3
"""Zarzysseus V4.5: bounded browser_snapshot continuation for native Odysseus.

After real, successful screenshot execution, a text-only local model may stop
with "I'll call browser_snapshot" and no actual tool call. This patch makes
ONE additional, model-generated, structured snapshot proposal attempt within
the same run. No tool runs outside Odysseus' original dispatch/approval path.

Scope intentionally narrow; NOT a general autonomous task state machine.
"""
from __future__ import annotations
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
from datetime import datetime

MARKER = "# ZARZYSSEUS_BOUNDED_SNAPSHOT_CONTINUATION_V45"
ANCHOR = "        # ZARZYSSEUS_AGENT_THINKING_RECOVERY_V3\n"
NEEDED = (
    "ZARZYSSEUS_BROWSER_WORKFLOW_V43",
    "ZARZYSSEUS_TEXT_ONLY_SCREENSHOT_HANDOFF_V44",
    "ZARZYSSEUS_FORCED_ADDITIVE_FOCUS_V42",
    "ZARZYSSEUS_AGENT_THINKING_RECOVERY_V3",
)

# The checks and helpers are pure functions, testable without live inference.
HELPER = r'''
# ZARZYSSEUS_BOUNDED_SNAPSHOT_CONTINUATION_V45_HELPERS
# A helper is module-local but it cannot dispatch tools or change permissions.
def _zar_snapshot_pending_v45(request, events, offered, *, round_num, max_rounds,
                              attempted, guide_only, force_answer, plan_mode,
                              doc_mode, relevant_tools, disabled_tools,
                              tool_policy):
    import re
    name = "mcp__builtin_browser__browser_snapshot"
    text = str(request or "")[:1500]
    if (attempted or round_num >= max_rounds or guide_only or force_answer
            or plan_mode or doc_mode or relevant_tools is not None
            or not isinstance(disabled_tools, (set, frozenset, list, tuple, dict))
            or name in disabled_tools):
        return None
    # This is scoped to the user-authored explicit combined browser workflow.
    # No assistant text or page content can request execution.
    if (not re.search(r"\b(?:describe|summari[sz]e|read|explain|analy[sz]e)\b", text, re.I)
            or not re.search(r"\b(?:page|site|website|webpage|tab)\b", text, re.I)
            or not re.search(r"(?:https?://|www\.|\b[a-z0-9-]+\.(?:com|org|net|io|dev|edu|gov|app)\b)", text, re.I)):
        return None
    if tool_policy is not None:
        if getattr(tool_policy, "block_all_tool_calls", True):
            return None
        blocks = getattr(tool_policy, "blocks", None)
        if not callable(blocks):
            return None
        try:
            if blocks(name):
                return None
        except (TypeError, ValueError, AttributeError):
            return None
    if not isinstance(events, (list, tuple)):
        return None
    def completed(tool, *, success):
        for event in events:
            if not isinstance(event, dict) or event.get("tool") != tool:
                continue
            if not success:
                return True
            if (event.get("exit_code") in (None, 0)
                    and not event.get("error")
                    and not re.search(r"(?:^|\n)\s*(?:error|failed):", str(event.get("output") or ""), re.I)):
                return True
        return False
    screenshot = "mcp__builtin_browser__browser_take_screenshot"
    if not completed(screenshot, success=True) or completed(name, success=False):
        return None
    if not isinstance(offered, (tuple, list)):
        return None
    matches = [s for s in offered if isinstance(s, dict)
               and (s.get("function") or {}).get("name") == name]
    if len(matches) != 1:
        return None
    params = (matches[0].get("function") or {}).get("parameters")
    # A zero-argument snapshot is available in the known Playwright MCP schema.
    # Unknown/mandatory arguments must not be guessed by the model probe.
    if not isinstance(params, dict) or params.get("type") != "object":
        return None
    if params.get("required") not in (None, []):
        return None
    return matches[0]


async def _zar_snapshot_proposal_v45(endpoint_url, model, headers, schema, timeout):
    import json
    name = "mcp__builtin_browser__browser_snapshot"
    if not isinstance(schema, dict) or (schema.get("function") or {}).get("name") != name:
        return []
    system = ("Select exactly one real structured tool call using the single "
              "available function. The user requested the readable content of "
              "a previously opened browser page. Do not narrate a plan and do "
              "not claim a tool was executed. If you cannot call the tool, "
              "return no call. The only valid arguments are {}.")
    try:
        proposals = []
        async for event in stream_llm(
            endpoint_url, model,
            [{"role": "system", "content": system},
             {"role": "user", "content": "Retrieve readable page content with browser_snapshot now."}],
            temperature=0, max_tokens=512, headers=headers,
            timeout=min(max(int(timeout), 10), 60), tools=[schema],
            workload="foreground",
        ):
            if not isinstance(event, str) or not event.startswith("data: "):
                continue
            try:
                data = json.loads(event[6:].strip())
            except (TypeError, ValueError):
                continue
            if not isinstance(data, dict) or data.get("type") != "tool_calls":
                continue
            for call in data.get("calls") or []:
                if not isinstance(call, dict) or call.get("name") != name:
                    continue
                raw = call.get("arguments", "{}")
                try:
                    args = json.loads(raw) if isinstance(raw, str) else raw
                except (TypeError, ValueError):
                    continue
                if args != {}:
                    continue
                ident = call.get("id")
                if not isinstance(ident, str) or not ident:
                    ident = "zar_snapshot_v45"
                proposals.append({"id": ident, "name": name, "arguments": "{}"})
        return proposals[:1]
    except Exception as exc:
        logger.warning("[zarzysseus-v45] snapshot proposal unavailable: %s", type(exc).__name__)
        return []
'''

INJECT = r'''        # ZARZYSSEUS_BOUNDED_SNAPSHOT_CONTINUATION_V45
        # One bounded, model-generated native proposal after a real screenshot.
        # No execution here; the original Odysseus dispatcher and approvals apply.
        if (not native_tool_calls and not tool_blocks and not _zar_snapshot_attempted_v45
                and _is_api_model
                and "dolphin-mistral" in str(model or "").casefold()):
            _zar_snapshot_schema_v45 = _zar_snapshot_pending_v45(
                _last_user, tool_events, all_tool_schemas,
                round_num=round_num, max_rounds=max_rounds,
                attempted=_zar_snapshot_attempted_v45,
                guide_only=guide_only, force_answer=_force_answer,
                plan_mode=plan_mode, doc_mode=_ody_doc_finetune_mode,
                relevant_tools=relevant_tools,
                disabled_tools=disabled_tools, tool_policy=tool_policy,
            )
            if _zar_snapshot_schema_v45 is not None:
                _zar_snapshot_attempted_v45 = True
                logger.info("[zarzysseus-v45] pending_snapshot=True action=one_structured_proposal round=%s", round_num)
                _zar_calls_v45 = await _zar_snapshot_proposal_v45(
                    endpoint_url, model, headers, _zar_snapshot_schema_v45,
                    agent_stream_timeout,
                )
                if _zar_calls_v45:
                    _zar_blocks_v45, _zar_native_v45, _zar_converted_v45 = _resolve_tool_blocks(
                        round_response, _zar_calls_v45, round_num,
                        is_api_model=True,
                    )
                    if (_zar_blocks_v45 and _zar_native_v45
                            and len(_zar_blocks_v45) == 1
                            and getattr(_zar_blocks_v45[0], "tool_type", None)
                                  == "mcp__builtin_browser__browser_snapshot"):
                        native_tool_calls = _zar_calls_v45
                        tool_blocks = _zar_blocks_v45
                        used_native = _zar_native_v45
                        converted_calls = _zar_converted_v45
                        logger.info("[zarzysseus-v45] snapshot_proposal_accepted=True normal_dispatch=True")
                    else:
                        logger.warning("[zarzysseus-v45] snapshot proposal rejected by native conversion")
                else:
                    logger.warning("[zarzysseus-v45] model did not provide snapshot tool call; no execution")
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _inside_stream_loop(tree: ast.AST, lineno: int) -> bool:
    # Ensure the injection is inside a real round loop, not a string/comment.
    for node in ast.walk(tree):
        if not isinstance(node, (ast.AsyncFunctionDef, ast.FunctionDef)) or node.name != "stream_agent_loop":
            continue
        for sub in ast.walk(node):
            if (isinstance(sub, (ast.For, ast.AsyncFor))
                    and sub.lineno < lineno < sub.end_lineno
                    and isinstance(sub.target, ast.Name) and sub.target.id == "round_num"):
                return True
    return False


def patch_source(src: str) -> str:
    if MARKER in src:
        return src
    for marker in NEEDED:
        if marker not in src:
            raise ValueError(f"Required prior patch not found: {marker}")
    if src.count(ANCHOR) != 1:
        raise ValueError(f"Expected one V3 conversion anchor; found {src.count(ANCHOR)}")
    tree = ast.parse(src)
    pos = src.index(ANCHOR)
    lineno = src.count("\n", 0, pos) + 1
    if not _inside_stream_loop(tree, lineno):
        raise ValueError("V3 anchor not inside stream_agent_loop round loop")
    # Verify V3 recovery follows the native conversion, not before it.
    lines = src.splitlines()
    preceding = "\n".join(lines[max(lineno-100, 0):lineno-1])
    if "_resolve_tool_blocks(" not in preceding:
        raise ValueError("Cannot confirm tool conversion precedes V3 anchor")
    if not src.endswith("\n"):
        raise ValueError("Expected newline-terminated source")
    insert_loop = "    _zar_snapshot_attempted_v45 = False\n    for round_num in range(1, max_rounds + 1):\n"
    loop_anchor = "    for round_num in range(1, max_rounds + 1):\n"
    if src.count(loop_anchor) != 1:
        raise ValueError("Expected one agent round loop")
    new = src.replace(loop_anchor, insert_loop, 1)
    new = new.replace(ANCHOR, INJECT + ANCHOR, 1)
    # Keep original imports/definitions untouched. The helper runs from the
    # imported module namespace; adding it after existing V4.4 is safe.
    new += HELPER.lstrip("\n").rstrip("\n") + "\n"
    ast.parse(new)
    compile(new, "<zarzysseus-v45>", "exec")
    return new


def atomic_replace(file: Path, data: bytes, mode: int):
    fd, tmp = tempfile.mkstemp(prefix=".zar-snapshot-v45-", suffix=".py", dir=str(file.parent))
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(data); out.flush(); os.fsync(out.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, file)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def run_cli() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("action", choices=("dry-run", "install", "status", "rollback"))
    p.add_argument("source", type=Path)
    a = p.parse_args()
    f = a.source.expanduser()
    if not f.is_file() or f.is_symlink():
        print("[refused] Expected a regular agent_loop.py", file=sys.stderr)
        return 2
    old = f.read_bytes()
    base = f.parents[1] / "data" / "local" / "patch-backups"
    manifest = base / "task-continuation-v45.json"
    if a.action == "status":
        active = MARKER.encode() in old
        print("V4.5 bounded snapshot continuation:", "installed" if active else "not installed")
        return 0 if active else 1
    if a.action == "rollback":
        if not manifest.is_file():
            print("[refused] Missing V4.5 rollback manifest", file=sys.stderr)
            return 2
        try:
            record = json.loads(manifest.read_text("utf-8"))
            backup = Path(record["backup"])
            saved = backup.read_bytes()
            if (str(f.resolve()) != record["file"]
                    or sha(old) != record["installed_sha256"]
                    or sha(saved) != record["original_sha256"]):
                raise ValueError("Current source or saved backup differs from expected digest")
            compile(saved.decode("utf-8"), str(f), "exec")
        except (OSError, ValueError, KeyError, SyntaxError, UnicodeDecodeError) as e:
            print("[refused] Unsafe rollback:", e, file=sys.stderr)
            return 2
        atomic_replace(f, saved, stat.S_IMODE(f.stat().st_mode))
        manifest.unlink()
        print("[restored] Pre-V4.5 agent source restored")
        return 0
    try:
        new = patch_source(old.decode("utf-8")).encode("utf-8")
    except (ValueError, SyntaxError, UnicodeDecodeError) as e:
        print("[refused]", e, file=sys.stderr)
        return 2
    if a.action == "dry-run":
        print("[pass] Required V4.3/V4.4 markers, round placement and AST syntax; no files changed")
        print("[status]", "already installed" if new == old else "upgrade applicable")
        return 0
    if new == old:
        print("[ready] Already installed")
        return 0
    if manifest.exists():
        print("[refused] Existing V4.5 manifest", file=sys.stderr)
        return 2
    base.mkdir(parents=True, exist_ok=True)
    backup = base / ("agent_loop.py.v45." + datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".bak")
    shutil.copy2(f, backup)
    os.chmod(backup, 0o600)
    atomic_replace(f, new, stat.S_IMODE(f.stat().st_mode))
    manifest.write_text(json.dumps({
        "file": str(f.resolve()), "backup": str(backup.resolve()),
        "original_sha256": sha(old), "installed_sha256": sha(new),
    }, indent=2) + "\n", encoding="utf-8")
    os.chmod(manifest, 0o600)
    print("[installed] One bounded model-generated browser_snapshot continuation")
    print("[backup]", backup)
    return 0


if __name__ == "__main__":
    raise SystemExit(run_cli())
