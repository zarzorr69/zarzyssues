# Seamless MCP routing and CPU-only Docker readiness (work in progress)

This change addresses two independent failure classes. Neither requires a user to invoke a `/skill` just to use MCP.

## 1. Seamless MCP routing

- An enabled, available MCP schema can be selected from an ordinary request, such as "create a GitHub issue", "send an email", or "open this URL and screenshot it".
- Small contextual follow-ups can reuse **the previous user message from the same request history** solely for tool choice. No third-party page content or assistant text is used as a new authorization.
- The injection uses the active endpoint's **existing MCP inventory**. It does not connect a server, install dependencies, open credentials, bypass approvals/denylists, or force a tool call.
- The number of selected tools is capped to avoid flooding the CPU-only Qwen prompt.
- Any unrecognized upstream `agent_loop.py` layout fails closed; backups are created, and installation is idempotent.

Native, when deployed with the complete source checkout:

```bash
bash zarzysseus.sh mcp-seamless-status
bash zarzysseus.sh mcp-seamless-install
```

The native `agent-repair` / `install-all-fixes` actions also check the patch. A **running** Odysseus service needs a managed restart for changes to take effect; do not restart in the middle of an active agent run.

Docker, after guarded `docker-kit-sync` and toolkit initialization:

```bash
bash zarzysseus.sh docker seamless-mcp-status
bash zarzysseus.sh docker seamless-mcp-install
```

The Docker bridge records source changes in the existing guarded overlay and prints restart instructions. The one-click Docker fix action includes it, but is separate from a read-only doctor.

## 1.1 Current-chat context and cross-chat recall

Short follow-ups like **CSS is fine**, **now screenshot it**, and **do that** can carry a bounded window of the last three user requests into tool relevance. Assistant replies, pages, and tool outputs are not treated as user authorization.

The agent can also offer the **existing Odysseus tools** when relevant:

- `search_chats`: find the signed-in user's past session evidence for natural requests such as "we discussed this in our previous chat". Merely offering this tool does not read any chats.
- `manage_memory`: retrieve or save information through Odysseus Brain when explicitly asked to remember, save a preference, or describe saved memories. No automatic transcript scraping or silent saving.

These tools still obey explicit caller selection, disabled-tool lists, approvals and Odysseus account permissions. The patch does not introduce an unscoped global memory database.

**Limitations:** No automatic full-history semantic indexing, background summarization, or guarantee that a small model calls every offered tool. Durable memories require an actual successful `manage_memory` call. The screenshot tool can return pixels to the UI even if a text-only model cannot interpret them; Dolphin-Mistral GGUF should not be expected to understand Base64 image data. For visual analysis use a vision-capable model, then test whether the screenshot is actually passed as image content.

**Manual native tests after successful dry-run/install and managed restart:**

1. Ask "Open https://example.com and take a screenshot" in Agent mode, without a skill; then follow up with "CSS is fine". Verify real browser calls and screenshot UI, not just text saying it succeeded.
2. In a fresh chat ask "We discussed my AI server in another chat; find that chat and remind me what model we chose." Check for a real `search_chats` tool execution.
3. Ask "Remember this: I prefer fish commands". Verify the result in Brain, then ask "What do you remember about my shell?". Verify real `manage_memory` usage.
4. Test that disabled tools stay disabled and an explicit caller-tool scope is never broadened.

## 2. ZimaOS CPU-only safety diagnosis

Target: fourth-generation Intel Core i7, 16 GiB DDR3, no GPU. Previously, simultaneous Odysseus/Ollama operations were followed by extreme I/O pressure and a frozen host. **Do not use a generation or preload loop as a diagnostic.**

After synchronizing the updated kit, run:

```bash
bash zarzysseus.sh docker cpu-doctor
bash zarzysseus.sh docker model-doctor
```

The new `cpu-doctor` is read-only. It reports memory availability, kernel I/O and memory pressure, the nonsecret Compose CPU/memory policy, service state, and bounded `ollama list` / `ollama ps` metadata calls. It **does not invoke inference**. Share its output before setting aggressive model warmup or concurrency values.

The Docker kit still defaults to `MODEL_KEEP_ALIVE=30m` unless the *existing deployment's* `.env` says otherwise. A lower value may reduce idle RAM occupancy, but blindly changing limits while the server is struggling is not safe. The model-inventory auto-registration in PR #1 needs real deployment testing as well.

## Validation boundary

Offline Python tests and Bash syntax checks run in GitHub Actions. They do **not** prove a model has made an MCP call, that the current Odysseus source matches the patch, or that an older ZimaOS host can withstand inference. Keep this PR unmerged until native and Docker testing succeeds. Do not delete model volumes, reset authorization, re-download models, or alter Docker's data mount as part of these fixes.
