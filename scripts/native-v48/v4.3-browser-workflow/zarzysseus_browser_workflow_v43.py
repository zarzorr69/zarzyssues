#!/usr/bin/env python3
"""V4.3 guarded workflow-tool routing patch for Zarzysseus native Odysseus.

Targets *only* the existing V4.1/V4.2 browser-intent helper. It never changes
permissions, tool approvals, transport, dispatcher, or forced tool semantics.
Focused schemas are still filtered by the existing V4.2 authorization code.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import shutil
import stat
import sys
import tempfile
from datetime import datetime
from pathlib import Path

MARKER = "ZARZYSSEUS_BROWSER_WORKFLOW_V43"
EXPECTED_HELPER_SHA256 = "ab84166fd09a6a86dc3534786ef6a02f175998439b2cc4911e5220f4e6f3d72f"
REQUIRED = (
    "# ZARZYSSEUS_MODEL_INDEPENDENT_MCP_FOCUS_V4",
    "# ZARZYSSEUS_FORCED_ADDITIVE_FOCUS_V42",
    "# ZARZYSSEUS_CONTEXT_CONTINUITY_V2",
)

# This is a relevance hint only. The V4.2 focus code decides whether a tool
# may actually be included, preserving explicit scopes, disabled tools, policy,
# forced schemas, and approval replay behavior.
NEW_HELPER = r'''    def _zar_browser_targets_v4(latest, recent_messages):
        """V4.3: task-scoped browser selection; never authorization/execution."""
        # ZARZYSSEUS_BROWSER_WORKFLOW_V43
        import re as _re
        _cur = str(latest or "")[:1400].strip().lower()
        if not _cur or _re.search(
            r"\b(?:don't|do not|never|without|cancel|stop|not now)\b", _cur
        ):
            return ()
        _domain = (r"(?:https?://|www\.|(?<![\w@])(?:[a-z0-9-]+\.)+"
                   r"(?:com|org|net|io|dev|ai|edu|gov|co|info|app|me|xyz|uk|eg)"
                   r"(?=[/:?#\s]|$))")
        _url_now = bool(_re.search(_domain, _cur))
        _previous = []
        if isinstance(recent_messages, (list, tuple)):
            _previous = [m["content"].strip().lower()[-580:]
                         for m in recent_messages[-36:]
                         if isinstance(m, dict) and m.get("role") == "user"
                         and isinstance(m.get("content"), str) and m["content"].strip()]
        if _previous and _previous[-1] == _cur:
            _previous.pop()
        _prior_last = _previous[-1] if _previous else ""
        # History is only used to resolve read-only tool *relevance*.
        # Neither assistant output nor web content can authorize tool calls.
        _prior_site = any(_re.search(_domain, s) or _re.search(
            r"\b(?:website|webpage|browser|web page)\b", s)
            for s in _previous[-3:])
        if _re.match(r"^(?:how (?:do|can|would|to)\b|why\b|explain how\b|teach me how\b)", _cur):
            return ()
        _nav = bool(_re.search(
            r"^(?:(?:please|now)\s+|(?:can|could|would)\s+you\s+)*"
            r"(?:open|visit|load|navigate(?:\s+to)?|go\s+to|browse(?:\s+to)?)\b",
            _cur,
        )) and (_url_now or (_prior_site and _re.search(
            r"\b(?:it|that page|that site|the page|the site|webpage|website)\b", _cur
        )))
        _screenshot_word = bool(_re.search(r"\b(?:screenshot|screen\s*shot)\b", _cur))
        _shot_request = bool(_re.search(
            r"^(?:now\s+|please\s+)?(?:(?:take|capture|make|get|show|send)\s+"
            r"(?:me\s+|a\s+|the\s+)?)?(?:screenshot|screen\s*shot)\b",
            _cur,
        )) or bool(_re.search(
            r"\b(?:take|capture|send|show|provide|make|get)\b.{0,70}"
            r"\b(?:screenshot|screen\s*shot)\b", _cur
        ))
        # Explicit multi-action commands like 'open example.com screenshot the
        # page and describe it' should offer screenshot even without 'take'.
        _shot = (_nav and _screenshot_word) or _shot_request
        _describe = bool(_re.search(
            r"\b(?:describe|summari[sz]e|read|inspect|explain|analy[sz]e)\b", _cur
        ) and (_url_now or _prior_site or _re.search(
            r"\b(?:page|website|webpage|site|current tab)\b", _cur
        )) and _re.search(r"\b(?:page|website|webpage|site|tab|it)\b", _cur))
        _yes = bool(_re.fullmatch(r"(?:yes|yep|sure|go ahead|do it|okay|ok)", _cur))
        _css = bool(_re.match(r"^css\s+(?:is\s+)?(?:fine|okay|ok)\b", _cur))
        if (_yes or _css) and _prior_last:
            if _css or _re.search(r"\b(?:screenshot|screen\s*shot)\b", _prior_last):
                _shot = True
            elif _re.search(r"\b(?:describe|summari[sz]e|read|inspect|explain)\b", _prior_last) and (
                _prior_site or _re.search(r"\b(?:page|site|webpage|tab)\b", _prior_last)
            ):
                _describe = True
            elif _re.match(r"^(?:open|visit|navigate)\b", _prior_last) and _re.search(_domain, _prior_last):
                _nav = True
        if not (_nav or _shot or _describe):
            return ()
        _prefix = "mcp__builtin_browser__"
        _targets = []
        if _nav:
            _targets.append(_prefix + "browser_navigate")
        if _describe:
            _targets.append(_prefix + "browser_snapshot")
        if _shot:
            _targets.append(_prefix + "browser_take_screenshot")
        return tuple(_targets)
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def updated_source(source: str) -> str:
    if MARKER in source:
        return source
    for required in REQUIRED:
        if source.count(required) != 1:
            raise ValueError(f"Required marker missing or duplicated: {required}")
    tree = ast.parse(source)
    candidates = [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))
                  and n.name == "_zar_browser_targets_v4"]
    if len(candidates) != 1:
        raise ValueError("Expected one installed V4 browser-intent helper")
    target = candidates[0]
    if not any(isinstance(parent, (ast.FunctionDef, ast.AsyncFunctionDef))
               and target in parent.body for parent in ast.walk(tree)):
        raise ValueError("Unexpected browser helper nesting")
    lines = source.splitlines(keepends=True)
    old = "".join(lines[target.lineno-1:target.end_lineno])
    if sha(old.encode("utf-8")) != EXPECTED_HELPER_SHA256:
        raise ValueError("Installed V4 browser-target helper differs from tested V4.1 layout")
    lines[target.lineno-1:target.end_lineno] = [NEW_HELPER + "\n"]
    replacement = "".join(lines)
    ast.parse(replacement)
    compile(replacement, "<zarzysseus-v4.3>", "exec")
    return replacement


def atomic_replace(file: Path, payload: bytes, mode: int):
    fd, p = tempfile.mkstemp(prefix=".zar-browser-v43-", suffix=".py", dir=str(file.parent))
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(payload)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(p, mode)
        os.replace(p, file)
    finally:
        if os.path.exists(p):
            os.unlink(p)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("dry-run", "install", "status", "rollback"))
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    f = args.source.expanduser()
    if not f.is_file() or f.is_symlink():
        print("[refused] Expected existing regular Odysseus source", file=sys.stderr)
        return 2
    old = f.read_bytes()
    backups = f.parents[1] / "data" / "local" / "patch-backups"
    manifest = backups / "browser-workflow-v43.json"
    if args.action == "status":
        active = MARKER.encode() in old
        print("V4.3 browser workflow:", "installed" if active else "not installed")
        return 0 if active else 1
    if args.action == "rollback":
        if not manifest.is_file():
            print("[refused] No V4.3 rollback manifest", file=sys.stderr)
            return 2
        try:
            record = json.loads(manifest.read_text("utf-8"))
            restore_file = Path(record["backup"])
            saved = restore_file.read_bytes()
            if (str(f.resolve()) != record["file"]
                    or sha(old) != record["installed_sha256"]
                    or sha(saved) != record["original_sha256"]):
                raise ValueError("Source or original backup changed")
            compile(saved.decode("utf-8"), str(f), "exec")
        except (OSError, KeyError, TypeError, ValueError, SyntaxError, UnicodeDecodeError) as exc:
            print("[refused] Unsafe rollback:", exc, file=sys.stderr)
            return 2
        atomic_replace(f, saved, stat.S_IMODE(f.stat().st_mode))
        manifest.unlink()
        print("[restored] Pre-V4.3 agent source restored")
        return 0
    try:
        new = updated_source(old.decode("utf-8")).encode("utf-8")
    except (SyntaxError, ValueError, UnicodeDecodeError) as exc:
        print("[refused]", exc, file=sys.stderr)
        return 2
    if args.action == "dry-run":
        print("[pass] Expected V4.2 markers, exact V4 intent helper and AST syntax")
        print("[status]", "already installed" if new == old else "upgrade applicable")
        return 0
    if new == old:
        print("[ready] Already installed")
        return 0
    if manifest.exists():
        print("[refused] Existing V4.3 rollback manifest", file=sys.stderr)
        return 2
    backups.mkdir(parents=True, exist_ok=True)
    backup = backups / ("agent_loop.py.v43." + datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".bak")
    shutil.copy2(f, backup)
    atomic_replace(f, new, stat.S_IMODE(f.stat().st_mode))
    manifest.write_text(json.dumps({
        "file": str(f.resolve()), "backup": str(backup.resolve()),
        "original_sha256": sha(old), "installed_sha256": sha(new),
    }, indent=2) + "\n", encoding="utf-8")
    print("[installed] Browser navigation, snapshot and screenshot workflow targets")
    print("[backup]", backup)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
