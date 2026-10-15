# Zarzysseus CPU starter kit

Prepared for a fourth-generation Intel Core i7, 16 GB DDR3, no discrete GPU,
and ZimaOS. This is a separate, reviewable deployment draft for your server;
it does not depend on installing apt, ROCm, CUDA, vLLM, SGLang, or PyTorch there.
Docker and Docker Compose must already work. The first stage measured the CPU
backend. This revision also provides a Zarzysseus Docker menu for that same stack.

## Model choices

| Profile | Base model | Quantized download | Intended use |
| --- | --- | --- | --- |
| `quality` (default) | `qwen3.5:4b-q4_K_M` | 3.3 GB | Tested daily-chat starting point: 3.41 tokens/second with Thinking off; native tool proposal passed |
| `agent` | `LiquidAI/lfm2.5-2.6b:q4_k_m` | 1.7 GB | Native tool protocol confirmed; mandatory reasoning was too slow for everyday chat in the server test |
| `moe` | `lfm2.5:8b-a1b-q4_K_M` | 5.2 GB | Optional sparse reasoning-model experiment; all expert weights occupy RAM |

These are download sizes, not total runtime RAM. LFM2.5-2.6B's publisher
explicitly advises against using it for knowledge-heavy work or agentic coding.
It is text-only. Browser DOM/text tools can be useful; interpreting screenshots
requires a model with vision. Qwen3.5 supports vision, but this kit's tests use text.

