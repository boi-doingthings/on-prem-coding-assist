# NVIDIA DSX OS — Inference Serving Stack

A **layered, inference-focused reference architecture** for the NVIDIA AI factory. It
starts at bare-metal provisioning (**BCM**) and climbs to serverless consumption
(**NVCF**). Each layer of the **DSX OS** turns raw GPU infrastructure into a self-service
inference cloud.

Open [`structure.html`](./structure.html) in a browser for the visual, interactive stack diagram.

> **How this relates to the campus kit (added 2026-09-26).** This is the
> production "AI factory" stack. The campus lab in this repository runs the
> same serving layer (Dynamo) directly on Slurm + Enroot instead of BCM +
> Kubernetes; see `../../diagrams/campus-to-ai-factory.svg` for the mapping.
>
> **Correction for Dynamo ≥ 1.5.0:** KVBM (the KV Block Manager) is
> *deprecated* in Dynamo 1.5.0 with removal targeted for 1.6.0. Use the
> engine's native KV offloading (vLLM `OffloadingConnector`, SGLang HiCache) or
> LMCache for GPU → CPU → disk tiering. The feature table below predates this.
> Measured on 8 × B300 in this lab, KV-aware routing gave up to 1.8× faster
> TTFT and +51% throughput/GPU on multi-turn agent sessions
> (`../../08-dynamo-showcase.md`).

---

## Architecture at a glance

```
┌─────────────────────────────────────────────────────────────┐
│  5 · NVCF — NVIDIA Cloud Functions      (serverless / top)   │  ← consume
│     Serverless GPU inference · scale-to-zero · OpenAI API    │
├─────────────────────────────────────────────────────────────┤
│  4 · Grove — Multi-node Inference Orchestration              │
│     Gang scheduling · topology-aware · PodClique / PodGang   │
├─────────────────────────────────────────────────────────────┤
│  3 · NVIDIA Dynamo — Distributed Inference Engine            │  ← serve
│     PD Disaggregation · Cache-Aware Routing · KVBM · Planner │
│     Backends:  TensorRT-LLM  ·  vLLM  ·  SGLang              │
├─────────────────────────────────────────────────────────────┤
│  2 · GPU Operator  +  Network Operator                       │
│     Drivers · MIG · DCGM · RDMA/RoCE · GPUDirect · SR-IOV    │
├─────────────────────────────────────────────────────────────┤
│  1 · BCM — Base Command Manager         (bare-metal / bottom)│  ← provision
│     Node provisioning · Kubernetes · monitoring · lifecycle  │
└─────────────────────────────────────────────────────────────┘
        ▲  abstraction / consumption increases upward
        ▼  hardware proximity increases downward
```

**Inference-focused**: every layer exists to move a request from an API call at the top
to tokens generated on GPUs at the bottom — as fast and cost-efficiently as possible.

---

## Layer 1 · BCM — Base Command Manager (foundation)

The bedrock IaaS layer (formerly *Bright Cluster Manager*). BCM provisions bare-metal GPU
nodes and stands up the Kubernetes cluster that the rest of the stack runs on.

- **Bare-metal provisioning** — image/PXE-based OS deployment across the GPU fleet.
- **Kubernetes deployment & management** — the orchestration substrate for all layers above.
- **Cluster monitoring & health** — metrics, alerts, and automated health checks.
- **GPU & driver management** — consistent node configuration at fleet scale.
- **Multi-tenant HPC + AI** — shared infrastructure for mixed workloads.

**DSX OS benefit:** Turns racks of GPU servers into a healthy, monitored, Kubernetes-ready
cluster in hours instead of weeks. Every layer above inherits a consistent, observable
foundation.

