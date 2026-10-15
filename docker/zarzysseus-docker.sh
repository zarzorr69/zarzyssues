#!/usr/bin/env bash
# Zarzysseus Docker edition: shared categories with native Linux, container-scoped actions.
# Never uses the native installer on the ZimaOS host.
set -euo pipefail
cd -- "${ZARZYSSEUS_KIT_DIR:-$(dirname -- "${BASH_SOURCE[0]}")}"
[[ -f compose.yaml && -f run.sh ]] || { echo 'Not a Zarzysseus Docker kit: compose.yaml/run.sh missing.' >&2; exit 2; }
if [[ ! -f .env ]]; then (umask 077; cp .env.example .env); fi

# ZimaOS commonly needs sudo for Docker. Respect it only for Docker actions;
# never run the host-native Zarzysseus script as root.
DOCKER=(docker)
if [[ "${ZARZYSSEUS_DOCKER_SUDO:-auto}" == 1 ]]; then
    DOCKER=(sudo docker)
elif [[ "${ZARZYSSEUS_DOCKER_SUDO:-auto}" != 0 ]] && ! docker info >/dev/null 2>&1; then
    if command -v sudo >/dev/null 2>&1 && { sudo -n docker info >/dev/null 2>&1 || { [[ -t 0 ]] && sudo -v && sudo docker info >/dev/null 2>&1; }; }; then
        DOCKER=(sudo docker)
    fi
fi
if "${DOCKER[@]}" compose version >/dev/null 2>&1; then
    COMPOSE=("${DOCKER[@]}" compose)
