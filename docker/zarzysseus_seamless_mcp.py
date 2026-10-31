#!/usr/bin/env python3
"""Source-guarded MCP relevance routing for an existing Odysseus agent_loop.py.

No MCP server installation, forced calls, policy changes, or credential access.
Only currently offered and enabled schemas can be selected. Chat history is
used for routing short follow-ups, never for granting permission.
"""
from __future__ import annotations

import argparse
import ast
import datetime as dt
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile

MARKER = "# ZARZYSSEUS_SEAMLESS_MCP_V1"
CONTEXT_MARKER = "# ZARZYSSEUS_CONTEXT_CONTINUITY_V2"
DOMAIN_MARKER = "# ZARZYSSEUS_MCP_BARE_DOMAIN_V3"
HELPER_ANCHOR = "    def _filter_route_tool_schemas(schemas):\n"
RELEVANCE_ANCHOR = '        route_relevant_tools = route_state["relevant_tools"]\n'
LEGACY_ANCHOR = (
    "        wants_mcp = any(keyword in _last_user.lower() for keyword in _MCP_KEYWORDS)\n"
    "        schemas = route_mcp_schemas if wants_mcp and route_mcp_schemas else []\n"
)
QWEN_ANCHOR = '                _zar_text = _last_user or ""\n'

# Match natural task descriptions, not magic /skill names.
DOMAINS = {
    "browser": (
        r"https?://|www\.|(?<![\w@])(?:[a-z0-9-]+\.)+(?:com|org|net|io|dev|ai|edu|gov|co|info|app|me|xyz|uk|eg)(?=[/:?#\s]|$)|\b(?:browser|website|webpage|navigate|screenshot|"
        r"open (?:the |a )?site|click (?:on |the )?(?:link|button)|visit (?:the |a )?site)\b",
        ("browser", "playwright", "chromium"),
    ),
    "github": (
        r"\b(?:github|gitlab|pull request|merge request|commit|repository|"
        r"repo issue|github issue|review (?:the |a )?pr)\b",
        ("github", "gitlab"),
    ),
    "email": (
        r"\b(?:email|e-mail|gmail|inbox|mailbox|send (?:a |an )?message|"
        r"reply to (?:the |an? )?email)\b",
        ("gmail", "email", "outlook", "mail"),
    ),
    "calendar": (
        r"\b(?:calendar|meeting|appointment|invite|schedule a meeting|"
        r"book a meeting)\b",
        ("calendar",),
    ),
    "cloud_files": (
        r"\b(?:google drive|onedrive|dropbox|sharepoint|box\.com)\b",
        ("drive", "dropbox", "onedrive", "sharepoint", "box"),
    ),
}
FOLLOWUP = re.compile(
    r"^(?:and\b|also\b|now\b|then\b|yes\b|sure\b|go ahead\b|"
    r"do it\b|continue\b|same\b|what about\b|can you\b|could you\b|"
    r"(?:take )?screenshot\b|(?:click|open|show|send|reply|save) (?:it|that|there)\b)",
    re.I,
)
NEGATE = re.compile(r"^\s*(?:no\b|stop\b|cancel\b|don't\b|do not\b|never\b)", re.I)
WORD = re.compile(r"[a-z0-9]+")


def contextual_request(latest: str, messages: object) -> str:
    """Small, user-only conversation window for *tool relevance*, not authorization.

    A brief continuation can refer to several prior turns ("open URL" ->
    "screenshot it" -> "CSS is fine"). Never concatenate assistant responses
    or untrusted tool/page text into the user's authorization.
    """
    current = str(latest or "")[:1400]
    followup = bool(FOLLOWUP.search(current.strip())) or bool(re.match(
        r"^(?:css|device|default|fine|okay|ok|yes|yep|sure|same|"
        r"do that|that works|sounds good|go ahead)\b",
        current.strip(), re.I,
    ))
    if (len(current.strip()) > 150 or not followup
            or NEGATE.search(current.strip()) or not isinstance(messages, (list, tuple))):
        return current
    previous = [
        m["content"].strip() for m in messages[-36:]
        if isinstance(m, dict) and m.get("role") == "user"
        and isinstance(m.get("content"), str) and m["content"].strip()
    ]
    if previous and previous[-1] == current.strip():
        previous.pop()
    # Three prior user turns, capped to 1800 characters. Do not carry stale
    # instructions from an unrelated chat/session (messages is request-local).
    prior = previous[-3:]
    if not prior:
        return current
    return "Previous user requests:\n" + "\n".join(x[-580:] for x in prior)[-1800:] + "\nCurrent request: " + current


