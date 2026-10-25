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
HELPER_ANCHOR = "    def _filter_route_tool_schemas(schemas):\n"
API_ANCHOR = "            schemas = _drop_legacy_email_alias_schemas_when_mcp_available(schemas)\n"
LEGACY_ANCHOR = (
    "        wants_mcp = any(keyword in _last_user.lower() for keyword in _MCP_KEYWORDS)\n"
    "        schemas = route_mcp_schemas if wants_mcp and route_mcp_schemas else []\n"
)
QWEN_ANCHOR = '                _zar_text = _last_user or ""\n'

# Match natural task descriptions, not magic /skill names.
DOMAINS = {
    "browser": (
        r"https?://|www\.|\b(?:browser|website|webpage|navigate|screenshot|"
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
    current = str(latest or "")[:1400]
    if (len(current.strip()) > 150 or not FOLLOWUP.search(current.strip())
            or NEGATE.search(current.strip()) or not isinstance(messages, (list, tuple))):
        return current
    previous = []
    for message in messages[-24:]:
        if isinstance(message, dict) and message.get("role") == "user":
            content = message.get("content")
            if isinstance(content, str) and content.strip():
                previous.append(content.strip())
    if len(previous) < 2:
        return current
    # Only previous USER text from this request's own message history.
    prior = previous[-2] if previous[-1] == current.strip() else previous[-1]
    return prior[-1100:] + "\nFollow-up: " + current


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
    def _zar_seamless_mcp_tools(text, recent_messages, offered):
        import re as _re
        if not isinstance(offered, (tuple, list)) or not text:
            return []
        _current = str(text)
        _context = _current
        if (len(_current.strip()) <= 150
                and _re.search(r"^(?:and|also|now|then|yes|sure|go ahead|do it|continue|same|what about|can you|could you|screenshot|click|open|send)\\b",
                               _current.strip(), _re.I)
                and not _re.search(r"^(?:no|stop|cancel|don't|do not|never)\\b", _current.strip(), _re.I)
                and isinstance(recent_messages, (list, tuple))):
            _users = [m.get("content").strip() for m in recent_messages[-24:]
                      if isinstance(m, dict) and m.get("role") == "user"
                      and isinstance(m.get("content"), str) and m.get("content").strip()]
            if len(_users) >= 2:
                _previous = _users[-2] if _users[-1] == _current.strip() else _users[-1]
                _context = _previous[-1100:] + "\\nFollow-up: " + _current
        _ctx = _context.lower()
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


def patch_source(source: str) -> str:
    if MARKER in source:
        return source
    anchors = {
        "route helper": HELPER_ANCHOR,
        "API model MCP filter": API_ANCHOR,
        "legacy MCP fallback": LEGACY_ANCHOR,
    }
    mismatches = [
        f"{label}: found {source.count(anchor)}, expected 1"
        for label, anchor in anchors.items() if source.count(anchor) != 1
    ]
    if mismatches:
        raise ValueError(
            "Installed Odysseus source differs from the tested routing layout; "
            "no file changed. " + "; ".join(mismatches)
        )
    updated = source.replace(HELPER_ANCHOR, RUNTIME_HELPER + "\n" + HELPER_ANCHOR, 1)
    api_extra = '''            # Semantic MCP discovery only when there is no caller/contract tool
            # restriction. Existing disabled-tool and approval filters still apply.
            if (route_mcp_schemas and turn_contract is None
                    and _caller_relevant_tools is None and not guide_only):
                _zar_auto = _zar_seamless_mcp_tools(_last_user, messages, route_mcp_schemas)
                _zar_names = {(s.get("function") or {}).get("name") for s in schemas}
                schemas.extend(
                    s for s in _zar_auto
                    if (s.get("function") or {}).get("name") not in _zar_names
                )
'''
    updated = updated.replace(API_ANCHOR, api_extra + API_ANCHOR, 1)
    legacy = '''        # Natural-language MCP requests no longer require /skill or "use MCP".
        # Only schemas already offered by Odysseus are eligible.
        wants_mcp = any(keyword in _last_user.lower() for keyword in _MCP_KEYWORDS)
        schemas = (route_mcp_schemas if wants_mcp and route_mcp_schemas
                   else _zar_seamless_mcp_tools(_last_user, messages, route_mcp_schemas))
'''
    updated = updated.replace(LEGACY_ANCHOR, legacy, 1)
    if "# ZARZYSSEUS_QWEN_EXPLICIT_TOOL_FOCUS_V4" in source and QWEN_ANCHOR in updated:
        # Qwen's existing browser filter works on _zar_text. Short follow-ups
        # need the previous browser request, but must not change actual messages.
        context = '''                if (len(_zar_text.strip()) <= 150 and
                        _zar_re.search(r"^(?:and|also|now|then|yes|go ahead|do it|continue|screenshot|click|open)\\b",
                                       _zar_text.strip(), _zar_re.I)):
                    _zar_history = [m.get("content").strip() for m in messages[-24:]
                                    if isinstance(m, dict) and m.get("role") == "user"
                                    and isinstance(m.get("content"), str) and m.get("content").strip()]
                    if len(_zar_history) >= 2:
                        _zar_prior = _zar_history[-2] if _zar_history[-1] == _zar_text.strip() else _zar_history[-1]
                        _zar_text = _zar_prior[-1100:] + "\\n" + _zar_text
'''
        updated = updated.replace(QWEN_ANCHOR, QWEN_ANCHOR + context, 1)
    ast.parse(updated)
    return updated


def install(path: Path) -> int:
    if not path.is_file() or path.is_symlink():
        print("ERROR: Expected an existing regular Odysseus src/agent_loop.py", file=sys.stderr)
        return 2
    before = path.read_text(encoding="utf-8")
    if MARKER in before:
        print("[ready] Seamless MCP routing already installed")
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


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("install", "status", "dry-run"))
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    if not args.source.is_file():
        print("Agent loop source does not exist", file=sys.stderr)
        return 2
    data = args.source.read_text(encoding="utf-8")
    if args.action == "status":
        print("Seamless MCP:", "installed" if MARKER in data else "not installed")
        return int(MARKER not in data)
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
