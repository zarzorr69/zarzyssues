# Zarzysseus

An interactive AI installation and service-management toolkit for **Odysseus native Linux and Windows installs**, with my own custom favorite models and skills available for install under `Fave` selections.

Zarzysseus is a separate installer and management TUI for the upstream [Odysseus project](https://github.com/odysseus-dev/odysseus). It helps discover an existing checkout, install the native application, browse models, install skills, and repair supported dependencies. **The Linux and Windows editions do not yet have identical feature coverage**; see [Windows support](#windows-support) below.

## Glossary

A quick reference for terms used throughout this README and in the Zarzysseus installers.

| Term | Meaning in Zarzysseus |
| --- | --- |
| **Zarzysseus** | This independent Linux Bash / Windows PowerShell installer and management toolkit for Odysseus. |
| **Odysseus / upstream** | The application installed and managed by Zarzysseus; *upstream* means the original `odysseus-dev/odysseus` repository, not this installer. |
| **Checkout / `PROJECT_DIR`** | The actual local directory where the Odysseus Git repository is cloned or found; the installer does not have to use `~/odysseus`. |
| **TUI** | Text-based user interface: the interactive terminal menu. Opening or browsing it does not itself authorize an installation. |
| **Full stack / committed installation** | An install/update or confirmed model selection that initiates setup; this is when missing Docker is provisioned on supported systems. |
| **Normal / L.P.S. / Fave / auto-fit** | Model selections: ordinary hardware targets, Low Power Spec, curated favorites, and an installer-estimated hardware match, respectively. A fit estimate is not a measured performance guarantee. |
| **Ollama** | Local model server used for downloading and running supported chat models; separate from the Odysseus web server. |
| **Model / provider / endpoint** | The chosen AI model, the service hosting it, and the URL/configuration Odysseus uses to reach it. A model can be listed yet have a misconfigured endpoint. |
| **Native tool calling / `supports_tools`** | Structured function requests sent by a model to Odysseus. `supports_tools=True` permits schemas on a matching endpoint; it does **not** prove the model invoked or completed a tool. |
| **Agent Mode / tool / skill** | Agent Mode can run registered actions (*tools*); *skills* are reusable workflows or capabilities that may need tools, dependencies, or authorization. |
| **`ask_teacher` / teacher model** | An agent tool that delegates a question to another configured model. The main chat model and teacher model can be different. |
| **Utility model** | A model used for background tasks such as chat naming; its route can differ from the active chat model. |
| **Agent workspace / default workspace** | The directory the Agent uses for file operations; Zarzysseus initially proposes the actual checkout, while preserving a user's chosen or cleared workspace. This is distinct from the service working directory. |
| **Docker Engine / Docker Desktop / Compose** | Container runtime on Linux, desktop-managed runtime on Windows, and the configuration/command used to launch Odysseus's existing containers. Docker installation may require permissions, WSL 2, or a reboot. |
| **ChromaDB / VectorRAG / tool index** | The vector database, retrieval subsystem, and searchable tool catalog. ChromaDB is started from the checkout's existing `chromadb` Compose service when available. |
| **Embedding / FastEmbed** | Converting text into vectors for search; FastEmbed is the local fallback observed working when the Ollama-compatible embeddings endpoint returned 404. |
| **Hugging Face / HF token** | Model hosting service and an optional access credential for private or gated downloads; a token alone does not grant gated-repository approval. |
| **ROCm / CUDA / XPU / CPU** | AMD, NVIDIA, Intel, and processor execution paths, respectively. Available backends and drivers vary by platform. |
| **Localhost / LAN / `0.0.0.0`** | Loopback-only access, local-network access, and a server bind address for all interfaces. `0.0.0.0` is **not** a browser URL. |
| **Guarded patch / repair / health check** | A source modification that checks expected file structure and saves a backup; a repeatable corrective action; and a diagnostic check. A successful check does not guarantee every model or skill will run. |

## Recommended first-time setup: Hugging Face (Linux **and** Windows)

**Hugging Face sign-in is recommended for either installer**, especially when downloading gated or private models. Public models often work without a token. A token alone does not grant gated-model access: open the model page and accept its terms or request access if required.

1. Create or sign in to your account at [huggingface.co](https://huggingface.co/).
2. Open **[Settings → Access Tokens](https://huggingface.co/settings/tokens)** and create a **Read** token, or a fine-grained token with read access to the specific repositories you want. Do not use a write token just for model downloads.
3. Copy the token privately. **Do not paste it into GitHub, your README, screenshots, chat, or a shared shell command.**
4. **Linux:** launch `./zarzysseus.sh`, open **Hugging Face / Model Files → Set / Inspect / Clear HF Token**, and paste the token when prompted (input is hidden). Or use `./zarzysseus.sh hf-token` after native stack installation; check it with `./zarzysseus.sh hf-token status`.
5. **Windows:** launch `zarzysseus.ps1`, choose **Hugging Face setup (recommended)**, and paste the token at the hidden prompt. Check it with `powershell -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 hf-token-status`.

Windows stores the Zarzysseus token encrypted for the current Windows user. On Linux, the installer persists the token in the Odysseus configuration with restrictive file permissions; keep your machine and configuration files private. You can clear a Zarzysseus-managed token in either TUI. Other Hugging Face tools may store separate credentials.

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

### Linux features

- Terminal-size-aware installation and service-management TUI
- Existing Odysseus checkout discovery and launch-time upstream Git check
- AMD/ROCm, NVIDIA/CUDA, Intel/XPU and CPU detection and supported repair paths
- Normal, L.P.S. (Low Power Spec), and Desert Ant Labs model groups
- Text, photo, video, and audio browsers; auto-fit modes; manual batch selection
- Favorite model and skill options
- Skill health checks and selected-skill / Fix All dependency repair
- Provider login handoff where supported
- Persistent localhost/LAN network discoverability controls
- Docker Engine + Compose v2 install-time preflight on supported Linux package managers; existing ChromaDB service startup (without installing Docker merely on TUI launch)
- ChromaDB startup/heartbeat and Ollama native-tool endpoint alias repair
- First-use Agent workspace set to the actual cloned/discovered checkout
- Tool health reporting and an opt-in guarded Qwen explicit-tool focus patch

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
| Network discoverability | Persistent localhost/all-interface mode; no automatic firewall changes |
| Agent default workspace | Actual discovered/cloned checkout as first-use browser workspace; respects user override and Clear |
| Docker Desktop / ChromaDB | On a committed app install or confirmed manual model selection, installs Docker Desktop through WinGet if missing, starts it if possible, and starts the upstream `chromadb` Compose service; WSL2/virtualization/reboot or user setup may be required |
| Qwen tool focus | Explicit opt-in, guarded source patch with backup; not a universal tool-execution guarantee |
| Local chat models | Ollama install/start/pull/sync and manual text catalog; native-tool endpoint alias repair |
| Photo/video/audio catalog | Browse and download curated Hugging Face snapshots; **inference runtime is separate** |
| Manual selection | Choose and confirm before any model installation; Tab switches model families, 1–5 filter types |
| Hugging Face token | Hidden entry, encrypted at rest for current Windows user |
| Favorite skills | Local starter templates and Python prerequisites; app import/registration may need manual setup |
| Skill fixer | Declared `requirements.txt` / `package.json` dependencies; not a guarantee for undocumented requirements |
| Hardware | Adapter display; Ollama is the practical native local-model path |
| vLLM / SGLang / ROCm | **Not native Windows installation targets**; use Linux or WSL2 where supported |
| Desert Ant Labs | Windows SDK exists, but no Windows CLI installer is bundled here |

Native Windows Odysseus uses **Python 3.11+**; Git for Windows supplies Bash for some upstream Cookbook tasks. WinGet helps install Git, Python, Ollama and supported prerequisites. Windows antivirus, driver versions, permissions and individual upstream features may require manual intervention. **This companion has not been validated end-to-end on a Windows host; treat it as an initial Windows edition, not a feature-identical port of the Linux script.**

## Odysseus integration fixes and diagnostics

The following are **Zarzysseus compatibility fixes for issues reproduced against a local Odysseus checkout**. They are not claims that these changes have been merged into, or verified across every release of, the original [odysseus-dev/odysseus](https://github.com/odysseus-dev/odysseus) repository. Upstream versions may change the files and APIs that these integrations target.

| Observed behavior in the upstream checkout | Zarzysseus response | Status / scope |
| --- | --- | --- |
| Agent's semantic tool index and VectorRAG could not connect to `localhost:8100`; `ask_teacher` was not retrieved during fallback keyword selection | Start **the checkout's existing `chromadb` Docker Compose service**, wait for `/api/v2/heartbeat`, then allow Odysseus to initialize FastEmbed/tool index | ChromaDB connectivity and `ask_teacher` discovery were verified on the reported Linux setup; both scripts now offer the existing-service startup, **installing Docker on committed install/model-selection actions when missing; never just on TUI launch**. |
| A second Ollama route, `http://localhost:11434/v1`, had `ModelEndpoint.supports_tools=None`; Qwen got `native_tools=False`, `tools_sent=0` despite Ollama advertising tools | Reconcile only verified local Ollama `/v1` aliases on port `11434`; set `supports_tools` from the installer option and refresh the Ollama model inventory | Linux retest showed Qwen `native_tools=True`; Windows uses the equivalent database reconciliation, not yet end-to-end validated on Windows. Other backends/ports are left alone. |
| Qwen generated prose instead of an actual call under the larger Agent request, although direct Ollama streaming and non-streaming calls worked | Optional **Qwen explicit-tool focus** patch narrows the *first-round supplied schemas* when the user explicitly names an already available tool | An integration workaround, **not a verified universal fix**. It does not force invocation, automatically retry, bypass approvals, or improve unrelated prompts. Run the opt-in patch command and test a real tool execution. |
| The Agent workspace might be empty even when Odysseus's service starts in the cloned folder | Make the **actual discovered/cloned checkout** the browser's *first-use Agent workspace* | Existing browser selections and deliberate Clear actions remain authoritative. The source patch is guarded and backed up. Workspaces are browser-local, not a global server setting. |
| Session auto-naming/memory extraction still tried the unavailable `127.0.0.1:8000` route despite global utility defaults pointing at Ollama | Expose the active **global** utility/default/teacher settings in `tool-health`, without overwriting a user-specific/session override | **Not resolved** by the above patches; diagnose the actual per-user/session route before changing models or removing vLLM endpoints. |
| Ollama `/v1/embeddings` returned 404 | Leave Odysseus's working local FastEmbed fallback available | FastEmbed successfully indexed built-in and MCP tools on the reported Linux setup; this warning alone does not justify downloading a separate embedding model. |

**Local source changes and updates:** Workspace defaulting edits `static/js/workspace.js` during supported install/start paths, and explicit Qwen tool focus edits `src/agent_loop.py`. Both write backups under `data/local/patch-backups/` and refuse unexpected upstream source layouts instead of applying an unsafe replacement. Tracked changes can make the installer's conservative Git fast-forward updater skip an update; reconcile local changes with upstream rather than resetting them blindly. Back up your checkout before replacing or editing it manually.

### Linux: repair and verify

```bash
cd ~/odysseus  # or your actual discovered/PROJECT_DIR checkout
./zarzysseus.sh docker-setup  # explicit/repeatable Docker + Compose + ChromaDB repair
./zarzysseus.sh chromadb-start
./zarzysseus.sh ollama-sync
./zarzysseus.sh workspace-default
./zarzysseus.sh workspace-default status
./zarzysseus.sh agent-tool-focus-install   # optional; guarded local Qwen patch
./zarzysseus.sh tool-health
```

The Linux installer starts the existing ChromaDB Compose service during supported install/start/restart paths when Docker Compose is available; committed install/model selections also provision Docker on supported distros if it is missing. `CHROMADB_AUTO_START=0`, `ZARZYSSEUS_DEFAULT_WORKSPACE=0`, `OLLAMA_SUPPORTS_TOOLS=0`, and `ZARZYSSEUS_QWEN_TOOL_FOCUS=0` disable their corresponding behaviors. The Qwen source patch is **never silently enabled merely by syncing Ollama**.

### Windows: repair and verify

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 workspace-default
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 workspace-default status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 docker-setup  # explicit/repeatable Docker Desktop + ChromaDB repair
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 chromadb-start
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 ollama-sync
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 tool-health
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 agent-tool-focus-install  # optional; guarded local Qwen patch
```

The Windows edition now **installs Docker Desktop during committed app installation or confirmed manual model selection** when Docker is missing (WinGet/admin/WSL 2 prerequisites apply); `chromadb-start` alone does not install it, while `docker-setup` explicitly does. The existing upstream `chromadb` service must be defined. `ollama-sync` requires a responding local Ollama API and an installed Odysseus Python environment. The Windows implementation deliberately preserves an existing non-Ollama default endpoint. Native Windows vLLM/SGLang/ROCm and GPU tooling remain outside its supported native installation path. These Windows compatibility additions have been source-reviewed but **not tested on a live Windows machine**.

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