def relevant_memory_tools(latest: str, messages: object) -> set[str]:
    """Offer built-in recall tools, never execute reads/writes or save memory."""
    text = contextual_request(latest, messages).lower()
    if NEGATE.search(str(latest or "")):
        return set()
    tools = set()
    if re.search(
        r"\b(?:last time|previous chats?|prior chats?|past chats?|"
        r"earlier conversation|we (?:discussed|talked about|worked on)|"
        r"from (?:our|my) (?:chats?|conversation)|"
        r"what (?:did|have) (?:i|we) (?:say|do|discuss)|"
        r"as (?:we|i) (?:said|discussed) before|"
        r"continue (?:our|the) (?:project|work)|"
        r"what (?:do|did) you remember about)\b",
        text,
    ):
        tools.add("search_chats")
    if re.search(
        r"\b(?:remember (?:this|that|my|our)|save (?:this|that|my) (?:fact|preference|memory)|"
        r"what do you remember|my saved memor(?:y|ies)|"
        r"from (?:your|saved) memor(?:y|ies)|"
        r"keep (?:this|that) in mind)\b",
        text,
    ):
        tools.add("manage_memory")
    return tools


def select_mcp_schemas(latest: str, messages: object, offered: object, cap: int = 12) -> list[dict]:
    if not isinstance(offered, (tuple, list)) or not latest:
        return []
    context = contextual_request(latest, messages).lower()
    domains = {
        domain for domain, (pattern, _) in DOMAINS.items()
        if re.search(pattern, context, re.I)
    }
    if not domains:
        return []
    tokens = set(WORD.findall(context)) - {"the", "for", "and", "with", "that", "this", "from"}
    ranked = []
    for idx, schema in enumerate(offered):
        if not isinstance(schema, dict):
            continue
        function = schema.get("function")
        function = function if isinstance(function, dict) else {}
        name = str(function.get("name") or schema.get("name") or "")
        if not name.startswith("mcp__"):
            continue
        name_l = name.lower()
        if any(part in name_l for part in ("unsafe", "eval", "execute_javascript")):
            continue
        parts = name_l.split("__")
        server = parts[1] if len(parts) >= 3 else ""
        if not any(
            domain in domains and any(key in server for key in servers)
            for domain, (_, servers) in DOMAINS.items()
        ):
            continue
        description = str(function.get("description") or "").lower()
        tool_words = set(WORD.findall(name_l.replace("__", " ") + " " + description[:350]))
        score = len(tokens & tool_words)
        if "screenshot" in context and "screenshot" in name_l:
            score += 6
        if "navigate" in context and "navigate" in name_l:
            score += 5
        if "send" in context and any(x in name_l for x in ("send", "create_draft")):
            score += 4
        if "issue" in context and "issue" in name_l:
            score += 4
        ranked.append((-score, idx, schema))
    ranked.sort(key=lambda row: (row[0], row[1]))
    return [schema for _, _, schema in ranked[:cap]]


