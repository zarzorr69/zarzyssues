"""Replay explicitly recorded Zarzysseus source repairs on the same upstream code.

The index and content-addressed before/after files live in Odysseus's existing
data volume. Changed upstream files or damaged blobs stop replay before app load.
"""
import hashlib
import json
import os
from pathlib import Path
import tempfile

SOURCE_DIRS = ('src', 'routes', 'static')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def target_path(root, relative):
    relative_path = Path(relative)
    if (relative_path.is_absolute() or '..' in relative_path.parts
            or len(relative_path.parts) < 2 or relative_path.parts[0] not in SOURCE_DIRS
            or relative_path.suffix not in ('.py', '.js', '.html', '.css')):
        raise ValueError(f'Invalid managed source path: {relative}')
    target = root / relative_path
    if target.resolve().is_relative_to(root.resolve()) and target.is_file() and not target.is_symlink():
        return target
    raise ValueError(f'Managed source missing or outside app root: {relative}')


def read_index(storage):
    index = storage / 'index.json'
    if not index.is_file():
        return {'version': 1, 'files': {}}
    state = json.loads(index.read_text())
    if state.get('version') != 1 or not isinstance(state.get('files'), dict):
        raise ValueError('Unknown Zarzysseus overlay index format.')
    return state


def atomic_write(path, data, mode=0o644):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.zar-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def read_blob(storage, checksum):
    if not isinstance(checksum, str) or len(checksum) != 64 or any(c not in '0123456789abcdef' for c in checksum):
        raise ValueError('Invalid source blob checksum.')
    data = (storage / 'blobs' / checksum).read_bytes()
    if digest(data) != checksum:
        raise ValueError('Zarzysseus source blob checksum mismatch.')
    return data


def apply(root, storage):
    """Validate every managed file first; never copy old patches onto new code."""
    root, storage = Path(root), Path(storage)
    state = read_index(storage)
    plan = []
    for relative, record in state['files'].items():
        path = target_path(root, relative)
        before = read_blob(storage, record['base'])
        after = read_blob(storage, record['patched'])
        current = digest(path.read_bytes())
        if current not in (digest(before), digest(after)):
            raise ValueError(f'Upstream source changed: {relative}. Old Zarzysseus repair was not replayed.')
        if current != record['patched']:
            plan.append((path, after, path.stat().st_mode & 0o777))
    for path, data, mode in plan:
        atomic_write(path, data, mode)
    return len(state['files'])


def snapshot(root):
    root = Path(root)
    files = {}
    for dirname in SOURCE_DIRS:
        for path in (root / dirname).rglob('*'):
            if path.is_file() and not path.is_symlink() and path.suffix in ('.py', '.js', '.html', '.css'):
                relative = path.relative_to(root).as_posix()
                target_path(root, relative)
                files[relative] = path.read_bytes()
    return files


def capture(root, storage, before):
    """Record changed existing source only; keep the original image baseline."""
    root, storage = Path(root), Path(storage)
    state = read_index(storage)
    changed = []
    after = snapshot(root)
    if before.keys() != after.keys():
        raise ValueError('A repair added/deleted source files; automatic replay needs review.')
    for relative, previous in before.items():
        data = after[relative]
        if previous == data:
            continue
        record = state['files'].get(relative)
        if record:
            if digest(previous) != record['patched']:
                raise ValueError(f'Managed source was edited outside the toolkit: {relative}')
            base = read_blob(storage, record['base'])
        else:
            base = previous
        if data == base:
            state['files'].pop(relative, None)
        else:
            if relative.endswith('.py'):
                compile(data, relative, 'exec')
            for content in (base, data):
                checksum = digest(content)
                blob = storage / 'blobs' / checksum
                if blob.exists():
                    read_blob(storage, checksum)
                else:
                    atomic_write(blob, content)
            state['files'][relative] = {'base': digest(base), 'patched': digest(data)}
        changed.append(relative)
    atomic_write(storage / 'index.json', (json.dumps(state, indent=2, sort_keys=True) + '\n').encode())
    return changed
