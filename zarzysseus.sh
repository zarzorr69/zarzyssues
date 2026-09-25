  $0 skills-repair-selected <installed-root>...  Repair only selected installed skills
  $0 skills-repair-all       Repair every installed skill using validated paths (no OS upgrade)
  $0 skills-list             List installed agent skills
  $0 skills-manage-list      List installed global skills with permission metadata
  $0 skills-update           Update installed agent skills
  $0 skills-update-one <name> Update one installed skill and re-check dependencies
  $0 skills-remove <name>    Remove one installed global skill
  $0 skills-summary-installed <name>  Show installed skill details and permissions
  $0 skills-permissions <name>        Show allowed-tools permissions
  $0 skills-permissions-set <name> <tool...>  Set allowed-tools (space-separated)
  $0 skills-permissions-clear <name>  Reset allowed-tools to agent defaults
  $0 accelerator-status   Detect GPU/OS and report ROCm/CUDA readiness
  $0 accelerator-setup   Install/verify ROCm, CUDA, Intel XPU, or CPU torch stack
  $0 sam-mask-install     Install/verify SAM mask + checkpoint
  $0 sam-mask-status      Show independent SAM mask verification status
  $0 vllm-status          Show vLLM ROCm dependency/library status
  $0 ollama-start        Start Ollama; install first if needed
  $0 ollama-stop         Stop Ollama
  $0 ollama-restart      Restart Ollama; install first if needed
  $0 ollama-status       Show Ollama service/API status and configured LLM
  $0 ollama-enable       Enable Ollama automatic startup and start
  $0 ollama-disable      Disable Ollama automatic startup and stop
  $0 ollama-sync         Reconcile Ollama inventory and repair local Ollama native-tool endpoint aliases
  $0 chromadb-start      Start the checkout's ChromaDB service and verify its heartbeat
  $0 docker-setup        Explicitly install/start Docker Engine + Compose v2, then ChromaDB
  $0 tool-health         Inspect ChromaDB, Ollama endpoint flags, default/utility/teacher model settings
  $0 agent-tool-focus-install   Install guarded Qwen first-round explicit-tool focus in local agent_loop.py
  $0 ollama-pull <model> Pull a model with Ollama, make it the default LLM, then register it
  $0 opull <model> Pull with Ollama (short alias)
  $0 vpull <org/model> [include-glob] Download/cache a Hugging Face model for vLLM and make it default
  $0 spull <org/model> [include-glob] Download/cache a Hugging Face model for SGLang and make it default
  $0 mpull <org/model> [include-glob] Download/cache a Hugging Face model for MLX-LM, start its OpenAI-compatible server, and make it default
  $0 start               Start Zarzysseus; install first if needed
  $0 stop                Stop Zarzysseus
  $0 restart             Restart Zarzysseus; install first if needed
  $0 status              Show whether Zarzysseus/service are installed and running
  $0 enable              Enable automatic startup and start; install first if needed
  $0 disable             Disable automatic startup and stop
  $0 uninstall           Remove Zarzysseus project + Zarzysseus-related user services
  $0 uninstall-service   Remove the automatic startup service only
  $0 help                Show this help

