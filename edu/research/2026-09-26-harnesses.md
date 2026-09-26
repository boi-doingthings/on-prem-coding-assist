# Open-source coding-agent harnesses, chat UIs, gateways and tracing for a university-hosted Dynamo endpoint

Research date: 2026-09-26. Stars/licences/activity were pulled live from the GitHub API, PyPI and npm on that date. Config snippets come from official docs or READMEs; the source URLs are listed in each section. Anything I could not confirm is marked **(verify)**.

Target backend: NVIDIA Dynamo frontend at `http://HOST:8000/v1`, serving `Qwen/Qwen3.5-122B-A10B`.

---

## 0. Things to know before choosing (big changes since 2025)

| Change | Impact |
|---|---|
| **Continue.dev is end-of-life.** Cursor acquired it in mid-June 2026. It shipped a final v2.0.0 on 2026-06-19, which removed telemetry and auth, and the repo is now read-only. | Don't pick it for a new deployment. It still works, but it gets no security fixes. |
| **Roo Code shut down on 2026-05-15.** The repo is archived and the extension, Cloud and Router services are all gone. | Use Cline or Kilo instead. Kilo publishes a Roo→Kilo migration guide. |
| **Void editor was archived on 2026-06-02.** Development is paused. | Avoid it. |
| **Aider has slowed down.** The last PyPI release was 0.86.2 on 2026-02-12, there has been no tagged GitHub release since Aug 2025, and about 500 PRs are open. The community fork **cecli** (formerly Aider-CE) ships weekly. | Aider is still useful as a teaching tool with text edit formats, but it is effectively in maintenance mode. |
| **OpenHands was restructured.** `OpenHands/OpenHands` is now "Agent Canvas", an orchestration UI that can also drive Claude Code, Codex and Gemini via ACP. The agent itself moved to `OpenHands/software-agent-sdk`. The V1 CLI (`OpenHands/OpenHands-CLI`) is "no longer actively maintained". | Use the **SDK** for evals and research, and Agent Canvas for a GUI. |
| **Codex CLI dropped Chat Completions.** `wire_api="chat"` was removed in Feb 2026, and `responses` is now the only value. | Codex needs `/v1/responses`. **Dynamo implements `/v1/responses`**: in this repo, `lib/llm/src/protocols/openai/responses/mod.rs` converts Responses requests, including function calls and reasoning items, into chat requests. So Codex can point straight at Dynamo **(verify tool-call round trips in the lab)**. LiteLLM can also bridge. |
| **Goose moved to the Linux Foundation's Agentic AI Foundation (AAIF).** The repo is now `aaif-goose/goose` and the docs are at goose-docs.ai. | Neutral governance, Apache-2.0. |
| **Pi moved.** `badlogic/pi-mono` redirects to `earendil-works/pi`, and the npm package is now `@earendil-works/pi-coding-agent`. | |
| **Qwen Code's free Qwen OAuth tier ended on 2026-04-15.** | Students need to be configured with a custom OpenAI provider pointing at Dynamo. |
| **LiteLLM had a PyPI supply-chain compromise.** Versions 1.82.7 and 1.82.8 were backdoored on 2026-03-24 by TeamPCP and were live for about 40 minutes. | Pin versions and hashes, and prefer the official Docker image digests. Treat any host that installed those versions as compromised. |
| **Langfuse's copyright is now held by ClickHouse, Inc.** The core is still MIT, and the `ee/` directories are under a separate licence. | |
| **New in 2026: DeepSeek Harness (`dsh`)**, MIT, developer preview, about 237k stars since 2026-08-13. It has a web UI and an everything-is-a-plugin design, and uses `pi-ai` for OpenAI-compatible providers. | Interesting to watch. Its README warns of breaking changes, so don't standardise on it yet. |

### Dynamo-side prerequisites for any agent harness

- Tool calling and reasoning parsers are required for Qwen3.5. Dynamo's docs (`docs/fern/pages/use-cases/tool-calling-and-reasoning/reasoning-parsing.md`) say: `--dyn-tool-call-parser qwen3_coder --dyn-reasoning-parser qwen3`. Without them, native-tool-calling harnesses break.
- Reasoning comes back in the `reasoning_content` field. Most harnesses show it or drop it. For multi-turn agent loops, check whether the harness sends earlier reasoning back to the model. Qwen3.x chat templates generally strip past `<think>` content, so this usually doesn't matter much **(verify)**.
- Optional: `--enable-anthropic-api` exposes `/v1/messages`, which lets Anthropic-protocol clients (Claude Code, Crush `--type anthropic`, Goose Anthropic engine) connect. Claude Code is not open source, but it's a common baseline.
- FIM/autocomplete needs `/v1/completions` and a FIM-trained model. Qwen3.5-122B-A10B is a chat/agent model. For autocomplete, serve a **small dedicated FIM model** (e.g. a Qwen2.5-Coder / Qwen3-Coder base) as a second Dynamo model **(verify FIM tokens for any Qwen3.5 variant)**.
- Always set `limit.context` / `context_limit` / `max_tokens` in each harness to match what Dynamo actually serves. Many harnesses assume 128k–200k.

---

## 1. Master comparison table (coding harnesses)

"Tool calling": **native** means the harness needs the OpenAI `tools`/`tool_calls` API, so Dynamo's tool parser must work. **text** means the harness parses edits or commands out of plain text.

