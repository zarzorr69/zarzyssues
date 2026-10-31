#!/usr/bin/env python3
"""Targeted V4.1 routing gate diagnostic for existing native Odysseus.

Adds one privacy-minimal logger line before V4.1's early-return gates. It does
NOT change tool selection, permissions, model output, prompts, execution, or
approvals. Source guard, atomic backup-before-write and checksum rollback.
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

TRACE_MARKER = '# ZARZYSSEUS_V4_GATE_TRACE_V1'
FOCUS_MARKER = '# ZARZYSSEUS_MODEL_INDEPENDENT_MCP_FOCUS_V4'
SOURCE_ANCHOR = '''        _targets = _zar_browser_targets_v4(_last_user, messages)
        if not _targets:
            return schemas
'''
LOG_INSERT = '''        # ZARZYSSEUS_V4_GATE_TRACE_V1
        # Metadata only: no prompts, tool arguments, secrets, account IDs, or history.
        _zar_existing_v4 = {
            str((s.get("function") or {}).get("name") or "")
            for s in schemas
            if isinstance(s, dict) and isinstance(s.get("function"), dict)
        } if isinstance(schemas, (tuple, list)) else set()
        logger.info(
            "[zarzysseus-v4-gate] targets=%s offered=%s existing_targets=%s mcp_inventory=%s history_count=%s api=%s guide=%s force=%s plan=%s scope=%s forced=%s approval=%s finetune=%s disabled_valid=%s policy_present=%s policy_blocks_all=%s policy_has_blocks=%s",
            list(_targets),
            len(schemas) if isinstance(schemas, (tuple, list)) else -1,
            sorted(_zar_existing_v4.intersection(_targets)),
            len(route_mcp_schemas) if isinstance(route_mcp_schemas, (tuple, list)) else -1,
            len(messages) if isinstance(messages, (tuple, list)) else -1,
            bool(route_state.get("is_api_model")), bool(guide_only),
            bool(_force_answer), bool(plan_mode), relevant_tools is not None,
            bool(forced_tools), exact_approval is not None,
            bool(route_state.get("ody_qwen_finetune_model")),
            isinstance(disabled_tools, (set, frozenset, list, tuple, dict)),
            tool_policy is not None,
            bool(getattr(tool_policy, "block_all_tool_calls", True)) if tool_policy is not None else False,
            callable(getattr(tool_policy, "blocks", None)) if tool_policy is not None else True,
        )
'''

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def updated(text: str) -> str:
    if TRACE_MARKER in text:
        return text
    if FOCUS_MARKER not in text:
        raise ValueError('V4.1 model-independent focus marker missing; no changes')
    if text.count(SOURCE_ANCHOR) != 1:
        raise ValueError('Unexpected V4.1 focus helper layout; no changes')
    tree = ast.parse(text)
    funcs = [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == '_zar_focus_schemas_v4']
    if len(funcs) != 1:
        raise ValueError('Expected one V4.1 helper in source; no changes')
    fn = funcs[0]
    lines = text.splitlines(keepends=True)
    matchline = text[:text.index(SOURCE_ANCHOR)].count('\n') + 1
    if not (fn.lineno < matchline <= fn.end_lineno):
        raise ValueError('V4.1 source anchor is outside focus helper; no changes')
    if len([n for n in ast.walk(fn) if isinstance(n, ast.Assign) and any(isinstance(t, ast.Name) and t.id == '_targets' for t in n.targets)]) != 1:
        raise ValueError('Unrecognized V4.1 targets assignment; no changes')
    out = text.replace(SOURCE_ANCHOR,
        '        _targets = _zar_browser_targets_v4(_last_user, messages)\n'
        + LOG_INSERT
        + '        if not _targets:\n            return schemas\n', 1)
    ast.parse(out)
    compile(out, '<v4-gate-trace>', 'exec')
    return out

def atomic_write(target: Path, contents: bytes, mode: int) -> None:
    fd, tmp = tempfile.mkstemp(prefix='.zar-v4-gate-', suffix='.py', dir=str(target.parent))
    try:
        with os.fdopen(fd, 'wb') as out:
            out.write(contents); out.flush(); os.fsync(out.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, target)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=('status', 'dry-run', 'install', 'rollback'))
    p.add_argument('source', type=Path)
    args = p.parse_args()
    target = args.source.expanduser()
    if not target.is_file() or target.is_symlink():
        print('[refused] Missing or symlinked agent source; no changes', file=sys.stderr)
        return 2
    before = target.read_bytes()
    backups = target.parents[1] / 'data' / 'local' / 'patch-backups'
    manifest = backups / 'schema-focus-v4-gate-trace.json'
    if args.action == 'status':
        print('V4 gate trace:', 'installed' if TRACE_MARKER.encode() in before else 'not installed')
        return 0 if TRACE_MARKER.encode() in before else 1
    if args.action == 'rollback':
        if not manifest.is_file():
            print('[refused] Trace rollback manifest not found; no changes', file=sys.stderr)
            return 2
        try:
            state = json.loads(manifest.read_text(encoding='utf-8'))
            saved = Path(state['backup'])
            restored = saved.read_bytes()
            if (target.resolve() != Path(state['file']).resolve()
                or sha(before) != state['installed_sha256']
                or sha(restored) != state['original_sha256']):
                raise ValueError('source or backup changed; no changes')
            compile(restored.decode('utf-8'), str(target), 'exec')
        except (OSError, ValueError, KeyError, UnicodeDecodeError, TypeError) as exc:
            print('[refused] Unsafe rollback:', exc, file=sys.stderr)
            return 2
        atomic_write(target, restored, stat.S_IMODE(target.stat().st_mode))
        manifest.unlink()
        print('[restored] Trace removed; original V4.1 remains')
        return 0
    try:
        after = updated(before.decode('utf-8')).encode('utf-8')
    except (ValueError, SyntaxError, UnicodeDecodeError) as exc:
        print('[refused]', exc, file=sys.stderr)
        return 2
    if args.action == 'dry-run':
        print('[pass] Existing V4.1 helper recognized, AST compiles; no files changed')
        print('[state]', 'trace already installed' if before == after else 'trace applicable')
        return 0
    if before == after:
        print('[ready] Trace already installed')
        return 0
    if manifest.exists():
        print('[refused] Existing trace manifest present; no changes', file=sys.stderr)
        return 2
    backups.mkdir(parents=True, exist_ok=True)
    backup = backups / ('agent_loop.py.v4-gate-trace.' + datetime.now().strftime('%Y%m%d-%H%M%S-%f') + '.bak')
    shutil.copy2(target, backup)
    atomic_write(target, after, stat.S_IMODE(target.stat().st_mode))
    manifest.write_text(json.dumps({
        'file': str(target.resolve()), 'backup': str(backup.resolve()),
        'original_sha256': sha(before), 'installed_sha256': sha(after)
    }, indent=2) + '\n', encoding='utf-8')
    print('[installed] One V4 gate diagnostic log; NO routing behavior change')
    print('[backup]', backup)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
