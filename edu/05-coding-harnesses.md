# Open coding harnesses on the campus endpoint (snapshot: 2026-09-26)

A *harness* (agent, IDE extension, or CLI) turns a model endpoint into a
coding assistant: it builds the prompt, exposes tools (read/edit files, run
shell commands, search), and loops until the task is done. Every harness below
speaks the OpenAI-compatible API that Dynamo serves, so students keep their
favorite tool and the university keeps the model.

## 1. What the endpoint must provide

| Requirement | How in Dynamo | Check |
| --- | --- | --- |
| Native tool calling | worker flags `--dyn-tool-call-parser <model parser>` | `scripts/smoke-api.sh` → `finish_reason: tool_calls` |
| Reasoning separated from the answer | `--dyn-reasoning-parser <parser>` → `reasoning_content` | reply text contains no `<think>` |
| Chat Completions API | `/v1/chat/completions` (default) | OpenCode, Aider, Cline, Kilo, Qwen Code, Pi, Goose, Crush |
| Responses API | `/v1/responses` (built in) | **Codex CLI** (Responses-only since Feb 2026) |
| Anthropic Messages API | frontend `--enable-anthropic-api` → `/v1/messages` (experimental) | Anthropic-protocol clients, e.g. Claude Code as a baseline |
| Autocomplete (FIM) | a **separate small FIM model** on `/v1/completions` | Zed edit predictions, Tabby, Kilo |
| Honest context limits | `--max-model-len` equals what harness configs declare | agents compact correctly instead of overflowing |

Parser names per model family are in `config/edu-models/*.env` and
`upstream/dynamo/docs/fern/pages/use-cases/tool-calling-and-reasoning/`.

## 2. Which harness for whom

| Harness | License | Form | Tools | Best for | Telemetry off |
| --- | --- | --- | --- | --- | --- |
| **OpenCode** | MIT | TUI, desktop, web, SDK | native | **default student agent**; admins can pin config in `/etc/opencode/` | `OPENCODE_DISABLE_{AUTOUPDATE,SHARE,MODELS_FETCH}=true` |
| **Qwen Code** | Apache-2.0 | CLI/TUI + VS Code/Zed | native | Qwen-family models (tuned prompts) | `privacy.usageStatisticsEnabled=false` |
| **Cline** | Apache-2.0 | VS Code, JetBrains, CLI | native | VS Code users; plan/act with approvals is a good fit for teaching | VS Code `telemetry.telemetryLevel=off` |
| **Kilo Code** | MIT | VS Code, JetBrains, CLI | native (+ autocomplete) | Roo Code successor | `KILO_TELEMETRY_LEVEL=off` |
| **Codex CLI** | Apache-2.0 | CLI/TUI, IDE | native, Responses | students who already know Codex | `[analytics] enabled=false` |
| **Goose** | Apache-2.0 (Linux Foundation AAIF) | desktop, CLI | native | non-CS users; MCP extensions | `GOOSE_TELEMETRY_ENABLED=false` |
| **Pi** | MIT | TUI, JSON/RPC | native, 4 tools | **teaching the agent loop**: ~1K-token system prompt, JSONL sessions. Validated in this lab | `PI_TELEMETRY=0 PI_OFFLINE=1` |
| **Aider** | Apache-2.0 | CLI | **text** edit formats | works even when tool calling is flaky; transparent prompts. Maintenance mode (fork: cecli) | `--analytics-disable` |
| **mini-SWE-agent** | MIT | Python CLI/batch | native or text | **teaching + SWE-bench evals**: ~100-line agent | none |
| **OpenHands SDK** | MIT | Python SDK, agent server | native or prompt-based | research, custom agents, evals, trace logging | none |
| **Crush** | FSL-1.1 (source-available) | TUI | native | terminal enthusiasts | `CRUSH_DISABLE_METRICS=1` |
| **Zed** | GPL-3.0 | editor | native + FIM | autocomplete against a small FIM model | `telemetry.{metrics,diagnostics}=false` |
| **Tabby** | Apache-2.0 core | self-hosted server | FIM + chat | campus-wide autocomplete with SSO | `TABBY_DISABLE_USAGE_COLLECTION=1` |

**Avoid for new deployments:** Continue.dev (acquired, end-of-life June
2026), Roo Code (archived May 2026), Void (archived June 2026), the OpenHands
V1 CLI (unmaintained), Kimi CLI (archived), and DeepSeek Harness (developer
preview with breaking changes).

**Suggested defaults:** OpenCode for the terminal, Cline or Kilo for VS Code,
and Pi, mini-SWE-agent, and Aider for teaching how agents work.

