"""Offline tests for Docker model endpoint bootstrap; no live server required."""
import importlib.util
import json
import pathlib
import sys
import types
import unittest
from unittest.mock import patch

MODULE_PATH = pathlib.Path(__file__).resolve().parents[1] / "zarzysseus_ollama_bootstrap.py"
spec = importlib.util.spec_from_file_location("zarzysseus_ollama_bootstrap", MODULE_PATH)
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class Record:
    id = "id"
    base_url = "base_url"
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


class Column:
    def __eq__(self, other):
        return other


class Endpoint:
    id = Column()
    base_url = Column()
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


class Query:
    def __init__(self, records):
        self.records = records
        self.value = None
    def filter(self, value):
        self.value = value
        return self
    def first(self):
        for row in self.records:
            if row.id == self.value or row.base_url == self.value:
                return row
        return None


class DB:
    def __init__(self, rows):
        self.rows = rows
        self.commits = 0
    def query(self, model):
        return Query(self.rows)
    def add(self, row):
        self.rows.append(row)
    def commit(self):
        self.commits += 1
    def rollback(self):
        pass
    def close(self):
        pass


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.db = DB([])
        self.core = types.ModuleType("core")
        self.database = types.ModuleType("core.database")
        self.database.ModelEndpoint = Endpoint
        self.database.SessionLocal = lambda: self.db
        self.modules = patch.dict(sys.modules, {"core": self.core, "core.database": self.database})
        self.modules.start()
        self.addCleanup(self.modules.stop)
        self.inventory = patch.object(bootstrap, "read_inventory",
            return_value=("http://cpu-ollama:11434/v1", ["qwen3.5-zarzysseus-cpu:4b", "lfm2.5-zarzysseus-cpu:2.6b"]))
        self.inventory.start()
        self.addCleanup(self.inventory.stop)

    def test_register_once_and_keep_settings(self):
        self.assertIn("registered", bootstrap.sync())
        self.assertEqual(len(self.db.rows), 1)
        row = self.db.rows[0]
        self.assertEqual(row.cached_models, json.dumps(["qwen3.5-zarzysseus-cpu:4b", "lfm2.5-zarzysseus-cpu:2.6b"]))
        self.assertIsNone(row.owner)
        self.assertEqual(self.db.commits, 1)
        self.assertIn("already synchronized", bootstrap.sync())
        self.assertEqual(self.db.commits, 1)

    def test_preserve_existing_manual_endpoint(self):
        self.db.rows.append(Endpoint(id="user-created", base_url="http://cpu-ollama:11434/v1",
                                     is_enabled=True, cached_models='["qwen3.5:4b"]'))
        self.assertIn("preserving manual settings", bootstrap.sync())
        self.assertEqual(self.db.rows[0].cached_models, '["qwen3.5:4b"]')
        self.assertEqual(self.db.commits, 0)

    def test_disabled_endpoint_stays_disabled(self):
        self.db.rows.append(Endpoint(id=bootstrap.MANAGED_ID, base_url="http://cpu-ollama:11434/v1",
                                     is_enabled=False, cached_models="[]"))
        self.assertIn("explicitly disabled", bootstrap.sync())
        self.assertEqual(self.db.commits, 0)

    def test_existing_managed_inventory_is_refreshed(self):
        self.db.rows.append(Endpoint(id=bootstrap.MANAGED_ID, base_url="http://cpu-ollama:11434/v1",
                                     is_enabled=True, cached_models="[]"))
        self.assertIn("refreshed", bootstrap.sync())
        self.assertEqual(self.db.commits, 1)

    def test_empty_models_do_not_create_phantom_endpoint(self):
        bootstrap.read_inventory.return_value = ("http://cpu-ollama:11434/v1", [])
        self.assertIn("skipped", bootstrap.sync())
        self.assertEqual(self.db.rows, [])

    def test_inventory_failure_does_not_touch_db(self):
        bootstrap.read_inventory.side_effect = TimeoutError("Ollama offline")
        with self.assertRaises(TimeoutError):
            bootstrap.sync()
        self.assertEqual(self.db.rows, [])

    def test_url_validation(self):
        for bad in ("file:///etc/passwd", "http://evil:pass@cpu-ollama:11434", "https://api.example.com", "http://cpu-ollama:11434/v1/other"):
            with self.assertRaises(ValueError):
                bootstrap._urls(bad)


if __name__ == "__main__":
    unittest.main()
