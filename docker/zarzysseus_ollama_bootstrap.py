"""Idempotently register an existing Docker Ollama service in Odysseus.

This runs at application startup, after the Docker Ollama dependency is healthy.
No chat model is downloaded, launched, selected, or deleted. The user-facing
endpoint and its model cache are created only after Ollama returns a real
inventory. Existing manually configured endpoints are left untouched.
"""

import json
from urllib.parse import urlsplit, urlunsplit
from urllib.request import urlopen

MANAGED_ID = "zarzysseus-cpu-ollama"


def _urls(raw_base):
    parsed = urlsplit((raw_base or "").strip().rstrip("/"))
    if (parsed.scheme != "http" or not parsed.hostname or parsed.username
            or parsed.password or parsed.query or parsed.fragment
            or parsed.path not in ("", "/", "/v1")):
        raise ValueError("Unsupported local Ollama base URL")
    root = urlunsplit((parsed.scheme, parsed.netloc, "", "", ""))
    return root, root + "/v1"


def read_inventory(base_url, timeout=5):
    """Get actual local Ollama names; never invent model IDs or call chat."""
    root, endpoint_url = _urls(base_url)
    with urlopen(root + "/api/tags", timeout=timeout) as response:
        result = json.load(response)
    models = result.get("models")
    if not isinstance(models, list):
        raise ValueError("Ollama returned an unexpected model inventory")
    names = []
    for item in models:
        if not isinstance(item, dict) or not isinstance(item.get("name"), str):
            continue
        name = item["name"].strip()
        if name and name not in names:
            names.append(name)
    return endpoint_url, names


def sync(base_url="http://cpu-ollama:11434"):
    """Insert a shared endpoint once, preserving user endpoints and settings.

    An empty inventory is not evidence that a model is available; we refuse to
    create a misleading empty endpoint. Existing managed rows are not disabled
    or wiped if Ollama becomes temporarily inaccessible.
    """
    url, names = read_inventory(base_url)
    if not names:
        return "skipped: Ollama reports no models"

    # Import only after Odysseus has prepared its normal DB and migrations.
    from core.database import ModelEndpoint, SessionLocal
    db = SessionLocal()
    try:
        same_url = db.query(ModelEndpoint).filter(ModelEndpoint.base_url == url).first()
        if same_url is not None and same_url.id != MANAGED_ID:
            return f"already registered as {same_url.id} ({len(names)} models); preserving manual settings"

        owned = db.query(ModelEndpoint).filter(ModelEndpoint.id == MANAGED_ID).first()
        if owned is not None and owned.base_url != url:
            raise ValueError("Managed endpoint ID is occupied by a different URL")
        if owned is None:
            db.add(ModelEndpoint(
                id=MANAGED_ID,
                name="ZimaOS Ollama (CPU)",
                base_url=url,
                api_key=None,
                is_enabled=True,
                hidden_models="[]",
                cached_models=json.dumps(names),
                pinned_models="[]",
                model_type="llm",
                endpoint_kind="local",
                model_refresh_mode="auto",
                owner=None,
            ))
            db.commit()
            return f"registered {url} with {len(names)} models"
        if not owned.is_enabled:
            return "skipped: managed endpoint was explicitly disabled"
        cached = json.dumps(names)
        if owned.cached_models != cached:
            owned.cached_models = cached
            db.commit()
            return f"refreshed {len(names)} models in existing managed endpoint"
        return f"already synchronized ({len(names)} models)"
    except Exception:
        db.rollback()
        raise
    finally:
        db.close()
