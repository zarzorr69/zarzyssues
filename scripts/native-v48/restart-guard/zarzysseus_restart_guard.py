#!/usr/bin/env python3
"""Guarded local patch to make Zarzysseus `restart` skip auto-repair.

Applies to zarzysseus.sh only. No agent_loop.py, model or MCP changes.
Usage:
  python3 zarzysseus_restart_guard.py dry-run ~/odysseus/zarzysseus.sh
  python3 zarzysseus_restart_guard.py install ~/odysseus/zarzysseus.sh
  python3 zarzysseus_restart_guard.py status ~/odysseus/zarzysseus.sh
  python3 zarzysseus_restart_guard.py rollback ~/odysseus/zarzysseus.sh
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from datetime import datetime

MARKER = "# ZARZYSSEUS_RESTART_NO_REPAIR_V1"
ORIGINAL = '''    start|enable|restart)
        # These are convenience actions: when Zarzysseus is missing, install it first.
        if ! installation_complete; then
            info "Zarzysseus is not fully installed; installing it before '$ACTION'..."
            install_odysseus
        fi

        install_chat_continuity_guard || true
        install_cookbook_reliability_fixes || true
        install_direct_tool_json_recovery || true
        agent_reliability_auto_install || true
        skills_mcp_autoprovision_all || true
        case "$ACTION" in
            start) service_start ;;
            enable) service_enable ;;
            restart) service_restart ;;
        esac
        ;;
'''
PATCHED = '''    start|enable|restart)
        if [[ "$ACTION" == restart ]]; then
            # ZARZYSSEUS_RESTART_NO_REPAIR_V1
            # A service restart must not modify a locally patched agent runtime.
            # Explicit install/repair commands retain their original safeguards.
            if ! installation_complete; then
                echo "ERROR: Zarzysseus installation is incomplete; refusing to auto-install during restart." >&2
                echo "       Run the explicit install/repair command after reviewing its changes." >&2
                exit 2
            fi
            echo "    [note] Restart-only: skipping automatic agent, Cookbook, and skill repairs."
        else
            # Original start/enable provisioning behavior is unchanged.
            if ! installation_complete; then
                info "Zarzysseus is not fully installed; installing it before '$ACTION'..."
                install_odysseus
            fi

            install_chat_continuity_guard || true
            install_cookbook_reliability_fixes || true
            install_direct_tool_json_recovery || true
            agent_reliability_auto_install || true
            skills_mcp_autoprovision_all || true
        fi
        case "$ACTION" in
            start) service_start ;;
            enable) service_enable ;;
            restart) service_restart ;;
        esac
        ;;
'''

def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def patch(data: bytes) -> bytes:
    src = data.decode("utf-8")
    if MARKER in src:
        if src.count(MARKER) != 1 or src.count(PATCHED) != 1:
            raise ValueError("Modified/partial restart guard; refusing changes")
        return data
    if src.count(ORIGINAL) != 1:
        raise ValueError("Unknown Zarzysseus restart command layout; refusing changes")
    result = src.replace(ORIGINAL, PATCHED, 1).encode("utf-8")
    if result.count(MARKER.encode("utf-8")) != 1:
        raise ValueError("Internal marker validation failed")
    return result


def syntax_check(data: bytes) -> None:
    with tempfile.NamedTemporaryFile(prefix="zar-restart-check-", suffix=".sh", delete=False) as f:
        fn = f.name
        f.write(data)
    try:
        res = subprocess.run(["bash", "-n", fn], text=True, capture_output=True)
        if res.returncode:
            raise ValueError("bash -n failed: " + res.stderr.strip()[:1200])
    finally:
        os.unlink(fn)


def atomic_write(path: Path, data: bytes, mode: int) -> None:
    fd, tmp = tempfile.mkstemp(prefix=".zar-restart-", suffix=".sh", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def paths(source: Path) -> tuple[Path, Path]:
    home = source.parent
    backup_dir = home / "data/local/patch-backups"
    return backup_dir, backup_dir / "zarzysseus-restart-only-v1.json"


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("command", choices=["dry-run", "install", "status", "rollback"])
    p.add_argument("script", nargs="?", default=str(Path.home() / "odysseus/zarzysseus.sh"))
    args = p.parse_args(argv)
    source = Path(args.script).expanduser().resolve()
    if not source.is_file() or source.name != "zarzysseus.sh":
        raise ValueError("Pass an existing Zarzysseus zarzysseus.sh path")
    before = source.read_bytes()
    bdir, manifest = paths(source)
    is_patched = MARKER.encode("utf-8") in before

    if args.command == "status":
        if is_patched:
            patch(before)
            print("Restart-only guard: installed")
            print("Manifest:", "present" if manifest.exists() else "missing")
        else:
            print("Restart-only guard: not installed")
        return 0

    if args.command == "dry-run":
        after = patch(before)
        syntax_check(after)
        print("[pass] Recognized restart source and Bash syntax")
        print("[pass] Agent files and all runtime services untouched")
        print("[status]", "already installed" if after == before else "upgrade applicable")
        return 0

    if args.command == "install":
        after = patch(before)
        syntax_check(after)
        if after == before:
            print("[ready] Restart-only guard already installed; no changes")
            return 0
        if manifest.exists():
            raise ValueError("Backup manifest already exists; refusing unmanaged update")
        bdir.mkdir(parents=True, exist_ok=True)
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        backup = bdir / ("zarzysseus.sh.restart-only." + stamp + ".bak")
        with backup.open("xb") as f:
            f.write(before)
        os.chmod(backup, 0o600)
        state = {"file": str(source), "backup": str(backup),
                 "original_sha256": digest(before), "installed_sha256": digest(after)}
        state_text = (json.dumps(state, indent=2) + "\n").encode("utf-8")
        fd, manifest_tmp = tempfile.mkstemp(prefix=".zar-restart-manifest-", dir=bdir)
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(state_text)
                f.flush()
                os.fsync(f.fileno())
            os.chmod(manifest_tmp, 0o600)
            atomic_write(source, after, source.stat().st_mode & 0o777)
            os.replace(manifest_tmp, manifest)
        finally:
            if os.path.exists(manifest_tmp):
                os.unlink(manifest_tmp)
        print("[installed] Restart-only guard (zarzysseus.sh only)")
        print("[backup]", backup)
        return 0

    # Rollback only if the currently installed bytes and original backup match manifest.
    if not manifest.is_file():
        raise ValueError("No manifest for safe rollback; no changes")
    state = json.loads(manifest.read_text("utf-8"))
    backup = Path(state.get("backup", ""))
    if source != Path(state.get("file", "")):
        raise ValueError("Manifest belongs to another source")
    if digest(before) != state.get("installed_sha256"):
        raise ValueError("Source was modified after installation; refusing rollback")
    if not backup.is_file():
        raise ValueError("Backup missing")
    saved = backup.read_bytes()
    if digest(saved) != state.get("original_sha256"):
        raise ValueError("Backup changed; refusing rollback")
    syntax_check(saved)
    atomic_write(source, saved, source.stat().st_mode & 0o777)
    manifest.unlink()
    print("[restored] Original Zarzysseus launcher. Backup preserved:", backup)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, UnicodeError, ValueError, json.JSONDecodeError) as exc:
        print("[refused]", exc, file=sys.stderr)
        sys.exit(2)
