# Lab notebook

## 2026-09-21 — Session 001: discovery and target selection

### Host inventory

- Host: `dgx06`, Linux 6.8, x86_64
- CPU: 2 x Intel Xeon 6776P, 256 logical CPUs total
- RAM: 2.0 TiB
- GPUs: 4 x NVIDIA B300 SXM6 AC, 275,040 MiB each
- Driver: 580.126.20
- Rootless Docker storage: `/raid/docker/tmp/docker-container-storage-1004`
- Local `/raid`: approximately 23 TiB available
- NVIDIA Container Toolkit: 1.20.0; CDI devices present
- Fabric: active 100 Gb/s InfiniBand HCAs observed
- GPU fabric: all four GPUs are mutually connected over NV18

Host `nvidia-smi` is hidden from the restricted shell, but a disposable CUDA
container successfully enumerated all four GPUs. GPU access is therefore valid
through the configured rootless Docker daemon.

The current managed session and rootless Docker daemon are pinned to CPUs 69
and 197 (`Cpus_allowed_list: 69,197`). This is enough for control-plane and API
smoke testing but invalidates serious throughput/latency benchmarking. Before
performance runs, launch the daemon from a wider NUMA-aware CPU allocation and
rerun the preflight.

### Software inventory

- Docker 29.6.2; Compose v5.3.1
- `kubectl` and Helm installed, but no Kubernetes context/cluster
- Pi managed install 0.86.1 exists at `~/.pi/agent`
- Pi currently fails because `node` is absent from `PATH`
- Dynamo shallow checkout pinned at
  `a67b954e74942a4e3106391c21ebf3cae152849e`

### Selected first production-like target

Use the official Blackwell Qwen3.5 NVFP4 recipe as the baseline. The upstream
reported disaggregated profile is 1P/2D on three B200 GPUs and is a close match
for this four-B300 host. Adaptations must be explicit: accept the B300 node
label, preserve the upstream no-MTP caveat, and verify rather than assume B300
kernel compatibility.

### Open setup items

- Bootstrap a GPU-enabled local Kubernetes cluster.
- Install Dynamo platform and validate DGD CRDs.
- Determine whether the NVIDIA checkpoint requires an HF token in this
  environment; do not log token values.
- Restore a Node.js runtime for Pi and add a workspace-local model provider
  configuration after the Dynamo endpoint passes tool-call smoke tests.

### Kubernetes bootstrap result

Minikube v1.39.0 with Kubernetes v1.34.3 failed before kubelet startup. The
rootless Docker node inherited the Slurm cgroup-v1 path
`/system.slice/slurmd.service`; systemd in the nested node could not create its
manager cgroup and exited 255. This is an infrastructure limitation, not a
Dynamo failure. The active deployment path is the supported local Dynamo CLI
topology. Kubernetes operator/planner work is deferred to a cgroup-capable
allocation or existing cluster.

### Runtime pin

- Image: `nvcr.io/nvidia/ai-dynamo/vllm-runtime:1.3.0`
- Digest: `sha256:effd250754b8a70517c27eab8f18463b395a7b2a8e868fd919226c3180636939`

The first local worker launch exited before download because the named cache
volume was not writable by the image's default user. The Kubernetes recipe uses
`runAsUser: 0`; the local wrapper was updated with the equivalent `--user 0:0`.

Pi 0.86.1 requires Node >=22.19.0. A checksum-verified Node 22.23.2 LTS runtime
is installed under the ignored workspace `bin/` directory. Pi now starts and
recognizes the `dynamo-local/Qwen/Qwen3.5-122B-A10B` provider/model definition.

The runtime's automatic ModelExpress fallback began a serial Hugging Face
download. It was stopped before serving and replaced with the upstream recipe's
pre-download pattern: `hf download` with `HF_XET_HIGH_PERFORMANCE=1`, writing to
the same persistent named volume.

The first pre-download invocation did not inherit the session's existing
`HF_TOKEN` and was anonymously throttled. It was restarted with the token passed
by environment name (never printed or written); the cache resumed in place.