elif [[ ${#DOCKER[@]} == 1 ]] && command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
else
    printf 'Docker Compose unavailable or permission denied. Check Docker access or use ZARZYSSEUS_DOCKER_SUDO=1.\n' >&2
    exit 2
fi
dc() { "${COMPOSE[@]}" --env-file .env -f compose.yaml "$@"; }
gc() { "${COMPOSE[@]}" --env-file .env -f compose.yaml -f compose.gpu.yaml "$@"; }
profile="${ZARZYSSEUS_PROFILE:-cpu}"
case "$profile" in cpu|full) ;; *) echo "Invalid hardware profile: $profile" >&2; exit 2 ;; esac
setting() { sed -n "s/^$1=//p" .env | tail -n 1; }
app_uid=$(setting APP_UID); app_gid=$(setting APP_GID)
app_uid=${app_uid:-999}; app_gid=${app_gid:-1000}
[[ "$app_uid" =~ ^[0-9]+$ && "$app_gid" =~ ^[0-9]+$ && "$app_uid" != 0 ]] || {
    echo 'Docker helper requires numeric non-root APP_UID and APP_GID in .env.' >&2; exit 2;
}
bridge() {
    if [[ -t 0 && -t 1 ]]; then
        dc exec --user "$app_uid:$app_gid" odysseus python /cpu-kit/zarzysseus_bridge.py "$@"
    else
        dc exec -T --user "$app_uid:$app_gid" odysseus python /cpu-kit/zarzysseus_bridge.py "$@"
    fi
}
native() { bridge run "$@"; }
kit_run() {
    if [[ ${DOCKER[0]} == sudo ]] && [[ $(id -u) != 0 ]]; then
        # The kit's run.sh uses docker directly, so the root wrapper is needed
        # on ZimaOS without Docker group membership.
        sudo bash ./run.sh "$@"
    else
        bash ./run.sh "$@"
    fi
}
kit_state() {
    echo '=== Docker stack ==='; dc --profile app ps || :
    echo '=== Mode / configured endpoint ==='
    printf 'Docker hardware profile: %s\n' "$profile"
    printf 'Stack directory: %s\n' "$PWD"
    printf 'Listen: %s:%s\n' "$(setting APP_BIND)" "$(setting APP_PORT)"
    echo '=== Docker toolkit ==='; bridge status || echo 'Toolkit unavailable: start app and choose Install toolkit.'
}
require_confirmation() {
    local prompt="${1:?Approval keyword required}" reply
    local description="${2:-This action may download images/models or change the Docker stack.}"
    if [[ "${ZARZYSSEUS_CONFIRM:-}" == "$prompt" ]]; then return 0; fi
    [[ -t 0 ]] || { printf 'Approval required: %s. Run interactively.\n' "$prompt" >&2; return 2; }
    printf '%s\nType %s to proceed: ' "$description" "$prompt"
    read -r reply || return 2
    [[ "$reply" == "$prompt" ]] || { echo 'Cancelled.'; return 2; }
}
docker_install() {
    echo 'Docker installation: Ollama + Qwen3.5 4B + Odysseus + ChromaDB + SearXNG.'
    if [[ "$profile" == full ]]; then
        echo 'Full profile enables additional GPU runtime controls, but never pulls GPU weights or launches SGLang automatically.'
    fi
    echo 'Existing named volumes and .env will be retained. Images/models may be downloaded.'
    echo 'The initial model is optional: a 4th-gen i7 may run slowly.'
    require_confirmation INSTALL || return 2
    kit_run setup quality
    kit_run app
    bridge install
    echo 'Container installed. Use status and doctor; set APP_BIND/APP_ORIGIN for remote access.'
}
repair_core() {
    local action failures=0
    for action in agent-tool-focus-install container-agent-repair chat-continuity-fix tool-json-fix; do
        printf '\nRepair: %s\n' "$action"
        native "$action" || failures=$((failures + 1))
    done
    printf 'Repair actions failed: %s\n' "$failures"
    if (( failures == 0 )); then dc restart odysseus; else return 2; fi
}
gpu_doctor() {
    local pinned='ghcr.io/amd-aim/sglang-radeon@sha256:e9c8365e6e0a7e63c1241aa9d0de8acd104d19ad785a45fc1b76215b541184d1'
    if [[ ! -e /dev/kfd || ! -d /dev/dri ]]; then
        echo 'No ROCm device detected. On CPU-only ZimaOS, use the Ollama profiles instead.' >&2
        return 2
    fi
    if ! "${DOCKER[@]}" image inspect "$pinned" >/dev/null 2>&1; then
        echo "RDNA3 image not cached: $pinned"
        require_confirmation PULL || return 2
        "${DOCKER[@]}" pull "$pinned"
    fi
    "${DOCKER[@]}" run --rm --network none --device /dev/kfd --device /dev/dri \
        --security-opt no-new-privileges --shm-size 8g "$pinned" sglang-rdna3 doctor
}
readiness() {
    # Health check is not a promise of successful inference; requires separate test.
    local url="${1:-http://127.0.0.1:30000}"
    case "$url" in http://127.0.0.1:*|http://localhost:*) ;; *) echo 'Only loopback health URLs supported by this diagnostic.' >&2; return 2 ;; esac
    command -v curl >/dev/null || { echo 'curl unavailable.' >&2; return 2; }
    printf '=== HTTP readiness (%s) ===\n' "$url"
    curl --fail --silent --show-error --max-time 8 "$url/health" >/dev/null || { echo 'Not ready.'; return 2; }
    echo 'Health endpoint responded. Confirm supported model and actual generation separately.'
    curl --fail --silent --show-error --max-time 8 "$url/v1/models" || :
}
# Pinned, independently checked AMD-AIM RDNA3 image. GPU service in compose.gpu.yaml
# uses the same digest by default. No daemon/network configuration is modified.
gpu_image() {
    local configured
    configured="$(setting RDNA3_IMAGE)"
    echo "${configured:-ghcr.io/amd-aim/sglang-radeon@sha256:e9c8365e6e0a7e63c1241aa9d0de8acd104d19ad785a45fc1b76215b541184d1}"
}
gpu_require_full() {
    [[ "$profile" == full ]] || { echo 'CPU-only profile. Switch to Full before managing a GPU engine.' >&2; return 2; }
    [[ -e /dev/kfd && -d /dev/dri ]] || { echo 'ROCm GPU devices missing: GPU server unavailable on this host. The CPU stack remains available.' >&2; return 2; }
    [[ -f compose.gpu.yaml ]] || { echo 'GPU overlay missing; use docker-kit-sync from the V11.1 release.' >&2; return 2; }
}
gpu_dns_check() {
    local dns_override="${1:-}" img
    gpu_require_full || return 2
    img="$(gpu_image)"
    if ! "${DOCKER[@]}" image inspect "$img" >/dev/null 2>&1; then
        echo 'RDNA3 image is not cached. Choose GPU Doctor (with explicit approval) before DNS checking.' >&2
        return 2
    fi
    # Match the actual Compose network when it already exists; do not claim
    # a bridge-network test proves resolution inside a different network.
    local test_network=bridge
    if "${DOCKER[@]}" network inspect zarzysseus-cpu-private >/dev/null 2>&1; then
        test_network=zarzysseus-cpu-private
    else
        echo 'Compose network does not exist yet; testing default bridge only. Start the CPU stack before final GPU readiness testing.'
    fi
    local -a args=(run --rm --network "$test_network" --security-opt no-new-privileges --entrypoint python)
    if [[ -n "$dns_override" ]]; then
        [[ "$dns_override" =~ ^[0-9a-fA-F:.]+$ ]] || { echo 'Expected an IPv4/IPv6 DNS server address.' >&2; return 2; }
        echo 'One-off Docker DNS override test. This resolver may bypass your normal Pi-hole policy.'
        args+=(--dns "$dns_override")
    fi
    printf 'Checking Hugging Face DNS + HTTPS on Docker network %s (no model download).\n' "$test_network"
    "${DOCKER[@]}" "${args[@]}" "$img" -c 'import socket,ssl,sys
host="huggingface.co"
try:
    records=socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)
    print("DNS_OK",host,records[0][4][0],flush=True)
    sock=socket.create_connection((host,443),timeout=10)
    with ssl.create_default_context().wrap_socket(sock,server_hostname=host) as tls:
        print("HTTPS_OK",tls.version(),flush=True)
except Exception as e:
    print("DNS_OR_HTTPS_FAILED",type(e).__name__,str(e),file=sys.stderr,flush=True)
    sys.exit(2)'
}
gpu_start() {
    gpu_require_full || return 2
    local img
    img="$(gpu_image)"
    [[ "$img" == ghcr.io/amd-aim/sglang-radeon@sha256:* ]] || {
        echo 'GPU image override is not a pinned trusted digest; review before running.' >&2
        return 2
    }
    echo 'GPU launch: requires working Docker DNS, downloads model weights on first run; persistent cache volume is retained.'
    echo 'Model will be served at 127.0.0.1:30000 only; no automatic chat model switching.'
    require_confirmation GPU || return 2
    if ! "${DOCKER[@]}" image inspect "$img" >/dev/null 2>&1; then
        require_confirmation PULL || return 2
        "${DOCKER[@]}" pull "$img" || return 2
    fi
    gpu_dns_check || { echo 'Docker DNS/HTTPS check failed. Not starting SGLang; diagnose Docker resolver before retrying.' >&2; return 2; }
    gc --profile gpu up -d --no-deps rdna3-sglang || return 2
    echo 'Container launched; NOT yet ready. Check gpu-status and gpu-logs until /health responds.'
}
gpu_status() {
    [[ -f compose.gpu.yaml ]] || { echo 'GPU compose overlay not installed.'; return 2; }
    gc --profile gpu ps rdna3-sglang || :
    local port url
    port="$(setting RDNA3_PORT)"; port="${port:-30000}"
    [[ "$port" =~ ^[0-9]+$ ]] || { echo 'Invalid RDNA3_PORT.' >&2; return 2; }
    url="http://127.0.0.1:$port"
    if command -v curl >/dev/null && curl -fsS --max-time 3 "$url/health" >/dev/null 2>&1; then
        printf '[READY] SGLang health endpoint %s/health responded. Run gpu-test for a generation test.\n' "$url"
    else
        echo '[NOT READY] Health endpoint has not responded; container may be downloading, starting, or failed.'
        echo 'Run gpu-logs. A running container is not proof of inference readiness.'
        return 2
    fi
}
gpu_test() {
    gpu_require_full || return 2
    gpu_status || return 2
    local port model url
    port="$(setting RDNA3_PORT)"; port="${port:-30000}"
    model="$(setting RDNA3_MODEL)"; model="${model:-Qwen/Qwen2.5-0.5B-Instruct}"
    [[ "$model" =~ ^[A-Za-z0-9_./-]+$ ]] || { echo 'Invalid model ID.' >&2; return 2; }
    url="http://127.0.0.1:$port/v1/chat/completions"
    if ! command -v python3 >/dev/null; then
        echo 'Host python3 required for safe inference-test response validation.' >&2; return 2
    fi
    MODEL_ID="$model" python3 -c 'import json,os; print(json.dumps({"model":os.environ["MODEL_ID"],"messages":[{"role":"user","content":"Say hello."}],"max_tokens":32,"temperature":0}))' \
      | curl -fsS --max-time 120 -H 'Content-Type: application/json' --data-binary @- "$url" \
      | python3 -c 'import json,sys; obj=json.load(sys.stdin); choices=obj.get("choices") or []; msg=(choices[0].get("message") or {}) if choices else {}; result=msg.get("content"); assert isinstance(result,str) and result.strip(), "No assistant text returned"; print("INFERENCE_OK:",result)'
}
unsupported() {
    printf 'This is a HOST-ONLY native operation, not safe to run inside Odysseus Docker.\n'
    printf 'Use Zarzysseus Native mode on a supported Linux host for %s.\n' "$1"
    return 2
}
docker_doctor() {
    echo '=== Docker Compose ==='; dc --profile app ps || :
    echo '=== Resources ==='; "${DOCKER[@]}" stats --no-stream --format '{{.Name}} {{.MemUsage}} {{.CPUPerc}}' || :
    echo '=== Toolkit / Agent / MCP / Skills ==='
    bridge status || return 2
    local failures=0
    native container-agent-doctor || failures=$((failures+1))
    native tool-health || failures=$((failures+1))
    native skills-doctor || failures=$((failures+1))
    (( failures == 0 ))
}
dispatch() {
    local action=${1:-tui}; shift || :
    case "$action" in
        tui) menu ;;
        profile) printf 'Docker hardware profile: %s\n' "$profile" ;;
        install|install-full|install-auto-fit) docker_install ;;
        toolkit-install) bridge install ;;
        status|docker-status) kit_state ;;
        start) kit_run app ;;
        stop) dc --profile app stop ;;
        restart) dc --profile app restart odysseus ;;
        logs) dc --profile app logs --tail 120 odysseus ;;
        enable) dc --profile app up -d odysseus ;;
        disable) dc --profile app stop odysseus ;;
        down) dc --profile app down ;;
        models|model-list) dc exec -T cpu-ollama ollama list ;;
        ollama-status) dc ps cpu-ollama; dc exec -T cpu-ollama ollama ps ;;
        ollama-start) dc up -d cpu-ollama ;;
        ollama-stop) dc stop cpu-ollama ;;
        ollama-restart) dc restart cpu-ollama ;;
        warm) kit_run warm "${1:-quality}" ;;
        benchmark) kit_run benchmark "${1:-quality}" ;;
        model-setup) kit_run setup "${1:-quality}" ;;
        pull|opull|ollama-pull)
            [[ $# == 1 && "$1" != -* ]] || { echo 'Usage: pull MODEL:TAG' >&2; return 2; }
            dc exec -T cpu-ollama ollama pull "$1" ;;
        gpu-doctor) gpu_require_full && gpu_doctor ;;
        gpu-dns-check) gpu_dns_check "${1:-}" ;;
        gpu-start) gpu_start ;;
        gpu-status) gpu_status ;;
        gpu-logs) gc --profile gpu logs --tail 120 rdna3-sglang ;;
        gpu-stop) gc --profile gpu stop rdna3-sglang ;;
        gpu-test) gpu_test ;;
        gpu-readiness) readiness "${1:-http://127.0.0.1:30000}" ;;
        doctor) docker_doctor ;;
        repair) repair_core ;;
        agent-rollback|agent-tool-focus-install|container-agent-repair|container-agent-legacy-repair|chat-continuity-fix|tool-json-fix|cookbook-fix|mcp-health|mcp-setup|skills-doctor|skills-health|skills-list|skills-manage-list|skills-permissions|skills-summary-installed|skills-summary|skills-search|skills-install|skills-update|skills-update-one|skills-remove|skills-permissions-set|skills-permissions-clear|skills-setup|skills-mcp-fix|skills-runtime-fix|skills-sync-all|install-personal-skills|model-advisor|model-advisor-json|model-advisor-pins|model-list-json|providers|ollama-sync|tool-health|agent-smoke|agent-doctor)
            if [[ "$action" == agent-doctor ]]; then action=container-agent-doctor; fi
            native "$action" "$@" ;;
        help) cat <<'HELP'