| Harness | License | Stars (2026-09-26) | Latest release | Form factor | Tool calling | Reasoning models | FIM autocomplete | Telemetry default → disable | Multi-user fit | Teaching transparency | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **OpenCode** (anomalyco/opencode, formerly sst) | MIT | ~210k | opencode-ai 1.18.32 (2026-09-21) | TUI, CLI (`opencode run`), desktop (beta), web, server/SDK, ACP | native | yes (variants/reasoning effort) | no | No product analytics in the binary per community audit. It does phone out for autoupdate, `models.dev` catalog fetch and share → `OPENCODE_DISABLE_AUTOUPDATE=true`, `OPENCODE_DISABLE_MODELS_FETCH=true`, `OPENCODE_DISABLE_SHARE=true` or `"share":"disabled","autoupdate":false` | Per-user local. Admin-managed config in `/etc/opencode/` overrides user config (good for lab images) | Medium-high: readable TS, plan/build agents, `opencode export` sessions | Very active |
| **Aider** | Apache-2.0 | ~49k | 0.86.2 (2026-02-12) | CLI (+ browser mode, IDE watch mode) | **text** (whole/diff/udiff/…) | yes (`--reasoning-effort`, `--thinking-tokens`, strips `<think>`) | no | Random subset asked to opt in → `--analytics-disable` (permanent) / `--no-analytics` | Per-user | **High**: prompts and edit formats visible, `.aider.chat.history.md` | Slow. See fork `cecli-dev/cecli` |
| **Cline** | Apache-2.0 (JetBrains plugin reported closed-source) | ~69k | CLI `cline` 3.0.65 (2026-09-24) | VS Code, JetBrains, CLI/TUI (headless `--json`), SDK, desktop | native for most providers. Historically XML-in-text **(verify for OpenAI-compatible)**. "Compact prompt" option for local models | yes | no | **On** by default (PostHog, anonymous, prompt on install) → toggle in settings. Also honours VS Code `telemetry.telemetryLevel=off` | Enterprise remote-config for org-wide OpenAI-compatible endpoint (SSO via WorkOS is paid). Users can always opt out | High (Plan/Act, approvals per step) | Very active |
| **Kilo Code** | MIT | ~27k | @kilocode/cli 7.8.1 (2026-09-25) | VS Code (rebuilt 2026-04-02), JetBrains, CLI (**fork of OpenCode**), cloud | native | yes | **yes** (ghost-text autocomplete in the extension; custom FIM model config **(verify)**) | **On** (PostHog `us.i.posthog.com`) → `KILO_TELEMETRY_LEVEL=off` (any value ≠ `all` disables), `experimental.openTelemetry=false` in `kilo.jsonc`, or VS Code telemetry off | Per-user | Medium | Active. Main Roo successor |
| **Roo Code** | Apache-2.0 | ~24k | n/a | VS Code | native | – | – | – | – | – | **Archived 2026-05-15** |
| **Continue.dev** | Apache-2.0 | ~36k | 2.0.0 final (2026-06-19) | VS Code, JetBrains, CLI `cn` | native (agent) / text (chat/edit) | yes | **yes** (best FIM config story historically) | Removed in 2.0.0 | Per-user | Medium | **EOL / read-only** |
| **OpenHands SDK** (`software-agent-sdk`) | MIT | ~1.2k (the SDK repo; OpenHands brand ~89k) | openhands-sdk 1.49.6 (2026-09-25) | Python SDK, Agent Server (REST/WebSocket) | native by default. `LLM(native_tool_calling=False)` switches to prompt-based function calling | yes (`reasoning_effort`, thinking modes) | no | none documented in SDK | Server mode is multi-conversation. Multi-tenant auth only in Cloud/Enterprise | **High**: event-sourced, every Action/Observation persisted | Very active |
| **OpenHands Agent Canvas** (`OpenHands/OpenHands`) | MIT (enterprise dir separate) | ~89k | v1.24 (docker) | Web GUI + backend, npm or Docker | via SDK | yes | no | **(verify)** | Single-user self-host. Multi-user = OpenHands Enterprise | High (web event stream) | Beta, active |
| **OpenHands CLI V1** | MIT | ~260 | openhands 1.16.0 (2026-05-08) | TUI | native | yes | no | – | per-user | – | **No longer maintained** |
| **Goose** (aaif-goose/goose) | Apache-2.0 | ~55k | stable channel | Desktop app, CLI, API. Rust | **native required** (without tools = chat only). "toolshim" experimental for non-tool models | yes | no | **Opt-in** (asks on first run) → `GOOSE_TELEMETRY_ENABLED=false` (env or `~/.config/goose/config.yaml`) | per-user. Custom distributions for orgs | Medium (recipes, MCP extensions) | Active, AAIF governance |
| **Codex CLI** (openai/codex) | Apache-2.0 | ~127k | @openai/codex 0.157.1 (2026-09-26) | CLI/TUI, IDE extension, app | native, **Responses API only** | yes (`model_reasoning_effort`) | no | analytics on by client default → `[analytics] enabled=false`. `feedback.enabled=false`. `check_for_update_on_startup=false` | per-user. `requirements.toml` admin layer | Medium (Rust, but `codex exec --json` and rollout JSONL are very clear) | Very active |
| **Qwen Code** (QwenLM/qwen-code) | Apache-2.0 (Gemini CLI fork) | ~28k | 0.24.6 (2026-09-26) | CLI/TUI, VS Code/Zed companions, web/desktop | native. Supports `wireApi: chat-completions` or `responses` | yes (tuned for Qwen) | no | usage statistics **on** by default → `"privacy":{"usageStatisticsEnabled":false}` or `QWEN_USAGE_STATISTICS_ENABLED=false` | per-user. System-level settings file for admins | Medium | Very active. Natural match for Qwen3.5 |
| **Pi** (earendil-works/pi, formerly badlogic/pi-mono) | MIT | ~109k | 0.87.1 (2026-09-22) | TUI, print/JSON/RPC modes, TS SDK | native. Only four tools (read/write/edit/bash). Minimal (~1k-token) system prompt | yes (`/thinking` levels) | no | install/update telemetry + attribution headers → `PI_TELEMETRY=0`. `PI_OFFLINE=1` disables catalog refresh. No built-in permission system (sandbox it) | per-user | **Very high**: tiny prompt, JSONL session tree | Very active |
| **Crush** (charmbracelet/crush) | **FSL-1.1-MIT** (source-available, becomes MIT after 2 years; non-compete clause) | ~28k | 0.96.1 (2026-09-21) | TUI | native | yes (`--can-reason`) | no | pseudonymous metrics **on** → `CRUSH_DISABLE_METRICS=1` or `DO_NOT_TRACK=1`. Provider catalog auto-update → `CRUSH_DISABLE_PROVIDER_AUTO_UPDATE=1` | per-user | Medium | Active. Config format changed to `crushrc` (Bash DSL) |
| **mini-SWE-agent** | MIT | ~8k | 2.4.6 (2026-07-23) | Python CLI (`mini`), batch (`mini-extra swebench`), library | v2: **native tool calling (bash tool) by default**. `model_class: litellm_textbased` for text/regex actions | yes (via LiteLLM) | no | none documented | batch-friendly | **Highest**: ~100-line agent, linear message history | Active. Reference harness for SWE-bench "bash-only" |
| **SWE-agent** | MIT | ~20k | GitHub releases (pip name `sweagent` on PyPI is not it) | Python CLI, batch | configurable (function-calling or thought-action text parsers) | yes | no | none | batch | High (ACI tool YAML, .traj files) | Maintained. mini-SWE-agent recommended as default |
| **Zed** (+ Agent Panel) | GPL-3.0 editor (server AGPL, some parts Apache) | ~91k | continuous | Native editor (macOS/Linux/Windows). Hosts external agents via ACP | native | yes | **yes**: `edit_predictions.provider = "open_ai_compatible_api"` (FIM via `/v1/completions`, prompt formats incl. `qwen`) | **On** → `"telemetry":{"diagnostics":false,"metrics":false}` | per-user | Medium | Very active |
| **Void** | Apache-2.0 | ~29k | – | VS Code fork | – | – | – | – | – | – | **Archived 2026-06-02** |
| **Tabby** (TabbyML) | Apache-2.0 core + `ee/` proprietary | ~34k | v0.32.0 (2026-01-25). Last push 2026-06-30 | Self-hosted server + VS Code/JetBrains/Vim plugins | n/a (completion + chat) | – | **yes** (core purpose) | usage collection **on** → `TABBY_DISABLE_USAGE_COLLECTION=1` | **Yes**: server with users, tokens, SSO (GitHub/GitLab/LDAP), admin analytics | low (product, not agent) | Slowing |
| **DeepSeek Harness** (dsh) | MIT | ~237k | dev preview | Web UI (`npx @deepseek-ai/dsh web`), desktop | native (pi-ai `openai-completions`) | yes | no | has an OTel product-telemetry plugin **(verify defaults)** | per-user | High (plugin architecture) | Preview. Breaking changes promised |
| Others worth knowing | Gemini CLI (Apache-2.0, ~107k, Google API-centric), Mistral Vibe (Apache-2.0, ~5k), Kimi CLI (Apache-2.0, **archived**), Trae Agent (MIT, stale since Feb 2026), OpenClaw / Hermes Agent (general personal agents, not coding-focused, very large star counts) | | | | | | | | | | |