### Canary deployment and CPU-contention result

To separate serving/configuration errors from the large checkpoint transfer, a
`Qwen/Qwen3-0.6B` canary was deployed on GPU 0 with the same Dynamo frontend,
etcd discovery, NATS, vLLM worker, and KV-aware router. The worker initialized,
registered its chat/completions endpoints, and reported a healthy topology.

The first OpenAI-compatible text request succeeded (HTTP 200, 16 input tokens,
32 output tokens), but took 49.4 seconds: TTFT 22.3 seconds and average ITL
869 ms. A simultaneous tool-call request later stalled. With the large-model
Xet downloader competing for the allocation's only two logical CPUs, etcd lost
its lease and Dynamo drained the frontend. This is a useful negative control:
the GPU was healthy, but CPU starvation made the service unusable. These values
are diagnostic observations and must not be reported as B300 performance.

The resumable large-model download was paused at approximately 11 GiB in the
persistent Docker volume to free CPU for retesting. During the restart, the
host's already-failed `nvidia-persistenced.service` became a hard blocker for
new GPU containers: the NVIDIA runtime requires
`/run/nvidia-persistenced/socket`, which no longer exists. Restoring the system
service requires host administrator privileges. Existing cache data and lab
configuration are retained.

A diagnostic container inspection accidentally rendered the inherited Hugging
Face credential in the interactive tool transcript. The value was never
written to this repository, and the stopped container containing it was
removed, but the token must be rotated before this transcript is shared.

## 2026-09-22 — Session 002: correctly sized allocation

- Slurm job: `7967`, node `dgx10`, eight-hour `maint` allocation
- Resources: 4 x B300, 128 CPU threads, approximately 2 TiB host RAM
- CPU affinity: `0-63,128-191`, spanning both NUMA nodes
- `nvidia-persistenced`: active; runtime socket present
- Rootless Docker inherited all 128 allocated CPUs
- Disposable CUDA 13.0 container enumerated all four B300s successfully

The Docker data root and named model volume were node-local, so the partial
checkpoint from `dgx06` did not follow the allocation. The lab now defaults to
an ignored NFS-backed cache at `.state/model-cache`; model downloads survive
future Slurm node changes, while Docker image layers remain on fast local RAID.
Because Docker is rootless, container UID 0 maps to the invoking host user and
is the correct identity for writing this NFS bind mount. A trial using container
UID 1004 mapped to a subordinate UID and was denied; the downloader therefore
uses container `0:0` without gaining host root privileges.

Allocated GPU 3 contains a 1.6 GiB `cuopt_server` process from expired job
`7339`, owned by another user and running for more than five days. The process
was revalidated before a user-authorized `SIGTERM`, but Unix permissions denied
the signal and passwordless sudo is unavailable. Experiments will avoid GPU 3
until an administrator removes the stale process.

### End-to-end canary result

The `Qwen/Qwen3-0.6B` canary downloaded to the persistent cache, initialized on
GPU 0, and registered Dynamo's `generate`, KV-indexer, router-discovery,
metrics, and cache-control endpoints. Direct OpenAI-compatible API validation
passed:

- Chat completion returned HTTP 200.
- The 32-token exact-text probe exhausted its cap in reasoning content before
  emitting visible text; this is a tiny reasoning-model/test-cap limitation.
- The tool-call probe returned `finish_reason: tool_calls`, function
  `get_weather`, and valid arguments `{"city":"Seattle"}`.
- Pi 0.86.1 connected through provider `dynamo-local` and returned exactly
  `PI_DYNAMO_OK`.

This closes the functional path: Pi -> OpenAI-compatible frontend -> Dynamo
KV-aware router -> vLLM worker -> structured response. Unlike Session 001, the
same test completed in seconds with the correctly sized 128-CPU allocation.

The main checkpoint's high-performance Xet transfer completed eight of nine
weight shards, then one CDN range request remained idle for more than seven
minutes despite internal retries. The downloader was stopped without deleting
the cache and resumed through standard Hub HTTP using `DYNAMO_DISABLE_XET=1`.

