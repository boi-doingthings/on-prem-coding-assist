# Open-model catalog for campus self-hosting (snapshot: 2026-09-26)

Open models move monthly. Treat this as a dated snapshot: re-check the model
cards and leaderboards before each engagement, and update the date above.
Every benchmark number here is **vendor-reported** (from the model card)
unless marked **(indep.)**. Blank = not published.

## 1. How to read benchmarks in 2026 — say this in every session

- **SWE-bench Verified is saturated and contaminated.** Vals AI archived its
  board on 2026-09-01; newer model cards report SWE-bench Pro, DeepSWE, and
  Terminal-Bench instead. Treat SWE-bench Verified scores above ~75 as marketing.
- **Terminal-Bench versions are not comparable** (2.0 vs 2.1 vs 3.0/4.0 differ
  by tens of points). Always quote the version.
- **The harness changes the score.** The same model scores 60.5 on SWE-bench
  Verified with OpenHands and 53.7 with Codex (Nemotron 3 Super card). Evaluate
  with the harness your students will use (`05-coding-harnesses.md` §5).
- **Independent, contamination-resistant checks are much lower.** SWE-rebench
  (fresh GitHub tasks, May–Jul 2026) (indep.): GLM-5.2 62.9, MiniMax M3 47.2,
  MiMo V2.5 Pro 46.5, DeepSeek-V4 Pro 40.2, Qwen3.6-27B 31.2,
  Qwen3.6-35B-A3B 24.7, Qwen3.5-35B-A3B 17.1.
