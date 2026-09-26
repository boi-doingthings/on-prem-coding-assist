# From usage traces to campus-tuned models (Phase 4 roadmap)

The long-term goal: a university that serves open models can also *improve*
them. It can turn consented usage and course material into evaluation sets,
fine-tuned adapters, and eventually its own post-trained models. This module
is a staged roadmap. Each stage is useful on its own, so a campus can stop at
any point.

```text
Stage 1 capture ──► Stage 2 curate ──► Stage 3 evaluate ──► Stage 4 fine-tune ──► Stage 5 serve & compare
(consented traces)  (dedupe, PII,      (campus eval set +   (LoRA/SFT → GRPO)     (Dynamo LoRA adapters,
                     filter by outcome) public benchmarks)                          A/B on the gateway)
```

## Stage 0: consent and governance (before any data is kept)

- **Opt-in only.** Students opt in per course or per key; the gateway key
  carries `metadata.trace_consent` (`scripts/gateway-issue-keys.sh` defaults it
  to `false`). The default service stores no prompt or response bodies.
- **IRB review** for research use of student interactions; a consent form
  that states purpose, retention, de-identification, and whether data may be
  released.
- **Exclude sensitive courses and data** (FERPA/HIPAA/export-controlled).
- **Publish what was collected, and allow withdrawal.**
- **Model licenses on outputs.** Check the serving model's license terms on
  using outputs for training (most Apache-2.0/MIT models allow it).
  Third-party trajectory datasets carry their own terms.

## Stage 1: capture

| Source | Format | Best for |
| --- | --- | --- |
| **Gateway** (LiteLLM → Langfuse/OTel, consenting keys only) | request/response JSON incl. `tool_calls`, `reasoning_content` | harness-agnostic campus-wide collection |
| **Dynamo request traces** | `dynamo.request.trace.v1` JSONL (S3 sink in v1.5, opt-in); `benchmarks/request_trace/` converts to Perfetto | serving research: arrival patterns, prefix reuse, replay |
| **Harness logs** | Pi JSONL session trees, Codex rollouts, OpenHands `log_completions`, mini-SWE-agent `.traj.json`, OpenCode sessions | full agent trajectories with tool observations |
| **Harbor evals** | **ATIF** trajectories (normalized across ~40 agents) | benchmark-grade, outcome-labeled trajectories |

Two uses of the same data:

1. **Systems research (no model training):** replay traces with AIPerf
   (mooncake-style JSONL with hashed prefixes) to measure KV-aware routing,
   prefix caching, and disaggregation under *real* campus load. Hashed-block
   traces contain no text, so they are far easier to share. This is the most
   publishable, lowest-risk output of the program.
2. **Model research:** text trajectories for SFT and RL (below).

## Stage 2: curate

- **NeMo Curator** (v1.3): exact and fuzzy dedup, PII detection and redaction,
  quality classifiers. Run it on GPUs in the same cluster.
- Filter by **outcome**. Keep trajectories where tests passed or the
  student accepted the change; label failures for preference/RL data.
- **NeMo Data Designer** (v0.9) can synthesize variations (new tasks from
  seed trajectories, course-specific Q&A) when consented data is scarce.

## Stage 3: evaluate first (the most useful stage)

Build a **campus eval set** before training anything:

- 50–200 tasks from course assignments (with instructor permission), a
  departmental codebase, or a local research tool, each with tests.
- Run it with the harnesses students use (Harbor, mini-SWE-agent, OpenHands
  SDK) against every candidate model and quantization on the campus endpoint.
- Add public benchmarks through **NeMo Evaluator** or
  `upstream/dynamo/recipes/accuracy/` (GPQA, MMLU-Pro, LiveCodeBench) to check
  that serving choices (FP8/NVFP4) didn't degrade quality.

The eval set alone justifies the program. It tells the campus which open
model actually works for *its* students.

## Stage 4: fine-tune

| Step | NVIDIA tool (Sep 2026) | Hardware | Notes |
| --- | --- | --- | --- |
| LoRA / SFT on HF checkpoints | **NeMo AutoModel** (v0.6) | 1 node; A100 is fine for ≤ 32B LoRA | HF in, HF out; no checkpoint conversion |
| Large MoE / long-context SFT | **Megatron-Bridge** (v0.6) | multi-node H100+ | HF ↔ Megatron conversion, FP8 training |
| DPO, GRPO, on-policy distillation, multi-turn tool-use RL | **NeMo RL** (v0.7) | ≥ 1 node for ≤ 9B; ≥ 2 nodes for 30B-A3B RL | LoRA on both backends; vLLM/SGLang rollouts |
| Agent environments for RL (SWE, terminal) | **NeMo Gym** (v0.6) | with NeMo RL | harnesses incl. OpenHands, mini-SWE-agent, OpenCode, Codex; 100+ envs |

