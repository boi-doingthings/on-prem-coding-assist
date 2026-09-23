# Architecture and learning path

## Why this first model

`nvidia/Qwen3.5-122B-A10B-NVFP4` is a 122B-total, 10B-active hybrid MoE model.
The official Dynamo Blackwell recipe runs TP1, uses FP8 KV cache, supports a
262K context window, and enables Dynamo-native `qwen3_coder` tool-call and
`qwen3` reasoning parsers. The checkpoint reports 77.76 GiB when loaded.

It is a stronger experimental choice than a tiny quickstart model: coding-agent
requests have long, highly reusable prefixes, tool schemas, multi-turn state,
and decode-heavy continuations. Those characteristics expose Dynamo's routing,
cache, disaggregation, and scaling behavior.

## Data path

```text
Pi
  -> OpenAI-compatible HTTP/SSE
  -> Dynamo Frontend (chat template + tool/reasoning parsing)
  -> KV-aware router
  -> aggregated worker pool
     or
     prefill worker -> NIXL KV transfer -> decode worker pool
  -> streamed tool calls/text back to Pi
```

## Staged progression

1. **Control-plane smoke test** — local Dynamo CLI topology, GPU discovery,
   etcd/NATS, and a small public model. This separates infrastructure failures
   from large-model failures. Repeat on the Kubernetes platform once a
   cgroup-capable allocation is available.
2. **Agentic aggregated baseline** — Qwen3.5 NVFP4 with two, then four TP1
   replicas behind the KV-aware router. Validate structured streaming tool calls
   and prefix affinity.
3. **Disaggregated 1P/2D** — reproduce the official Blackwell recipe with NIXL
   on three GPUs and measure TTFT/ITL/output throughput.
4. **Disaggregated 1P/3D** — use the fourth GPU to test whether coding-agent
   traffic is decode-bound at the chosen concurrency.
5. **Feature isolation** — A/B round-robin versus KV-aware routing, prefix
   caching on/off, aggregated versus disaggregated, and conditional
   disaggregation where supported.
6. **Operational scale** — Prometheus, planner/autoscaling, failure injection,
   then multi-node RDMA only after the single-node experiment contract is
   stable.

## Benchmark layers

- **Engine/API:** AIPerf with fixed synthetic and trace-replay workloads.
- **Harness:** Pi sessions that exercise repository search, editing, tests, and
  repeated tool calls.
- **Quality:** task success, patch correctness, tests passed, tool-call parse
  errors, and retries—not only tokens per second.
- **Operations:** cold-start time, cache warmth, GPU memory/utilization, queue
  depth, request failures, and recovery behavior.

The core latency metrics are time to first token (TTFT), inter-token latency
(ITL), end-to-end latency, output tokens/second, and tokens/second/user. Report
percentiles and error rates; averages alone hide agent-tail behavior.

## Scale-out rule

Four B300s are sufficient for the first controlled study. Add GPUs only when a
measured bottleneck requires them—for example, prefill saturation, insufficient
decode replicas, or a larger model that needs tensor/expert parallelism. This
keeps each scaling claim falsifiable.

For the local single-container 1P/2D experiment, NIXL can use same-host CUDA IPC
over the fully connected NV18 fabric. The production Kubernetes recipe instead
forces GPU-local RDMA and must expose the appropriate InfiniBand device resources
to each pod; these are intentionally separate experimental conditions.

The Slurm lab uses Enroot for disaggregation because its host-integrated mount
namespace exposes `/sys/class/net` and allocated NVIDIA devices to UCX. The
site's rootless Docker daemon presents an empty container `/sys`, so NIXL cannot
instantiate UCX there even with Docker's rootless `--privileged` flag.
