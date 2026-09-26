# GPU tiers, precision, and sizing

The same curriculum runs on every NVIDIA data-center GPU from A100 onward;
what changes is which model fits and which precision runs natively.

## 1. GPU reference (per GPU, dense tensor throughput)

| GPU | Arch | Memory | Bandwidth | GPU↔GPU | BF16 | FP8 | FP4 | Native low precision |
| --- | --- | --- | --- | --- | ---: | ---: | ---: | --- |
| A100 40 GB SXM | Ampere sm80 | 40 GB HBM2 | 1.56 TB/s | NVLink3 600 GB/s | 312 TF | — | — | BF16, INT8, INT4 |
| A100 80 GB SXM | Ampere sm80 | 80 GB HBM2e | 2.04 TB/s | NVLink3 600 GB/s | 312 TF | — | — | BF16, INT8, INT4 |
| L40S | Ada sm89 | 48 GB GDDR6 | 0.86 TB/s | PCIe only | 362 TF | 733 TF | — | **FP8** |
| H100 SXM | Hopper sm90 | 80 GB HBM3 | 3.35 TB/s | NVLink4 900 GB/s | 989 TF | 1,979 TF | — | **FP8** |
| H200 SXM | Hopper sm90 | 141 GB HBM3e | 4.8 TB/s | NVLink4 900 GB/s | 989 TF | 1,979 TF | — | **FP8** |
| RTX PRO 6000 Blackwell Server | Blackwell sm120 | 96 GB GDDR7 | 1.6 TB/s | PCIe only | see note | | | FP8, NVFP4 |
| B200 (HGX) | Blackwell sm100 | 180 GB HBM3e | 8 TB/s | NVLink5 1.8 TB/s | 2.25 PF | 4.5 PF | 9 PF | FP8, MXFP4, **NVFP4** |
| B300 (HGX) | Blackwell Ultra sm103 | 288 GB HBM3e (~268 GiB usable) | 8 TB/s | NVLink5 1.8 TB/s | 2.25 PF | 4.5 PF | 13.5 PF | FP8, **NVFP4 at 1.5× B200**; INT8/FP64 sharply reduced |
| DGX Spark (GB10) | Blackwell sm121 | 128 GB unified LPDDR5x | 0.27 TB/s | 200 Gb/s CX-7 | — | — | ~0.5 PF | FP8, FP4 — dev/LoRA box, not a server |

Sources: nvidia.com product pages for A100, L40S, H100, H200, HGX B200/B300,
RTX PRO 6000, and DGX Spark; the Blackwell Ultra technical blog. B200 and B300
per-GPU figures are the HGX 8-GPU totals divided by 8. The RTX PRO 6000
"4/2/1 PF" figures are probably sparse, so halve them for dense.

**Takeaways for faculty**

- **Decode speed is set by memory bandwidth**, not TFLOPS. A single stream's
  ceiling is roughly bandwidth ÷ bytes of weights read per token, so MoE
  models (few active parameters) and low precision decode much faster.
- **Prefill speed is set by compute.** Long agent prompts are prefill-heavy, so
  FP8 and FP4 tensor cores matter most there.
- **B300 pays off only with FP4.** Its FP8/BF16 throughput equals B200's. Use
  NVFP4 checkpoints and avoid INT8 W8A8 on B300.

## 2. Precision by architecture

| Checkpoint format | Ampere (A100) | Ada (L40S) / Hopper (H100, H200) | Blackwell (B200, B300, RTX PRO 6000) |
| --- | --- | --- | --- |
| BF16 | native | native | native |
| FP8 (W8A8) | **weight-only** via vLLM Marlin: memory win, no compute win | native | native |
| NVFP4 | weight-only Marlin fallback: best-effort, open correctness bugs, validate accuracy | weight-only fallback, same caveats | **native** (sm120/121 may fall back for some MoE kernels) |
| MXFP4 (gpt-oss) | Marlin MoE + Triton attention: officially works | works | native |
| INT4 AWQ/GPTQ (W4A16) | **most mature low-bit path** | works | works |
| INT8 W8A8 | native (624 TOPS) | native | avoid on B300 |
| KV cache FP8 | memory-only; test before relying on it | native | native |

**Recommended backend by site:** Dynamo with the **vLLM** backend everywhere.
It has the broadest quantization coverage on Ampere, and it is the only
backend with fully supported LoRA serving in Dynamo, which Phase 4 needs.
SGLang and TensorRT-LLM are for advanced labs on Hopper/Blackwell.

## 3. Software prerequisites (Dynamo v1.5.0, 2026-09-21)

- **Driver R580+ (CUDA 13)** for current `vllm/sglang/tensorrtllm-runtime`
  images (1.3.0+). Sites stuck on R575 must use 1.2.x images (CUDA 12.9).
  Check this first in Phase 0.
