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
# Only Zarzysseus-managed key/value settings are updated. We never source .env
# (which could execute arbitrary shell from a config file) or echo credentials.
_env_update_network() {
    # One atomic update keeps bind/port/origins consistent after interruptions.
    local bind="$1" port="$2" origins="$3" backup tmp
    [[ -f .env && ! -L .env ]] || { echo 'The .env file is missing or a symlink; refusing.' >&2; return 2; }
    if [[ ! -w .env ]]; then
        echo '.env belongs to another user (often root from an earlier sudo kit setup).'
        if [[ -t 0 ]] && command -v sudo >/dev/null 2>&1 && \
           require_confirmation OWNERSHIP 'Change ownership of this one .env file to your current account so the Network menu can save it?'; then
            sudo chown "$(id -u):$(id -g)" .env && sudo chmod 600 .env || return 2
        else
            echo 'Refusing to edit .env without permission; no changes made.' >&2; return 2
        fi
    fi
    for value in "$bind" "$port" "$origins"; do
        [[ "$value" != *$'\n'* && "$value" != *$'\r'* && "$value" != *' '* ]] || return 2
    done
    backup=".env.zarzysseus-backup.$(date +%Y%m%d-%H%M%S).$$"
    (umask 077; cp -p -- .env "$backup") || return 2
    tmp="$(mktemp ./.env.zarzysseus.XXXXXX)" || return 2
    if ! awk -v bind="$bind" -v port="$port" -v origins="$origins" '
        BEGIN { keys["APP_BIND"]=bind; keys["APP_PORT"]=port; keys["APP_ORIGIN"]=origins }
        /^APP_(BIND|PORT|ORIGIN)=/ {
            k=$0; sub(/=.*/, "", k)
            if (!seen[k]++) print k "=" keys[k]
            next
        }
        { print }
        END {
            if (!seen["APP_BIND"]) print "APP_BIND="bind
            if (!seen["APP_PORT"]) print "APP_PORT="port
            if (!seen["APP_ORIGIN"]) print "APP_ORIGIN="origins
        }
    ' .env > "$tmp"; then rm -f -- "$tmp"; return 2; fi
    chmod 600 "$tmp" || { rm -f -- "$tmp"; return 2; }
    mv -f -- "$tmp" .env || return 2
    printf 'Network settings saved atomically. Private backup: %s\n' "$backup"
}
_network_ip_valid() {
    local ip="$1" octet count=0
    [[ "$ip" =~ ^[0-9]+(\.[0-9]+){3}$ ]] || return 1
    local IFS=.
    for octet in $ip; do
        [[ "$octet" =~ ^[0-9]{1,3}$ ]] && ((10#$octet<=255)) || return 1
        ((count+=1))
    done
    (( count==4 ))
}
_network_show() {
    printf 'Zarzysseus Docker network settings (no changes):\n'
    printf '  Host bind:      %s\n' "$(setting APP_BIND)"
    printf '  Host port:      %s\n' "$(setting APP_PORT)"
    printf '  Allowed origins: %s\n' "$(setting APP_ORIGIN)"
    echo 'Docker internal address remains port 7000. Auth stays enabled.'
}
_network_configure() {
    local bind port origin mode choice answer
    _network_show
    printf '\nChoose a host binding:\n  1) This machine only (127.0.0.1)\n  2) One LAN/Tailscale IPv4 address\n  3) All interfaces (0.0.0.0; firewall/reverse proxy required)\n  0) Cancel\n'
    read -r -p 'Binding choice [0-3]: ' choice || return 2
    case "$choice" in
        0|'') return 0 ;;
        1) bind=127.0.0.1 ;;
        2) read -r -p 'Server LAN or Tailscale IPv4: ' bind || return 2
           _network_ip_valid "$bind" || { echo 'Invalid IPv4 address.' >&2; return 2; }
           [[ "$bind" != 0.0.0.0 && "$bind" != 127.* ]] || { echo 'Choose another address.' >&2; return 2; } ;;
        3) bind=0.0.0.0 ;;
        *) echo 'Invalid choice.'; return 2 ;;
    esac
    read -r -p "Host port [$(setting APP_PORT)]: " port || return 2
    port="${port:-$(setting APP_PORT)}"
    [[ "$port" =~ ^[0-9]{1,5}$ ]] && ((10#$port >= 1024 && 10#$port <= 65535)) || { echo 'Port must be 1024–65535.' >&2; return 2; }
    if [[ "$bind" == 127.0.0.1 ]]; then
        origin="http://localhost:$port,http://127.0.0.1:$port"
    else
        printf 'Browser address should be your LAN/Tailscale IP or HTTPS proxy URL.\n'
        read -r -p "Browser origin [http://$bind:$port]: " origin || return 2
        origin="${origin:-http://$bind:$port}"
        if [[ "$origin" == 'http://o.o.o.o:'* || "$origin" == 'https://o.o.o.o:'* ]]; then
            echo 'Looks like letter-o.o.o.o rather than a real server address. Enter your actual LAN/Tailscale IP.' >&2; return 2
        fi
        if [[ "$bind" == 0.0.0.0 && "$origin" == 'http://0.0.0.0:'* ]]; then
            echo '0.0.0.0 is not a browser address. Enter the server LAN IP or an HTTPS origin.' >&2; return 2
        fi
    fi
    [[ "$origin" =~ ^https?://[A-Za-z0-9._:-]+(,https?://[A-Za-z0-9._:-]+)*$ ]] || { echo 'Invalid origin; expected http(s)://host:port, no path or spaces.' >&2; return 2; }
    printf '\nNew bind: %s:%s\nAllowed origins: %s\n' "$bind" "$port" "$origin"
    if [[ "$bind" != 127.0.0.1 ]]; then
        echo 'WARNING: LAN/all-interface exposure may allow other devices to reach Odysseus.'
        echo 'Use a firewall, Tailscale, or HTTPS reverse proxy. Keep authentication and approvals enabled.'
    fi
    require_confirmation NETWORK 'Apply new binding and allowed origins? Existing auth and data will not be changed.' || return 2
    _env_update_network "$bind" "$port" "$origin" || return 2
    if dc --profile app ps --status running --services 2>/dev/null | grep -Fxq odysseus; then
        if require_confirmation RECREATE 'Recreate only the Odysseus service to apply new port binding? A short interruption will occur.'; then
            dc --profile app up -d --no-deps --force-recreate odysseus || return 2
        else
            echo 'Saved configuration; restart/recreate Odysseus later from the Network menu.'
        fi
    else
        echo 'Odysseus was not running; settings take effect at the next start.'
    fi
}
_network_apply() {
    require_confirmation RECREATE 'Recreate Odysseus to apply saved network settings?' || return 2
    dc --profile app up -d --no-deps --force-recreate odysseus
}

# Create an admin ONLY through upstream first-run API; never change existing
# users or save plaintext credentials in Compose .env or shell history.
# First-run credentials are written by upstream AuthManager in a disposable
# Compose container, before the Odysseus web service's first boot. Credentials
# are carried on stdin only; they are never added to .env, CLI args or logs.
_auth_helper_available() {
    [[ -f ./admin_preseed.py && ! -L ./admin_preseed.py ]] &&
      grep -Fq './admin_preseed.py:/cpu-kit/admin_preseed.py:ro' ./compose.yaml
}
_auth_prepare_helper() {
    if _auth_helper_available; then return 0; fi
    echo '[NEEDS SYNC] Your existing Docker kit lacks the first-admin helper or its Compose mount.' >&2
    echo 'No account information has been changed.' >&2
    local launcher="${ZARZYSSEUS_MODE_SWITCH_CMD:-}"
    if [[ -z "$launcher" || ! -f "$launcher" ]]; then
        echo 'Open the full Zarzysseus release and run: bash zarzysseus.sh docker-kit-sync' >&2
        echo 'Then: bash zarzysseus.sh docker-kit-sync apply (confirm SYNC).' >&2
        return 2
    fi
    echo 'Review the non-destructive sync preview before approving any kit changes:' >&2
    bash "$launcher" docker-kit-sync >&2 || return 2
    echo 'This sync can update Compose and kit scripts. It backs up replaced files and preserves .env and volumes.' >&2
    require_confirmation SYNC 'Apply the previewed kit update now? (Backups are kept.)' >&2 || return 2
    # The outer user confirmation is explicit; the sync command also requires
    # the keyword on stdin when launched as an interactive child.
    printf 'SYNC\n' | ZARZYSSEUS_SYNC_CONFIRM=SYNC bash "$launcher" docker-kit-sync apply >&2 || return 2
    _auth_helper_available || { echo 'Admin helper still missing after sync. No account changes made.' >&2; return 2; }
    echo '[OK] Admin helper and Compose mount are ready. Existing accounts remain protected.' >&2
}
_auth_probe() {
    _auth_prepare_helper || return 2
    dc run --rm --no-deps -T --entrypoint python odysseus /cpu-kit/admin_preseed.py status
}
_auth_setup() {
    local state username password verify result
    state="$(_auth_probe)" || { echo '[WARN] Account state could not be checked. No changes made.' >&2; return 2; }
    case "$state" in
        *EXISTING_AUTH_PRESERVED*)
            echo '[SKIP] An admin account already exists. Credentials preserved.'
            echo 'Change the password after logging into Odysseus using Account Settings.'
            return 0 ;;
        *FIRST_RUN_AVAILABLE*) ;;
        *) echo '[WARN] Unexpected account state. No changes made.' >&2; return 2 ;;
    esac
    [[ -t 0 ]] || { echo 'Account setup requires an interactive terminal.' >&2; return 2; }
    echo 'Choose the first admin username and password (password input stays hidden).'
    read -r -p 'Admin username [admin]: ' username || return 2
    username="${username:-admin}"
    [[ "$username" =~ ^[A-Za-z0-9._-]{1,32}$ ]] || { echo 'Username must use letters/digits/._- (max 32).' >&2; return 2; }
    read -rs -p 'Admin password (12+ characters): ' password || return 2; echo
    [[ ${#password} -ge 12 ]] || { echo 'Password must be at least 12 characters.' >&2; unset password; return 2; }
    read -rs -p 'Confirm admin password: ' verify || { unset password; return 2; }; echo
    if [[ "$password" != "$verify" ]]; then echo 'Passwords did not match.' >&2; unset password verify; return 2; fi
    unset verify
    if result="$(printf '%s\n%s\n' "$username" "$password" | dc run --rm --no-deps -T --entrypoint python odysseus /cpu-kit/admin_preseed.py "$app_uid" "$app_gid")"; then
        unset password
        case "$result" in
            *ADMIN_CREATED*) printf '[OK] First admin account created: %s\n' "$username" ;;
            *EXISTING_AUTH_PRESERVED*) echo '[SKIP] An admin account already exists. No credentials changed.' ;;
            *) echo '[WARN] Account setup result was not recognized.' >&2; return 2 ;;
        esac
    else
        unset password
        echo '[WARN] Admin setup failed. Review the error above; no existing accounts are intentionally replaced.' >&2
        return 2
    fi
}
_auth_help() {
    echo 'Zarzysseus Docker account controls:'
    echo '  First-time setup: Accounts / Login -> Create initial admin account.'
    echo '  Existing account: log in to Odysseus and use its Account Settings to change your password.'
    echo '  Security: this CLI never overwrites existing credentials, deletes auth.json, or prints passwords.'
    echo '  Browser address is shown under Network Discoverability -> Show address.'
    echo '  CLI: zarzysseus.sh docker auth-setup  (first-admin only)'
}
_install_step() { printf '\n========== STEP %s/6: %s ==========\n' "$1" "$2"; }
docker_install() {
    echo 'ZARZYSSEUS DOCKER — GUIDED INSTALL'
    echo 'Prerequisites, model downloads, admin account, startup, and toolkit status will be shown.'
    echo 'Existing .env, named volumes, models, and user accounts are preserved.'
    printf 'Hardware policy: %s | Docker Compose project: zarzysseus-cpu\n' "$profile"
    require_confirmation INSTALL 'Start the guided Docker installation? Image/model downloads may take several minutes.' || return 2
    _install_step 1 'Docker Engine and Compose'
    "${DOCKER[@]}" info --format 'Docker Server: {{.ServerVersion}}' || return 2
    dc version || return 2
    _install_step 2 'Current network configuration and existing services'
    _network_show
    dc --profile app ps || :
    _install_step 3 'Ollama and optional CPU quality model'
    local choice
    printf 'Suggested: Qwen3.5 4B (an older i7 may run slowly).\n'
    read -r -p 'Download/prepare this model now? [y/N]: ' choice || return 2
    if [[ "$choice" == [yY]* ]]; then kit_run setup quality || return 2
    else echo '[SKIP] Model download skipped; use Ollama Management later.'; fi
    _install_step 4 'First-run admin account (before application launch)'
    echo 'Admin setup is optional; pre-existing users are never overwritten.'
    read -r -p 'Set the first admin username/password now? [Y/n]: ' choice || return 2
    if [[ "$choice" != [nN]* ]]; then
        _auth_setup || echo '[WARN] No new admin set. An upstream-generated password may appear in the first-start logs.'
    fi
    _install_step 5 'Launch Odysseus, ChromaDB and SearXNG'
    kit_run app || return 2
    dc --profile app ps || :
    _install_step 6 'Install agent/skills/MCP toolkit and final checks'
    if bridge install; then echo '[OK] Toolkit bridge installed.'
    else echo '[WARN] Toolkit bridge not ready; retry from Install / Update -> Toolkit.'; fi
    echo '--- INSTALL SUMMARY ---'
    _network_show
    dc --profile app ps || :
    echo 'Use Status/Doctor to check readiness; Running alone does not confirm healthy inference.'
    echo 'Use Network menu to change APP_BIND/APP_PORT/APP_ORIGIN without manual editing.'
}

