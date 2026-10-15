#!/usr/bin/env python3
"""Launch upstream Odysseus with a narrow, reversible CPU profile adapter.

No upstream source file is edited. The Docker image's own entrypoint handles
setup and privileges before running this command. Disable with CPU_PROFILE_GUARD=0.
The adapter affects only the kit's Qwen alias through native Ollama /api/chat.
"""
import argparse
import functools
import importlib
import inspect
import os
from pathlib import Path
import sys

CPU_MODEL = 'qwen3.5-zarzysseus-cpu:4b'


def guard_builder(builder, keep_alive='30m'):
    """Keep the measured non-thinking settings on this alias's native requests."""
    if not callable(builder) or 'model' not in inspect.signature(builder).parameters:
        raise RuntimeError('Upstream native Ollama builder changed; CPU adapter was not installed.')

    @functools.wraps(builder)
    def guarded(*args, **kwargs):
        payload = builder(*args, **kwargs)
        if not isinstance(payload, dict) or 'model' not in payload:
            raise RuntimeError('Upstream native Ollama payload changed; refusing to guess its shape.')
        if payload['model'] == CPU_MODEL:
            # Return a new payload/options mapping: preserve tools, images,
            # streaming, temperature and output limits supplied by Odysseus.
            payload = dict(payload)
            payload['think'] = False
            payload['keep_alive'] = keep_alive
            runtime_options = payload.get('options') or {}
            if not isinstance(runtime_options, dict):
                raise RuntimeError('Upstream native Ollama options are no longer a mapping.')
            payload['options'] = dict(runtime_options, num_ctx=4096, num_thread=2,
                                      num_gpu=0, num_batch=128)
        return payload

    return guarded


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', type=Path, default=Path('/app'))
    parser.add_argument('--host', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=7000)
    args = parser.parse_args(argv)
    app_root = args.app_root.resolve()
    if not (app_root / 'app.py').is_file():
        parser.error(f'No Odysseus app.py found in {app_root}.')
    os.chdir(app_root)
    sys.path.insert(0, str(app_root))
    if os.getenv('ZARZYSSEUS_OVERLAY', '1') == '1':
        import zarzysseus_overlay
        restored = zarzysseus_overlay.apply(
            app_root, app_root / 'data/local/zarzysseus-docker/overlay')
        if restored:
            print(f'Zarzysseus: {restored} managed source files verified/replayed.', flush=True)
    if os.getenv('CPU_PROFILE_GUARD', '1') == '1':
        llm_core = importlib.import_module('src.llm_core')
        llm_core._build_ollama_payload = guard_builder(
            getattr(llm_core, '_build_ollama_payload', None),
            os.getenv('MODEL_KEEP_ALIVE', '30m'))
        print(f'CPU profile guard enabled for {CPU_MODEL}: thinking off, 2 threads, 4096 context.', flush=True)
    uvicorn = importlib.import_module('uvicorn')
    # One process keeps the adapter in the same process as the imported app.
    uvicorn.run('app:app', host=args.host, port=args.port, workers=1)


if __name__ == '__main__':
    main()
