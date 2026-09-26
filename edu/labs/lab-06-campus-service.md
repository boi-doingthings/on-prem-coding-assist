# Lab 6 — Operating a campus service (60 min)

**You will:** put the LiteLLM gateway and Open WebUI in front of Dynamo,
issue per-user keys with limits, cap backend concurrency below the measured
failure point, and practise a failure drill.

Background: `edu/06-campus-service.md`. Run on a CPU VM or login-adjacent
service node with Docker; Dynamo stays on the GPU node.

## 1. Bring up the gateway

```bash
cd deploy/edu/gateway
cp gateway.env.example gateway.env && chmod 600 gateway.env
# fill: image digests, secrets (openssl rand -hex 32), DYNAMO_BASE_URL,
# DYNAMO_MAX_PARALLEL = highest safe concurrency from your Lab 4 sweep
docker compose --env-file gateway.env up -d
curl -s localhost:4000/health/liveliness
```

## 2. Issue keys and connect

```bash
printf 'alice,alice@example.edu\nbob,bob@example.edu\n' > roster.csv
GATEWAY_URL=http://localhost:4000 LITELLM_MASTER_KEY=... \
  ../../../scripts/gateway-issue-keys.sh roster.csv lab6
CAMPUS_LLM_URL=http://localhost:4000/v1 CAMPUS_LLM_MODEL=campus-coder \
  CAMPUS_LLM_KEY=<alice key> ../../../scripts/setup-harness.sh opencode
```

Open WebUI: http://localhost:3000 (create the admin account, then disable signup
or configure OIDC).

## 3. Show that limits work

1. With Alice's key, start 5 parallel requests. Only 2 may run
   (`max_parallel_requests=2`): record whether the rest queue or are
   rejected with 429, and what the harness does with each.
2. Run the Lab 4 sweep *through the gateway* at a concurrency above
   `DYNAMO_MAX_PARALLEL`. Compare TTFT with the direct sweep: the gateway turns
   an engine failure into queueing delay.

## 4. Failure drill

1. Start `WATCHDOG_MODEL=<served name> ./scripts/watchdog.sh` in a terminal.
2. Kill one worker process on the GPU node (`pkill -f "dynamo.vllm"`) or
   `scancel` the serving job.
3. Observe: watchdog failures, gateway errors, harness retry behaviour.
   Resubmit `deploy/edu/serve.sbatch` and time the recovery (load time from
   the shared model cache).

## 5. Discuss

- Which usage data should the gateway keep, for how long, and who may see it?
  Write the retention line for your site profile.
- What would you change for exam week?
