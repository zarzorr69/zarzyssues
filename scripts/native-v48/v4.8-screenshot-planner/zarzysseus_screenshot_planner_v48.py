#!/usr/bin/env python3
"""Zarzysseus V4.8: fail-closed, one-shot screenshot planning fallback.

The existing V4.6/4.7.1 source has already authenticated user intent,
confirmed successful navigation, gated caller scope/policy, and selected an
already offered screenshot schema. If its one-model proposal fails, this patch
constructs *arguments* (not an execution) from that schema and returns it to
Odysseus' normal native-tool conversion + approval + dispatcher path.

It never opens a browser, auto-approves a tool, changes the policy, or hides a
failure. It does not modify earlier successful multi-step pathways.
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

MARKER = '# ZARZYSSEUS_SCHEMA_SCREENSHOT_PLAN_V48'
REQUIRE = ('# ZARZYSSEUS_BOUNDED_SCREENSHOT_CONTINUATION_V46',
           '# ZARZYSSEUS_APPROVED_REPLAY_SCREENSHOT_V471',
           '# ZARZYSSEUS_BOUNDED_SNAPSHOT_CONTINUATION_V45')
CALL_NAME = 'mcp__builtin_browser__browser_take_screenshot'

# A conservative, audit-friendly fallback. Unknown schema constraints refuse.
HELPER = '''
# ZARZYSSEUS_SCHEMA_SCREENSHOT_PLAN_V48_HELPER
def _zar_shot_plan_v48(schema, full_page_requested=False, round_number=1):
    import json as _zar_json48
    from uuid import uuid4 as _zar_uuid4
    name = 'mcp__builtin_browser__browser_take_screenshot'
    if not isinstance(schema, dict) or (schema.get('function') or {}).get('name') != name:
        return []
    params = (schema.get('function') or {}).get('parameters')
    if not isinstance(params, dict) or params.get('type') != 'object':
        return []
    if any(k in params for k in ('oneOf','anyOf','allOf','not','if','then','else',
                                   'dependencies','dependentRequired', 'patternProperties',
                                   '$ref', 'unevaluatedProperties')):
        return []
    props = params.get('properties')
    required = params.get('required', [])
    if (not isinstance(props, dict) or not isinstance(required, list)
            or any(not isinstance(k,str) for k in required)
            or len(set(required)) != len(required)):
        return []
    allowed = {'type', 'scale', 'fullPage'}
    if any(k not in allowed or k not in props for k in required):
        return []
    # Generate only literals explicitly supported by the actual server schema;
    # never include filename, element, target, or untrusted page-derived input.
    desired = {'type': 'png', 'scale': 'css'}
    if 'fullPage' in props:
        desired['fullPage'] = bool(full_page_requested)
    elif full_page_requested:
        return []
    args = {}
    for key, value in desired.items():
        if key not in props:
            continue
        descriptor = props[key]
        if not isinstance(descriptor, dict):
            return []
        if any(k in descriptor for k in ('$ref','oneOf','anyOf','allOf','not','if','then','else','pattern')):
            return []
        kind = 'boolean' if key == 'fullPage' else 'string'
        if descriptor.get('type') not in (None, kind):
            return []
        if 'const' in descriptor and descriptor['const'] != value:
            return []
        if 'enum' in descriptor and (not isinstance(descriptor['enum'], list)
                                      or value not in descriptor['enum']):
            return []
        args[key] = value
    if not all(k in args for k in required):
        return []
    # Re-use V4.6's existing schema/parameter validator rather than loosen it.
    if not _zar_shot_args_valid_v46(args, schema, bool(full_page_requested)):
        return []
    return [{'id': 'zar_schema_screenshot_v48_' + _zar_uuid4().hex,
             'name': name,
             'arguments': _zar_json48.dumps(args, separators=(',', ':'))}]
'''

INJECT = '''                # ZARZYSSEUS_SCHEMA_SCREENSHOT_PLAN_V48
                # Only reached after V4.6's existing policy, scope, intent,
                # navigation-success and single-attempt checks permitted this.
                # The model failed to produce one valid native screenshot call.
                # This is a deterministic USER-REQUESTED proposal, not a model
                # response and never an execution. Normal Odysseus conversion,
                # approval and dispatch below remain the only execution path.
                if not _zar_proposals_v46:
                    _zar_proposals_v46 = _zar_shot_plan_v48(
                        _zar_shot_schema_v46,
                        full_page_requested=_zar_fullpage_v46,
                        round_number=round_num,
                    )
                    if _zar_proposals_v46:
                        logger.info('[zarzysseus-v48] explicit_user_screenshot_plan=True '
                                    'model_proposal_failed=True normal_dispatch_only=True')
                    else:
                        logger.warning('[zarzysseus-v48] unavailable_or_unknown_schema; '
                                       'no screenshot proposal')
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def check_anchors(src: str) -> int:
    for item in REQUIRE:
        if item not in src:
            raise ValueError('Missing prerequisite: '+item)
    tree = ast.parse(src)
    outer = [n for n in ast.walk(tree) if isinstance(n, ast.AsyncFunctionDef)
             and n.name=='stream_agent_loop']
    if len(outer) != 1:
        raise ValueError('Expected one stream_agent_loop')
    loop = outer[0]
    # Ensure the specific "if proposals" gate follows V4.6's model proposal.
    matches = [n for n in ast.walk(loop) if isinstance(n, ast.If)
               and isinstance(n.test, ast.Name) and n.test.id=='_zar_proposals_v46']
    if len(matches) != 1:
        raise ValueError('Expected one screenshot proposal branch')
    gate = matches[0]
    preceding = src.splitlines()
    context = '\n'.join(preceding[max(0,gate.lineno-17):gate.lineno-1])
    if ('_zar_shot_proposal_v46(' not in context
            or '_zar_shot_attempted_v46 = True' not in context
            or '[zarzysseus-v46]' not in context):
        raise ValueError('Screenshot branch no longer follows original V4.6 approval/policy gating')
    if not any(isinstance(n, (ast.For, ast.AsyncFor)) and isinstance(n.target,ast.Name)
               and n.target.id == 'round_num' and n.lineno < gate.lineno < n.end_lineno
               for n in ast.walk(loop)):
        raise ValueError('Screenshot proposal is outside agent round loop')
    helper = [n for n in tree.body if isinstance(n, ast.FunctionDef)
              and n.name=='_zar_shot_args_valid_v46']
    if len(helper) != 1:
        raise ValueError('Expected existing V4.6 argument validator')
    # Screenshot must be routed via _resolve_tool_blocks(), not called directly.
    nearby='\n'.join(preceding[gate.lineno-1:gate.lineno+19])
    if '_resolve_tool_blocks(' not in nearby:
        raise ValueError('Missing native-tool conversion after screenshot proposal')
    return gate.lineno


def patched_source(source: str) -> str:
    if MARKER in source:
        return source
    if not source.endswith('\n'):
        raise ValueError('Expected newline terminated agent source')
    gate_lineno = check_anchors(source)
    lines = source.splitlines(keepends=True)
    target_line=lines[gate_lineno-1]
    if target_line != '                if _zar_proposals_v46:\n':
        raise ValueError('Unexpected source indentation of V4.6 proposal branch')
    lines.insert(gate_lineno-1, INJECT)
    out = ''.join(lines) + '\n' + HELPER.lstrip('\n').rstrip('\n') + '\n'
    ast.parse(out)
    compile(out,'<zar-v48-agent-source>','exec')
    return out


def atomic_write(path: Path, data: bytes):
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix='.zar-v48-', suffix='.tmp')
    try:
        with os.fdopen(fd,'wb') as file:
            file.write(data);file.flush();os.fsync(file.fileno())
        os.chmod(tmp,stat.S_IMODE(path.stat().st_mode))
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)


def cli():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=('dry-run','install','status','rollback'))
    p.add_argument('source',type=Path)
    x=p.parse_args()
    path=x.source.expanduser()
    if path.is_symlink() or not path.is_file() or path.name != 'agent_loop.py':
        print('[refused] Expected regular agent_loop.py source',file=sys.stderr);return 2
    original=path.read_bytes()
    backup_root=path.parents[1]/'data'/'local'/'patch-backups'
    manifest=backup_root/'schema-screenshot-plan-v48.json'
    installed=MARKER.encode() in original
    if x.action=='status':
        print('V4.8 screenshot schema planner:', 'installed' if installed else 'not installed')
        print('Manifest:', 'present' if manifest.is_file() else 'absent')
        if installed and manifest.is_file():
            try:
                rec=json.loads(manifest.read_text('utf8'))
                if rec['file'] != str(path.resolve()) or rec['installed_sha256'] != sha(original):
                    print('[warning] Source changed after V4.8 install')
            except (ValueError,OSError,KeyError): print('[warning] Manifest unreadable')
        return 0 if installed else 1
    if x.action=='rollback':
        if not manifest.is_file():
            print('[refused] No V4.8 rollback manifest',file=sys.stderr);return 2
        try:
            rec=json.loads(manifest.read_text('utf8'))
            backup=Path(rec['backup']);saved=backup.read_bytes()
            if (rec['file'] != str(path.resolve()) or rec['installed_sha256'] != sha(original)
                    or rec['original_sha256'] != sha(saved)):
                raise ValueError('Source changed after install or backup mismatch')
            ast.parse(saved.decode('utf8'))
        except (KeyError,OSError,ValueError,SyntaxError,UnicodeError) as err:
            print('[refused] Unsafe rollback:',err,file=sys.stderr);return 2
        atomic_write(path,saved)
        manifest.unlink()
        print('[restored] Original pre-V4.8 agent source')
        return 0
    if installed and not manifest.is_file():
        print('[refused] V4.8 marker exists without manifest',file=sys.stderr);return 2
    try:
        proposed=patched_source(original.decode('utf8')).encode('utf8')
    except (ValueError,UnicodeError,SyntaxError) as err:
        print('[refused]',err,file=sys.stderr);return 2
    if x.action=='dry-run':
        print('[pass] V4.6/V4.7.1 guards, model proposal, AST, and dispatch path checked')
        print('[status]','already installed' if proposed==original else 'upgrade applicable')
        print('[note] No source changes or MCP calls')
        return 0
    if proposed==original:
        if not manifest.is_file():
            print('[refused] Manifest absent for existing V4.8',file=sys.stderr);return 2
        print('[ready] V4.8 already installed');return 0
    if manifest.exists():
        print('[refused] Stale V4.8 manifest',file=sys.stderr);return 2
    backup_root.mkdir(parents=True,exist_ok=True)
    backup=backup_root/('agent_loop.py.v48.'+datetime.now().strftime('%Y%m%d-%H%M%S-%f')+'.bak')
    shutil.copy2(path,backup);os.chmod(backup,0o600)
    atomic_write(path,proposed)
    manifest.write_text(json.dumps({'file':str(path.resolve()), 'backup':str(backup.resolve()),
                                    'original_sha256':sha(original),'installed_sha256':sha(proposed)},indent=2)+'\n')
    os.chmod(manifest,0o600)
    print('[installed] Schema-based screenshot proposal fallback under existing approvals')
    print('[backup]',backup)
    return 0

if __name__=='__main__':
    raise SystemExit(cli())
