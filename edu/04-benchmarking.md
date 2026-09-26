# Benchmarking self-hosted inference: users, throughput, latency

This module teaches faculty and students to answer the question every campus
asks first — *"how many students can this box serve?"* — with measurements
instead of guesses. It uses NVIDIA AIPerf against the Dynamo
OpenAI-compatible endpoint and the tools in this repository.

## 1. The five numbers that matter

| Metric | What the user feels | Typical coding-assistant target |
| --- | --- | --- |
| **TTFT** — time to first token | "Is it thinking or broken?" Dominated by *prefill* of the prompt | p99 ≤ 2 s for chat; agent turns with 30K+ token context tolerate 3–5 s |
| **ITL** — inter-token latency | Reading speed of the stream. Dominated by *decode* | ≤ 50 ms (≥ 20 tok/s/user); agents benefit from ≥ 50 tok/s/user |
| **tokens/s/user** | How long an agent step takes end to end | ≥ 20 minimum, 50–150 feels "instant" |
| **tokens/s/GPU** | How many users the hardware carries | Maximize *subject to* the two lines above |
| **error / timeout rate** | Trust | 0. A single wedge is worse than a slow system |

Report p50 and p99, never only averages. Agents make dozens of calls per task;
the task latency is governed by the tail.

## 2. Throughput vs. interactivity is a curve, not a number

Every deployment has a **Pareto curve**: as concurrency rises, total throughput
per GPU goes up while each user's tokens/s goes down. A single "tokens/s"
number is meaningless without the concurrency and per-user speed it was
measured at. `tools/summarize-aiperf.py` draws this curve:

- x-axis: output tokens/s **per user** (interactivity)
- y-axis: output tokens/s **per GPU** (efficiency / cost)
- one line per deployment choice (model, precision, TP, agg vs. disagg,
  router mode); one point per concurrency level

Pick the operating point by drawing a vertical line at your per-user SLO; the
highest point of each curve to the right of that line is the capacity of that
configuration.

## 3. From concurrency to "number of students"

AIPerf measures **concurrent in-flight requests**, not users. Convert with a
duty cycle — the fraction of wall-clock time an active user actually has a
request in flight:

```text
supported active users ≈ max SLO-passing concurrency / duty cycle
```

| Usage pattern | Duty cycle (starting assumption) | Why |
| --- | --- | --- |
| Chat UI (Open WebUI), tutoring | 0.03 – 0.10 | Users read and type far longer than the model generates |
| IDE assistant (Cline, Kilo, Zed) | 0.10 – 0.25 | Bursty, human in the loop between steps |
| Autonomous agent (OpenCode, OpenHands, Aider `--yes`) | 0.5 – 1.0 | Agent loops back to the model immediately after each tool call |
| Batch jobs (grading, synthetic data, evals) | 1.0 | Always in flight — schedule them off-peak |

These are **assumptions to replace with measurement**: once the campus
gateway (module 06) is live, compute the real duty cycle from its request logs
(sum of request durations per user ÷ session length). Always state the duty
cycle next to any "N students" claim.

Also distinguish **active** users from **enrolled** users. A 300-student course
rarely has more than 10–20% of students active in the same hour except right
before a deadline — plan the deadline peak, and use gateway rate limits to keep
it fair.

## 4. Workload shapes

The same server can look fast or slow depending on the prompt/answer shape.
`scripts/sweep-aiperf.sh` ships four profiles; always report which one you ran.

| Profile | ISL / OSL | Represents | Stresses |
| --- | --- | --- | --- |
| `chat` | 800 / 256 | Q&A, tutoring | balanced |
| `coding-agent` | 16,000 / 512 | an agent turn: repo files + tool output in, a short edit out | **prefill**, KV capacity, prefix cache |
| `long-context` | 64,000 / 256 | whole-repo / paper reasoning | prefill, KV memory |
| `decode-heavy` | 800 / 2,048 | reasoning traces, explanations | **decode**, memory bandwidth |

Real agent traffic is dominated by long, *highly repeated* prefixes (system
prompt + tool schemas + growing conversation). Synthetic random prompts defeat
the prefix cache, so they are a **pessimistic** bound for agents. The advanced
lab replays captured traces (module 07) to measure the realistic case and the
value of Dynamo's KV-aware routing.

## 5. Running a sweep

