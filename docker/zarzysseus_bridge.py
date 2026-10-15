#!/usr/bin/env python3
"""Run the user's actual Zarzysseus repair helpers against container Odysseus.

Install validates and adapts the bundled read-only Zarzysseus Linux script
inside the existing application data volume. The compatibility copy uses the image's Python and never invokes the
native stack installer or the native TUI. Host service control is in the Docker
menu. Source changes are recorded for guarded replay at container startup.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

import zarzysseus_overlay as overlay

COMMIT = 'v11-bundled'
# Updated at release packaging from the exact read-only toolkit bind-mount.
SCRIPT_SHA256 = 'ab25143ee45e66047431bde01024f9e3f2a6b9d64744425b87f6e04687747303'
BUNDLED_TOOLKIT = Path('/cpu-kit/zarzysseus.sh')
CURRENT_NATIVE_RETURN = '''        return [schema for schema in schemas or ()
                if schema.get("function", {}).get("name", schema.get("name")) not in _caller_hard_denials
                and not (tool_policy and tool_policy.block_all_tool_calls)
                and not (delegated_credential and delegated_tool_is_blocked(
                    schema.get("function", {}).get("name", schema.get("name"))))]
'''
READ_ONLY = {'agent-doctor', 'agent-smoke', 'container-agent-doctor', 'container-agent-smoke', 'tool-health', 'mcp-health', 'skills-doctor',
             'skills-health', 'skills-list', 'skills-manage-list', 'skills-permissions',
             'skills-summary-installed', 'skills-summary', 'skills-search',
             'model-advisor', 'model-advisor-json', 'model-advisor-pins', 'providers',
             'model-list', 'model-list-json'}
MUTATING = {'container-agent-repair', 'container-agent-legacy-repair', 'container-agent-rollback', 'agent-rollback', 'agent-tool-focus-install',
            'chat-continuity-fix', 'tool-json-fix', 'cookbook-fix', 'skills-runtime-fix',
            'skills-sync-all', 'skills-install', 'skills-update', 'skills-update-one',
            'skills-remove', 'skills-permissions-set', 'skills-permissions-clear',
            'skills-setup', 'skills-mcp-fix', 'mcp-setup', 'ollama-sync',
            'install-personal-skills'}


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise ValueError('Pinned toolkit layout changed; compatibility copy was not generated.')
    return source.replace(old, new, 1)


def adapt(source):
    if hashlib.sha256(source.encode()).hexdigest() != SCRIPT_SHA256:
        raise ValueError('Toolkit script checksum mismatch; refusing unverified code.')
    source = replace_once(source,
        '    [[ -d "$PROJECT_DIR/.git" || -f "$PROJECT_DIR/.git" ]] && [[ -f "$PROJECT_DIR/app.py" || -f "$PROJECT_DIR/pyproject.toml" ]]',
        '    [[ -f "$PROJECT_DIR/app.py" && -d "$PROJECT_DIR/src" ]]')
    source = replace_once(source, 'OLLAMA_ENDPOINT="http://127.0.0.1:11434"',
                          'OLLAMA_ENDPOINT="${OLLAMA_ENDPOINT:-http://cpu-ollama:11434}"')
    source = replace_once(source,
        'if (( EUID == 0 )); then\n    # Root does not need a privilege wrapper.',
        'if [[ "${ZARZYSSEUS_CONTAINER_MODE:-0}" == 1 ]]; then\n    SUDO=""\nelif (( EUID == 0 )); then\n    # Root does not need a privilege wrapper.')
    source = replace_once(source, 'prepare_project_runtime_context() {\n',
        'prepare_project_runtime_context() {\n    if [[ "${ZARZYSSEUS_CONTAINER_MODE:-0}" == 1 ]]; then cd "$PROJECT_DIR"; return; fi\n')
    source = replace_once(source, 'refresh_existing_odysseus_checkout() {\n',
        'refresh_existing_odysseus_checkout() {\n    [[ "${ZARZYSSEUS_CONTAINER_MODE:-0}" != 1 ]] || return 0\n')
    source = replace_once(source, 'install_missing_packages() {\n',
        'install_missing_packages() {\n'
        '    if [[ "${ZARZYSSEUS_CONTAINER_MODE:-0}" == 1 ]]; then\n'
        '        local package\n'
        '        for package in "$@"; do\n'
        '            pkg_installed "$package" || { echo "Missing image package: $package. Update the container image instead of the ZimaOS host."; return 1; }\n'
        '        done\n'
        '        return 0\n'
        '    fi\n')
    source = source.replace('source "$VENV_DIR/bin/activate"',
        '[[ "${ZARZYSSEUS_CONTAINER_MODE:-0}" == 1 ]] || source "$VENV_DIR/bin/activate"')
    # Preserve the newer upstream caller/policy/delegated-credential filter,
    # then let the original V2 helper narrow only the schemas it returned.
    old_guard = ("    if block.count(return_line) != 1:\n"
                 "        raise ValueError('Upstream routing return shape changed; no changes made')\n")
    new_guard = ("    if block.count(return_line) != 1:\n"
                 f"        native_return = {CURRENT_NATIVE_RETURN!r}\n"
                 "        if block.count(native_return) != 1:\n"
                 "            raise ValueError('Upstream routing return shape changed; no changes made')\n"
                 "        filtered = native_return.replace('        return ', '        schemas = ', 1)\n"
                 "        block = block.replace(native_return, filtered + return_line, 1)\n")
    source = replace_once(source, old_guard, new_guard)
    # Newer upstream code keeps older prompt constants before overriding them.
    # Update only the final top-level assignment, whose value the app uses.
    prompt_start = "    for name in ('_AGENT_RULES', '_API_AGENT_RULES'):\n"
    if source.count(prompt_start) != 1:
        raise ValueError('Pinned prompt patch layout changed.')
    start = source.index(prompt_start)
    end = source.index('    ast.parse(updated)\n    return updated\n', start)
    prompt_patch = '''    for name in ('_AGENT_RULES', '_API_AGENT_RULES'):
        assignments = [node for node in ast.parse(updated).body
            if isinstance(node, ast.Assign)
            and any(isinstance(target, ast.Name) and target.id == name for target in node.targets)
            and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str)]
        if not assignments:
            raise ValueError('Upstream ' + name + ' prompt assignment changed; no changes made')
        node = assignments[-1]
        lines = updated.splitlines(keepends=True)
        if node.lineno >= len(lines) or lines[node.lineno] not in ('## Rules\\n', '## Base rules\\n'):
            raise ValueError('Upstream ' + name + ' prompt header changed; no changes made')
        lines.insert(node.lineno + 1, RULE)
        updated = ''.join(lines)
'''
    source = source[:start] + prompt_patch + source[end:]
    source = replace_once(source, 'case "$ACTION" in\n    tui)\n',
        'case "$ACTION" in\n'
        '    container-agent-doctor)\n'
        '        echo "=== Zarzysseus CPU Agent Doctor ==="\n'
        '        if ! agent_reliability status; then echo "CPU core repairs are not installed; choose Apply CPU Agent repairs."; exit 2; fi\n'
        '        agent_reliability smoke\n'
        '        echo "Legacy V3-V8 is a separate version-sensitive chain; it is not part of the CPU core readiness result."\n'
        '        ;;\n'
        '    container-agent-smoke)\n'
        '        agent_reliability smoke\n'
        '        ;;\n'
        '    container-agent-rollback)\n'
        '        if grep -Fq ZARZYSSEUS_AGENT_THINKING_RECOVERY_V3 "$PROJECT_DIR/src/agent_loop.py"; then\n'
        '            agent_rollback\n'
        '        else\n'
        '            agent_reliability rollback\n'
        '        fi\n'
        '        ;;\n'
        '    container-agent-repair)\n'
        '        install_qwen_tool_focus\n'
        '        agent_reliability install\n'
        '        agent_reliability smoke\n'
        '        ;;\n'
        '    container-agent-legacy-repair)\n'
        '        install_qwen_tool_focus\n'
        '        agent_reliability_auto_install\n'
        '        agent_reliability smoke\n'
        '        agent_runtime_v3 smoke\n'
        '        ;;\n'
        '    tui)\n')
    return source


def install(root, content=None):
    storage = root / 'data/local/zarzysseus-docker'
    original = storage / 'zarzysseus.original.sh'
    # The mounted release toolkit takes precedence over cached previous releases.
    # Older container compatibility copies remain backed up in data/local.
    if content is None:
        if not BUNDLED_TOOLKIT.is_file():
            raise ValueError('Bundled toolkit missing. Run docker-kit-sync apply on host, then recreate the Odysseus container.')
        content = BUNDLED_TOOLKIT.read_bytes()
        if len(content) > 4 * 1024 * 1024:
            raise ValueError('Unexpected bundled toolkit size.')
    adapted = adapt(content.decode('utf-8')).encode()
    result = subprocess.run(['bash', '-n'], input=adapted, capture_output=True)
    if result.returncode:
        raise ValueError('Toolkit compatibility copy failed Bash syntax validation.')
    overlay.atomic_write(original, content)
    script = storage / 'zarzysseus.container.sh'
    overlay.atomic_write(script, adapted, 0o755)
    overlay.atomic_write(storage / 'installed.json', json.dumps({
        'commit': COMMIT, 'original_sha256': SCRIPT_SHA256,
        'adapter_sha256': overlay.digest(adapted)}, indent=2).encode())
    print(f'Zarzysseus toolkit installed: {COMMIT[:7]}. CPU/Docker actions are available.', flush=True)
    return script


def action_is_mutating(action, arguments):
    if action == 'cookbook-fix' and arguments == ['status']:
        return False
    if action == 'chat-continuity-fix' and arguments == ['status']:
        return False
    return action in MUTATING


def run_action(root, action, arguments):
    if action not in READ_ONLY | MUTATING:
        raise ValueError(f'{action} is a native-only or unsupported action. Use the Docker menu for services and models.')
    if action == 'install-personal-skills' and arguments not in (['office'], ['scripting'], ['transcription']):
        raise ValueError('CPU menu supports explicit office, scripting or transcription favorites; GPU/cloud packs need separate setup.')
    storage = root / 'data/local/zarzysseus-docker'
    script = storage / 'zarzysseus.container.sh'
    if not script.is_file():
        raise ValueError('Install the toolkit first: sudo bash run.sh zarzysseus install')
    state = json.loads((storage / 'installed.json').read_text())
    if state.get('commit') != COMMIT or overlay.digest(script.read_bytes()) != state.get('adapter_sha256'):
        raise ValueError('Installed compatibility copy was modified or is from another toolkit version.')
    replay_dir = storage / 'overlay'
    overlay.apply(root, replay_dir)
    mutating = action_is_mutating(action, arguments)
    before = overlay.snapshot(root) if mutating else None
    env = dict(os.environ, HOME=str(root), PROJECT_DIR=str(root), VENV_DIR=str(Path(sys.executable).parent.parent),
        ZARZYSSEUS_CONTAINER_MODE='1', ZARZYSSEUS_AUTO_DISCOVER='0', SYSTEM_AUTO_UPDATE='0',
        INSTALL_VLLM='0', INSTALL_SGLANG='0', INSTALL_MLX_LM='0', INSTALL_SAM_MASK_FULL='0',
        PATCH_COOKBOOK_SAM_MASK_RECIPE='0', CHROMADB_AUTO_START='0', ZARZYSSEUS_DOCKER_AUTO_INSTALL='0',
        OLLAMA_ENDPOINT='http://cpu-ollama:11434', OLLAMA_OPENAI_ENDPOINT='http://cpu-ollama:11434/v1',
        OLLAMA_HOST='http://cpu-ollama:11434', OLLAMA_DEFAULT_MODEL='qwen3.5-zarzysseus-cpu:4b',
        DEFAULT_MODEL_PROVIDER='ollama', DEFAULT_MODEL_ID='qwen3.5-zarzysseus-cpu:4b',
        OLLAMA_CONTEXT_LENGTH='4096', CHROMADB_HEARTBEAT_URL='http://chromadb:8000/api/v2/heartbeat',
        HF_HOME=str(root / '.cache/huggingface'),
        MANAGED_SCRIPT_PATH=str(script), NPM_CONFIG_CACHE=str(root / 'data/local/npm-cache'))
    # The global skill folders and toolkit preferences are in small named
    # volumes supplied by Compose; the application's existing data stays put.
    result = subprocess.run(['bash', str(script), action, *arguments], env=env, cwd=root)
    if before is not None:
        changed = overlay.capture(root, replay_dir, before)
        print(json.dumps({'source_changes_recorded': changed, 'helper_exit_code': result.returncode}), flush=True)
        print('Restart Odysseus from the Docker menu to load changed code.', flush=True)
    return result.returncode


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-root', type=Path, default=Path('/app'))
    parser.add_argument('operation', choices=['install', 'run', 'status'])
    parser.add_argument('arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    root = args.app_root.resolve()
    try:
        if not (root / 'app.py').is_file():
            raise ValueError(f'No Odysseus app found in {root}.')
        if args.operation == 'install':
            install(root)
            return 0
        if args.operation == 'status':
            storage = root / 'data/local/zarzysseus-docker'
            print(json.dumps({'toolkit_installed': (storage / 'installed.json').is_file(),
                              'pinned_commit': COMMIT,
                              'agent_core': 'V2 plus Qwen focus; source checks still apply',
                              'legacy_v3_v8': 'source-guarded and version-sensitive; must test before claiming parity',
                              'cookbook_v10_2': 'version sensitive; inspected upstream card anchor was rejected',
                              'managed_source_files': list(overlay.read_index(storage / 'overlay')['files'])}, indent=2))
            return 0
        if not args.arguments:
            parser.error('run requires a toolkit action.')
        return run_action(root, args.arguments[0], args.arguments[1:])
    except (OSError, ValueError, RuntimeError) as error:
        print(f'Zarzysseus Docker: {error}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    raise SystemExit(main())