# Installed as a nested helper so it needs no import path inside the container.
RUNTIME_HELPER = '''
    # ZARZYSSEUS_SEAMLESS_MCP_V1
    # ZARZYSSEUS_CONTEXT_CONTINUITY_V2
    def _zar_seamless_user_context(text, recent_messages):
        import re as _re
        _current = str(text or "")[:1400].strip()
        if not isinstance(recent_messages, (list, tuple)):
            return _current
        _follow = len(_current) <= 150 and bool(_re.search(
            r"^(?:and|also|now|then|yes|sure|go ahead|do it|continue|"
            r"same|what about|can you|could you|screenshot|click|open|send|"
            r"css|device|default|fine|okay|ok|that works|do that)\\b",
            _current, _re.I
        ))
        _negative = _re.search(r"^(?:no|stop|cancel|don't|do not|never)\\b",
                               _current, _re.I)
        if not _follow or _negative:
            return _current
        _users = [
            m["content"].strip() for m in recent_messages[-36:]
            if isinstance(m, dict) and m.get("role") == "user"
            and isinstance(m.get("content"), str) and m["content"].strip()
        ]
        if _users and _users[-1] == _current:
            _users.pop()
        _prior = _users[-3:]
        if not _prior:
            return _current
        return ("Previous user requests:\\n"
                + "\\n".join(u[-580:] for u in _prior)[-1800:]
                + "\\nCurrent request: " + _current)

    def _zar_seamless_memory_names(text, recent_messages):
        import re as _re
        _latest = str(text or "").strip().lower()
        if _re.search(r"^(?:no|don't|do not|never|stop|cancel)\\b", _latest):
            return set()
        _ctx = _zar_seamless_user_context(text, recent_messages).lower()
        _search = (
            "last time", "previous chat", "prior chat", "past chat",
            "earlier conversation", "other chat", "another chat",
            "we discussed", "we talked", "we worked on", "remember when",
            "what did we", "what did i say", "as we said before",
            "from our chats", "continue our project", "continue the project",
        )
        _save = (
            "remember this", "remember my", "remember that",
            "save my preference", "save this preference", "keep this in mind",
            "what do you remember", "my saved memory", "saved memories",
        )
        _names = set()
        if any(t in _ctx for t in _search):
            _names.add("search_chats")
        if any(t in _ctx for t in _save) and not any(
                phrase in _latest for phrase in ("don't remember", "do not remember",
                                                 "never remember", "don't save")):
            _names.add("manage_memory")
        return _names

    def _zar_seamless_mcp_tools(text, recent_messages, offered):
        import re as _re
        if not isinstance(offered, (tuple, list)) or not text:
            return []
        _ctx = _zar_seamless_user_context(text, recent_messages).lower()
        _domains = {
            "browser": (r"https?://|www\\.|\\b(?:browser|website|webpage|navigate|screenshot|open (?:the |a )?site|click (?:on |the )?(?:link|button)|visit (?:the |a )?site)\\b", ("browser","playwright","chromium")),
            "github": (r"\\b(?:github|gitlab|pull request|merge request|commit|repository|repo issue|github issue|review (?:the |a )?pr)\\b", ("github","gitlab")),
            "email": (r"\\b(?:email|e-mail|gmail|inbox|mailbox|send (?:a |an )?message|reply to (?:the |an? )?email)\\b", ("gmail","email","outlook","mail")),
            "calendar": (r"\\b(?:calendar|meeting|appointment|invite|schedule a meeting|book a meeting)\\b", ("calendar",)),
            "cloud_files": (r"\\b(?:google drive|onedrive|dropbox|sharepoint|box\\.com)\\b", ("drive","dropbox","onedrive","sharepoint","box")),
        }
        _wanted = {domain for domain, (pat, _) in _domains.items() if _re.search(pat, _ctx, _re.I)}
        if not _wanted:
            return []
        _tokens = set(_re.findall(r"[a-z0-9]+", _ctx)) - {"the","for","and","with","that","this","from"}
        _ranked = []
        for _i, _schema in enumerate(offered):
            if not isinstance(_schema, dict):
                continue
            _fn = _schema.get("function") or {}
            _fn = _fn if isinstance(_fn, dict) else {}
            _name = str(_fn.get("name") or _schema.get("name") or "").lower()
            if not _name.startswith("mcp__") or any(x in _name for x in ("unsafe","eval","execute_javascript")):
                continue
            _parts = _name.split("__")
            _server = _parts[1] if len(_parts) >= 3 else ""
            if not any(domain in _wanted and any(key in _server for key in servers)
                       for domain, (_, servers) in _domains.items()):
                continue
            _words = set(_re.findall(r"[a-z0-9]+", _name.replace("__"," ") + " " + str(_fn.get("description") or "").lower()[:350]))
            _score = len(_tokens & _words)
            if "screenshot" in _ctx and "screenshot" in _name: _score += 6
            if "navigate" in _ctx and "navigate" in _name: _score += 5
            if "send" in _ctx and any(x in _name for x in ("send","create_draft")): _score += 4
            if "issue" in _ctx and "issue" in _name: _score += 4
            _ranked.append((-_score, _i, _schema))
        _ranked.sort(key=lambda row: (row[0], row[1]))
        return [schema for _, _, schema in _ranked[:12]]

'''



