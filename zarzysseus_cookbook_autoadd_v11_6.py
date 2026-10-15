#!/usr/bin/env python3
"""Guarded V11.6 Cookbook Ollama download -> model picker refresh.

Does not download, serve, or switch models. Only reconciles completed,
local Ollama downloads that the Odysseus server can verify.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile

MARKER = "ZARZYSSEUS_COOKBOOK_OLLAMA_AUTOADD_V11_6"
TARGET = "static/js/cookbookRunning.js"
MANIFEST = "data/local/patch-backups/cookbook-ollama-autoadd-v11_6.json"
BACKUP = "data/local/patch-backups/cookbook-ollama-autoadd-v11_6.before.js"
ANCHOR = """function _updateTask(sessionId, updates) {
  const tasks = _loadTasks();
  const task = tasks.find(t => t.sessionId === sessionId);
  if (task) {
    Object.assign(task, updates);
    _saveTasks(tasks);
  }
"""

INSERT = r'''// ZARZYSSEUS_COOKBOOK_OLLAMA_AUTOADD_V11_6
// Only verified Ollama downloads become chat-picker entries. Downloading a
// generic HF checkpoint does not make it a text-generation model.
const _zarAutoAddedSessions = new Set();
async function _zarReconcileOllamaDownload(task) {
  if (!task || task.type !== 'download' || task.payload?.backend !== 'ollama') return;
  // The app's /api/runtime describes *its own* endpoint, not an arbitrary SSH
  // server. Never register a remote model as if it were installed locally.
  if (task.remoteHost || task.payload?.remote_host) return;
  const model = String(task.payload?.repo_id || '').trim();
  if (!/^[A-Za-z0-9][A-Za-z0-9._:/-]{0,180}$/.test(model)) return;
  const id = String(task.sessionId || '');
  if (!id || _zarAutoAddedSessions.has(id)) return;
  _zarAutoAddedSessions.add(id);
  try {
    const rr = await fetch('/api/runtime', { credentials: 'same-origin' });
    if (!rr.ok) throw Error(`Runtime configuration unavailable (${rr.status})`);
    const runtime = await rr.json();
    const base = String(runtime?.ollama_base_url || (!runtime?.in_docker ? 'http://127.0.0.1:11434/v1' : '')).trim();
    if (!base) throw Error('Ollama endpoint is not configured in Odysseus');
    const parsed = new URL(base);
    if (!['http:', 'https:'].includes(parsed.protocol)) throw Error('Invalid Ollama endpoint');
    // The address comes from Odysseus server configuration. The browser never
    // connects to it; Odysseus's admin-only endpoint test makes the request.
    const form = new FormData();
    form.set('base_url', base);
    form.set('endpoint_kind', 'local');
    const check = await fetch('/api/model-endpoints/test', {
      method: 'POST', credentials: 'same-origin', body: form,
    });
    if (!check.ok) throw Error(`Ollama verification failed (${check.status})`);
    const result = await check.json();
    const found = Array.isArray(result?.models) ? result.models.map(x => String(x).toLowerCase()) : [];
    const expected = model.toLowerCase();
    const isFound = found.includes(expected) || (expected.endsWith(':latest')
      ? found.includes(expected.slice(0, -7)) : found.includes(expected + ':latest'));
    if (!isFound) throw Error(`Ollama does not list ${model}; download may not be complete`);
    const fields = new FormData();
    fields.set('name', 'Ollama (Local)');
    fields.set('base_url', base);
    fields.set('model_type', 'llm');
    fields.set('endpoint_kind', 'local');
    fields.set('require_models', 'true');
    // An explicit pin permits the selected model to appear even if a prior
    // endpoint has an allowlist; the API merges it without clearing old pins.
    fields.set('pinned_models', JSON.stringify([model]));
    const added = await fetch('/api/model-endpoints', {
      method: 'POST', credentials: 'same-origin', body: fields,
    });
    if (!added.ok) throw Error(`Could not register Ollama endpoint (${added.status})`);
    if (window.modelsModule?.refreshModels) {
      await window.modelsModule.refreshModels(true, { waitForRefresh: true });
    } else {
      const refreshed = await fetch('/api/models?refresh=true&wait_refresh=true', { credentials: 'same-origin' });
      if (!refreshed.ok) throw Error(`Model catalog refresh failed (${refreshed.status})`);
    }
    uiModule.showToast(`${model} is available in the model picker; select it when ready.`);
  } catch (error) {
    uiModule.showToast(`Ollama download finished, but picker sync needs attention: ${error.message}`, 9000);
  }
}
'''


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_write(path: Path, data: bytes) -> None:
    fd, name = tempfile.mkstemp(prefix='.zar-cookbook-autoadd-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(name, path.stat().st_mode)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def transform(text: str) -> str:
    if MARKER in text:
        raise ValueError('Patch marker already present but no manifest; refusing unsafe overwrite')
    if text.count(ANCHOR) != 1:
        raise ValueError(f'Cookbook task update layout changed (anchor count {text.count(ANCHOR)}); source unchanged')
    updated = text.replace(
        ANCHOR, INSERT + '\n' + ANCHOR.replace('    _saveTasks(tasks);\n',
           "    _saveTasks(tasks);\n    if (updates.status === 'done') {\n      void _zarReconcileOllamaDownload(task);\n    }\n"), 1
    )
    assert updated.count(MARKER) == 1
    return updated


def status(root: Path) -> int:
    file = root / TARGET
    manifest = root / MANIFEST
    if not manifest.is_file():
        print('Cookbook Ollama auto-add V11.6: not installed')
        return 2
    record = json.loads(manifest.read_text())
    ok = file.exists() and sha(file.read_bytes()) == record['after']
    print('Cookbook Ollama auto-add V11.6:', 'INSTALLED' if ok else 'CHANGED; review manually')
    return 0 if ok else 3


def install(root: Path) -> int:
    file = root / TARGET
    manifest = root / MANIFEST
    backup = root / BACKUP
    if manifest.exists():
        return status(root)
    if not file.is_file():
        raise ValueError(f'{file} missing; no changes')
    before = file.read_bytes()
    after = transform(before.decode('utf-8')).encode('utf-8')
    # Never overwrite an existing earlier backup if its contents differ.
    backup.parent.mkdir(parents=True, exist_ok=True)
    if backup.exists() and backup.read_bytes() != before:
        raise ValueError(f'Existing backup differs: {backup}; source unchanged')
    if not backup.exists():
        fd, temp = tempfile.mkstemp(dir=str(backup.parent), prefix='.zar-cb-backup-')
        with os.fdopen(fd, 'wb') as f:
            f.write(before)
        os.replace(temp, backup)
    atomic_write(file, after)
    record = dict(marker=MARKER, file=TARGET, backup=BACKUP, before=sha(before), after=sha(after))
    fd, temp = tempfile.mkstemp(dir=str(manifest.parent), prefix='.zar-cb-manifest-')
    with os.fdopen(fd, 'w') as f:
        json.dump(record, f, indent=2)
    os.replace(temp, manifest)
    print('Cookbook V11.6: verified Ollama downloads now refresh the chat model picker.')
    print('Only local Ollama models are auto-added; HF files never masquerade as chat servers.')
    return 0


def rollback(root: Path) -> int:
    file = root / TARGET
    manifest = root / MANIFEST
    if not manifest.is_file():
        raise ValueError('Patch not installed')
    record = json.loads(manifest.read_text())
    backup = root / record['backup']
    if record['marker'] != MARKER or record['file'] != TARGET:
        raise ValueError('Unexpected manifest; refusing rollback')
    if sha(file.read_bytes()) != record['after'] or sha(backup.read_bytes()) != record['before']:
        raise ValueError('Installed file or backup changed; refusing rollback')
    atomic_write(file, backup.read_bytes())
    manifest.unlink()
    print('Cookbook V11.6: original task UI restored')
    return 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument('action', choices=('install', 'status', 'rollback'))
    p.add_argument('--project', type=Path, required=True)
    a = p.parse_args()
    try:
        return {'install': install, 'status': status, 'rollback': rollback}[a.action](a.project)
    except (ValueError, OSError, KeyError, json.JSONDecodeError) as exc:
        print(f'Cookbook V11.6: {exc}', file=__import__('sys').stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
