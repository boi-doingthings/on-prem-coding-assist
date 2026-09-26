# Session 3 — Research-computing engineer hands-on (full day)

**Audience:** HPC/research-computing engineers who will operate the service;
motivated grad students.
**Goal:** participants can deploy, benchmark, operate, and upgrade the service
without NVIDIA assistance.
**Setup:** one GPU node per 2–3 participants (any tier), repository cloned,
model cache pre-staged (`scripts/download-model.sh`), runtime image pulled.

| Time | Lab | Outcome |
| ---: | --- | --- |
| 09:00 | Intro and site walkthrough | Everyone knows the node types, QOS, storage paths |
| 09:30 | Lab 1 — First deployment | `deploy/edu/serve.sbatch` with a small model; health + tool-call smoke |
| 10:30 | Lab 2 — Sizing and choosing a model | `tools/sizing.py`; deploy the site's target model; read engine KV log vs. estimate |
| 11:30 | Lab 3 — Coding harness end to end | OpenCode/Aider/Continue against the endpoint; fix a bug in a sample repo |
| 12:30 | *Lunch* | |
| 13:30 | Lab 4 — Benchmark sweep | `scripts/sweep-aiperf.sh` chat + coding-agent profiles; Pareto chart; find the safe concurrency |
| 14:45 | Lab 5 — Topology experiments | replicas vs. TP; KV router vs. round-robin; (Hopper/Blackwell) agg vs. disagg |
| 16:00 | Lab 6 — Operating a campus service | LiteLLM gateway, keys, limits, Open WebUI, Prometheus; opt-in traces |
| 17:00 | Runbook review | Restart, requeue, upgrade, rollback, incident drill (kill a worker mid-sweep) |

Handouts: `../labs/`.
