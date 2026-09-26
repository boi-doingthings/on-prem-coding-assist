# Session 4 — Student lab / hackathon (half day or 2-day event)

**Audience:** graduate and advanced undergraduate students.
**Goal:** every student leaves with a working free coding assistant and one
measured, reproducible result about inference.

## Half-day lab (3 h)

| Time | Activity |
| ---: | --- |
| 0:00 | 20-min talk: how an LLM request is served (prefill, decode, KV cache) |
| 0:20 | Get a key from the campus gateway; configure a harness (`05-coding-harnesses.md`) |
| 0:50 | Guided task: use the agent to add a feature + tests to a sample repo; record tokens and time |
| 1:40 | Benchmark challenge: run `sweep-aiperf.sh` against a dedicated benchmark endpoint; plot Pareto |
| 2:30 | Share results; how to contribute to the campus results repo |

## Hackathon tracks (2 days)

1. **Fastest correct server** — best tokens/s/GPU at ≥ 30 tok/s/user and
   p99 TTFT ≤ 2 s on the `coding-agent` profile, without failing a quality
   gate (tool-call validity + a small task pack).
2. **Best agent on a budget** — highest task-pack pass rate using the campus
   model, scored per 1M tokens consumed.
3. **Campus eval set** — build a small, licensed, de-duplicated benchmark from
   course material with a reference solution and tests.
4. **Fine-tune track** (Blackwell/Hopper sites) — LoRA a small model on a
   provided dataset and serve it as an adapter; beat the base model on the
   campus eval.

Rules: publish configs and raw artifacts (`manifest.env`, AIPerf exports);
results that don't reproduce don't count.