def strip_legacy_v1(source: str) -> str:
    """Uninstall only this patch's known V1 inserts in-memory for rebase.

    Never modifies files. Preserve every unrelated Odysseus/Zarzysseus V8 line
    and abort rather than guessing if a V1 block has been edited unpredictably.
    """
    if MARKER not in source or CONTEXT_MARKER in source:
        raise ValueError("Expected V1-only source for guarded context migration")
    helper_start = "    # ZARZYSSEUS_SEAMLESS_MCP_V1\n"
    helper_end = HELPER_ANCHOR
    if source.count(helper_start) != 1 or source.count(helper_end) != 1:
        raise ValueError("V1 helper insertion is not unique; refusing migration")
    i = source.index(helper_start)
    j = source.index(helper_end, i)
    helper = source[i:j]
    if (j - i > 9000 or "def _zar_seamless_mcp_tools" not in helper
            or "def _zar_seamless_permitted_offerings" in helper):
        raise ValueError("V1 helper has an unrecognized layout")
    source = source[:i] + source[j:]

    relevance = "        # ZARZYSSEUS_SEAMLESS_MCP_RELEVANCE_V1\n"
    tail = "        if _force_answer:\n"
    if source.count(relevance) != 1:
        raise ValueError("Missing or duplicate V1 relevance insertion")
    i = source.index(relevance)
    j = source.find(tail, i)
    if j < 0 or j - i > 9500:
        raise ValueError("V1 relevance does not end at the expected agent guard")
    block = source[i:j]
    if ("def _zar_seamless_permitted_offerings" not in block
            or "route_relevant_tools" not in block):
        raise ValueError("V1 relevance block is not recognizable")
    source = source[:i] + source[j:]

    # V1 shipped in more than one exact form: the first release inserted
    # _zar_seamless_mcp_tools(...); later releases used the prefiltered
    # _zar_seamless_permitted_offerings(). Its explanatory comment may have
    # been removed by subsequent upstream agent repairs. Match a KNOWN
    # executable sequence, rather than requiring the comment to survive.
    legacy_note = '        # Natural-language MCP requests no longer require /skill or "use MCP".\n'
    legacy_note2 = '        # Only schemas already offered by Odysseus are eligible.\n'
    legacy_return = '        return _filter_route_tool_schemas(schemas)\n'
    old_call = '        wants_mcp = any(keyword in _last_user.lower() for keyword in _MCP_KEYWORDS)\n'
    variants = (
        old_call
        + '        schemas = (route_mcp_schemas if wants_mcp and route_mcp_schemas\n'
        + '                   else _zar_seamless_permitted_offerings())\n',
        old_call
        + '        schemas = (route_mcp_schemas if wants_mcp and route_mcp_schemas\n'
        + '                   else _zar_seamless_mcp_tools(_last_user, messages, route_mcp_schemas))\n',
        LEGACY_ANCHOR,
    )
    matches = [
        (variant, source.find(variant))
        for variant in variants if source.count(variant) == 1
    ]
    if len(matches) != 1:
        # Print narrowly scoped source structure, never user conversation data.
        ix = source.find('        wants_mcp =')
        preview = source[ix:ix + 520] if ix >= 0 else "(wants_mcp absent)"
        raise ValueError(
            "Could not uniquely identify the V1 legacy MCP fallback; "
            "no file changed. Nearby code:\n" + preview
        )
    variant, i = matches[0]
    # Optional exact V1 comments immediately preceding the known call.
    start = i
    if source[:start].endswith(legacy_note + legacy_note2):
        start -= len(legacy_note + legacy_note2)
    elif source[:start].endswith(legacy_note2):
        start -= len(legacy_note2)
    elif source[:start].endswith(legacy_note):
        start -= len(legacy_note)
    j = i + len(variant)
    if source[j:j + len(legacy_return)] != legacy_return:
        raise ValueError(
            "V1 legacy fallback has unexpected intervening code; "
            "refusing migration to preserve existing tool guards."
        )
    source = source[:start] + LEGACY_ANCHOR + source[j:]

    # Earlier patch also enriched Qwen's _zar_text on follow-up requests.
    # Remove only the recognizable V1 block to avoid duplicate context text.
    qwen = '                if (len(_zar_text.strip()) <= 150 and\n'
    if qwen in source:
        if source.count(qwen) != 1:
            raise ValueError("Multiple V1 Qwen follow-up fragments")
        i = source.index(qwen)
        terminator = '_zar_text = _zar_prior[-1100:] + "\\n" + _zar_text\n'
        j = source.find(terminator, i)
        if j < 0 or j - i > 2400 or "_zar_history =" not in source[i:j]:
            raise ValueError("V1 Qwen follow-up fragment differs; refusing migration")
        source = source[:i] + source[j+len(terminator):]
    ast.parse(source)
    return source