---

## 2. Per-harness configuration against Dynamo (minimal, verified snippets)

Replace `HOST` with the Dynamo host. Dynamo ignores the API key unless a gateway is in front, but most clients refuse to run without one, so use a dummy key or a LiteLLM virtual key.

### 2.1 OpenCode, `opencode.json` (project root) or `~/.config/opencode/opencode.json`. Admin override: `/etc/opencode/`
```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "dynamo": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "Campus Dynamo",
      "options": { "baseURL": "http://HOST:8000/v1", "apiKey": "{env:CAMPUS_LLM_KEY}" },
      "models": {
        "Qwen/Qwen3.5-122B-A10B": { "name": "Qwen3.5 122B", "limit": { "context": 131072, "output": 16384 } }
      }
    }
  },
  "model": "dynamo/Qwen/Qwen3.5-122B-A10B",
  "small_model": "dynamo/Qwen/Qwen3.5-122B-A10B",
  "share": "disabled",
  "autoupdate": false,
  "enabled_providers": ["dynamo"]
}
```
- `@ai-sdk/openai-compatible` talks to `/v1/chat/completions`. `@ai-sdk/openai` talks to `/v1/responses`.
- Set `small_model` explicitly, otherwise title generation may try another provider.
- Also set `OPENCODE_DISABLE_MODELS_FETCH=true` to stop the `models.dev` fetches.
- Sources: https://opencode.ai/docs/providers/ , https://opencode.ai/docs/config/ , https://voodisss.github.io/opencode-privacy-fix/ , https://github.com/anomalyco/opencode/issues/5554

