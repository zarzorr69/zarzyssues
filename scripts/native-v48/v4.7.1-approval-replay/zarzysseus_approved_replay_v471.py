#!/usr/bin/env python3
"""Guarded V4.7.1 repair for V4.6 screenshot continuation during approval replay.

Targets only _zar_shot_pending_v46's exact 'relevant_tools is not None'
permission check and its one call from stream_agent_loop. All other guards,
policy checks, original approval dispatch, and screenshot schema validation stay.

Usage: python3 zarzysseus_approved_replay_v471.py dry-run|install|status|rollback /path/to/src/agent_loop.py
"""
from __future__ import annotations

import argparse
import ast
from datetime import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile

MARKER = '# ZARZYSSEUS_APPROVED_REPLAY_SCREENSHOT_V471'
PREREQUISITES = (
    '# ZARZYSSEUS_BOUNDED_SCREENSHOT_CONTINUATION_V46',
    '# ZARZYSSEUS_BOUNDED_SNAPSHOT_CONTINUATION_V45',
    '# ZARZYSSEUS_TEXT_ONLY_SCREENSHOT_HANDOFF_V44',
)
TARGET = 'mcp__builtin_browser__browser_take_screenshot'


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _span(source: str, node: ast.AST) -> tuple[int, int]:
    # AST columns are UTF-8 byte offsets; the full source may include Unicode.
    lines = source.encode('utf-8').splitlines(keepends=True)
    if any(getattr(node, k, None) is None for k in ('lineno', 'col_offset', 'end_lineno', 'end_col_offset')):
        raise ValueError('Missing AST source offsets')
    start = sum(map(len, lines[:node.lineno - 1])) + node.col_offset
    end = sum(map(len, lines[:node.end_lineno - 1])) + node.end_col_offset
    return start, end


def _is_none_check(node: ast.AST) -> bool:
    return (isinstance(node, ast.Compare) and isinstance(node.left, ast.Name)
            and node.left.id == 'relevant_tools' and len(node.ops) == 1
            and isinstance(node.ops[0], ast.IsNot)
            and len(node.comparators) == 1
            and isinstance(node.comparators[0], ast.Constant)
            and node.comparators[0].value is None)


def _contains_return_none(node: ast.If) -> bool:
    return len(node.body) == 1 and isinstance(node.body[0], ast.Return) and (
        node.body[0].value is None or
        isinstance(node.body[0].value, ast.Constant) and node.body[0].value.value is None
    )


def _find_guard(helper: ast.FunctionDef) -> ast.Compare:
    candidates = []
    for branch in ast.walk(helper):
        if (isinstance(branch, ast.If) and isinstance(branch.test, ast.BoolOp)
                and isinstance(branch.test.op, ast.Or) and _contains_return_none(branch)):
            values = branch.test.values
            items = [node for node in values if _is_none_check(node)]
            if not items:
                continue
            if len(items) != 1:
                raise ValueError('Ambiguous screenshot caller-scope guard')
            # The original safety guard must still be present; we replace only
            # the explicit-scope check and leave every sibling restriction intact.
            text = [ast.unparse(v) for v in values]
            required = ('attempted', 'round_num >= max_rounds', 'guide_only',
                        'force_answer', 'plan_mode', 'doc_mode',
                        'not isinstance(disabled_tools, (set, frozenset, list, tuple, dict))',
                        'name in disabled_tools')
            if not all(item in text for item in required):
                raise ValueError('V4.6 safety guard changed; refusing patch')
            candidates.append(items[0])
    if len(candidates) != 1:
        raise ValueError('Unknown V4.6 relevant_tools guard; expected one safety-checked AST expression')
    return candidates[0]


def _find_call(round_func: ast.AsyncFunctionDef) -> ast.Call:
    matches = [node for node in ast.walk(round_func)
               if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
               and node.func.id == '_zar_shot_pending_v46']
    if len(matches) != 1:
        raise ValueError('Unknown V4.6 proposal call layout; expected one helper call')
    call = matches[0]
    keywords = {kw.arg: kw.value for kw in call.keywords}
    required_kw = ('relevant_tools', 'disabled_tools', 'tool_policy')
    if not all(k in keywords and isinstance(keywords[k], ast.Name) and keywords[k].id == k for k in required_kw):
        raise ValueError('V4.6 permission forwarding changed')
    if 'approval_replay' in keywords:
        raise ValueError('Approval replay already supplied under another patch layout')
    return call