def upgrade_v2_browser_domain(source: str) -> str:
    """Guarded V2->V3 change. No policy, tool-call or user-message changes.

    Browser tool discovery previously required https://, www., or the literal
    word "browser". An explicit public bare hostname such as example.com was
    missed, causing small models to narrate instead of being offered tools.
    """
    if DOMAIN_MARKER in source:
        return source
    if source.count(CONTEXT_MARKER) != 1:
        raise ValueError("Expected one V2 context marker before browser-domain upgrade")
    original = (
        '            "browser": (r"https?://|www\\.|\\b(?:browser|website|'
        'webpage|navigate|screenshot|open (?:the |a )?site|click (?:on |the )?'
        '(?:link|button)|visit (?:the |a )?site)\\b", '
        '("browser","playwright","chromium")),'
    )
    revised = (
        '            "browser": (r"https?://|www\\.|'
        '(?<![\\w@])(?:[a-z0-9-]+\\.)+'
        '(?:com|org|net|io|dev|ai|edu|gov|co|info|app|me|xyz|uk|eg)'
        '(?=[/:?#\\s]|$)|'
        '\\b(?:browser|website|webpage|navigate|screenshot|open (?:the |a )?site|'
        'click (?:on |the )?(?:link|button)|visit (?:the |a )?site)\\b", '
        '("browser","playwright","chromium")),'
    )
    if source.count(original) != 1:
        raise ValueError(
            "V2 browser hostname matcher was changed; refusing to overwrite "
            "unknown MCP routing code. No file modified."
        )
    marker_line = '    ' + CONTEXT_MARKER + '\n'
    if source.count(marker_line) != 1:
        raise ValueError("V2 context marker is not uniquely located within agent")
    updated = source.replace(original, revised, 1)
    updated = updated.replace(marker_line, marker_line + '    ' + DOMAIN_MARKER + '\n', 1)
    ast.parse(updated)
    return updated


