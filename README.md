# Zarzysseus

An interactive AI installation and service-management toolkit for **Odysseus native Linux and Windows installs**, with my own custom favorite models and skills available for install under `Fave` selections.

Zarzysseus is a separate installer and management TUI for the upstream [Odysseus project](https://github.com/odysseus-dev/odysseus). It helps discover an existing checkout, install the native application, browse models, install skills, and repair supported dependencies. **The Linux and Windows editions do not yet have identical feature coverage**; see [Windows support](#windows-support) below.

## 🧭 Quick links

**New here?** Start with the [first-run checklist](#first-run-checklist). **Something broken?** Jump straight to the [troubleshooting guide](#quick-start-and-troubleshooting).

### 🚀 Install & get running

| Installation | First-time setup |
| :--- | :--- |
| 🐧 **[Linux installation](#linux-installation)** | ✅ **[First-run checklist](#first-run-checklist)** |
| 🪟 **[Windows installation](#windows-installation)** | 🤗 **[Hugging Face setup](#recommended-first-time-setup-hugging-face-linux-and-windows)** |

### 🛠️ Find a fix fast

| Application & models | Agents & integrations |
| :--- | :--- |
| 🚫 [App or web UI won't open](#app-or-web-ui-wont-open) | 🌐 [Browser or screenshots aren't working](#browser-tools-or-screenshots-arent-working) |
| 🦙 [Ollama or models missing](#ollama-or-a-model-is-missing) | 🧩 [Skills or MCP tools missing](#skills-or-mcp-tools-arent-available) |
| 🐳 [Docker / ChromaDB problems](#docker-or-chromadb-isnt-ready) | 💬 [Agent follow-ups lose context](#follow-ups-lose-their-context) |
| 🪟 [Windows setup hurdles](#windows-specific-setup-hurdles) | 🔑 [Hugging Face model / access problems](#recommended-first-time-setup-hugging-face-linux-and-windows) |

**🍳 [Cookbook: one-click Download/Run shows missing GGUF source](#cookbook-one-click-download-and-runtime-routing)**

**📊 [Cookbook: progress bar, status updates and Show logs](#cookbook-clean-live-download-progress-v102)**

**🩺 [Full troubleshooting guide →](#quick-start-and-troubleshooting)** — diagnostics first, repairs only when needed.

<details>
<summary><strong>⚙️ Configuration & integrations</strong> — networking, Docker, skills, MCP, models and more</summary>

| System & environment | Agent & skills |
| :--- | :--- |
| [Network access & security](#network-discoverability-and-security-linux-and-windows) | [MCP & FreeMCP](#mcp-runtime-built-ins-and-freemcp) |
| [Docker & ChromaDB](#docker-and-chromadb-setup-linux-and-windows) | [V9 Skills & MCP Manager](#v9-unified-skill-installation-mcp-consent-and-tool-health) |
| [Linux OS-update toggle](#linux-full-os-update-toggle) | [V10 Skill-Aware Model Advisor](#v10-skill-aware-model-advisor-and-hardware-auto-fit) |
| [Linux distribution support](#linux-distribution-support) | [Skill-declared MCP setup](#skill-declared-mcp-servers) |
| [Windows support](#windows-support) | [Executable skills & tool routing](#executable-skills-and-native-tool-routing) |
| [Ollama vs Hugging Face IDs](#ollama-vs-hugging-face-model-ids) | [Tool-call JSON recovery](#local-model-json-tool-call-recovery) |
| | [Same-chat continuity & Cookbook](#same-chat-continuity-and-cookbook-reliability) |

</details>

<details>
<summary><strong>🔬 Advanced diagnostics</strong> — repair commands, tool execution and requirements</summary>

| Diagnose & repair | Validate |
| :--- | :--- |
| [Agent reliability & browser repairs](#agent-reliability-repair-and-diagnostics-linux-and-windows) | [Verify tool execution](#confirm-a-tool-was-actually-executed) |
| [Odysseus integration diagnostics](#odysseus-integration-fixes-and-diagnostics) | [System requirements](#requirements) |
| [Linux repair commands](#linux-repair-and-verify) | [Windows repair commands](#windows-repair-and-verify) |

</details>

## Quick start and troubleshooting

New to Zarzysseus? Follow the checklist first. If something fails, use the **symptom → diagnosis → fix** links below rather than reinstalling the entire stack. Run commands from the directory containing your downloaded `zarzysseus.sh` or `zarzysseus.ps1` (or use their full paths). All examples assume the standard filenames.

### First-run checklist

1. **Download and open the installer:** follow [Linux installation](#linux-installation) or [Windows installation](#windows-installation). Opening the TUI is not the same as installing Odysseus: choose its **Install / Update** action and confirm the components you actually want.
2. **Let prerequisites finish:** native Python environment, Ollama, and any chosen model downloads need time and disk space. Docker/ChromaDB setup may need additional permissions; Windows Docker Desktop may need WSL 2 setup or a reboot. [Docker details](#docker-and-chromadb-setup-linux-and-windows).
3. **Check the running app and model backend:** on Linux run `./zarzysseus.sh status` and `./zarzysseus.sh ollama-status`; on Windows use the PowerShell examples below. If Ollama is running but no model is installed, choose one using the TUI or the [V10 Model Advisor](#v10-skill-aware-model-advisor-and-hardware-auto-fit). **The advisor recommends models; it does not install or select one automatically.**
4. **Open Odysseus:** on the host, try `http://127.0.0.1:7000` (default port; adjust if changed). For access from another device, read [Network access & security](#network-discoverability-and-security-linux-and-windows) first. Never use `0.0.0.0` as the URL.
5. **Test Agent mode separately:** choose an installed tool-capable model, enable **Agent** mode, and request a harmless action. For browser screenshots, `qwen3-vl:8b` is a **tested** baseline; other models may vary. A tool listed in the UI is not proof that the model executed it. [Live browser test](#live-browser-test-navigation-screenshot-display).
6. **Only when you need skills:** run `skills-doctor` to see what an imported skill needs, then `skills-setup` to **review and approve** declared dependencies/MCP servers. Never approve unknown third-party code or share secrets in logs. [V9 skill setup](#v9-unified-skill-installation-mcp-consent-and-tool-health).

**Minimal read-only checks** (safe to run before any repairs):

```bash
# Linux, from the directory containing zarzysseus.sh
./zarzysseus.sh status
./zarzysseus.sh ollama-status
./zarzysseus.sh mcp-health
./zarzysseus.sh agent-doctor
./zarzysseus.sh skills-doctor
./zarzysseus.sh model-advisor
```

```powershell
# Windows PowerShell, from the directory containing zarzysseus.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 ollama-status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 mcp-health
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 skills-doctor
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 model-advisor
```

### Find the fix for your symptom

| If you see... | First check | Next step |
| --- | --- | --- |
| Installer closes, Odysseus won't start, or the webpage won't load | `status` / user service logs | [App or web UI won't open](#app-or-web-ui-wont-open) |
| `ollama` not found, no models in selector, or model won't answer | `ollama-status`, `ollama list` | [Ollama or a model is missing](#ollama-or-a-model-is-missing) |
| Agent talks about opening a page but doesn't call the browser, or screenshot isn't displayed | `agent-doctor`, `mcp-health`, actual tool events | [Browser tools or screenshots](#browser-tools-or-screenshots-arent-working) |
| A skill shows up but has no usable tools or an MCP server won't connect | `skills-doctor`, `mcp-health` | [Skills or MCP tools](#skills-or-mcp-tools-arent-available) |
| Docker, ChromaDB, or vector-search services are absent | Docker readiness and ChromaDB heartbeat | [Docker or ChromaDB](#docker-or-chromadb-isnt-ready) |
| Agent forgets your previous message in the same conversation | Check you're still in the same Agent chat | [Follow-ups lose context](#follow-ups-lose-their-context) |
| Windows install blocked by PowerShell, WinGet, WSL 2, or reboot prompts | Terminal error + prerequisite status | [Windows-specific hurdles](#windows-specific-setup-hurdles) |
| Hugging Face download says 401/403, gated/private, or model ID not found | Token, granted access and registry | [Hugging Face setup](#recommended-first-time-setup-hugging-face-linux-and-windows) · [Model IDs](#ollama-vs-hugging-face-model-ids) |

### Cookbook clean live download progress (V10.2)

**Symptom:** Cookbook's **Active** panel shows a non-refreshing terminal dump of Hugging Face warnings, reconstruction output, or a changing percentage without a usable progress bar.

**Fix:** Use `./zarzysseus.sh cookbook-fix progress` (Linux), or `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 cookbook-fix progress` (Windows). The repair alters the **Cookbook frontend only**, keeps downloads and status/error reporting unchanged, and retains the V10.1 one-click model routing. Restart Odysseus if the launcher does not do so, then hard-refresh the browser with **Ctrl+Shift+R**.

Afterward, **Active** shows a compact live progress bar. File-completion percentages are labeled *of files*; byte-completion values are used when available. When the backend does not report reliable overall progress, the bar is animated without inventing a percentage. Detailed terminal output is initially collapsed; click **Show logs** only when debugging an error. Download polling remains active while the Active tab is visible, even with logs hidden.

**Check/undo:** `./zarzysseus.sh cookbook-fix status`, or `./zarzysseus.sh cookbook-fix rollback-progress` to restore the prior UI from a SHA-256 checked backup. If Odysseus updated Cookbook's Javascript structure, the guard will refuse the patch rather than guessing. A new download may be needed to exercise the progress UI after restarting; existing download processes are not intentionally interrupted by the patch itself (the launcher may restart Odysseus).

### Cookbook one-click download and runtime routing

**Symptom:** Clicking **Download** in Cookbook's model list shows *No GGUF source is configured*, even though the model fits your VRAM. This is a model-format selection error, not a Hugging Face login issue. Do not search for a random similarly named GGUF repository.

**Inspect before repairing:** `./zarzysseus.sh cookbook-fix status` on Linux, or `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 cookbook-fix status` on Windows.

**Fix the GUI itself:** run `./zarzysseus.sh cookbook-fix` on Linux, or the same Windows launcher with `cookbook-fix`. The V10.1 compatibility guard corrects the native model/quantized-source distinction in Cookbook's **existing** Download and Run buttons, using the catalog's declared GGUF sources when they exist, without forcing users through Direct Download. Restart Odysseus as prompted and hard-refresh the Cookbook page (Ctrl+Shift+R). The repair checks upstream code signatures and refuses unknown layouts; it writes SHA-256-verified backups. Restore with `cookbook-fix rollback-oneclick` if needed.

**Important limitations:** A quantization shown in a hardware-fit table does not prove an actual GGUF exists. For **mistralai/Voxtral-Mini-4B-Realtime-Arabic**, the official weights are native BF16, served as speech recognition through a **vLLM realtime** backend. Cookbook can download those weights with one click using the official repository, but clicking Run still requires a functioning compatible vLLM build and audio extras. It does **not** become a general text chat model. If vLLM is missing or cannot load on your GPU/ROCm install, downloading succeeds but serving cannot; check Cookbook → Dependencies. A compatibility patch must not promise support for every Hugging Face architecture.

**Scope:** source routing, catalog labeling and download behavior. It does not modify the V8 Playwright/browser agent, install unsupported runtimes, silently pull additional models, or bypass access restrictions. The Windows launcher includes the same guarded patch, but the local vLLM runtime is Linux-oriented; using Windows native may require WSL2 or a remote Linux server.

### App or web UI won't open

**Linux — inspect first:**

```bash
./zarzysseus.sh status
systemctl --user status odysseus.service --no-pager
journalctl --user -u odysseus.service -n 80 --no-pager
```

If installed but stopped, run `./zarzysseus.sh start`. The `systemctl`/`journalctl` commands apply to the **managed user service**; if you launch Odysseus manually, read the terminal where you started it instead. The default local address is `http://127.0.0.1:7000`, not port 8000. If using a different computer, see [LAN mode and firewall guidance](#network-discoverability-and-security-linux-and-windows).

**Windows — inspect first:**

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 status
# If installed but stopped:
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 start
```

A logged `Auto-name failed: Cannot reach http://127.0.0.1:8000` concerns an **auxiliary chat naming/utility route**; it does not by itself mean the main `:7000` web server or browser MCP is broken. See [integration diagnostics](#odysseus-integration-fixes-and-diagnostics) before changing the model endpoint.

### Ollama or a model is missing

```bash
./zarzysseus.sh ollama-status  # check API/service
ollama list                   # check downloaded model names (if Ollama CLI is installed)
./zarzysseus.sh model-advisor  # read-only hardware/skill-fit recommendations
```

If Ollama is installed but stopped, run `./zarzysseus.sh ollama-start`. If no suitable model is installed, use the TUI's model browser or explicitly approve a download with `model-advisor-install`. After changing the local model inventory, `./zarzysseus.sh ollama-sync` can refresh Odysseus's Ollama configuration. On Windows, replace `./zarzysseus.sh` with `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1`. An installed model still needs to be **selected in the Odysseus chat**; a V10 model preference doesn't switch it for you. [V10 advisor details](#v10-skill-aware-model-advisor-and-hardware-auto-fit).

### Browser tools or screenshots aren't working

First choose **Agent** mode, verify the built-in browser MCP is enabled, and try a tool-capable vision model for screenshot **interpretation** (the screenshot itself can be captured without vision). On Linux:

```bash
./zarzysseus.sh agent-doctor  # read-only diagnostics
./zarzysseus.sh mcp-health    # inspect MCP/runtime availability
# Only if checks identify a missing/older browser routing repair:
./zarzysseus.sh agent-repair  # modifies guarded source patches; may restart managed service
```

In a new Agent chat, try **“Open https://example.com, take a screenshot, and show it.”** Approve the requested action. Expand the `browser_take_screenshot` tool's process card: **the image may appear there instead of as a standalone assistant attachment**. Check for actual `Tool executed: ...browser_navigate` and `...browser_take_screenshot` success events; a model's reasoning text or an approval dialog alone does not prove execution. Linux logs:

```bash
journalctl --user -u odysseus.service --since '10 minutes ago' --no-pager \
  | grep -Ei 'agent-debug|browser_navigate|browser_take_screenshot|Tool executed|approval|zarzysseus-agent-v[45678]' \
  | tail -n 80
```

If navigation succeeds but the screenshot tool doesn't execute, inspect schema/approval messages. If the screenshot executes but the image is missing, inspect the result and UI rather than reinstalling Playwright. `model-advisor-test` tests **structured call formatting only**, not screenshots or visual understanding. [Browser execution stages](#live-browser-test-navigation-screenshot-display).

### Skills or MCP tools aren't available

```bash
./zarzysseus.sh skills-doctor            # read-only inventory and missing requirements
./zarzysseus.sh mcp-health               # read-only MCP status
./zarzysseus.sh skills-setup             # review + explicitly approve declared setup
```

If `skills-doctor` reports a disabled or unregistered server, check the skill's **explicit MCP declaration**, its command/package and any required credentials. V9 will not infer a server that a skill didn't declare; native-only skills do not require one. A successful handshake is not the same as a successful Agent call—test the skill with a supported tool-capable model. Windows exposes the corresponding `skills-doctor` and `skills-setup` commands through `zarzysseus.ps1` as well. [V9 readiness meanings and approvals](#v9-unified-skill-installation-mcp-consent-and-tool-health).

### Docker or ChromaDB isn't ready

```bash
./zarzysseus.sh status
./zarzysseus.sh chromadb-start  # starts existing Compose service if Docker is available
# Only if Docker/Compose is missing or unconfigured:
./zarzysseus.sh docker-setup    # may install/start Docker and change system setup
```

On Windows use `zarzysseus.ps1 chromadb-start` / `docker-setup` instead. Docker Desktop may need **WSL 2, hardware virtualization, administrator consent, and a reboot** before ChromaDB can start. A Docker install alone does not prove the ChromaDB service is healthy. [Detailed Docker instructions](#docker-and-chromadb-setup-linux-and-windows).

### Follow-ups lose their context

Confirm you're continuing the **same chat**, in **Agent** mode, with the relevant model/tools enabled. If messages in that chat still lose context, the installer offers a guarded continuity repair (and may restart its managed service):

```bash
./zarzysseus.sh chat-continuity-fix status  # inspect
./zarzysseus.sh chat-continuity-fix         # apply guarded fix if needed
```

For Windows use the equivalent `zarzysseus.ps1 chat-continuity-fix` command. This targets a known source-layout/session issue; it **does not guarantee** that every model can continue a multi-step Agent workflow or remember a separate chat. [Continuity limitations](#same-chat-continuity-and-cookbook-reliability).

### Windows-specific setup hurdles

Run the installer in **Windows PowerShell 5.1+**, not by double-clicking the `.ps1`. Use the [download-to-file installation commands](#windows-installation) so the menu keeps terminal input. If WinGet or Git/Python/Ollama is missing, let the **confirmed install** preflight set up supported prerequisites; restart PowerShell afterward if the PATH changes. Docker Desktop may require WSL 2/virtualization and a reboot. The included `-ExecutionPolicy Bypass` applies **only to that invocation**, not system-wide. Windows does not support the full Linux GPU/backend or skills.sh marketplace feature set yet. [Windows feature matrix](#windows-support).

> **Before sharing diagnostics:** remove tokens, private URLs, filenames containing personal data, and contents of browser pages. Read-only commands above are intended to inspect state; setup, repair, download, start and restart commands can modify services, dependencies or Odysseus's guarded source files. Never bypass an Agent tool-approval dialog merely to make a screenshot test pass.

## Agent reliability repair and diagnostics (Linux and Windows)

Zarzysseus adds *guarded compatibility repairs* to Odysseus's Agent tool-routing and browser behavior. These repairs are available from the existing TUI and CLI. **Installing a repair, passing a smoke test, or seeing an approval dialog does not prove that a browser screenshot was captured or shown in chat.**

### How the agent repairs fit together

| Component | Purpose | Limitations |
| --- | --- | --- |
| Qwen explicit-tool focus V4 | Limits irrelevant schemas for explicit tool and `/skill` requests | Helps tool selection; it does not execute tools |
| Agent Reliability V1/V2 | Prevents invented `browser-use` shell commands and focuses normal browser tasks on a small set of real authorized browser tools | Simulated routing tests cannot verify live MCP execution |
| Thinking-only Recovery V3 | Retries once when the first Qwen3-VL browser round produces reasoning but no tool call; reports failure if the retry also fails | An identical large-context retry can fail again |
| Compact Browser Fallback V4 | For a specific reasoning-only browser request containing an explicit HTTP(S) URL, asks the model for a real structured `browser_navigate` call through a compact prompt; after successful navigation, may request `browser_take_screenshot` | Experimental; does not guarantee a screenshot result or inline rendering |
| Approved Browser Continuation V5 | On a matching approved navigation for an explicitly requested screenshot, restores the original screenshot intent and preserves its **existing enabled** browser screenshot tool for the resumed request | Does not bypass approvals, force unrelated actions, or guarantee the frontend displays an image |
| Screenshot Schema Compatibility V8 | Applies explicit, schema-valid safe screenshot options after approved navigation if Playwright requires them | Refuses arbitrary filename/path requirements; inline image rendering remains host-test dependent |
| URL/Workspace Routing V7 | Prevents Odysseus from treating `https://example.com` as a local `/path` and replacing browser MCP tools with the Terminus file/terminal toolset | Fixes tool selection before the model call; no guarantees on screenshot image rendering |
| Explicit Screenshot Continuation V6 | When a Qwen3-VL approval continuation produces reasoning-only output after **successful approved navigation**, queues one user-requested screenshot with default arguments via Odysseus’s original converter, approval gate, and executor | Does not create images itself, approve the tool, override disabled tools, or guarantee inline rendering |

**Execution and security:** The V4 fallback may propose only a browser tool already authorized by Odysseus. Accepted structured calls return to Odysseus's existing converter, execution dispatcher, and user approval checks. It does **not** click approval dialogs, execute untrusted text as shell commands, or grant new permissions. V5 additionally checks that an approved `browser_navigate` URL matches the most recent user-authored request about that URL, that the user asked for a screenshot, and that the screenshot MCP schema is enabled. It then preserves that request through the approval continuation; no new permissions are granted. Neither version is desktop control or a multi-agent framework.

### Linux CLI and TUI

```bash
./zarzysseus.sh agent-repair    # Install/check routing and browser fallbacks; restart managed service
./zarzysseus.sh agent-doctor    # Read-only source and health checks
./zarzysseus.sh agent-smoke     # Simulated routing tests, no live browser calls
./zarzysseus.sh mcp-health      # MCP/runtime status
./zarzysseus.sh agent-rollback  # Restore verified backups; disable automatic reapplication
```

Open **Diagnostics / Tools / Advanced → Agent Diagnostics / Repair / Rollback** in the Linux TUI. Repair checks Node/Playwright MCP and Chromium, and restarts a running Odysseus service managed by Zarzysseus. A manually launched Odysseus process must be restarted separately. Backups are stored under `data/local/patch-backups/`; guarded installers and rollback refuse unexpected source edits or digest mismatches.

### Windows CLI and TUI

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 agent-repair
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 agent-doctor
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 agent-smoke
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 mcp-health
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 agent-rollback
```

Windows exposes the Agent actions directly as main-menu items **23–26**. Its installer may need Node or browser dependencies. **The PowerShell runtime has not been validated end-to-end on a Windows host.**

### Live browser test: navigation, screenshot, display

Use a new **Agent** chat with a tool-capable model such as `qwen3-vl:8b`. First test navigation alone: *“Open https://example.com using `mcp__builtin_browser__browser_navigate`.”* Then, in the same chat and after any necessary approval, ask: *“Use `mcp__builtin_browser__browser_take_screenshot` and show the result here.”*

The stages are separate:

1. **Tool proposed:** Qwen emits a structured tool call; reasoning text saying “I should call…” is not a call.
2. **Approved and executed:** Odysseus may request approval. An approval prompt alone doesn't mean a page opened. Confirm the actual tool result.
3. **Image returned:** The browser tool must return image data; successful navigation only returns page data, not automatically an image.
4. **Rendered by the UI:** Odysseus's agent loop forwards the first returned browser image as the `screenshot` field on a `tool_output` event. A missing inline image can be a screenshot-tool problem **or** a frontend rendering problem; no screenshot can be inferred from a model's description.

For a live failure, inspect the corresponding service run (do not paste passwords or private page content):

```bash
journalctl --user -u odysseus.service --since '20 minutes ago' --no-pager \
  | grep -Ei 'zarzysseus-agent-v8|zarzysseus-agent-v7|zarzysseus-agent-v6|zarzysseus-agent-v5|zarzysseus-agent-v4|browser_navigate|browser_take_screenshot|approval|tool.*start|tool.*output|mcp|error' \
  | tail -n 100
```

If V4 logs **`native proposal accepted; handing to upstream executor`**, that proves only a valid proposed call reached the normal dispatcher. Next verify the tool executed and returned images, then inspect frontend rendering if the tool returned image data but the UI stayed empty. Do not keep reinstalling Playwright or bypassing approval rules simply because the image is missing.

### V8: screenshot parameter-schema compatibility

In the live Qwen3-VL browser test, Odysseus successfully navigated and retained
`mcp__builtin_browser__browser_take_screenshot`, but the V6 continuation logged
`[zarzysseus-agent-v6] screenshot schema requires arguments; refusing default capture`.
V4's separate model proposal also failed. The screenshot tool was **not executed**.

V8 extends the existing V6 continuation after a successful, approved navigation.
It checks the **actual currently offered screenshot JSON schema** and supplies
only recognized required fields with safe values: `type: "png"`, `scale: "css"`,
and `fullPage: false`. It supplies **none** if there are no required fields.
If an unknown, unsupported or incompatible required field exists—including
`filename`—the continuation **fails closed** instead of guessing a path. It
never injects a screenshot if navigation failed or the tool was disabled. The
call uses Odysseus's original converter, approvals and executor.

Importantly, the filename is intentionally omitted: the official Playwright
MCP screenshot behavior returns inline image content when no filename is
provided (unless the server is configured to omit image responses). This
backend repair does **not** guarantee Odysseus renders that image in chat.

After `agent-repair`, look for:

```text
[zarzysseus-agent-v8] queued schema-valid screenshot via upstream executor
Tool executed: mcp: mcp__builtin_browser__browser_take_screenshot -> exit_code=0
```

If the first line appears but no execution follows, inspect tool approval or
MCP execution. If both appear and no image is shown, inspect the browser result
and Odysseus's `tool_output.screenshot` forwarding/rendering. Rollback restores
exact V7 source before the existing V7→V1 chain.

### V7: URL mistaken for a local workspace path

On the CachyOS host, a fresh **Open `https://example.com`, take a screenshot** request still yielded `tools_sent=2` (`web_search`, `web_fetch`) despite the connected browser MCP. The installed upstream workspace detector's file-path expression matched `//example.com` **inside** the URL; with the default Agent workspace set, Odysseus logged `Workspace file/terminal request; using Odysseus Terminus toolset`, overwrote retrieved browser tools, and sent no Playwright schemas to Qwen.

V7 corrects this detection error at the source by removing HTTP(S)/`www.` URLs *only for workspace-path classification*. Real local paths and mixed URL + project-file editing requests still activate Terminus as appropriate. Tool enable/disable settings, plan mode, browser MCP configuration, execution dispatcher, approval prompts and screenshot rendering remain unchanged. It backs up the exact V6 source with checksum-verified rollback. Linux and Windows installers include the fix internally; there is no additional skill or external browser binary to install.

After `agent-repair`, the first live log for a browser-only screenshot request should show real `mcp__builtin_browser__browser_navigate` and `browser_take_screenshot` schemas rather than just `web_search` and `web_fetch`. **This must be verified on the host:** V7's simulated detector tests do not establish live screenshot execution or frontend rendering.

### V5: fixing the post-approval screenshot drop

In a live CachyOS test, V4 generated a valid `browser_navigate` call and Odysseus executed it with `exit_code=0`. When the approval continuation resumed, however, `[agent-debug]` showed `tools_sent=2` with **only** `web_search` and `web_fetch`. The screenshot MCP tool had disappeared before the model could call it.

V5 addresses that exact handoff. It uses the verified approved-navigation URL and the most recent matching user screenshot request to restore the earlier browser intent. It retains `browser_take_screenshot` only when that function is still present in Odysseus's enabled MCP registry and permitted by its current tool policy; the usual tool dispatcher and approval checks remain in control. For Qwen3-VL reasoning-only continuations, V4's compact single-tool fallback can then propose the screenshot action. A successful screenshot capture and inline UI image rendering **still need a live test**.

To inspect the resumed call, check for `[zarzysseus-agent-v5] validated approved browser screenshot continuation`, `[zarzysseus-agent-v5] retained enabled screenshot schema`, and then a `browser_take_screenshot` tool start/output. If the screenshot tool executed but no image appears, inspect the backend tool result's `images` data and the frontend's `tool_output.screenshot` rendering. A successful navigation alone is never proof of an image capture.

### V6: screenshot after successful approved navigation

A live test confirmed V5 preserved the screenshot function (`tools_sent=1` after navigation), but Qwen3-VL again produced reasoning only, and the compact V4 screenshot proposal yielded `no valid native tool proposal returned`. **This was a screenshot selection failure, not a missing Playwright installation.**

V6 addresses exactly that dead end: when the original user expressly asked for a screenshot of the approved URL, the approved navigation succeeded, Qwen3-VL returns reasoning-only text, the screenshot function is still in the current authorized schema list, and its JSON schema requires no arguments, the runtime queues **one** screenshot with `{}` (default browser screenshot arguments). This is a deterministic continuation of the user request, **not a claimed model-generated function call**. The request still passes Odysseus's original tool converter, tool security policy, per-tool approval gate, and MCP executor. Failed navigation, mismatched approval, unavailable/disabled screenshot functions, and unrelated tasks do not trigger it.

Look for `[zarzysseus-agent-v6] queued explicitly requested screenshot via upstream approvals/executor`, followed by an approval prompt (if required) and `Tool executed: mcp: mcp__builtin_browser__browser_take_screenshot`. If the latter succeeds but the image is absent, investigate the MCP result `images` payload and frontend `tool_output.screenshot` rendering separately. **V6 has only been tested against local source and simulated tool states, not yet with a live browser session.**

### Testing evidence and patch history

On the reported CachyOS host, `qwen3-vl:8b` returned real structured calls through Ollama's native and OpenAI-compatible APIs, including streaming; a short isolated call through Odysseus's installed adapter also passed. Yet the full Agent request initially produced **reasoning only / zero tool calls**. V2 narrowed the browser tools to four; V3 retried without recovering; V4 introduced the compact fallback and the first live navigation executed successfully; the approved continuation lost browser schemas. V5 guards that continuation. A later live test confirmed V5 offered the screenshot tool, but the model and V4 compact fallback produced no valid screenshot proposal. V6 adds a tightly scoped explicit screenshot continuation. V7 then fixes a separate upstream regression that misclassifies URLs as workspace paths. **A live V8 test verified browser navigation, screenshot execution (`exit_code=0`), and image display in the screenshot tool's process panel.** Display as a standalone assistant image and cross-model reliability are not yet verified.

The guarded repairs make changes to `src/agent_loop.py` in the detected Odysseus checkout. `agent-rollback` restores V7, V6, V5, V4, V3, V2, and earlier agent repair layers in reverse order, provided their backups and digests match. After rollback, automatic reapplication remains disabled until an explicit repair.

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

### Cookbook reliability without a full OS update

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
./zarzysseus.sh skills-mcp-fix
./zarzysseus.sh tool-json-fix
./zarzysseus.sh freemcp-status
./zarzysseus.sh freemcp-search 'spreadsheet'
./zarzysseus.sh freemcp-login
```

### Windows MCP commands

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 mcp-setup
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 mcp-health
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 skills-mcp-fix
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 tool-json-fix
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 freemcp-status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 freemcp-search 'spreadsheet'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 freemcp-login
```

If an older Zarzysseus build prints `ERROR: Could not find a version that satisfies the requirement freemcp-cli`, rerun with the current installer. The corrected implementation no longer tries to force-install that unavailable PyPI package; `freemcp-setup` now clones/updates the public registry cache and `freemcp-search` searches the cached JSON entries locally.

The normal full/native install also attempts the MCP SDK compatibility check, browser MCP cache, FreeMCP registry sync, compact local-model tool-call recovery, and provisioning of MCP servers explicitly declared by installed skills automatically. All of these operations are safe to rerun. A missing/unpublished `freemcp-cli` package no longer aborts MCP setup. Registry search works without authentication; account login and remote deployment remain explicit user actions on `freemcp.space` unless a compatible CLI becomes available.

## V9: Unified skill installation, MCP consent, and tool health

**V9 builds on the verified V8 browser/screenshot runtime.** The underlying model/tool executor and permission system remain Odysseus's; installing a skill does not make a model *guaranteed* to use that skill. This update adds a unified **health → approve → install/repair → recheck** route for imported Odysseus Agent skills. Skills can work using native tools without any MCP server, and V9 **never invents or installs an unrelated MCP server**.

### What happens to an imported skill

1. Zarzysseus reads `data/skills/imported/<skill>/SKILL.md`, its `requires_toolsets`, supported dependency manifests, and *explicit* `mcpServers` / `mcp_servers` / `mcp-servers` declarations.
2. **Skills Doctor** checks current manifest/toolset metadata and MCP registration without executing the skill or starting third-party MCP code. It distinguishes `unregistered`, `disabled-config`, `enabled-config`, and already-enabled legacy server entries. Python dependencies are checked by installed distribution name; this is **not** a full environment/package-version audit.
3. **Skills Setup** prints a redacted plan (executable name or remote host but never environment values/secret arguments) and requires a typed `YES` before provisioning dependencies and authorizing new declared MCP servers. Approvals are bound to the exact imported-skill folder/server name and SHA-256 digest of that server declaration, saved with user-only permissions under `data/local/zarzysseus-skill-v9-approvals.json`. A changed/new declaration requires review again. Previously enabled MCP entries are retained for compatibility.
4. After approval, supported dependency installers run, native tool metadata is repaired, declared stdio servers are tested by MCP `initialize`/`list_tools`, and the discovered qualified MCP names are bound into `requires_toolsets`. Missing credentials, unsupported commands, unsuccessful handshakes, or disabled servers remain **not ready**. Remote HTTP/SSE entries are registered but still need a live Odysseus connection before their tools are known.
5. The final report shows remaining problems. A *live model tool call* and actual skill runner output must still be tested separately; `configured` is not a successful Agent execution guarantee.

**Linux TUI:** **Skills.sh / Agent Skills → V9: Skills + MCP Health** or **V9: Approve + Provision Skills / MCP**. The existing Linux `skills-install` flow now offers V9 setup after import. Rejecting setup leaves the imported skill in place but does not provision new unapproved MCP servers.

```bash
./zarzysseus.sh skills-doctor                   # Read-only skill inventory
./zarzysseus.sh skills-doctor imported-folder   # Inspect just one imported skill
./zarzysseus.sh skills-setup                    # Review and approve setup for all imported skills
./zarzysseus.sh skills-setup imported-folder    # Approve/setup one imported skill
```

**Windows TUI:** **Skills / Fix All → 5 V9 Health** or **6 V9 Approve + Setup**. The Windows commands audit/repair already imported skills and the existing Fave skills; the Windows edition does not yet provide the full Linux `skills.sh` marketplace/browser installer.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 skills-doctor
powershell -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 skills-setup
```

**Security:** Installing or repairing a third-party skill can execute untrusted `pip`, npm, and MCP package code or contact an external server. Review the skill/source and approve only providers you trust. The normal server startup must not provision *new, unapproved* MCP declarations. For deliberately unattended Linux provisioning after an out-of-band review, `ZARZYSSEUS_SKILL_SETUP_APPROVED=1 ./zarzysseus.sh skills-setup` bypasses only Zarzysseus's installer prompt, **not** Odysseus's runtime tool approvals. Do not set it persistently for untrusted skills. Existing manually configured MCPs remain under Odysseus's own enable/disable settings.

### What V9 does not claim

- It does not synthesize an MCP server for a skill with no declared MCP dependency or magically provide external account credentials.
- It does not prove all third-party tasks work; even with healthy MCP handshakes, the selected model can fail to invoke a tool.
- The Python requirements check is a best-effort distribution presence check, not full dependency/version compatibility testing. Readiness is labeled accordingly.
- No V9 patch is applied to the working browser/screenshot execution code in `src/agent_loop.py`.

## V10: Skill-Aware Model Advisor and hardware auto-fit

V10 extends the V9 Skill/MCP Manager without changing the verified V8
browser-navigation and screenshot runtime. It recommends local **Ollama** text,
code, or vision models based on each *imported* skill’s description/tool names,
your RAM, available dedicated GPU memory when detectable, and the models already
installed in Ollama. Importantly, **model advice is not an automatic download or
chat-model switch**.

### What the advisor checks

- Reads `data/skills/imported/<skill-folder>/SKILL.md` without executing the skill.
  Detects browser screenshots/vision, coding, research, general automation,
  audio and image-generation workloads. Category inference is heuristic.
- Detects system RAM, NVIDIA memory via `nvidia-smi`, AMD/DRM dedicated VRAM
  from supported Linux sysfs devices, or Windows GPU names through CIM. On
  Windows dedicated VRAM may remain **unknown** because CIM’s `AdapterRAM`
  frequently overflows; unknown hardware is never labeled a GPU fit.
- Reads the local Ollama `/api/tags` inventory, prioritizes already-installed
  models, and scores estimated RAM/VRAM fit, approximate quality/size and
  previous **local structured-tool probes**. No marketplace API credentials are
  needed for read-only recommendations.
- A bundled curated shortlist includes `qwen3-vl:2b`, `:4b`, `:8b`, `:30b`,
  `qwen2.5-coder:3b`, `:7b`, `:14b`, `qwen3-coder:30b`, and `llama3.1:8b`.
  The Qwen3-VL 8B browser screenshot flow has been verified during Zarzysseus
  development; **other model/skill pairs are candidates, not verified outcomes**.
- Treats audio transcription and image creation as specialized-backend tasks;
  recommending a text LLM would *not* install an ASR or image generator.
- Estimates model working memory from published approximate download sizes,
  with a separate overhead factor. The estimate is **not benchmarked VRAM use**;
  context window, quantization, multiple loaded models and GPU offload matter.

### Linux CLI and TUI

```bash
./zarzysseus.sh model-advisor                 # general tool-calling models, read-only
./zarzysseus.sh model-advisor <skill-folder>  # hardware-fit recommendations for imported skill
./zarzysseus.sh model-advisor-json <skill-folder>  # JSON for integrations
./zarzysseus.sh model-advisor-test qwen3-vl:8b  # harmless local tool-call proposal probe
./zarzysseus.sh model-advisor-install <skill-folder> [catalog-model-id] # prompt before Ollama pull
./zarzysseus.sh model-advisor-pin <skill-folder> qwen3-vl:8b # explicit advisory preference
./zarzysseus.sh model-advisor-pins           # list stored preferences
```

Open **Skills.sh / Agent Skills → V10: Skill Model Advisor**, **V10: Model Tool-Call
Test**, or **V10: Install a Recommended Model**. After importing a *new* skill
via the Linux CLI/TUI, the installer prints the related V10 recommendation
without downloading anything. `model-advisor-install` asks for confirmation;
`model-advisor-pin` stores a suggestion but **does not force an Odysseus chat
model or silently overwrite user-selected providers**.

### Windows CLI and TUI

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 model-advisor <skill-folder>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 model-advisor-json <skill-folder>
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 model-advisor-test qwen3-vl:8b
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 model-advisor-install qwen3-vl:8b
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 model-advisor-pin skill-folder=qwen3-vl:8b
```

On Windows choose **Skills → V10 Model Advisor / Test / Install**. The Windows
single-argument `model-advisor-install` CLI accepts a skill folder *or* a
catalog model ID; to specify both, use the interactive menu. Existing Windows
native install and skill-discovery limitations from V9 still apply.

### Verification, safety and files

The V10 probe asks an **already installed** Ollama model to return a structured
`diagnostic_ping(value=7)` proposal; it **never executes the tool**. A passing
probe proves tool-call formatting only, *not* a working Odysseus MCP server,
browser screenshot, application controller or multistep agent continuation.
Results are persisted in `data/local/zarzysseus-model-v10-tests.json` and
preferences in `data/local/zarzysseus-model-v10-prefs.json` with current-user
permissions. These files are independent of V9’s MCP consent data.

Only curated, cataloged model IDs can be auto-downloaded. Downloads require
an explicit confirmation, and models conservatively judged unlikely to fit
physical RAM are not automatically selected. On first installation test with
`model-advisor-test`, then run an **actual Odysseus Agent chat** to verify
MCP execution, visual interpretation and the UI. **V10 does not solve separate
same-chat continuation problems.**

Catalog references: [Ollama Qwen3-VL](https://ollama.com/library/qwen3-vl),
[Qwen2.5-Coder](https://ollama.com/library/qwen2.5-coder),
[Qwen3-Coder](https://ollama.com/library/qwen3-coder), and
[Llama 3.1](https://ollama.com/library/llama3.1).

## Skill-declared MCP servers

Zarzysseus now **auto-provisions MCP servers that a skill explicitly declares** in its `SKILL.md` frontmatter through `mcpServers`, `mcp_servers`, or `mcp-servers`. It does not guess a server from a skill name or silently attach a random FreeMCP result: many skills are intentionally local CLI/native-tool skills and have no MCP server at all.

For declared **stdio** servers, Zarzysseus creates a stable Odysseus MCP entry for that skill, prepares a launcher rooted in the skill directory, and performs an MCP initialize/`list_tools` handshake. `npx` declarations are made non-interactive (`-y`), so their package can be downloaded on first provisioning; local Node skills can install their declared `package.json` dependencies, and local Python servers can install a colocated `requirements.txt`. Successfully discovered tools are written back to the imported skill's `requires_toolsets` as their qualified `mcp__<server-id>__<tool>` names, which lets Odysseus expose the correct skill-owned MCP tools when that skill is matched.

Remote HTTP/SSE declarations are registered for Odysseus to connect at runtime. A declaration with a missing required environment variable, an unsafe command string, an executable that cannot be resolved, or a failed MCP handshake is left **disabled** instead of being advertised as ready. Because a third-party MCP stdio server is executable local code, only install skills you trust; automatic provisioning does not bypass Odysseus's normal MCP/tool permission and approval checks.

This runs automatically during supported install/update, MCP setup, skill installation/repair, and managed start/restart paths. It is also safe to rerun explicitly:

```bash
./zarzysseus.sh skills-mcp-fix
./zarzysseus.sh skills-runtime-fix
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 skills-mcp-fix
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 skills-runtime-fix
```

Set `ZARZYSSEUS_SKILL_MCP_AUTO_INSTALL=0` before launching Zarzysseus if you want declared MCP servers to remain manual.

## Local-model JSON tool-call recovery

Some local models correctly choose a tool but leak the call into assistant text as a compact object instead of returning it through the structured tool-call channel. A real example is:

```json
{
  "name": "mcp__builtin_browser__browser_tabs",
  "arguments": {
    "action": "new",
    "url": "https://www.reddit.com/r/unixporn/"
  }
}
```

With **Plan mode already off**, affected upstream Odysseus builds can display that object as prose because their raw OpenAI-style recovery recognizes the `{"function": {...}}` envelope but not the direct `{"name": ..., "arguments": ...}` shape. Zarzysseus installs a guarded parser compatibility patch that accepts the compact form only when the **entire assistant response** is one JSON object (optionally one JSON code fence), then hands it to Odysseus's existing canonical tool converter. Arbitrary JSON embedded in prose is not executed, and normal MCP/native security and approval checks still apply.

The fix is automatic on supported install/start/MCP/skill-repair paths and can be rerun manually:

```bash
./zarzysseus.sh tool-json-fix
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 tool-json-fix
```

Set `ZARZYSSEUS_DIRECT_TOOL_JSON_RECOVERY=0` to disable this compatibility patch.

## Executable skills and native tool routing

Odysseus skills are more than prompt text: an executable skill also needs the native tools required to run its procedure to be available to the Agent. In the upstream Agent loop, a matched skill's declared `requires_toolsets` is folded into the relevant tool set; simply placing `run.py` beside `SKILL.md` does not by itself guarantee that `bash` (or another native tool) will be offered. Zarzysseus repairs that metadata for imported executable skills and preserves explicit declarations. See the upstream [`agent_loop.py`](https://github.com/odysseus-dev/odysseus/blob/dev/src/agent_loop.py) for the relevant tool-selection path.

Zarzysseus now handles executable skills on **Linux and Windows** as follows:

- A skill with `run.py`, `run.sh`, `run.bash`, `run.ps1`, `runner.py`, `runner.sh`, or a local `scripts` / `bin` / `tools` payload is treated as executable and gets `bash` in `requires_toolsets` when it is missing.
- Common Agent Skills `allowed-tools` names are mapped to Odysseus native equivalents (`bash`, `python`, `read_file`, `write_file`, `edit_file`, `glob`, `grep`, `web_search`, `web_fetch`, `ask_user`). Existing explicit `requires_toolsets` values are preserved.
- Zarzysseus **does not invent MCP requirements** for a local runner. When a skill genuinely declares `mcpServers`/`mcp_servers`, Zarzysseus provisions that server and binds its discovered qualified tools; otherwise the skill stays on its declared native/CLI path.
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
| Need more MCP servers than the built-ins | Sync/search the machine-readable `Appnova-EU-OU/awesome-remote-mcp-servers` registry that is automatically mirrored to `freemcp.space`; separately auto-provision servers that an installed skill explicitly declares | FreeMCP discovery still does not auto-trust fuzzy search results. Skill-declared MCP servers are registered deterministically, probed, and bound to that skill's `requires_toolsets`; failed/missing-secret declarations stay disabled. |
| Local Qwen/model chooses the correct MCP/native tool but prints `{"name":"...","arguments":{...}}` instead of emitting a structured tool call | Guarded compact tool-JSON recovery converts only a whole-response direct tool object through Odysseus's existing canonical converter | Fixes the Plan-mode-OFF case where the call otherwise renders as prose. Embedded JSON/prose is not auto-executed and existing tool security/approvals remain in force. |
| Qwen generated prose instead of an actual call under the larger Agent request, although direct Ollama streaming and non-streaming calls worked | Guarded **Qwen explicit-tool + executable-skill + MCP routing focus V4** narrows first-round schemas when the user explicitly names a tool, invokes `/skill-name`, or the UI expands that request into a `BEGIN SKILL` block | Automatically attempted during supported full install/update and executable-skill repair/install (unless disabled), and rerunnable manually. It does not force every model to call a tool, automatically approve execution, or bypass security; test a real skill/tool execution. |
| The Agent workspace might be empty even when Odysseus's service starts in the cloned folder | Make the **actual discovered/cloned checkout** the browser's *first-use Agent workspace* | Existing browser selections and deliberate Clear actions remain authoritative. The source patch is guarded and backed up. Workspaces are browser-local, not a global server setting. |
| Session auto-naming/memory extraction still tried the unavailable `127.0.0.1:8000` route despite global utility defaults pointing at Ollama | Expose the active **global** utility/default/teacher settings in `tool-health`, without overwriting a user-specific/session override | **Not resolved** by the above patches; diagnose the actual per-user/session route before changing models or removing vLLM endpoints. |
| Ollama `/v1/embeddings` returned 404 | Leave Odysseus's working local FastEmbed fallback available | FastEmbed successfully indexed built-in and MCP tools on the reported Linux setup; this warning alone does not justify downloading a separate embedding model. |

**Local source changes and updates:** Workspace defaulting edits `static/js/workspace.js` during supported install/start paths; Qwen explicit-tool / executable-skill / MCP routing focus V4 edits `src/agent_loop.py`; compact tool-call recovery edits `src/tool_parsing.py`; the same-chat compatibility guard can edit `routes/session_routes.py`; and the Cookbook completed-download guard can edit `routes/cookbook_routes.py`. Guarded source patches write backups under `data/local/patch-backups/` and refuse unexpected upstream source layouts instead of applying an unsafe replacement. Tracked changes can make the installer's conservative Git fast-forward updater skip an update; reconcile local changes with upstream rather than resetting them blindly. Back up your checkout before replacing or editing it manually.

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

The Linux installer starts the existing ChromaDB Compose service during supported install/start/restart paths when Docker Compose is available; committed install/model selections also provision Docker on supported distros if it is missing. Full install/update and executable-skill install/repair also attempt the skill runtime metadata repair and guarded Qwen V4 focus patch. Full Linux OS upgrades additionally obey the persistent **AUTO FULL OS UPDATE** toggle; turning it off does not block required dependency-package installs. Same-chat continuity and Cookbook reliability repairs are also checked on supported install/start/restart paths. `CHROMADB_AUTO_START=0`, `ZARZYSSEUS_DEFAULT_WORKSPACE=0`, `OLLAMA_SUPPORTS_TOOLS=0`, `ZARZYSSEUS_QWEN_TOOL_FOCUS=0`, `ZARZYSSEUS_SKILL_MCP_AUTO_INSTALL=0`, and `ZARZYSSEUS_DIRECT_TOOL_JSON_RECOVERY=0` disable their corresponding behaviors. An ordinary `ollama-sync` alone does not patch upstream source.

### Windows: repair and verify

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 workspace-default
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 workspace-default status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 docker-setup  # explicit/repeatable Docker Desktop + ChromaDB repair
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 chromadb-start
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 ollama-sync
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 skills-runtime-fix       # metadata + Qwen focus + declared MCP provisioning
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 skills-mcp-fix           # rerun skill-declared MCP provisioning/discovery
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 tool-json-fix            # compact {name,arguments} tool-call recovery
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