def patch_source(source: str) -> str:
    if MARKER in source:
        return source
    if '# ZARZYSSEUS_APPROVED_REPLAY_SCREENSHOT_V47' in source:
        raise ValueError('V4.7 already present; do not layer V4.7.1')
    if not source.endswith('\n'):
        raise ValueError('Source must end in a newline')
    for item in PREREQUISITES:
        if item not in source:
            raise ValueError('Missing prerequisite ' + item)
    tree = ast.parse(source)
    helpers = [n for n in tree.body if isinstance(n, ast.FunctionDef)
               and n.name == '_zar_shot_pending_v46']
    loops = [n for n in ast.walk(tree) if isinstance(n, ast.AsyncFunctionDef)
             and n.name == 'stream_agent_loop']
    if len(helpers) != 1 or len(loops) != 1:
        raise ValueError('Unknown V4.6 helper/agent function structure')
    helper, loop = helpers[0], loops[0]
    arg_names = [arg.arg for arg in helper.args.kwonlyargs]
    if 'tool_policy' not in arg_names or 'approval_replay' in arg_names:
        raise ValueError('V4.6 helper keyword signature changed')
    if 'exact_approval' not in [arg.arg for arg in loop.args.args + loop.args.kwonlyargs]:
        raise ValueError('Missing exact_approval input on agent runtime')
    guard = _find_guard(helper)
    call = _find_call(loop)

    b = source.encode('utf-8')
    patches = []
    # AST-based position matching (not fragile multiline source.substring count).
    guard_start, guard_end = _span(source, guard)
    guard_text = b[guard_start:guard_end].decode('utf8')
    if ''.join(guard_text.split()) != 'relevant_toolsisnotNone':
        raise ValueError('Caller-scope guard contains unexpected source; refuse')
    replacement = ('(relevant_tools is not None and not ('
                   'approval_replay and isinstance(relevant_tools, (set, frozenset, list, tuple)) '
                   'and name in relevant_tools))')
    patches.append((guard_start, guard_end, replacement.encode()))

    # Insert a keyword-only parameter directly after the existing last kwonly arg.
    policy_arg = next(arg for arg in helper.args.kwonlyargs if arg.arg == 'tool_policy')
    ps, pe = _span(source, policy_arg)
    if b[ps:pe] != b'tool_policy' or arg_names[-1] != 'tool_policy':
        raise ValueError('Helper last keyword parameter not recognized')
    patches.append((pe, pe, b', approval_replay=False'))

    # The call must be inside the normal for-rounds loop; no independent tool path.
    in_round = any(isinstance(n, (ast.For, ast.AsyncFor)) and
                   isinstance(n.target, ast.Name) and n.target.id == 'round_num'
                   and n.lineno < call.lineno <= call.end_lineno < n.end_lineno
                   for n in ast.walk(loop))
    if not in_round:
        raise ValueError('V4.6 helper call no longer within round dispatch')
    cs, ce = _span(source, call)
    if b[ce - 1:ce] != b')':
        raise ValueError('Unable to find expected call closing parenthesis')
    # Preserve tool-policy keyword and insert immediately before standalone ')'.
    close_line = b[:ce - 1].rsplit(b'\n', 1)[-1]
    if close_line.strip():
        raise ValueError('Expected multiline V4.6 call; refusing unknown formatting')
    original_call_lines = b[cs:ce].decode('utf8').splitlines()
    policy_line = next((line for line in original_call_lines if 'tool_policy=tool_policy' in line), None)
    if policy_line is None or not policy_line.rstrip().endswith(','):
        raise ValueError('Unknown final tool_policy keyword layout')
    indentation = re.match(r'[ \t]*', policy_line).group(0)
    patches.append((ce - 1 - len(close_line), ce - 1 - len(close_line),
                    (indentation + 'approval_replay=exact_approval is not None,\n').encode()))
    # Marker is attached to the precise helper call; never to permission decisions.
    assignments = [node for node in ast.walk(loop) if isinstance(node, ast.Assign) and node.value is call]
    if len(assignments) != 1:
        raise ValueError('Expected screenshot helper to be assigned exactly once')
    assignment_start, _ = _span(source, assignments[0])
    marker_line = b[:assignment_start].rsplit(b'\n', 1)[-1]
    if marker_line.strip():
        raise ValueError('Expected screenshot assignment on its own line')
    patches.append((assignment_start - len(marker_line), assignment_start - len(marker_line),
                    marker_line + MARKER.encode() + b'\n'))

    for start, end, content in sorted(patches, key=lambda item:item[0], reverse=True):
        b = b[:start] + content + b[end:]
    updated = b.decode('utf8')
    ast.parse(updated)
    compile(updated, '<zarzysseus-v471>', 'exec')
    return updated


