# Running a campus AI service on idle GPUs

This module turns a benchmarked endpoint into a service that students and
staff can rely on. It must never get in the way of research jobs.

## 1. Reference architecture

```text
                 campus network (SSO)                         private cluster network
students ─┬─► Open WebUI (chat, RAG) ──┐
          ├─► harnesses (OpenCode, Cline, Codex, Pi …) ─┼─► LiteLLM gateway ──► Dynamo frontend :8000 ──► workers (Slurm job)
eval jobs ┘   (Harbor, mini-SWE-agent, OpenHands SDK)   │   keys · quotas · limits       KV-aware router       any GPU tier
                                                         │   usage logs · opt-in traces
                                                         └─► Langfuse / OTel (consented traces only)
```

- **Dynamo** runs as a Slurm job on GPU nodes (`deploy/edu/serve.sbatch`) and
  is reachable only from the gateway host.
- **LiteLLM** (`deploy/edu/gateway/`) runs on a small CPU VM. It issues one
  virtual key per user or course, enforces RPM/TPM and per-key parallelism,
  keeps usage accounting in Postgres, and caps total concurrency to the
  backend below the measured failure point.
- **Open WebUI** gives non-programmers a ChatGPT-style UI with campus SSO.
  LibreChat (MIT) is an alternative with built-in token balances.
- **Tracing** (Langfuse, OTel) is off by default and enabled only for
  consenting users (module 07).

## 2. Harvesting idle GPUs without hurting research

| Pattern | How | When |
| --- | --- | --- |
| **Preemptible QOS** | `sbatch --qos=<scavenger> --requeue deploy/edu/serve.sbatch`; research jobs preempt it; Slurm requeues it on the next free node | default |
| **Serving windows** | cron/scrontab submits the job for nights, weekends, and term breaks; `--time` ends it | GPUs busy during the day |
| **Reserved slice** | 1 node (or a MIG/partial node on A100/H100) permanently reserved for the service | high adoption, budget approved |
| **Burst replicas** | a second job adds replicas when the gateway queue grows (workers join the same frontend with `DYNAMO_DISCOVERY=etcd`) | term peaks, deadlines |

Operational requirements:

- The **model cache lives on shared storage** (`DYNAMO_MODEL_CACHE`). A
  requeue then costs a model load (1–5 min for ≤ 80 GB from fast storage)
  rather than a download.
- The **compile cache** (`DYNAMO_CACHE_ROOT`) is persisted per partition,
  which avoids re-paying torch.compile/FlashInfer autotuning on every restart.
- The gateway returns 503 with a clear "service is scaling back up" message
  while the backend restarts. Harnesses retry, so students just see a delay.
- **Health watchdog.** This lab observed engines that stop returning bytes
  under overload while `/health` still reports healthy. Probe with a real
  1-token completion every minute and requeue the job after two failures.

## 3. Capacity and fairness

1. Run the sweep (`04-benchmarking.md`) with the `coding-agent` profile and
   note the highest SLO-passing concurrency *C* and the first failing point.
   Re-run it after every image or model upgrade: in this lab an engine upgrade
   moved the failure point from c7 to beyond c32.
2. Set `DYNAMO_MAX_PARALLEL` on the gateway at or below *C*, and always below
   the failing point. Excess requests queue at the gateway instead of wedging
   the engine.
3. Per-key limits (defaults in `scripts/gateway-issue-keys.sh`):
   `max_parallel_requests=2`, `rpm=30`, `tpm=400K`. Agents burst, and these
   limits stop one runaway loop from starving a class.
4. Separate aliases for separate uses: `campus-coder` for interactive use and a
   batch alias (lower priority, off-peak only) for grading, synthetic data,
   and evals.
5. Report weekly: active users, requests, tokens, p95 latency, and queue time
   at the gateway. The measured duty cycle then replaces the planning
   assumption.

## 4. Issuing access

```bash
# per course, from an LMS roster export (user_id,email)
GATEWAY_URL=https://llm.<campus>.edu LITELLM_MASTER_KEY=... \
  ./scripts/gateway-issue-keys.sh roster.csv CS4803-fall26
# → keys-CS4803-fall26.csv (mode 600) to distribute through the LMS
```

Students then run `./scripts/setup-harness.sh opencode` with
`CAMPUS_LLM_URL=https://llm.<campus>.edu/v1` and their key. Chat users sign in
to Open WebUI through SSO and never see a key.

## 5. Governance checklist (review with IT security and legal)

- [ ] **Data classification**: which data students may paste (public course
      material yes; FERPA/HIPAA/export-controlled data only if approved).
- [ ] **Logging**: gateway stores usage metadata by default. Prompt and
      response bodies are **not** stored (`store_prompts_in_spend_logs: false`)
      unless the user has opted in to research tracing.
- [ ] **Retention**: e.g. usage metadata 1 year, consented traces per the
      IRB/consent form, everything else not stored.
- [ ] **Consent and IRB**: required before traces are used for research or
      fine-tuning (module 07).
- [ ] **Model licenses** reviewed (`02-model-catalog.md` §5).
- [ ] **Acceptable-use notice** shown in Open WebUI and in the harness setup
      guide.
- [ ] **Network**: Dynamo ports (8000, worker system ports, NIXL/UCX) are
      never exposed beyond the cluster. The LoRA admin API on
      `DYN_SYSTEM_PORT` is admin-only.
- [ ] **Supply chain**: pin image digests for Dynamo, LiteLLM, and Open WebUI.
      Review before upgrading. LiteLLM 1.82.7/1.82.8 on PyPI were compromised
      (2026-03-24).
- [ ] **Harness telemetry** disabled in lab images
      (`config/harnesses/telemetry-off.sh`).
- [ ] **Academic integrity**: per-course keys let instructors disable access
      during assessments. Visibility into individual usage follows campus
      policy.

## 6. Observability

- Dynamo frontend metrics: `http://<node>:8000/metrics`
  (`dynamo_frontend_*`). Worker metrics are on each `DYN_SYSTEM_PORT`.
- Upstream ships a local Prometheus, Grafana, and DCGM stack with dashboards
  (`upstream/dynamo/dev/docker-observability.yml`,
  `dev/observability/grafana_dashboards/`). This lab had no DCGM exporter, so
  `scripts/run-aiperf.sh` samples `nvidia-smi` beside every benchmark.
- LiteLLM exposes Prometheus `/metrics`, and its Postgres spend logs hold
  per-key usage.
- Key alerts: backend 5xx or timeouts, gateway queue time p95 over 30 s, GPU
  memory at the utilization ceiling with falling throughput, and the Slurm job
  not running during a serving window.

## 7. Operations runbook (condensed)

| Situation | Action |
| --- | --- |
| Job preempted/requeued | nothing; watch it come back (`squeue`, gateway 503 → 200) |
| Requests hang, `/health` OK | 1-token probe fails → `scancel` + resubmit (or let the watchdog do it); record the concurrency at failure |
| Upgrade Dynamo or model | new job on a spare node, run canary + smoke + short sweep, switch `DYNAMO_BASE_URL` on the gateway, keep the old job for rollback |
| New semester | re-issue course keys, re-run capacity sweep if the model changed, publish the updated harness guide |
| Suspected abuse | revoke the key (`/key/delete`), review gateway metadata per policy |
