# Campus AI on idle NVIDIA GPUs: session kit

A program kit for NVIDIA higher-education engagements. It shows university
faculty, research-computing teams, and students how to turn idle GPU capacity
(A100 → B300) into a self-hosted open-model service with NVIDIA Dynamo. The
service powers free coding assistants and course tools, serves as a live
teaching instrument for inference engineering, and seeds research (traces →
evaluation → fine-tuning).

Everything here was built on and validated against this repository's 4×B300
Slurm lab. Where something is taken from upstream docs rather than run here,
the file says so.

## Modules (read in order)

| # | Module | Use it for |
| --- | --- | --- |
| 01 | [Program plan](01-program-plan.md) | Phases, audiences, success metrics, risks — the SA's playbook |
| 02 | [Model catalog](02-model-catalog.md) | Which open models, per GPU tier; benchmarks and licenses (snapshot 2026-09-26) |
| 03 | [GPU tiers & sizing](03-gpu-sizing.md) | A100…B300 specs, precision support, memory math, starting configs |
| 04 | [Benchmarking](04-benchmarking.md) | TTFT/ITL/throughput, Pareto curves, concurrency → users, honest reporting |
| 05 | [Coding harnesses](05-coding-harnesses.md) | OpenCode, Cline, Codex, Pi, Aider, OpenHands…; setup and evals |
| 06 | [Campus service](06-campus-service.md) | Gateway, keys/quotas, idle-cycle harvesting, governance, runbook |
| 07 | [Traces → fine-tuning](07-traces-to-fine-tuning.md) | Consent, capture, eval sets, NeMo post-training, LoRA serving |
| 08 | [Dynamo feature showcase](08-dynamo-showcase.md) | Measured gains on 8 × B300: KV-aware routing, disaggregation, conditional disaggregation |

## Presentation assets

- **[Showcase page](showcase/index.html)**: one scrollable, projectable page
  with every diagram, measured chart and takeaway. Serve it with
  `./scripts/serve-recordbook.sh` and open `/edu/showcase/`.
- **[Diagrams](diagrams/)**: 8 architecture diagrams as 16:9 SVG, plus 2× PNG
  for PowerPoint. Regenerate them with `tools/diagrams.py --png` (needs
  `pip install cairosvg`).
  `dynamo-architecture` · `request-lifecycle` · `kv-aware-routing` ·
  `aggregated-vs-disaggregated` · `showcase-topologies` · `campus-service` ·
  `research-flywheel` · `campus-to-ai-factory`
- **Measured charts**: `../results/showcase/*.svg|png` (feature showcase) and
  `../results/sweeps/*.svg` (Pareto sweeps).
- **[DSX OS reference](reference/dsx-os/)**: NVIDIA's production inference
  stack (BCM → operators → Dynamo → Grove → NVCF), used for the "campus lab →
  AI factory" slide.

## Sessions and labs

| Session | Length | Labs |
| --- | --- | --- |
| [Executive briefing](sessions/01-executive-briefing.md) | 60 min | live demo |
| [Faculty workshop](sessions/02-faculty-workshop.md) | ½ day | 2, 4 (short), 3 |
| [Engineer hands-on](sessions/03-engineer-hands-on.md) | 1 day | 1–6 |
| [Student lab / hackathon](sessions/04-student-hackathon.md) | ½–2 days | 3, 4 |

Labs: [1 First deployment](labs/lab-01-first-deployment.md) ·
[2 Sizing](labs/lab-02-sizing.md) ·
[3 Coding harness](labs/lab-03-coding-harness.md) ·
[4 Benchmark sweep](labs/lab-04-benchmark-sweep.md) ·
[5 Topology experiments](labs/lab-05-topology.md) ·
[6 Campus service](labs/lab-06-campus-service.md).
Discovery template: [site profile](sessions/site-profile-template.md).

## Tooling

| Path | What it does |
| --- | --- |
| `deploy/edu/serve.sh` | Portable single-node launcher (frontend + KV router + N replicas × TP) inside any Dynamo runtime container; no etcd/NATS required |
| `deploy/edu/serve.sbatch` | Slurm job for idle-cycle serving: Pyxis, Apptainer, or Enroot; requeue-friendly |
| `config/edu-models/*.env` | Model profiles per GPU tier (parsers, precision, flags, validation status) |
| `tools/sizing.py` | Does model X fit GPU Y? KV capacity, sessions at context, decode roofline |
| `scripts/sweep-aiperf.sh` | Concurrency sweep with workload profiles; stops at the first failure |
| `tools/summarize-aiperf.py` | Table + CSV + Pareto SVG; SLO pass/fail and users-at-duty-cycle |
| `scripts/setup-harness.sh` + `config/harnesses/` | One-command harness configs; telemetry-off script |
| `deploy/edu/gateway/` + `scripts/gateway-issue-keys.sh` | LiteLLM + Open WebUI stack; per-course keys with limits |
| `scripts/watchdog.sh` | Data-plane probe (real 1-token completion) with requeue action |
| `scripts/start-showcase.sh`, `showcase-trace.sh`, `showcase-suite.sh` | 8-GPU feature showcase: topologies, cold-cache trace/multi-turn runs, per-run cache hit rates |
| `tools/showcase-report.py`, `tools/diagrams.py` | Comparison tables and small-multiple charts; architecture diagrams |

## Validated in this lab (2026-09-26, B300)

| Profile | Image | GPUs | Tool calls | Chat sweep | Coding-agent sweep (16K/512) |
| --- | --- | ---: | --- | --- | --- |
| Qwen3-0.6B canary | 1.3.0 | 2 | ✓ hermes | 800/256: clean to c128, 18.5K out tok/s/GPU | — |
| gpt-oss-20b | 1.3.0 | 1 | ✓ harmony | 800/256: clean to c128, 16.1K out tok/s/GPU at 188 tok/s/user | clean to c64; TTFT p99 2.0 s at c16 (prefill-bound) |
| Qwen3.6-35B-A3B-FP8 | 1.5.0 | 1 | ✓ qwen3_coder | 800/256: clean to c128, 8.9K out tok/s/GPU at 99 tok/s/user | clean to c64; TTFT p99 3.3 s at c16 |
| Qwen3.5-122B-A10B-NVFP4 | 1.5.0 | 1 | ✓ qwen3_coder | 800/64: clean to c32, 2.0K out tok/s/GPU at 104 tok/s/user | — |

**Key finding:** on 1.3.0 both hybrid Qwen models wedged at ~7–8 concurrent
requests; on 1.5.0 they did not (`results/dynamo-1.5-hybrid-models-2026-09-26.md`).
Use `vllm-runtime:1.5.0` or newer.

Other profiles copy flags from upstream Dynamo recipes and are marked as such.

## Delivering at a new university

1. Send the [site profile](sessions/site-profile-template.md) and run Phase 0.
2. Fork this repository per site. Edit `scripts/env.sh` (site paths) and pick
   profiles from `config/edu-models/`.
3. Stage the model cache and runtime image on shared storage before the
   session day. Downloads are the most common workshop failure.
4. Run the canary, one target model, and one sweep the day before. Commit the
   results so the session uses local numbers.
5. Refresh `02-model-catalog.md` and `research/` if they are more than about
   two months old.
