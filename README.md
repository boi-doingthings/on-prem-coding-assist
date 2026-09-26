# Dynamo coding-assistant lab

This repository is a reproducible lab for deploying a private coding model with
[NVIDIA Dynamo](https://github.com/ai-dynamo/dynamo), connecting it to Pi, and
measuring the serving behavior of coding-agent workloads.

## Current target

- Hardware: 4 x NVIDIA B300 SXM6 (275,040 MiB each)
- Model: `nvidia/Qwen3.5-122B-A10B-NVFP4`
- Served name: `Qwen/Qwen3.5-122B-A10B`
- Runtime: Dynamo vLLM runtime
- Baselines: aggregated replicas with KV-aware routing, then disaggregated
  prefill/decode with NIXL
- Client: Pi through Dynamo's OpenAI-compatible `/v1/chat/completions` API

The model is a useful first target because it fits on one Blackwell GPU at TP1,
supports reasoning and tool calls, and has official Dynamo agentic recipes for
both aggregated and disaggregated serving. Keeping the model fixed lets the
experiments attribute differences to serving topology rather than model quality.

## University program kit

`edu/` turns this lab into a reusable program for universities with idle
NVIDIA GPUs (A100 → B300): program plan, model catalog by GPU tier, sizing,
benchmarking methodology, coding-harness setup, campus-service operations,
a traces → fine-tuning roadmap, session agendas, and six hands-on labs.
Start at [`edu/README.md`](edu/README.md).

## Repository map

- `recordbook/index.html` — visual master recordbook with diagrams and results
- `results/` — compact, version-controlled benchmark summaries
- `docs/architecture.md` — system design and staged learning path
- `docs/decisions.md` — durable decision record
- `experiments/README.md` — experiment protocol and result conventions
- `notes/lab-notebook.md` — chronological observations and commands/results
- `scripts/` — repeatable preflight and cluster lifecycle scripts
- `config/pi-models.json` — reviewed Pi provider definition for the local API
- `deploy/` — site-specific Dynamo manifests (added after platform validation)
- `deploy/edu/` — portable launcher, Slurm job, and campus gateway stack
- `config/edu-models/` — model profiles per GPU tier; `config/harnesses/` — harness templates
- `tools/` — `sizing.py` (fit/KV estimator) and `summarize-aiperf.py` (Pareto charts)
- `edu/` — university session kit (modules, sessions, labs, dated research notes)
- `upstream/dynamo/` — ignored shallow checkout used as pinned source material

Serve the recordbook with working links to its local raw artifacts:

```bash
./scripts/serve-recordbook.sh
```

Open `http://127.0.0.1:8080/recordbook/`; for a remote node, use the SSH
tunnel printed by the script.

Raw benchmark exports, model weights, Enroot images, caches, and credentials are
intentionally ignored. Their durable conclusions belong in `results/` and the
notebook so the Git repository stays small and safe to share.

## Safety and reproducibility

- Credentials belong in `.env`, Kubernetes Secrets, or the shell; never commit
  them.
- The rootless Docker daemon and image layers live on node-local `/raid`. The
  model cache defaults to workspace `.state/model-cache` on shared NFS so it
  survives Slurm assigning a different node. Override `DYNAMO_MODEL_CACHE` for
  a deliberate node-local performance run after the checkpoint is staged.
- The reusable Enroot squashfs lives under ignored shared `.state/enroot/images`;
  its expanded root filesystem and runtime state default to node-local `/tmp`.
- Every benchmark records source revision, image digest, model revision,
  topology, request trace, concurrency, and raw artifacts.

## Quick status

See `notes/lab-notebook.md`. As of 2026-09-26 the lab runs Dynamo
`vllm-runtime:1.5.0` on a full 8 × B300 node. The 1.3.0 concurrency cliff for
hybrid Qwen models is gone
(`results/dynamo-1.5-hybrid-models-2026-09-26.md`). The measured feature
showcase is in `edu/08-dynamo-showcase.md`, covering KV-aware routing,
aggregated vs disaggregated, conditional disaggregation and multi-model serving.
The projectable version is `edu/showcase/index.html`. Showcase topologies
start with `./scripts/start-showcase.sh`; the scripts below are the original
Sessions 002–004 1.3.0 deployment.

## Local runbook

For a fresh node, verify the allocation and download the model if it is not
already present in the shared cache:

```bash
./scripts/preflight.sh
./scripts/download-model.sh
```

After every Slurm reallocation, the normal restart path is one command. It
reuses the shared model cache and Enroot image, recreates node-local state,
waits for readiness, validates both the API and Pi, and writes an allocation
manifest under `artifacts/restarts/`:

```bash
module load rootless-docker
cd /home/yagupta/experiments/inf_exps
./scripts/bootstrap-slurm.sh
```

Rootless Docker is suitable for aggregated serving but hides the host network
sysfs required by NIXL/UCX. Prepare the reusable Enroot image once, then launch
the 1P/2D deployment. On later Slurm nodes only the fast node-local expansion is
repeated automatically:

```bash
./scripts/prepare-enroot.sh
./scripts/start-enroot-disagg.sh --detach
./scripts/status-local.sh
./scripts/smoke-api.sh
PI_DYNAMO_MODEL=Qwen/Qwen3.5-122B-A10B ./scripts/smoke-pi.sh
./scripts/pi-local.sh
```

Run the pinned official AIPerf client with a conservative single-concurrency
baseline, then vary its environment-controlled workload explicitly:

```bash
./scripts/run-aiperf.sh
AIPERF_CONCURRENCY=2 AIPERF_REQUEST_COUNT=32 ./scripts/run-aiperf.sh
```

Use `./scripts/stop-local.sh` to stop Enroot, NATS, and etcd while retaining the
model cache and reusable image. `scripts/start-local-agg.sh` remains the Docker
aggregated baseline. The Docker `scripts/start-local-disagg.sh` is retained as
a diagnostic reference but cannot initialize UCX under this rootless daemon.

Secrets can be placed in the ignored `.env` file (start from `.env.example`).
The wrappers treat that file as the explicit workspace configuration, so it
takes precedence over inherited environment values.

Set `DYNAMO_HF_ANONYMOUS=1` for public-model operations that must guarantee no
Hugging Face credential is forwarded into a container.