def patch_source(source: str) -> str:
    if DOMAIN_MARKER in source:
        return source
    if CONTEXT_MARKER in source:
        return upgrade_v2_browser_domain(source)
    if MARKER in source:
        source = strip_legacy_v1(source)
    anchors = {
        "route helper": HELPER_ANCHOR,
        "shared API/MCP relevance selection": RELEVANCE_ANCHOR,
        "legacy MCP fallback": LEGACY_ANCHOR,
    }
    mismatches = [
        f"{label}: found {source.count(anchor)}, expected 1"
        for label, anchor in anchors.items() if source.count(anchor) != 1
    ]
    if mismatches:
        # Reveal only the routing-code anchor lines, not unrelated source/data.
        samples = []
        needles = (
            "def _filter_route_tool_schemas",
            "_drop_legacy_email_alias_schemas_when_mcp_available",
            "wants_mcp",
            "schemas = route_mcp_schemas",
        )
        for number, line in enumerate(source.splitlines(), 1):
            if any(needle in line for needle in needles):
                samples.append(f"line {number}: {line.strip()[:170]}")
            if len(samples) >= 12:
                break
        raise ValueError(
            "Installed Odysseus source differs from the tested routing layout; "
            "no file changed. " + "; ".join(mismatches)
            + ("\nNearby routing code:\n" + "\n".join(samples) if samples else "")
        )
    # Legacy agent routing has no turn_contract/_caller_relevant_tools.
    # The explicit caller scope is the existing relevant_tools parameter.
    # We must see policy, disabled and caller-request controls before injecting.
    required_guards = (
        "relevant_tools", "forced_tools", "guide_only", "_force_answer",
        "tool_policy", "disabled_tools",
    )
    missing_guards = [
        name for name in required_guards
        if not re.search(r"\b" + re.escape(name) + r"\b", source)
    ]
    if missing_guards:
        raise ValueError(
            "Legacy Odysseus is missing required caller/permission controls: "
            + ", ".join(missing_guards)
            + ". No file changed. Run 'diagnose' for the routing layout."
        )
    # The named route must live inside a function with an explicit relevant_tools
    # argument. A coincidental string elsewhere does not satisfy authorization.
    tree = ast.parse(source)
    route_functions = [
        node for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name == "_tool_schemas_for_route"
    ]
    if len(route_functions) != 1:
        raise ValueError("Unable to locate one scoped API tool router; no file changed.")
    enclosing = None
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if route_functions[0] in node.body:
            enclosing = node
            break
    if enclosing is None or "relevant_tools" not in {
        a.arg for a in (enclosing.args.posonlyargs + enclosing.args.args
                        + enclosing.args.kwonlyargs)
    }:
        raise ValueError(
            "Legacy caller scope is not a relevant_tools argument of the agent. "
            "Do not assume an implicit permission fallback; no file changed."
        )
    updated = source.replace(HELPER_ANCHOR, RUNTIME_HELPER + "\n" + HELPER_ANCHOR, 1)
    # Enrich the existing relevance set BEFORE Odysseus decides which API
    # schemas it will offer. This preserves its own disabled-tool, tool-surface,
    # caller-scope and approval filters, rather than appending after filtering.
    relevance_extra = '''        # ZARZYSSEUS_SEAMLESS_MCP_RELEVANCE_V1
        # Legacy scope is the ORIGINAL relevant_tools argument (caller-supplied),
        # never the RAG-inferred route_relevant_tools collection. Do not broaden
        # explicit caller scopes, forced tools, guide-only or force-answer turns.
        def _zar_seamless_permitted_offerings():
            if (guide_only or _force_answer or relevant_tools is not None
                    or forced_tools):
                return []
            if tool_policy is not None:
                if getattr(tool_policy, "block_all_tool_calls", True):
                    return []
                if not callable(getattr(tool_policy, "blocks", None)):
                    return []  # unknown policy object: fail closed
            if not isinstance(disabled_tools, (set, frozenset, list, tuple, dict)):
                return []  # Unknown disabled-list structure: do not auto-offer.
            _zar_offered = []
            for _zar_schema in route_mcp_schemas:
                if not isinstance(_zar_schema, dict):
                    continue
                _zar_name = str((_zar_schema.get("function") or {}).get("name") or "")
                if not _zar_name or _zar_name in disabled_tools:
                    continue
                if tool_policy is not None:
                    try:
                        if tool_policy.blocks(_zar_name):
                            continue
                    except (TypeError, ValueError, AttributeError):
                        return []  # Unrecognized policy contract: fail closed.
                _zar_offered.append(_zar_schema)
            return _zar_seamless_mcp_tools(_last_user, messages, _zar_offered)

        if route_state.get("is_api_model") and route_mcp_schemas:
            _zar_found = _zar_seamless_permitted_offerings()
            if _zar_found and route_relevant_tools is not None:
                route_relevant_tools = set(route_relevant_tools) | {
                    str((s.get("function") or {}).get("name") or "")
                    for s in _zar_found
                }
        # Existing Odysseus tools, NOT a new cross-user memory store.
        # When requested, surface read-only past-chat retrieval or user-authored
        # durable-memory management. Merely offering a schema does not execute.
        if (route_state.get("is_api_model") and route_relevant_tools is not None
                and not guide_only and not _force_answer
                and relevant_tools is None and not forced_tools
                and isinstance(disabled_tools, (set, frozenset, list, tuple, dict))):
            _zar_recall_names = _zar_seamless_memory_names(_last_user, messages)
            if _zar_recall_names:
                _zar_native_offered = {
                    str((s.get("function") or {}).get("name") or "")
                    for s in FUNCTION_TOOL_SCHEMAS if isinstance(s, dict)
                }
                _zar_recall_allowed = set()
                for _zar_name in _zar_recall_names & _zar_native_offered:
                    if _zar_name in disabled_tools:
                        continue
                    if tool_policy is not None:
                        if getattr(tool_policy, "block_all_tool_calls", True):
                            continue
                        if not callable(getattr(tool_policy, "blocks", None)):
                            continue
                        try:
                            if tool_policy.blocks(_zar_name):
                                continue
                        except (TypeError, ValueError, AttributeError):
                            continue
                    _zar_recall_allowed.add(_zar_name)
                if _zar_recall_allowed:
                    route_relevant_tools = set(route_relevant_tools) | _zar_recall_allowed
'''
    updated = updated.replace(RELEVANCE_ANCHOR, RELEVANCE_ANCHOR + relevance_extra, 1)
    legacy = '''        # Only select permitted, ENABLED MCP schemas for natural-language
        # requests in non-API routes; existing literal MCP handling is unchanged.
        wants_mcp = any(keyword in _last_user.lower() for keyword in _MCP_KEYWORDS)
        schemas = (route_mcp_schemas if wants_mcp and route_mcp_schemas
                   else _zar_seamless_permitted_offerings())
'''
    updated = updated.replace(LEGACY_ANCHOR, legacy, 1)
    if "# ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V4" in source and QWEN_ANCHOR in updated:
        # Qwen's browser filtering must use the same task-specific, user-only
        # rolling context as the MCP/recall selector.
        qwen_context = '''                # ZARZYSSEUS_QWEN_CONTEXT_CONTINUITY_V2
                _zar_text = _zar_seamless_user_context(_zar_text, messages)
'''
        updated = updated.replace(QWEN_ANCHOR, QWEN_ANCHOR + qwen_context, 1)
    ast.parse(updated)
    return upgrade_v2_browser_domain(updated)


