# Lab 1 — First deployment on any NVIDIA GPU (45–60 min)

**You will:** launch NVIDIA Dynamo with a small model on one GPU, confirm it
speaks the OpenAI API, and see a structured tool call — the capability every
coding agent depends on.

**Works on:** A100, H100, H200, L40S, B200, B300 (1 GPU).

## 0. Concepts (5 min)

```text
client (curl / harness)
   -> Dynamo frontend   : OpenAI-compatible HTTP, chat template, tool/reasoning parsing
   -> KV-aware router   : picks the worker that already caches most of your prompt
   -> worker (vLLM)     : prefill (read prompt) + decode (write tokens) on the GPU
```

## 1. Stage the model and image (done in advance by the instructor)

```bash
git clone <site fork of this repo> campus-ai && cd campus-ai
export DYNAMO_MODEL_CACHE=$PWD/.state/model-cache    # shared filesystem
DYNAMO_MODEL=Qwen/Qwen3-0.6B ./scripts/download-model.sh    # uses Docker
# no Docker: pip install -U huggingface_hub && HF_HOME=$DYNAMO_MODEL_CACHE hf download Qwen/Qwen3-0.6B
```

`scripts/env.sh` contains this lab's site-specific Docker paths — edit it in
your site fork (or skip it: `deploy/edu/*` does not need it).

## 2. Launch

```bash
sbatch --gres=gpu:1 --cpus-per-task=16 --time=02:00:00 \
  --export=ALL,EDU_PROFILE=config/edu-models/canary-qwen3-0.6b.env \
  deploy/edu/serve.sbatch
squeue --me                     # note the node name
tail -f dynamo-edu-<jobid>.log  # wait for "added model"
```

No Slurm? Inside the runtime container on any GPU machine:

```bash
DYNAMO_MODEL=Qwen/Qwen3-0.6B DYNAMO_TOOL_PARSER=hermes DYNAMO_REASONING_PARSER=qwen3 \
  bash deploy/edu/serve.sh
```

## 3. Talk to it

```bash
ssh -N -L 8000:<node>:8000 <you>@<login-node> &      # from your laptop
curl -s localhost:8000/health | jq '.instances[] | {component, endpoint}'
curl -s localhost:8000/v1/models | jq
DYNAMO_SERVED_MODEL=Qwen/Qwen3-0.6B ./scripts/smoke-api.sh
```

Look for `"finish_reason": "tool_calls"` and `get_weather` with
`{"city": "Seattle"}` in the last response.

## 4. Read the engine log (10 min)

Find and write down:

- model load time and memory (`Model loading took … GiB`)
- `Available KV cache memory` and `GPU KV cache size: … tokens`
- `Maximum concurrency for … tokens per request`

Question: why is the KV cache so much larger than the model for a 0.6B model?
What would change with a 30B model on the same GPU? (Lab 2 answers this.)

## 5. Check yourself

- [ ] `/health` shows a `backend` `generate` instance
- [ ] Text completion and tool call succeed
- [ ] You can state the KV-cache token capacity of your GPU for this model
