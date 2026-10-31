#!/usr/bin/env python3
"""V4.4: keep MCP screenshot pixels in the UI, not in Dolphin's text-only context.

Narrow, source-guarded adaptation of the existing agent_loop.py call to
_append_tool_results. Only the copy of tool results sent back to the model is
changed. Tool permissions, MCP dispatch, screenshot SSE, history persistence,
and visual-capable models are not changed by this patch.
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

MARKER = "# ZARZYSSEUS_TEXT_ONLY_SCREENSHOT_HANDOFF_V44"
REQUIRED = (
    "ZARZYSSEUS_CONTEXT_CONTINUITY_V2",
    "ZARZYSSEUS_FORCED_ADDITIVE_FOCUS_V42",
)
SUMMARY = (
    "Screenshot successfully captured and displayed in the browser tool UI. "
    "This text-only model has not received the image pixels and cannot analyze "
    "the screenshot visually. For the page's readable content, call the "
    "already-authorized browser_snapshot tool if available; otherwise explain "
    "the limitation. Do not interpret or reproduce Base64 image data."
)

INSERT = '''{i}# ZARZYSSEUS_TEXT_ONLY_SCREENSHOT_HANDOFF_V44
{i}# Keep UI/persisted screenshot events untouched; sanitize ONLY the result
{i}# records feeding the next LLM round for this known text-only model.
{i}_zar_model_records_v44 = tool_result_records
{i}_zar_model_texts_v44 = tool_result_texts
{i}if "dolphin-mistral" in str(model or "").casefold() and isinstance(tool_result_records, (list, tuple)):
{i}    _zar_model_records_v44 = []
{i}    _zar_model_texts_v44 = list(tool_result_texts)
{i}    _zar_omitted_v44 = 0
{i}    for _zar_idx_v44, _zar_record_v44 in enumerate(tool_result_records):
{i}        if (isinstance(_zar_record_v44, dict)
{i}                and _zar_record_v44.get("tool_name") == "mcp__builtin_browser__browser_take_screenshot"
{i}                and isinstance(_zar_record_v44.get("result"), dict)
{i}                and _zar_record_v44["result"].get("images")):
{i}            _zar_copy_v44 = dict(_zar_record_v44)
{i}            _zar_res_v44 = dict(_zar_record_v44["result"])
{i}            _zar_res_v44.pop("images", None)
{i}            # Retain the external-content taint even when the image bytes
{i}            # were the only producer data (including an MCP error result).
{i}            _zar_res_v44["untrusted_content"] = True
{i}            _zar_copy_v44["result"] = _zar_res_v44
{i}            _zar_model_records_v44.append(_zar_copy_v44)
{i}            if _zar_idx_v44 < len(_zar_model_texts_v44):
{i}                _zar_model_texts_v44[_zar_idx_v44] = _ZARZYSSEUS_SCREENSHOT_SUMMARY_V44
{i}            _zar_omitted_v44 += 1
{i}        else:
{i}            _zar_model_records_v44.append(_zar_record_v44)
{i}    if _zar_omitted_v44:
{i}        logger.info("[zarzysseus-image-v44] text_only_screenshot_sanitized=%d ui_unchanged=True", _zar_omitted_v44)
'''

# The summary is a fixed constant in agent_loop.py, not a user-supplied prompt.
MODULE_HELPER = '\n_ZARZYSSEUS_SCREENSHOT_SUMMARY_V44 = ' + repr(SUMMARY) + '\n'


def sha(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def patch_source(source: str) -> str:
    if MARKER in source:
        return source
    for required in REQUIRED:
        if source.count(required) < 1:
            raise ValueError(f"Expected pre-existing Zarzysseus marker: {required}")
    tree = ast.parse(source)
    calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if not isinstance(node.func, ast.Name) or node.func.id != "_append_tool_results":
            continue
        kwargs = {k.arg: k.value for k in node.keywords if k.arg}
        if ("tool_result_records" in kwargs
                and isinstance(kwargs["tool_result_records"], ast.Name)
                and kwargs["tool_result_records"].id == "tool_result_records"):
            calls.append(node)
    if len(calls) != 1:
        raise ValueError(f"Expected exactly one live model-feedback _append_tool_results call; found {len(calls)}")
    node = calls[0]
    # Other calls (e.g. approval replay) are NOT the LLM feedback site.
    lines = source.splitlines(keepends=True)
    index = node.lineno - 1
    line = lines[index]
    indent = line[:len(line)-len(line.lstrip(" \t"))]
    if not indent or "_append_tool_results(" not in line or "\t" in indent:
        raise ValueError("Unknown feedback call indentation/shape")
    # Must be within round loop and have the expected aligned positional params.
    call_lines = "".join(lines[node.lineno - 1:node.end_lineno])
    if ("tool_result_texts" not in call_lines or "tool_results" not in call_lines
            or "native_tool_calls" in call_lines or "tool_result_records=tool_result_records" not in call_lines):
        raise ValueError("Unknown result feedback arguments; refusing")
    if call_lines.count("tool_result_records=tool_result_records") != 1:
        raise ValueError("Unexpected tool-result keyword")
    # Guard the AST source span, not arbitrary global substring replacement.
    new_call = call_lines.replace("tool_result_records=tool_result_records",
                                  "tool_result_records=_zar_model_records_v44", 1)
    # Replace the positional tool_result_texts exactly once, not module-level identifiers.
    # The known feedback site is 1:1 aligned with tool_result_records.
    import re
    new_call, replacements = re.subn(r"\btool_result_texts\b", "_zar_model_texts_v44", new_call)
    if replacements != 1:
        raise ValueError(f"Expected one tool_result_texts parameter, found {replacements}")
    lines[node.lineno - 1:node.end_lineno] = [INSERT.format(i=indent) + new_call]
    # Helper constant added to module-level, immediately after module imports? Instead
    # add beside the outer function as a standalone top-level constant, preserving
    # all existing import/__future__ ordering by appending to the end of the file.
    patched = "".join(lines).rstrip("\n") + "\n" + MODULE_HELPER
    ast.parse(patched)
    compile(patched, "<zarzysseus-v44>", "exec")
    return patched


def atomic_replace(file: Path, data: bytes, mode: int) -> None:
    fd, name = tempfile.mkstemp(prefix=".zar-image-v44-", suffix=".py", dir=str(file.parent))
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(name, mode)
        os.replace(name, file)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("dry-run", "install", "status", "rollback"))
    parser.add_argument("source", type=Path)
    args = parser.parse_args()
    file = args.source.expanduser()
    if not file.is_file() or file.is_symlink():
        print("[refused] Expected regular existing agent_loop.py", file=sys.stderr)
        return 2
    before = file.read_bytes()
    backup_dir = file.parents[1] / "data" / "local" / "patch-backups"
    manifest = backup_dir / "image-handoff-v44.json"
    if args.action == "status":
        active = MARKER.encode() in before
        print("V4.4 text-only image handoff:", "installed" if active else "not installed")
        return 0 if active else 1
    if args.action == "rollback":
        if not manifest.is_file():
            print("[refused] No rollback manifest", file=sys.stderr)
            return 2
        try:
            payload = json.loads(manifest.read_text("utf-8"))
            backed_up = Path(payload["backup"]).read_bytes()
            if (str(file.resolve()) != payload["file"] or sha(before) != payload["installed_sha256"]
                    or sha(backed_up) != payload["original_sha256"]):
                raise ValueError("Source or backup changed since install")
            compile(backed_up.decode("utf-8"), str(file), "exec")
        except (KeyError, ValueError, OSError, UnicodeDecodeError, SyntaxError) as exc:
            print("[refused] Unsafe rollback:", exc, file=sys.stderr)
            return 2
        atomic_replace(file, backed_up, stat.S_IMODE(file.stat().st_mode))
        manifest.unlink()
        print("[restored] Pre-V4.4 agent source")
        return 0
    try:
        updated = patch_source(before.decode("utf-8")).encode("utf-8")
    except (ValueError, SyntaxError, UnicodeDecodeError) as exc:
        print("[refused]", exc, file=sys.stderr)
        return 2
    if args.action == "dry-run":
        print("[pass] Feedback call, source guard and AST syntax; no files changed")
        print("[status]", "already installed" if updated == before else "upgrade applicable")
        return 0
    if updated == before:
        print("[ready] Already installed")
        return 0
    if manifest.exists():
        print("[refused] Existing V4.4 rollback manifest", file=sys.stderr)
        return 2
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / ("agent_loop.py.v44." + datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".bak")
    shutil.copy2(file, backup)
    atomic_replace(file, updated, stat.S_IMODE(file.stat().st_mode))
    manifest.write_text(json.dumps({
        "file": str(file.resolve()), "backup": str(backup.resolve()),
        "original_sha256": sha(before), "installed_sha256": sha(updated),
    }, indent=2) + "\n", encoding="utf-8")
    print("[installed] Dolphin screenshot pixels suppressed from model input; UI path unchanged")
    print("[backup]", backup)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