Good first projects, in rising difficulty:

1. **LoRA SFT** of Qwen3.6-35B-A3B or Nemotron 3.5 Lightning on a
   department's codebase conventions or a course's language/framework, using
   curated campus trajectories plus `nvidia/Nemotron-SFT-SWE-v3.5` for
   general skill. Compare on the campus eval set.
2. **Distillation.** Use the big campus model (e.g. Qwen3.5-122B) as teacher
   and a 3B-active student that fits A100-40 GPUs, so smaller campuses can run
   it.
3. **GRPO on SWE tasks** with NeMo RL + NeMo Gym, using
   `nvidia/Nemotron-RL-Agentic-SWE-Pivot-v1` (SWE-Gym + R2E-Gym tasks). Start
   from the NeMo RL Nemotron-Nano LoRA-GRPO recipe.
4. **Fully open research** on OLMo 3.x (open data and every checkpoint) when
   the question concerns training dynamics rather than product quality.

**Ready-made lab for B300 sites: prune → distill → FP8.** The companion
repository [boi-doingthings/workshop-contents](https://github.com/boi-doingthings/workshop-contents)
(`nemotron-3.5-lightning-30b-a3b/`) adapts NVIDIA's Model Optimizer Nemotron
tutorial to Nemotron 3.5 Lightning on 8 × B300. It runs as restartable stages
with Minitron pruning, two-phase teacher-student distillation with
Megatron-Bridge, NeMo Evaluator, and FP8 PTQ, and logs every run. On this
cluster a structured-pruned 2.5B-active student exists (33 GB BF16), but it
has not been distilled or evaluated yet, so its quality is unrecovered. Two
natural next steps for a faculty/student project:

1. Run the 0.3B-token distillation candidate selection, then the NeMo
   Evaluator gate.
2. Serve teacher and student side by side through Dynamo (Lab 4 sweep plus
   the same accuracy recipe) to show the speed/quality trade-off of the
   campus-made model.

**Open datasets to seed training** (HF, CC-BY-4.0 unless noted; check each
card's "generated by" notes):

- SWE trajectories: `nvidia/Open-SWE-Traces` (200K+), `nvidia/Nemotron-SFT-SWE-v3.5`,
  `nvidia/Nemotron-SFT-OpenCode-v1`, `nvidia/Nemotron-SFT-Agentic-v2`.
- RL environments: `nvidia/Nemotron-RL-Agentic-SWE-Pivot-v1`, `nvidia/Nemotron-RL-Agentic-Terminal-Pivot-v1`.
- Code reasoning: `nvidia/OpenCodeReasoning-2`.
- Third-party: SWE-Gym, SWE-smith (MIT), R2E-Gym (Apache-2.0), nebius/SWE-rebench.

## Stage 5: serve the result and compare

Dynamo serves LoRA adapters dynamically on the **vLLM** backend (SGLang is
experimental; TensorRT-LLM has no LoRA support):

```bash
# worker: add to DYNAMO_EXTRA_ARGS and environment
DYNAMO_EXTRA_ARGS="... --enable-lora --max-lora-rank 64"
DYN_LORA_ENABLED=true DYN_SYSTEM_ENABLED=true

# load an adapter at runtime (worker system port; admin network only)
curl -X POST http://<node>:<DYN_SYSTEM_PORT>/v1/loras \
  -H 'Content-Type: application/json' \
  -d '{"lora_name": "cs101-tutor", "source": {"uri": "file:///model-cache/loras/cs101-tutor"}}'
# the adapter appears in /v1/models; the KV router is adapter-aware
```

Expose the adapter as its own gateway alias (e.g. `cs101-tutor`), give it to
one course section, and compare against the base model on the campus eval
set and on satisfaction and usage metrics. Every adapter shares the base
model's GPUs, so a campus can host many course-specific adapters at almost
no extra cost.

References: `upstream/dynamo/docs/fern/pages/cli/operations/lora-adapters.md`,
`examples/backends/vllm/launch/lora/`; github.com/NVIDIA-NeMo (Automodel, RL,
Gym, Curator, DataDesigner, Evaluator, Megatron-Bridge). The NVIDIA Data
Flywheel Blueprint was deprecated in April 2026. Use it only as a design
reference; the modular pipeline above replaces it.
