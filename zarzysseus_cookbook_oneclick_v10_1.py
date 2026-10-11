#!/usr/bin/env python3
"""Zarzysseus V10.1 guarded Odysseus Cookbook source/runtime compatibility repair.

Targets verified existing upstream JS shapes. Does NOT install runtimes or infer fake GGUF
repositories. Applies files as one transaction with SHA-256 audited backups and rollback.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time

MARKER = 'ZARZYSSEUS_COOKBOOK_NATIVE_ROUTING_V10_1'
FILES = ('static/js/cookbook.js', 'static/js/cookbookDownload.js', 'static/js/cookbook-hwfit.js')
MANIFEST = 'data/local/patch-backups/cookbook-native-routing-v10_1.json'


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def replace_once(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise ValueError(f'{label}: expected one known upstream anchor, found {count}; no files changed')
    return text.replace(old, new, 1)


def patch_core(text):
    # Keep true GGUF, Ollama, AWQ/GPTQ/FP8 etc. on their existing backends.
    # For plain HF repos with an estimated Q4 row but no GGUF source, download
    # native weights with vLLM (or SGLang on ROCm for general text models).
    # Voxtral Realtime is a supported vLLM realtime ASR model, not chat/GGUF.
    anchor = "  // GGUF → llama.cpp/Ollama-compatible.\n  if (isGgufLike) {"
    if anchor not in text:
        # Alternate upstream whitespace/ASCII comment variants are handled only
        # when the semantic anchor is unique and beside the known backend test.
        matches = list(re.finditer(r'(?m)^(\s*)// GGUF .*\n\1if \(isGgufLike\) \{', text))
        if len(matches) != 1:
            raise ValueError('cookbook.js backend selection differs from verified upstream; no changes')
        anchor = matches[0].group(0)
    insert = '''   // ZARZYSSEUS_COOKBOOK_NATIVE_ROUTING_V10_1:
   // A Q4_K_M *estimate* in hwfit is not evidence of GGUF weights. When
   // no actual GGUF source exists, pick native HF weights instead of sending
   // the user to Direct Download to guess a conversion repo.
   const _zarHasGgufSource = (Array.isArray(model.gguf_sources) && model.gguf_sources.some(s => !!s?.repo))
     || hasGgufFile;
   const _zarGgufRepo = /(?:^|[-_/\\s.])gguf(?:$|[-_/\\s.])/i.test(`${_nm} ${model.quant_repo || ''}`);
   const _zarHfRepo = /^[^\\s/]+\\/[^\\s/]+$/.test(String(model.name || ''));
   const _zarVoxtralRealtime = /(?:^|\\/)voxtral-mini-4b-realtime-arabic$/i.test(String(model.name || ''));
   if (_zarVoxtralRealtime) {
     return { backend: 'vllm', label: 'vLLM · speech (native)' };
   }
   if (isGgufLike && !model.is_gguf && !_zarHasGgufSource && !_zarGgufRepo && _zarHfRepo
       && /^(?:Q[2-8]|IQ[1-8])/.test(q)) {
     if (isRocm) return { backend: 'sglang', label: 'SGLang · native weights' };
     return { backend: 'vllm', label: 'vLLM · native weights' };
   }
'''
    text = replace_once(text, anchor, insert + anchor, 'cookbook.js backend decision')
    return text


def patch_download(text):
    anchor = "  const repo = backend === 'ollama'\n    ? (model.ollama || model.ollama_name || model.name)\n    : (ggufSource?.repo || model.quant_repo || model.name);"
    replacement = '''   // ZARZYSSEUS_COOKBOOK_NATIVE_ROUTING_V10_1: do not download an
   // imaginary quant repository for a native-weight HF model.
   const _zarNative = backend !== 'ollama' && backend !== 'llamacpp' && !!model._zarNativeOnly;
   const repo = backend === 'ollama'
     ? (model.ollama || model.ollama_name || model.name)
     : (_zarNative ? model.name : (ggufSource?.repo || model.quant_repo || model.name));'''
    return replace_once(text, anchor, replacement, 'cookbookDownload.js source choice')


def patch_hwfit(text):
    anchor = '''export function _hwfitRenderList(el, models) {
  if (!el) return;
  models = _sortHwfitRows(models);'''
    replacement = '''export function _hwfitRenderList(el, models) {
   if (!el) return;
   // ZARZYSSEUS_COOKBOOK_NATIVE_ROUTING_V10_1: fix catalog entries
   // that advertise Q4_K_M estimates for native BF16 ASR checkpoints.
   // This is a format correction, not a claim that vLLM is installed.
   models = (Array.isArray(models) ? models : []).map(m => {
     const name = String(m?.name || '');
     if (/(?:^|\\/)voxtral-mini-4b-realtime-arabic$/i.test(name)) {
       return { ...m, quant: 'BF16', quant_repo: null,
         required_gb: Math.max(Number(m.required_gb) || 0, 10.5),
         _zarNativeOnly: true };
     }
     const q = String(m?.quant || '').toUpperCase();
     const knownSource = !!m?.is_gguf
       || (Array.isArray(m?.gguf_sources) && m.gguf_sources.some(s => !!s?.repo))
       || (Array.isArray(m?.gguf_files) && m.gguf_files.some(f => /\\.gguf$/i.test(String(f?.rel_path || ''))));
     const namedGguf = /gguf/i.test(`${m?.quant_repo || ''} ${m?.repo_id || ''} ${name}`);
     if (!knownSource && !namedGguf && /^(?:Q[2-8]|IQ[1-8])/.test(q)
         && /^[^\\s/]+\\/[^\\s/]+$/.test(name)) {
       return { ...m, quant: 'native', quant_repo: null,
         required_gb: Math.max(Number(m.required_gb) || 0, (Number(m.params_b) || 0) * 2.2),
         _zarNativeOnly: true };
     }
     return m;
   });
   models = _sortHwfitRows(models);'''
    text = replace_once(text, anchor, replacement, 'cookbook-hwfit.js model listing')
    # Special-case ASR: no general text chat endpoint, and native runtime support is required.
    anchor = '''  if (modelData.is_image_gen) {
    html += `<div style="font-size:10px;opacity:0.5;margin-top:4px;">'''
    replacement = '''   if (/(?:^|\\/)voxtral-mini-4b-realtime-arabic$/i.test(String(modelData.name || ''))) {
     // ZARZYSSEUS_COOKBOOK_NATIVE_ROUTING_V10_1
     html += `<div class="hwfit-panel-note">Native BF16 Arabic speech-to-text checkpoint (not a general chat LLM). Download uses the official Hugging Face repository; Run requires vLLM with realtime audio support and a compatible GPU/runtime. GPU memory fit alone does not prove runtime readiness.</div>`;
   } else if (modelData._zarNativeOnly) {
     html += `<div class="hwfit-panel-note">No GGUF source exists in this catalog entry. One-click Download uses the original native Hugging Face weights; Run requires a compatible native-serving backend. The catalog quantization estimate is not an actual GGUF file.</div>`;
   }
   if (modelData.is_image_gen) {
     html += `<div style="font-size:10px;opacity:0.5;margin-top:4px;">'''
    return replace_once(text, anchor, replacement, 'cookbook-hwfit.js runtime notice')

PATCHERS = dict(zip(FILES, (patch_core, patch_download, patch_hwfit)))


def atomic_write(path, raw):
    fd, temp = tempfile.mkstemp(prefix='.zar-cookbook-', dir=str(path.parent))
    try:
        with os.fdopen(fd, 'wb') as out:
            out.write(raw)
            out.flush()
            os.fsync(out.fileno())
        shutil.copymode(path, temp)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def install(project):
    manifest = project / MANIFEST
    if manifest.exists():
        return status(project)
    original = {}
    patches = {}
    for rel in FILES:
        path = project / rel
        if not path.is_file():
            raise ValueError(f'missing Cookbook file: {path} (no changes)')
        raw = path.read_bytes()
        text = raw.decode('utf-8')
        if MARKER in text:
            raise ValueError(f'{rel} already contains patch but manifest missing; refusing overwrite')
        patched = PATCHERS[rel](text).encode('utf-8')
        if patched == raw or MARKER not in patched.decode('utf-8'):
            raise ValueError(f'{rel} failed required transformation (no changes)')
        original[rel] = raw
        patches[rel] = patched
    # Pre-validated all files before any mutation. Backups are private and
    # written before source changes. Manifest digest controls rollback.
    backup_dir = manifest.parent / 'cookbook-native-v10_1'
    backup_dir.mkdir(parents=True, exist_ok=True)
    records = []
    for rel in FILES:
        backup = backup_dir / Path(rel).name
        if backup.exists() and backup.read_bytes() != original[rel]:
            raise ValueError(f'existing backup collision: {backup}')
        backup.write_bytes(original[rel])
        records.append(dict(file=rel, before=digest(original[rel]), after=digest(patches[rel]), backup=str(backup.relative_to(project))))
    applied = []
    try:
        for rel in FILES:
            atomic_write(project / rel, patches[rel])
            applied.append(rel)
        manifest.parent.mkdir(parents=True, exist_ok=True)
        fd, temp = tempfile.mkstemp(prefix='.zar-cb-manifest-', dir=str(manifest.parent))
        with os.fdopen(fd, 'w', encoding='utf-8') as out:
            json.dump(dict(version='V10.1', marker=MARKER, files=records), out, indent=2)
        os.replace(temp, manifest)
    except Exception:
        for rel in reversed(applied):
            atomic_write(project / rel, original[rel])
        raise
    print('Cookbook V10.1: installed; corrected catalog source/runtime routing and native-weight download.')
    print(f'Backup manifest: {manifest}')
    return 0


def status(project):
    manifest = project / MANIFEST
    if not manifest.exists():
        print('Cookbook V10.1: not installed')
        return 2
    record = json.loads(manifest.read_text(encoding='utf-8'))
    valid = True
    for item in record['files']:
        p = project / item['file']
        good = p.is_file() and digest(p.read_bytes()) == item['after']
        print(f"{'OK' if good else 'CHANGED'}: {item['file']}")
        valid &= good
    return 0 if valid else 3


def rollback(project):
    manifest = project / MANIFEST
    if not manifest.is_file():
        raise ValueError('not installed; no rollback manifest')
    data = json.loads(manifest.read_text(encoding='utf-8'))
    for entry in data['files']:
        path = project / entry['file']
        backup = project / entry['backup']
        if not path.is_file() or digest(path.read_bytes()) != entry['after']:
            raise ValueError(f'{path} modified since repair; refusing unsafe rollback')
        if not backup.is_file() or digest(backup.read_bytes()) != entry['before']:
            raise ValueError(f'{backup} missing or altered; refusing rollback')
    for entry in data['files']:
        atomic_write(project / entry['file'], (project / entry['backup']).read_bytes())
    manifest.unlink()
    print('Cookbook V10.1: safely rolled back to original verified sources.')
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('action', choices=('install', 'status', 'rollback'))
    ap.add_argument('--project', type=Path, required=True)
    args = ap.parse_args()
    project = args.project.expanduser().resolve()
    if not project.is_dir():
        ap.error(f'missing Odysseus checkout: {project}')
    try:
        return {'install':install, 'status':status, 'rollback':rollback}[args.action](project)
    except (ValueError, OSError, UnicodeError, KeyError) as ex:
        print(f'Cookbook V10.1: {ex}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