ZARZYSSEUS DOCKER — CPU and opt-in AMD GPU diagnostics
Navigation categories mirror the native edition; implementations run in Compose.
  install                Ask approval, create CPU profile and start existing Compose stack
  toolkit-install        Install checksum-verified Zarzysseus helper into Odysseus
  start/stop/restart/status/logs  Manage the Docker Odysseus instance
  model-setup quality|agent|moe  Explicit CPU model download/profile setup
  models / model-list / pull MODEL / warm / benchmark
  model-advisor / skills-doctor / skills-install NAME / skills-setup
  mcp-health / mcp-setup / cookbook-fix status|progress
  doctor / repair / agent-doctor / agent-rollback
  profile                 Print selected Docker hardware profile
  gpu-doctor              Optional pinned RDNA3 image; explicit consent before pulling
  gpu-dns-check [DNS_IP]   Check Hugging Face DNS + TLS from a disposable container
  gpu-start/gpu-status/gpu-logs/gpu-stop/gpu-test (Full profile, AMD RDNA3)
  gpu-readiness [LOOPBACK_URL]  Health endpoint (not a generation test)
  down                    Stop Compose services, preserve named volumes
Not supported in Docker: native OS updates, driver installers, host systemd,
MLX (macOS), standalone GPU engine installation, unrestricted host file access.
HELP
          ;;
        system-update|accelerator-setup|vllm-install|sglang-install|mlx-install|sam-mask-install|uninstall)
            unsupported "$action" ;;
        *) printf 'Unknown Docker command: %s (run help)\n' "$action" >&2; return 2 ;;
    esac
}