📄 [BCM 9.2 User Manual](https://support.brightcomputing.com/manuals/9.2/user-manual.pdf)

---

## Layer 2 · GPU Operator + Network Operator (hardware enablement)

Two Kubernetes-native operators that make accelerated hardware self-managing.

**GPU Operator** automates the full NVIDIA software lifecycle on every node:
- NVIDIA drivers, container toolkit, and Kubernetes device plugin
- **DCGM** telemetry/monitoring
- **MIG** (Multi-Instance GPU) partitioning
- Node Feature Discovery

**Network Operator** deploys the accelerated networking stack:
- Mellanox OFED / DOCA drivers
- **RDMA / RoCE** and **InfiniBand** support
- **GPUDirect** RDMA for direct GPU-to-GPU transfers
- **SR-IOV** and secondary networks for east-west traffic

**DSX OS benefit:** Removes manual driver/fabric wrangling and guarantees every node
exposes GPUs and RDMA networking consistently. GPUDirect + RoCE give Dynamo's disaggregated
KV transfers the low-latency fabric that makes multi-node inference fast.

🔗 [GPU Operator](https://github.com/NVIDIA/gpu-operator) · [Network Operator](https://github.com/Mellanox/network-operator)

---

## Layer 3 · NVIDIA Dynamo — Distributed Inference Engine (the brain)

A backend-agnostic, datacenter-scale serving framework. Dynamo runs the **same
disaggregated architecture across all three leading inference backends**:

| Backend | Disagg | Cache-Aware Routing | KVBM |
|---|---|---|---|
| **TensorRT-LLM** | ✅ | ✅ | ✅ |
| **vLLM** | ✅ | ✅ | ✅ |
| **SGLang** | ✅ | ✅ | ✅ |

### Key features

- **PD Disaggregation (Prefill / Decode)** — splits the compute-bound *prefill* phase and
  the memory-bound *decode* phase onto **separate, independently-scaled GPU pools**, so each
  phase runs on hardware tuned to its profile.
- **Cache-Aware Routing** — a KV-aware smart router sends each request to the worker that
  **already holds the matching KV cache**, giving up to **~2× faster time-to-first-token**
  and eliminating redundant prefill compute.
- **KV Block Manager (KVBM)** — hierarchically tiers KV cache across **GPU → CPU → SSD →
  remote**, extending effective context length beyond GPU memory.
- **SLA-driven Planner** — profiles live load and **right-sizes prefill/decode pools** to
  hit latency targets at the lowest TCO.
- **NIXL transfer library** — low-latency GPU-to-GPU data/KV movement; up to **~7× faster**
  model & replica startup.
- **Backend-agnostic control plane** — swap engines without re-architecting the service.

**DSX OS benefit:** Decouples the two phases of LLM inference so each scales on its own
economics, and reuses KV cache instead of recomputing it — dramatically higher
tokens/sec/GPU and lower latency. This is the core efficiency win of the whole factory.

🔗 [ai-dynamo/dynamo](https://github.com/ai-dynamo/dynamo)

---

## Layer 4 · Grove — Multi-Node Inference Orchestration

A single **declarative Kubernetes API** for orchestrating any AI inference workload — from
one pod to systems sharded across **tens of thousands of GPUs**. Grove models a full
disaggregated deployment (prefill, decode, router, leader/workers) as one coherent unit.

### Grove features & API concepts

- **PodClique** — a group of pods sharing a role (e.g. prefill, decode, frontend), each
  independently configured.
- **PodCliqueScalingGroup** — bundles cliques that must **scale and schedule together** as a
  gang.
- **PodCliqueSet / PodGang** — top-level replica object and scheduler API that guarantee
  **minimum-replica gang scheduling**.
- **Hierarchical gang scheduling** — all-or-nothing startup prevents partially-scheduled
  deployments and GPU deadlock.
- **Topology-aware placement** — co-locates tightly-coupled components inside **NVLink / rail
  domains** for fast interconnect.
- **Startup ordering** — enforces correct init sequences (e.g. MPI leader → workers).
- **Multi-level autoscaling** — scales roles independently while honoring gang constraints.

**DSX OS benefit:** Makes disaggregated, multi-node inference deployable and reliable. Gang
scheduling eliminates wasted GPUs from half-scheduled jobs; topology awareness keeps
prefill↔decode KV transfers on the fastest links — directly boosting throughput per dollar.

🔗 [ai-dynamo/grove](https://github.com/ai-dynamo/grove)

---

## Layer 5 · NVCF — NVIDIA Cloud Functions (serverless, top of stack)

The **consumption layer** of DSX OS. NVCF exposes models as **serverless functions and
endpoints**, so developers ship a model and NVCF manages the GPUs beneath.

- **Scale-to-zero autoscaling** — pay only for GPUs in use.
- **Function & endpoint lifecycle** — deploy, version, and route model services.
- **OpenAI-compatible APIs** — streaming, gRPC/HTTP inference.
- **Multi-tenant isolation, auth & metering** — safe self-service across teams.
- **Global multi-region routing** — serve close to the user.

**DSX OS benefit:** Turns the GPU cluster into a self-service, pay-per-use inference cloud.
Teams consume LLM / multimodal / classic-ML inference through a stable API without touching
nodes, operators, or schedulers — maximizing utilization and shrinking time-to-value.

🔗 [NVCF](https://github.com/NVIDIA/nvcf) · [NVIDIA DSX Documentation](https://docs.nvidia.com/dsx#dsx-os)

---

## How the layers work together

1. **BCM** provisions bare-metal nodes and the Kubernetes cluster.
2. **GPU + Network Operators** make GPUs and RDMA fabric first-class Kubernetes resources.
3. **Dynamo** serves models with disaggregated prefill/decode and cache-aware routing across
   TensorRT-LLM, vLLM, and SGLang.
4. **Grove** orchestrates those multi-node Dynamo deployments with gang scheduling and
   topology awareness.
5. **NVCF** exposes it all as serverless, self-service inference endpoints.

Together they form the **DSX OS** — a full-stack path from bare metal to serverless
inference.

---

## References

- [NVIDIA DSX Documentation](https://docs.nvidia.com/dsx#dsx-os)
- [BCM 9.2 User Manual (PDF)](https://support.brightcomputing.com/manuals/9.2/user-manual.pdf)
- [GPU Operator](https://github.com/NVIDIA/gpu-operator)
- [Network Operator](https://github.com/Mellanox/network-operator)
- [NVIDIA Dynamo](https://github.com/ai-dynamo/dynamo)
- [Grove](https://github.com/ai-dynamo/grove)
- [NVCF](https://github.com/NVIDIA/nvcf)

> Illustrative reference architecture. Feature details reflect the linked upstream projects
> and NVIDIA DSX documentation at the time of writing.