def atomic_write(file: Path, content: bytes, mode: int) -> None:
    fd, name = tempfile.mkstemp(dir=str(file.parent), prefix='.zar-v471-', suffix='.tmp')
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(content)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(name, mode)
        os.replace(name, file)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def cli() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=('dry-run', 'install', 'status', 'rollback'))
    p.add_argument('source', type=Path)
    x = p.parse_args()
    file = x.source.expanduser()
    if file.is_symlink() or not file.is_file() or file.name != 'agent_loop.py':
        print('[refused] Expected a regular agent_loop.py', file=sys.stderr)
        return 2
    old = file.read_bytes()
    backups = file.parents[1]/'data'/'local'/'patch-backups'
    manifest = backups/'approved-replay-screenshot-v471.json'
    if x.action == 'status':
        installed = MARKER.encode() in old
        print('V4.7.1 approval replay screenshot:', 'installed' if installed else 'not installed')
        print('Manifest:', 'present' if manifest.exists() else 'absent')
        if installed and manifest.exists():
            try:
                record = json.loads(manifest.read_text())
                if record['file'] != str(file.resolve()) or sha(old) != record['installed_sha256']:
                    print('[warning] Agent source changed after V4.7.1 installation')
            except (OSError, KeyError, ValueError):
                print('[warning] Manifest unreadable')
        return 0 if installed else 1
    if x.action == 'rollback':
        if not manifest.is_file():
            print('[refused] V4.7.1 rollback manifest missing', file=sys.stderr)
            return 2
        try:
            rec = json.loads(manifest.read_text())
            saved = Path(rec['backup']).read_bytes()
            if (rec['file'] != str(file.resolve()) or sha(old) != rec['installed_sha256']
                    or sha(saved) != rec['original_sha256']):
                raise ValueError('File and backup digest mismatch')
            ast.parse(saved.decode('utf8'))
        except (OSError, KeyError, ValueError, UnicodeError, SyntaxError) as exc:
            print('[refused] Unsafe rollback:', exc, file=sys.stderr)
            return 2
        atomic_write(file, saved, stat.S_IMODE(file.stat().st_mode))
        manifest.unlink()
        print('[restored] Exact pre-V4.7.1 agent source')
        return 0
    try:
        updated = patch_source(old.decode('utf8')).encode('utf8')
    except (ValueError, UnicodeError, SyntaxError) as exc:
        print('[refused]', exc, file=sys.stderr)
        return 2
    if x.action == 'dry-run':
        print('[pass] V4.6 helper and scoped call checked with AST; no file changes')
        print('[status]', 'already installed' if updated == old else 'upgrade applicable')
        return 0
    if updated == old:
        print('[ready] V4.7.1 already installed')
        return 0
    if manifest.exists():
        print('[refused] Stale V4.7.1 manifest; reconcile first', file=sys.stderr)
        return 2
    backups.mkdir(parents=True, exist_ok=True)
    backup = backups/('agent_loop.py.v471.'+datetime.now().strftime('%Y%m%d-%H%M%S-%f')+'.bak')
    shutil.copy2(file, backup)
    os.chmod(backup, 0o600)
    atomic_write(file, updated, stat.S_IMODE(file.stat().st_mode))
    manifest.write_text(json.dumps({'file': str(file.resolve()), 'backup': str(backup.resolve()),
                                    'original_sha256': sha(old), 'installed_sha256': sha(updated)},indent=2)+'\n')
    os.chmod(manifest, 0o600)
    print('[installed] V4.7.1 approved-replay screenshot permission correction')
    print('[backup]', backup)
    return 0


if __name__ == '__main__':
    raise SystemExit(cli())