- **Artificial Analysis Intelligence Index v4.3.2** (indep., open-weights,
  fetched 2026-09-26): MiMo-V2.6-Pro 46 · GLM-5.3 45 · Qwen3.8-2.4T 45 ·
  Kimi K3 44 · GLM-5.3-Flash 42 · DeepSeek V4.1 Flash 39 · DeepSeek V4 Pro 0813
  36 · Qwen3.8-27B 34 · MiniMax-M3 29 · Nemotron 3 Ultra 23 · Gemma 4 31B 19 ·
  Nemotron 3 Super 13 · gpt-oss-120b 12 · gpt-oss-20b 9 · Nemotron 3 Nano 9 ·
  OLMo 3.1 32B Think 7. (Scale changed in v4.3; don't mix with older AA numbers.)
- **Your own measurement beats all of the above.** Module 04 and Lab 4 show
  how; `upstream/dynamo/recipes/accuracy/` runs GPQA/MMLU/LiveCodeBench
  against a live endpoint to confirm a quantized deployment matches the card.

## 2. Recommended models by hardware tier

Tier = the smallest hardware that serves the model with useful KV headroom.
"Fits" math: `tools/sizing.py <hf-id> --gpus <tier>`.

| Tier | Best coding pick | Why | Alternatives |
| --- | --- | --- | --- |
| **T1: 1× 24–48 GB** (A100-40, L40S, RTX 6000 Ada) | **gpt-oss-20b** (≤ 40 GB) / **Qwen3.8-27B-FP8** or **Qwen3.6-35B-A3B-FP8** (48 GB) | gpt-oss-20b fits anything (14 GB MXFP4); Qwen3.8-27B is the strongest per-GPU coder; Qwen3.6-35B-A3B has only 3B active → very fast | Nemotron 3.5 Lightning, Devstral Small 2 24B, Gemma 4 26B-A4B/31B, Granite 4.2 30B |
| **T2: 1× 80–96 GB** (A100-80, H100, RTX PRO 6000) | **Qwen3.8-27B (BF16)** | full precision + large KV pool | gpt-oss-120b (fast, general, weaker agent); Nemotron 3.5 Lightning (open data); Qwen3.6-35B-A3B at long context |
| **T3: 1× H200 / 2× 80 GB** | Qwen3.8-27B with high concurrency, or **Qwen3.5-122B-A10B-FP8** (TP2) | 122B MoE with 10B active is the "big model" demo that still decodes fast | Nemotron 3 Super FP8 (4× 80 GB), Mistral Small 4 |
| **T4: 4× H100/H200** | **DeepSeek-V4-Flash** (MIT, 284B/13B, 1M ctx) | SWE-bench Verified 79.0, TB 2.0 56.9 | Nemotron 3 Super FP8; Qwen3.5-397B-A17B (FP8, 8× 80 GB) |
| **T5: 1–4× B200/B300** (NVFP4) | **Qwen3.5-122B-A10B-NVFP4** (1 GPU/replica, this lab) or **DeepSeek-V4-Flash-NVFP4** (TP4) | NVFP4 doubles model size per GPU with near-lossless accuracy | GLM-5.3-Flash NVFP4, Qwen3.6-35B-A3B-NVFP4 (many replicas) |
| **T6: 8× H200 / 8× B200/B300** | **GLM-5.3** / **GLM-5.2** (MIT) or **DeepSeek-V4-Pro-0813** (MIT) | frontier-class open models; GLM-5.2 is the best independent SWE-rebench score | MiMo-V2.6-Pro (MIT, AA #1 open), Kimi K3 (≈1.5 TB, custom license) |

**Default recommendation for a first campus deployment:** start with the model
that fits one GPU of the idle hardware, with KV headroom, and scale out
**replicas** behind the Dynamo KV router. Moving to a bigger model comes later.
One well-served mid-size model beats a frontier model that wedges at ten users.

## 3. Coding and agentic benchmarks

| Model | Params (total/active) | SWE-bench Verified | SWE-bench Pro | Terminal-Bench | LiveCodeBench v6 | Source |
| --- | --- | ---: | ---: | --- | ---: | --- |
| Qwen3.8-27B | 27.8B dense | — | 61.7 | 73.0 (2.1) | 90.3 | HF card |
| Qwen3.6-27B | 27.8B dense | 77.2 | 53.5 | 59.3 (2.0) | 83.9 | HF card |
| Qwen3.6-35B-A3B | 36B / 3B | 73.4 | 49.5 | 51.5 (2.0) | 80.4 | HF card |
| Qwen3.5-122B-A10B | 125B / 10B | 72.0 | — | 49.4 (2.0) | 78.9 | HF card |
| Qwen3.5-397B-A17B | 403B / 17B | 76.4 | — | 52.5 (2.0) | 83.6 | HF card |
| Qwen3-Coder-Next | 80B / 3B | 71.3 (OpenHands) | 44.3 | 36.2 (2.0) | — | HF card |
| gpt-oss-20b (high) | 21B / 3.6B | 60.7 | — | — | — | arXiv 2508.10925 |
| gpt-oss-120b (high) | 117B / 5.1B | 62.4 | — | — | — | arXiv 2508.10925 |
| Nemotron 3 Nano | 32B / 3.5B | 38.8 (OpenHands) | — | — | 68.3 | HF card |
| Nemotron 3.5 Lightning | 32B / 3B | 51.6 | — | 24.6 (2.1) | — | HF card |
| Nemotron 3 Super | 124B / 12B | 60.5 (OpenHands) | — | 31.0 (2.0 core) | 81.2 (v5) | HF card |
| Nemotron 3 Ultra | 561B / 55B | 70.7 | — | — | 89.0 | HF card |
| DeepSeek-V4-Flash (max) | 284B / 13B | 79.0 | — | 56.9 (2.0) | 91.6 | HF card |
| DeepSeek-V4-Pro (max) | 1.6T / 49B | 80.6 | — | 67.9 (2.0) | 93.5 | HF card |
| GLM-5.3-Flash | 321B / 18B | — | — | 84.3 (2.1) | — | HF card |
| GLM-5.2 | 753B / ~40B | — | 62.1 | 81.0 (2.1) | — | HF card; SWE-rebench 62.9 (indep.) |
| Kimi K2.6 | 1.03T / 32B | 80.2 | 58.6 | 66.7 (2.0) | 89.6 | HF card |
| MiniMax M3 | 427B / ~23B | 80.5 | 59.0 | — | — | HF card; SWE-rebench 47.2 (indep.) |
| Gemma 4 31B | 31B dense | — | — | — | 80.0 | Google card |
| Devstral Small 2 | 24B dense | 68.0 | — | 22.5 (2.0) | — | HF card |
| Granite 4.2 30B | 29B dense | 57 | — | 29.2 (2.1) | 75.8 | HF card |
| OLMo 3.1 32B Think | 32B dense | — | — | — | 83.3 (**v3**) | HF card |

## 4. General reasoning and tool use

| Model | MMLU-Pro | GPQA-Diamond | AIME / HMMT | IFBench | BFCL v4 | τ²-bench |
| --- | ---: | ---: | --- | ---: | ---: | ---: |
| Qwen3.8-27B | — | 89.2 | — | 79.5 | — | — |
| Qwen3.6-35B-A3B | 85.2 | 86.0 | AIME26 92.7 | — | — | — |
| Qwen3.5-122B-A10B | 86.7 | 86.6 | HMMT Feb25 91.4 | 76.1 | 72.2 | 79.5 |
| Nemotron 3 Super | 83.7 | 79.2 | AIME25 90.2 | 72.6 | — | — |
| Nemotron 3 Nano | 78.3 | 73.0 | AIME25 89.1 | 71.5 | 53.8 | 49.0 |
| gpt-oss-120b (high) | MMLU 90.0 | 80.1 | AIME25 92.5 | — | — | — |
| gpt-oss-20b (high) | MMLU 85.3 | 71.5 | AIME25 91.7 | — | — | — |
| DeepSeek-V4-Flash (max) | 86.2 | 88.1 | — | — | — | — |
| Gemma 4 31B | 85.2 | 84.3 | AIME26 89.2 | — | — | 76.9 |
| Granite 4.2 30B | 77.6 | 66.4 | AIME25 89.2 | — | 61.4 | — |
| OLMo 3.1 32B Think | MMLU 86.4 | 57.5 | AIME25 78.1 | 68.1 | — | — |

## 5. Licenses — review before a campus-wide service

| Verdict | Licenses | Models |
| --- | --- | --- |
| **Clean** (OSI) | Apache-2.0, MIT | Qwen3.5 / 3.6 / 3.8-27B, Qwen3-Coder-Next, gpt-oss, Gemma 4, Mistral Small 4, Devstral Small 2, Granite 4.x, OLMo 3.x, Seed-OSS, K-EXAONE 2.0; DeepSeek V4 (all), GLM-5.2, GLM-5.3-Flash, MiMo V2.5/V2.6 |
| **Permissive, custom** | OpenMDW-1.1, NVIDIA Nemotron Open Model License, Kimi modified-MIT, Mistral modified-MIT, GLM-5.3 License | Nemotron 3 family, Kimi K2.6/K2.7, Devstral 2 123B, Mistral Medium 3.5, GLM-5.3 |
| **Legal review** | Qwen Community License 1.0 (restricts "AI Work Assistant" services), minimax-community, Kimi K3 License, Qwen3.8-Max License, Upstage Solar License | Qwen3.8-Flash-Next, MiniMax M3, Kimi K3, Qwen3.8-2.4T, Solar Open 2 |
| **Avoid as default** | EXAONE 1.2-NC (non-commercial), Llama 4 Community (gated, 700M-MAU/AUP clauses) | EXAONE 4.5, Llama 4 |

## 6. Models for research and post-training

| Goal | Model | Why |
| --- | --- | --- |
| Fully open science (data + code + checkpoints) | **OLMo 3.1 32B** / **Olmo-Hybrid-7B** (Ai2, Apache-2.0) | Only family with open pre-training data, every intermediate checkpoint, and full pipeline; weaker in absolute terms |
| Realistic-scale post-training / RL on the NVIDIA stack | **Nemotron 3 Nano / 3.5 Lightning (30B-A3B)**, Super (120B-A12B) | Open weights + open SFT/RL data (Nemotron-Post-Training-v3, Nemotron-SFT-SWE) + NeMo RL/Gym recipes; Lightning was trained with NeMo RL |
| Agentic RL recipe to copy | **Ai2 TMax-27B** (on Qwen3.6-27B) | Open data (TMax-15K) + code for terminal-agent RL |
| Fine-tune a strong small coder | Qwen3.6-35B-A3B, Qwen3.8-27B (Apache-2.0) | Best starting quality; NeMo AutoModel loads HF checkpoints directly |

## 7. Status of models you may be asked about

- **Llama:** no new Meta open LLM since Llama 4 (Apr 2025).
- **Phi:** no new general Phi model since Phi-4-reasoning (Apr 2025).
- **gpt-oss:** still OpenAI's only open LLMs.
- **Qwen 3.7:** never released with open weights.
- **Aider Polyglot:** leaderboard not updated since Nov 2025, so it's not useful for 2026 models.

## Sources

Model cards on huggingface.co (Qwen, nvidia, openai, deepseek-ai, zai-org,
moonshotai, MiniMaxAI, XiaomiMiMo, google, mistralai, ibm-granite, allenai);
gpt-oss card arXiv:2508.10925; Gemma 4 card ai.google.dev; independent:
artificialanalysis.ai/models/open-source, swe-rebench.com; license texts in each
repo. Full research notes with per-number URLs were collected on 2026-09-26.
A few extracted values are flagged for re-verification and were left out here
(e.g. DeepSeek-V4.1-Flash MMLU-Pro).
