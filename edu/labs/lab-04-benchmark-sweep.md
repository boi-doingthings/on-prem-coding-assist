# Lab 4 — Benchmark sweep and the Pareto curve (60–75 min)

**You will:** measure how latency and throughput change with load, find the
safe operating point, and translate it into "students served".

Background: `edu/04-benchmarking.md`.

## 1. Chat profile sweep

```bash
export DYNAMO_SERVED_MODEL=<served name> DYNAMO_MODEL=<hf id for tokenizer>
export AIPERF_GPUS=<gpus behind the endpoint> AIPERF_EXPECTED_TOPOLOGY=any
# add AIPERF_RUNNER=local if Docker is unavailable (pip install aiperf)
SWEEP_PROFILE=chat SWEEP_CONCURRENCIES="1 4 16 64" ./scripts/sweep-aiperf.sh
```

## 2. Coding-agent profile sweep

```bash
SWEEP_PROFILE=coding-agent SWEEP_CONCURRENCIES="1 2 4 8 16 32" ./scripts/sweep-aiperf.sh
```

## 3. Compare on one chart

```bash
tools/summarize-aiperf.py artifacts/runs/*sweep-* --series-key series \
  --slo-tps-user 20 --slo-ttft-ms 3000 --duty-cycle 0.25 --out results/sweeps/lab4-<team>
```

Open the `.svg` in a browser; hover points for details.

## 4. Questions

1. At what concurrency does TTFT p99 cross your SLO? Is it prefill or decode
   that runs out first? (Hint: compare the two profiles' TTFT and ITL.)
2. How many active students does the node support for IDE-style use
   (duty 0.15) vs. autonomous agents (duty 0.6)?
3. Did any point *fail* (timeouts) rather than slow down? What should the
   gateway's concurrency cap be?
4. Run the `chat` sweep twice. How reproducible is tokens/s/GPU (± %)?

## Deliverable

Commit `results/sweeps/lab4-<team>.md/.svg` with a 3-sentence interpretation.
