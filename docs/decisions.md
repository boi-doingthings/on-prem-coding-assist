# Decision log

## D-001: Pin upstream source

- Date: 2026-09-21
- Decision: Use Dynamo commit `a67b954e74942a4e3106391c21ebf3cae152849e`
  as the initial source reference.
- Reason: Recipes and platform APIs evolve quickly; a SHA makes observations
  reproducible.

## D-002: Start with Qwen3.5-122B-A10B-NVFP4

- Date: 2026-09-21
- Decision: Use `nvidia/Qwen3.5-122B-A10B-NVFP4`, served as
  `Qwen/Qwen3.5-122B-A10B`.
- Reason: Official Blackwell agentic recipes, single-GPU TP1 fit, tool calling,
  reasoning, long context, and both aggregated/disaggregated topologies.
- Constraint: Do not enable MTP initially. Upstream documents a concurrent
  prefix-caching crash for this hybrid DeltaNet architecture.

## D-003: Kubernetes for the main lab

- Date: 2026-09-21
- Decision: Use a local GPU-enabled Kubernetes cluster for the main path, with
  direct Docker/CLI only as a diagnostic fallback.
- Reason: DGD/DGDR, native discovery, operator reconciliation, observability,
  and planner behavior are central Dynamo concepts.

## D-004: Compare topologies with one model and workload

- Date: 2026-09-21
- Decision: Establish an aggregated baseline before disaggregation and keep the
  model, trace, sampling parameters, and SLO constant.
- Reason: This isolates the effect of Dynamo features.

## D-005: Use local CLI until a cgroup-capable Kubernetes allocation exists

- Date: 2026-09-21
- Decision: Supersede D-003 for the current allocation. Validate Dynamo and Pi
  with the official local vLLM runtime; move the same experiment to the Dynamo
  Kubernetes Platform when the node can run nested systemd/kubelet correctly.
- Reason: Minikube inherited the Slurm cgroup-v1 path and failed before kubelet
  startup. This is a host allocation constraint, not evidence about Dynamo.

## D-006: Use Enroot for NIXL disaggregation on Slurm

- Date: 2026-09-22
- Decision: Run the Dynamo runtime in Enroot for single-node disaggregated
  experiments while retaining rootless Docker for NATS, etcd, image staging,
  and the aggregated baseline.
- Reason: NIXL's UCX backend must enumerate host network interfaces through
  `/sys/class/net`. Rootless Docker cannot expose that host sysfs path from its
  daemon mount namespace; Enroot exposes both host interfaces and Slurm's GPU
  allocation without requiring rootful Docker.
- Implementation: Keep the squashfs and model cache on shared NFS, expand the
  rootfs under node-local `/tmp`, and use writable mode because FlashInfer's
  B300 TRT-LLM backend creates runtime symlinks in `flashinfer_cubin`.

## D-007: Package the lab as a university program kit

- Date: 2026-09-26
- Decision: Add `edu/` (modules, sessions, labs), portable tooling
  (`deploy/edu/`, `tools/`, profiles, harness templates), and dated research
  notes, while keeping the B300 experiments as the worked case study.
- Reason: The same curriculum must run on A100 through B300; only the model
  profile and the demo change per site.

## D-008: Portable single-node launcher with file discovery

- Date: 2026-09-26
- Decision: `deploy/edu/serve.sh` runs frontend + N aggregated replicas inside
  one runtime container with `--discovery-backend file` by default, and
  `DYNAMO_DISCOVERY=etcd` for routing experiments and multi-job scale-out.
- Reason: Universities differ in container runtimes (Pyxis, Apptainer, Enroot,
  Docker); a single process tree with no etcd/NATS is the most portable
  workshop path. Upstream documents KV events as unavailable in file mode, so
  KV-routing experiments use etcd+NATS.

## D-009: vLLM backend as the default everywhere

- Date: 2026-09-26
- Decision: Profiles default to the vLLM backend.
- Reason: Broadest quantization coverage on Ampere (Marlin FP8/MXFP4/INT4),
  and the only backend with supported Dynamo LoRA serving, which the
  traces → fine-tuning roadmap needs.

## D-010: Sweeps stop at the first failed concurrency

- Date: 2026-09-26
- Decision: `scripts/sweep-aiperf.sh` stops at the first point with errors,
  and summaries mark failures instead of averaging them.
- Reason: Engines in this lab wedged (no bytes returned, restart required)
  rather than degrading; continuing a sweep against a wedged server produces
  misleading numbers and wastes allocation time. The gateway concurrency cap
  is set below the first failure.

## D-011: Dynamo vllm-runtime 1.5.0 is the default

- Date: 2026-09-26
- Decision: Use `nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.5.0` (digest
  `sha256:d7f73fdc…e761`) for all new work; keep 1.3.0 only to reproduce
  Sessions 002–004.
- Reason: Hybrid DeltaNet models wedged at ~7–8 concurrent requests on 1.3.0
  and ran cleanly to c128 on 1.5.0; one B300 served ~4× more tokens.

## D-012: Cold-cache A/B by seed, one variable at a time

- Date: 2026-09-26
- Decision: Showcase comparisons change only the serving feature (router,
  topology, policy), run against the same workers where possible (parallel
  frontends), and use a fresh AIPerf seed per run instead of cache flushes.
- Reason: The worker cache-flush route is unavailable in this mode, and
  restarts cost ~7 minutes; seeded synthesis preserves prefix structure while
  guaranteeing no cross-run cache hits.