### Qwen3.5 aggregated deployment

The complete checkpoint is pinned at snapshot
`98915d837c4e7c87ac8296d02e89de19b3207e6d`. Two TP1 replicas were launched on
GPUs 0 and 1 behind one Dynamo KV-aware router. Both workers registered separate
`generate` instances and enabled chat, completions, and responses endpoints.

Observed initialization details per replica:

- Model load: approximately 73.22 GiB and 194 seconds from shared NFS
- Device memory after KV/cache warmup: approximately 246 GiB
- Available KV cache: 163.6 GiB / 13,559,243 tokens
- Engine-reported maximum concurrency at 262,144 tokens: 51.72x
- NVFP4 ModelOpt weights, FP8 KV cache, FlashInfer TRT-LLM MoE autotuning,
  prefix caching, multimodal routing, and CUDA graphs all initialized on B300

The real target passed the OpenAI-compatible tool-call test with function
`get_weather` and arguments `{"city":"Seattle"}`. Pi then returned exactly
`PI_DYNAMO_OK` using `dynamo-local/Qwen/Qwen3.5-122B-A10B`.

A bounded non-streaming diagnostic probe (16 requests, concurrency 8, 64 output
tokens) completed with 16/16 successes and no errors in 4.56 seconds. It
observed 224.38 output tokens/s, 3.51 requests/s, 0.76 s p50 and 3.92 s p99
end-to-end latency. Recent router logs showed selections split 10/9 across the
two workers (including adjacent smoke traffic), confirming both replicas were
active. These numbers are a functional baseline, not a publication-grade
benchmark; raw results are under
`artifacts/runs/20260922T141156Z-agg-smoke-c8/`.

### Qwen3.5 disaggregated deployment

The initial 1P/2D attempt under rootless Docker failed before engine startup:
UCX could not enumerate `/sys/class/net` because the container received an
empty `/sys`. A read-only bind and rootless `--privileged` could not repair a
path absent from the daemon's own mount namespace. This is a container-runtime
constraint, not a Dynamo or GPU failure.

The existing Dynamo Docker image was converted once to a reusable Enroot
squashfs. Enroot exposed the host's Ethernet and InfiniBand interfaces plus the
allocated B300s, and a standalone NIXL probe instantiated UCX successfully.
The expanded Enroot rootfs is node-local and writable: FlashInfer's Blackwell
TRT-LLM MoE backend creates runtime symlinks inside `flashinfer_cubin`, while
HOME, XDG, Triton, vLLM, and Transformers caches are redirected to `/tmp`.

The working topology is:

- GPU 0: one prefill worker, NIXL `kv_producer`
- GPUs 1 and 2: two decode workers, NIXL `kv_consumer`
- Frontend: OpenAI-compatible HTTP on port 8000 with KV routing
- Discovery/event plane: etcd, NATS, and ZMQ KV events

All three engines instantiated UCX-backed NIXL agents. The frontend health
response listed one `dynamo.prefill.generate` instance and two
`dynamo.backend.generate` instances. Each GPU allocated approximately 245 GiB
after warmup; the prefill engine reported 163.6 GiB / 13,559,243 KV tokens and
the decode engines each reported 163.08 GiB / 13,515,896 KV tokens.

Correctness checks passed end to end. The API emitted a structured
`get_weather` call with `{"city":"Seattle"}`, and Pi returned exactly
`PI_DYNAMO_OK`. The 32-token literal response probe again spent its entire cap
in reasoning content, which is a probe/model interaction rather than a serving
failure.

The matched bounded diagnostic probe (16 requests, concurrency 8, 64 output
tokens) completed 16/16 with no errors in 2.82 seconds. It observed 362.51
output tokens/s, 5.66 requests/s, 1.14 s p50, and 1.91 s p99 end-to-end
latency. Dynamo request metrics recorded one prefill worker and both decode
worker IDs. NIXL reported 9 and 7 successful transfers to the two decode
workers, approximately 100.03 MB per transfer, at observed aggregate samples
of 480 and 814 MB/s. These are functional diagnostic numbers, not a
publication-grade comparison; the raw results are under
`artifacts/runs/20260922T150151Z-disagg-smoke-c8/`.

