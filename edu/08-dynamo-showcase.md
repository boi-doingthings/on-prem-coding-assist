# Dynamo feature showcase on 8 × B300: measured gains

This module is the "cutting edge" part of the faculty workshop. Every number
comes from this repository's 8 × B300 node (job 8363, 2026-09-26). It uses the
same model, the same Dynamo build, and cold caches for every run. Only the
serving feature under discussion changes. Present the trade-offs as well as
the wins: that is what makes the results credible to researchers.

**Setup.** `nvidia/Qwen3.5-122B-A10B-NVFP4` (122B MoE, 10B active, hybrid
DeltaNet attention) on `vllm-runtime:1.5.0` (vLLM 0.28). The launcher is
`deploy/edu/serve.sh` with etcd discovery (`scripts/start-showcase.sh`), and
the client is AIPerf 0.12. Each run uses a fresh random seed, which gives
identical prompt structure with new token content, so every run starts cold.
Engine prefix-cache hit rates come from each worker's `vllm:prefix_cache_*`
counters. Raw artifacts are in `artifacts/runs/*showcase-*`; the curated
tables and charts are in `results/showcase/`.

**Two workloads**

| Workload | What it is | Why |
| --- | --- | --- |
| **Agentic trace** | 800 requests from NVIDIA's agentic coding trace (the one upstream used for this model on B200): median 64K-token prompts, 512-token blocks with shared prefixes, output capped at 1,024 tokens | realistic long prompts; most reuse comes from 4 shared system/tool prefixes |
| **Multi-turn sessions** | 128 sessions × 6 turns: 4K shared system prompt + 30K private context per session + 1K new tokens and 300 output per turn; history accumulates | the coding-agent pattern: every turn resends a growing private conversation |

Diagrams to show alongside: `diagrams/dynamo-architecture`,
`kv-aware-routing`, `aggregated-vs-disaggregated`, and `showcase-topologies`.

## 1. KV-aware routing vs round-robin

Same 8 aggregated workers (TP1 each). Two frontends serve them: the KV-aware
router on `:8000` and round-robin on `:8001`. Only the router differs.

**Multi-turn agent sessions** (`results/showcase/routing-multiturn.svg`)

| Concurrent sessions | Router | Cache hit | TTFT p50 | ITL p50 | Output tok/s/GPU | Request latency p50 |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 32 | **KV-aware** | **70%** | **0.39 s** | **7.9 ms** | **382** | **2.87 s** |
| 32 | round-robin | 34% | 0.72 s | 11.1 ms | 283 | 3.98 s |
| 64 | **KV-aware** | **67%** | **0.43 s** | **11.0 ms** | **532** | **3.90 s** |
| 64 | round-robin | 33% | 0.74 s | 16.9 ms | 353 | 5.89 s |

**Headline: +35–51% throughput per GPU, 1.7–1.8× faster first token, 1.4–1.5×
faster requests.** The GPUs, model and engine were unchanged; the router alone
doubled cache reuse.

**Agentic trace** (`results/showcase/routing-trace.svg`)

| Concurrency | Router | Cache hit | TTFT p50 / p99 | ITL p50 | Output tok/s/GPU |
| ---: | --- | ---: | ---: | ---: | ---: |
| 32 | KV-aware | 68% | 0.27 / 6.4 s | 8.6 ms | 370 |
| 32 | round-robin | 63% | 0.26 / 7.2 s | 7.4 ms | 342 |
| 64 | KV-aware | 70% | 0.32 / 6.6 s | 13.2 ms | 528 |
| 64 | round-robin | 63% | 0.28 / 8.7 s | 9.7 ms | 437 |
| 128 | KV-aware | 69% | 0.44 / 8.9 s | 20.6 ms | 650 |
| 128 | round-robin | 63% | 0.90 / 10.8 s | 18.3 ms | 571 |

**Why the trace gain is smaller (+8% to +21%).** This trace's reuse is
dominated by four shared system/tool prefixes, and each B300 caches 13.5M
tokens. Under round-robin, every worker ends up holding those shared prefixes
anyway. The router's advantage lies in *session-private* context, which is
exactly what multi-turn agents generate.

**Honest trade-off.** KV-aware routing concentrates load on the workers that
hold hot prefixes, so per-token latency (ITL) was 11–26% worse on the trace.
Dynamo exposes the balance as knobs (`--router-kv-overlap-score-credit`,
`--router-temperature`, load weights), which makes a good student exercise.

