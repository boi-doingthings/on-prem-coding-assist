# Hybrid DeltaNet wedge: Dynamo 1.3.0 vs 1.5.0 on B300 (2026-09-26)

## Question

Sessions 002–004 found that the Qwen3.5-122B-A10B NVFP4 engine stopped
returning tokens once it had about seven concurrent prefills. Is that a
property of the model and hardware, of Dynamo/NIXL, or of the engine version?

## Setup

- Job 8352 on dgx10, one B300 (GPU 0) per test, portable launcher
  `deploy/edu/serve.sh` (aggregated, 1 replica, file discovery, KV router).
- AIPerf 0.12.0 via `scripts/sweep-aiperf.sh`: streaming chat, `ignore_eos`,
  temperature 0, seed 42. Sweeps stop at the first failed point.
- Images: `vllm-runtime:1.3.0` (vLLM 0.23.0) and `vllm-runtime:1.5.0`
  (vLLM 0.28.0,
  `sha256:d7f73fdc1a66d2e1e0bdec2a74f49093ff6c85bc5e9f5ddf8296634418abe761`).

## Results

| Model (architecture) | Image | Workload | Result |
| --- | --- | --- | --- |
| Qwen3-0.6B (dense attention) | 1.3.0 | 800/256, c1→c128, 2 GPUs | clean; 18.5K out tok/s/GPU at c128 |
| gpt-oss-20b (MoE, attention + sliding window) | 1.3.0 | 800/256, c1→c128 | clean; 16.1K out tok/s/GPU at 188 tok/s/user |
| gpt-oss-20b | 1.3.0 | 16K/512, c1→c64 | clean (prefill-bound: TTFT p99 2.0 s at c16, 8.0 s at c64) |
| **Qwen3.6-35B-A3B FP8** (hybrid Gated DeltaNet MoE) | **1.3.0** | 800/256 | **wedged at c8**: 8/32 timeouts, then a 1-token probe hung |
| **Qwen3.6-35B-A3B FP8** | **1.5.0** | 800/256, c1→c128 | **clean**; 8.9K out tok/s/GPU at c128, 99.5 tok/s/user |
| Qwen3.6-35B-A3B FP8 | 1.5.0 | 16K/512, c1→c64 | clean, 256/256 (prefill-bound like gpt-oss) |
| **Qwen3.5-122B-A10B NVFP4** (hybrid Gated DeltaNet MoE) | **1.5.0** | 800/64 (the Session 004 wedge workload), c1→c32 | **clean**; 2,005 out tok/s/GPU at 104 tok/s/user, TTFT p99 486 ms |

For comparison, the best Session 004 result on 1.3.0 was two replicas at c12:
975 out tok/s total (≈ 488 per GPU). Each engine wedged above about seven
concurrent requests.

Charts: `sweeps/20260926-compare-dynamo-1.3-vs-1.5.svg`,
`sweeps/20260926-compare-chat-1xB300.svg`,
`sweeps/20260926-compare-coding-agent-1xB300.svg`.

## Interpretation

- The wedge follows the **hybrid linear-attention (Gated DeltaNet)
  architecture on vLLM 0.23**. Dense and sliding-window models on the same
  image, GPU, launcher and client scaled to c128. The same hybrid models on
  vLLM 0.28 did not wedge in any tested point.
- The earlier NIXL/disaggregation boundary (c6/c7) is consistent with this:
  all prompts converged on one affected prefill engine.
- This is strong localization, not a root-caused bug. The exact vLLM change
  was not bisected, and 1.5.0 was tested only up to c32 (Qwen3.5) and c128
  (Qwen3.6) on one GPU with aggregated serving.

## Actions

- Default image for the university kit (`deploy/edu/serve.sbatch`) moved to
  `vllm-runtime:1.5.0`.
- Recommended next lab step: rebuild the 1P/2D and multi-replica Qwen3.5
  deployments on 1.5.0 and repeat the Session 004 matrix to higher
  concurrency before setting gateway caps.