```bash
# 1. serve something (any GPU tier)
sbatch --gres=gpu:1 --export=ALL,EDU_PROFILE=config/edu-models/<model>.env deploy/edu/serve.sbatch

# 2. sweep it; the sweep stops at the first failing concurrency
DYNAMO_SERVED_MODEL=<served-name> DYNAMO_MODEL=<hf-id-for-tokenizer> \
AIPERF_GPUS=1 AIPERF_EXPECTED_TOPOLOGY=any \
SWEEP_PROFILE=coding-agent SWEEP_CONCURRENCIES="1 2 4 8 16 32 64" \
./scripts/sweep-aiperf.sh

# No Docker on the cluster? pip install aiperf, then add AIPERF_RUNNER=local

# 3. compare several sweeps on one Pareto chart
tools/summarize-aiperf.py artifacts/runs/*sweep-* --series-key series \
  --slo-tps-user 20 --slo-ttft-ms 2000 --duty-cycle 0.15 --out results/sweeps/compare
```

Outputs: a markdown table with SLO pass/fail per point, a CSV for
spreadsheets, and an SVG Pareto chart (hover a point for details).

## 6. Rules that keep results honest

1. Warm up first (compile, CUDA graphs, autotuning); never measure the first
   request after a restart.
2. Change **one** variable per comparison (model *or* precision *or* topology).
3. Sweep concurrency; never compare two systems at each one's favorite point.
4. A failed point is a failure, not "low throughput". Never average it in.
5. Record everything: image digest, model revision, flags, GPU count, CPU
   allocation, workload shape, duty-cycle assumption (`run-aiperf.sh` writes
   `manifest.env` for this).
6. Watch the host, not only the GPU. In this lab, a 2-CPU Slurm allocation made
   a B300 look 100× slower (TTFT 22 s) — request ≥ 32 CPU threads per node.
7. GPU memory "used" ≠ GPU busy. vLLM pre-allocates ~90% of memory for KV cache;
   look at utilization and throughput instead.

## 7. Case study from this lab: 4 × B300, Qwen3.5-122B-A10B NVFP4

These are real measurements from this repository (`results/`), used in the
workshop as a worked example.

| Deployment | Image | Workload | Highest safe concurrency | Output tok/s | tok/s/user p50 | TTFT p99 |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| 1 prefill + 2 decode GPUs (disagg, NIXL) | 1.3.0 | 800/64 | 6 | 514 | 145 | 441 ms |
| 2 aggregated replicas, prefix cache off | 1.3.0 | 800/64 | 12 | 975 | 140 | 995 ms |
| 1 aggregated replica, **1 GPU** | **1.5.0** | 800/64 | ≥ 32 (max tested) | 2,005 | 104 | 486 ms |

Teaching points it illustrates:

- **Per-user speed is excellent** (~140 tok/s/user, ITL ≈ 7 ms) — a 122B MoE
  with only 10B active parameters, in NVFP4 on Blackwell, decodes like a small
  model.
- **The system failed before it saturated.** On 1.3.0, past ~7 concurrent
  prefills per engine the service wedged (no bytes returned, restart
  required) while GPUs averaged only 35–60% utilization. The sweep script
  therefore stops at the first failure. Stability testing is part of
  benchmarking.
- **Disaggregation is not automatically faster.** With one prefill GPU feeding
  two decode GPUs, all prompts converge on one engine; the aggregated layout
  carried twice the safe concurrency for this short-prompt workload.
  Disaggregation pays off with long prompts and many decode replicas —
  measure it with the `coding-agent` profile.
- **Control experiments found the cause.** Non-hybrid models (Qwen3-0.6B,
  gpt-oss-20b) ran cleanly to concurrency 128 on the same image. The hybrid
  Qwen3.6-35B-A3B wedged at c8 on Dynamo 1.3.0 (vLLM 0.23) but ran cleanly to
  c128 on Dynamo 1.5.0 (vLLM 0.28). Qwen3.5-122B on 1.5.0 then served
  **2,005 out tok/s on one B300 at c32**, about 4× the best per-GPU result on
  1.3.0 (`results/dynamo-1.5-hybrid-models-2026-09-26.md`). Lesson: keep the
  engine version in every result, and re-test before blaming the hardware.

## 8. Beyond speed: quality and task success

Throughput without quality is meaningless for a coding assistant. Pair every
performance sweep with at least one quality measurement on the *same* endpoint:

- tool-call validity rate (`scripts/smoke-api.sh`, then the harness itself),
- a small fixed task pack solved by the harness (pass@1, wall-clock, tokens),
- a public benchmark subset through its standard harness (e.g. SWE-bench
  Verified via mini-SWE-agent/OpenHands, Terminal-Bench via Harbor) when time
  allows — see `05-coding-harnesses.md`.

Quantization (FP8/NVFP4/INT4) changes quality slightly and speed a lot;
measuring both on the same curve is the core lesson of this module.
