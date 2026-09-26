# Session 1 — Executive briefing (60 min)

**Audience:** CIO, research-computing director, dean/associate dean for research,
department chairs, IT security.
**Goal:** approval to run a pilot on idle GPU capacity and to name champions.

| Time | Segment | Content | Artifact |
| ---: | --- | --- | --- |
| 0–10 | The opportunity | Idle GPU-hours on campus (bring their `sreport` numbers if available); student spend on AI subscriptions; equity of access | `01-program-plan.md` §1 |
| 10–20 | What open models can do now | Benchmark table: best open models vs. frontier on coding/reasoning; license overview | `02-model-catalog.md` |
| 20–30 | Live demo | A coding agent (OpenCode or Pi) fixing a bug in a small repo against the on-prem endpoint; show the Grafana/usage view | `labs/lab-03-coding-harness.md` |
| 30–40 | What it costs and what it serves | Pareto chart from the lab; "N students at SLO" with the duty-cycle assumption stated; preemptible serving so research always wins | `04-benchmarking.md` §3, §7 |
| 40–50 | Governance | Data stays on prem, opt-in logging, per-course keys, license review, academic-integrity options | `06-campus-service.md` |
| 50–60 | Ask | Pilot scope (1 node, 1 semester), champions, success metrics, next date for faculty workshop | `01-program-plan.md` §3–4 |

**Leave behind:** one-page summary, the site-profile template, and the pilot
success metrics.

**Speaker notes**

- Lead with *their* idle numbers, not NVIDIA's roadmap.
- Show a failure honestly (the concurrency wedge in §7 of the benchmarking
  guide) — it builds trust and justifies the benchmarking discipline.
- Position research first: serving is preemptible and shares a model cache, so
  a research job reclaiming the node costs the service a few minutes.
