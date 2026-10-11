#!/usr/bin/env python3
"""Zarzysseus V9 read-only skill audit and narrowly scoped MCP consent store.

Does not execute skills, access the network, import third-party runners, or probe MCP servers.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import urlparse


def md_frontmatter(path: Path):
    text = path.read_text(encoding="utf-8", errors="replace")
    match = re.match(r"\A---\s*\n(.*?)\n---\s*(?:\n|$)", text, re.S)
    if not match:
        return {}, text
    try:
        from services.memory.skill_format import parse_frontmatter
        data, body = parse_frontmatter(text)
        return data if isinstance(data, dict) else {}, body
    except Exception:
        try:
            import yaml
            data = yaml.safe_load(match.group(1)) or {}
            return data if isinstance(data, dict) else {}, text[match.end():]
        except Exception:
            return {}, text[match.end():]


def declarations(fm):
    for key in ("mcpServers", "mcpservers", "mcp_servers", "mcp-servers"):
        if key in fm:
            value = fm[key]
            break
    else:
        return []
    if isinstance(value, dict):
        return [(str(k), v) for k, v in value.items() if isinstance(v, dict)]
    if isinstance(value, list):
        return [(str(v.get("name") or v.get("id") or f"server-{i+1}"),
                 {k: item for k, item in v.items() if k not in ("name", "id")})
                for i, v in enumerate(value) if isinstance(v, dict)]
    return []


def slug(value):
    return re.sub(r"[^A-Za-z0-9_]+", "_", value.strip()).strip("_").lower()[:36] or "server"


def digest(spec):
    return hashlib.sha256(json.dumps(spec, sort_keys=True, default=str, separators=(",", ":")).encode()).hexdigest()


def load_approvals(project):
    path = project / "data/local/zarzysseus-skill-v9-approvals.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(data, dict) and data.get("version") == 1 and isinstance(data.get("approved"), dict):
            return path, data["approved"]
    except (ValueError, OSError):
        pass
    return path, {}


def installed_servers(project):
    try:
        from core.database import SessionLocal, McpServer
        with SessionLocal() as db:
            return {x.id: {"enabled": bool(x.is_enabled), "transport": x.transport}
                    for x in db.query(McpServer).filter(McpServer.id.like("skill_%")).all()}
    except Exception:
        return None


def expected_names(fm):
    raw = fm.get("requires_toolsets") or []
    if isinstance(raw, str):
        return [x.strip().strip('"\'') for x in re.split(r"[,\s]+", raw.strip("[]")) if x.strip()]
    if isinstance(raw, list):
        return [str(x) for x in raw]
    return []


def requirements_status(skill_dir):
    findings = []
    req = skill_dir / "requirements.txt"
    if req.is_file():
        try:
            from importlib import metadata
            missing = []
            for line in req.read_text(encoding="utf-8", errors="replace").splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if line.startswith(("-", ".", "git+", "http:", "https:")):
                    findings.append("Python requirement uses a non-index/option spec: needs manual verification")
                    continue
                name = re.match(r"([\w.-]+)", line)
                if name:
                    try:
                        metadata.version(name.group(1))
                    except metadata.PackageNotFoundError:
                        missing.append(name.group(1))
            if missing:
                findings.append("missing Python distributions: " + ", ".join(sorted(set(missing))))
        except Exception:
            findings.append("Python requirements not verified")
    if (skill_dir / "package.json").is_file() and not (skill_dir / "node_modules").is_dir():
        findings.append("npm package manifest present but node_modules missing")
    for name in ("run.py", "run.sh", "run.ps1", "runner.py", "runner.sh"):
        if (skill_dir / name).is_file():
            break
    return findings


def visible_server(spec):
    transport = str(spec.get("transport") or ("http" if spec.get("url") else "stdio")).lower()
    if transport in ("http", "sse", "streamable-http", "streamable_http"):
        target = urlparse(str(spec.get("url") or ""))
        return f"remote {transport}: {target.scheme}://{target.netloc or 'unconfigured'} (credentials hidden)"
    command = spec.get("command") or "unspecified"
    if isinstance(command, list):
        command = command[0] if command else "unspecified"
    return f"local stdio executable: {Path(str(command)).name} (arguments and credentials hidden)"


def audit(project, only=None):
    root = project / "data/skills/imported"
    path, approvals = load_approvals(project)
    rows = installed_servers(project)
    collected = []
    for md in sorted(root.glob("*/SKILL.md")):
        if only and md.parent.name != only:
            continue
        fm, body = md_frontmatter(md)
        skill_name = str(fm.get("name") or md.parent.name)
        native = expected_names(fm)
        runnable = any((md.parent / n).exists() for n in ("run.py", "run.sh", "run.ps1", "runner.py", "runner.sh", "scripts", "bin", "tools"))
        issues = requirements_status(md.parent)
        if runnable and not ("bash" in native or "python" in native):
            issues.append("executable skill has no declared native bash/python toolset")
        servers = []
        for name, spec in declarations(fm):
            key = f"{md.parent.name}/{name}"
            server_id = ("skill_" + slug(skill_name) + "_" + slug(name))[:90]
            current = (rows or {}).get(server_id)
            approved = approvals.get(key) == digest(spec)
            state = "enabled-config" if current and current["enabled"] else ("disabled-config" if current else "unregistered")
            if current and current["enabled"] and not approved:
                state = "legacy-enabled-config"
            if not approved and state not in ("legacy-enabled-config",):
                issues.append(f"{name}: explicit MCP approval required")
            if state in ("unregistered", "disabled-config"):
                issues.append(f"{name}: {state}")
            qualified_prefix = f"mcp__{server_id}__"
            if state in ("enabled-config", "legacy-enabled-config") and not any(x.startswith(qualified_prefix) for x in native):
                issues.append(f"{name}: no discovered MCP tools bound to requires_toolsets")
            servers.append({"name": name, "key": key, "spec": spec, "approved": approved,
                            "state": state, "server_id": server_id})
        if not fm:
            issues.append("frontmatter missing or cannot parse")
        collected.append({"folder": md.parent.name, "name": skill_name, "runnable": runnable,
                          "native": native, "servers": servers, "issues": issues})
    return collected, rows is not None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["doctor", "plan", "approve", "test"])
    parser.add_argument("--project", required=True)
    parser.add_argument("--skill", help="Folder name in data/skills/imported; omit for all")
    parser.add_argument("--yes", action="store_true", help="Explicit approval from host TUI/CLI")
    parser.add_argument("--strict", action="store_true", help="Return failure when readiness issues remain")
    args = parser.parse_args()
    project = Path(args.project).expanduser().resolve()
    sys.path.insert(0, str(project))
    os.chdir(project) if project.is_dir() else None
    found, db_ok = audit(project, args.skill)
    if args.skill and not found:
        print(f"ERROR: imported skill not found: {args.skill}", file=sys.stderr)
        return 2
    if args.action == "test":
        print("PASS: V9 skill manager imports and runs; no MCP server launched")
        return 0
    if args.action == "approve":
        if not args.yes:
            print("ERROR: explicit approval required (--yes after reviewing plan)", file=sys.stderr)
            return 2
        path, approvals = load_approvals(project)
        changed = 0
        for skill in found:
            for server in skill["servers"]:
                # Approve exact declaration digest only; secrets are not logged.
                fingerprint = digest(server["spec"])
                if approvals.get(server["key"]) != fingerprint:
                    approvals[server["key"]] = fingerprint
                    changed += 1
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            old_state = json.loads(path.read_text(encoding="utf-8"))
            legacy = old_state.get("legacy", {}) if isinstance(old_state, dict) else {}
        except (OSError, ValueError):
            legacy = {}
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps({"version": 1, "approved": approvals, "legacy": legacy}, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        os.chmod(tmp, 0o600)
        tmp.replace(path)
        print(f"V9 approved {changed} changed MCP declaration(s); approval file restricted to current user")
        return 0
    print(f"Zarzysseus V9 {'SKILL INSTALL PLAN' if args.action == 'plan' else 'AGENT SKILLS HEALTH'}")
    print(f"Imported skills: {len(found)} | DB inspection: {'available' if db_ok else 'unavailable'}")
    unresolved = 0
    for skill in found:
        print(f"\n[{skill['folder']}] {skill['name']}")
        print("  Toolsets:", ", ".join(skill["native"]) if skill["native"] else "none declared")
        if not skill["servers"]:
            print("  MCP: none declared; native/skill runner route only")
        for server in skill["servers"]:
            print(f"  MCP {server['name']}: {visible_server(server['spec'])}")
            print(f"    registration={server['state']} exact-declaration-approved={'yes' if server['approved'] else 'no'}")
        if skill["issues"]:
            unresolved += 1
            for issue in skill["issues"]:
                print(f"  [attention] {issue}")
        else:
            print("  [configured] declared dependencies/tool routing appear ready; LIVE model execution NOT tested")
    print(f"\nSkills needing attention: {unresolved}. This report does not execute skill code or prove live model execution.")
    return 1 if args.strict and unresolved else 0


if __name__ == "__main__":
    raise SystemExit(main())