### 2.2 Aider, environment variables or `.aider.conf.yml`
```bash
export OPENAI_API_BASE=http://HOST:8000/v1
export OPENAI_API_KEY=dummy
aider --model openai/Qwen/Qwen3.5-122B-A10B --edit-format diff --analytics-disable
```
- To set context size and edit format for an unknown model, add `.aider.model.settings.yml` / `.aider.model.metadata.json`.
- Aider parses edits from plain text (SEARCH/REPLACE blocks), so it works even if tool parsing is broken.
- Sources: https://aider.chat/docs/llms/openai-compat.html , https://aider.chat/docs/more/analytics.html , https://aider.chat/docs/more/edit-formats.html

### 2.3 Cline
- **VS Code:** Settings ⚙ → API Provider "OpenAI Compatible" → Base URL `http://HOST:8000/v1`, API key, Model ID `Qwen/Qwen3.5-122B-A10B`. Under Model Configuration, set context window, max output tokens and "supports images".
- **CLI:** run `cline auth` interactively and choose OpenAI Compatible. Config lives in `~/.cline/data/settings/providers.json`. Headless run: `cline --json -m <model> "task"`. The flags `-P <provider> -k <key>` override the provider for one run.
- **Org-wide:** Enterprise remote configuration can set the OpenAI-compatible endpoint for all members (https://docs.cline.bot/enterprise-solutions/configuration/remote-configuration/openai-compatible/admin-configuration.md).
- **Telemetry:** PostHog, anonymous, on by default. Turn it off in Cline settings or with VS Code `telemetry.telemetryLevel: off`.
- Sources: https://docs.cline.bot/provider-config/openai-compatible , https://docs.cline.bot/cli/cli-reference.md , https://docs.cline.bot/more-info/telemetry

### 2.4 Kilo Code
- **VS Code:** Settings → Providers → "Custom provider" → Base URL, key and models. It auto-discovers models from `/v1/models`.
- **CLI:** `~/.config/kilo/kilo.jsonc`. The CLI is an OpenCode fork, so the OpenCode `provider` block above works with the same shape **(verify key names)**.
- **Telemetry:** set `KILO_TELEMETRY_LEVEL=off` (source: `packages/kilo-telemetry/src/telemetry.ts`) and/or `{"experimental":{"openTelemetry":false}}`. OTLP export turns on when `OTEL_EXPORTER_OTLP_ENDPOINT` is set.
- Sources: https://kilo.ai/docs/ai-providers/openai-compatible , https://github.com/Kilo-Org/kilocode/blob/main/packages/kilo-docs/pages/code-with-ai/platforms/cli.md

### 2.5 OpenHands SDK (Python)
```python
from openhands.sdk import LLM, Agent, Conversation, Tool
from openhands.tools.terminal import TerminalTool
from openhands.tools.file_editor import FileEditorTool
llm = LLM(model="openai/Qwen/Qwen3.5-122B-A10B", base_url="http://HOST:8000/v1",
          api_key="dummy", usage_id="agent",
          native_tool_calling=True,        # False → prompt-based function calling
          log_completions=True, log_completions_folder="logs/completions")
agent = Agent(llm=llm, tools=[Tool(name=TerminalTool.name), Tool(name=FileEditorTool.name)])
conv = Conversation(agent=agent, workspace=".", persistence_dir="runs/")   # event JSON persisted
conv.send_message("Fix the failing test"); conv.run()
```
- **Agent Canvas GUI:** Settings → LLM → Advanced → Custom Model `openai/Qwen/Qwen3.5-122B-A10B`, Base URL `http://HOST:8000/v1`, API key.
- **Legacy CLI:** config lives in `~/.openhands/agent_settings.json`. `LLM_MODEL`, `LLM_BASE_URL` and `LLM_API_KEY` are only honoured with `--override-with-envs`.
- **Evals:** `OpenHands/benchmarks` takes a JSON LLM config `{"model","base_url","api_key"}` and supports SWE-Bench, SWE-Bench Pro, GAIA, Commit0, OpenAgentSafety and ProgramBench.
- Sources: https://docs.openhands.dev/openhands/usage/llms/openai-llms , https://github.com/OpenHands/software-agent-sdk , https://github.com/OpenHands/OpenHands-CLI , https://github.com/OpenHands/benchmarks , https://www.openhands.dev/blog/use-any-coding-agent-in-openhands-with-acp

### 2.6 Goose
Option A: environment variables with the built-in openai provider.
```bash
export GOOSE_PROVIDER=openai OPENAI_HOST=http://HOST:8000 OPENAI_BASE_PATH=v1/chat/completions \
       OPENAI_API_KEY=dummy GOOSE_MODEL=Qwen/Qwen3.5-122B-A10B GOOSE_TELEMETRY_ENABLED=false
```
Option B: a custom provider file, `~/.config/goose/custom_providers/campus.json`.
```json
{ "name": "campus", "engine": "openai", "display_name": "Campus Dynamo",
  "api_key_env": "CAMPUS_LLM_KEY", "base_url": "http://HOST:8000/v1/chat/completions",
  "models": [ { "name": "Qwen/Qwen3.5-122B-A10B", "context_limit": 131072 } ],
  "supports_streaming": true, "requires_auth": true }
```
- Sources: https://goose-docs.ai/docs/getting-started/providers/ , https://goose-docs.ai/docs/guides/usage-data/ , https://github.com/aaif-goose/goose

### 2.7 OpenAI Codex CLI, `~/.codex/config.toml`
```toml
model = "Qwen/Qwen3.5-122B-A10B"
model_provider = "dynamo"
model_context_window = 131072
model_reasoning_effort = "medium"
check_for_update_on_startup = false

[model_providers.dynamo]
name = "Campus Dynamo"
base_url = "http://HOST:8000/v1"
env_key = "CAMPUS_LLM_KEY"
wire_api = "responses"          # only supported value since Feb 2026

[analytics]
enabled = false
[feedback]
enabled = false
[otel]
exporter = "none"               # or otlp-http to ship traces to Langfuse/Phoenix
```
- Dynamo serves `/v1/responses`. If a particular Responses feature is missing, put LiteLLM in between; LiteLLM bridges Responses to Chat.
- `--oss` only supports the `ollama` and `lmstudio` providers, so use a custom provider for Dynamo.
- Session transcripts are JSONL rollouts under `~/.codex/sessions/`, controlled by `history.persistence`. `codex exec --json` streams events.
- Sources: https://learn.chatgpt.com/docs/config-file/config-advanced , https://learn.chatgpt.com/docs/config-file/config-reference , https://github.com/openai/codex/discussions/7782

### 2.8 Qwen Code, `~/.qwen/settings.json` (a system-level settings file exists for admins)
```json
{
  "modelProviders": {
    "openai": [
      { "id": "Qwen/Qwen3.5-122B-A10B", "name": "Campus Qwen3.5",
        "baseUrl": "http://HOST:8000/v1", "envKey": "CAMPUS_LLM_KEY" }
    ]
  },
  "security": { "auth": { "selectedType": "openai" } },
  "privacy": { "usageStatisticsEnabled": false }
}
```
- Quick alternative: `OPENAI_BASE_URL=http://HOST:8000/v1 OPENAI_API_KEY=dummy OPENAI_MODEL=Qwen/Qwen3.5-122B-A10B QWEN_USAGE_STATISTICS_ENABLED=false qwen`
- A model entry may also set `wireApi: "responses"`.
- Sources: https://qwenlm.github.io/qwen-code-docs/en/users/configuration/auth/ , https://github.com/QwenLM/qwen-code/blob/main/docs/users/configuration/model-providers.md , https://qwenlm.github.io/qwen-code-docs/en/users/configuration/settings/

### 2.9 Pi, `~/.pi/agent/models.json`
```json
{
  "providers": {
    "dynamo": {
      "baseUrl": "http://HOST:8000/v1",
      "api": "openai-completions",
      "apiKey": "${CAMPUS_LLM_KEY}",
      "models": [ { "id": "Qwen/Qwen3.5-122B-A10B" } ]
    }
  }
}
```
- Set `PI_TELEMETRY=0` and `PI_OFFLINE=1` for air-gapped labs.
- Sessions are JSONL trees at `~/.pi/agent/sessions/--<path>--/<ts>_<id>.jsonl`.
- `pi -p` runs in print mode; `--mode json` / `--mode rpc` are for automation.
- Pi has no permission system, so run it in containers.
- Sources: https://github.com/earendil-works/pi (`packages/coding-agent/docs/models.md`, `session-format.md`, `environment-variables.md`)

### 2.10 Crush, `crushrc` (Bash DSL; `./.crushrc` > `./crushrc` > `~/.config/crush/crushrc`)
```bash
provider add campus --type openai-compat --base-url "http://HOST:8000/v1" --api-key "$CAMPUS_LLM_KEY"
model add campus/Qwen/Qwen3.5-122B-A10B --name "Qwen3.5 122B" --context-window 131072 --default-max-tokens 16384 --can-reason true
option provider-auto-update false
```
- Also set `CRUSH_DISABLE_METRICS=1` (or `DO_NOT_TRACK=1`).
- Logs go to `./.crush/logs/crush.log`.
- The licence is FSL, not OSI-approved. Fine for campus use; check it before redistributing.
- Source: https://github.com/charmbracelet/crush (README)

### 2.11 mini-SWE-agent, agent config YAML
```yaml
model:
  model_name: "openai/Qwen/Qwen3.5-122B-A10B"
  model_kwargs: { api_base: "http://HOST:8000/v1", api_key: "dummy" }
  cost_tracking: "ignore_errors"        # or export MSWEA_COST_TRACKING=ignore_errors
  # model_class: litellm_textbased       # text/regex actions if tool calling misbehaves
```
- Single task: `mini solve --config cfg.yaml`.
- SWE-bench batch: `mini-extra swebench --subset verified --output results/ -c cfg.yaml`.
- Output is `*.traj.json` with the full message list. In v2, messages keep the model's native output plus an `extra` field.
- Sources: https://mini-swe-agent.com/latest/models/local_models/ , https://mini-swe-agent.com/latest/advanced/v2_migration/ , https://github.com/SWE-agent/mini-swe-agent

### 2.12 SWE-agent
- `sweagent run --agent.model.name openai/Qwen/Qwen3.5-122B-A10B --agent.model.api_base http://HOST:8000/v1 ...` (LiteLLM under the hood) **(verify flag names against the current release)**.
- Output is `.traj` JSON with a `trajectory` of {thought, action, observation, response}, the full `history`, and `info`.
- Source: https://github.com/SWE-agent/SWE-agent

### 2.13 Zed, `settings.json`
```json
{
  "language_models": {
    "openai_compatible": {
      "campus": {
        "api_url": "http://HOST:8000/v1",
        "available_models": [ { "name": "Qwen/Qwen3.5-122B-A10B", "display_name": "Qwen3.5 122B", "max_tokens": 131072 } ]
      }
    }
  },
  "edit_predictions": {
    "provider": "open_ai_compatible_api",
    "open_ai_compatible_api": {
      "api_url": "http://HOST:8000/v1/completions",
      "model": "<small-FIM-model>",
      "prompt_format": "qwen",
      "max_output_tokens": 256
    }
  },
  "telemetry": { "diagnostics": false, "metrics": false }
}
```
- The API key goes in the environment variable `CAMPUS_API_KEY` (the provider id in upper snake case plus `_API_KEY`).
- Zed can also host OpenCode, Codex, Qwen Code, Goose and others as ACP external agents.
- Sources: https://zed.dev/docs/ai/use-api-access , https://github.com/zed-industries/zed/blob/main/docs/src/ai/edit-prediction.md , https://zed.dev/docs/telemetry

### 2.14 Tabby, `~/.tabby/config.toml` (Tabby as a campus completion server in front of Dynamo)
```toml
[model.completion.http]
kind = "vllm/completion"            # plain OpenAI /v1/completions style with FIM template
model_name = "<small-FIM-model>"
api_endpoint = "http://HOST:8000/v1"
api_key = "dummy"
prompt_template = "<|fim_prefix|>{prefix}<|fim_suffix|>{suffix}<|fim_middle|>"

[model.chat.http]
kind = "openai/chat"
model_name = "Qwen/Qwen3.5-122B-A10B"
api_endpoint = "http://HOST:8000/v1"
api_key = "dummy"
```
- Set `TABBY_DISABLE_USAGE_COLLECTION=1`.
- Tabby has users, auth tokens, SSO (GitHub/GitLab/LDAP) and per-user acceptance analytics. It's the only turnkey multi-user **autocomplete** server on this list. Its development pace has slowed (last push 2026-06-30).
- Sources: https://tabby.tabbyml.com/docs/references/models-http-api/vllm/ , https://tabby.tabbyml.com/docs/administration/usage-collection/

---

## 3. Campus-facing chat UIs and gateways

| Tool | License | Stars | Role | Custom endpoint config | Multi-user / SSO | Quotas | Logging |
|---|---|---|---|---|---|---|---|
| **Open WebUI** | BSD-3 + **branding clause** (v0.6.6+). Keep the "Open WebUI" branding unless ≤50 users/30 days or an enterprise licence is bought. v0.6.5 and earlier stay pure BSD-3 | ~153k | ChatGPT-style web UI: RAG, tools, pipelines | `OPENAI_API_BASE_URLS="http://HOST:8000/v1"` + `OPENAI_API_KEYS="dummy"` (semicolon-separated lists), or Admin → Connections | OIDC/OAuth (`OAUTH_CLIENT_ID`, `OAUTH_CLIENT_SECRET`, `OPENID_PROVIDER_URL`, `ENABLE_OAUTH_SIGNUP=true`), LDAP, trusted-header, groups/RBAC, per-model access | per-group model access. Budgets are better handled in LiteLLM | chat history in DB. OTel support **(verify env names)** |
| **LibreChat** (LibreChat-AI/LibreChat, formerly danny-avila) | MIT | ~45k | Web UI with Agents (tool calling), MCP, artifacts | `librechat.yaml` → `endpoints.custom: [{name: "Campus", apiKey: "${CAMPUS_LLM_KEY}", baseURL: "http://HOST:8000/v1", models: {default: ["Qwen/Qwen3.5-122B-A10B"], fetch: true}, titleConvo: true}]` | OpenID Connect, LDAP, social logins. Can forward `{{LIBRECHAT_USER_EMAIL}}` headers to the gateway for per-user attribution | built-in token **balance**/credits + rate limits | MongoDB transcripts |
| **LiteLLM Proxy** | MIT core, `enterprise/` dir paid | ~60k | OpenAI-compatible gateway in front of Dynamo | `model_list: [{model_name: qwen3.5, litellm_params: {model: hosted_vllm/Qwen/Qwen3.5-122B-A10B, api_base: http://HOST:8000/v1}}]` | **OSS:** virtual keys, users, teams, master key. **SSO is enterprise, free for up to 5 users**. SCIM, audit logs, org-level RBAC and per-team logging routing are enterprise | OSS: `max_budget`, `budget_duration`, `rpm_limit`, `tpm_limit`, `max_parallel_requests`, model allow-lists per key/team/user (`/key/generate`) | OSS callbacks: `success_callback: ["langfuse"]`, `callbacks: ["otel"]`, Prometheus `/metrics`, spend logs in Postgres. Can also expose `/v1/responses` and `/v1/messages` in front of chat-only backends. **Pin versions (March 2026 compromise).** |

Recommended topology:
```
students ─► Open WebUI / LibreChat (chat) ─┐
students ─► harness (OpenCode/Qwen Code/…) ┼─► LiteLLM (virtual keys, budgets, rpm/tpm, logs ─► Langfuse/OTel) ─► Dynamo :8000/v1
eval jobs ─► Harbor / mini-SWE-agent / OH-SDK ┘                                                   (tool + reasoning parsers on)
```
Give each student a LiteLLM virtual key and set it as `OPENAI_API_KEY` / `env_key` in every harness. That gives per-user quotas and trace attribution without touching Dynamo.

- Sources: https://docs.openwebui.com/license/ , https://docs.openwebui.com/features/authentication-access/auth/sso/ , https://www.librechat.ai/docs/configuration/librechat_yaml/object_structure/custom_endpoint , https://docs.litellm.ai/docs/enterprise , https://docs.litellm.ai/docs/providers/vllm , https://docs.litellm.ai/blog/security-update-march-2026

---

## 4. Trace capture and observability

| Tool | License | What it captures | How to wire it up |
|---|---|---|---|
| **Langfuse** | MIT core (`ee/` separate). © ClickHouse Inc. ~35k stars | Traces/spans/generations, sessions, users, cost, evals, datasets. Accepts OTLP at `/api/public/otel` | LiteLLM `success_callback: ["langfuse"]` (+ `LANGFUSE_HOST/PUBLIC_KEY/SECRET_KEY`), or point any harness's OTLP exporter at Langfuse. Self-host: set `TELEMETRY_ENABLED=false` |
| **Arize Phoenix** | **Elastic License 2.0** (free to self-host; can't offer as a managed service). ~11.6k stars | OpenInference spans (LLM, tool, agent, retriever) and span-level evals | OTLP endpoint. OpenInference instrumentors for LiteLLM/OpenAI/LangChain etc. |
| **OpenTelemetry GenAI semconv** | Apache-2.0 spec | `gen_ai.*` spans/events/metrics for model calls, tool execution and agent runs | Still **Development** status. Moved to its own repo `open-telemetry/semantic-conventions-genai` with v1.42.0 (2026-06-12). No stable release yet, so attribute names may change. Use `OTEL_SEMCONV_STABILITY_OPT_IN` |
| **LiteLLM logging** | – | Every request/response at the gateway (spend logs DB, callbacks) | The harness-agnostic choke point. It captures raw chat/Responses payloads (including `tool_calls` and `reasoning_content`) for **every** harness |
| Harness-native OTel | – | Codex `[otel]` (`otlp-http`/`otlp-grpc`, `log_user_prompt` opt-in). Kilo/OpenCode export OTLP when `OTEL_EXPORTER_OTLP_ENDPOINT` is set. Qwen Code has an OpenTelemetry guide. Goose supports OTLP export separately from its product telemetry | Point at a Langfuse or Phoenix OTLP endpoint |

Sources: https://github.com/langfuse/langfuse , https://github.com/Arize-ai/phoenix/blob/main/LICENSE , https://john-hodge.com/blog/opentelemetry-genai-semantic-conventions/ , https://qwenlm.github.io/qwen-code-docs/en/developers/development/telemetry/

---

## 5. Evaluation (SWE-bench / Terminal-Bench) and trajectory formats for fine-tuning

### 5.1 Harbor (harbor-framework/harbor, formerly laude-institute)
- Apache-2.0, ~5.6k stars, `harbor` 0.23.0 on PyPI (2026-09-12).
- It is the official runner for **Terminal-Bench 2.0**, and it also runs SWE-bench-style and many adapted datasets from Harbor Hub.
- It runs the same agents students use, inside sandboxes. Pre-integrated agents include `aider, claude-code, cline-cli, codex, gemini-cli, goose, mini-swe-agent, opencode, openhands, openhands-sdk, pi, qwen-coder, swe-agent, terminus-2, trae-agent, vibe, kimi-cli, hermes, openclaw, nemo-agent …`.
- **ATIF output** is supported by nearly all of these, including codex, opencode, openhands(-sdk), mini-swe-agent, swe-agent, goose, pi, qwen-coder, cline-cli and terminus-2. **Aider does not produce ATIF.**
- Example: `harbor run -d terminal-bench@2.0 -a terminus-2 -m openai/Qwen/Qwen3.5-122B-A10B --ak api_base=http://HOST:8000/v1`. Per-agent kwargs go through `--ak`, and env vars through `--ae` (e.g. `--ae OPENAI_BASE_URL=...`) **(verify per-agent kwarg names)**.
- **Terminus-2** is the reference Terminal-Bench harness. It is tmux-based and outputs JSON actions, not native tool calls. It's a good neutral baseline.
- **Harbor telemetry is ON** (PostHog) → set `HARBOR_TELEMETRY=off`.
- Sources: https://docs.harborframework.com/core-concepts/agents/pre-integrated-agents.md , https://docs.harborframework.com/core-concepts/agents/atif , https://docs.harborframework.com/telemetry/telemetry.md , https://github.com/harbor-framework/harbor/blob/main/rfcs/0001-trajectory-format.md

### 5.2 Which harness for which benchmark
| Benchmark | Common harnesses |
|---|---|
| SWE-bench Verified / "bash-only" leaderboard | **mini-SWE-agent** (official bash-only baseline, >74% with frontier models), SWE-agent, OpenHands SDK (`OpenHands/benchmarks`, ~77.6% advertised), Harbor adapters |
| SWE-bench Pro / multi-lingual | OpenHands benchmarks, mini-SWE-agent |
| Terminal-Bench 2.0 | Harbor with Terminus-2 (reference), Codex, Claude Code, OpenHands, OpenCode, Goose, mini-SWE-agent |
| GAIA / Commit0 / safety | OpenHands benchmarks |

### 5.3 Trajectory / trace formats useful for SFT/RL
| Format | Producer | Shape | SFT usefulness |
|---|---|---|---|
| **ATIF v1.0–1.7** (Agent Trajectory Interchange Format) | Harbor (converts most agents), VT Code natively | JSON: `agent{name,version,model,tool_definitions}`, `steps[{step_id, source, message, reasoning_content, tool_calls[{tool_call_id,function_name,arguments}], observation, metrics}]`, `final_metrics`, `subagent_trajectories` | **Best cross-harness normalisation.** Built for SFT and RL (token/logprob metrics). Pydantic models and a validator are included |
| mini-SWE-agent `.traj.json` | mini-SWE-agent | linear `messages` list (native model output + `extra`) + info/exit status | Nearly direct chat-format SFT data. Used by SWE-smith-style pipelines |
| SWE-agent `.traj` | SWE-agent | `trajectory` steps (thought/action/observation) + `history` messages | Well established. Many public SFT sets (e.g. SWE-smith trajectories) use it |
| OpenHands events | OpenHands SDK / Agent Server | event-sourced JSON (Action/Observation/MessageEvent) under `persistence_dir`. `log_completions=True` dumps raw LLM request/response JSON per call. Benchmarks write `output.jsonl` | Raw completion logs are exactly what the model saw, which makes them ideal for SFT |
| Codex rollouts | Codex CLI | JSONL under `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. `codex exec --json` streams events | Good. Responses-item format |
| Pi sessions | Pi | JSONL tree (`id`/`parentId`, v3) | Good. Branching is preserved |
| OpenCode sessions | OpenCode | `opencode export <session>` JSON **(verify)**. Stored under `~/.local/share/opencode` | OK |
| Gateway logs | LiteLLM → Langfuse/Phoenix/DB | every raw request/response | Harness-agnostic. The simplest way to collect campus-wide data. **Needs consent/IRB-style policy for student data.** |

---

## 6. Recommendations for a university

1. **Default student harness:**
   - **OpenCode**: MIT, most popular, admin-managed `/etc/opencode` config, no product analytics once share/autoupdate/models-fetch are off.
   - **Qwen Code**: tuned for the Qwen family. Disable usage statistics.
   - **Cline or Kilo** for VS Code users. Disable PostHog telemetry.
2. **Teaching the agent loop:**
   - **mini-SWE-agent**: about 100 lines, linear history, and it can switch between text and native tool calls to show the difference.
   - **Pi**: minimal prompt, four tools.
   - **Aider**: text edit formats, which also works when native tool calling is broken.
3. **Research, evals and data collection:**
   - **Harbor** (+ `HARBOR_TELEMETRY=off`) for Terminal-Bench and SWE-bench with the same harnesses students use, giving ATIF output.
   - **OpenHands SDK** for custom agents with `log_completions`.
   - **mini-SWE-agent** for SWE-bench.
4. **Chat:** Open WebUI (note the branding clause above 50 users; keep the branding) or LibreChat (MIT, built-in balances). Put **LiteLLM** in front for virtual keys, budgets and rate limits. SSO in LiteLLM itself is paid beyond 5 users; do SSO at the UI layer instead.
5. **Autocomplete:** Tabby (multi-user server) or Zed's `open_ai_compatible_api` edit predictions against a **separate small FIM model** on Dynamo. Continue is EOL.
6. **Avoid for new deployments:** Continue (EOL), Roo Code (archived), Void (archived), OpenHands V1 CLI (unmaintained), Kimi CLI (archived), DeepSeek Harness (preview).
7. **Telemetry checklist for lab images:**
   ```bash
   export OPENCODE_DISABLE_AUTOUPDATE=true OPENCODE_DISABLE_SHARE=true OPENCODE_DISABLE_MODELS_FETCH=true
   export KILO_TELEMETRY_LEVEL=off CRUSH_DISABLE_METRICS=1 CRUSH_DISABLE_PROVIDER_AUTO_UPDATE=1 DO_NOT_TRACK=1
   export QWEN_USAGE_STATISTICS_ENABLED=false GOOSE_TELEMETRY_ENABLED=false PI_TELEMETRY=0 PI_OFFLINE=1
   export TABBY_DISABLE_USAGE_COLLECTION=1 HARBOR_TELEMETRY=off
   ```
   - aider: `--analytics-disable`
   - Codex: `[analytics] enabled=false`
   - Zed: `telemetry.metrics/diagnostics=false`
   - Cline / VS Code: `telemetry.telemetryLevel=off`

## 7. Items to verify in the lab
- Codex against Dynamo `/v1/responses`: multi-turn function_call / function_call_output round trips and reasoning items with Qwen3.5.
- Qwen3.5-122B-A10B tool-call reliability with `qwen3_coder` parser under each harness's tool schema, especially Cline's and Goose's large tool sets.
- Whether any harness sends `reasoning_content` back to the model on later turns, and whether that matters for the Qwen3.5 template.
- Kilo CLI `kilo.jsonc` provider key names; OpenCode session export command; SWE-agent CLI flag names; Harbor per-agent `api_base` kwargs.
- Open WebUI OTel env var names; Agent Canvas telemetry defaults; DeepSeek Harness telemetry defaults.
