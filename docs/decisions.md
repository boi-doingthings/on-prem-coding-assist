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
