# Zarzysseus

An interactive AI installation and service-management toolkit for **Odysseus native Linux and Windows installs**, with my own custom favorite models and skills available for install under `Fave` selections.

Zarzysseus is a separate installer and management TUI for the upstream [Odysseus project](https://github.com/odysseus-dev/odysseus). It helps discover an existing checkout, install the native application, browse models, install skills, and repair supported dependencies. **The Linux and Windows editions do not yet have identical feature coverage**; see [Windows support](#windows-support) below.

## Quick links

**Get started:** [Hugging Face setup](#recommended-first-time-setup-hugging-face-linux-and-windows) · [Linux installation](#linux-installation) · [Windows installation](#windows-installation)

**Configure:** [Network access & security](#network-discoverability-and-security-linux-and-windows) · [Docker & ChromaDB](#docker-and-chromadb-setup-linux-and-windows) · [Linux OS-update toggle](#linux-full-os-update-toggle) · [Same-chat continuity & Cookbook](#same-chat-continuity-and-cookbook-reliability) · [MCP & FreeMCP](#mcp-runtime-built-ins-and-freemcp) · [Executable skills](#executable-skills-and-native-tool-routing) · [Linux distribution support](#linux-distribution-support) · [Windows support](#windows-support) · [Ollama vs Hugging Face model IDs](#ollama-vs-hugging-face-model-ids)

**Troubleshoot:** [Odysseus fixes & diagnostics](#odysseus-integration-fixes-and-diagnostics) · [Linux repair commands](#linux-repair-and-verify) · [Windows repair commands](#windows-repair-and-verify) · [Verify tool execution](#confirm-a-tool-was-actually-executed) · [Requirements](#requirements)

## Recommended first-time setup: Hugging Face (Linux **and** Windows)

**Hugging Face sign-in is recommended for either installer**, especially when downloading gated or private models. Public models often work without a token. A token alone does not grant gated-model access: open the model page and accept its terms or request access if required.

1. Create or sign in to your account at [huggingface.co](https://huggingface.co/).
2. Open **[Settings → Access Tokens](https://huggingface.co/settings/tokens)** and create a **Read** token, or a fine-grained token with read access to the specific repositories you want. Do not use a write token just for model downloads.
3. Copy the token privately. **Do not paste it into GitHub, your README, screenshots, chat, or a shared shell command.**
4. **Linux:** launch `./zarzysseus.sh`, open **Hugging Face / Model Files → Set / Inspect / Clear HF Token**, and paste the token when prompted (input is hidden). Or use `./zarzysseus.sh hf-token` after native stack installation; check it with `./zarzysseus.sh hf-token status`.
5. **Windows:** launch `zarzysseus.ps1`, choose **Hugging Face setup (recommended)**, and paste the token at the hidden prompt. Check it with `powershell -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 hf-token-status`.

Windows stores the Zarzysseus token encrypted for the current Windows user. On Linux, the installer persists the token in the Odysseus configuration with restrictive file permissions; keep your machine and configuration files private. You can clear a Zarzysseus-managed token in either TUI. Other Hugging Face tools may store separate credentials.

## Ollama vs Hugging Face model IDs

An `org/model`-shaped ID does **not** automatically mean it lives on Hugging Face. For example, [`tobestyledintro/qwen3.8-9b-distill`](https://ollama.com/tobestyledintro/qwen3.8-9b-distill) is published in the **Ollama registry**, so select it under **Fave text models** or install it with:

```bash
./zarzysseus.sh pull 'tobestyledintro/qwen3.8-9b-distill'
# Equivalent when Ollama is already running:
ollama pull tobestyledintro/qwen3.8-9b-distill
```

**Linux:** Zarzysseus routes this curated model through Ollama even before it is locally installed; manually selected Normal/text batches use that same route. The explicit `hf-pull` and `model-install` Hugging Face commands reject that particular Ollama ID with the correct command instead of repeatedly retrying a nonexistent Hugging Face repository.

**Windows:** The **Normal → Text** catalog includes **Qwen3.8 9B Distill (Ollama)**. Selecting and confirming it runs `ollama pull`, not a Hugging Face snapshot download. You can also use these Windows commands:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 ollama-pull 'tobestyledintro/qwen3.8-9b-distill'
# model-install routes this curated ID (and its optional Ollama tags) through Ollama too:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 model-install 'tobestyledintro/qwen3.8-9b-distill'
```

On either platform, explicitly choosing `hf-pull` for this particular Ollama registry ID stops before setting up or invoking the Hugging Face downloader and prints the appropriate Ollama command. Other Hugging Face repositories continue using their Hub download paths. For other ambiguous `org/model` registry names, explicitly choose `ollama-pull` or `hf-pull` according to their actual host; syntax alone does not prove which registry owns a model. An HF token or updating `huggingface_hub` cannot convert an Ollama registry ID into a Hugging Face repository.

## Network discoverability and security (Linux and Windows)

> **Security notice:** Zarzysseus defaults to starting the **Odysseus web server** on `0.0.0.0:7000` (unless you change the setting). `0.0.0.0` means **listen on all network interfaces**—not a URL to type in a browser. Depending on your firewall and network configuration, other devices on your LAN *or other routed networks* may reach the app. Do not assume that Odysseus provides authentication sufficient for exposure to untrusted networks; do **not** port-forward it or expose it directly to the public internet. Choose **Localhost only** if you don't need network access. Zarzysseus does not automatically open firewall rules.

Both installers have a **Network Discoverability** menu with persistent choices:

| Mode | Bind address | Access |
| --- | --- | --- |
| **Localhost only** | `127.0.0.1` | This computer only: `http://127.0.0.1:7000` |
| **Local network / all interfaces** | `0.0.0.0` | This computer plus network clients permitted by the firewall/routing; browse to `http://YOUR_LAN_IP:7000` |

Changing modes saves the choice across launches and applies it to an existing *managed* Odysseus server (restarting it if running). Changing this setting does **not** change Ollama or model backend binding. If you start Odysseus manually outside Zarzysseus, pass the desired `--host` yourself. Replace `7000` below if you configured a different port.

### Linux: find your LAN IP and connect

Open **Network Discoverability → Show current mode and LAN IP addresses**, or run:

```bash
./zarzysseus.sh network-mode status
ip -4 addr show
hostname -I
```

Find the private IPv4 address of your active Wi-Fi/Ethernet adapter (for example, `192.168.1.42`), not `127.0.0.1`, a VPN/container address, or `0.0.0.0`. On a phone or second computer on a network that can reach the host, open `http://192.168.1.42:7000` (substitute **your** IP). Use `./zarzysseus.sh network-mode localhost` to restrict access, or `./zarzysseus.sh network-mode lan` to enable listening on all interfaces. If it does not connect, verify Odysseus is running, the devices can route to each other, and your firewall permits the chosen port **only on trusted networks**.

### Windows: find your LAN IP and connect

Open **Network Discoverability** in the Windows menu, or use:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 network-mode status
ipconfig
Get-NetIPAddress -AddressFamily IPv4
```

Look for the IPv4 Address of the active Wi-Fi/Ethernet adapter (for example, `192.168.1.55`), not a virtual adapter, `127.0.0.1`, or `0.0.0.0`. From another device on a network that can reach the Windows computer, open `http://192.168.1.55:7000` (substitute **your** IP). To change the listener:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 network-mode localhost
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 network-mode lan
```

Windows Defender Firewall may block incoming connections; allowing the app/port on a **Private** trusted network is a separate decision and is **not** done automatically. Do not enable a Public-network rule just to make the server reachable. If your LAN address changes (DHCP/VPN), check it again.

## Docker and ChromaDB setup (Linux and Windows)

**Docker setup happens after you commit to an installation, not when you open the TUI or browse model choices.** On **Linux**, choosing **Install / Update full stack / auto-fit** (including a timed auto-fit confirmation), confirming **Normal** models in the full-stack manual picker, or confirming a manual model batch triggers a repeatable Docker Engine + Compose v2 preflight. An ordinary `install` command is also a committed installation. On **Windows**, **Install / Update native Windows Odysseus** or choosing **Install** and typing `YES` in the manual model browser triggers the Docker Desktop preflight. No Docker installation is attempted on status, read-only health checks, TUI launch, or merely highlighting models.

| Platform | Automatic provision on committed installation | Service/access details |
| --- | --- | --- |
| Linux | Install distro-packaged **Docker Engine + Compose v2** where a supported package recipe is available, then start the daemon and the checkout's existing `chromadb` Compose service | Uses an existing user-accessible Docker daemon when possible; otherwise runs Compose through `sudo`/`doas` on supported service managers. **Does not automatically join the `docker` group** (membership grants root-equivalent control). Some distros require repository setup or a reboot; unsupported Docker package recipes report instructions without running untrusted install scripts. |
| Windows | Install **Docker Desktop** through WinGet (`Docker.DockerDesktop`) if the CLI is missing; start Desktop, wait for Docker Engine and Compose, and use the checkout's `chromadb` service | WinGet may request administrator approval. Docker Desktop may require WSL 2, hardware virtualization, accepting first-run terms, a logout or reboot. If it cannot become ready in the current session, finish its setup and rerun the installer or `docker-setup`; model downloads can still proceed, but tool search may remain degraded. |

If a compatible ChromaDB heartbeat is already answering on `127.0.0.1:8100`, provisioning is skipped rather than installing another Docker stack. **No duplicate ChromaDB service is created**: Zarzysseus uses `docker compose up -d chromadb` from the detected checkout. On startup/restart, Zarzysseus attempts to start this service **if Docker is already available**; startup does not silently install Docker. Rerunning the installer or `docker-setup` is supported. Installing Docker itself does not prove the vector index is healthy; verify its heartbeat and Agent tool execution after startup.

**Explicit repair commands** (use the actual checkout directory instead of `~/odysseus` if different):

```bash
./zarzysseus.sh docker-setup
./zarzysseus.sh chromadb-start
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 docker-setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 chromadb-start
```

Set `ZARZYSSEUS_DOCKER_AUTO_INSTALL=0` to disable **automatic installation during committed actions**, or `CHROMADB_AUTO_START=0` to disable automatic ChromaDB startup (which also skips its Docker auto-preflight). `docker-setup` explicitly requests Docker provisioning even if those automatic behaviors are disabled. Neither script automatically opens firewall ports or makes Docker's TCP daemon publicly accessible.

## Linux installation

Run this in a Linux terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/zarzorr69/zarzyssues/main/zarzysseus.sh -o zarzysseus.sh && chmod +x zarzysseus.sh && ./zarzysseus.sh
```

The script is downloaded before execution so its interactive TUI retains terminal input. The URL assumes the public repository's default branch is `main` and `zarzysseus.sh` is at its root.

### Linux distribution support

Zarzysseus detects the Linux distribution and chooses an available package manager. The **package-manager adapters** in the current Linux installer cover these distribution families and examples:

| Distribution family | Examples | Detected package manager |
| --- | --- | --- |
| Arch Linux | Arch, CachyOS, Manjaro, EndeavourOS, Garuda | `pacman` |
| Debian / Ubuntu | Debian, Ubuntu, Linux Mint, Pop!_OS, Kali, MX Linux | `apt-get` |
| Fedora / RHEL | Fedora, RHEL, CentOS-family, Rocky Linux, AlmaLinux, Nobara, Amazon Linux, Oracle Linux | `dnf5`, `dnf`, `microdnf`, or `yum` |
| openSUSE / SUSE | openSUSE and SUSE derivatives | `zypper` |
| Alpine | Alpine Linux | `apk` |
| Void | Void Linux | `xbps-install` |
| Gentoo | Gentoo and Funtoo | `emerge` |
| Solus | Solus | `eopkg` |
| Clear Linux | Clear Linux | `swupd` |
| Mageia / related RPM distributions | Mageia and compatible systems | `urpmi` |
| Photon OS | VMware Photon OS | `tdnf` |
| Slackware | Slackware | `slackpkg` |
| NixOS | NixOS | `nix` |
| GNU Guix | Guix System | `guix` |
| rpm-ostree systems | Fedora Atomic desktops and compatible systems | `rpm-ostree` |

**What “supported” means here:** the Linux installer has package-manager detection and adapters for these ecosystems; this does **not** mean every model, accelerator, service-management operation, or distribution release has been tested. It detects `systemd`, OpenRC, runit, and s6, but some managed-service features are systemd-specific. Immutable systems and layered packages may require a reboot. GPU drivers, Python/runtime compatibility, repository availability, and model requirements can impose further limitations.

### Linux full OS update toggle

The Linux **Install / Update** menu now has a persistent **AUTO FULL OS UPDATE: ON/OFF** switch. It controls only the broad operating-system upgrade that Zarzysseus may run before a committed install/update. It does **not** disable installation of individual packages that Zarzysseus actually needs (for example Git, Python, Docker, build tools, or accelerator dependencies), and the explicit **RUN SYSTEM UPDATE NOW** action remains available.

The initial default is **ON** to preserve the previous installer behavior. Turn it off from the TUI, or use:

```bash
./zarzysseus.sh system-auto-update off
./zarzysseus.sh system-auto-update status
# Re-enable later:
./zarzysseus.sh system-auto-update on
```

The choice is stored under `~/.config/zarzysseus/system-auto-update` and survives reruns. Setting the `SYSTEM_AUTO_UPDATE` environment variable to `0` or `1` overrides the stored value for that invocation. **Windows is different:** the PowerShell installer already avoids full Windows OS upgrades, so there is no equivalent Windows-wide update toggle; it may still install or update specific prerequisites such as Git, Python, Ollama, or Docker Desktop when an action requires them.

### Linux features

- Terminal-size-aware installation and service-management TUI
- Existing Odysseus checkout discovery and launch-time upstream Git check
- AMD/ROCm, NVIDIA/CUDA, Intel/XPU and CPU detection and supported repair paths
- Normal, L.P.S. (Low Power Spec), and Desert Ant Labs model groups
- Text, photo, video, and audio browsers; auto-fit modes; manual batch selection
- Favorite model and skill options
- Skill health checks, selected-skill / Fix All dependency repair, executable-skill `requires_toolsets` repair, and native-tool routing
- Provider login handoff where supported
- Persistent localhost/LAN network discoverability controls
- Docker Engine + Compose v2 install-time preflight on supported Linux package managers; existing ChromaDB service startup (without installing Docker merely on TUI launch)
- ChromaDB startup/heartbeat and Ollama native-tool endpoint alias repair
- First-use Agent workspace set to the actual cloned/discovered checkout
- Tool health reporting and an automatically attempted, guarded Qwen explicit-tool + `/skill` focus patch (rerunnable manually)
- Persistent full-OS-update ON/OFF toggle for committed Linux install/update flows; required package installation remains independent
- Guarded same-chat continuity repair plus Cookbook retry/status compatibility bridge, both automatically checked and rerunnable

## Windows installation

Use **Windows PowerShell 5.1 or later** on Windows 10/11. Paste the following into PowerShell; the script downloads to a file before execution, preserving keyboard input for its menu:

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/zarzorr69/zarzyssues/main/zarzysseus.ps1' -OutFile "$env:TEMP\zarzysseus.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:TEMP\zarzysseus.ps1"
```

Alternatively, download `zarzysseus.ps1` from the repository and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1
```

The PowerShell script checks for an existing Odysseus checkout before opening its menu. **It does not upgrade Windows merely because you opened the TUI or browsed models.** Installing the app or confirming model downloads may install relevant prerequisites using WinGet. The `-ExecutionPolicy Bypass` argument applies only to the launched process; it does not change your permanent execution policy.

### Windows support

| Capability | Native Windows edition |
| --- | --- |
| Install/update Odysseus | Yes: upstream checkout, isolated Python environment, dependencies, setup |
| Run/stop/status | Yes: local Python server with current-user startup option |
| Same-chat continuity | Guarded session-lifecycle compatibility repair with backup; automatically checked on install/start and rerunnable with `chat-continuity-fix` |
| Cookbook reliability | Local HF retry shim plus guarded completed-download status repair; never performs a full Windows OS update |
| Network discoverability | Persistent localhost/all-interface mode; no automatic firewall changes |
| Agent default workspace | Actual discovered/cloned checkout as first-use browser workspace; respects user override and Clear |
| Docker Desktop / ChromaDB | On a committed app install or confirmed manual model selection, installs Docker Desktop through WinGet if missing, starts it if possible, and starts the upstream `chromadb` Compose service; WSL2/virtualization/reboot or user setup may be required |
| Qwen tool/MCP focus | Guarded V4 source patch with backup; rerunnable; focuses explicit tools and `/skill` / UI-expanded skill requests, suppresses unrelated browser MCP schemas, and withholds the unsafe browser code runner unless browser scripting is explicit |
| Local chat models | Ollama install/start/pull/sync and manual text catalog; native-tool endpoint alias repair |
| Photo/video/audio catalog | Browse and download curated Hugging Face snapshots; **inference runtime is separate** |
| Manual selection | Choose and confirm before any model installation; Tab switches model families, 1–5 filter types |
| Hugging Face token | Hidden entry, encrypted at rest for current Windows user |
| Favorite skills | Real local executable imported skills with `SKILL.md` + runner (`run.py`) for Office, photo, video, scripting and transcription; dependencies are installed/repaired where supported |
| Skill fixer | Declared dependency repair **plus executable-skill native-tool metadata repair**; maps common `allowed-tools` aliases and infers `bash` for local runners without inventing MCP dependencies |
| MCP / FreeMCP | Repairs the Odysseus MCP SDK when the checked-out built-ins still require MCP 1.x, caches Playwright MCP, syncs the machine-readable public registry used by `freemcp.space`, and provides health/search helpers without requiring the currently-unavailable beta CLI |
| Hardware | Adapter display; Ollama is the practical native local-model path |
| vLLM / SGLang / ROCm | **Not native Windows installation targets**; use Linux or WSL2 where supported |
| Desert Ant Labs | Windows SDK exists, but no Windows CLI installer is bundled here |

Native Windows Odysseus uses **Python 3.11+**; Git for Windows supplies Bash for some upstream Cookbook tasks. WinGet helps install Git, Python, Ollama and supported prerequisites. Windows antivirus, driver versions, permissions and individual upstream features may require manual intervention. **This companion has not been validated end-to-end on a Windows host; treat it as an initial Windows edition, not a feature-identical port of the Linux script.**

## Same-chat continuity and Cookbook reliability

### Same-chat continuity (conversation history)

If a follow-up in the **same visible chat** behaves as though it were a brand-new conversation, that is different from Odysseus's cross-chat persistent Memory feature. An upstream session-lifecycle bug has previously allowed background auto-sort/cleanup to delete a newly created active session before the next turn; the browser can then keep a stale session id and the next chat request returns `404`, making consecutive messages look like unrelated chats.

Zarzysseus now installs a guarded **same-chat continuity** compatibility patch on supported install/start paths. On the affected source layout it prevents the immediate `session_created` housekeeping trigger from deleting the just-created chat before turn two. The patch is idempotent, Python-compiles the modified source before replacement, writes a backup under `data/local/patch-backups/`, and leaves the file unchanged when the expected upstream layout is not present. This is specifically about retaining the current chat/session history; it does not manufacture long-term memories or merge separate chats.

Repair or check it explicitly:

```bash
./zarzysseus.sh chat-continuity-fix
./zarzysseus.sh chat-continuity-fix status
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 chat-continuity-fix
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 chat-continuity-fix status
```

### Cookbook reliability

Cookbook now receives a Zarzysseus reliability bridge instead of requiring the user to abandon Cookbook and run model commands manually. On Linux, the managed Odysseus service prepends a local `data/local/cookbook-bin` shim to `PATH`; Cookbook Hugging Face downloads therefore use a resumable retry wrapper around the same Odysseus-venv `hf` command, with the Zarzysseus Hugging Face cache/timeout policy. On Windows, the managed process receives the equivalent local `hf.cmd` retry shim. These repairs **do not call the full operating-system updater**.

Zarzysseus also guards an affected Cookbook backend status path so conclusive runner markers such as `DOWNLOAD_OK` / `DOWNLOAD_FAILED` are trusted before cache probes. This addresses the upstream failure mode where a completed tmux download could be reported as `stopped` after its pane disappeared, particularly with custom download directories or Ollama tasks. Existing SAM/`segment_anything` Cookbook compatibility repairs remain included. If upstream changes or already fixes the relevant code shape, the guarded patch skips it rather than forcing a replacement.

Repair or check Cookbook explicitly:

```bash
./zarzysseus.sh cookbook-fix
./zarzysseus.sh cookbook-fix status
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 cookbook-fix
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 cookbook-fix status
```

Both repairs are safe to rerun. Supported full install/update and managed start/restart paths also check/apply them automatically unless `ZARZYSSEUS_CHAT_CONTINUITY_GUARD=0` or `ZARZYSSEUS_COOKBOOK_FIXES=0` is set.

## MCP runtime, built-ins, and FreeMCP

Odysseus already contains an MCP client/manager and built-in MCP servers. The Python built-ins include memory, RAG, image generation and email, while the browser integration is an `npx`-launched Playwright MCP server. Seeing a qualified tool such as `mcp__builtin_browser__browser_network_requests` therefore means **MCP is present**; it does not mean the model chose the correct tool.

Zarzysseus now adds a repeatable MCP preflight on both Linux and Windows:

- Detect the MCP SDK version in the Odysseus venv. While the checked-out built-in servers still use the MCP 1.x `@server.list_tools()` / `@server.call_tool()` API, Zarzysseus repairs a missing/incompatible install with `mcp<2` (see upstream issue [#6165](https://github.com/odysseus-dev/odysseus/issues/6165)). If a future upstream checkout no longer contains that legacy API shape, the forced `<2` pin is not applied.
- Install/cache Node.js + `@playwright/mcp` when needed so the built-in browser MCP can start reliably.
- Sync the **[public machine-readable registry used by `freemcp.space`](https://github.com/Appnova-EU-OU/awesome-remote-mcp-servers)** into `data/local/freemcp-registry`. The registry repository states that its JSON entries are automatically synced to `freemcp.space`, so Zarzysseus can search them locally without modifying Odysseus's Python environment.
- Upgrade the guarded Qwen routing patch to **V4**. Explicit `/skill` requests still receive the skill's declared toolsets. Ordinary Qwen requests that do not ask for browser interaction do not receive the large built-in browser MCP schema set, and `browser_run_code_unsafe` is withheld unless the user explicitly asks for browser scripting/automation. This targets the class of failure where a coding request was diverted into an unrelated Playwright MCP action; upstream has also documented browser MCP tool crowding in issue [#5763](https://github.com/odysseus-dev/odysseus/issues/5763).

> **FreeMCP is a third-party MCP registry/deployment service, not the official Model Context Protocol project or official MCP Registry.** Its CLI documentation currently advertises `pip install freemcp-cli`, but that package can return `No matching distribution found` from PyPI. Zarzysseus therefore treats the CLI as optional and uses the public registry repository for discovery. It does **not** create a FreeMCP account, log in, deploy a server, trust a server, forward credentials, or register a remote server automatically. Review any third-party MCP server's code, permissions and network access before connecting it to Odysseus.

### Linux MCP commands

```bash
./zarzysseus.sh mcp-setup
./zarzysseus.sh mcp-health
./zarzysseus.sh freemcp-status
./zarzysseus.sh freemcp-search 'spreadsheet'
./zarzysseus.sh freemcp-login
```

### Windows MCP commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 mcp-setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 mcp-health
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 freemcp-status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 freemcp-search 'spreadsheet'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 freemcp-login
```

If an older Zarzysseus build prints `ERROR: Could not find a version that satisfies the requirement freemcp-cli`, rerun with the current installer. The corrected implementation no longer tries to force-install that unavailable PyPI package; `freemcp-setup` now clones/updates the public registry cache and `freemcp-search` searches the cached JSON entries locally.

The normal full/native install also attempts the MCP SDK compatibility check, browser MCP cache and FreeMCP registry sync automatically. All of these operations are safe to rerun. A missing/unpublished `freemcp-cli` package no longer aborts MCP setup. Registry search works without authentication; account login and remote deployment remain explicit user actions on `freemcp.space` unless a compatible CLI becomes available.

## Executable skills and native tool routing

Odysseus skills are more than prompt text: an executable skill also needs the native tools required to run its procedure to be available to the Agent. In the upstream Agent loop, a matched skill's declared `requires_toolsets` is folded into the relevant tool set; simply placing `run.py` beside `SKILL.md` does not by itself guarantee that `bash` (or another native tool) will be offered. Zarzysseus repairs that metadata for imported executable skills and preserves explicit declarations. See the upstream [`agent_loop.py`](https://github.com/odysseus-dev/odysseus/blob/dev/src/agent_loop.py) for the relevant tool-selection path.

Zarzysseus now handles executable skills on **Linux and Windows** as follows:

- A skill with `run.py`, `run.sh`, `run.bash`, `run.ps1`, `runner.py`, `runner.sh`, or a local `scripts` / `bin` / `tools` payload is treated as executable and gets `bash` in `requires_toolsets` when it is missing.
- Common Agent Skills `allowed-tools` names are mapped to Odysseus native equivalents (`bash`, `python`, `read_file`, `write_file`, `edit_file`, `glob`, `grep`, `web_search`, `web_fetch`, `ask_user`). Existing explicit `requires_toolsets` values are preserved.
- Zarzysseus **does not invent MCP requirements** for a local runner. A browser/email/provider MCP is kept only when the skill itself genuinely declares or needs it.
- The built-in Fave Office/photo/video/scripting/transcription skills are installed as real local runners, not prompt-only templates. Their instructions explicitly tell the Agent to execute the checked runner and verify the requested output instead of merely writing a plan.
- The guarded Qwen V4 focus patch recognizes both a direct `/skill-name ...` invocation **and Odysseus's UI-expanded `--- BEGIN SKILL ---` form**. On the first Qwen round it narrows the supplied schemas to that skill's declared native tools, preventing unrelated browser/MCP schemas from crowding an explicit local skill request.
- Normal Odysseus approval, tool policy, disabled-tool and security checks still apply. The patch does not bypass permission gates and does not guarantee that every third-party model or malformed skill will execute successfully. Prompt-only skills remain prompt-only, and provider-backed skills still require their provider authentication.

For an older installation, repair the imported skill metadata and upgrade the Qwen V4 focus patch at any time:

```bash
./zarzysseus.sh skills-runtime-fix
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 skills-runtime-fix
```

The operation is designed to be rerunnable. Linux **Fix Selected / Fix All Skills** and Windows **Fix All Skills** also perform this runtime-routing repair as part of their finalization.

## Odysseus integration fixes and diagnostics

The following are **Zarzysseus compatibility fixes for issues reproduced against a local Odysseus checkout**. They are not claims that these changes have been merged into, or verified across every release of, the original [odysseus-dev/odysseus](https://github.com/odysseus-dev/odysseus) repository. Upstream versions may change the files and APIs that these integrations target.

| Observed behavior in the upstream checkout | Zarzysseus response | Status / scope |
| --- | --- | --- |
| Same visible chat behaves like a new chat on the next turn because the newly created session is removed by immediate background cleanup | Guard the vulnerable `session_created` housekeeping trigger so the active session survives long enough for normal multi-turn history | Targets the session-deletion/404 failure mode reported upstream; this is **same-chat context**, not cross-chat persistent Memory. The patch is guarded, backed up and skipped when its expected source layout is absent. |
| Cookbook finishes a model download but later reports it `stopped` after the tmux session disappears | Put Zarzysseus's retrying `hf` shim in Cookbook's runtime `PATH` and trust conclusive `DOWNLOAD_OK` / `DOWNLOAD_FAILED` markers before cache probes on the affected backend layout | Rerunnable and does **not** invoke the full OS updater; especially useful for resumable HF downloads, custom download locations, and tasks whose tmux pane has already exited. |
| Agent's semantic tool index and VectorRAG could not connect to `localhost:8100`; `ask_teacher` was not retrieved during fallback keyword selection | Start **the checkout's existing `chromadb` Docker Compose service**, wait for `/api/v2/heartbeat`, then allow Odysseus to initialize FastEmbed/tool index | ChromaDB connectivity and `ask_teacher` discovery were verified on the reported Linux setup; both scripts now offer the existing-service startup, **installing Docker on committed install/model-selection actions when missing; never just on TUI launch**. |
| A second Ollama route, `http://localhost:11434/v1`, had `ModelEndpoint.supports_tools=None`; Qwen got `native_tools=False`, `tools_sent=0` despite Ollama advertising tools | Reconcile only verified local Ollama `/v1` aliases on port `11434`; set `supports_tools` from the installer option and refresh the Ollama model inventory | Linux retest showed Qwen `native_tools=True`; Windows uses the equivalent database reconciliation, not yet end-to-end validated on Windows. Other backends/ports are left alone. |
| An imported executable skill was injected into the prompt but Qwen only wrote a plan, then selected an unrelated MCP/browser tool instead of running the skill's local command | Repair/import `requires_toolsets`, map common `allowed-tools` aliases, infer `bash` for verified local runners, and make Fave skills real executable runners | Targets the missing native-tool reachability that caused local skills to behave like prompt-only instructions. Zarzysseus does **not** invent MCP dependencies; provider-backed skills still need their real provider/tooling. |
| Fresh/native Odysseus pulls MCP 2.x while built-in Python servers still use the MCP 1.x decorator API | Detect the source API shape and pin `mcp<2` only while that compatibility requirement exists | Prevents Memory/RAG/Image/Email MCP subprocesses from disappearing after an incompatible SDK upgrade without permanently blocking a future upstream MCP 2 migration. |
| Qwen receives dozens of Playwright MCP schemas for an unrelated coding request and chooses `browser_network_requests` or `browser_run_code_unsafe` | Qwen MCP routing guard V4 hides browser MCP schemas unless browser intent is present and hides the unsafe code runner unless browser scripting is explicit | Keeps MCP available for real browser tasks and MCP-backed skills while reducing unrelated tool hijacking. |
| Need more MCP servers than the built-ins | Sync/search the machine-readable `Appnova-EU-OU/awesome-remote-mcp-servers` registry that is automatically mirrored to `freemcp.space` | Avoids depending on the currently-unpublished beta `freemcp-cli`; account login, server deployment/trust and Odysseus registration remain explicit user actions. |
| Qwen generated prose instead of an actual call under the larger Agent request, although direct Ollama streaming and non-streaming calls worked | Guarded **Qwen explicit-tool + executable-skill + MCP routing focus V4** narrows first-round schemas when the user explicitly names a tool, invokes `/skill-name`, or the UI expands that request into a `BEGIN SKILL` block | Automatically attempted during supported full install/update and executable-skill repair/install (unless disabled), and rerunnable manually. It does not force every model to call a tool, automatically approve execution, or bypass security; test a real skill/tool execution. |
| The Agent workspace might be empty even when Odysseus's service starts in the cloned folder | Make the **actual discovered/cloned checkout** the browser's *first-use Agent workspace* | Existing browser selections and deliberate Clear actions remain authoritative. The source patch is guarded and backed up. Workspaces are browser-local, not a global server setting. |
| Session auto-naming/memory extraction still tried the unavailable `127.0.0.1:8000` route despite global utility defaults pointing at Ollama | Expose the active **global** utility/default/teacher settings in `tool-health`, without overwriting a user-specific/session override | **Not resolved** by the above patches; diagnose the actual per-user/session route before changing models or removing vLLM endpoints. |
| Ollama `/v1/embeddings` returned 404 | Leave Odysseus's working local FastEmbed fallback available | FastEmbed successfully indexed built-in and MCP tools on the reported Linux setup; this warning alone does not justify downloading a separate embedding model. |

**Local source changes and updates:** Workspace defaulting edits `static/js/workspace.js` during supported install/start paths; Qwen explicit-tool / executable-skill / MCP routing focus V4 edits `src/agent_loop.py`; the same-chat compatibility guard can edit `routes/session_routes.py`; and the Cookbook completed-download guard can edit `routes/cookbook_routes.py`. Guarded source patches write backups under `data/local/patch-backups/` and refuse unexpected upstream source layouts instead of applying an unsafe replacement. Tracked changes can make the installer's conservative Git fast-forward updater skip an update; reconcile local changes with upstream rather than resetting them blindly. Back up your checkout before replacing or editing it manually.

### Linux: repair and verify

```bash
cd ~/odysseus  # or your actual discovered/PROJECT_DIR checkout
./zarzysseus.sh docker-setup  # explicit/repeatable Docker + Compose + ChromaDB repair
./zarzysseus.sh chromadb-start
./zarzysseus.sh ollama-sync
./zarzysseus.sh workspace-default
./zarzysseus.sh workspace-default status
./zarzysseus.sh skills-runtime-fix        # executable-skill metadata + Qwen /skill focus
./zarzysseus.sh agent-tool-focus-install  # explicit rerun/upgrade of the guarded focus patch
./zarzysseus.sh chat-continuity-fix        # preserve same-chat follow-up context on affected source layouts
./zarzysseus.sh cookbook-fix               # retry/status repair; no full OS update
./zarzysseus.sh system-auto-update status  # Linux-only persistent full-OS-update toggle
./zarzysseus.sh tool-health
```

The Linux installer starts the existing ChromaDB Compose service during supported install/start/restart paths when Docker Compose is available; committed install/model selections also provision Docker on supported distros if it is missing. Full install/update and executable-skill install/repair also attempt the skill runtime metadata repair and guarded Qwen V4 focus patch. Full Linux OS upgrades additionally obey the persistent **AUTO FULL OS UPDATE** toggle; turning it off does not block required dependency-package installs. Same-chat continuity and Cookbook reliability repairs are also checked on supported install/start/restart paths. `CHROMADB_AUTO_START=0`, `ZARZYSSEUS_DEFAULT_WORKSPACE=0`, `OLLAMA_SUPPORTS_TOOLS=0`, and `ZARZYSSEUS_QWEN_TOOL_FOCUS=0` disable their corresponding behaviors. An ordinary `ollama-sync` alone does not patch upstream source.

### Windows: repair and verify

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 workspace-default
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 workspace-default status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 docker-setup  # explicit/repeatable Docker Desktop + ChromaDB repair
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 chromadb-start
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 ollama-sync
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 skills-runtime-fix       # executable-skill metadata + Qwen /skill focus
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 tool-health
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 agent-tool-focus-install  # explicit rerun/upgrade
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 chat-continuity-fix       # same-chat session guard
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 cookbook-fix              # retry/status repair; no Windows OS upgrade
```

The Windows edition now **installs Docker Desktop during committed app installation or confirmed manual model selection** when Docker is missing (WinGet/admin/WSL 2 prerequisites apply); `chromadb-start` alone does not install it, while `docker-setup` explicitly does. Full install/update and Fave/Fix-All skill flows also repair executable-skill routing metadata and install/upgrade the guarded Qwen skill-focus patch unless disabled. Install/start also checks the guarded same-chat continuity and Cookbook reliability repairs. Windows still does **not** run a full operating-system upgrade; only required prerequisites may be installed/updated. The existing upstream `chromadb` service must be defined. `ollama-sync` requires a responding local Ollama API and an installed Odysseus Python environment. The Windows implementation deliberately preserves an existing non-Ollama default endpoint. Native Windows vLLM/SGLang/ROCm and GPU tooling remain outside its supported native installation path. These Windows compatibility additions have been source-reviewed but **not tested on a live Windows machine**.

### Confirm a tool was actually executed

A model's final answer alone is not proof. In Agent Mode, explicitly request an available tool (for example, `Call get_workspace now`) and inspect the Odysseus tool-execution UI/logs for a native tool call and its result. An endpoint flag of `True` and `native_tools=True` only mean the model was **offered** schemas; a valid direct Ollama call does not guarantee that the full Agent request invokes one. Tool approval and security rules still apply.

## Requirements

- Linux with a supported package manager **or** Windows 10/11 with PowerShell 5.1+ and preferably WinGet
- Internet connection for initial source, dependency and model downloads
- Disk, RAM and (where needed) GPU resources appropriate for selected models
- Appropriate permissions for package installation; third-party accounts require their own authorization

Review the installer's fit, size, and health readouts before choosing large models. Parameter counts and resource estimates are planning information, not measured guarantees.

## Upstream

[odysseus-dev/odysseus](https://github.com/odysseus-dev/odysseus)

Zarzysseus is an independently maintained installer and management toolkit built around Odysseus. For the upstream native Windows setup instructions, see [Odysseus's setup guide](https://github.com/odysseus-dev/odysseus/blob/dev/website/setup.md).

**Enjoying Zarzysseus?**

**A ⭐ on [the project](https://github.com/zarzorr69/zarzyssues) would mean a lot — thank you for supporting it!**
