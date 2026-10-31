#!/usr/bin/env python3
"""Guarded V4.1 compact browser-tool routing for an existing Odysseus agent_loop.py.

This narrows *already permitted* schemas for narrowly recognized browser tasks.
It does not execute tools, force function calls, disable approvals, mutate
permissions, touch model configuration, or invoke inference. Unknown source
layouts are rejected. Install creates a timestamped backup.
"""
from __future__ import annotations

import argparse
import ast
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile

MARKER = "# ZARZYSSEUS_MODEL_INDEPENDENT_MCP_FOCUS_V4"
V3_MARKER = "# ZARZYSSEUS_MCP_BARE_DOMAIN_V3"
QWEN_MARKER = "# ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V4"
FUNC_ANCHOR = "    def _tool_schemas_for_route(route_state):\n"
API_RETURN = "            return _filter_route_tool_schemas(schemas)\n"
LEGACY_RETURN = "        return _filter_route_tool_schemas(schemas)\n"
ROUTE_ANCHOR = '        route_relevant_tools = route_state["relevant_tools"]\n'

# This helper is INSIDE the existing agent coroutine, before the tool router.
# The only candidate tools it can add are members of the current MCP schema
# inventory, after repeating the pre-existing per-tool authorization checks.
HELPER = '''    # ZARZYSSEUS_MODEL_INDEPENDENT_MCP_FOCUS_V4
    def _zar_browser_targets_v4(latest, recent_messages):
        """Conservative user-only task classification, never an authorization."""
        import re as _zar_re_v4
        _cur = str(latest or "")[:1400].strip().lower()
        if not _cur or _zar_re_v4.search(
            r"\\b(?:don't|do not|never|without|cancel|stop|not now)\\b", _cur
        ):
            return ()
        _ctx = _zar_seamless_user_context(latest, recent_messages).lower()
        _domain = r"(?:https?://|www\\.|(?<![\\w@])(?:[a-z0-9-]+\\.)+(?:com|org|net|io|dev|ai|edu|gov|co|info|app|me|xyz|uk|eg)(?=[/:?#\\s]|$))"
        _url = bool(_zar_re_v4.search(_domain, _ctx))
        _nav = bool(_zar_re_v4.search(
            r"^(?:(?:please|now)\\s+|(?:can|could|would)\\s+you\\s+)*(?:open|visit|load|navigate(?:\\s+to)?|go\\s+to|browse(?:\\s+to)?)\\b",
            _cur,
        )) and _url
        _shot = bool(_zar_re_v4.search(
            r"^(?:now\\s+|please\\s+)?(?:(?:take|capture|make|get|show)\\s+(?:a\\s+|the\\s+)?)?(?:screenshot|screen\\s*shot)\\b",
            _cur,
        )) or bool(_zar_re_v4.search(
            r"\\b(?:take|capture)\\s+(?:a\\s+|the\\s+)?screenshot\\b", _cur
        ) and _nav)
        _confirm = bool(_zar_re_v4.fullmatch(
            r"(?:yes|yep|sure|go ahead|do it|okay|ok)", _cur
        ))
        _css = bool(_zar_re_v4.match(r"^css\\s+(?:is\\s+)?(?:fine|okay|ok)\\b", _cur))
        if (_confirm or _css) and _ctx != _cur:
            if _css or _zar_re_v4.search(r"\\bscreenshot\\b", _ctx):
                _shot = True
            elif _confirm and _url and _zar_re_v4.search(r"\\b(?:open|visit|navigate)\\b", _ctx):
                _nav = True
        if not (_nav or _shot):
            return ()
        _prefix = "mcp__builtin_browser__"
        _wanted = []
        if _nav:
            _wanted.append(_prefix + "browser_navigate")
        if _shot:
            _wanted.append(_prefix + "browser_take_screenshot")
        return tuple(_wanted)

    def _zar_focus_schemas_v4(schemas, route_state, route_mcp_schemas):
        """Only reduce schemas or add exact active-and-permitted browser schemas."""
        _targets = _zar_browser_targets_v4(_last_user, messages)
        if not _targets:
            return schemas
        # No direct MCP auto-offer under an explicit caller-selected scope,
        # forced call, guide/plan mode, approval replay or uncertain policy.
        if (not route_state.get("is_api_model") or guide_only or _force_answer
                or plan_mode or relevant_tools is not None or forced_tools
                or exact_approval is not None
                or route_state.get("ody_qwen_finetune_model")
                or not isinstance(disabled_tools, (set, frozenset, list, tuple, dict))):
            return schemas
        if tool_policy is not None:
            if (getattr(tool_policy, "block_all_tool_calls", True)
                    or not callable(getattr(tool_policy, "blocks", None))):
                return schemas
        if not isinstance(route_mcp_schemas, (list, tuple)):
            return schemas
        _allowed = {}
        for _s in route_mcp_schemas:
            if not isinstance(_s, dict):
                continue
            _fn = _s.get("function")
            if not isinstance(_fn, dict):
                continue
            _name = _fn.get("name")
            if _name not in _targets or _name in disabled_tools:
                continue
            if tool_policy is not None:
                try:
                    if tool_policy.blocks(_name):
                        continue
                except (TypeError, ValueError, AttributeError):
                    return schemas
            _allowed[_name] = _s
        _focused = [_allowed[_name] for _name in _targets if _name in _allowed]
        if not _focused:
            logger.info(
                "[zarzysseus-focus-v4] no authorized browser target in active MCP inventory; inventory_count=%s",
                len(route_mcp_schemas),
            )
            return schemas
        logger.info(
            "[zarzysseus-focus-v4] tool_schemas=%s->%s focused=%s",
            len(schemas), len(_focused), [s["function"]["name"] for s in _focused],
        )
        return _focused

'''
HOOK = '''            # Model-independent focus operates on the ACTIVE MCP inventory and
            # keeps caller scope, tool_policy, disabled_tools and approvals intact.
            schemas = _zar_focus_schemas_v4(schemas, route_state, route_mcp_schemas)
'''