## 3. Setup in one command

Templates live in `config/harnesses/`. The renderer fills in URL, model, and
context, backs up any existing file, and never writes the key:

```bash
export CAMPUS_LLM_URL=https://llm.<campus>.edu/v1        # gateway or Dynamo frontend
export CAMPUS_LLM_MODEL=Qwen/Qwen3.5-122B-A10B            # GET $CAMPUS_LLM_URL/models
export CAMPUS_LLM_CONTEXT=131072 CAMPUS_LLM_MAX_OUTPUT=16384
export CAMPUS_LLM_KEY=<personal key from the gateway>
source config/harnesses/telemetry-off.sh

./scripts/setup-harness.sh opencode     # or: codex, qwen, pi, goose, crush, aider, aider-metadata
./scripts/setup-harness.sh --print zed  # templates to merge by hand: zed, mini-swe-agent
```

VS Code extensions (Cline, Kilo): Settings → API provider "OpenAI Compatible"
→ Base URL `$CAMPUS_LLM_URL`, API key, model ID, then set context window and
max output to match the server.

The OpenHands SDK example with full LLM request logging is
`config/harnesses/openhands_sdk_example.py`.

## 4. Classroom patterns

- **Per-course keys** from the gateway (`06-campus-service.md`): instructors
  can set budgets, cut access during exams, or allow only a teaching model.
- **Explain the loop before using it.** Run Pi or mini-SWE-agent with verbose
  output and have students annotate one trajectory: prompt → tool call →
  observation → next call. Then switch to OpenCode for productivity.
- **Compare tool-calling styles.** Run mini-SWE-agent with native tools, then
  with `model_class: litellm_textbased`, and discuss which is more robust
  and why.
- **Sandbox agents.** Pi and most CLIs execute shell commands. Run them in a
  container or a throwaway VM/dev node, never on a shared login node.
- **Academic integrity** is a course policy, not a technical control. The
  gateway gives visibility (usage per key) that faculty can choose to use
  under the campus policy.

## 5. Evaluating models with the same harnesses

| Benchmark | Harness | Command sketch |
| --- | --- | --- |
| Terminal-Bench 2.x | **Harbor** (official runner; ~40 built-in agents incl. opencode, codex, openhands-sdk, mini-swe-agent, pi, qwen-coder, terminus-2) | `HARBOR_TELEMETRY=off harbor run -d terminal-bench@2.0 -a terminus-2 -m openai/<model> --ak api_base=$CAMPUS_LLM_URL` (check per-agent kwargs) |
| SWE-bench Verified / bash-only | **mini-SWE-agent** | `mini-extra swebench --subset verified --slice 0:50 -c mini-swe-agent.yaml -o runs/` |
| SWE-bench Pro, GAIA | `OpenHands/benchmarks` | JSON LLM config `{model, base_url, api_key}` |
| Model-card accuracy check (GPQA, MMLU, LiveCodeBench) | `upstream/dynamo/recipes/accuracy/` (AIPerf accuracy mode) or NeMo Evaluator | point at the endpoint, compare to card |

Harbor exports **ATIF** (Agent Trajectory Interchange Format) for almost every
agent. That gives one normalized trajectory format for later fine-tuning
(`07-traces-to-fine-tuning.md`). Start with a 20–50-task slice; full runs take
hours and should be scheduled off-peak.

## 6. Status notes

- **Codex → Dynamo:** Dynamo implements `/v1/responses`, but verify
  multi-turn `function_call`/`function_call_output` round trips with your model
  before recommending Codex to a class. LiteLLM can also bridge Responses to
  Chat Completions.
- **Pi → Dynamo:** validated in this lab (Qwen3.5-122B via
  `config/pi-models.json`). Dynamo also publishes a Pi plugin at
  github.com/ai-dynamo/agent-plugins.
- **Qwen Code:** the free Qwen OAuth tier ended 2026-04-15, so students must
  use the campus provider configuration.
- **Unverified config keys:** Kilo CLI's `kilo.jsonc` provider keys, SWE-agent
  CLI flags, and Harbor's per-agent `api_base` kwargs. Check these against
  current docs before a workshop.

Sources (checked 2026-09-26): opencode.ai/docs, aider.chat/docs,
docs.cline.bot, kilo.ai/docs, docs.openhands.dev, goose-docs.ai,
github.com/openai/codex, github.com/QwenLM/qwen-code, github.com/earendil-works/pi,
github.com/charmbracelet/crush, mini-swe-agent.com, zed.dev/docs,
tabby.tabbyml.com, docs.harborframework.com, and the Dynamo docs page
`use-cases/agents/agent-harnesses.mdx`.