## 2. Aggregated vs disaggregated prefill/decode

Same 8 GPUs and KV-aware router. Aggregated means 8 × (prefill + decode).
Disaggregated splits a prefill pool from a decode pool, with KV moved over
NIXL (NVLink on this node).

**Agentic trace** (`results/showcase/disagg-trace.svg`)

| Concurrency | Layout | TTFT p50 | ITL p99 | Output tok/s/GPU | Request latency p50 |
| ---: | --- | ---: | ---: | ---: | ---: |
| 64 | Aggregated × 8 | **0.32 s** | 88 ms | 528 | 7.61 s |
| 64 | Disagg 2P + 6D | 5.67 s | **10 ms** | 416 | 9.85 s |
| 64 | **Disagg 4P + 4D** | 0.71 s | 12 ms | **594** | **6.15 s** |
| 128 | Aggregated × 8 | **0.44 s** | 198 ms | 650 | 12.85 s |
| 128 | Disagg 2P + 6D | 13.99 s | **9 ms** | 418 | 17.70 s |
| 128 | **Disagg 4P + 4D** | 3.57 s | 20 ms | **674** | **12.05 s** |

**Multi-turn sessions** (`results/showcase/disagg-multiturn.svg`)

| Sessions | Layout | TTFT p50 | ITL p99 | Output tok/s/GPU | Request latency p50 |
| ---: | --- | ---: | ---: | ---: | ---: |
| 32 | Aggregated × 8 | 0.39 s | 13.0 ms | 382 | 2.87 s |
| 32 | Disagg 2P + 6D | 0.59 s | **6.7 ms** | 348 | **2.48 s** |
| 32 | **Disagg 4P + 4D** | **0.38 s** | 7.2 ms | **416** | 2.49 s |
| 64 | Aggregated × 8 | **0.43 s** | 19.8 ms | 532 | 3.90 s |
| 64 | Disagg 2P + 6D | 0.94 s | **8.4 ms** | 430 | **3.18 s** |
| 64 | **Disagg 4P + 4D** | 0.64 s | 9.1 ms | **561** | 3.20 s |

**What to teach**

1. **Disaggregation removes prefill/decode interference.** Aggregated
   workers stall every stream while they prefill a 64K prompt: ITL p99 rose
   to 88–198 ms. Dedicated decode GPUs kept ITL p99 at 9–20 ms, a 7–22× smoother
   stream.
2. **The prefill:decode ratio decides who wins.** 2P + 6D starves prefill on
   64K prompts: TTFT reached 5.7–14 s and throughput per GPU fell 21–36%.
   4P + 4D beats 8 aggregated replicas on throughput (+4–12% trace, +5–9%
   sessions) *and* request latency (up to 19% faster).
3. **Sizing the pools is a real optimization problem.** Dynamo's SLA planner
   does it automatically on Kubernetes, and AISimulate searches it offline.
   Here students can find it by sweeping xPyD.
4. The upstream B200 recipe for this model reported the opposite verdict
   (aggregated 22% ahead per GPU). Different hardware, trace sampling, OSL cap
   and ratio change the answer, so measure on your own hardware.

## 3. Conditional disaggregation (Dynamo 1.5, experimental)

Same 2P + 6D workers, with decode-side KV events enabled. Two frontends
serve them: plain disaggregation on `:8000`, and
`--router-conditional-disagg` (default policy `isl_bounding`: bypass when
uncached prompt < 2,048 tokens and < 70% of the prompt) on `:8002`. The
router logged 860 requests routed straight to decode workers
("Conditional disagg routing to decode worker … net_new_tokens=1514").

| Workload | Router | TTFT p50 | ITL p99 | Output tok/s/GPU | Request latency p50 |
| --- | --- | ---: | ---: | ---: | ---: |
| Agentic trace, c64 (prefill **saturated**) | plain disagg | 4.90 s | **9.1 ms** | 421 | 9.93 s |
| | **conditional** | **0.42 s** | 27.5 ms | 428 | **7.64 s** |
| Sessions, c32 (prefill has headroom) | **plain disagg** | **0.57 s** | **6.8 ms** | **352** | **2.45 s** |
| | conditional | 0.71 s | 11.3 ms | 340 | 3.00 s |
| Sessions, c64 | **plain disagg** | **0.62 s** | **8.4 ms** | **435** | **2.96 s** |
| | conditional | 0.73 s | 17.0 ms | 403 | 3.59 s |

