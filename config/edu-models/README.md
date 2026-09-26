# Model profiles

One file per deployable model. `deploy/edu/serve.sbatch` sources a profile;
`deploy/edu/serve.sh` reads the `DYNAMO_*` variables; any other exported
variable (e.g. `VLLM_*`) reaches the engine.

| Profile | Min GPU (per replica) | Use | Status |
| --- | --- | --- | --- |
| `canary-qwen3-0.6b.env` | any ≥ 8 GB | stack validation, Lab 1 | **validated** 2×B300, vllm-runtime 1.3.0 |
| `gpt-oss-20b.env` | 1× 24 GB+ (A100-40, L40S, …) | small-GPU coding/chat, Apache-2.0 | **validated** 1×B300, 1.3.0 |
| `qwen3.6-35b-a3b-fp8.env` | 1× 48 GB+ (L40S, A100-80\*, H100…) | fast MoE coding model, Apache-2.0 | **validated** 1×B300, **1.5.0 required** |
| `qwen3.8-27b.env` | 1× 80 GB BF16 / 1× 48 GB FP8 | strongest coding model per GPU (vendor numbers) | template, no Dynamo recipe yet |
| `gpt-oss-120b.env` | 1× 80 GB | general + coding, Apache-2.0 | from upstream recipe flags |
| `nemotron-3.5-lightning.env` | 1× H100/H200 (NVFP4) or B200 (BF16) | NVIDIA open-data model, post-training base | from upstream recipe (dev image) |
| `nemotron-3-super-fp8.env` | 4× H100/H200 TP4 | NVIDIA open-data 120B | from upstream recipe |
| `qwen3.5-122b-a10b-nvfp4.env` | 1× B200/B300 | this lab's production model | **validated** 1×B300 on 1.5.0; 1.3.0 wedges (see `results/`) |
| `qwen3.5-122b-a10b-fp8.env` | 2× H200 TP2 | Hopper version of the above | from upstream recipe |
| `deepseek-v4-flash-nvfp4.env` | 4× B200/B300 TP4 | frontier-class MIT model | from upstream recipe, advanced |

Default image: `nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.5.0` (override with
`DYNAMO_RUNTIME_IMAGE`). The hybrid Gated-DeltaNet Qwen models (3.5, 3.6)
wedged under concurrency on 1.3.0 in this lab and ran clean on 1.5.0; other
hybrid families (Qwen3.8, Nemotron-H) were not tested — sweep them first.

\* A100 has no FP8 tensor cores: vLLM runs FP8 checkpoints weight-only
(Marlin), saving memory but not compute. Prefer BF16/AWQ/MXFP4 there.

"From upstream recipe" means the parser and engine flags were copied from the
pinned Dynamo recipe (`upstream/dynamo/recipes/…`) but not yet run through
this launcher — run Lab 1's smoke test and a short sweep before using one for
a class, then update its status line.

Add a model: copy the closest profile, set the parsers from
`upstream/dynamo/docs/fern/pages/use-cases/tool-calling-and-reasoning/`,
size it with `tools/sizing.py`, validate with `scripts/smoke-api.sh`.