# Read-only, two-hop visibility test. Avoid changing Odysseus provider settings,
# which can contain user preferences or credentials. Do not assume an empty GUI
# picker implies an empty Ollama volume.
model_doctor() {
    echo '=== MODEL VISIBILITY / OLLAMA DOCTOR (READ ONLY) ==='
    echo '[1/3] Models inside this Compose project (cpu-ollama):'
    if ! dc exec -T cpu-ollama ollama list; then
        echo '[FAIL] Cannot list the CPU Ollama container. Check: Service Management -> Status.' >&2
        return 2
    fi
    echo '[2/3] Connection from Odysseus container to Ollama /api/tags:'
    if ! dc exec -T odysseus python -c '
import json, os, sys, urllib.request, urllib.parse
raw = os.getenv("OLLAMA_BASE_URL", "http://cpu-ollama:11434").rstrip("/")
url = raw.removesuffix("/v1") + "/api/tags"
try:
    data = json.load(urllib.request.urlopen(urllib.request.Request(url,headers={"Accept":"application/json"}),timeout=8))
    names = [m.get("name", "") for m in data.get("models", []) if isinstance(m, dict)]
    print("OLLAMA_API_OK", "models=" + str(len(names)))
    for name in names[:30]: print("  " + name)
    if not names: print("No installed models were reported by this Ollama API.")
except Exception as exc:
    print("OLLAMA_API_FAILED", type(exc).__name__, str(exc), file=sys.stderr)
    sys.exit(2)
'; then
        echo '[FAIL] Odysseus cannot query Ollama. Verify both services use the same Compose network.' >&2
        return 2
    fi
    echo '[3/3] Odysseus model picker:'
    echo 'Open the Odysseus UI, sign in, and select/refresh the Ollama model provider.'
    echo 'The in-container Ollama endpoint is http://cpu-ollama:11434 (NOT localhost or host port 11435).'
    echo 'If Ollama API models exist but the UI is empty, inspect its saved provider endpoint, hidden/pinned model filters, and refresh the catalog.'
    echo 'No providers, saved preferences, or credentials have been modified.'
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
        auth-help|account-help) _auth_help ;;
        status|docker-status) kit_state ;;
        network-status) _network_show ;;
        network-configure) _network_configure ;;
        network-apply) _network_apply ;;
        auth-setup) _auth_setup ;;
        start) kit_run app ;;
        stop) dc --profile app stop ;;
        restart) dc --profile app restart odysseus ;;
        logs) dc --profile app logs --tail 120 odysseus ;;
        enable) dc --profile app up -d odysseus ;;
        disable) dc --profile app stop odysseus ;;
        down) dc --profile app down ;;
        models|model-list) dc exec -T cpu-ollama ollama list ;;
        model-doctor|model-visibility) model_doctor ;;
        ollama-status) dc ps cpu-ollama; dc exec -T cpu-ollama ollama ps ;;
        ollama-start) dc up -d cpu-ollama ;;
        ollama-stop) dc stop cpu-ollama ;;
        ollama-restart) dc restart cpu-ollama ;;
        warm) kit_run warm "${1:-quality}" ;;
        benchmark) kit_run benchmark "${1:-quality}" ;;
        model-mount-check) kit_run mount-check "${1:-quality}" ;;
        model-mount-repair) kit_run mount-repair "${1:-quality}" ;;
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
  model-doctor             Check installed Ollama models and Odysseus container reachability (read-only)
  model-mount-check [quality|agent|moe]   Inspect Ollama /profiles Modelfile bind mount (read-only)
  model-mount-repair [quality|agent|moe]  Confirm REMOUNT; recreate only Ollama, keep volumes
  model-advisor / skills-doctor / skills-install NAME / skills-setup
  mcp-health / mcp-setup / cookbook-fix status|progress
  doctor / repair / agent-doctor / agent-rollback
  profile                 Print selected Docker hardware profile
  gpu-doctor              Optional pinned RDNA3 image; explicit consent before pulling
  gpu-dns-check [DNS_IP]   Check Hugging Face DNS + TLS from a disposable container
  gpu-start/gpu-status/gpu-logs/gpu-stop/gpu-test (Full profile, AMD RDNA3)
  gpu-readiness [LOOPBACK_URL]  Health endpoint (not a generation test)
  network-status          Show current listen IP/port and browser origins
  network-configure       Guided binding change, backed-up .env, approval before recreate
  network-apply           Apply saved settings by recreating only Odysseus
  auth-setup              First-run admin account only, never resets existing users
  auth-help               How to change an existing user's password safely
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