### Slurm restart automation and AIPerf

Job `7967` reached its eight-hour limit during the first AIPerf c8
investigation. Job `7975` was allocated on `dgx10` with the same four B300s,
128 CPUs, and 1 TiB RAM. The shared 78 GiB model cache and 16 GiB Enroot
squashfs survived. `scripts/bootstrap-slurm.sh` now turns reallocation into a
single command: it records allocation/GPU/runtime metadata, removes stale PID
state, recreates node-local Enroot state when necessary, requires one
`prefill.generate` and two distinct `backend.generate` instances, then runs API,
tool-call, and Pi checks. The first healthy evidence bundle is
`artifacts/restarts/20260922T182330Z-job-7975-dgx10/`.

The readiness gate was strengthened during validation. HTTP `/health` reports
healthy before workers exist, and counting instance rows is incorrect because
one worker registers several endpoints. The final gate checks component and
endpoint identity. Pi returned exactly `PI_DYNAMO_OK` after startup and again
after incident recovery.

Official NVIDIA AIPerf 0.12.0 was run from image
`nvcr.io/nvidia/ai-dynamo/aiperf:0.12.0` (digest
`sha256:d22eb02bccadcd2acbbd905a1742f1e642f2bdd7bc3a0377cebda685a233902d`).
The controlled synthetic workload used streaming chat, server token counts,
temperature 0, `ignore_eos=true`, target ISL 800, OSL 64, seed 42, three c1
warmups, and 16 measured requests:

| Concurrency | Result | Req/s | Output tok/s | TTFT avg/p99 | ITL avg | E2E avg/p99 |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | 16/16 | 1.58 | 100.91 | 224/240 ms | 6.44 ms | 630/669 ms |
| 2 | 16/16 | 2.56 | 163.57 | 338/383 ms | 6.97 ms | 777/824 ms |
| 4 | 16/16 | 3.99 | 255.24 | 464/832 ms | 7.81 ms | 956/1307 ms |
| 8 | invalid: 8 timed out, 8 cancelled | — | — | >120 s | — | >120 s |

The c8 result reproduced the earlier failure on a fresh allocation: sequential
warmups completed, then all eight requests in the first burst received no bytes
before the 120-second client timeout. Cancelling the run left discovery healthy
but a new c1 data-plane request also timed out. A full Dynamo process restart
restored service; the recovery evidence bundle is
`artifacts/restarts/20260922T183015Z-job-7975-dgx10/`. This rules out Slurm
expiry as the primary cause and narrows the failure to a serving/scheduling
interaction at concurrency eight. The leading hypothesis is a disaggregated
hybrid-cache interaction, but this is not yet proven.

AIPerf discovered Dynamo's Prometheus endpoint. DCGM exporters were not running
on ports 9400/9401, so AIPerf collected no GPU telemetry. Dynamo also did not
return cached-token usage details, preventing AIPerf from calculating
prompt-cache-read metrics. Raw artifacts are under the timestamped
`artifacts/runs/20260922T182*-aiperf-*` directories. The curated visual summary
is `recordbook/index.html`.

## 2026-09-22 — Session 003: restart on job 8005 and repository publication

Slurm job `7975` expired at its eight-hour limit. Job `8005` started on
`dgx10` with four B300s, 128 CPUs, and 1 TiB RAM. The bootstrap reused the
shared model cache and Enroot squashfs, removed the stale launcher PID, and
restored the exact 1P/2D topology. The structured tool-call test passed and Pi
returned exactly `PI_DYNAMO_OK`. Evidence is stored locally at
`artifacts/restarts/20260923T044539Z-job-8005-dgx10/`.

The shareable lab sources are being published to
`boi-doingthings/on-prem-coding-assist`. Large/generated artifacts, model
weights, Enroot state, downloaded runtimes, logs, and secrets remain ignored.
The compact AIPerf results in `results/` are the version-controlled bridge back
to the full local raw exports.
