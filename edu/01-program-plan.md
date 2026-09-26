# Program plan: "Idle GPUs → Campus AI" for higher education and research

## 1. Why

Many universities own NVIDIA GPU systems (A100, H100, H200, B200, B300) that sit
partly idle between research jobs, while students pay for — or go without —
commercial AI coding assistants. Open-weight models have closed most of the
quality gap for everyday coding and learning tasks, and NVIDIA Dynamo makes it
practical to serve them efficiently on hardware the university already owns.

The program turns idle cycles into three things at once:

1. **A service** — a free, private, OpenAI-compatible endpoint that powers
   coding assistants, chat, and course tools for students and staff.
2. **A teaching instrument** — a live production inference system that
   faculty can use to teach serving, performance engineering, and LLM systems
   (prefill/decode, KV cache, batching, quantization, routing, disaggregation).
3. **A research asset** — consented usage traces, benchmark results, and
   evaluation harnesses that become the raw material for campus research,
   and eventually for fine-tuning the university's own models.

## 2. Audiences and what each gets

| Audience | Goal | Format |
| --- | --- | --- |
| CIO / research-computing directors | Approve idle-cycle serving, policies, and scale | 60-min executive briefing |
| AI/CS/systems faculty | Adopt the stack for teaching and research; co-own the service | Half-day faculty workshop |
| HPC / research-computing engineers | Operate it: Slurm, containers, gateway, monitoring | Full-day hands-on lab |
| Students (grad + advanced undergrad) | Use it daily; learn inference by benchmarking and hacking it | Hands-on labs, hackathon, course modules |

Session agendas are in `sessions/`; lab handouts in `labs/`.

## 3. Phased rollout per university

### Phase 0 — Discovery (1–2 weeks, remote)

- Inventory: GPU model/count/memory per node, interconnect (NVLink, IB),
  scheduler (Slurm/K8s), container runtime (Pyxis/Enroot, Apptainer, Docker),
  shared storage for model weights, outbound internet/HF access.
- Utilization: median and p10 idle GPU-hours per week from Slurm accounting
  (`sacct`/`sreport`) — this is the capacity the program can claim.
- Policies: acceptable use, data classification (FERPA/GDPR/export),
  whether student prompts may be logged, identity provider (SSO).
- Champions: one faculty lead and one research-computing engineer.
- Output: a one-page site profile (template in `sessions/site-profile-template.md`).

### Phase 1 — Pilot deployment (1 week, remote or on site)

- Pick the model tier from `03-gpu-sizing.md` and the catalog in
  `02-model-catalog.md` that matches the idle hardware.
- Deploy with `deploy/edu/serve.sbatch` in a preemptible/low-priority QOS.
- Validate: health, tool calling, one coding harness end to end, one AIPerf
  sweep. Record in `results/`.
- Output: a working endpoint for ~10 pilot users and a measured Pareto curve.

### Phase 2 — Enablement sessions (1–2 days, on site preferred)

- Executive briefing → faculty workshop → engineer hands-on lab.
- Students join the hands-on labs or a hackathon in the same week.
- Output: faculty confident to demo and teach; engineers able to restart,
  upgrade, and benchmark without NVIDIA help.

### Phase 3 — Campus service (4–8 weeks)

- Put the LiteLLM gateway in front (`06-campus-service.md`): SSO, per-user
  keys, rate limits, usage dashboards, Open WebUI for non-coders.
- Opt-in trace capture with a consent notice.
- Publish harness setup guides to students (`05-coding-harnesses.md`).
- Output: steady-state service, weekly usage report, measured duty cycle.

### Phase 4 — Research flywheel (a semester or more)

- Course projects and theses on inference optimization using the live system.
- Build campus evaluation sets from anonymized traces.
- LoRA/SFT fine-tunes (e.g. on course material, a local codebase, a language
  other than English) with NeMo; serve adapters through Dynamo
  (`07-traces-to-fine-tuning.md`).
- Output: papers, open datasets, a campus-tuned model, and a case study.

## 4. Success metrics

| Metric | Pilot target | Service target |
| --- | --- | --- |
| Idle GPU-hours converted to serving | measured | ≥ 50% of idle hours |
| Weekly active users | 10–30 | 10% of target population |
| Availability during term | best effort | ≥ 99% business hours, with automatic requeue |
| p99 TTFT / p50 tok/s/user at peak | measured | ≤ 3 s / ≥ 20 tok/s |
| Faculty using it in a course | 1 | 3+ courses |
| Research outputs | — | trace dataset, eval set, 1+ fine-tune, 1+ paper/poster |
| Commercial-subscription spend avoided | — | reported per term |

## 5. Hardware tiers — one program, different starting points

The curriculum is identical everywhere; only the model and the "wow" demo
change. Details and memory math are in `03-gpu-sizing.md`.

| Site has | Serve for coding | Teaching emphasis |
| --- | --- | --- |
| A100 40/80 GB (Ampere) | small/medium MoE or dense ≤ 32B in BF16/INT4/MXFP4 | batching, KV cache, quantization without FP8 hardware |
| H100 / H200 (Hopper) | medium MoE in FP8; large MoE across 4–8 GPUs | FP8, tensor parallelism, KV routing, disaggregation |
| B200 / B300 (Blackwell) | large MoE in NVFP4 on 1–4 GPUs | NVFP4, disaggregated prefill/decode, multi-model serving |

## 6. Roles

- **NVIDIA SA**: program owner, session delivery, reference architecture,
  escalation path to Dynamo/NeMo engineering.
- **Faculty champion**: course integration, research agenda, student recruiting.
- **Research-computing engineer**: operations, Slurm policy, security review.
- **Student ambassadors** (2–4 per campus): office hours, harness guides,
  benchmark maintenance — a natural fit for the NVIDIA Student/University
  Ambassador programs and DLI teaching kits.

## 7. Risks and mitigations

| Risk | Mitigation |
| --- | --- |
| Serving steals cycles from research | Preemptible QOS + `--requeue`; serve only in declared windows; shared model cache makes restart cheap |
| Engine wedges under load (seen in this lab) | Sweep before launch; gateway concurrency cap below the measured cliff; health-probe + auto-restart |
| Student data leakage / compliance | Opt-in trace logging, default retention limits, no training on data without consent, on-prem only |
| Model licenses | Prefer Apache-2.0/MIT/NVIDIA Open Model License; review each license in `02-model-catalog.md` |
| Academic integrity concerns | Faculty-configurable per-course keys; usage visible to instructors only with policy approval |
| Stale software | Pin image digests and model revisions; quarterly upgrade window with a regression sweep |
| Only one champion | Train two engineers and a student ambassador team per site |

## 8. What to leave behind at every site

- This repository (forked per site) with the site profile, model profiles,
  and benchmark results committed.
- A running endpoint and gateway with dashboards.
- Recorded sessions and slides.
- A named NVIDIA contact and a quarterly check-in on usage and research.
