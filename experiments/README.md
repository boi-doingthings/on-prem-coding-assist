# Experiment protocol

Each run gets a directory under `artifacts/runs/<UTC timestamp>-<slug>/` with:

- `metadata.env` — non-secret revisions, image digests, topology, and flags
- `request.json` or trace checksum
- `raw/` — unmodified benchmark and metrics output
- `summary.json` — normalized metrics
- `notes.md` — anomalies and interpretation

## Required controls

1. Warm the model and tokenizer before measurement.
2. Run cold-cache and warm-prefix series separately.
3. Use identical prompts, output-token caps, and sampling parameters.
4. Sweep concurrency; do not compare only each topology's favorite point.
5. Repeat steady-state points at least three times.
6. Record p50/p90/p99 TTFT, ITL, end-to-end latency, throughput, and errors.
7. For Pi tasks, also record task success, test outcome, tool calls, retries,
   input/output tokens, and wall-clock time.

## Initial matrix

| Series | Topology | Router | GPUs | Purpose |
| --- | --- | --- | ---: | --- |
| A | Aggregated, 2 replicas | KV-aware | 2 | Upstream baseline |
| B | Aggregated, 4 replicas | KV-aware | 4 | Scale-out efficiency |
| C | Aggregated, 4 replicas | round-robin | 4 | Prefix-affinity value |
| D | Disaggregated, 1P/2D | KV-aware | 3 | Upstream disagg baseline |
| E | Disaggregated, 1P/3D | KV-aware | 4 | Decode scaling |

