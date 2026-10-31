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

