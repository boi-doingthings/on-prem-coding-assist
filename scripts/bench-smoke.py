#!/usr/bin/env python3
"""Small dependency-free Dynamo concurrency probe; not a full benchmark."""

from __future__ import annotations

import argparse
import concurrent.futures
import datetime as dt
import json
import math
import pathlib
import statistics
import time
import urllib.request


def percentile(values: list[float], quantile: float) -> float:
    ordered = sorted(values)
    index = max(0, math.ceil(quantile * len(ordered)) - 1)
    return ordered[index]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--model", default="Qwen/Qwen3.5-122B-A10B")
    parser.add_argument("--concurrency", type=int, default=8)
    parser.add_argument("--requests", type=int, default=16)
    parser.add_argument("--max-tokens", type=int, default=64)
    parser.add_argument("--output-root", default="artifacts/runs")
    parser.add_argument("--slug", default="smoke")
    args = parser.parse_args()

    shared_prefix = (
        "You are reviewing a Python service. "
        "The service has an HTTP frontend, a KV-aware router, and two model workers. "
        "Return one concise sentence explaining the requested serving concept. " * 24
    )

    def send(index: int) -> dict[str, object]:
        body = {
            "model": args.model,
            "messages": [
                {
                    "role": "user",
                    "content": f"{shared_prefix}\nRequest {index}: explain prefix-cache affinity.",
                }
            ],
            "temperature": 0,
            "max_tokens": args.max_tokens,
        }
        request = urllib.request.Request(
            f"{args.base_url}/v1/chat/completions",
            data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json"},
        )
        started = time.perf_counter()
        try:
            with urllib.request.urlopen(request, timeout=300) as response:
                payload = json.load(response)
            elapsed = time.perf_counter() - started
            usage = payload.get("usage", {})
            return {
                "index": index,
                "ok": True,
                "latency_seconds": elapsed,
                "prompt_tokens": usage.get("prompt_tokens", 0),
                "completion_tokens": usage.get("completion_tokens", 0),
                "finish_reason": payload["choices"][0].get("finish_reason"),
            }
        except Exception as error:  # noqa: BLE001 - preserve probe failures
            return {
                "index": index,
                "ok": False,
                "latency_seconds": time.perf_counter() - started,
                "error": repr(error),
            }

    wall_started = time.perf_counter()
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.concurrency) as pool:
        results = list(pool.map(send, range(args.requests)))
    wall_seconds = time.perf_counter() - wall_started

    successes = [result for result in results if result["ok"]]
    latencies = [float(result["latency_seconds"]) for result in successes]
    output_tokens = sum(int(result.get("completion_tokens", 0)) for result in successes)
    summary = {
        "kind": "smoke-concurrency-probe",
        "warning": "Non-streaming diagnostic probe; not a publication-grade benchmark.",
        "model": args.model,
        "concurrency": args.concurrency,
        "requests": args.requests,
        "successes": len(successes),
        "errors": args.requests - len(successes),
        "wall_seconds": wall_seconds,
        "requests_per_second": len(successes) / wall_seconds,
        "output_tokens_per_second": output_tokens / wall_seconds,
        "latency_seconds": {
            "mean": statistics.mean(latencies) if latencies else None,
            "p50": percentile(latencies, 0.50) if latencies else None,
            "p90": percentile(latencies, 0.90) if latencies else None,
            "p99": percentile(latencies, 0.99) if latencies else None,
        },
    }

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = pathlib.Path(args.output_root) / f"{stamp}-{args.slug}-c{args.concurrency}"
    run_dir.mkdir(parents=True, exist_ok=False)
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    (run_dir / "raw-results.json").write_text(json.dumps(results, indent=2) + "\n")
    print(json.dumps(summary, indent=2))
    print(f"artifact_dir={run_dir}")


if __name__ == "__main__":
    main()