def install(path: Path) -> int:
    if not path.is_file() or path.is_symlink():
        print("ERROR: Expected an existing regular Odysseus src/agent_loop.py", file=sys.stderr)
        return 2
    before = path.read_text(encoding="utf-8")
    if DOMAIN_MARKER in before:
        print("[ready] Seamless MCP routing, context continuity and bare-domain V3 installed")
        return 0
    try:
        after = patch_source(before)
    except (SyntaxError, ValueError) as error:
        print("[skipped] " + str(error), file=sys.stderr)
        return 2
    backup_dir = path.parents[1] / "data" / "local" / "patch-backups"
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / ("agent_loop.py.mcp-v1." + dt.datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".bak")
    shutil.copy2(path, backup)
    fd, temp = tempfile.mkstemp(prefix=".zar-mcp-", suffix=".py", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(after)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temp, path.stat().st_mode & 0o777)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    print("[installed] Natural-language MCP routing, contextual follow-ups; existing policy retained")
    print("[backup] " + str(backup))
    return 0


def diagnose_source(source: str) -> None:
    """Describe routing structure without writing source or printing secrets."""
    print("=== Odysseus installed agent routing (read-only) ===")
    symbols = (
        "turn_contract", "_caller_relevant_tools", "guide_only",
        "relevant_tools", "_relevant_tools", "tool_policy",
        "disabled_tools", "_caller_hard_denials", "forced_tools",
        "route_relevant_tools", "route_state", "mcp_schemas",
    )
    for symbol in symbols:
        count = len(re.findall(r"\b" + re.escape(symbol) + r"\b", source))
        print(f"{symbol}: {count} occurrence(s)")
    lines = source.splitlines()
    markers = (
        "def _filter_route_tool_schemas(",
        "def _tool_schemas_for_route(",
        "route_relevant_tools =",
        "wants_mcp =",
    )
    printed = set()
    for marker in markers:
        hits = [i for i, line in enumerate(lines) if marker in line]
        print(f"\nRouting anchor {marker!r}: {len(hits)} hit(s)")
        for index in hits[:2]:
            lo, hi = max(0, index - 4), min(len(lines), index + 23)
            for k in range(lo, hi):
                if k in printed:
                    continue
                printed.add(k)
                print(f"{k+1}: {lines[k][:180]}")
    print("\nRead-only diagnosis complete. No files modified.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "status", "dry-run", "diagnose"))
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    if not args.source.is_file():
        print("Agent loop source does not exist", file=sys.stderr)
        return 2
    data = args.source.read_text(encoding="utf-8")
    if args.action == "diagnose":
        diagnose_source(data)
        return 0
    if args.action == "status":
        version = ("bare-domain-v3" if DOMAIN_MARKER in data else
                   "context-v2 (upgrade available)" if CONTEXT_MARKER in data else
                   "legacy-v1 (migration needed)" if MARKER in data else
                   "not installed")
        print("Seamless MCP:", version)
        return 0 if DOMAIN_MARKER in data else 1
    if args.action == "dry-run":
        try:
            patch_source(data)
            print("[pass] Guarded MCP patch source and AST syntax")
            return 0
        except (SyntaxError, ValueError) as error:
            print("[fail]", error, file=sys.stderr)
            return 2
    return install(args.source)


if __name__ == "__main__":
    raise SystemExit(main())