def apply_patch(source: str) -> str:
    if MARKER in source:
        return source
    required_markers = (V3_MARKER, QWEN_MARKER,
                        "# ZARZYSSEUS_SEAMLESS_MCP_RELEVANCE_V1")
    absent = [m for m in required_markers if m not in source]
    if absent:
        raise ValueError("Required installed V3/V8 context is absent: " + ", ".join(absent))
    # NOTE: `"        return ..."` occurs *inside* the 12-space API return as a
    # substring. The V4 candidate counted that substring and incorrectly
    # refused the user's real V3 source. Select full, indentation-exact lines
    # inside the one verified nested router instead of global substring hits.
    if source.count(FUNC_ANCHOR) != 1:
        raise ValueError("Unknown Odysseus nested router: expected one exact anchor; no changes")
    tree = ast.parse(source)
    routers = [n for n in ast.walk(tree)
               if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
               and n.name == "_tool_schemas_for_route"]
    if len(routers) != 1 or not any(
        isinstance(parent, (ast.FunctionDef, ast.AsyncFunctionDef))
        and routers[0] in parent.body for parent in ast.walk(tree)
    ):
        raise ValueError("Expected exactly one nested agent tool-router; no changes")
    router = routers[0]
    lines = source.splitlines(keepends=True)
    router_lines = lines[router.lineno - 1: router.end_lineno]

    def exact_line_hits(anchor: str) -> list[int]:
        # 1-based lines within this router only; no prefix/substring matches.
        return [router.lineno + idx for idx, line in enumerate(router_lines)
                if line.rstrip("\r\n") == anchor.rstrip("\r\n")]

    api_hits = exact_line_hits(API_RETURN)
    legacy_hits = exact_line_hits(LEGACY_RETURN)
    relevance_hits = exact_line_hits(ROUTE_ANCHOR)
    if not (len(api_hits) == len(legacy_hits) == len(relevance_hits) == 1
            and relevance_hits[0] < api_hits[0] < legacy_hits[0]):
        raise ValueError(
            "Unknown Odysseus route return layout: expected one API and one "
            "legacy return in the verified nested router; no changes"
        )
    # Both must be actual AST returns, so a coincidental string, commented
    # block, or other function cannot satisfy the source guard.
    def is_filter_call(node):
        return (isinstance(node, ast.Return)
                and isinstance(node.value, ast.Call)
                and isinstance(node.value.func, ast.Name)
                and node.value.func.id == "_filter_route_tool_schemas"
                and len(node.value.args) == 1
                and isinstance(node.value.args[0], ast.Name)
                and node.value.args[0].id == "schemas")

    returns = [node for node in ast.walk(router) if is_filter_call(node)]
    if (len(returns) != 2
            or sorted(node.lineno for node in returns) != sorted(api_hits + legacy_hits)):
        raise ValueError("Unknown Odysseus return AST shape; no changes")
    # The API return is inside a top-level if route; the legacy return must
    # remain a direct child of the router. No insertion outside that branch.
    if not any(isinstance(node, ast.Return) and node.lineno == legacy_hits[0]
               for node in router.body):
        raise ValueError("Unexpected non-API return nesting; no changes")
    if not any(isinstance(node, ast.If) and any(
        isinstance(child, ast.Return) and child.lineno == api_hits[0]
        for child in node.body) for node in router.body):
        raise ValueError("Unexpected API return nesting; no changes")
    result = source.replace(FUNC_ANCHOR, HELPER + FUNC_ANCHOR, 1)
    # Replace only the checked line number from the original source (the helper
    # is inserted earlier, so its line count is taken into account here).
    helper_lines_added = HELPER.count("\n")
    api_index = api_hits[0] - 1 + helper_lines_added
    patched_lines = result.splitlines(keepends=True)
    if patched_lines[api_index] != API_RETURN:
        raise ValueError("API return moved during patch assembly; no changes")
    patched_lines[api_index] = HOOK + patched_lines[api_index]
    result = "".join(patched_lines)
    ast.parse(result)
    compile(result, "<v4-agent>", "exec")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("status", "dry-run", "install", "rollback"))
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    target = args.source.expanduser()
    if not target.is_file() or target.is_symlink():
        print("[error] Expected existing non-symlink agent_loop.py", file=sys.stderr)
        return 2
    before = target.read_text(encoding="utf-8")
    backups = target.parents[1] / "data" / "local" / "patch-backups"
    manifest = backups / "schema-focus-v4.json"
    if args.action == "rollback":
        if not manifest.is_file():
            print("[refused] V4 rollback manifest absent; no changes")
            return 2
        try:
            state = json.loads(manifest.read_text(encoding="utf-8"))
            prev = Path(state["backup"])
            original_bytes = prev.read_bytes()
            if (target.resolve() != Path(state["file"]).resolve()
                    or hashlib.sha256(target.read_bytes()).hexdigest() != state["installed_sha256"]
                    or hashlib.sha256(original_bytes).hexdigest() != state["original_sha256"]):
                raise ValueError("source or backup changed since V4 install")
        except (OSError, KeyError, ValueError, TypeError) as exc:
            print("[refused] Cannot safely rollback:", exc, file=sys.stderr)
            return 2
        fd, temp = tempfile.mkstemp(prefix=".zar-mcp-v4-rollback-", suffix=".py", dir=str(target.parent))
        try:
            with os.fdopen(fd, "wb") as output:
                output.write(original_bytes)
                output.flush()
                os.fsync(output.fileno())
            os.chmod(temp, stat.S_IMODE(prev.stat().st_mode))
            os.replace(temp, target)
        finally:
            if os.path.exists(temp):
                os.unlink(temp)
        manifest.unlink()
        print("[restored] V4 source restored from", prev)
        return 0
    if args.action == "status":
        print("V4 compact browser focus:", "installed" if MARKER in before else "not installed")
        return 0 if MARKER in before else 1
    try:
        after = apply_patch(before)
    except (SyntaxError, ValueError) as exc:
        print("[refused]", exc, file=sys.stderr)
        return 2
    if args.action == "dry-run":
        print("[pass] Source anchors, nesting and AST syntax; no files changed")
        print("[status]", "already installed" if after == before else "upgrade applicable")
        return 0
    if before == after:
        print("[ready] V4 already installed")
        return 0
    # Unlike single-file ad-hoc sed rewrites, this is backup-before-replace.
    backups.mkdir(parents=True, exist_ok=True)
    if manifest.exists():
        print("[refused] Existing V4 rollback manifest; inspect before overwriting", file=sys.stderr)
        return 2
    backup = backups / ("agent_loop.py.mcp-focus-v4."
                        + datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".bak")
    shutil.copy2(target, backup)
    fd, tmp = tempfile.mkstemp(prefix=".zar-mcp-focus-v4-", suffix=".py", dir=str(target.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as out:
            out.write(after)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(tmp, stat.S_IMODE(target.stat().st_mode))
        os.replace(tmp, target)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)
    manifest.write_text(json.dumps({
        "file": str(target.resolve()),
        "backup": str(backup.resolve()),
        "original_sha256": hashlib.sha256(before.encode("utf-8")).hexdigest(),
        "installed_sha256": hashlib.sha256(after.encode("utf-8")).hexdigest(),
    }, indent=2) + "\n", encoding="utf-8")
    print("[installed] V4 compact browser focus; tool approval and policy unchanged")
    print("[backup]", backup)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
