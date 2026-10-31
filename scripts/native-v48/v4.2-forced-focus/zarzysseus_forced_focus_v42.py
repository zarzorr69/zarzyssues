#!/usr/bin/env python3
"""Source-guarded V4.2 upgrade for V4.1 compact browser routing.

In the installed agent, forced_tools is an ADDITIVE retrieval hint, not a
caller-selected *exclusive* tool scope. The V4.1 helper treated any nonempty
forced_tools as a blanket veto. This patch focuses the active, policy-allowed
browser inventory while preserving any caller-forced schemas already present.

Only changes a recognized V4.1 helper. No tool execution or changes to approval,
caller-selected relevant_tools scopes, disabled tools, tool policy, or prompts.
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

MARKER = "# ZARZYSSEUS_FORCED_ADDITIVE_FOCUS_V42"
BASE_MARKER = "# ZARZYSSEUS_MODEL_INDEPENDENT_MCP_FOCUS_V4"
GUARD_OLD = '''        # No direct MCP auto-offer under an explicit caller-selected scope,
        # forced call, guide/plan mode, approval replay or uncertain policy.
        if (not route_state.get("is_api_model") or guide_only or _force_answer
                or plan_mode or relevant_tools is not None or forced_tools
                or exact_approval is not None
'''
GUARD_NEW = '''        # ZARZYSSEUS_FORCED_ADDITIVE_FOCUS_V42
        # forced_tools adds *visible* tools to retrieval; it is not an exclusive
        # scope. Preserve every authorized, actually offered forced schema below.
        # Explicit relevant_tools remains a hard no-expansion boundary.
        if (not route_state.get("is_api_model") or guide_only or _force_answer
                or plan_mode or relevant_tools is not None
                or exact_approval is not None
'''
FOCUSED_OLD = '''        logger.info(
            "[zarzysseus-focus-v4] tool_schemas=%s->%s focused=%s",
            len(schemas), len(_focused), [s["function"]["name"] for s in _focused],
        )
        return _focused
'''
FOCUSED_NEW = '''        # Keep additive forced tools, but only when they were ALREADY offered
        # by this route. Never use forced_tools to authorize or invent a schema.
        # Unknown types fail closed, preserving the upstream route unchanged.
        if forced_tools is not None:
            if not isinstance(forced_tools, (set, frozenset, list, tuple, dict)):
                return schemas
            if not all(isinstance(_v, str) for _v in forced_tools):
                return schemas
            _forced_names_v42 = set(forced_tools)
        else:
            _forced_names_v42 = set()
        _focused_names_v42 = {
            str((_s.get("function") or {}).get("name") or "")
            for _s in _focused if isinstance(_s, dict)
        }
        _preserved_v42 = []
        for _s in schemas:
            if not isinstance(_s, dict) or not isinstance(_s.get("function"), dict):
                continue
            _name = _s["function"].get("name")
            if (not isinstance(_name, str) or _name not in _forced_names_v42
                    or _name in _focused_names_v42 or _name in disabled_tools):
                continue
            if tool_policy is not None:
                try:
                    if tool_policy.blocks(_name):
                        continue
                except (TypeError, ValueError, AttributeError):
                    return schemas
            _preserved_v42.append(_s)
            _focused_names_v42.add(_name)
        _result_v42 = _focused + _preserved_v42
        logger.info(
            "[zarzysseus-focus-v4] tool_schemas=%s->%s browser=%s forced_kept=%s tools=%s",
            len(schemas), len(_result_v42), len(_focused), len(_preserved_v42),
            [s["function"]["name"] for s in _result_v42],
        )
        return _result_v42
'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def upgrade_source(source: str) -> str:
    if MARKER in source:
        return source
    if BASE_MARKER not in source:
        raise ValueError("Expected installed V4.1 compact browser focus; no changes")
    tree = ast.parse(source)
    funcs = [node for node in ast.walk(tree)
             if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
             and node.name == "_zar_focus_schemas_v4"]
    if len(funcs) != 1:
        raise ValueError("Expected exactly one V4.1 focus helper; no changes")
    fn = funcs[0]
    lines = source.splitlines(keepends=True)
    fn_text = "".join(lines[fn.lineno-1:fn.end_lineno])
    for anchor, label in ((GUARD_OLD, "V4.1 guard"), (FOCUSED_OLD, "V4.1 return")):
        if fn_text.count(anchor) != 1 or source.count(anchor) != 1:
            raise ValueError("Unrecognized " + label + " source layout; no changes")
    if not any(isinstance(x, ast.If) and any(isinstance(n, ast.Name)
                       and n.id == "forced_tools" for n in ast.walk(x.test))
               for x in ast.walk(fn)):
        raise ValueError("V4.1 forced-tools guard AST not recognized; no changes")
    result = source.replace(GUARD_OLD, GUARD_NEW, 1).replace(FOCUSED_OLD, FOCUSED_NEW, 1)
    compile(result, "<zarzysseus-v4.2>", "exec")
    return result


def atomic_write(path: Path, content: bytes, mode: int) -> None:
    fd, tmp = tempfile.mkstemp(prefix=".zar-v42-", suffix=".py", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as out:
            out.write(content)
            out.flush()
            os.fsync(out.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("action", choices=("status", "dry-run", "install", "rollback"))
    ap.add_argument("source", type=Path)
    ns = ap.parse_args()
    path = ns.source.expanduser()
    if not path.is_file() or path.is_symlink():
        print("[refused] Existing regular agent_loop.py required; no changes", file=sys.stderr)
        return 2
    original = path.read_bytes()
    backups = path.parents[1] / "data" / "local" / "patch-backups"
    manifest = backups / "schema-focus-v42.json"
    if ns.action == "status":
        found = MARKER.encode() in original
        print("V4.2 additive forced-tool focus:", "installed" if found else "not installed")
        return 0 if found else 1
    if ns.action == "rollback":
        if not manifest.is_file():
            print("[refused] V4.2 rollback manifest missing; no changes", file=sys.stderr)
            return 2
        try:
            state = json.loads(manifest.read_text(encoding="utf-8"))
            saved_path = Path(state["backup"])
            saved = saved_path.read_bytes()
            if (path.resolve() != Path(state["file"]).resolve()
                    or digest(original) != state["installed_sha256"]
                    or digest(saved) != state["original_sha256"]):
                raise ValueError("Source or backup modified since installation")
            compile(saved.decode("utf-8"), str(path), "exec")
        except (ValueError, OSError, TypeError, KeyError, UnicodeDecodeError) as exc:
            print("[refused] Unsafe rollback:", exc, file=sys.stderr)
            return 2
        atomic_write(path, saved, stat.S_IMODE(path.stat().st_mode))
        manifest.unlink()
        print("[restored] Source returned to pre-V4.2 state:", saved_path)
        return 0
    try:
        text = original.decode("utf-8")
        patched = upgrade_source(text).encode("utf-8")
    except (SyntaxError, UnicodeDecodeError, ValueError) as exc:
        print("[refused]", exc, file=sys.stderr)
        return 2
    if ns.action == "dry-run":
        print("[pass] Guarded V4.1 helper and AST syntax; no files changed")
        print("[status]", "already installed" if patched == original else "upgrade applicable")
        return 0
    if patched == original:
        print("[ready] V4.2 already installed")
        return 0
    if manifest.exists():
        print("[refused] An existing V4.2 manifest is present", file=sys.stderr)
        return 2
    backups.mkdir(parents=True, exist_ok=True)
    backup = backups / ("agent_loop.py.v42." + datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".bak")
    shutil.copy2(path, backup)
    atomic_write(path, patched, stat.S_IMODE(path.stat().st_mode))
    manifest.write_text(json.dumps({
        "file": str(path.resolve()), "backup": str(backup.resolve()),
        "original_sha256": digest(original), "installed_sha256": digest(patched),
    }, indent=2) + "\n", encoding="utf-8")
    print("[installed] V4.2: additive forced-tool names retained; source backup created")
    print("[backup]", backup)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