Environment overrides:
  PYTHON_VERSION
  PROJECT_DIR                              Zarzysseus checkout (auto-discovered; default fallback: ~/odysseus)
  ZARZYSSEUS_AUTO_DISCOVER (default: 1)      Auto-detect existing clones/services/script locations
  ZARZYSSEUS_DEFAULT_WORKSPACE (default: 1)  Set project as first-use browser Agent workspace
  ZARZYSSEUS_DISCOVERY_MAXDEPTH (default: 5) Home-directory search depth for old/renamed clones
  ZARZYSSEUS_GIT_FETCH_TIMEOUT (default: 60) Seconds before a stalled upstream fetch times out
  SYSTEM_AUTO_UPDATE (default: 1)          Update the OS before mutating install actions
  SYSTEM_UPDATE_TTL (default: 21600)       Cache window for install/update-triggered system upgrades
  SYSTEM_UPDATE_FORCE (default: 0)         Force an update even when the TTL stamp is fresh
  SYSTEM_UPDATE_STRICT (default: 1)        Stop before project changes if the OS update fails
  MANAGED_SCRIPT_PATH                       Stable installer copy (default: PROJECT_DIR/zarzysseus.sh)
  VENV_DIR
  ZARZYSSEUS_HOST
  ZARZYSSEUS_PORT
  SAM_MODEL_TYPE (vit_b, vit_l, vit_h)
  SAM_MODEL_DIR
  PLAYWRIGHT_CACHE_DIR
  OLLAMA_SERVICE_NAME
  OLLAMA_DEFAULT_MODEL (default: llama3.1:8b)
  DEFAULT_MODEL_ID (default: dphn/Dolphin-Mistral-24B-Venice-Edition)
  DEFAULT_MODEL_PROVIDER (default: vllm; supports vllm, sglang, ollama, mlx_lm)
  DEFAULT_MODEL_CONTEXT_LENGTH (default: 4096; ROCm vLLM 0.29 Mistral limitation)
  OLLAMA_PULL_DEFAULT_MODEL (default: 1)
  OLLAMA_MAX_LOADED_MODELS (default: 1)
  OLLAMA_CONTEXT_LENGTH (default: 32768)
  OLLAMA_SUPPORTS_TOOLS (default: 1; opt in all local Ollama /v1 endpoint aliases)
  CHROMADB_AUTO_START (default: 1; start existing Compose service on install/start/restart)
  ZARZYSSEUS_DOCKER_AUTO_INSTALL (default: 1; install Docker only on committed install or model selection)
  CHROMADB_HEARTBEAT_URL (default: http://127.0.0.1:8100/api/v2/heartbeat)
  ZARZYSSEUS_QWEN_TOOL_FOCUS (default: 1; opt-in local source patch via agent-tool-focus-install)
  INSTALL_VLLM (default: 1)              Install vLLM during setup
  INSTALL_SGLANG (default: 1)            Install SGLang during setup
  INSTALL_MLX_LM (default: 1)            Install MLX-LM during setup
  PATCH_COOKBOOK_SAM_MASK_RECIPE (default: 1) Patch Cookbook sam_mask recipe to full deps
  ACCELERATOR_PREFERENCE (default: auto)  auto|amd|nvidia|intel|cpu
  NVIDIA_DRIVER_PACKAGE (default: auto)  override only with a verified driver package
  NVIDIA_AUTO_DRIVER (default: 1)         Allow supported distros to install NVIDIA drivers
  ROCM_AUTO_DRIVER (default: 0)            Allow Ubuntu/Debian amdgpu-install to manage the driver
  ROCM_VERSION (default: 7.2.4)             AMD ROCm release used by the system installer
  ROCM_PATH (default: /opt/rocm)             ROCm installation prefix
  PYTORCH_ROCM_VERSION (default: 2.14.0+rocm7.2)
  VLLM_ROCM_VERSION (default: 0.29.0+rocm723)
  INSTALL_SAM_MASK_FULL (default: 1)     Install full SAM mask extras
  VLLM_EXTRA_INDEX_URL                   Optional extra wheel index for vLLM (e.g. ROCm)
  MODEL_AUTO_PROVIDER_ORDER               Provider order for automatic HF model routing (default: vllm,sglang,mlx_lm,ollama)
  COOKBOOK_LOCAL_DIR                     Persistent local serving-engine root (default: PROJECT_DIR/data/local)
  VLLM_VENV_DIR                          Isolated vLLM environment
  OPENMPI4_VERSION (default: 4.1.8)       OpenMPI 4 C++ ABI compatibility version
  OPENMPI4_PREFIX                          Private OpenMPI 4 prefix for serving engines
  OPENMPI4_MAKE_JOBS                       Parallel OpenMPI compatibility build jobs
  SGLANG_VENV_DIR                        Isolated SGLang environment
  MLX_LM_VENV_DIR                        Isolated MLX-LM environment
  MLX_LM_MODEL_DIR                       Persistent MLX-LM model cache
  MLX_LM_ENDPOINT                        MLX-LM OpenAI-compatible endpoint (default: http://127.0.0.1:8081/v1)
  MLX_LM_SERVICE_NAME                    MLX-LM user service name
  MLX_LM_SERVICE_FILE                    MLX-LM user service file
  COOKBOOK_BIN_DIR                       Engine executable directory
EOF_HELP
        ;;
    *)
        echo "Unknown action: $ACTION"
        echo "Run '$0 help' for usage."
        exit 2
        ;;
esac
