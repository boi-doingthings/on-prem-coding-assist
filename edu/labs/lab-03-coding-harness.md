# Lab 3 — A coding agent on your own GPUs (45–60 min)

**You will:** connect an open-source coding agent to the campus endpoint, use
it to fix a bug and add a test, and inspect what the agent actually sent to
the model.

Background: `edu/05-coding-harnesses.md`.

## 1. Point a harness at the endpoint

```bash
export CAMPUS_LLM_URL=http://127.0.0.1:8000/v1    # or the campus gateway URL
export CAMPUS_LLM_MODEL=$(curl -s $CAMPUS_LLM_URL/models | jq -r '.data[0].id')
export CAMPUS_LLM_KEY=dummy                        # a real per-user key behind the gateway
export CAMPUS_LLM_CONTEXT=32768                    # must not exceed the server's max-model-len
source config/harnesses/telemetry-off.sh

./scripts/setup-harness.sh opencode     # or: qwen, codex, pi, goose, crush, aider
```

VS Code users: Cline or Kilo → "OpenAI Compatible" provider, same URL/model.

## 2. Task: fix and test

Use the instructor's sample repository (or any small repo with a failing
test). Run the agent inside a container or a throwaway directory — agents
execute shell commands.

```bash
git clone <sample-repo> lab3 && cd lab3
opencode run "The test suite fails. Find the bug, fix it, and add a regression test. Run the tests."
```

Record: wall-clock time, did tests pass, number of model calls (see step 3).

## 3. Look inside the loop

Pick the tool that shows you the most:

- **Pi**: sessions are JSONL under `~/.pi/agent/sessions/`; `pi -p "<task>"`
  prints each step.
- **mini-SWE-agent**: `./scripts/setup-harness.sh --print mini-swe-agent`,
  run `mini`, then read the `.traj.json` — the entire message list.
- **Server side**: count requests in the Dynamo frontend log, or
  `curl -s localhost:8000/metrics | grep dynamo_frontend_requests_total`.

Answer:

1. How many model calls did one task take? How long was the *largest*
   prompt, and how much of it was repeated from the previous call?
2. Why does that repetition make **prefix caching** and **KV-aware routing**
   so valuable for agents? (Dynamo measured 85–97% prefix-cache hits on
   agent sessions.)
3. What fraction of the time was the model generating vs. the agent running
   tools? That is the *duty cycle* used in Lab 4 to turn concurrency into
   "number of students".

## 4. Stretch

- Swap harnesses (OpenCode → Aider) on the same task. Aider uses text edit
  formats instead of native tool calls — which was more reliable with this
  model?
- Run the same task against two models (e.g. gpt-oss-20b vs
  Qwen3.6-35B-A3B). Compare success, calls, tokens, and time.
