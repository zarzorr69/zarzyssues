#!/usr/bin/env python3
"""Native Odysseus model endpoint audit and opt-in disable; never touch model weights.

Only local offline endpoints are eligible for disable; SQLite is backed up first.
Supports Odysseus SQLite app.db, not external Postgres installations.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import socket
import sqlite3
import sys
from urllib.parse import urlsplit


def find_db(project: Path) -> Path:
    url = os.environ.get("DATABASE_URL", "").strip()
    envfile = project / ".env"
    if not url and envfile.is_file():
        for line in envfile.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("DATABASE_URL="):
                url = line.partition("=")[2].strip().strip('"').strip("'")
                break
    if url:
        if not url.startswith("sqlite:///") or "?" in url:
            raise ValueError("Only ordinary SQLite DATABASE_URL is supported. Manage other databases in the authenticated Admin UI.")
        # SQLAlchemy absolute SQLite database paths have four slashes.
        dbval = url[len("sqlite:///"):]
        db = Path("/" + dbval) if url.startswith("sqlite:////") else Path(dbval)
        if not db.is_absolute(): db = project / db
    else:
        db = project / "data" / "app.db"
    return db.resolve(strict=True)


def local_reachability(raw_url: str):
    try:
        parsed = urlsplit(raw_url)
        host = (parsed.hostname or "").lower().rstrip(".")
        if parsed.scheme not in {"http", "https"} or host not in {"localhost", "127.0.0.1", "::1"}:
            return "not-local"
        port = parsed.port or (443 if parsed.scheme == "https" else 80)
        with socket.create_connection((host, port), timeout=1.25):
            return "port-open"
    except (OSError, ValueError):
        return "offline"


def rows_from(db):
    con = sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True, timeout=5)
    con.row_factory = sqlite3.Row
    try:
        cols = {row[1] for row in con.execute("PRAGMA table_info(model_endpoints)")}
        needed = {"id", "name", "base_url", "is_enabled", "cached_models", "pinned_models"}
        if not needed.issubset(cols):
            raise ValueError("model_endpoints schema not recognized; refusing to edit anything.")
        return [dict(row) for row in con.execute("SELECT id,name,base_url,is_enabled,cached_models,pinned_models FROM model_endpoints ORDER BY name,id")]
    finally:
        con.close()


def suspect(row):
    text = " ".join(str(row.get(k) or "") for k in ("name", "cached_models", "pinned_models"))
    return "tipsv2" in text.lower() or "tipsv2" in str(row.get("id", "")).lower()


def audit(db):
    rows = rows_from(db)
    print(f"Native Odysseus endpoint doctor | DB: {db}")
    print("Read-only inspection; port-open only confirms a TCP listener, not working chat inference.\n")
    if not rows: print("No model endpoints registered.")
    for n, row in enumerate(rows, 1):
        reach = local_reachability(row['base_url'])
        is_sus = suspect(row)
        state = "enabled" if row['is_enabled'] else "disabled"
        hint = " [NON-CHAT MODEL CANDIDATE]" if is_sus else ""
        print(f"{n}. {row['name']} | {state} | {reach}{hint}")
        print(f"   ID: {row['id']}\n   URL: {row['base_url']}")
    return rows


def disable(db, endpoint_id, confirm):
    rows = rows_from(db)
    hit = [r for r in rows if r['id'] == endpoint_id]
    if len(hit) != 1: raise ValueError("Endpoint ID not found. Run the read-only doctor first.")
    row = hit[0]
    if not row['is_enabled']:
        print("Already disabled; no changes made."); return
    if local_reachability(row['base_url']) != 'offline':
        raise ValueError("Only unreachable localhost endpoints may be disabled by this helper. Use Admin → Services for other endpoints.")
    if not suspect(row):
        raise ValueError("Endpoint does not identify the known tipsv2 non-chat model; use Admin → Services to review manually.")
    # Never disable a shared endpoint that also advertises unrelated chat models.
    for field in ("cached_models", "pinned_models"):
        raw = row.get(field)
        if not raw:
            continue
        try:
            identifiers = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            raise ValueError(f"Unrecognized {field}; review this endpoint in Admin → Services instead.")
        if not isinstance(identifiers, list) or any(not isinstance(x, str) for x in identifiers):
            raise ValueError(f"Unexpected {field} format; declining to change a shared endpoint.")
        if any("tipsv2" not in model_id.lower() for model_id in identifiers):
            raise ValueError("Endpoint also advertises other models; use Admin → Services to manage it manually.")
    print(f"About to DISABLE exactly one endpoint: {row['name']} ({row['id']})")
    print("Existing chats and model downloads will remain. This does not reset your database.")
    if confirm != "DISABLE":
        if not sys.stdin.isatty(): raise ValueError("An interactive terminal is required for consent.")
        if input("Type DISABLE to back up the database and disable this endpoint: ") != "DISABLE":
            raise ValueError("Cancelled; nothing changed.")
    # SQLite's online backup safely includes WAL pages and creates a consistent snapshot.
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = db.parent / f"app.db.zarzysseus-endpoint-backup.{stamp}.{os.getpid()}"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    fd = os.open(backup, flags, 0o600)
    os.close(fd)
    try:
        src = sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True, timeout=10)
        dest = sqlite3.connect(str(backup), timeout=10)
        try: src.backup(dest)
        finally: dest.close(); src.close()
        con = sqlite3.connect(str(db), timeout=15)
        try:
            con.execute("BEGIN IMMEDIATE")
            live = con.execute("SELECT name,base_url,is_enabled,cached_models,pinned_models FROM model_endpoints WHERE id=?", (endpoint_id,)).fetchone()
            if not live or live[0] != row['name'] or live[1] != row['base_url'] or not live[2]:
                raise ValueError("Endpoint changed during review; aborting.")
            changed = con.execute("UPDATE model_endpoints SET is_enabled=0 WHERE id=? AND is_enabled=1", (endpoint_id,)).rowcount
            if changed != 1: raise ValueError("Endpoint update did not affect exactly one row.")
            con.commit()
        except Exception:
            con.rollback(); raise
        finally: con.close()
    except Exception:
        print(f"Backup preserved at {backup}. Database edit not confirmed.", file=sys.stderr)
        raise
    print(f"Disabled only {row['name']}. Private SQLite backup: {backup}")
    print("Refresh the Odysseus page/model catalog and select a real Ollama chat model in a NEW chat.")
    print("The existing chat may still reference tipsv2; no chat history was deleted.")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--project', type=Path, required=True)
    p.add_argument('--disable-id', default=None)
    p.add_argument('--confirm', default=None)
    args = p.parse_args()
    try:
        db = find_db(args.project.resolve())
        if args.disable_id is None: audit(db)
        else: disable(db, args.disable_id, args.confirm)
    except (ValueError, OSError, sqlite3.Error) as exc:
        print("[MODEL ENDPOINT DOCTOR] " + str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__': sys.exit(main())