# Keep Docker's artwork and responsive centering identical to Native mode.
# Extracted from the same release's native TUI; no terminal-specific font needed.
TUI_COLS=80
TUI_LINES=24
_zd_print_center() {
    local text="$1" max_width width pad chunk
    max_width=$((TUI_COLS - 4))
    (( max_width < 8 )) && max_width=$TUI_COLS

    # Terminal fonts cannot be scaled safely, so "auto fit" means wrapping at
    # word boundaries and centering every wrapped row. This keeps the complete
    # message visible on narrow displays rather than silently clipping it.
    if (( ${#text} <= max_width )); then
        width=${#text}
        pad=$(( (TUI_COLS - width) / 2 )); (( pad < 0 )) && pad=0
        printf '%*s%s\n' "$pad" '' "$text"
        return 0
    fi

    if command -v fold >/dev/null 2>&1; then
        while IFS= read -r chunk; do
            width=${#chunk}
            pad=$(( (TUI_COLS - width) / 2 )); (( pad < 0 )) && pad=0
            printf '%*s%s\n' "$pad" '' "$chunk"
        done < <(printf '%s\n' "$text" | fold -s -w "$max_width")
    else
        while [[ -n "$text" ]]; do
            chunk="${text:0:max_width}"
            text="${text:max_width}"
            width=${#chunk}
            pad=$(( (TUI_COLS - width) / 2 )); (( pad < 0 )) && pad=0
            printf '%*s%s\n' "$pad" '' "$chunk"
        done
    fi
}

_zd_logo_block() {
    # Zarzysseus binary logo supplied by the user. Keep the delimiter at column 1.
    # The payload stores literal \\033 escapes so the script remains plain text;
    # printf %b expands them only when the TUI is actually rendered.
    while IFS= read -r line; do
        printf '%b\n' "$line"
    done <<'EOF_TUI_LOGO'
\033[38;2;12;12;12m0\033[38;2;13;13;13m00\033[38;2;14;14;14m01\033[38;2;14;14;13m0\033[38;2;14;14;14m00\033[38;2;15;15;15m00\033[38;2;16;16;16m10\033[38;2;17;17;17m1\033[38;2;18;18;18m01\033[38;2;19;19;19m11\033[38;2;20;20;20m1\033[38;2;20;21;20m0\033[38;2;20;20;20m0\033[38;2;21;21;21m00110100101\033[38;2;22;22;22m0010\033[38;2;21;21;21m011001\033[38;2;20;20;20m0\033[38;2;19;19;19m001\033[38;2;18;18;18m1\033[38;2;17;17;17m010101\033[38;2;16;16;16m00111010\033[0m
\033[38;2;13;13;13m10\033[38;2;14;14;14m001\033[38;2;14;14;13m1\033[38;2;14;14;14m1\033[38;2;15;15;15m0\033[38;2;16;16;16m1\033[38;2;17;17;17m1\033[38;2;18;18;18m1\033[38;2;19;19;19m1\033[38;2;20;20;20m0\033[38;2;21;22;20m1\033[38;2;22;22;22m1\033[38;2;23;23;23m0\033[38;2;24;24;24m1\033[38;2;25;25;25m10\033[38;2;26;26;26m01100\033[38;2;25;25;25m0000\033[38;2;26;26;26m11\033[38;2;27;26;26m0\033[38;2;27;27;27m0\033[38;2;28;28;28m0\033[38;2;27;27;27m0\033[38;2;26;26;26m1\033[38;2;26;27;26m0\033[38;2;27;27;27m1\033[38;2;27;27;26m0\033[38;2;27;27;27m1\033[38;2;28;28;28m0\033[38;2;27;27;27m0\033[38;2;26;26;26m1\033[38;2;24;24;24m1\033[38;2;23;23;23m0\033[38;2;21;21;21m1\033[38;2;20;19;19m1\033[38;2;19;19;19m1110\033[38;2;18;18;18m00\033[38;2;18;18;17m0\033[38;2;17;17;17m111\033[38;2;16;17;17m0\033[38;2;16;16;16m0\033[38;2;17;17;17m01\033[0m
\033[38;2;13;13;13m010\033[38;2;13;14;14m1\033[38;2;14;14;14m00\033[38;2;15;15;15m1\033[38;2;16;16;16m1\033[38;2;18;18;18m1\033[38;2;21;21;20m1\033[38;2;23;23;23m0\033[38;2;27;27;27m0\033[38;2;29;29;29m1\033[38;2;30;30;30m0\033[38;2;34;34;34m0\033[38;2;36;36;36m1\033[38;2;37;38;38m1\033[38;2;39;39;39m1\033[38;2;40;40;40m0\033[38;2;41;41;41m0\033[38;2;42;42;42m11\033[38;2;41;41;41m1\033[38;2;40;40;40m000001\033[38;2;41;41;41m0\033[38;2;41;42;42m0\033[38;2;42;43;42m0\033[38;2;42;43;43m1\033[38;2;41;42;42m0\033[38;2;41;41;41m00\033[38;2;41;41;42m1\033[38;2;42;42;42m0\033[38;2;43;43;43m1\033[38;2;44;44;44m0\033[38;2;43;43;42m0\033[38;2;39;39;39m1\033[38;2;34;34;34m0\033[38;2;33;33;33m0\033[38;2;28;28;29m1\033[38;2;24;24;24m0\033[38;2;21;21;21m10\033[38;2;20;20;20m110\033[38;2;19;19;19m1\033[38;2;19;19;20m1\033[38;2;19;19;19m10\033[38;2;19;19;18m1\033[38;2;18;18;18m000\033[38;2;18;17;18m0\033[0m
\033[38;2;13;13;13m0\033[38;2;12;12;12m0\033[38;2;13;13;13m1\033[38;2;13;14;13m0\033[38;2;14;14;14m0\033[38;2;15;15;15m1\033[38;2;17;17;17m0\033[38;2;20;20;20m0\033[38;2;25;25;25m0\033[38;2;29;29;28m0\033[38;2;32;33;32m1\033[38;2;44;46;45m1\033[38;2;83;83;82m0\033[38;2;123;123;122m1\033[38;2;132;132;130m0\033[38;2;135;135;134m0\033[38;2;137;137;136m0\033[38;2;138;139;138m1\033[38;2;140;141;139m1\033[38;2;141;141;140m1\033[38;2;143;143;142m0\033[38;2;143;143;141m0\033[38;2;141;142;140m1\033[38;2;141;142;141m1\033[38;2;141;141;140m1\033[38;2;142;142;141m01\033[38;2;142;142;140m1\033[38;2;141;141;140m10\033[38;2;141;141;141m1\033[38;2;142;142;141m1\033[38;2;141;142;142m1\033[38;2;142;143;142m0\033[38;2;142;142;142m0\033[38;2;141;142;141m0\033[38;2;143;143;143m1\033[38;2;144;144;144m1\033[38;2;144;145;145m1\033[38;2;153;154;153m0\033[38;2;169;169;168m0\033[38;2;152;152;151m0\033[38;2;115;115;113m0\033[38;2;58;58;59m0\033[38;2;41;41;42m1\033[38;2;35;36;36m1\033[38;2;32;34;35m1\033[38;2;24;25;25m0\033[38;2;23;23;23m1\033[38;2;22;22;22m10\033[38;2;21;21;21m1\033[38;2;21;21;22m0\033[38;2;20;20;21m0\033[38;2;20;20;20m101\033[38;2;20;20;19m1\033[38;2;19;19;19m0\033[38;2;19;19;20m0\033[0m
\033[38;2;12;12;12m1\033[38;2;13;13;13m1\033[38;2;14;14;14m01\033[38;2;16;16;16m0\033[38;2;19;19;19m0\033[38;2;24;24;23m0\033[38;2;32;32;31m1\033[38;2;44;44;44m1\033[38;2;78;78;78m0\033[38;2;131;133;133m1\033[38;2;109;110;108m0\033[38;2;104;105;104m1\033[38;2;156;155;154m1\033[38;2;167;167;166m1\033[38;2;172;173;172m1\033[38;2;176;176;176m1\033[38;2;177;177;176m1\033[38;2;179;179;177m1\033[38;2;180;180;178m11\033[38;2;180;181;179m0\033[38;2;182;182;180m0\033[38;2;180;180;179m1\033[38;2;178;178;177m1\033[38;2;176;177;176m0\033[38;2;176;176;175m00\033[38;2;177;176;175m1\033[38;2;178;178;176m1\033[38;2;178;178;177m0\033[38;2;178;178;176m11\033[38;2;180;179;178m1\033[38;2;180;180;179m1\033[38;2;181;181;181m1\033[38;2;179;180;180m1\033[38;2;182;182;181m0\033[38;2;183;183;181m1\033[38;2;181;180;177m0\033[38;2;211;210;207m0\033[38;2;186;186;183m0\033[38;2;149;149;147m0\033[38;2;98;99;98m1\033[38;2;90;92;92m1\033[38;2;62;66;67m1\033[38;2;49;54;57m1\033[38;2;30;31;32m0\033[38;2;30;29;31m0\033[38;2;28;27;28m1\033[38;2;25;25;27m0\033[38;2;23;24;26m0\033[38;2;23;22;24m1\033[38;2;21;21;22m000\033[38;2;20;20;20m0111\033[0m
\033[38;2;13;13;13m11\033[38;2;14;14;14m0\033[38;2;15;15;15m0\033[38;2;18;18;18m0\033[38;2;24;24;24m1\033[38;2;34;34;34m1\033[38;2;51;51;51m1\033[38;2;93;94;93m1\033[38;2;211;211;210m1\033[38;2;211;212;210m1\033[38;2;131;131;130m0\033[38;2;70;71;71m0\033[38;2;63;63;63m0\033[38;2;68;68;69m1\033[38;2;71;71;71m1\033[38;2;74;74;74m1\033[38;2;76;76;76m1\033[38;2;78;77;78m1\033[38;2;80;80;80m0\033[38;2;80;80;79m1\033[38;2;79;79;79m1\033[38;2;80;80;80m1\033[38;2;81;80;81m1\033[38;2;80;79;79m0\033[38;2;78;78;78m1\033[38;2;77;77;77m00\033[38;2;77;76;75m0\033[38;2;78;77;75m1\033[38;2;77;77;77m0\033[38;2;76;76;76m1\033[38;2;76;76;75m0\033[38;2;75;75;74m01\033[38;2;76;77;75m0\033[38;2;78;78;76m0\033[38;2;81;81;79m0\033[38;2;87;86;84m1\033[38;2;85;84;82m0\033[38;2;98;97;95m1\033[38;2;143;142;141m0\033[38;2;201;201;200m0\033[38;2;198;200;199m0\033[38;2;104;106;107m0\033[38;2;58;60;61m0\033[38;2;46;48;48m1\033[38;2;43;45;46m1\033[38;2;40;41;43m0\033[38;2;37;38;40m0\033[38;2;33;34;36m0\033[38;2;30;31;33m0\033[38;2;28;28;30m0\033[38;2;26;25;27m0\033[38;2;24;24;26m0\033[38;2;22;22;24m1\033[38;2;21;21;21m0110\033[0m
\033[38;2;13;13;12m0\033[38;2;13;13;13m0\033[38;2;15;15;15m0\033[38;2;17;17;17m1\033[38;2;21;21;21m1\033[38;2;28;28;28m0\033[38;2;44;44;44m1\033[38;2;79;79;78m1\033[38;2;199;198;197m1\033[38;2;213;213;212m0\033[38;2;147;148;147m0\033[38;2;109;110;109m0\033[38;2;59;59;58m0\033[38;2;45;46;44m1\033[38;2;42;42;42m1\033[38;2;42;42;41m0\033[38;2;44;43;42m1\033[38;2;48;47;46m1\033[38;2;52;50;50m1\033[38;2;55;54;54m0\033[38;2;56;55;55m01\033[38;2;55;54;55m0\033[38;2;53;52;52m1\033[38;2;50;49;49m0\033[38;2;49;47;48m1\033[38;2;47;46;46m1\033[38;2;43;43;43m0\033[38;2;43;43;42m0\033[38;2;43;42;41m0\033[38;2;42;41;41m0\033[38;2;41;40;40m01\033[38;2;40;40;38m1\033[38;2;41;41;39m1\033[38;2;44;44;42m1\033[38;2;49;48;46m1\033[38;2;55;55;53m0\033[38;2;66;66;64m0\033[38;2;104;104;102m1\033[38;2;179;179;177m1\033[38;2;232;232;231m0\033[38;2;207;207;205m0\033[38;2;143;143;141m0\033[38;2;88;89;89m1\033[38;2;82;84;84m0\033[38;2;101;103;103m1\033[38;2;97;99;100m1\033[38;2;85;88;90m1\033[38;2;62;64;66m0\033[38;2;49;51;52m0\033[38;2;43;45;46m1\033[38;2;37;38;40m1\033[38;2;32;33;35m0\033[38;2;28;29;30m0\033[38;2;26;26;26m1\033[38;2;23;23;24m0\033[38;2;22;22;22m1\033[38;2;21;21;22m0\033[38;2;21;21;21m0\033[0m
\033[38;2;13;13;12m1\033[38;2;14;14;14m0\033[38;2;15;15;15m0\033[38;2;17;17;17m1\033[38;2;21;21;21m1\033[38;2;28;28;28m1\033[38;2;42;42;42m0\033[38;2;68;68;68m0\033[38;2;154;155;155m0\033[38;2;153;154;153m1\033[38;2;115;115;113m1\033[38;2;67;67;66m1\033[38;2;55;55;54m0\033[38;2;50;50;48m0\033[38;2;50;51;49m0\033[38;2;67;67;65m0\033[38;2;102;102;100m1\033[38;2;133;132;130m1\033[38;2;146;145;143m0\033[38;2;149;149;147m0\033[38;2;151;151;149m0\033[38;2;152;151;150m1\033[38;2;151;151;149m0\033[38;2;155;155;153m1\033[38;2;162;162;161m1\033[38;2;116;115;113m0\033[38;2;83;82;79m0\033[38;2;79;79;75m0\033[38;2;54;55;52m1\033[38;2;43;42;42m0\033[38;2;41;40;41m0\033[38;2;40;40;40m11\033[38;2;42;42;40m1\033[38;2;45;46;44m1\033[38;2;52;52;51m1\033[38;2;62;62;60m1\033[38;2;93;93;91m0\033[38;2;165;166;164m1\033[38;2;220;220;219m0\033[38;2;195;195;193m1\033[38;2;131;130;128m0\033[38;2;93;92;90m1\033[38;2;93;93;90m1\033[38;2;131;132;129m0\033[38;2;197;198;196m1\033[38;2;233;233;230m1\033[38;2;190;190;189m0\033[38;2;187;189;189m0\033[38;2;182;184;184m0\033[38;2;101;104;105m1\033[38;2;63;65;66m1\033[38;2;50;52;53m0\033[38;2;40;42;44m1\033[38;2;33;35;36m0\033[38;2;28;29;31m1\033[38;2;26;26;26m0\033[38;2;24;24;24m1\033[38;2;23;23;23m0\033[38;2;22;22;22m0\033[0m
\033[38;2;13;13;13m0\033[38;2;14;14;14m0\033[38;2;15;15;15m1\033[38;2;17;17;17m0\033[38;2;19;19;20m0\033[38;2;25;25;25m1\033[38;2;33;33;33m0\033[38;2;44;44;45m0\033[38;2;89;90;90m1\033[38;2;203;203;202m1\033[38;2;177;176;176m1\033[38;2;102;102;101m0\033[38;2;69;67;66m1\033[38;2;65;64;63m0\033[38;2;70;69;68m1\033[38;2;139;139;136m0\033[38;2;243;244;243m0\033[38;2;223;222;220m1\033[38;2;191;190;187m0\033[38;2;188;188;186m0\033[38;2;187;187;186m1\033[38;2;188;188;185m0\033[38;2;190;190;188m0\033[38;2;191;190;187m1\033[38;2;198;197;193m1\033[38;2;195;194;191m0\033[38;2;212;211;208m0\033[38;2;154;154;150m1\033[38;2;73;73;70m1\033[38;2;49;48;47m1\033[38;2;45;44;44m1\033[38;2;44;44;43m1\033[38;2;47;47;45m1\033[38;2;52;52;50m1\033[38;2;61;61;59m1\033[38;2;93;92;90m0\033[38;2;164;164;161m1\033[38;2;227;227;225m0\033[38;2;202;203;200m1\033[38;2;121;120;118m1\033[38;2;78;77;75m0\033[38;2;77;76;75m0\033[38;2;82;81;79m0\033[38;2;122;122;117m1\033[38;2;170;170;166m1\033[38;2;186;186;184m1\033[38;2;126;127;126m0\033[38;2;126;127;127m0\033[38;2;148;149;149m1\033[38;2;179;180;179m1\033[38;2;220;222;222m0\033[38;2;146;152;155m1\033[38;2;71;74;76m0\033[38;2;53;55;57m1\033[38;2;41;43;44m0\033[38;2;33;35;36m0\033[38;2;29;29;29m0\033[38;2;25;25;25m1\033[38;2;23;23;24m1\033[38;2;22;22;23m0\033[0m
\033[38;2;13;13;13m0\033[38;2;14;14;14m1\033[38;2;15;15;15m0\033[38;2;17;17;17m0\033[38;2;19;19;18m0\033[38;2;21;21;20m1\033[38;2;26;26;25m1\033[38;2;35;35;35m1\033[38;2;52;52;51m1\033[38;2;91;91;88m1\033[38;2;172;172;171m1\033[38;2;216;216;215m0\033[38;2;173;172;170m0\033[38;2;111;109;107m1\033[38;2;89;88;84m1\033[38;2;110;109;106m0\033[38;2;201;201;199m0\033[38;2;201;200;197m0\033[38;2;112;111;108m1\033[38;2;92;90;89m0\033[38;2;89;88;86m1\033[38;2;91;89;87m1\033[38;2;103;101;99m1\033[38;2;154;152;150m1\033[38;2;220;219;217m0\033[38;2;224;224;221m1\033[38;2;165;165;163m1\033[38;2;96;95;93m0\033[38;2;64;62;61m1\033[38;2;55;54;53m0\033[38;2;53;53;51m1\033[38;2;56;56;54m1\033[38;2;64;64;61m0\033[38;2;93;92;90m0\033[38;2;161;160;158m1\033[38;2;220;221;218m1\033[38;2;197;197;195m1\033[38;2;131;130;128m0\033[38;2;82;82;80m0\033[38;2;72;71;69m0\033[38;2;104;104;101m0\033[38;2;142;144;142m0\033[38;2;149;150;148m0\033[38;2;109;111;109m0\033[38;2;83;83;82m1\033[38;2;70;70;69m0\033[38;2;64;65;65m0\033[38;2;70;71;71m0\033[38;2;106;107;107m1\033[38;2;143;144;143m0\033[38;2;169;170;168m1\033[38;2;233;235;235m1\033[38;2;135;141;145m1\033[38;2;68;70;71m0\033[38;2;50;52;54m0\033[38;2;39;40;41m0\033[38;2;32;32;32m1\033[38;2;27;27;27m1\033[38;2;25;25;25m0\033[38;2;23;23;23m0\033[0m
\033[38;2;13;13;13m0\033[38;2;14;14;13m1\033[38;2;15;15;14m0\033[38;2;16;17;16m0\033[38;2;17;17;17m1\033[38;2;19;19;18m1\033[38;2;21;22;20m0\033[38;2;26;26;26m1\033[38;2;33;33;32m0\033[38;2;43;43;41m0\033[38;2;61;61;59m0\033[38;2;108;108;107m0\033[38;2;184;184;182m0\033[38;2;221;221;220m1\033[38;2;180;180;177m0\033[38;2;182;181;178m0\033[38;2;223;224;221m0\033[38;2;183;184;180m1\033[38;2;117;116;113m0\033[38;2;86;84;82m0\033[38;2;88;87;85m1\033[38;2;133;131;130m1\033[38;2;207;207;205m1\033[38;2;230;230;228m1\033[38;2;175;175;172m1\033[38;2;107;107;105m0\033[38;2;74;73;71m0\033[38;2;64;62;61m0\033[38;2;61;59;58m1\033[38;2;63;61;60m1\033[38;2;70;69;67m0\033[38;2;95;95;92m1\033[38;2;160;160;157m1\033[38;2;222;221;220m0\033[38;2;202;203;201m0\033[38;2;126;126;124m1\033[38;2;77;76;74m1\033[38;2;64;62;61m0\033[38;2;63;62;61m0\033[38;2;69;68;66m1\033[38;2;104;103;99m0\033[38;2;175;175;171m1\033[38;2;219;219;216m0\033[38;2;226;228;228m1\033[38;2;121;123;124m1\033[38;2;71;70;70m0\033[38;2;61;61;61m10\033[38;2;70;72;72m0\033[38;2;125;126;125m1\033[38;2;144;144;143m1\033[38;2;208;208;206m0\033[38;2;205;210;213m1\033[38;2;90;94;96m0\033[38;2;56;58;59m0\033[38;2;43;44;45m0\033[38;2;35;35;35m0\033[38;2;29;29;29m0\033[38;2;25;25;25m0\033[38;2;24;24;24m1\033[0m
\033[38;2;13;13;13m0\033[38;2;14;14;13m1\033[38;2;15;15;14m1\033[38;2;15;15;15m1\033[38;2;16;16;16m0\033[38;2;17;17;17m0\033[38;2;19;20;18m1\033[38;2;22;22;20m0\033[38;2;25;25;23m1\033[38;2;29;30;28m1\033[38;2;37;37;35m0\033[38;2;47;47;45m1\033[38;2;64;64;62m0\033[38;2;109;109;107m0\033[38;2;157;157;155m0\033[38;2;172;172;169m1\033[38;2;150;150;147m1\033[38;2;115;114;110m0\033[38;2;104;102;99m1\033[38;2;139;137;134m1\033[38;2;199;199;196m0\033[38;2;229;229;227m0\033[38;2;181;181;179m0\033[38;2;112;111;109m1\033[38;2;76;75;73m0\033[38;2;64;63;61m1\033[38;2;61;60;58m0\033[38;2;63;62;60m1\033[38;2;70;70;68m0\033[38;2;96;96;93m0\033[38;2;160;159;156m1\033[38;2;225;225;222m0\033[38;2;218;218;216m0\033[38;2;141;140;138m1\033[38;2;84;83;82m0\033[38;2;68;67;65m1\033[38;2;64;63;60m0\033[38;2;62;62;59m1\033[38;2;64;63;62m1\033[38;2;70;69;68m0\033[38;2;81;80;77m0\033[38;2;111;110;107m1\033[38;2;174;174;170m1\033[38;2;245;245;243m0\033[38;2;176;178;178m1\033[38;2;73;73;72m1\033[38;2;60;60;60m0\033[38;2;57;59;59m0\033[38;2;65;67;67m1\033[38;2;101;102;103m0\033[38;2;148;148;149m1\033[38;2;186;187;186m1\033[38;2;227;230;231m1\033[38;2;104;109;111m1\033[38;2;61;63;64m0\033[38;2;46;47;49m1\033[38;2;36;36;36m1\033[38;2;29;29;29m1\033[38;2;26;26;26m0\033[38;2;24;24;24m0\033[0m
\033[38;2;14;14;14m101\033[38;2;15;15;14m0\033[38;2;15;15;15m1\033[38;2;17;17;17m1\033[38;2;19;19;17m0\033[38;2;20;20;18m1\033[38;2;22;22;20m0\033[38;2;25;25;23m1\033[38;2;29;29;27m1\033[38;2;34;35;32m1\033[38;2;41;41;39m0\033[38;2;49;48;46m0\033[38;2;59;58;56m1\033[38;2;71;70;68m0\033[38;2;85;83;82m0\033[38;2;126;125;122m0\033[38;2;202;202;199m1\033[38;2;236;236;233m0\033[38;2;187;188;185m0\033[38;2;118;117;113m0\033[38;2;78;77;74m1\033[38;2;64;63;61m0\033[38;2;60;59;58m0\033[38;2;63;62;60m0\033[38;2;70;69;67m1\033[38;2;95;94;91m1\033[38;2;157;156;153m0\033[38;2;224;223;221m1\033[38;2;222;222;219m1\033[38;2;156;155;153m0\033[38;2;101;100;98m0\033[38;2;82;81;79m0\033[38;2;86;85;83m0\033[38;2;105;103;102m0\033[38;2;114;114;112m0\033[38;2;107;107;105m0\033[38;2;105;105;103m1\033[38;2;109;109;107m1\033[38;2;120;120;118m0\033[38;2;152;152;150m1\033[38;2;206;206;203m1\033[38;2;223;223;221m0\033[38;2;124;124;122m0\033[38;2;63;63;62m0\033[38;2;56;56;56m0\033[38;2;57;57;57m1\033[38;2;65;67;67m1\033[38;2;111;111;111m0\033[38;2;149;150;149m1\033[38;2;208;209;208m1\033[38;2;201;202;202m0\033[38;2;88;91;92m0\033[38;2;58;61;62m0\033[38;2;44;45;47m1\033[38;2;35;35;36m0\033[38;2;29;29;29m1\033[38;2;26;26;26m1\033[38;2;24;24;24m1\033[0m
\033[38;2;15;15;15m0\033[38;2;14;14;15m1\033[38;2;15;15;14m01\033[38;2;16;16;16m1\033[38;2;17;17;17m1\033[38;2;19;19;18m1\033[38;2;21;21;19m1\033[38;2;23;23;21m0\033[38;2;26;26;25m0\033[38;2;29;30;28m0\033[38;2;35;36;33m1\033[38;2;44;43;41m0\033[38;2;54;53;51m0\033[38;2;70;69;67m0\033[38;2;112;112;111m0\033[38;2;185;185;183m1\033[38;2;230;230;229m0\033[38;2;193;194;191m0\033[38;2;122;122;119m0\033[38;2;80;79;77m1\033[38;2;65;63;61m1\033[38;2;60;58;57m1\033[38;2;61;61;58m0\033[38;2;68;68;66m0\033[38;2;92;92;90m1\033[38;2;154;153;151m0\033[38;2;219;219;217m0\033[38;2;221;222;219m0\033[38;2;163;163;160m1\033[38;2;109;108;105m0\033[38;2;92;91;88m0\033[38;2;102;99;98m0\033[38;2;141;140;137m1\033[38;2;202;202;200m0\033[38;2;218;218;216m1\033[38;2;206;205;204m0\033[38;2;205;204;202m1\033[38;2;209;209;207m0\033[38;2;209;209;208m0\033[38;2;203;203;201m1\033[38;2;194;195;193m1\033[38;2;169;169;167m1\033[38;2;106;106;104m0\033[38;2;63;63;63m1\033[38;2;57;57;57m11\033[38;2;63;63;63m1\033[38;2;86;89;88m0\033[38;2;141;141;140m0\033[38;2;167;168;166m0\033[38;2;233;233;231m0\033[38;2;133;134;133m1\033[38;2;71;73;74m0\033[38;2;52;54;56m1\033[38;2;40;41;43m0\033[38;2;33;33;33m0\033[38;2;28;28;28m0\033[38;2;25;25;25m0\033[38;2;23;23;23m1\033[0m
\033[38;2;15;15;15m00\033[38;2;16;16;16m0\033[38;2;16;16;15m0\033[38;2;17;17;16m0\033[38;2;19;19;18m0\033[38;2;20;20;20m0\033[38;2;22;23;21m0\033[38;2;26;26;24m0\033[38;2;31;31;30m1\033[38;2;38;38;36m1\033[38;2;48;48;46m0\033[38;2;65;64;62m0\033[38;2;107;105;103m0\033[38;2;181;181;178m1\033[38;2;230;231;229m1\033[38;2;199;199;196m0\033[38;2;127;127;124m0\033[38;2;79;78;76m0\033[38;2;63;62;61m1\033[38;2;60;58;56m1\033[38;2;62;60;59m0\033[38;2;68;68;66m1\033[38;2;90;91;88m0\033[38;2;150;150;147m0\033[38;2;217;218;215m0\033[38;2;218;218;215m1\033[38;2;153;152;149m1\033[38;2;99;98;96m0\033[38;2;84;82;80m1\033[38;2;91;89;87m0\033[38;2;135;134;131m1\033[38;2;209;208;206m0\033[38;2;234;234;232m0\033[38;2;189;189;187m1\033[38;2;124;124;121m1\033[38;2;98;96;95m1\033[38;2;94;92;91m1\033[38;2;92;91;89m0\033[38;2;88;87;86m1\033[38;2;79;79;77m0\033[38;2;69;69;67m1\033[38;2;60;60;58m1\033[38;2;56;56;56m1\033[38;2;57;57;57m0\033[38;2;59;59;59m1\033[38;2;67;67;67m1\033[38;2;92;92;92m0\033[38;2;140;142;140m0\033[38;2;182;183;181m0\033[38;2;227;228;225m0\033[38;2;154;154;153m1\033[38;2;77;79;79m1\033[38;2;56;58;59m0\033[38;2;44;46;47m1\033[38;2;35;36;38m1\033[38;2;30;30;31m0\033[38;2;27;27;27m1\033[38;2;25;25;25m0\033[38;2;23;23;23m1\033[0m
\033[38;2;15;15;15m0\033[38;2;16;16;16m11\033[38;2;17;17;17m0\033[38;2;18;19;18m0\033[38;2;21;21;21m0\033[38;2;24;24;22m1\033[38;2;29;29;27m1\033[38;2;36;36;34m0\033[38;2;45;45;43m1\033[38;2;60;60;58m0\033[38;2;98;99;97m0\033[38;2;175;175;173m0\033[38;2;230;230;227m1\033[38;2;201;201;198m0\033[38;2;129;129;126m1\033[38;2;80;79;77m0\033[38;2;62;61;59m0\033[38;2;58;56;55m0\033[38;2;60;60;58m1\033[38;2;69;69;66m0\033[38;2;90;90;87m1\033[38;2;146;146;143m0\033[38;2;217;218;216m0\033[38;2;225;225;223m1\033[38;2;155;156;154m0\033[38;2;94;94;92m0\033[38;2;73;71;70m1\033[38;2;68;67;66m1\033[38;2;72;70;68m1\033[38;2;83;82;81m1\033[38;2;148;148;146m0\033[38;2;243;243;241m0\033[38;2;219;220;218m0\033[38;2;130;129;127m1\033[38;2;90;88;87m1\033[38;2;75;73;72m0\033[38;2;64;62;61m0\033[38;2;57;56;54m1\033[38;2;53;53;51m1\033[38;2;50;50;49m0\033[38;2;49;49;48m0\033[38;2;50;50;49m1\033[38;2;54;54;54m0\033[38;2;64;64;64m1\033[38;2;88;88;87m1\033[38;2;129;129;128m0\033[38;2;174;175;174m1\033[38;2;208;209;208m1\033[38;2;208;208;207m1\033[38;2;133;134;133m0\033[38;2;73;74;75m1\033[38;2;55;57;58m1\033[38;2;45;46;47m1\033[38;2;37;39;40m1\033[38;2;32;33;33m0\033[38;2;29;29;29m1\033[38;2;26;26;26m0\033[38;2;24;24;24m1\033[38;2;23;23;22m0\033[0m
\033[38;2;15;15;16m1\033[38;2;16;16;16m0\033[38;2;17;17;17m1\033[38;2;19;19;19m1\033[38;2;21;22;20m1\033[38;2;25;26;24m1\033[38;2;32;32;30m1\033[38;2;42;42;40m0\033[38;2;56;56;54m1\033[38;2;93;93;91m0\033[38;2;169;169;167m0\033[38;2;227;227;226m0\033[38;2;203;204;202m0\033[38;2;132;132;129m1\033[38;2;80;79;77m0\033[38;2;62;60;58m0\033[38;2;56;55;53m0\033[38;2;58;56;55m1\033[38;2;66;65;63m1\033[38;2;88;88;86m0\033[38;2;143;142;140m1\033[38;2;213;213;212m0\033[38;2;230;231;229m0\033[38;2;170;171;169m0\033[38;2;103;102;100m0\033[38;2;75;73;72m0\033[38;2;67;65;64m1\033[38;2;62;61;59m0\033[38;2;61;59;58m0\033[38;2;62;60;59m1\033[38;2;67;65;64m0\033[38;2;78;77;75m0\033[38;2;108;107;105m1\033[38;2;147;146;143m0\033[38;2;169;169;166m0\033[38;2;137;137;134m1\033[38;2;101;100;98m0\033[38;2;74;73;71m1\033[38;2;62;62;61m1\033[38;2;56;56;56m1\033[38;2;51;51;51m0\033[38;2;49;49;49m10\033[38;2;54;55;54m0\033[38;2;87;87;86m1\033[38;2;139;140;137m0\033[38;2;196;197;195m1\033[38;2;190;192;191m0\033[38;2;140;142;142m0\033[38;2;92;93;93m0\033[38;2;67;67;67m0\033[38;2;55;55;57m0\033[38;2;46;47;49m0\033[38;2;40;40;42m1\033[38;2;35;35;36m1\033[38;2;31;31;31m0\033[38;2;28;28;28m0\033[38;2;26;26;26m0\033[38;2;24;24;24m1\033[38;2;23;23;23m0\033[0m
\033[38;2;16;16;16m1\033[38;2;17;17;17m0\033[38;2;19;19;18m0\033[38;2;21;22;20m1\033[38;2;25;26;24m1\033[38;2;34;35;33m0\033[38;2;48;49;48m0\033[38;2;73;73;72m1\033[38;2;149;148;146m0\033[38;2;222;221;219m0\033[38;2;206;206;204m1\033[38;2;131;131;129m0\033[38;2;75;75;73m0\033[38;2;55;54;53m0\033[38;2;50;48;47m11\033[38;2;58;57;55m1\033[38;2;78;78;76m1\033[38;2;134;134;132m1\033[38;2;209;209;207m0\033[38;2;230;230;228m1\033[38;2;178;179;176m1\033[38;2;115;114;113m0\033[38;2;87;85;83m0\033[38;2;78;77;76m0\033[38;2;74;73;72m0\033[38;2;71;70;68m0\033[38;2;69;68;67m0\033[38;2;68;68;65m0\033[38;2;67;67;65m0\033[38;2;67;66;64m0\033[38;2;69;67;65m0\033[38;2;72;70;69m1\033[38;2;81;79;77m0\033[38;2;112;111;107m1\033[38;2;198;197;195m1\033[38;2;232;232;230m1\033[38;2;179;179;177m1\033[38;2;105;106;104m0\033[38;2;78;77;77m0\033[38;2;67;67;66m0\033[38;2;59;59;58m1\033[38;2;57;57;57m1\033[38;2;61;61;60m1\033[38;2;83;83;82m1\033[38;2;124;124;122m1\033[38;2;187;186;184m0\033[38;2;201;202;202m1\033[38;2;134;136;137m0\033[38;2;88;90;90m0\033[38;2;68;69;70m1\033[38;2;56;58;59m0\033[38;2;48;50;51m1\033[38;2;42;42;42m0\033[38;2;37;37;37m1\033[38;2;33;33;33m1\033[38;2;30;30;30m0\033[38;2;28;28;28m1\033[38;2;27;27;27m0\033[38;2;25;25;26m0\033[0m
\033[38;2;17;17;17m1\033[38;2;19;19;19m0\033[38;2;21;21;20m0\033[38;2;25;25;23m0\033[38;2;34;34;32m1\033[38;2;50;50;49m0\033[38;2;82;82;81m1\033[38;2;182;182;180m0\033[38;2;224;224;221m1\033[38;2;149;149;146m1\033[38;2;77;77;76m1\033[38;2;52;51;49m0\033[38;2;43;42;40m1\033[38;2;38;38;36m11\033[38;2;43;43;41m0\033[38;2;62;61;59m1\033[38;2;164;164;160m0\033[38;2;233;232;230m1\033[38;2;176;175;170m0\033[38;2;149;147;143m1\033[38;2;171;170;168m1\033[38;2;182;181;180m0\033[38;2;181;180;179m0\033[38;2;179;179;177m1\033[38;2;177;177;175m1\033[38;2;176;176;174m0\033[38;2;175;175;173m0\033[38;2;175;175;174m0\033[38;2;174;174;173m01\033[38;2;172;172;170m1\033[38;2;150;150;148m1\033[38;2;113;113;110m0\033[38;2;93;93;90m1\033[38;2;108;106;104m1\033[38;2;154;154;151m1\033[38;2;220;220;218m1\033[38;2;227;227;226m1\033[38;2;169;169;169m1\033[38;2;110;110;109m1\033[38;2;80;80;79m1\033[38;2;70;70;68m1\033[38;2;65;65;64m0\033[38;2;64;64;64m0\033[38;2;75;75;74m1\033[38;2;108;108;106m1\033[38;2;174;175;173m1\033[38;2;229;229;228m1\033[38;2;205;206;206m0\033[38;2;132;134;135m1\033[38;2;82;84;85m1\033[38;2;63;64;65m0\033[38;2;52;54;54m1\033[38;2;44;46;45m0\033[38;2;39;40;40m0\033[38;2;34;35;36m1\033[38;2;31;31;33m0\033[38;2;29;29;31m1\033[38;2;27;27;27m1\033[0m
\033[38;2;18;18;17m0\033[38;2;20;20;20m0\033[38;2;24;25;24m1\033[38;2;33;33;31m0\033[38;2;48;48;46m0\033[38;2;74;74;73m1\033[38;2;166;165;164m0\033[38;2;239;240;237m1\033[38;2;152;153;150m0\033[38;2;78;78;76m1\033[38;2;50;49;47m1\033[38;2;39;39;37m0\033[38;2;34;34;32m0\033[38;2;33;34;32m1\033[38;2;34;35;32m0\033[38;2;38;38;36m0\033[38;2;47;46;45m0\033[38;2;80;79;77m1\033[38;2;88;87;84m1\033[38;2;75;73;70m1\033[38;2;127;126;124m1\033[38;2;161;161;159m1\033[38;2;154;153;152m0\033[38;2;157;156;154m0\033[38;2;157;157;155m1\033[38;2;156;156;154m00\033[38;2;157;157;154m0\033[38;2;157;156;155m0\033[38;2;158;157;155m1\033[38;2;159;158;157m0\033[38;2;168;167;166m0\033[38;2;204;204;202m0\033[38;2;231;232;230m1\033[38;2;184;185;183m1\033[38;2;121;120;118m0\033[38;2;98;96;95m0\033[38;2;110;109;107m1\033[38;2;162;162;160m1\033[38;2;225;225;224m1\033[38;2;228;229;228m1\033[38;2;165;166;165m1\033[38;2;107;106;105m0\033[38;2;81;81;79m1\033[38;2;70;70;69m0\033[38;2;66;66;66m0\033[38;2;67;68;68m1\033[38;2;80;80;80m0\033[38;2;120;120;118m1\033[38;2;188;187;185m0\033[38;2;230;231;230m0\033[38;2;197;198;198m1\033[38;2;123;125;126m1\033[38;2;78;80;81m0\033[38;2;60;62;63m1\033[38;2;49;50;52m1\033[38;2;41;43;44m0\033[38;2;36;37;39m0\033[38;2;32;33;35m1\033[38;2;29;29;30m1\033[0m
\033[38;2;19;19;17m1\033[38;2;22;22;21m1\033[38;2;29;29;27m1\033[38;2;43;43;41m0\033[38;2;69;69;67m1\033[38;2;153;153;151m0\033[38;2;246;246;245m0\033[38;2;182;181;178m1\033[38;2;97;95;93m0\033[38;2;56;55;53m0\033[38;2;44;43;41m0\033[38;2;37;37;35m0\033[38;2;35;35;33m0\033[38;2;36;36;34m0\033[38;2;37;37;34m1\033[38;2;37;38;35m1\033[38;2;39;39;37m0\033[38;2;38;38;36m1\033[38;2;41;40;39m1\033[38;2;47;45;46m0\033[38;2;49;47;48m0\033[38;2;51;50;49m1\033[38;2;56;55;53m1\033[38;2;59;58;56m0\033[38;2;61;59;58m0\033[38;2;62;60;59m1\033[38;2;63;61;60m1\033[38;2;64;62;61m0\033[38;2;65;63;62m1\033[38;2;66;64;63m0\033[38;2;70;68;67m1\033[38;2;77;76;74m0\033[38;2;94;93;91m0\033[38;2;143;142;141m1\033[38;2;214;213;211m0\033[38;2;233;233;232m0\033[38;2;178;178;177m0\033[38;2;117;116;114m1\033[38;2;96;95;93m0\033[38;2;111;109;108m0\033[38;2;164;163;161m0\033[38;2;221;221;219m1\033[38;2;221;222;221m1\033[38;2;159;159;159m1\033[38;2;109;110;108m0\033[38;2;80;80;78m0\033[38;2;70;69;69m0\033[38;2;67;67;67m0\033[38;2;74;74;74m1\033[38;2;91;91;90m0\033[38;2;132;133;132m0\033[38;2;201;201;200m0\033[38;2;236;236;236m0\033[38;2;189;190;191m0\033[38;2;116;118;119m0\033[38;2;72;74;75m0\033[38;2;55;57;58m1\033[38;2;44;45;47m1\033[38;2;36;37;39m0\033[38;2;31;32;34m0\033[0m
\033[38;2;18;18;16m0\033[38;2;22;22;20m0\033[38;2;31;31;29m1\033[38;2;45;44;43m0\033[38;2;110;109;107m0\033[38;2;243;243;241m1\033[38;2;204;204;201m1\033[38;2;108;107;103m0\033[38;2;66;64;61m0\033[38;2;56;54;52m1\033[38;2;54;52;51m0\033[38;2;52;51;49m1\033[38;2;53;52;51m1\033[38;2;55;54;52m1\033[38;2;56;56;54m1\033[38;2;57;58;55m1\033[38;2;59;59;57m11\033[38;2;60;60;58m1\033[38;2;62;62;60m1\033[38;2;65;64;63m0\033[38;2;67;66;65m0\033[38;2;69;68;66m1\033[38;2;70;69;67m1\033[38;2;72;70;69m010\033[38;2;72;71;69m1\033[38;2;74;73;71m0\033[38;2;75;74;73m0\033[38;2;78;77;75m1\033[38;2;81;80;78m1\033[38;2;84;83;80m1\033[38;2;90;87;85m1\033[38;2;107;105;102m1\033[38;2;158;156;153m0\033[38;2;224;225;223m1\033[38;2;226;226;226m0\033[38;2;148;147;145m0\033[38;2;94;92;91m0\033[38;2;85;83;82m0\033[38;2;104;103;101m0\033[38;2;171;172;169m1\033[38;2;238;239;238m1\033[38;2;224;225;224m1\033[38;2;142;143;142m1\033[38;2;95;96;95m0\033[38;2;85;85;84m1\033[38;2;82;82;82m0\033[38;2;87;87;87m0\033[38;2;97;97;97m1\033[38;2;113;115;115m0\033[38;2;156;158;158m1\033[38;2;205;206;205m1\033[38;2;222;223;223m1\033[38;2;155;158;158m1\033[38;2;73;77;80m0\033[38;2;48;50;54m1\033[38;2;37;39;42m1\033[38;2;31;33;35m1\033[0m
\033[38;2;17;17;15m1\033[38;2;20;19;18m0\033[38;2;24;23;21m1\033[38;2;50;49;46m1\033[38;2;110;110;106m1\033[38;2;125;125;122m1\033[38;2;73;72;68m0\033[38;2;100;98;95m0\033[38;2;183;182;179m1\033[38;2;175;174;171m0\033[38;2;160;160;158m1\033[38;2;170;170;168m1\033[38;2;165;164;162m1\033[38;2;166;164;163m0\033[38;2;167;166;165m0\033[38;2;168;168;167m1\033[38;2;169;169;168m0\033[38;2;170;170;169m0\033[38;2;172;171;170m00\033[38;2;173;172;171m1\033[38;2;175;175;174m1\033[38;2;175;175;173m010\033[38;2;174;174;172m0\033[38;2;175;174;173m01\033[38;2;175;175;173m1\033[38;2;175;175;174m1\033[38;2;177;177;176m1\033[38;2;178;178;177m0\033[38;2;178;178;176m0\033[38;2;180;179;177m0\033[38;2;197;196;194m1\033[38;2;186;185;183m0\033[38;2;143;141;137m1\033[38;2;149;147;144m0\033[38;2;130;130;126m0\033[38;2;101;101;98m1\033[38;2;69;69;68m0\033[38;2;63;62;62m1\033[38;2;73;73;72m1\033[38;2;99;99;98m1\033[38;2;130;131;130m0\033[38;2;144;146;146m0\033[38;2;138;140;142m0\033[38;2;171;171;171m1\033[38;2;174;174;173m1\033[38;2;180;180;178m0\033[38;2;207;207;207m0\033[38;2;200;201;201m1\033[38;2;184;185;185m0\033[38;2;173;175;175m1\033[38;2;181;183;184m0\033[38;2;168;173;177m1\033[38;2;86;94;101m0\033[38;2;56;61;65m0\033[38;2;32;34;37m0\033[38;2;29;30;33m0\033[0m
\033[38;2;15;14;13m0\033[38;2;16;15;14m0\033[38;2;16;16;14m1\033[38;2;37;37;34m1\033[38;2;38;37;34m0\033[38;2;34;32;29m0\033[38;2;51;49;46m1\033[38;2;66;65;62m1\033[38;2;131;130;129m0\033[38;2;142;143;142m1\033[38;2;137;137;136m0\033[38;2;140;140;139m0\033[38;2;141;141;140m0\033[38;2;143;143;142m0\033[38;2;145;144;144m0\033[38;2;145;145;144m1\033[38;2;147;147;147m0\033[38;2;150;151;150m0\033[38;2;153;153;152m011\033[38;2;155;155;154m1\033[38;2;156;156;155m0\033[38;2;155;155;154m0\033[38;2;155;155;153m1\033[38;2;154;154;153m0\033[38;2;154;155;154m1\033[38;2;155;155;154m1\033[38;2;154;154;154m1\033[38;2;154;153;153m0\033[38;2;153;153;152m0\033[38;2;153;152;152m1\033[38;2;151;151;150m00\033[38;2;160;160;159m0\033[38;2;131;131;131m1\033[38;2;72;71;69m1\033[38;2;57;56;54m0\033[38;2;55;55;55m1\033[38;2;51;52;51m0\033[38;2;41;41;41m0\033[38;2;39;39;39m00\033[38;2;40;40;40m1\033[38;2;43;43;43m1\033[38;2;51;51;51m0\033[38;2;70;71;71m1\033[38;2;112;114;114m1\033[38;2;139;140;139m1\033[38;2;151;152;152m1\033[38;2;165;165;165m1\033[38;2;158;159;160m0\033[38;2;142;143;144m0\033[38;2;137;138;139m0\033[38;2;122;124;125m0\033[38;2;83;87;91m0\033[38;2;49;52;56m0\033[38;2;34;36;39m1\033[38;2;29;30;32m0\033[38;2;25;26;29m1\033[0m
\033[38;2;13;12;12m0\033[38;2;13;13;12m1\033[38;2;15;15;14m1\033[38;2;14;15;14m0\033[38;2;16;16;15m0\033[38;2;18;17;17m0\033[38;2;19;19;18m0\033[38;2;22;21;20m10\033[38;2;24;24;23m0\033[38;2;28;28;27m1\033[38;2;30;30;29m1\033[38;2;31;31;30m1\033[38;2;32;32;32m1\033[38;2;33;33;33m1\033[38;2;34;34;34m0\033[38;2;35;35;35m0\033[38;2;36;36;36m1\033[38;2;37;38;38m0\033[38;2;39;39;39m1\033[38;2;40;40;40m00\033[38;2;41;41;40m1\033[38;2;41;42;41m0\033[38;2;42;42;41m1\033[38;2;42;42;42m1101\033[38;2;42;42;41m1\033[38;2;41;41;41m0\033[38;2;41;41;40m1\033[38;2;40;40;39m1\033[38;2;38;38;37m0\033[38;2;34;34;34m0\033[38;2;31;31;31m1\033[38;2;33;33;32m1\033[38;2;32;32;31m1\033[38;2;30;30;29m1\033[38;2;28;28;28m01\033[38;2;27;27;27m111\033[38;2;28;28;28m1\033[38;2;29;29;29m0\033[38;2;32;32;32m1\033[38;2;33;34;34m1\033[38;2;35;35;35m0\033[38;2;37;37;37m1\033[38;2;38;38;38m0\033[38;2;39;39;39m1\033[38;2;38;39;39m1\033[38;2;36;36;37m1\033[38;2;32;32;33m1\033[38;2;30;30;31m1\033[38;2;29;29;29m0\033[38;2;27;27;27m0\033[38;2;25;25;25m0\033[38;2;23;23;24m0\033[0m
\033[38;2;12;12;12m0\033[38;2;13;13;13m0\033[38;2;14;14;14m1\033[38;2;14;14;15m1\033[38;2;15;15;15m1\033[38;2;16;16;16m00\033[38;2;17;17;17m0\033[38;2;18;18;18m1\033[38;2;19;19;18m1\033[38;2;19;19;19m1\033[38;2;20;20;20m0\033[38;2;20;21;19m0\033[38;2;20;20;20m1\033[38;2;21;21;21m0\033[38;2;21;22;21m1\033[38;2;21;21;21m0\033[38;2;22;22;22m00\033[38;2;23;23;22m0\033[38;2;23;23;23m1\033[38;2;23;24;23m1\033[38;2;24;24;22m1\033[38;2;24;24;23m0\033[38;2;24;24;24m001\033[38;2;25;25;25m01\033[38;2;24;24;24m1\033[38;2;25;25;24m1\033[38;2;24;25;24m1\033[38;2;24;24;24m0\033[38;2;25;25;25m01\033[38;2;24;24;24m01\033[38;2;24;24;23m1\033[38;2;23;23;23m1\033[38;2;22;22;22m10100100\033[38;2;23;23;23m1\033[38;2;24;24;24m1010\033[38;2;25;25;25m0\033[38;2;25;24;24m0\033[38;2;23;24;24m1\033[38;2;23;23;22m0\033[38;2;22;22;22m0\033[38;2;21;21;21m0\033[38;2;21;21;20m0\033[38;2;20;20;20m1\033[0m
\033[38;2;12;12;12m01\033[38;2;13;13;13m00\033[38;2;13;14;13m1\033[38;2;14;14;14m0\033[38;2;15;15;15m10\033[38;2;16;16;16m001\033[38;2;16;17;17m1\033[38;2;17;17;17m11\033[38;2;18;18;18m001\033[38;2;19;19;19m1100\033[38;2;19;20;20m0\033[38;2;20;20;19m0\033[38;2;20;20;20m110\033[38;2;21;21;21m1\033[38;2;20;20;20m010\033[38;2;20;20;21m1\033[38;2;21;21;21m1\033[38;2;20;20;20m1\033[38;2;21;21;21m0\033[38;2;20;20;20m01011101\033[38;2;19;20;19m1\033[38;2;19;19;19m1\033[38;2;20;20;20m00\033[38;2;19;19;20m1\033[38;2;20;20;20m00001\033[38;2;21;21;21m0\033[38;2;20;21;20m0\033[38;2;20;20;20m10\033[38;2;19;20;19m1\033[38;2;19;19;19m00\033[38;2;18;18;18m0\033[0m
EOF_TUI_LOGO
}
_zd_logo_medium_block() {
    while IFS= read -r line; do printf '%b\n' "$line"; done <<'EOF_TUI_LOGO_MEDIUM'
\033[38;2;12;12;12m0\033[38;2;14;14;14m010\033[38;2;15;15;15m0\033[38;2;16;16;16m1\033[38;2;18;18;18m01\033[38;2;20;20;20m10\033[38;2;21;21;21m01001\033[38;2;22;22;22m000\033[38;2;21;21;21m10\033[38;2;20;20;20m1\033[38;2;19;19;19m0\033[38;2;18;18;18m1\033[38;2;17;17;17m000\033[38;2;16;16;16m0111\033[0m
\033[38;2;13;13;13m1\033[38;2;14;14;14m01\033[38;2;15;15;15m1\033[38;2;18;18;18m1\033[38;2;22;22;22m0\033[38;2;25;25;25m0\033[38;2;29;29;29m1\033[38;2;31;32;32m1\033[38;2;33;33;33m0\033[38;2;34;34;34m1\033[38;2;33;33;33m1\033[38;2;32;32;32m00\033[38;2;33;33;33m0\033[38;2;34;34;34m0\033[38;2;34;35;35m1\033[38;2;34;34;34m00\033[38;2;36;36;36m0\033[38;2;34;34;34m0\033[38;2;28;28;28m0\033[38;2;23;23;23m1\033[38;2;20;20;20m11\033[38;2;19;19;19m0\033[38;2;18;18;18m10\033[38;2;17;17;17m0\033[38;2;18;17;18m0\033[0m
\033[38;2;12;12;12m0\033[38;2;14;14;14m0\033[38;2;16;16;16m0\033[38;2;23;23;23m1\033[38;2;44;44;44m0\033[38;2;79;80;80m1\033[38;2;116;116;116m1\033[38;2;152;152;150m1\033[38;2;157;157;156m1\033[38;2;160;160;158m1\033[38;2;162;162;160m0\033[38;2;161;162;160m0\033[38;2;159;160;158m1\033[38;2;159;159;158m01\033[38;2;160;160;159m0\033[38;2;160;160;160m1\033[38;2;161;161;161m1\033[38;2;162;162;162m0\033[38;2;165;166;164m1\033[38;2;180;179;177m0\033[38;2;105;105;104m0\033[38;2;57;59;59m1\033[38;2;34;36;37m1\033[38;2;26;25;26m0\033[38;2;23;23;24m0\033[38;2;21;21;22m1\033[38;2;20;20;21m0\033[38;2;20;20;20m11\033[0m
\033[38;2;13;13;13m1\033[38;2;15;15;15m1\033[38;2;23;23;23m0\033[38;2;52;52;52m1\033[38;2;179;179;178m0\033[38;2;150;150;149m1\033[38;2;59;60;59m0\033[38;2;56;56;56m1\033[38;2;60;60;60m1\033[38;2;66;65;66m0\033[38;2;68;67;67m1\033[38;2;67;66;67m1\033[38;2;64;63;64m0\033[38;2;61;61;61m0\033[38;2;60;60;58m1\033[38;2;59;58;58m0\033[38;2;58;58;57m0\033[38;2;59;59;58m0\033[38;2;66;66;64m0\033[38;2;86;85;83m1\033[38;2;163;162;161m0\033[38;2;187;188;186m0\033[38;2;83;85;85m0\033[38;2;72;74;74m1\033[38;2;56;58;60m1\033[38;2;39;40;42m0\033[38;2;31;31;33m1\033[38;2;25;25;26m0\033[38;2;22;22;22m0\033[38;2;21;21;21m0\033[0m
\033[38;2;14;14;13m0\033[38;2;16;16;16m1\033[38;2;23;23;24m1\033[38;2;47;47;47m0\033[38;2;150;150;150m1\033[38;2;115;115;114m1\033[38;2;60;59;58m1\033[38;2;82;82;80m0\033[38;2;175;175;173m0\033[38;2;168;168;166m0\033[38;2;170;169;168m0\033[38;2;172;172;169m0\033[38;2;168;167;164m1\033[38;2;132;132;128m0\033[38;2;55;54;53m1\033[38;2;42;42;42m1\033[38;2;45;45;44m1\033[38;2;63;63;61m0\033[38;2;136;136;134m0\033[38;2;177;177;175m0\033[38;2;120;120;118m1\033[38;2;98;97;94m1\033[38;2;171;172;169m1\033[38;2;169;169;168m1\033[38;2;174;176;175m0\033[38;2;132;136;137m0\033[38;2;54;56;58m0\033[38;2;34;36;37m0\033[38;2;26;26;26m0\033[38;2;22;22;23m1\033[0m
\033[38;2;14;14;13m1\033[38;2;16;16;16m0\033[38;2;19;19;18m1\033[38;2;27;27;26m1\033[38;2;55;55;53m1\033[38;2;139;139;138m0\033[38;2;172;172;170m1\033[38;2;140;140;136m0\033[38;2;202;202;199m0\033[38;2;102;100;98m0\033[38;2;100;99;97m1\033[38;2;174;172;170m1\033[38;2;182;181;179m1\033[38;2;100;99;97m1\033[38;2;61;59;58m1\033[38;2;68;68;66m1\033[38;2;135;134;132m0\033[38;2;177;178;175m1\033[38;2;117;116;114m1\033[38;2;72;71;69m0\033[38;2;131;132;128m1\033[38;2;176;177;175m1\033[38;2;86;86;86m1\033[38;2;64;64;64m0\033[38;2;111;112;112m0\033[38;2;188;189;188m1\033[38;2;124;129;131m1\033[38;2;47;48;50m0\033[38;2;31;31;31m0\033[38;2;24;24;24m0\033[0m
\033[38;2;14;14;14m1\033[38;2;15;15;14m1\033[38;2;16;16;16m0\033[38;2;20;20;18m0\033[38;2;25;26;24m1\033[38;2;37;37;35m1\033[38;2;66;66;64m0\033[38;2;115;114;112m1\033[38;2;119;118;115m1\033[38;2;170;169;166m0\033[38;2;183;183;180m0\033[38;2;109;108;106m0\033[38;2;66;65;63m0\033[38;2;72;71;69m1\033[38;2;137;136;134m1\033[38;2;191;190;188m0\033[38;2;136;135;133m0\033[38;2;86;84;83m0\033[38;2;87;86;84m0\033[38;2;87;86;85m1\033[38;2;116;116;113m1\033[38;2;212;212;209m0\033[38;2;109;110;108m1\033[38;2;58;58;58m0\033[38;2;86;87;87m0\033[38;2;173;174;173m1\033[38;2;155;158;159m1\033[38;2;52;54;56m0\033[38;2;32;32;32m1\033[38;2;25;25;25m0\033[0m
\033[38;2;15;15;15m0\033[38;2;16;16;15m0\033[38;2;17;17;17m0\033[38;2;20;21;20m0\033[38;2;26;26;25m1\033[38;2;38;38;36m0\033[38;2;68;66;64m0\033[38;2;148;148;146m1\033[38;2;185;185;183m0\033[38;2;114;114;112m0\033[38;2;67;65;63m1\033[38;2;70;70;67m0\033[38;2;132;132;130m0\033[38;2;186;186;183m0\033[38;2;142;141;139m0\033[38;2;107;106;103m1\033[38;2;172;170;168m0\033[38;2;183;183;181m1\033[38;2;151;149;148m0\033[38;2;150;149;148m0\033[38;2;136;136;134m1\033[38;2;98;98;96m1\033[38;2;59;59;59m1\033[38;2;70;70;70m0\033[38;2;137;139;137m0\033[38;2;195;196;194m0\033[38;2;84;86;86m1\033[38;2;43;44;46m1\033[38;2;30;30;30m0\033[38;2;24;24;24m0\033[0m
\033[38;2;16;16;16m1\033[38;2;17;17;17m1\033[38;2;21;22;21m1\033[38;2;32;32;30m0\033[38;2;58;58;56m0\033[38;2;138;139;137m0\033[38;2;185;185;183m1\033[38;2;118;117;115m0\033[38;2;64;63;61m0\033[38;2;68;67;66m0\033[38;2;129;128;126m0\033[38;2;191;192;189m0\033[38;2;140;139;137m1\033[38;2;74;73;71m0\033[38;2;66;64;63m1\033[38;2;94;93;92m0\033[38;2;179;179;177m0\033[38;2;132;131;128m0\033[38;2;78;77;76m0\033[38;2;57;57;56m1\033[38;2;50;50;49m0\033[38;2;52;52;52m0\033[38;2;94;95;94m0\033[38;2;172;173;172m1\033[38;2;162;163;162m1\033[38;2;82;82;83m0\033[38;2;46;48;49m1\033[38;2;34;34;35m1\033[38;2;27;27;27m1\033[38;2;24;24;23m1\033[0m
\033[38;2;17;17;17m0\033[38;2;22;22;20m0\033[38;2;36;36;34m0\033[38;2;96;96;95m0\033[38;2;186;186;183m1\033[38;2;116;116;114m1\033[38;2;53;52;50m0\033[38;2;45;44;43m1\033[38;2;90;90;88m0\033[38;2;188;188;185m1\033[38;2;182;182;179m1\033[38;2;141;140;139m0\033[38;2;127;126;125m1\033[38;2;123;122;120m0\033[38;2;121;121;119m0\033[38;2;120;120;118m1\033[38;2;104;103;101m1\033[38;2;128;127;124m1\033[38;2;196;196;194m1\033[38;2;145;145;144m1\033[38;2;79;79;78m1\033[38;2;63;63;62m1\033[38;2;86;86;86m1\033[38;2;168;168;166m1\033[38;2;164;165;165m1\033[38;2;84;86;87m1\033[38;2;51;52;53m0\033[38;2;38;39;39m0\033[38;2;31;31;32m1\033[38;2;27;27;28m1\033[0m
\033[38;2;20;20;19m1\033[38;2;32;32;31m0\033[38;2;86;86;84m0\033[38;2;208;208;206m0\033[38;2;96;95;93m0\033[38;2;42;42;40m1\033[38;2;34;35;33m0\033[38;2;36;37;34m0\033[38;2;51;50;49m1\033[38;2;63;61;60m1\033[38;2;97;96;95m1\033[38;2;106;106;104m0\033[38;2;109;108;106m1\033[38;2;110;109;107m0\033[38;2;112;110;109m1\033[38;2;118;117;116m0\033[38;2;168;168;166m1\033[38;2;188;188;186m0\033[38;2;126;125;123m0\033[38;2;148;148;146m1\033[38;2;194;195;193m1\033[38;2;142;142;141m1\033[38;2;81;82;80m0\033[38;2;71;71;71m0\033[38;2;118;118;117m0\033[38;2;190;191;190m0\033[38;2;156;158;158m0\033[38;2;74;76;77m0\033[38;2;44;46;47m1\033[38;2;32;33;34m0\033[0m
\033[38;2;19;19;17m0\033[38;2;38;37;35m1\033[38;2;147;147;144m1\033[38;2;121;120;117m1\033[38;2;120;118;116m1\033[38;2;109;108;106m1\033[38;2;110;108;107m0\033[38;2;112;112;110m1\033[38;2;114;114;113m0\033[38;2;116;116;114m0\033[38;2;120;119;118m1\033[38;2;122;122;120m0\033[38;2;123;122;121m0\033[38;2;124;122;121m0\033[38;2;125;124;123m1\033[38;2;128;128;126m0\033[38;2;133;132;130m0\033[38;2;162;160;158m1\033[38;2;186;185;182m0\033[38;2;118;118;115m0\033[38;2;80;79;78m0\033[38;2;145;146;144m1\033[38;2;160;161;160m1\033[38;2;122;123;123m1\033[38;2;131;131;130m0\033[38;2;154;155;155m0\033[38;2;180;181;181m1\033[38;2;182;184;186m1\033[38;2;66;70;75m0\033[38;2;32;34;37m1\033[0m
\033[38;2;14;14;13m0\033[38;2;20;21;19m1\033[38;2;26;26;24m0\033[38;2;40;38;36m1\033[38;2;80;80;78m1\033[38;2;84;84;83m0\033[38;2;87;87;86m0\033[38;2;89;89;89m1\033[38;2;92;92;92m0\033[38;2;96;96;95m0\033[38;2;97;97;96m1\033[38;2;98;98;98m0\033[38;2;98;98;97m1\033[38;2;98;98;98m11\033[38;2;97;97;96m0\033[38;2;95;95;94m0\033[38;2;89;89;89m0\033[38;2;48;48;46m1\033[38;2;41;41;41m1\033[38;2;34;34;34m0\033[38;2;33;33;33m1\033[38;2;38;38;38m0\033[38;2;62;63;63m1\033[38;2;90;91;91m1\033[38;2;100;100;100m1\033[38;2;88;89;90m0\033[38;2;67;68;70m0\033[38;2;35;36;38m0\033[38;2;26;26;28m0\033[0m
\033[38;2;12;12;12m0\033[38;2;14;14;14m1\033[38;2;14;15;14m0\033[38;2;16;16;16m0\033[38;2;17;17;17m1\033[38;2;18;18;18m0\033[38;2;18;19;18m0\033[38;2;20;20;20m10\033[38;2;21;21;20m0\033[38;2;21;22;21m1\033[38;2;22;22;21m0\033[38;2;22;22;22m001\033[38;2;22;23;22m1\033[38;2;22;22;22m011\033[38;2;21;21;21m10\033[38;2;20;21;20m0\033[38;2;21;21;21m11\033[38;2;22;22;22m11\033[38;2;23;23;22m0\033[38;2;22;22;22m1\033[38;2;20;20;20m0\033[38;2;20;20;19m0\033[0m
EOF_TUI_LOGO_MEDIUM
}

_zd_logo_small_block() {
    while IFS= read -r line; do printf '%b\n' "$line"; done <<'EOF_TUI_LOGO_SMALL'
\033[38;2;13;13;13m0\033[38;2;14;14;14m0\033[38;2;15;15;15m1\033[38;2;19;19;19m0\033[38;2;23;23;23m0\033[38;2;27;27;27m1\033[38;2;29;29;29m1100\033[38;2;30;30;30m1010\033[38;2;24;24;25m0\033[38;2;20;19;19m0\033[38;2;19;19;19m1\033[38;2;18;18;18m1\033[38;2;17;17;17m00\033[0m
\033[38;2;13;13;13m0\033[38;2;16;17;16m1\033[38;2;38;38;38m1\033[38;2;108;109;108m1\033[38;2;107;107;107m1\033[38;2;128;129;128m1\033[38;2;133;133;132m1\033[38;2;134;134;133m0\033[38;2;132;132;132m1\033[38;2;132;132;130m1\033[38;2;132;132;131m0\033[38;2;132;133;132m1\033[38;2;136;136;135m1\033[38;2;153;153;151m0\033[38;2;117;118;117m0\033[38;2;42;44;45m1\033[38;2;29;29;30m0\033[38;2;24;24;25m0\033[38;2;21;21;22m0\033[38;2;20;20;20m1\033[0m
\033[38;2;14;14;14m0\033[38;2;21;21;22m0\033[38;2;84;84;84m1\033[38;2;143;143;142m0\033[38;2;56;56;55m1\033[38;2;116;115;114m0\033[38;2;131;130;129m0\033[38;2;132;132;130m0\033[38;2;124;123;121m0\033[38;2;65;64;62m1\033[38;2;42;42;42m1\033[38;2;52;52;50m0\033[38;2;120;120;118m0\033[38;2;149;148;146m0\033[38;2;125;125;123m0\033[38;2;149;150;149m1\033[38;2;135;137;137m0\033[38;2;59;62;64m1\033[38;2;30;31;31m0\033[38;2;23;23;23m1\033[0m
\033[38;2;14;14;14m0\033[38;2;17;18;17m1\033[38;2;29;29;28m1\033[38;2;89;89;88m0\033[38;2;143;143;140m1\033[38;2;171;171;167m0\033[38;2;114;113;110m0\033[38;2;160;159;157m1\033[38;2;130;129;127m1\033[38;2;70;69;67m0\033[38;2;122;122;120m0\033[38;2;146;146;144m0\033[38;2;89;89;87m1\033[38;2;103;103;100m1\033[38;2;167;168;166m0\033[38;2;65;66;65m1\033[38;2;119;120;120m1\033[38;2;162;165;166m1\033[38;2;44;45;46m0\033[38;2;26;26;26m0\033[0m
\033[38;2;15;15;15m0\033[38;2;16;16;16m0\033[38;2;21;21;20m0\033[38;2;33;33;31m0\033[38;2;74;74;71m1\033[38;2;152;151;149m1\033[38;2;136;135;133m0\033[38;2;74;73;71m0\033[38;2;121;121;119m1\033[38;2;157;157;154m1\033[38;2;135;134;132m1\033[38;2;153;153;151m0\033[38;2;137;136;134m0\033[38;2;136;136;134m0\033[38;2;118;118;117m0\033[38;2;63;63;63m0\033[38;2;141;142;141m0\033[38;2;136;137;137m0\033[38;2;41;42;44m0\033[38;2;26;26;26m1\033[0m
\033[38;2;16;16;16m0\033[38;2;22;23;22m0\033[38;2;54;54;53m0\033[38;2;139;139;137m0\033[38;2;133;133;131m1\033[38;2;70;69;67m1\033[38;2;117;117;115m1\033[38;2;161;161;159m0\033[38;2;105;104;102m1\033[38;2;67;66;64m1\033[38;2;104;103;101m0\033[38;2;143;142;139m0\033[38;2;105;105;103m1\033[38;2;57;57;56m0\033[38;2;62;62;62m1\033[38;2;159;159;158m1\033[38;2;126;128;127m1\033[38;2;51;52;53m1\033[38;2;32;33;33m1\033[38;2;25;25;25m1\033[0m
\033[38;2;21;21;20m1\033[38;2;59;59;57m0\033[38;2;174;174;172m0\033[38;2;65;64;62m1\033[38;2;36;37;34m1\033[38;2;61;61;58m0\033[38;2;109;108;106m1\033[38;2;130;129;128m0\033[38;2;132;131;130m10\033[38;2;141;140;139m0\033[38;2;160;160;158m0\033[38;2;151;151;149m1\033[38;2;164;164;162m1\033[38;2;105;105;104m1\033[38;2;87;88;87m1\033[38;2;156;156;155m0\033[38;2;136;137;137m0\033[38;2;57;58;59m0\033[38;2;33;33;35m1\033[0m
\033[38;2;20;19;18m1\033[38;2;88;87;85m1\033[38;2;109;108;105m1\033[38;2;121;120;118m0\033[38;2;121;120;119m0\033[38;2;125;125;124m0\033[38;2;129;129;128m1\033[38;2;133;133;131m1\033[38;2;134;133;132m0\033[38;2;134;134;133m1\033[38;2;137;137;135m0\033[38;2;151;150;148m1\033[38;2;134;133;131m0\033[38;2;72;71;70m0\033[38;2;117;118;117m1\033[38;2;112;113;113m1\033[38;2;142;143;142m0\033[38;2;163;164;165m1\033[38;2;127;130;133m1\033[38;2;36;38;41m0\033[0m
\033[38;2;13;13;13m1\033[38;2;15;15;15m0\033[38;2;18;18;17m1\033[38;2;21;21;21m1\033[38;2;23;23;23m1\033[38;2;25;25;25m1\033[38;2;27;27;27m0\033[38;2;28;28;28m0\033[38;2;29;29;29m10\033[38;2;28;29;28m0\033[38;2;26;26;26m0\033[38;2;25;25;25m1\033[38;2;23;23;23m01\033[38;2;24;25;25m1\033[38;2;27;27;27m0\033[38;2;28;28;28m1\033[38;2;24;24;24m1\033[38;2;21;21;21m0\033[0m
EOF_TUI_LOGO_SMALL
}

_zd_logo_tiny_block() {
    while IFS= read -r line; do printf '%b\n' "$line"; done <<'EOF_TUI_LOGO_TINY'
\033[38;2;13;13;13m0\033[38;2;17;17;17m0\033[38;2;37;37;37m0\033[38;2;55;55;55m1\033[38;2;57;58;57m0\033[38;2;57;57;57m0\033[38;2;58;58;58m0\033[38;2;59;59;59m0\033[38;2;47;47;46m0\033[38;2;21;21;21m1\033[38;2;18;18;19m0\033[38;2;18;18;18m0\033[0m
\033[38;2;15;15;15m1\033[38;2;80;81;80m0\033[38;2;97;97;96m1\033[38;2;123;123;122m0\033[38;2;132;131;130m1\033[38;2;102;102;100m0\033[38;2;77;77;76m1\033[38;2;121;121;119m0\033[38;2;140;140;138m0\033[38;2;104;106;106m1\033[38;2;50;52;53m0\033[38;2;23;23;24m0\033[0m
\033[38;2;15;15;15m0\033[38;2;29;29;28m1\033[38;2;107;107;105m1\033[38;2;145;145;142m0\033[38;2;140;139;137m1\033[38;2;97;96;94m1\033[38;2;133;132;130m0\033[38;2;98;98;96m1\033[38;2;152;153;150m0\033[38;2;77;78;78m0\033[38;2;139;142;142m1\033[38;2;31;31;32m1\033[0m
\033[38;2;17;17;17m1\033[38;2;46;46;45m0\033[38;2;111;110;108m1\033[38;2;112;111;109m1\033[38;2;122;122;120m0\033[38;2;110;110;108m0\033[38;2;132;131;129m0\033[38;2;124;123;122m1\033[38;2;78;78;77m1\033[38;2;130;130;130m1\033[38;2;82;83;83m0\033[38;2;28;28;28m0\033[0m
\033[38;2;33;33;32m0\033[38;2;140;140;138m0\033[38;2;45;44;43m1\033[38;2;75;75;73m1\033[38;2;112;111;109m0\033[38;2;117;116;115m1\033[38;2;134;134;132m1\033[38;2;159;158;157m0\033[38;2;137;137;136m1\033[38;2;109;109;109m1\033[38;2;136;138;138m0\033[38;2;46;48;49m1\033[0m
\033[38;2;22;22;21m1\033[38;2;54;53;52m1\033[38;2;75;75;74m1\033[38;2;79;79;79m0\033[38;2;83;83;82m1\033[38;2;83;83;83m1\033[38;2;84;84;83m1\033[38;2;58;58;57m0\033[38;2;39;39;39m0\033[38;2;68;69;69m0\033[38;2;83;83;84m0\033[38;2;37;38;40m1\033[0m
EOF_TUI_LOGO_TINY
}


_zd_draw_header() {
    # Pick a logo size from BOTH width and height. A 60x27 logo is beautiful on
    # a large terminal but leaves no room for menus on a normal 80x24 display.
    # Compact variants preserve the artwork while keeping the controls visible.
    local logo line logo_width logo_pad header_mode
    if (( TUI_COLS >= 64 && TUI_LINES >= 42 )); then
        logo="$(_zd_logo_block)"; logo_width=60; header_mode=full
    elif (( TUI_COLS >= 36 && TUI_LINES >= 30 )); then
        logo="$(_zd_logo_medium_block)"; logo_width=30; header_mode=medium
    elif (( TUI_COLS >= 24 && TUI_LINES >= 19 )); then
        logo="$(_zd_logo_small_block)"; logo_width=20; header_mode=small
    else
        logo="$(_zd_logo_tiny_block)"; logo_width=12; header_mode=tiny
    fi

    logo_pad=$(( (TUI_COLS - logo_width) / 2 )); (( logo_pad < 0 )) && logo_pad=0
    while IFS= read -r line; do
        printf '%*s%s\n' "$logo_pad" '' "$line"
    done <<< "$logo"

    if [[ "$header_mode" == full || "$header_mode" == medium ]]; then
        printf '\n'
        _zd_print_center 'ZARZYSSEUS'
        _zd_print_center 'AI INSTALLER / SERVICE MANAGER'
    elif [[ "$header_mode" == small ]]; then
        _zd_print_center 'ZARZYSSEUS — AI INSTALLER'
    else
        if (( TUI_LINES >= 12 )); then
            _zd_print_center 'ZARZYSSEUS'
        fi
    fi
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
        TUI_COLS=$cols; TUI_LINES=$lines
        local head="" head_lines=0 line draw_row hleft pad label width avail top_padding
        head="$(_zd_draw_header)"
        while IFS= read -r line; do ((head_lines+=1)); done <<< "$head"
        ((head_lines>0)) && ((head_lines-=1))
        # If the terminal shrinks, keep selections visible with a scrolling list.
        avail=$((lines - head_lines - 6)); ((avail<2)) && avail=2
        visible=$avail
        start=1
        if ((selected>visible)); then start=$((selected-visible+1)); fi
        end=$((start+visible-1)); ((end>count)) && end=$count
        top_padding=$(( (lines - head_lines - (end-start+1) - 6)/2 ))
        ((top_padding<0)) && top_padding=0
        printf '\033[H\033[2J%s' "$head"
        for ((draw_row=0;draw_row<top_padding;draw_row++)); do printf '\n'; done
        _zd_print_center '------------------------------------------------'
        _zd_print_center "$title"
        _zd_print_center '[UP/DOWN] Move   [ENTER] Select   [Q] Back'
        printf '\n'
        ((start>1)) && _zd_print_center '[more above]'
        for ((i=start;i<=end;i++)); do
            label="${items[i-1]}"
            width=$((cols-8)); ((width<12)) && width=12
            if (( ${#label}>width )); then label="${label:0:width-3}..."; fi
            if ((i==selected)); then label="> $label"; else label="  $label"; fi
            pad=$(( (cols-${#label})/2 )); ((pad<0)) && pad=0
            printf '%*s%s\n' "$pad" '' "$label"
        done
        ((end<count)) && _zd_print_center '[more below]'
        _zd_print_center 'Back / Exit [Q]'
        if [[ -n "$typed" ]]; then _zd_print_center "Choice: $typed"; fi
        key=''; IFS= read -rsn1 key < /dev/tty || { _zd_restore; return 1; }
        case "$key" in
            $'\e')
                extra=''; IFS= read -rsn2 -t 0.12 extra < /dev/tty || :
                case "$extra" in
                    '[A') selected=$((selected-1)); (( selected < 1 )) && selected=$count; typed='' ;;
                    '[B') selected=$((selected+1)); (( selected > count )) && selected=1; typed='' ;;
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
        'SWITCH TO NATIVE MODE' 'SWITCH CPU-ONLY / FULL PROFILE' 'ACCOUNT / LOGIN'
    )
    while true; do
        _zd_choose "ZARZYSSEUS — DOCKER MODE — ${profile^^} PROFILE" "${menu_items[@]}" || return 0
        option="$ZD_SELECTION"
        case "$option" in
            1) submenu 'INSTALL / UPDATE' 'Install Odysseus + CPU model (always available)|install' 'Install/refresh toolkit helper|toolkit-install' 'Check current status|status' 'Check Ollama Modelfile mount|model-mount-check' 'Repair Ollama Modelfile mount (confirm REMOUNT)|model-mount-repair' 'First-run admin account setup|auth-setup' 'Existing-account password help|auth-help' ;;
            2) submenu 'SERVICES' 'Start Odysseus|start' 'Stop services|stop' 'Restart Odysseus|restart' 'Show status|status' 'Show logs|logs' 'Stop containers, retain volumes|down' ;;
            3)
                if [[ "$profile" == full ]]; then
                    submenu 'MODEL RUNTIMES — FULL' 'CPU Ollama readiness|ollama-status' 'AMD RDNA3 diagnostics (no model download)|gpu-doctor' 'Test Docker DNS / Hugging Face HTTPS|gpu-dns-check' 'Start RDNA3 SGLang (explicit consent)|gpu-start' 'GPU readiness|gpu-status' 'GPU logs|gpu-logs' 'Run real generation test|gpu-test' 'Stop GPU model server|gpu-stop'
                else
                    submenu 'MODEL RUNTIMES — CPU-ONLY' 'CPU Ollama readiness|ollama-status' 'List CPU Ollama models|models' 'CPU model benchmark|benchmark quality'
                fi ;;
            4) submenu 'MODEL MANAGER / HARDWARE FIT' 'Model visibility doctor (container + UI)|model-doctor' 'Skill-aware model advisor|model-advisor' 'Models in CPU Ollama|models' 'Benchmark quality model|benchmark quality' ;;
            5) submenu 'OLLAMA MANAGEMENT' 'Install Qwen3.5 CPU quality profile|model-setup quality' 'Install LFM 2.6B agent profile|model-setup agent' 'Warm quality model|warm quality' 'List installed models|models' 'Diagnose Odysseus model visibility|model-doctor' 'Check Qwen Modelfile mount|model-mount-check' 'Repair Qwen Modelfile mount|model-mount-repair' 'Pull a named model|prompt:pull' 'Stop model backend|ollama-stop' ;;
            6) unsupported 'macOS MLX-LM on a Linux CPU container' || : ;;
            7) submenu 'HUGGING FACE / MODEL FILES' 'Catalog/model advisor (read only)|model-advisor' 'Why no Hugging Face chat launcher?|info:hf' ;;
            8) submenu 'SKILLS.SH / AGENT SKILLS' 'List installed skills|skills-list' 'Search skill|prompt:skills-search' 'Install selected skill|prompt:skills-install' 'Skills + MCP health|skills-doctor' 'Approve/setup dependencies|skills-setup' 'Skill model advisor|model-advisor' ;;
            9) submenu 'MCP / FREEMCP' 'MCP health|mcp-health' 'MCP setup (may download deps)|mcp-setup' 'Agent diagnostic|agent-doctor' ;;
            10) submenu 'DIAGNOSTICS / TOOLS / ADVANCED' 'Docker + Agent + skills doctor|doctor' 'Models / Ollama reachability|model-doctor' 'Apply guarded Agent repairs|repair' 'Cookbook status|cookbook-fix status' 'Cookbook progress repair (version sensitive)|cookbook-fix progress' 'GPU runtime health|gpu-status' 'Show full help|help' ;;
            11) submenu 'NETWORK DISCOVERABILITY' 'Show address and CORS origins|network-status' 'Change LAN / Tailscale / localhost binding|network-configure' 'Apply saved network settings (recreate app)|network-apply' 'First-run admin account setup|auth-setup' ;;
            12)
                if [[ -n "${ZARZYSSEUS_MODE_SWITCH_CMD:-}" ]]; then
                    bash "$ZARZYSSEUS_MODE_SWITCH_CMD" mode native && exec bash "$ZARZYSSEUS_MODE_SWITCH_CMD" native
                else
                    echo 'Open the unified launcher and run: ./zarzysseus.sh mode native'
                fi
                ;;
            14) submenu 'ACCOUNT / LOGIN' 'First-run admin account setup|auth-setup' 'How to change an existing password|auth-help' 'View browser address|network-status' ;;
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
            *) local -a command_parts=(); read -r -a command_parts <<< "$action"; dispatch "${command_parts[@]}" || echo 'Action failed; inspect output.' ;;
        esac
        if [[ -t 0 && -t 1 && "${ZARZYSSEUS_MENU_STYLE:-auto}" != plain ]]; then
            read -r -p 'Press Enter to return to the menu... ' _zd_unused || return 0
        fi
    done
}

if [[ $# == 0 ]]; then
    if [[ -t 0 && -t 1 ]]; then menu; else dispatch help; fi
else
    dispatch "$@"
fi
