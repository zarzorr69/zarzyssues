#!/usr/bin/env python3
"""Zarzysseus V8: schema-valid screenshot continuation without fabricated model calls.

Patches V6's approved navigation -> screenshot continuation to accept only
known safe mandatory screenshot parameters. Rejects unexpected mandatory
fields. Preserves Odysseus permissions/approvals, output handling, and rollback.

Usage: python zarzysseus_screenshot_schema_v8.py install|status|rollback|smoke CHECKOUT
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

MARKER = '# ZARZYSSEUS_SCREENSHOT_SCHEMA_ARGS_V8'
PREV_MARKER = '# ZARZYSSEUS_URL_WORKSPACE_ROUTING_V7'
PREVIOUS_BRANCH_START = '                if _zar_required_v6 == []:\n'
PREVIOUS_BRANCH_END = '            elif _zar_nav_ok_v6 and not _zar_shot_already_v6:\n'
NEW_BRANCH = '''                # ZARZYSSEUS_SCREENSHOT_SCHEMA_ARGS_V8
                # Some installed Playwright MCP adapters mark image format,
                # scale or fullPage as required although the API has defaults.
                # Supply safe values ONLY when their actual JSON schema agrees.
                # Never supply filename: leaving it unset lets Playwright return
                # the screenshot inline as image data instead of just a path.
                _zar_args_v8 = {}
                _zar_defaults_v8 = {"type": "png", "scale": "css", "fullPage": False}
                _zar_expected_types_v8 = {"type": "string", "scale": "string", "fullPage": "boolean"}
                _zar_properties_v8 = _zar_params_v6.get("properties", {}) if isinstance(_zar_params_v6, dict) else None
                _zar_invalid_v8 = not (
                    isinstance(_zar_required_v6, list)
                    and all(isinstance(k, str) for k in _zar_required_v6)
                    and isinstance(_zar_properties_v8, dict)
                )
                if not _zar_invalid_v8:
                    for _zar_field_v8 in _zar_required_v6:
                        if _zar_field_v8 not in _zar_defaults_v8:
                            _zar_invalid_v8 = True
                            break
                        _zar_prop_v8 = _zar_properties_v8.get(_zar_field_v8)
                        _zar_value_v8 = _zar_defaults_v8[_zar_field_v8]
                        if not isinstance(_zar_prop_v8, dict):
                            _zar_invalid_v8 = True
                            break
                        _zar_field_type_v8 = _zar_prop_v8.get("type")
                        if _zar_field_type_v8 not in (None, _zar_expected_types_v8[_zar_field_v8]):
                            _zar_invalid_v8 = True
                            break
                        _zar_enum_v8 = _zar_prop_v8.get("enum")
                        if _zar_enum_v8 is not None and (
                            not isinstance(_zar_enum_v8, list) or _zar_value_v8 not in _zar_enum_v8
                        ):
                            _zar_invalid_v8 = True
                            break
                        _zar_args_v8[_zar_field_v8] = _zar_value_v8
                if not _zar_invalid_v8:
                    _zar_explicit_call_v6 = [{
                        "id": "zarzysseus_explicit_screenshot_v8",
                        "name": _zar_shot_v6,
                        "arguments": json.dumps(_zar_args_v8, separators=(",", ":")),
                    }]
                    _zar_blocks_v6, _zar_native_v6, _zar_converted_v6 = _resolve_tool_blocks(
                        round_response, _zar_explicit_call_v6, round_num, is_api_model=True,
                    )
                    if len(_zar_blocks_v6) == 1 and _zar_native_v6 and _zar_blocks_v6[0].tool_type == _zar_shot_v6:
                        native_tool_calls = _zar_explicit_call_v6
                        tool_blocks = _zar_blocks_v6
                        used_native = _zar_native_v6
                        converted_calls = _zar_converted_v6
                        logger.info(
                            "[zarzysseus-agent-v8] queued schema-valid screenshot via upstream executor args=%s",
                            sorted(_zar_args_v8),
                        )
                    else:
                        logger.warning("[zarzysseus-agent-v8] screenshot converter refused; no action queued")
                else:
                    logger.warning(
                        "[zarzysseus-agent-v8] unsupported mandatory screenshot fields: %s",
                        _zar_required_v6,
                    )
'''


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def locations(root: Path):
    root = root.expanduser().resolve()
    b = root / 'data' / 'local' / 'patch-backups'
    return root / 'src' / 'agent_loop.py', b / 'agent-screenshot-schema-v8.before.py', b / 'agent-screenshot-schema-v8.json', b / 'agent-url-workspace-v7.json'


def patch_source(source: str) -> str:
    if MARKER in source:
        raise ValueError('V8 already installed')
    if PREV_MARKER not in source:
        raise ValueError('Install V7 before V8')
    if source.count(PREVIOUS_BRANCH_START) != 1 or source.count(PREVIOUS_BRANCH_END) != 1:
        raise ValueError('V6 screenshot branch changed; refusing unguarded patch')
    start = source.index(PREVIOUS_BRANCH_START)
    end = source.index(PREVIOUS_BRANCH_END)
    if end <= start or end - start > 6000 or '# ZARZYSSEUS_EXPLICIT_SCREENSHOT_CONTINUATION_V6' not in source[:start]:
        raise ValueError('Unexpected screenshot branch range')
    old_segment = source[start:end]
    if '_zar_explicit_call_v6' not in old_segment or 'screenshot schema requires arguments' not in old_segment:
        raise ValueError('Unexpected V6 screenshot branch body')
    patched = source[:start] + NEW_BRANCH + source[end:]
    ast.parse(patched)
    return patched


def choose_safe_arguments(required, properties):
    """Test oracle matching the deliberately conservative runtime logic."""
    defaults = {'type': 'png', 'scale': 'css', 'fullPage': False}
    types = {'type': 'string', 'scale': 'string', 'fullPage': 'boolean'}
    if not isinstance(required, list) or not all(isinstance(k, str) for k in required) or not isinstance(properties, dict):
        return None
    args = {}
    for field in required:
        if field not in defaults or not isinstance(properties.get(field), dict):
            return None
        prop = properties[field]
        if prop.get('type') not in (None, types[field]):
            return None
        enum = prop.get('enum')
        if enum is not None and (not isinstance(enum, list) or defaults[field] not in enum):
            return None
        args[field] = defaults[field]
    return args


def smoke(source: str) -> None:
    if MARKER not in source:
        source = patch_source(source)
    ast.parse(source)
    props = {'type': {'type':'string','enum':['png','jpeg']}, 'scale':{'type':'string','enum':['css','device']}, 'fullPage':{'type':'boolean'}, 'filename':{'type':'string'}}
    assert choose_safe_arguments([], props) == {}
    assert choose_safe_arguments(['type'], props) == {'type':'png'}
    assert choose_safe_arguments(['type','scale','fullPage'], props) == {'type':'png','scale':'css','fullPage':False}
    assert choose_safe_arguments(['filename'], props) is None
    assert choose_safe_arguments(['type'], {'type': {'type':'string','enum':['jpeg']}}) is None
    assert choose_safe_arguments(['type'], {'type': {'type':'integer'}}) is None
    assert choose_safe_arguments(['unexpected'], props) is None
    assert 'and _approved_result_injected' in source
    assert 'and bool(_zar_approved_browser_followup_v5)' in source
    assert 'and not _zar_shot_already_v6' in source
    assert 'and e.get("exit_code") == 0' in source
    assert '_resolve_tool_blocks(' in source
    assert '"filename":' not in NEW_BRANCH
    print('PASS: safe required screenshot fields -> schema-valid, no filename')
    print('PASS: unknown/unsafe mandatory fields are rejected')
    print('PASS: approved successful navigation, one-shot guard, upstream executor preserved')


def atomic_write(path: Path, data: bytes) -> None:
    fd, name = tempfile.mkstemp(prefix='.zar-v8-', dir=path.parent)
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


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('install','status','rollback','smoke'))
    parser.add_argument('checkout', nargs='?', default=str(Path.home() / 'odysseus'))
    args = parser.parse_args(argv)
    source, backup, manifest, prev_manifest = locations(Path(args.checkout))
    try:
        if not source.is_file():
            raise ValueError(f'Agent source missing: {source}')
        original = source.read_bytes()
        current = original.decode('utf-8')
        installed = MARKER in current
        if args.operation == 'status':
            print('V8 screenshot schema arguments:', 'installed' if installed else 'not installed')
            print('V8 backup manifest:', 'present' if manifest.is_file() else 'missing')
            if installed and (not manifest.is_file() or json.loads(manifest.read_text('utf-8')).get('installed_sha256') != digest(original)):
                raise ValueError('Installed V8 source differs from recorded digest')
            return 0 if installed else 1
        if args.operation == 'smoke':
            smoke(current)
            return 0
        if args.operation == 'install':
            if installed:
                if not manifest.is_file() or json.loads(manifest.read_text('utf-8')).get('installed_sha256') != digest(original):
                    raise ValueError('Existing V8 source was modified; installation refused')
                print('    [ready] V8 screenshot schema repair already installed')
                return 0
            if manifest.exists() or backup.exists():
                raise ValueError('Stale V8 manifest or backup; reconcile first')
            if not prev_manifest.is_file():
                raise ValueError('V7 backup manifest missing')
            prev = json.loads(prev_manifest.read_text('utf-8'))
            if digest(original) != prev.get('installed_sha256'):
                raise ValueError('Current V7 source differs from saved digest; refusing patch')
            patched = patch_source(current).encode('utf-8')
            smoke(patched.decode('utf-8'))
            backup.parent.mkdir(parents=True, exist_ok=True)
            backup.write_bytes(original)
            os.chmod(backup, 0o600)
            state = {'previous_sha256':digest(original), 'installed_sha256':digest(patched), 'source':str(source), 'backup':str(backup)}
            try:
                atomic_write(source, patched)
                manifest.write_text(json.dumps(state, indent=2) + '\n', encoding='utf-8')
                os.chmod(manifest, 0o600)
            except Exception:
                if digest(source.read_bytes()) == digest(patched):
                    atomic_write(source, original)
                raise
            print('Installed V8 schema-aware screenshot continuation (approvals unchanged)')
            print('Backup:', backup)
            return 0
        if not installed or not manifest.is_file() or not backup.is_file():
            raise ValueError('V8 source/manifest/backup required for rollback')
        state = json.loads(manifest.read_text('utf-8'))
        if digest(original) != state.get('installed_sha256'):
            raise ValueError('Current source was edited since V8 install; rollback refused')
        old = backup.read_bytes()
        if digest(old) != state.get('previous_sha256'):
            raise ValueError('V8 backup digest mismatch')
        atomic_write(source, old)
        manifest.unlink()
        backup.unlink()
        print('V8 rolled back to exact V7 source')
        return 0
    except (OSError, ValueError, AssertionError, SyntaxError, UnicodeError, KeyError, json.JSONDecodeError) as e:
        print('ERROR:', e, file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