Sources: [LFM2.5-2.6B](https://ollama.com/LiquidAI/lfm2.5-2.6b:q4_k_m),
[Qwen3.5 quantizations](https://ollama.com/library/qwen3.5/tags),
[LFM2.5-8B-A1B](https://www.liquid.ai/blog/lfm2-5-8b-a1b).
Vendor results on modern Ryzen/M-series CPUs are not measurements of your i7.

## Observed server results

The corrected LFM2.5-2.6B native proposal passed. One tool proposal took 19.437
seconds after the preceding chats. At two threads, a two-sentence chat answer
began after 148.558 seconds and finished after 155.178 seconds, generating 856
tokens at 5.87 tokens/second. At four threads, it generated 1,024 tokens at 4.0
tokens/second and stopped at the output limit without an answer after 263.816
seconds. These were individual requests under the kit's three-CPU quota, not
an exhaustive comparison of the processor's capabilities.

The subsequent Qwen3.5-4B test on October 14, 2026 used two threads, a 4,096-token
context, a 256-token output budget and `think: false`. It answered correctly in
58 tokens at 3.41 tokens/second, with zero thinking characters. First content
arrived after 16.710 seconds and the full request finished in 33.711 seconds;
14.857 seconds were model loading. Subtracting loading leaves about 1.853
seconds before first content, but this is an estimate of loading overhead,
not a measured warm-request latency. Its subsequent native tool proposal
passed in 24.650 seconds with 27 output tokens. Larger prompts and tool schemas
can add substantial prompt-processing time, even with a warm model.

These individual requests establish that Qwen avoids LFM's mandatory reasoning
delay on this server. Qwen is the current daily-chat starting point; broader
answer quality and a complete Odysseus tool round trip remain to be checked.

## Start with the model service

Extract this folder somewhere persistent, for example `/DATA/zarzysseus-cpu-kit`.
Open a terminal there and run:

```bash
sudo bash run.sh setup quality
sudo bash run.sh benchmark quality
```

For an already downloaded profile, load it without generating another answer:

```bash
sudo bash run.sh warm quality
```

This command uses cached images and weights. The model stays loaded for
`MODEL_KEEP_ALIVE`, which defaults to 30 minutes after a request. It still uses
RAM while idle. A later API request can override that interval; selecting a
different model can evict it because the kit allows one loaded model.

The first command starts a separate Ollama container, downloads the requested
base model, creates a CPU profile and checks a simulated structured tool call.
The second runs a quick check of answer latency and decoding speed with two
threads, then one tool proposal. For Qwen it requests Thinking off and uses a
256-token output budget. It prints actual answers for review.
No proposed diagnostic tool is executed. A passed proposal is not proof of
complete Odysseus Agent execution: verify a real enabled tool inside Odysseus.

### Repair the initial reasoning-budget/tool-format failure

The first release incorrectly gave text tests only 160 output tokens and tool
tests 256. LFM2.5-2.6B always reasons before answering, so those caps can end the
response before any final answer. The tool prompt could also steer it into
JSON prose instead of its native function-call representation. This revision
uses a 1,024-token shared reasoning/answer budget, explicitly declares LFM's
thinking renderer/parser, and requests native calls without counting JSON
prose as successful tool calls. An answerless, completed stream now reports
its token rate, thinking size and stop reason instead of discarding those metrics.

To repair an already downloaded installation, replace `benchmark.py`, `run.sh`
and `models/Modelfile.agent` from this corrected package, then run:

```bash
sudo bash run.sh repair-agent
sudo bash run.sh benchmark agent
```

The repair uses the existing model/image and does not pull images or weights.
The default CPU benchmark is now the shorter quick check. For the full repeated
and longer-prompt experiment, use:

```bash
sudo docker compose run --rm bench lfm2.5-zarzysseus-cpu:2.6b --threads 2 4
```

The 2.6B model's mandatory reasoning can still make it slow to deliver a final
answer on older CPUs. This repair corrects the test and protocol settings;
it does not establish model quality or make reasoning free. If the tool probe
still fails, keep the failed result and compare the base model's metadata and
native response before enabling agent execution.

The default profile is now `quality`, creating `qwen3.5-zarzysseus-cpu:4b`.
When using it in Odysseus, select Thinking off; the Modelfile cannot persist
the per-request `think: false` setting. The benchmark handles that switch.
The optional application launcher now also enforces the measured fast settings
for this exact alias on native Ollama requests; see the integration note below.
The other profiles are optional and require their own explicit downloads:

```bash
sudo bash run.sh setup agent
sudo bash run.sh benchmark agent
# Optional, after comparing the first two:
sudo bash run.sh setup moe
sudo bash run.sh benchmark moe
```

They appear as `lfm2.5-zarzysseus-cpu:2.6b` and
`lfm2.5-zarzysseus-cpu:8b-a1b`. Names retain the model-family prefix because
some application routing logic uses that identity. Base model tags remain
installed; Ollama's content-addressed storage reuses their weights for profiles.

## Zarzysseus on this Docker stack

V11 integrates this CPU kit into the **unified Linux launcher**. Docker mode
reuses this kit's Compose project, ports, model volume and selected Qwen model.
The container helper now reads the **bundled, checksum-verified V11 Linux script**
through a read-only `/cpu-kit/zarzysseus.sh` mount, rather than downloading an
older GitHub commit. It builds a container-only compatibility copy in the
Odysseus data volume. The native stack installer and native TUI are never
executed inside the container.

For an existing kit, use the root V11 launcher and **preview before syncing**.
Its `docker-kit-sync apply` command backs up modified kit source, preserves your
`.env`, workspace and named volumes, and adds the toolkit mount. Keep your
chosen `APP_BIND` and `APP_ORIGIN` settings. After syncing:

```bash
# From your existing kit directory; requires accessible Docker Compose.
sudo bash run.sh app
sudo bash run.sh zarzysseus toolkit-install
sudo bash run.sh zarzysseus
```

Alternatively, open the root unified TUI, choose Docker, then
**Install / Update → Install/refresh toolkit helper** after starting the app.
A fresh Docker stack has a separate consent-gated **Install complete CPU stack**
choice. Installing only the bundled toolkit helper does not redownload models,
create host Python environments or install inference runtimes. Opening the menu
does not install anything.

| Docker menu capability | Implementation and current boundary |
| --- | --- |
| Start/stop/restart/status/logs | Host Docker Compose controls this existing kit's Odysseus container |
| Model list/warm/benchmark/pull | The existing CPU Ollama service; model download is explicit |
| Agent/tools/skills diagnostics | Your actual toolkit helpers inside the app container |
| CPU Agent repairs | Qwen focus, Agent V2, same-chat continuity and strict JSON recovery; validated against the inspected upstream source |
| Skills search/install/sync/setup | Your actual skill manager; setup retains its review/approval prompts |
| Selected favorite packs | Office, scripting and transcription definitions/runners; dependencies and readiness still need their own checks |
| Cookbook progress and MCP setup | Guarded helpers; report installed only after source checks and on-host validation |
| AMD Radeon SGLang preflight | Opt-in, pinned RDNA3 Docker doctor on supported AMD hosts; actual inference must be tested separately |
| Native OS/systemd/GPU/alternate runtimes | Continue using the native edition for system-level operations |

The V2 adapter preserves upstream caller denials, block-all tool policy, and
delegated-credential restrictions before narrowing browser schemas. It also
patches only the final active prompt constants when upstream retains shadowed
older definitions. The newer dispatch structure rejects the legacy V3-V8
recovery/screenshot chain; that chain is not counted as installed by the CPU
repair command. It remains an explicitly optional, version-sensitive action,
`container-agent-legacy-repair`, which prints the original guard failure.

Useful direct commands, also exposed in the menu:

```bash
sudo bash run.sh zarzysseus doctor
sudo bash run.sh zarzysseus repair
sudo bash run.sh zarzysseus cookbook-fix status
sudo bash run.sh zarzysseus skills-doctor
sudo bash run.sh zarzysseus skills-search office
sudo bash run.sh zarzysseus models
```

Each mutating helper records changed existing Python/JavaScript/HTML/CSS source
in `data/local/zarzysseus-docker/overlay`. The app startup verifies original and
patched hashes and replays only onto matching source. Patches survive container
recreation without freezing all upstream source in a volume. A new upstream
layout or damaged blob stops replay before app loading; it is not silently
overwritten. Your original helper backups remain under
`data/local/patch-backups`. The actual toolkit rollback updates the replay
record too. CPU Agent rollback retains the separately installed Qwen focus
patch. `ZARZYSSEUS_OVERLAY=0` disables automatic replay for version
reconciliation; it does not undo source already changed in a running container.
Set it in `.env` and recreate the app if an upstream image update is rejected.

The Docker launcher initializes only the new `.agents` and `.config` named
volume roots before handing off to the image's own entrypoint for its usual
setup and PUID/PGID drop. The toolkit runs as that non-root app UID and uses
the image's installed Python. Missing OS packages are reported for an image
update; no ZimaOS package installation is attempted. Additional skill/browser
dependencies download only when their setup action is chosen. Check disk
space before choosing optional packs or browser setup.

This Docker edition mirrors the **native top-level menu categories**, but
some operations are intentionally scoped to Compose or native host only. It
is not a claim of complete runtime feature parity or a live server integration test. Live Agent execution,
image ownership and actual dependency setup must still be verified on ZimaOS.
No GitHub changes or pushes were made.

## Connect an existing Odysseus instance

- If Odysseus runs **natively on this ZimaOS host**, use Ollama's native base URL
  `http://127.0.0.1:11435`.
- If Odysseus runs **inside Docker**, attach that container to the kit's bridge:
  `sudo docker network connect zarzysseus-cpu-private YOUR_ODYSSEUS_CONTAINER`.
  Use the native base URL `http://cpu-ollama:11434`. Persist the shared network
  in that application's Compose configuration before recreating its container.
- Select the installed CPU profile in the chat model picker. For tools, enable
  Agent and the actual required tools. The API's `/v1` path is a separate
  compatibility dialect; the native Ollama URL above is the intended route.
- With a native existing Zarzysseus install, the advisor can reach this service
  using `OLLAMA_HOST=127.0.0.1:11435`; its existing static catalog still needs
  updating before it can recommend these new profile names.

### Native Ollama thinking control

In the inspected upstream `src/llm_core.py`, `_build_ollama_payload` does not
send `think`, and its native callers do not forward the chat's `thinking_mode`.
Therefore the UI switch alone does not establish that Qwen receives
`think: false` on this route. This kit's optional Docker application uses
`launch_odysseus.py` as its command, while retaining the image's own entrypoint
and PUID/PGID setup. Before loading the app, it wraps that native payload builder
inside the app process. Only `qwen3.5-zarzysseus-cpu:4b` receives `think: false`,
two threads, GPU layers zero, a 4,096-token context, batch 128 and the configured
keep-alive. Tools, images, streaming, temperature and output budgets are
preserved. Other model payloads pass through unchanged.

For this CPU alias, the adapter keeps Thinking off even if the UI is switched
on. Use the base Qwen model tag if you deliberately want different runtime
settings. The CPU adapter itself edits no upstream source file; selected
Zarzysseus repair commands can edit and persist compatible source patches.
To disable the CPU adapter, set
`CPU_PROFILE_GUARD=0` in `.env` and recreate the optional Odysseus container.
An unexpected builder/payload shape raises an error rather than guessing.

An existing Odysseus instance connected only by URL does not receive this
adapter. Verify its outgoing native request or launch it with the helper using
that installation's Python environment and `--app-root`/`--port`. Do not start
a second process on an occupied port. The Docker wrapper has been tested with
a simulated app and the inspected real native builder; a live app run on ZimaOS
is still required.

## Optional fresh Odysseus instance on ZimaOS

This starts the **upstream Odysseus Docker image**, plus ChromaDB and SearxNG,
on this kit's private Docker bridge. It uses new named volumes and port 7012.
It does not migrate an existing application's database or install Zarzysseus's
native services. The optional Docker menu installs your toolkit separately and
applies only the repair actions you select; see the integration section above.

First copy `.env.example` to `.env` if `setup` has not already created it.
For access from another device, **prefer the Docker TUI → Network Discoverability → Change binding** (it backs up `.env` and asks before restarting Odysseus). You can also edit these values manually:

```dotenv
APP_BIND=YOUR_SERVER_LAN_OR_TAILSCALE_IP
APP_PORT=7012
APP_ORIGIN=http://YOUR_SERVER_LAN_OR_TAILSCALE_IP:7012
```

Replace the placeholder with an address actually assigned to your server.
Leave the default loopback bind for server-local access. Set APP_ORIGIN to the
URL you will use; for a private HTTPS reverse proxy, use its HTTPS origin.
PUID/PGID default to your previously reported ZimaOS user/group, 999/1000;
change APP_UID/APP_GID if this installation uses another account.

Then:

```bash
sudo bash run.sh app
sudo bash run.sh status
sudo bash run.sh logs
```

Open the configured server address on port 7012, complete Odysseus's account
setup, discover the Ollama models and choose the CPU profile. Authentication
is enabled. ChromaDB, SearxNG and Ollama have no public host bindings; the
optional app bind is chosen in `.env`.

App/model images use current moving tags for this experiment. After a live
successful test, you can pin the image digests in `.env` for repeatability.
SearxNG uses the image/digest pinned in the inspected upstream Compose file.

## Why these settings

- **4,096-token context** starts with a modest memory and prompt-processing
  budget. Do not allocate a model's entire 128K/256K capacity on this server.
  Increase to 8K only after checking latency and memory; long agents may need it.
- **One loaded model and one concurrent request** limit competition for RAM and
  CPU. Odysseus utility/background requests share that queue. Running a browser,
  embeddings or additional applications simultaneously can still slow inference.
- **Thirty-minute keep-alive** avoids repeatedly paying the measured 14.857-second
  Qwen loading cost when requests are separated by a few minutes. Set
  MODEL_KEEP_ALIVE in `.env` to trade idle RAM for fewer reloads. Keeping a model
  loaded does not raise its decoding speed.
- **Two inference threads** are the current starting value based on your run,
  not an assumed core count. Fourth-generation i7 desktop/mobile variants differ.
  To compare other counts, pass `--threads 2 4` directly to the bench service;
  change `PARAMETER num_thread` in the chosen Modelfile and rerun setup. An eight-
  thread setting is not automatically faster just because Hyper-Threading exists.
- **GPU layers zero** and no device passthrough keep this deployment on the CPU.
  The model service's three-logical-CPU quota trades peak benchmark speed for
  server responsiveness; tune MODEL_CPU_LIMIT in `.env` after measurement.
- **Memory caps** are upper limits, not allocations: 6 GB for Ollama, 3 GB for
  Odysseus, 768 MB for ChromaDB and 512 MB for search. Your other services also
  need RAM. Check `free -h` and `sudo docker stats --no-stream` on the server.
  If a container hits its cap it can be killed; reduce context/workload first.
- For Qwen, keep Thinking off in Odysseus for quick routine requests. The optional
  launcher applies that choice to the native CPU alias. The benchmark requests
  no thinking when the model advertises
  compatible controls. LFM2.5-2.6B's always-thinking setting cannot be disabled
  through the advertised boolean controls. Hard reasoning takes longer.

`stop` stops this kit's containers. `down` removes them and the bridge while
preserving named volumes. A separately attached Odysseus container can prevent
bridge removal; disconnect it first if you intend to remove the bridge.

## Optimization reality and the 27B experiment

Quantization reduces bits per weight. A 7B model is roughly 14 GB of FP16 weights
before caches; Q4 builds commonly fit in several GB. This preserves the parameter
count, unlike selecting a 0.5B model. Quality can decline with lower precision.
Sparse MoE models reduce active computation but still need all expert weights
in memory. Distillation trains smaller students; it is not a runtime switch.
Speculative decoding needs supported target/draft models and useful acceptance
rates; it can fail to help on an old CPU that is already resource constrained.
CPU/disk offload can make a model load while leaving it too slow for useful chat.

There is a real 27B option worth a separate experiment: PrismML's earlier
Bonsai-27B binary build has about 3.53 GiB of deployed language-model weights;
its ternary build is around 6.66 GiB. The newer **Bonsai 2 27B** model card lists
5.95 GB and 7.21 GB language-model packings, plus an optional 0.63 GB vision
projector. Its demo README reports a roughly 7.8 GB default download, so inspect
the actual selected file and packing rather than an idealized bit-width size.
Current Bonsai 2 requires
PrismML's patched llama.cpp runtime; stock runtime support is incomplete, and
a superficially successful load can still generate incorrect output. Memory fit
does not establish useful Haswell speed or equivalent quality to full precision.

That experiment could later connect through Odysseus's llama.cpp/OpenAI-compatible
provider. It is deliberately not part of this starter kit's automatic downloads.
Sources: [Bonsai demo/runtime requirements](https://github.com/PrismML-Eng/Bonsai-demo),
[earlier model memory table](https://github.com/PrismML-Eng/Bonsai-demo/blob/main/Bonsai1_README.md),
[Bonsai 2 model](https://huggingface.co/prism-ml/Ternary-Bonsai-2-27B-gguf).

## Repository inspection

Inspected your [Zarzysseus repo](https://github.com/zarzorr69/zarzyssues) at
`f44bda2` and upstream Odysseus `dev` at `a8c147b` on October 13, 2026.

1. Your project is an installer/repair toolkit for the upstream app, rather than
   an independently packaged full Odysseus application.
2. `zarzysseus.sh` detects many package managers, but not ZimaOS's Entware/opkg.
   Native install paths fail on an unknown package manager. Docker is a practical
   deployment route for this host without extending its package-management layer.
3. `zarzysseus_model_advisor_v10.py` has nine older catalog entries. It does not
   include LFM2.5, Qwen3.5 or Bonsai, and its memory fit is a rough weight/headroom
   estimate. It uses total RAM and dedicated VRAM detection, without an available-
   RAM budget for your server services or a measured CPU inference result.
4. The same V10 helper is embedded in both the Bash and PowerShell scripts.
   Updating only the standalone Python copy would leave the launchers stale;
   your existing fixture test explicitly checks embedded-source identity.
5. The native-tool health check already checks a proposal without executing it.
   This kit extends that idea with CPU context/thread settings and speed/latency
   measurements. A live Odysseus tool execution remains a separate verification.
6. Upstream already discovers Ollama and llama.cpp providers. An application's
   `localhost` inside a container refers to that container, so this kit gives
   the application a shared-network Ollama hostname instead.
7. The inspected native Ollama payload builder ignores the Thinking UI setting.
   The optional CPU launcher now adapts this exact Qwen alias without editing
   upstream source. Existing instances need that fix or equivalent request-level
   controls to preserve the non-thinking behavior measured by the benchmark.

Further native-repo integration should add a CPU server profile, available-memory
budgeting, separate total/active MoE parameter fields, measurements saved by
runtime/quant/context, and guarded container patch installation. Apply this
through the existing TUI rather than treating RAM fit as tested readiness.

## Validation boundary

This package was syntax-checked and tested against a local simulated Ollama API.
All sixteen helper tests passed: separate streaming timings, incomplete/error
response handling, strict structured tool proposals, model-specific thinking
controls, reasoning-only generation limits, native LFM prompt/budget handling,
and the native HTTP request workflow, including generation-free preloading,
without tool execution. The CPU adapter tests preserve tools/images/output
budgets, leave other models unchanged, reject incompatible builder shapes,
and verify installation before a simulated app starts without editing its source.
The adapter was also checked against the real inspected native request builder.
Docker toolkit tests check source replay across recreation, original baseline
retention over successive repairs, exact rollback removal, drift rejection before
any replay write, corrupt blobs, path validation, native-installer exclusion and
literal argument forwarding by the host menu. The pinned compatibility script
was verified and Bash-checked. Offline checks against the inspected upstream
source applied Qwen focus, Agent V2, continuity and JSON repairs and verified
that caller/policy/delegated-credential denials still hold. The legacy V3-V8
chain rejected its changed dispatch anchor, and Cookbook V10.2 rejected its
changed card-update anchor without editing source. These checks did not run the app,
models or browser, and the workspace could not reproduce the server UID.
The shell passed `bash -n`, the Python modules compiled, and the Compose YAML parsed.
These helper tests ran without a real model. Your first server run confirmed
that the image and 1.7 GB model download and load, but the original native tool
probe returned JSON text and the 160-token chat test returned no final answer.
Your subsequent server run verified native tool proposals and exposed the slow
LFM chat timings summarized above. Qwen's successful non-thinking chat and native
tool proposal were measured on your server as summarized above. The
container stack has not been booted in this workspace because Docker is
unavailable here. Model
quality, actual speed, image compatibility and end-to-end Odysseus tool execution
must be checked on the server. No GitHub commit, push or server deployment was made.

To rerun the helper tests on a computer with Python:

```bash
python3 -m unittest discover -s tests -v
```

## Windows Docker Desktop controller (V11.3)

Windows PowerShell 5.1+ can run the same Linux-container CPU kit without Git Bash.
Install/start Docker Desktop in **Linux containers** mode, then run from the
complete Zarzysseus release folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 mode docker
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\zarzysseus.ps1 tui
```

The Windows-specific controller is `docker/zarzysseus-docker.ps1`. It uses
Docker Compose directly, retains `.env` and named volumes, and calls the
same checksum-guarded Python toolkit bridge as Linux Docker for skills,
MCP, agent and Cookbook repairs. If Docker Desktop is missing, use the
**Install / Update → Docker Desktop prerequisite check**; downloading Docker
Desktop requires explicit approval. No Bash is needed on the Windows host.

The Docker menu exposes matching **feature categories**, not every host
operation. Windows services, driver installation, MLX, and AMD `gfx1100`
Linux `/dev/kfd` GPU serving cannot be performed in Windows Docker Desktop.
The hardware `Full` profile never silently enables unsupported GPU engines.
Windows end-to-end testing is pending; use Docker mode on Linux/ZimaOS for
an already tested CLI deployment and consult the main README for the
one-line Windows `curl.exe` bootstrap.


### Guided setup and initial admin (V11.4)

Use **Docker → Install / Update → Install Odysseus + CPU model**. The six-stage
installer shows real Compose logs and model downloads. Before the application
first starts, it can create an admin username and hidden password through the
upstream `AuthManager` using a short-lived Compose container. No plaintext
credentials are written to `.env` or passed as Docker environment variables.

Existing `auth.json` is never overwritten. If an account exists, log in and
change credentials through Odysseus's authenticated account settings. To
update the host bind address, use the Docker Network menu and approve
recreation of **only** Odysseus; never enable unauthenticated public access.
