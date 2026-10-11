#!/usr/bin/env python3
"""Zarzysseus V7: treat an HTTP(S) URL as web content, never a workspace path.

The installed upstream Odysseus _looks_like_workspace_coding_request() matched
`//example.com` in `https://example.com` as a Unix path. With a workspace set,
that activated Terminus-only routing and stripped Playwright browser MCP tools.
This patch changes just the workspace detector; it does not grant any tool,
change enabled/disabled MCP settings, or override approval/security decisions.
"""
from __future__ import annotations
import argparse
import ast
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

MARKER = '# ZARZYSSEUS_URL_WORKSPACE_ROUTING_V7'
PREV_MARKER = '# ZARZYSSEUS_EXPLICIT_SCREENSHOT_CONTINUATION_V6'
FUNCTION_ANCHOR = 'def _looks_like_workspace_coding_request(text: str) -> bool:'
OLD_RETURN = '    return bool(_WORKSPACE_CODE_ACTION_RE.search(text) and _WORKSPACE_CODE_TARGET_RE.search(text))'
NEW_RETURN = '''    # ZARZYSSEUS_URL_WORKSPACE_ROUTING_V7
    # URLs are web resources, not local /paths. The upstream path regex can
    # match //example.com inside https://example.com and incorrectly replace
    # the browser toolset with workspace/terminal tools when a workspace exists.
    # Preserve normal mixed URL + genuine repo/file tasks (they still match).
    _zar_non_url_targets_v7 = re.sub(
        r"(?i)\\b(?:https?://|www\\.)[^\\s\\\"'<>`]+", " ", text
    )
    return bool(
        _WORKSPACE_CODE_ACTION_RE.search(_zar_non_url_targets_v7)
        and _WORKSPACE_CODE_TARGET_RE.search(_zar_non_url_targets_v7)
    )'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def locations(root: Path):
    root = root.expanduser().resolve()
    b = root / 'data' / 'local' / 'patch-backups'
    return (root / 'src' / 'agent_loop.py', b / 'agent-url-workspace-v7.before.py',
            b / 'agent-url-workspace-v7.json', b / 'agent-explicit-screenshot-v6.json')


def patch_source(source: str) -> str:
    if MARKER in source:
        raise ValueError('V7 is already installed')
    if PREV_MARKER not in source:
        raise ValueError('Install V6 before V7')
    if source.count(FUNCTION_ANCHOR) != 1 or source.count(OLD_RETURN) != 1:
        raise ValueError('Upstream workspace detector changed; refuse unguarded patch')
    fn = source.index(FUNCTION_ANCHOR)
    end = source.find('\ndef ', fn + len(FUNCTION_ANCHOR))
    if end == -1:
        raise ValueError('Cannot safely locate detector end')
    if OLD_RETURN not in source[fn:end]:
        raise ValueError('Expected return not within workspace detector')
    patched = source.replace(OLD_RETURN, NEW_RETURN, 1)
    ast.parse(patched)
    return patched


def atomic_write(path: Path, data: bytes) -> None:
    fd, name = tempfile.mkstemp(prefix='.zar-v7-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(name, path.stat().st_mode & 0o777)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def smoke(source: str) -> None:
    tree = ast.parse(source)
    required = ['_looks_like_workspace_coding_request']
    regexes = ['_WORKSPACE_CODE_ACTION_RE', '_WORKSPACE_CODE_TARGET_RE']
    nodes = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
             and n.name in required]
    assert len(nodes) == 1
    assign_nodes = [n for n in tree.body if isinstance(n, ast.Assign) and any(
        getattr(t, 'id', '') in regexes for t in n.targets)]
    assert len(assign_nodes) == 2
    import re
    env = {'re': re}
    exec(compile(ast.Module(body=assign_nodes + nodes, type_ignores=[]), 'agent_loop.py', 'exec'), env)
    detector = env[required[0]]
    cases = [
        ('Open https://example.com, take a screenshot, display it here, and describe the page.', False),
        ('Open https://example.com using the browser, take a screenshot', False),
        ('Visit https://github.com and take a screenshot of the UI', False),
        ('Open www.example.com in the browser and screenshot it', False),
        ('Open https://example.com/docs/guide with Playwright', False),
        ('Open /etc/hosts and inspect the file', True),
        ('Read ~/project/file.py and fix it', True),
        ('Fix this project bug', True),
        ('Open https://example.com and edit my project file', True),
        ('Inspect this workspace repo', True),
    ]
    for request, expected in cases:
        got = bool(detector(request))
        if got != expected:
            raise AssertionError(f'{request!r}: got workspace={got}; expected {expected}')
    print('PASS: browser URLs no longer trigger Terminus workspace mode')
    print('PASS: local files, repo edits, mixed web+file tasks retain workspace routing')


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('operation', choices=('install', 'status', 'rollback', 'smoke'))
    ap.add_argument('checkout', nargs='?', default=str(Path.home() / 'odysseus'))
    args = ap.parse_args(argv)
    source, backup, manifest, prev_manifest = locations(Path(args.checkout))
    try:
        if not source.is_file():
            raise ValueError(f'Agent source missing: {source}')
        original = source.read_bytes()
        current = original.decode('utf-8')
        installed = MARKER in current
        if args.operation == 'status':
            print('V7 URL/workspace routing fix:', 'installed' if installed else 'not installed')
            print('V7 backup manifest:', 'present' if manifest.exists() else 'missing')
            if installed:
                if not manifest.is_file() or json.loads(manifest.read_text('utf-8')).get('installed_sha256') != digest(original):
                    raise ValueError('Installed V7 differs from saved checksum')
            return 0 if installed else 1
        if args.operation == 'smoke':
            smoke(current if installed else patch_source(current))
            return 0
        if args.operation == 'install':
            if installed:
                if not manifest.is_file() or json.loads(manifest.read_text('utf-8')).get('installed_sha256') != digest(original):
                    raise ValueError('V7 modified since installation; refusing to overwrite')
                print('    [ready] V7 URL/workspace routing fix already installed')
                return 0
            if backup.exists() or manifest.exists():
                raise ValueError('Stale V7 manifest or backup; reconcile before installation')
            if not prev_manifest.is_file():
                raise ValueError('V6 backup manifest missing; refusing unmanaged upgrade')
            prev = json.loads(prev_manifest.read_text('utf-8'))
            if prev.get('installed_sha256') != digest(original):
                raise ValueError('Current agent source differs from recorded V6; refusing patch')
            patched = patch_source(current).encode('utf-8')
            smoke(patched.decode('utf-8'))
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(original)
            os.chmod(backup, 0o600)
            state = {'previous_sha256': digest(original), 'installed_sha256': digest(patched),
                     'source': str(source), 'backup': str(backup)}
            try:
                atomic_write(source, patched)
                manifest.write_text(json.dumps(state, indent=2) + '\n', encoding='utf-8')
                os.chmod(manifest, 0o600)
            except Exception:
                if digest(source.read_bytes()) == digest(patched):
                    atomic_write(source, original)
                raise
            print('Installed V7 URL-as-path routing repair (tool policy and approvals unchanged)')
            print('Backup:', backup)
            return 0
        if not installed or not manifest.is_file() or not backup.is_file():
            raise ValueError('V7 source/manifest/backup required for rollback')
        state = json.loads(manifest.read_text('utf-8'))
        if digest(original) != state.get('installed_sha256'):
            raise ValueError('Installed V7 source was edited; refusing rollback')
        old = backup.read_bytes()
        if digest(old) != state.get('previous_sha256'):
            raise ValueError('V7 backup digest mismatch')
        atomic_write(source, old)
        manifest.unlink()
        backup.unlink()
        print('V7 rolled back to exact V6 source')
        return 0
    except (OSError, ValueError, AssertionError, SyntaxError, UnicodeError, KeyError, json.JSONDecodeError) as e:
        print('ERROR:', e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
