# Non-Kubernetes experiment matrix — 2026-09-23

All measurements use NVIDIA AIPerf 0.12.0 against
`Qwen/Qwen3.5-122B-A10B` from the NVFP4 checkpoint. Requests are streaming
chat completions with server-reported token counts, temperature 0,
`ignore_eos=true`, seed 42, and zero ISL/OSL standard deviation.

The nominal ISL is the synthetic prompt target. The server-observed ISL is
about ten tokens larger because the chat template adds framing tokens. Thus
the 800-token workload measured 810.1–810.2 tokens and the 8192-token workload
measured 8202.2 tokens. OSL is exact because `ignore_eos=true` forces the
configured output length.

## Disaggregated 1P/2D results

| Experiment | Measured requests | Result | Req/s | Output tok/s | TTFT avg/p99 | ITL avg | Latency avg/p99 |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| c4, ISL 800 / OSL 64, sustained | 128 | 128/128 | 5.96 | 381.70 | 225/357 ms | 6.98 ms | 665/869 ms |
| c4, ISL 8192 / OSL 64 | 32 | 32/32 | 4.43 | 283.68 | 420/627 ms | 6.76 ms | 846/1087 ms |
| c4, ISL 800 / OSL 512 | 32 | 32/32 | 1.01 | 517.16 | 269/401 ms | 7.01 ms | 3853/4455 ms |
| c5, ISL 800 / OSL 64 | 40 | 40/40 | 6.53 | 418.06 | 297/397 ms | 7.09 ms | 743/866 ms |
| c6, ISL 800 / OSL 64 | 48 | 48/48 | 8.03 | 513.69 | 300/441 ms | 6.90 ms | 734/865 ms |
| c7, ISL 800 / OSL 64 | first burst | **1 valid, 7 timeouts** | — | — | — | — | — |
| c8, ISL 800 / OSL 64 | first burst | **0 valid, 8 timeouts** | — | — | >120 s | — | >120 s |

The c7 run and a bounded c1 probe after it prove that this is a persistent
data-plane wedge, not ordinary queueing: six requests timed out together at
30 seconds, the seventh timed out one second later, and a new single request
then returned no bytes. Discovery remained healthy. A process restart was
required.

## Aggregated controls

Two TP1 aggregate workers ran on GPUs 0 and 1. This removes NIXL KV transfer
and the dedicated prefill engine while retaining the checkpoint, vLLM engine,
hybrid DeltaNet/attention cache, Dynamo frontend/router, and AIPerf workload.

| Prefix cache | Concurrency | Measured requests | Result | Req/s | Output tok/s | TTFT avg/p99 | Latency avg/p99 |
| --- | ---: | ---: | --- | ---: | ---: | ---: | ---: |
| on | 8 | 64 | 64/64 | 8.23 | 526.94 | 294/1366 ms | 949/1986 ms |
| on | 16 | first burst | **0/16; all timed out** | — | — | >30 s | >30 s |
| off | 12 | 96 | 96/96 | 15.24 | 975.42 | 263/995 ms | 764/1401 ms |
| off | 14 | 28 | **7/28; 21 timed out** | invalid | invalid | — | — |
| off | 16 | first burst | **0/16; all timed out** | — | — | >30 s | >30 s |

Disabling prefix caching did not remove the c16 failure, so prefix caching is
not the primary cause. The two-replica c12/c14 boundary and the 1P/2D c6/c7
boundary point to a per-engine burst threshold around seven concurrent
prefills for this software/model configuration. NIXL/disaggregation lowers the
global safe concurrency because all prompts converge on one prefill engine,
but the aggregate control proves that NIXL is not necessary to trigger the
higher-concurrency wedge. This is a strong localization result, not yet a root
cause; vLLM/Dynamo engine traces are needed to identify the exact stalled
kernel or scheduler state.

## B300 utilization

Host `nvidia-smi` was sampled once per second around each profile window.

| Workload | GPU 0 | GPU 1 | GPU 2 | GPU 3 |
| --- | --- | --- | --- | --- |
| 1P/2D c4 sustained | prefill 11.7% avg / 58% max | decode 50.2% / 81% | decode 46.6% / 72% | unused, 0% |
| 1P/2D prefill-heavy | prefill 37.1% / 99% | decode 51.1% / 81% | decode 36.6% / 71% | unused, 0% |
| 1P/2D decode-heavy | prefill 2.6% / 32% | decode 62.7% / 83% | decode 58.1% / 73% | unused, 0% |
| aggregate c8, prefix on | 44.2% / 98% | 26.7% / 65% | unused, 0% | unavailable, 0% |
| aggregate c12, prefix off | 34.6% / 97% | 63.5% / 99% | unused, 0% | unavailable, 0% |

The allocation is not fully utilized. The 1P/2D layout uses only three GPUs;
GPU 3 still contains another user's stale `cuopt_server`. Even the used GPUs
show substantial average compute headroom. Approximately 245 GiB allocated per
worker is mainly model and reserved KV-cache capacity, not sustained compute
load. The concurrency wedge currently prevents increasing useful load far
enough to saturate the devices safely.

## Operational findings

- Docker aggregate restarts repeat several minutes of torch compilation and
  FlashInfer TRT-LLM MoE autotuning because `/tmp` and the container cache are
  ephemeral. Persist these caches in a future revision.
- AIPerf's DCGM collectors still find no exporter on ports 9400/9401; the lab
  runner therefore records host `nvidia-smi` telemetry beside every run.
- AIPerf does not receive `usage.prompt_tokens_details.cached_tokens`, so
  prompt-cache-read metrics are unavailable even when prefix caching is on.
- Treat c14/c16 metrics as failures, not throughput measurements. Their small
  set of successful requests makes aggregate throughput misleading.

Raw generated artifacts remain local under `artifacts/runs/20260923T05*` and
`artifacts/runs/20260923T06*`; this curated result is version controlled.