- Architectures: Blackwell, Hopper, Ada, Ampere.
- Images: `nvcr.io/nvidia/ai-dynamo/{vllm,sglang,tensorrtllm}-runtime:1.5.0`
  (vLLM 0.28.0, SGLang 0.5.18, TRT-LLM 1.3.0rc25). **Use ≥ 1.5.0 for hybrid
  models:** on 1.3.0 (vLLM 0.23) Qwen3.5/3.6 wedged at ~7–8 concurrent requests
  on B300; on 1.5.0 the same profiles ran clean to c32–c128.
- Containers: Pyxis/Enroot, Apptainer, or Docker (`deploy/edu/serve.sbatch`).
- CPU: request ≥ 32 threads per serving node. A 2-thread allocation made a
  B300 serve at 22 s TTFT in this lab.
- Storage: put the model cache on shared storage so a requeued job can
  restart on another node without re-downloading.

## 4. Memory math (the three budgets)

```text
usable = GPU memory × 0.90 (engine utilization) − ~6 GB (activations, CUDA graphs)
KV pool = TP × usable − weights            (per replica)
KV bytes/token = 2 × attention_layers × kv_heads × head_dim × bytes(kv dtype)
    MLA (DeepSeek/Kimi/GLM-5): attention_layers × (kv_lora_rank + rope_dim) × bytes
    hybrid Mamba/DeltaNet layers: constant state per sequence, no per-token KV
sessions at context C = KV pool ÷ (KV bytes/token × C)
```

`tools/sizing.py` implements this from the model's `config.json` and
safetensors index. Validation: for Qwen3.5-122B-A10B NVFP4 on one B300 it
predicts 13.8M KV tokens (52 × 262K-token sessions); vLLM reported 13.56M
tokens (51.7×).

**KV cost per token (BF16 KV; FP8 halves it)** — why architecture matters more
than parameter count for long-context agents:

| Model | KV/token | One 64K-token session |
| --- | ---: | ---: |
| Qwen3-32B (dense GQA, 64 layers) | 256 KiB | 16 GiB |
| Qwen3-Coder-30B-A3B (GQA) | 96 KiB | 6 GiB |
| DeepSeek-V3/Kimi-K2 (MLA) | ~69 KiB | 4.3 GiB |
| gpt-oss-120b (half sliding-window) | 36 KiB | 2.3 GiB |
| Qwen3.5-122B-A10B (hybrid, 12 of 48 layers attention) | 24 KiB | 1.5 GiB |
| Nemotron-3-Nano-30B-A3B (hybrid, 6 attention layers) | 6 KiB | 0.4 GiB |

## 5. Starting configurations by tier

| Site hardware | Starting profile (`config/edu-models/`) | Layout | Notes |
| --- | --- | --- | --- |
| 1–8× A100-40 | `gpt-oss-20b` | 1 replica per GPU, KV router | 32K–64K context; BF16 KV |
| 1–8× A100-80 | `gpt-oss-120b` or `qwen3.8-27b` (BF16) | 1 replica per GPU | FP8 checkpoints run weight-only |
| L40S nodes | `qwen3.6-35b-a3b-fp8` or `gpt-oss-20b` | 1 replica per GPU | PCIe only: avoid TP > 2 |
| 1–8× H100 | `qwen3.6-35b-a3b-fp8`, `qwen3.8-27b`, `nemotron-3.5-lightning` | replicas; 4 GPUs → `nemotron-3-super-fp8` TP4 | native FP8 |
| 4–8× H200 | `qwen3.5-122b-a10b-fp8` (2× TP2), DeepSeek-V4-Flash (4 GPUs) | replicas of TP2/TP4 | upstream recipes exist |
| 4–8× B200/B300 | `qwen3.5-122b-a10b-nvfp4` (1 GPU/replica), `deepseek-v4-flash-nvfp4` (TP4) | replicas; try disaggregation for long prompts | NVFP4 essential on B300 |

**Planning rule:** scale out with *replicas* of the smallest configuration
that fits, behind the Dynamo KV-aware router. Use TP only when the model
doesn't fit on one GPU, or when you need lower latency per user than one GPU
delivers. Don't assume disaggregation wins; measure it (`04-benchmarking.md`).

## 6. Offline what-if sizing (AISimulate)

AIConfigurator was renamed **AISimulate** in Dynamo 1.5 (`pip install
aisimulate`). It searches TP, EP, and aggregated/disaggregated splits against a
TTFT/ITL SLA without GPUs. It has system data for a100_sxm/pcie, l40s,
h100_sxm/pcie, h200_sxm, b200_sxm, b300_sxm, gb200/gb300, and
rtx_pro_6000_server. Model coverage varies, so run `aisimulate support` first.
It makes a good pre-lab exercise: predict with AISimulate, then measure with
AIPerf, and explain the gap.
