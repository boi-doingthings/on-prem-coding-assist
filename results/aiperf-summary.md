# AIPerf results — Qwen3.5 122B-A10B NVFP4

## Experiment contract

- Date: 2026-09-22
- NVIDIA AIPerf: 0.12.0
- Image digest:
  `sha256:d22eb02bccadcd2acbbd905a1742f1e642f2bdd7bc3a0377cebda685a233902d`
- Served model: `Qwen/Qwen3.5-122B-A10B`
- Checkpoint: `nvidia/Qwen3.5-122B-A10B-NVFP4`
- Topology: one prefill worker on GPU 0 and two decode workers on GPUs 1–2
- Endpoint: streaming OpenAI-compatible chat completions
- Dataset: AIPerf synthetic, seed 42
- Target input/output: 800/64 tokens, zero standard deviation
- Sampling: temperature 0, `ignore_eos=true`
- Warmup: three requests at concurrency one
- Profile: 16 requests per concurrency point
- Token counts: server-reported

## Results

| Concurrency | Valid requests | Requests/s | Output tokens/s | TTFT avg/p99 | ITL avg | Request latency avg/p99 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 16/16 | 1.58 | 100.91 | 224/240 ms | 6.44 ms | 630/669 ms |
| 2 | 16/16 | 2.56 | 163.57 | 338/383 ms | 6.97 ms | 777/824 ms |
| 4 | 16/16 | 3.99 | 255.24 | 464/832 ms | 7.81 ms | 956/1307 ms |
| 8 | 0/16 | — | — | >120 s | — | >120 s |

At concurrency four versus one, aggregate output throughput increased 2.53x,
while mean TTFT increased 2.07x and mean request latency increased 1.52x.
These are bounded single-run measurements, not production capacity claims.

## Concurrency-eight failure

The failure was reproduced on two Slurm allocations. Sequential warmups
completed normally. The first burst of eight requests then returned no bytes
before the client timeout. On the controlled retry:

- Eight requests timed out after 120 seconds.
- The remaining eight were cancelled when the run was stopped.
- Dynamo discovery continued reporting a healthy 1P/2D topology.
- A subsequent single-request data-plane probe also timed out.
- A full Dynamo process restart restored service, tool calling, and Pi.

This rules out Slurm expiry as the primary cause. The current hypothesis is an
interaction between concurrent prefills, the hybrid DeltaNet/attention cache,
and disaggregated NIXL scheduling. That hypothesis remains unproven.

## Instrumentation limitations

- Dynamo's Prometheus endpoint was captured by AIPerf.
- DCGM endpoints on ports 9400 and 9401 were unavailable, so AIPerf did not
  collect GPU telemetry.
- Cached-token usage details were absent, so AIPerf could not calculate prompt
  cache read metrics.
- Full raw exports remain in ignored local `artifacts/runs/` directories because
  they are generated data. The structured summary below is version controlled.

See the [master recordbook](../recordbook/index.html) and
[chronological notebook](../notes/lab-notebook.md) for the architecture,
earlier custom probe, NIXL evidence, and incident history.
