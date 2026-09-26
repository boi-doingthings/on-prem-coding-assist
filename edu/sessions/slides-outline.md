# Core deck outline: "Idle GPUs → Campus AI" (~22 slides)

One master deck. The executive briefing uses the ★ slides; the faculty
workshop uses everything. Put the site's own measured numbers (from
`results/sweeps/`) on slides 12–14 before each delivery.

| # | Slide | Content | Speaker notes / source |
| ---: | --- | --- | --- |
| 1 ★ | Title | "Your idle GPUs can power a free, private AI coding assistant — and a research program" | |
| 2 ★ | The opportunity | Campus idle GPU-hours (site's `sreport` numbers); students paying for AI subscriptions; equity of access | site profile |
| 3 ★ | What open models do now | 4–5 models vs. the tier table; one line on benchmark caveats | `02-model-catalog.md` §2–3 |
| 4 | Reading benchmarks honestly | SWE-bench Verified saturated; Terminal-Bench versions; harness effect (60.5 vs 53.7); independent SWE-rebench much lower | `02` §1 |
| 5 ★ | Licenses | clean / custom / review / avoid table | `02` §5 |
| 6 | How an LLM request is served | prefill vs. decode, KV cache, batching (diagram) | `04` §1, Lab 2 |
| 7 | Why MoE + low precision changed the economics | decode ≈ bandwidth ÷ active bytes; KV/token table (256 KiB → 6 KiB) | `03` §1, §4 |
| 8 | Your GPU tier | A100/H100/H200/B200/B300 table; precision support; starting profile per tier | `03` §1, §2, §5 |
| 9 | NVIDIA Dynamo | frontend → KV-aware router → workers; disaggregation with NIXL; planner; one API for every harness | diagram `dynamo-architecture` |
| 10 | Deploy on Slurm in one command | `sbatch … serve.sbatch`, preemptible and requeue-friendly; shared model cache | `06` §2 |
| 11 ★ | Live demo | a coding agent fixes a bug against the on-prem endpoint | Lab 3 |
| 12 ★ | "How many students?" | Pareto chart (tok/s/GPU vs. tok/s/user); SLO line; concurrency ÷ duty cycle | `04` §2–3, site sweep SVG |
| 13 | Same GPU, different workloads | chat scales to high concurrency; long agent prompts are prefill-bound (gpt-oss-20b: c128 chat vs. c4–8 agent at 2 s TTFT) | `results/sweeps/20260926-gpt-oss-20b-*` |
| 14 | Stability is part of performance | B300 case study: on Dynamo 1.3.0 the hybrid Qwen engines wedged at ~7 concurrent prefills with GPUs half idle; controls isolated the engine version; on 1.5.0 one B300 served 4× more. Chart: `compare-dynamo-1.3-vs-1.5.svg` | `04` §7, `results/dynamo-1.5-hybrid-models-2026-09-26.md` |
| 14a ★ | KV-aware routing: +51% per GPU | diagram `kv-aware-routing` + chart `routing-multiturn`; trade-off note | `08` §1 |
| 14b | Disaggregation: ratio decides | diagram `aggregated-vs-disaggregated` + charts `disagg-trace`, `disagg-multiturn` | `08` §2 |
| 14c | Conditional disaggregation (1.5) | chart `conditional-disagg` | `08` §3 |
| 14d ★ | Campus lab → AI factory | diagram `campus-to-ai-factory`; DSX OS reference | `reference/dsx-os/` |
| 15 | Harnesses students already like | OpenCode, Cline/Kilo, Codex, Qwen Code, Pi, Aider; telemetry off | `05` §2 |
| 16 ★ | Running it as a campus service | gateway architecture; keys per course; Open WebUI + SSO | `06` §1, §4 |
| 17 ★ | Governance | data stays on prem; opt-in traces; retention; academic integrity | `06` §5 |
| 18 | Teaching with it | course modules and labs; hackathon tracks | `sessions/`, `labs/` |
| 19 | Research flywheel | consented traces → eval set → LoRA/SFT/GRPO with NeMo → serve adapters in Dynamo | `07` |
| 20 | Datasets and models to start from | Nemotron open data, OLMo fully open, SWE datasets | `07` Stage 4 |
| 21 ★ | Pilot plan | Phase 0–4 timeline, success metrics, roles | `01` §3–4 |
| 22 ★ | Ask and next steps | champions, pilot node, date for the faculty workshop; NVIDIA DLI teaching kits and ambassador program | `01` §6 |

Visuals are ready: diagrams in `edu/diagrams/` (SVG + PNG), measured charts in
`results/showcase/` and `results/sweeps/`, and the whole story as one page in
`edu/showcase/index.html`.
