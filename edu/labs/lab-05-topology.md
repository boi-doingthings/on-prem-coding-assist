# Lab 5 — Topology experiments: replicas, TP, routing, disaggregation (75 min)

**You will:** change one serving variable at a time and measure its effect.
Requires a node with ≥ 2 GPUs (4 preferred).

Keep model, image, workload profile, and concurrency list identical across
runs; name each sweep with `SWEEP_LABEL` so the chart legend is readable.

## Experiment A — replicas vs. tensor parallelism

```bash
# A1: 2 replicas x TP1
DYNAMO_GPUS=0,1 DYNAMO_TP=1 ...serve...   SWEEP_LABEL=A1-2xTP1
# A2: 1 replica x TP2
DYNAMO_GPUS=0,1 DYNAMO_TP=2 ...serve...   SWEEP_LABEL=A2-1xTP2
```

Expectation to test: TP2 gives better tokens/s/user at low load; two TP1
replicas give more tokens/s/GPU at high load.

## Experiment B — KV-aware vs. round-robin routing

Use the `coding-agent` profile, or better, a replayed trace with shared
prefixes (`07-traces-to-fine-tuning.md` §2), since random prompts share no
prefix.

```bash
DYNAMO_ROUTER_MODE=kv          SWEEP_LABEL=B1-kv
DYNAMO_ROUTER_MODE=round-robin SWEEP_LABEL=B2-rr
```

Measure TTFT p50/p99 — prefix-cache hits turn prefill into a lookup.

For this experiment run discovery through etcd + NATS so KV events are
guaranteed to reach the router (upstream docs list KV events as unavailable in
`file` discovery mode):

```bash
docker compose -f deploy/local/compose.yaml up -d nats etcd   # on the GPU node
export DYNAMO_DISCOVERY=etcd ETCD_ENDPOINTS=http://127.0.0.1:2379 NATS_SERVER=nats://127.0.0.1:4222
```

## Experiment C — aggregated vs. disaggregated (Hopper/Blackwell, NIXL)

Reference implementation for single-node 1 prefill / 2 decode:
`deploy/local/start-disagg.sh` and `scripts/start-enroot-disagg.sh`.
Compare with two aggregated replicas on the `chat` and `coding-agent`
profiles. In this lab (B300, Qwen3.5-122B), aggregation won on short prompts
and disaggregation hit a lower concurrency cliff — can you find the prompt
length where the answer flips on your hardware?

## Report

One Pareto chart per experiment (`tools/summarize-aiperf.py … --out`), plus:
the variable changed, the result, and whether it matched the expectation.