Charts: `results/showcase/conditional-disagg.svg` and `conditional-disagg-multiturn.svg`.

**What to teach**

- When the prefill pool is the bottleneck, conditional disaggregation
  **cut TTFT p50 11.7× (4.9 s → 0.42 s) and request latency 23%** by letting
  cache-hit turns prefill locally on idle decode capacity.
- When prefill has headroom, the same default thresholds **hurt**: moving
  1.5–2K-token prefills onto decode GPUs brought back the interference that
  disaggregation removes (ITL p99 up to 2×, requests 18–22% slower).
- It is marked experimental upstream for exactly this reason. Tune
  `eff_isl_threshold`, `prefill_busy_threshold` and `decode_busy_threshold`
  (policy `isl_or_load`) for your own workload. That makes a good graduate
  systems project.

## 4. Multi-model serving and the post-training loop

One Dynamo frontend (`:8000`) served **two models at once**: the Nemotron 3.5
Lightning BF16 teacher on GPUs 0–3, and a structured-pruned student from the
companion `workshop-contents` prune → distill experiment on GPUs 4–7.
Each model registers in its own Dynamo namespace, and the frontend discovers
both through etcd. `/v1/models` lists both, and clients choose one per
request (`scripts/start-model-pair.sh`). A campus can use exactly this
pattern to serve a general model and a course-tuned model side by side.

| Model | Params (total / active) | Checkpoint | Output tok/s/GPU at c128 / c256 | tok/s/user p50 at c128 | Quality check |
| --- | --- | ---: | ---: | ---: | --- |
| Teacher (Nemotron 3.5 Lightning BF16) | 31B / 3B | 62 GB | 2,927 / 5,264 | 106 | correct `is_prime` |
| Pruned student (Minitron, not yet distilled) | 18B / 2.5B | 33 GB | **3,328 / 6,159** | **127** | degenerate ("code code code…") |

Chart: `results/showcase/nemotron-teacher-vs-pruned.svg` (chat profile,
4 × B300 each, Dynamo 1.5.0 stock image).

**What to teach:** pruning bought 8–17% more throughput per GPU, 11–21%
faster per-user decode at high load, and a 45% smaller checkpoint. Quality
collapsed, though. That is why the NVIDIA recipe continues with
teacher-student **distillation** (Megatron-Bridge + ModelOpt), then NeMo
Evaluator, and only then serving. The same sweep and accuracy gate show when
a campus-made model is ready to replace the teacher.

## 5. Engine version matters: the hybrid-model fix

On Dynamo 1.3.0 (vLLM 0.23), hybrid Gated-DeltaNet models (Qwen3.5, Qwen3.6)
stopped returning tokens at about 7–8 concurrent requests. On 1.5.0 (vLLM
0.28) they served cleanly, and one B300 delivered 2,005 output tok/s at c32
for this model (`results/dynamo-1.5-hybrid-models-2026-09-26.md`). Every
number in this module is from 1.5.0.

## 6. Reproduce it

```bash
docker compose -f deploy/local/compose.yaml up -d nats etcd      # KV events via etcd/NATS
./scripts/start-showcase.sh agg8          # or disagg-2p6d | disagg-4p4d | cdisagg-2p6d
./scripts/wait-ready.sh 8
./scripts/showcase-suite.sh <label> <seed-base>       # trace c64/c128 + sessions c32/c64
SHOWCASE_URL=http://127.0.0.1:8001 SHOWCASE_LABEL=agg8-rr ./scripts/showcase-trace.sh   # round-robin A/B
tools/showcase-report.py --series agg8-kv,agg8-rr --out results/showcase/<name> --png
```

The agentic trace is fetched from the Dynamo repository's Git LFS
(`recipes/kimi-k2.6/perf/traces/64k_400_90kv_agent_new_noschedule_short_15perc.jsonl`,
sha256 `f20d3f2b…79d0`). Rows longer than 250K tokens are dropped because
they exceed the model's context.

**Caveats.** These are single-node, single-model runs with 1–2 repetitions
per point. Output was capped at 1,024 tokens for the trace, and requests used
`ignore_eos`. Cache hit rates are engine counters summed over workers, and in
disaggregated mode they include decode-side lookups. Treat differences under
about 5% as noise.