# Docker's menu has an interactive ANSI selector on real terminals, keeping a
# numbered fallback for TERM=dumb, pipes and accessibility preferences.
_ZD_TUI_ACTIVE=0
_zd_restore() {
    if [[ "$_ZD_TUI_ACTIVE" == 1 ]]; then
        printf '\033[?25h\033[?1049l'
        _ZD_TUI_ACTIVE=0
    fi
}
# EXIT also restores the terminal if a command or connection ends unexpectedly.
trap '_zd_restore' EXIT
trap '_zd_restore; exit 130' INT
trap '_zd_restore; exit 143' TERM
_zd_choose() {
    local title="$1"; shift
    local -a items=("$@")
    local count=${#items[@]} selected=1 typed="" key="" extra="" size="" lines=24 cols=80
    local start end i row visible
    ZD_SELECTION=0
    if [[ "${ZARZYSSEUS_MENU_STYLE:-auto}" == plain || ! -t 0 || ! -t 1 || "${TERM:-dumb}" == dumb ]]; then
        printf '\n=== %s ===\n' "$title"
        for ((i=1; i<=count; i++)); do printf '%2d %s\n' "$i" "${items[i-1]}"; done
        printf '%2d %s\n' 0 'BACK / EXIT'
        read -r -p "Select [0-$count]: " ZD_SELECTION || { ZD_SELECTION=0; return 0; }
        [[ "$ZD_SELECTION" =~ ^[0-9]+$ ]] && (( ZD_SELECTION <= count )) || { echo 'Invalid choice.'; ZD_SELECTION=-1; }
        return 0
    fi
    if [[ "$_ZD_TUI_ACTIVE" == 0 ]]; then
        printf '\033[?1049h\033[?25l'
        _ZD_TUI_ACTIVE=1
    fi
    while true; do
        size="$(stty size < /dev/tty 2>/dev/null || echo '24 80')"
        read -r lines cols <<< "$size"
        [[ "$lines" =~ ^[0-9]+$ ]] || lines=24
        [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
        (( lines < 8 )) && lines=8
        (( cols < 22 )) && cols=22
        visible=$((lines - 8)); ((visible < 2)) && visible=2
        start=1
        if (( selected > visible )); then start=$((selected - visible + 1)); fi
        end=$((start + visible - 1)); (( end > count )) && end=count
        printf '\033[H\033[2J\n'
        printf '\033[1;36m  Z A R Z Y S S E U S  •  DOCKER\033[0m\n'
        printf '  %s\n' "$title"
        printf '%s\n' '  ───────────────────────────────────────────'
        printf '  [↑/↓] Navigate  [Enter] Select  [Q] Back  [digits+Enter]\n\n'
        if ((start > 1)); then printf '    ▲ More above\n'; fi
        for ((i=start; i<=end; i++)); do
            if ((i == selected)); then
                printf '\033[7m  ▶ %2d  %-*.*s\033[0m\n' "$i" "$(( cols - 9 ))" "$(( cols - 9 ))" "${items[i-1]}"
            else
                printf '    %2d  %.*s\n' "$i" "$(( cols - 9 ))" "${items[i-1]}"
            fi
        done
        if ((end < count)); then printf '    ▼ More below\n'; fi
        printf '\n    0  BACK / EXIT\n'
        if [[ -n "$typed" ]]; then printf '  Choice: %s\n' "$typed"; fi
        key=''; IFS= read -rsn1 key < /dev/tty || { _zd_restore; return 1; }
        case "$key" in
            $'\e')
                extra=''; IFS= read -rsn2 -t 0.12 extra < /dev/tty || :
                case "$extra" in
                    '[A') ((selected--)); (( selected < 1 )) && selected=$count; typed='' ;;
                    '[B') ((selected++)); (( selected > count )) && selected=1; typed='' ;;
                    *) ZD_SELECTION=0; _zd_restore; return 0 ;;
                esac ;;
            [qQ]) ZD_SELECTION=0; _zd_restore; return 0 ;;
            '')
                if [[ -n "$typed" ]]; then
                    if (( 10#$typed <= count )); then ZD_SELECTION=$((10#$typed)); _zd_restore; return 0; fi
                    typed=''
                else
                    ZD_SELECTION=$selected; _zd_restore; return 0
                fi ;;
            [0-9])
                if [[ "$typed" == 0 ]]; then typed="$key"; else typed="${typed}${key}"; fi
                if (( ${#typed} > 3 )); then typed="$key"; fi
                if (( 10#$typed >= 1 && 10#$typed <= count )); then selected=$((10#$typed)); fi ;;
            [kK]) ((selected--)); ((selected < 1)) && selected=$count; typed='' ;;
            [jJ]) ((selected++)); ((selected > count)) && selected=1; typed='' ;;
        esac
    done
}

# Use the same menu categories as the native edition. Submenus give Docker's
# real equivalent or explain scope limitations; never silently run host-native.
menu() {
    local option
    local -a menu_items=(
        'INSTALL / UPDATE' 'SERVICE MANAGEMENT' 'MODEL RUNTIMES'
        'MODEL MANAGER / HARDWARE FIT' 'OLLAMA MANAGEMENT'
        'MLX-LM MANAGEMENT (native/macOS only)' 'HUGGING FACE / MODEL FILES'
        'SKILLS.SH / AGENT SKILLS' 'MCP / FREEMCP'
        'DIAGNOSTICS / TOOLS / ADVANCED' 'NETWORK DISCOVERABILITY'
        'SWITCH TO NATIVE MODE' 'SWITCH CPU-ONLY / FULL PROFILE'
    )
    while true; do
        _zd_choose "ZARZYSSEUS — DOCKER MODE — ${profile^^} PROFILE" "${menu_items[@]}" || return 0
        option="$ZD_SELECTION"
        case "$option" in
            1) submenu 'INSTALL / UPDATE' 'Install Odysseus + CPU model (always available)|install' 'Install/refresh toolkit helper|toolkit-install' 'Check current status|status' ;;
            2) submenu 'SERVICES' 'Start Odysseus|start' 'Stop services|stop' 'Restart Odysseus|restart' 'Show status|status' 'Show logs|logs' 'Stop containers, retain volumes|down' ;;
            3)
                if [[ "$profile" == full ]]; then
                    submenu 'MODEL RUNTIMES — FULL' 'CPU Ollama readiness|ollama-status' 'AMD RDNA3 diagnostics (no model download)|gpu-doctor' 'Test Docker DNS / Hugging Face HTTPS|gpu-dns-check' 'Start RDNA3 SGLang (explicit consent)|gpu-start' 'GPU readiness|gpu-status' 'GPU logs|gpu-logs' 'Run real generation test|gpu-test' 'Stop GPU model server|gpu-stop'
                else
                    submenu 'MODEL RUNTIMES — CPU-ONLY' 'CPU Ollama readiness|ollama-status' 'List CPU Ollama models|models' 'CPU model benchmark|benchmark quality'
                fi ;;
            4) submenu 'MODEL MANAGER / HARDWARE FIT' 'Skill-aware model advisor|model-advisor' 'Models in CPU Ollama|models' 'Benchmark quality model|benchmark quality' ;;
            5) submenu 'OLLAMA MANAGEMENT' 'Install Qwen3.5 CPU quality profile|model-setup quality' 'Install LFM 2.6B agent profile|model-setup agent' 'Warm quality model|warm quality' 'List installed models|models' 'Pull a named model|prompt:pull' 'Stop model backend|ollama-stop' ;;
            6) unsupported 'macOS MLX-LM on a Linux CPU container' || : ;;
            7) submenu 'HUGGING FACE / MODEL FILES' 'Catalog/model advisor (read only)|model-advisor' 'Why no Hugging Face chat launcher?|info:hf' ;;
            8) submenu 'SKILLS.SH / AGENT SKILLS' 'List installed skills|skills-list' 'Search skill|prompt:skills-search' 'Install selected skill|prompt:skills-install' 'Skills + MCP health|skills-doctor' 'Approve/setup dependencies|skills-setup' 'Skill model advisor|model-advisor' ;;
            9) submenu 'MCP / FREEMCP' 'MCP health|mcp-health' 'MCP setup (may download deps)|mcp-setup' 'Agent diagnostic|agent-doctor' ;;
            10) submenu 'DIAGNOSTICS / TOOLS / ADVANCED' 'Docker + Agent + skills doctor|doctor' 'Apply guarded Agent repairs|repair' 'Cookbook status|cookbook-fix status' 'Cookbook progress repair (version sensitive)|cookbook-fix progress' 'GPU runtime health|gpu-status' 'Show full help|help' ;;
            11) submenu 'NETWORK DISCOVERABILITY' 'Show configured listen address|status' 'How to configure LAN/Tailscale access|info:network' ;;
            12)
                if [[ -n "${ZARZYSSEUS_MODE_SWITCH_CMD:-}" ]]; then
                    bash "$ZARZYSSEUS_MODE_SWITCH_CMD" mode native && exec bash "$ZARZYSSEUS_MODE_SWITCH_CMD" native
                else
                    echo 'Open the unified launcher and run: ./zarzysseus.sh mode native'
                fi
                ;;
            13)
                if [[ -n "${ZARZYSSEUS_MODE_SWITCH_CMD:-}" ]]; then
                    bash "$ZARZYSSEUS_MODE_SWITCH_CMD" profile-menu docker || :
                    exec bash "$ZARZYSSEUS_MODE_SWITCH_CMD" docker tui
                else
                    echo 'Open the unified launcher and run: ./zarzysseus.sh profile docker cpu|full'
                fi ;;
            0|q|Q) return 0 ;;
            *) echo 'Choose a listed number.' ;;
        esac
    done
}
submenu() {
    local title="$1" select idx item action; shift
    local -a labels=()
    for item in "$@"; do labels+=("${item%%|*}"); done
    while true; do
        _zd_choose "$title" "${labels[@]}" || return 0
        select="$ZD_SELECTION"
        [[ "$select" == 0 ]] && return 0
        ((select>=1 && select<=$#)) || { echo 'Invalid choice.'; continue; }
        item="${@:$select:1}"
        action="${item#*|}"
        case "$action" in
            prompt:*)
                local supplied
                read -r -p 'Enter model/skill: ' supplied || return
                [[ -n "$supplied" ]] && dispatch "${action#prompt:}" "$supplied" || : ;;
            info:hf) echo 'Hugging Face download does not prove chat compatibility. Use CPU Ollama for supported generative models; non-chat models need task-specific runtimes.' ;;
            info:network) echo 'Edit .env APP_BIND and APP_ORIGIN, then recreate with start. Restrict network access and keep AUTH_ENABLED=true.' ;;
            *) local -a command_parts=(); read -r -a command_parts <<< "$action"; dispatch "${command_parts[@]}" || echo 'Action failed; inspect output.' ;;
        esac
    done
}

if [[ $# == 0 ]]; then
    if [[ -t 0 && -t 1 ]]; then menu; else dispatch help; fi
else
    dispatch "$@"
fi
