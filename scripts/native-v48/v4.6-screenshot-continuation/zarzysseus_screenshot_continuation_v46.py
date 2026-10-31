#!/usr/bin/env python3
"""Zarzysseus V4.6: one guarded screenshot continuation after browser navigation.

Requires V4.5. For an explicit user-requested screenshot that stalls after
successful browser_navigate, asks the *model* for one structured screenshot call,
validates it against the offered MCP tool schema, then hands the proposal to
Odysseus' normal approval/dispatch path. Never executes or bypasses approvals.
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

MARKER = '# ZARZYSSEUS_BOUNDED_SCREENSHOT_CONTINUATION_V46'
ANCHOR = '        # ZARZYSSEUS_BOUNDED_SNAPSHOT_CONTINUATION_V45\n'
LOOP_ANCHOR = '    for round_num in range(1, max_rounds + 1):\n'
NEEDED = (
    'ZARZYSSEUS_BOUNDED_SNAPSHOT_CONTINUATION_V45',
    'ZARZYSSEUS_BROWSER_WORKFLOW_V43',
    'ZARZYSSEUS_TEXT_ONLY_SCREENSHOT_HANDOFF_V44',
    'ZARZYSSEUS_FORCED_ADDITIVE_FOCUS_V42',
)

HELPER = r'''
# ZARZYSSEUS_BOUNDED_SCREENSHOT_CONTINUATION_V46_HELPERS
# No execution/permission mutation here. All input data from browser is untrusted.
def _zar_shot_pending_v46(request, events, offered, *, attempted, round_num,
                          max_rounds, guide_only, force_answer, plan_mode,
                          doc_mode, relevant_tools, disabled_tools,
                          tool_policy):
    import re
    name = 'mcp__builtin_browser__browser_take_screenshot'
    nav = 'mcp__builtin_browser__browser_navigate'
    text = str(request or '')[:1800]
    if (attempted or round_num >= max_rounds or guide_only or force_answer
            or plan_mode or doc_mode or relevant_tools is not None
            or not isinstance(disabled_tools, (set, frozenset, list, tuple, dict))
            or name in disabled_tools):
        return None
    # Must be a user-authored web browsing request containing an explicit
    # capture intent. Neither assistant prose nor MCP page output can opt in.
    if not re.search(r'\b(?:https?://|www\.|[a-z0-9-]+\.(?:com|org|net|io|dev|edu|gov|app)\b)', text, re.I):
        return None
    if not re.search(r'\b(?:open|navigate|browse|visit|load|go to)\b', text, re.I):
        return None
    if not re.search(r'(?:\bscreen[ -]?shot\b|\bscreen[ -]?capture\b|\bcapture (?:a |the )?(?:page|screen|website)\b|\bshow me what (?:it|the page|the website|the site) looks like\b|\bshow (?:me )?(?:the |a )?(?:image|picture) of (?:the |this )?(?:page|site|website)\b)', text, re.I):
        return None
    if tool_policy is not None:
        if getattr(tool_policy, 'block_all_tool_calls', True):
            return None
        blocks = getattr(tool_policy, 'blocks', None)
        if not callable(blocks):
            return None
        try:
            if blocks(name):
                return None
        except (Exception,):
            return None
    if not isinstance(events, (list, tuple)):
        return None
    nav_success = False
    for event in events:
        if not isinstance(event, dict):
            continue
        if event.get('tool') == name:
            # An attempted screenshot, including a failure, must not be retried
            # or bypassed by this helper.
            return None
        if event.get('tool') == nav and event.get('exit_code') == 0 and not event.get('error'):
            message = str(event.get('output') or '')
            if not re.search(r'(?:^|\n)\s*(?:error|failed):', message, re.I):
                nav_success = True
    if not nav_success or not isinstance(offered, (list, tuple)):
        return None
    matches = [x for x in offered if isinstance(x, dict) and
               (x.get('function') or {}).get('name') == name]
    if len(matches) != 1:
        return None
    params = (matches[0].get('function') or {}).get('parameters')
    if not isinstance(params, dict) or params.get('type') != 'object':
        return None
    props = params.get('properties')
    required = params.get('required', [])
    if not isinstance(props, dict) or not isinstance(required, list):
        return None
    if any(x not in {'type','scale','fullPage'} for x in required):
        return None
    # If a connected MCP server does not advertise png/css, don't guess.
    for k, expected in (('type','png'),('scale','css')):
        if k not in props:
            if k in required:
                return None
            continue
        p = props[k]
        if not isinstance(p, dict) or p.get('type') not in (None,'string'):
            return None
        if isinstance(p.get('enum'),list) and expected not in p['enum']:
            return None
    if 'fullPage' in props and (not isinstance(props['fullPage'], dict)
                               or props['fullPage'].get('type') not in (None,'boolean')):
        return None
    if any(x not in props for x in required):
        return None
    return matches[0]


def _zar_shot_args_valid_v46(args, schema, full_page_requested):
    if not isinstance(args, dict) or not isinstance(schema, dict):
        return False
    params = (schema.get('function') or {}).get('parameters')
    if not isinstance(params,dict) or params.get('type') != 'object':
        return False
    props = params.get('properties')
    required = params.get('required', [])
    if not isinstance(props,dict) or not isinstance(required,list):
        return False
    if any(k not in {'type','scale','fullPage'} or k not in props for k in args):
        return False
    if not all(k in args for k in required):
        return False
    if 'type' in args and args['type'] != 'png':
        return False
    if 'scale' in args and args['scale'] != 'css':
        return False
    if 'fullPage' in args and not isinstance(args['fullPage'],bool):
        return False
    if full_page_requested and args.get('fullPage') is not True:
        return False
    for k,v in args.items():
        desc = props[k]
        if not isinstance(desc,dict):
            return False
        if k == 'fullPage' and desc.get('type') not in (None,'boolean'):
            return False
        if k != 'fullPage' and desc.get('type') not in (None,'string'):
            return False
        if isinstance(desc.get('enum'),list) and v not in desc['enum']:
            return False
    return True


async def _zar_shot_proposal_v46(endpoint_url, model, headers, schema, timeout,
                                 full_page_requested=False):
    import json
    name = 'mcp__builtin_browser__browser_take_screenshot'
    if (not isinstance(schema,dict) or
            (schema.get('function') or {}).get('name') != name):
        return []
    instruction = (
        'The user requested a screenshot of the browser page already opened. '
        'You have ONE tool. Return a real native function call, not prose or '
        'pseudo-calls. Use PNG, CSS scale, no filename, no target and no element. '
        + ('Take the FULL page; fullPage must be true.' if full_page_requested
           else 'Capture the current page; fullPage is optional.')
    )
    try:
        async for event in stream_llm(
            endpoint_url, model,
            [{'role':'system','content':'You are a one-action tool proposal assistant. Only use the single provided tool. Do not claim execution.'},
             {'role':'user','content':instruction}],
            temperature=0, max_tokens=512, headers=headers,
            timeout=min(max(int(timeout),10),60), tools=[schema],
            workload='foreground',
        ):
            if not isinstance(event,str) or not event.startswith('data: '):
                continue
            try:
                data = json.loads(event[6:].strip())
            except (ValueError,TypeError):
                continue
            if not isinstance(data,dict) or data.get('type') != 'tool_calls':
                continue
            for call in data.get('calls') or []:
                if not isinstance(call,dict) or call.get('name') != name:
                    continue
                raw = call.get('arguments','{}')
                try:
                    args = json.loads(raw) if isinstance(raw,str) else raw
                except (TypeError,ValueError):
                    continue
                if not _zar_shot_args_valid_v46(args,schema,full_page_requested):
                    continue
                identifier=call.get('id')
                if not isinstance(identifier,str) or not identifier:
                    identifier='zar_shot_v46'
                return [{'id':identifier,'name':name,'arguments':json.dumps(args,separators=(',',':'))}]
        return []
    except Exception as exc:
        logger.warning('[zarzysseus-v46] screenshot proposal unavailable: %s',type(exc).__name__)
        return []
'''

INJECT = r'''        # ZARZYSSEUS_BOUNDED_SCREENSHOT_CONTINUATION_V46
        # A bounded MODEL proposal after an authorized, successful navigation;
        # execution goes back through the normal Odysseus policy/approval path.
        if (not native_tool_calls and not tool_blocks and not _zar_shot_attempted_v46
                and _is_api_model):
            _zar_shot_schema_v46 = _zar_shot_pending_v46(
                _last_user, tool_events, all_tool_schemas,
                attempted=_zar_shot_attempted_v46,
                round_num=round_num, max_rounds=max_rounds,
                guide_only=guide_only, force_answer=_force_answer,
                plan_mode=plan_mode, doc_mode=_ody_doc_finetune_mode,
                relevant_tools=relevant_tools,
                disabled_tools=disabled_tools, tool_policy=tool_policy,
            )
            if _zar_shot_schema_v46 is not None:
                _zar_shot_attempted_v46 = True
                import re as _zar_re46
                _zar_fullpage_v46 = bool(_zar_re46.search(
                    r'\b(?:full[ -]?page|whole page|entire page)\b',
                    str(_last_user or ''), _zar_re46.I,
                ))
                logger.info('[zarzysseus-v46] pending_screenshot=True attempt=one_model_proposal round=%s',round_num)
                _zar_proposals_v46 = await _zar_shot_proposal_v46(
                    endpoint_url,model,headers,_zar_shot_schema_v46,
                    agent_stream_timeout,full_page_requested=_zar_fullpage_v46,
                )
                if _zar_proposals_v46:
                    _zar_blocks_v46, _zar_native_v46, _zar_converted_v46 = _resolve_tool_blocks(
                        round_response,_zar_proposals_v46,round_num,is_api_model=True,
                    )
                    if (_zar_blocks_v46 and _zar_native_v46
                            and len(_zar_blocks_v46) == 1
                            and getattr(_zar_blocks_v46[0],'tool_type',None)
                                == 'mcp__builtin_browser__browser_take_screenshot'):
                        native_tool_calls = _zar_proposals_v46
                        tool_blocks = _zar_blocks_v46
                        used_native = _zar_native_v46
                        converted_calls = _zar_converted_v46
                        logger.info('[zarzysseus-v46] screenshot_proposal_accepted=True normal_dispatch=True')
                    else:
                        logger.warning('[zarzysseus-v46] screenshot proposal native conversion rejected')
                else:
                    logger.warning('[zarzysseus-v46] no valid screenshot proposal; no execution')
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _in_agent_round(tree: ast.AST, lineno: int) -> bool:
    for node in ast.walk(tree):
        if isinstance(node,(ast.AsyncFunctionDef,ast.FunctionDef)) and node.name=='stream_agent_loop':
            for sub in ast.walk(node):
                if (isinstance(sub,(ast.For,ast.AsyncFor)) and isinstance(sub.target,ast.Name)
                    and sub.target.id=='round_num' and sub.lineno < lineno < sub.end_lineno):
                    return True
    return False


def patch_source(source: str) -> str:
    if MARKER in source:
        return source
    for marker in NEEDED:
        if marker not in source:
            raise ValueError('Required source marker missing: '+marker)
    if source.count(ANCHOR)!=1 or source.count(LOOP_ANCHOR)!=1:
        raise ValueError('Unknown loop/continuation structure; no changes')
    tree=ast.parse(source)
    anchor_line=source.count('\n',0,source.index(ANCHOR))+1
    if not _in_agent_round(tree,anchor_line):
        raise ValueError('Expected continuation inside stream_agent_loop round loop')
    preceding='\n'.join(source.splitlines()[max(0,anchor_line-120):anchor_line-1])
    if '_resolve_tool_blocks(' not in preceding:
        raise ValueError('Native tool conversion not found before continuation')
    if not source.endswith('\n'):
        raise ValueError('Expected newline-terminated source')
    updated=source.replace(LOOP_ANCHOR,'    _zar_shot_attempted_v46 = False\n'+LOOP_ANCHOR,1)
    updated=updated.replace(ANCHOR,INJECT+ANCHOR,1)
    updated+=HELPER.lstrip('\n').rstrip('\n')+'\n'
    ast.parse(updated)
    compile(updated,'<zarzysseus-v46>','exec')
    return updated


def atomic_write(path:Path,data:bytes,mode:int):
    fd,tmp=tempfile.mkstemp(dir=str(path.parent),prefix='.zar-v46-',suffix='.py')
    try:
        with os.fdopen(fd,'wb') as f:
            f.write(data);f.flush();os.fsync(f.fileno())
        os.chmod(tmp,mode)
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp):os.unlink(tmp)


def cli() -> int:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('action',choices=('dry-run','install','status','rollback'))
    p.add_argument('source',type=Path)
    args=p.parse_args()
    target=args.source.expanduser()
    if not target.is_file() or target.is_symlink() or target.name!='agent_loop.py':
        print('[refused] Expected regular agent_loop.py source',file=sys.stderr)
        return 2
    original=target.read_bytes()
    base=target.parents[1]/'data'/'local'/'patch-backups'
    manifest=base/'screenshot-continuation-v46.json'
    if args.action=='status':
        active=MARKER.encode() in original
        print('V4.6 screenshot continuation:', 'installed' if active else 'not installed')
        return 0 if active else 1
    if args.action=='rollback':
        if not manifest.is_file():
            print('[refused] V4.6 rollback manifest missing',file=sys.stderr)
            return 2
        try:
            rec=json.loads(manifest.read_text('utf8'))
            saved=Path(rec['backup']).read_bytes()
            if (str(target.resolve())!=rec['file'] or sha(original)!=rec['installed_sha256']
                or sha(saved)!=rec['original_sha256']):
                raise ValueError('Installed source or backup changed')
            compile(saved.decode('utf8'),str(target),'exec')
        except (OSError,ValueError,KeyError,SyntaxError,UnicodeError) as e:
            print('[refused] Unsafe rollback:',e,file=sys.stderr)
            return 2
        atomic_write(target,saved,stat.S_IMODE(target.stat().st_mode))
        manifest.unlink()
        print('[restored] Pre-V4.6 source restored')
        return 0
    try:
        patched=patch_source(original.decode('utf8')).encode('utf8')
    except (ValueError,SyntaxError,UnicodeError) as e:
        print('[refused]',e,file=sys.stderr)
        return 2
    if args.action=='dry-run':
        print('[pass] Required V4.2–V4.5 markers and AST structure; no files changed')
        print('[status]','already installed' if patched==original else 'upgrade applicable')
        return 0
    if patched==original:
        print('[ready] V4.6 already installed')
        return 0
    if manifest.exists():
        print('[refused] Existing V4.6 manifest needs reconciliation',file=sys.stderr)
        return 2
    base.mkdir(parents=True,exist_ok=True)
    backup=base/('agent_loop.py.v46.'+datetime.now().strftime('%Y%m%d-%H%M%S-%f')+'.bak')
    shutil.copy2(target,backup);os.chmod(backup,0o600)
    atomic_write(target,patched,stat.S_IMODE(target.stat().st_mode))
    manifest.write_text(json.dumps({'file':str(target.resolve()),'backup':str(backup.resolve()),
        'original_sha256':sha(original),'installed_sha256':sha(patched)},indent=2)+'\n',encoding='utf8')
    os.chmod(manifest,0o600)
    print('[installed] One bounded screenshot proposal after successful navigation')
    print('[backup]',backup)
    return 0

if __name__=='__main__':
    raise SystemExit(cli())
