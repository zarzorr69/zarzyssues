#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"

if ! command -v docker >/dev/null 2>&1; then
  printf '%s\n' 'Docker is required. This kit does not install host packages.' >&2
  exit 1
fi
if docker compose version >/dev/null 2>&1; then
  COMPOSE=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE=(docker-compose)
else
  printf '%s\n' 'Docker Compose is required.' >&2
  exit 1
fi
dc() { "${COMPOSE[@]}" --env-file .env -f compose.yaml "$@"; }
if [[ ! -f .env ]]; then (umask 077; cp .env.example .env); fi

if [[ "${1:-}" == zarzysseus ]]; then
  shift
  exec bash ./zarzysseus-docker.sh "$@"
fi

profile=${2:-quality}
case "$profile" in
  agent) model=lfm2.5-zarzysseus-cpu:2.6b; base=LiquidAI/lfm2.5-2.6b:q4_k_m ;;
  quality) model=qwen3.5-zarzysseus-cpu:4b; base=qwen3.5:4b-q4_K_M ;;
  moe) model=lfm2.5-zarzysseus-cpu:8b-a1b; base=lfm2.5:8b-a1b-q4_K_M ;;
  *) printf '%s\n' 'Profile must be agent, quality, or moe.' >&2; exit 2 ;;
esac
budget=1024
[[ "$profile" == quality ]] && budget=256

start_model_server() {
  dc up -d "$@" cpu-ollama
  local attempt
  for attempt in {1..60}; do
    if dc exec -T cpu-ollama ollama list >/dev/null 2>&1; then return; fi
    sleep 1
  done
  dc logs --tail 60 cpu-ollama
  printf '%s\n' 'Ollama did not become reachable; no model readiness claim is being made.' >&2
  exit 1
}

case "${1:-help}" in
  setup)
    start_model_server
    printf 'Downloading %s; Ollama will show live progress.\n' "$base"
    dc exec -T cpu-ollama ollama pull "$base"
    dc exec -T cpu-ollama ollama create "$model" -f "/profiles/Modelfile.$profile"
    dc run --rm bench "$model" --threads 2 --tool-only --tool-predict "$budget"
    printf '\nProfile created: %s. Run the benchmark before choosing it for everyday use.\n' "$model"
    ;;
  benchmark)
    start_model_server
    dc run --rm bench "$model" --threads 2 --quick --predict "$budget" --tool-predict "$budget"
    ;;
  warm)
    start_model_server --pull never --no-deps
    dc run --pull never --no-deps --rm bench "$model" --threads 2 --preload-only --predict "$budget"
    printf '\nModel loaded. The keep-alive interval is shown above; MODEL_KEEP_ALIVE defaults to 30m.\n'
    ;;
  repair-agent)
    dc exec -T cpu-ollama ollama list >/dev/null
    dc exec -T cpu-ollama ollama create lfm2.5-zarzysseus-cpu:2.6b -f /profiles/Modelfile.agent
    dc run --pull never --no-deps --rm bench lfm2.5-zarzysseus-cpu:2.6b --threads 2 --tool-only
    ;;
  app)
    # SearxNG gets a unique key locally; no shared secret is shipped in the kit.
    mkdir -p config/searxng workspace
    if [[ ! -s config/searxng/settings.yml ]]; then
      umask 077
      secret=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
      printf 'use_default_settings: true\nserver:\n  secret_key: "%s"\n  bind_address: "0.0.0.0"\n  port: 8080\nsearch:\n  formats:\n    - html\n    - json\n' "$secret" > config/searxng/settings.yml
      chmod 644 config/searxng/settings.yml
    fi
    # Match the upstream image's PUID/PGID-aware ownership handling for workspace.
    if [[ $(id -u) == 0 ]]; then
      app_uid=$(sed -n 's/^APP_UID=//p' .env | tail -n 1)
      app_gid=$(sed -n 's/^APP_GID=//p' .env | tail -n 1)
      chown "${app_uid:-999}:${app_gid:-1000}" workspace
    fi
    dc --profile app up -d odysseus
    printf '%s\n' 'Application containers started. Check logs and open the configured APP_BIND / APP_PORT.'
    printf '%s\n' 'In Odysseus choose native Ollama, then qwen3.5-zarzysseus-cpu:4b. Keep Thinking off.'
    printf '%s\n' 'The CPU guard applies the tested fast settings to this alias on the native Ollama route.'
    ;;
  status) dc --profile app ps; dc exec -T cpu-ollama ollama ps; dc exec -T cpu-ollama ollama list ;;
  logs) dc --profile app logs --tail 100 ;;
  stop) dc --profile app stop ;;
  down) dc --profile app down ;;
  *)
    printf '%s\n' 'Usage: sudo bash run.sh {setup|benchmark|warm} [agent|quality|moe]'
    printf '%s\n' '       sudo bash run.sh {repair-agent|app|status|logs|stop|down}'
    printf '%s\n' '       sudo bash run.sh zarzysseus [install|doctor|repair|COMMAND]'
    printf '%s\n' 'setup downloads only the requested model. app starts a separate upstream Odysseus instance.'
    printf '%s\n' 'down preserves the named model/application volumes.'
    [[ "${1:-help}" == help || "${1:-help}" == -h || "${1:-help}" == --help ]] || exit 2
    ;;
esac
