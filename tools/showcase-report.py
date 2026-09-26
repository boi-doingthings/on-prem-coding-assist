#!/usr/bin/env python3
"""Compare showcase trace runs (scripts/showcase-trace.sh) as a table and a
small-multiples bar chart: one panel per metric, grouped by concurrency,
one fixed color per configuration.

    tools/showcase-report.py --series agg8-kv,agg8-rr \
        --metrics ttft_p50,ttft_p99,out_tps_gpu,cache_hit \
        --title "KV-aware vs round-robin routing" --out results/showcase/routing
"""

from __future__ import annotations

import argparse
import html
import json
import pathlib
import re

COLORS = ["#76b900", "#2a78d6", "#eb6834", "#4a3aa7"]  # NVIDIA green first, then palette order
INK, INK2, GRID, BG = "#0b0b0b", "#52514e", "#e4e3df", "#fcfcfb"

METRICS = {
    # key: (label, unit, lower_is_better, extractor)
    "ttft_p50": ("TTFT p50", "s", True, lambda d, c: d["time_to_first_token"]["p50"] / 1000),
    "ttft_p99": ("TTFT p99", "s", True, lambda d, c: d["time_to_first_token"]["p99"] / 1000),
    "itl_p50": ("Inter-token latency p50", "ms", True, lambda d, c: d["inter_token_latency"]["p50"]),
    "itl_p99": ("Inter-token latency p99", "ms", True, lambda d, c: d["inter_token_latency"]["p99"]),
    "e2e_p50": ("Request latency p50", "s", True, lambda d, c: d["request_latency"]["p50"] / 1000),
    "tps_user": ("Output tok/s per user p50", "tok/s", False,
                 lambda d, c: d["output_token_throughput_per_user"]["p50"]),
    "out_tps_gpu": ("Output tok/s per GPU", "tok/s", False,
                    lambda d, c: d["output_token_throughput"]["avg"] / c["gpus"]),
    "total_tps_gpu": ("Total (in+out) tok/s per GPU", "tok/s", False,
                      lambda d, c: d["total_token_throughput"]["avg"] / c["gpus"]),
    "req_s": ("Requests/s", "req/s", False, lambda d, c: d["request_throughput"]["avg"]),
    "cache_hit": ("Prefix-cache hit rate", "%", False,
                  lambda d, c: 100 * c["cache"]["prefix_cache_hit_rate"] if c.get("cache") else None),
}


def load(runs_dir: pathlib.Path, series: list[str]) -> list[dict]:
    rows = []
    for d in sorted(runs_dir.glob("*-showcase-*")):
        manifest = dict(line.split("=", 1) for line in (d / "manifest.env").read_text().splitlines() if "=" in line) \
            if (d / "manifest.env").exists() else {}
        label = manifest.get("series", "")
        export = d / "profile_export_aiperf.json"
        if label not in series or not export.exists():
            continue
        data = json.loads(export.read_text())
        errors = sum(int(e.get("count", 0)) for e in data.get("error_summary") or [])
        cache = json.loads((d / "cache-stats.json").read_text()) if (d / "cache-stats.json").exists() else None
        ctx = {"gpus": int(manifest.get("gpus", 8)), "cache": cache}
        row = {"series": label, "concurrency": int(manifest["concurrency"]), "run": d.name,
               "valid": int(data["request_count"]["avg"]), "errors": errors}
        for key, (_, _, _, fn) in METRICS.items():
            try:
                row[key] = fn(data, ctx)
            except (KeyError, TypeError):
                row[key] = None
        rows.append(row)
    # keep the latest run per (series, concurrency)
    latest: dict[tuple, dict] = {}
    for r in rows:
        latest[(r["series"], r["concurrency"])] = r
    return sorted(latest.values(), key=lambda r: (r["concurrency"], series.index(r["series"])))


def fmt(v, unit):
    if v is None:
        return "—"
    if unit in ("s",):
        return f"{v:.2f}"
    if unit == "%":
        return f"{v:.0f}%"
    return f"{v:,.1f}" if v < 100 else f"{v:,.0f}"


def table(rows, series, metrics) -> str:
    head = "| Concurrency | Configuration | Valid/errors | " + " | ".join(
        f"{METRICS[m][0]} ({METRICS[m][1]})" for m in metrics) + " |"
    lines = [head, "|" + " --- |" * (3 + len(metrics))]
    for r in rows:
        lines.append(f"| {r['concurrency']} | {r['series']} | {r['valid']}/{r['errors']} | " +
                     " | ".join(fmt(r[m], METRICS[m][1]) for m in metrics) + " |")
    # headline ratios vs the first series
    base = series[0]
    notes = []
    for c in sorted({r["concurrency"] for r in rows}):
        b = next((r for r in rows if r["series"] == base and r["concurrency"] == c), None)
        for other in series[1:]:
            o = next((r for r in rows if r["series"] == other and r["concurrency"] == c), None)
            if not b or not o:
                continue
            parts = []
            for m in metrics:
                if b[m] and o[m] and METRICS[m][1] != "%":
                    lower = METRICS[m][2]
                    ratio = (o[m] / b[m]) if lower else (b[m] / o[m])
                    parts.append(f"{METRICS[m][0]} {ratio:.2f}×")
            notes.append(f"- c{c}: **{base}** vs {other}: " + ", ".join(parts) +
                         " (>1 means the first configuration is better)")
    return "\n".join(lines + [""] + notes) + "\n"


def nice(v: float) -> float:
    import math
    if v <= 0:
        return 1.0
    mag = 10 ** math.floor(math.log10(v))
    return next(m * mag for m in (1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10) if m * mag >= v)


def chart(rows, series, metrics, title, subtitle, labels) -> str:
    concs = sorted({r["concurrency"] for r in rows})
    panel_w, panel_h, gap = 360, 300, 40
    left, top = 60, 150
    width = left * 2 + len(metrics) * panel_w + (len(metrics) - 1) * gap
    height = top + panel_h + 50
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
           f'font-family="Helvetica, Arial, sans-serif" role="img" aria-label="{html.escape(title)}">',
           f'<rect width="{width}" height="{height}" fill="{BG}"/>',
           f'<text x="{left}" y="50" font-size="28" font-weight="700" fill="{INK}">{html.escape(title)}</text>',
           f'<text x="{left}" y="82" font-size="16" fill="{INK2}">{html.escape(subtitle)}</text>']
    for i, name in enumerate(series):
        x = left + i * 260
        out.append(f'<rect x="{x}" y="100" width="18" height="18" rx="3" fill="{COLORS[i]}"/>')
        out.append(f'<text x="{x + 26}" y="114" font-size="16" fill="{INK2}">{html.escape(labels[i])}</text>')
    for p, m in enumerate(metrics):
        label, unit, lower, _ = METRICS[m]
        px = left + p * (panel_w + gap)
        vals = [r[m] for r in rows if r[m] is not None]
        vmax = nice(max(vals) * 1.12) if vals else 1
        out.append(f'<text x="{px}" y="{top - 8}" font-size="17" font-weight="700" fill="{INK}">'
                   f'{html.escape(label)} ({unit}) {"↓ better" if lower else "↑ better"}</text>')
        base_y = top + panel_h
        for g in range(5):
            gy = base_y - panel_h * g / 4
            out.append(f'<line x1="{px}" y1="{gy:.1f}" x2="{px + panel_w}" y2="{gy:.1f}" stroke="{GRID}" stroke-width="1"/>')
            out.append(f'<text x="{px - 6}" y="{gy + 4:.1f}" font-size="12" fill="{INK2}" text-anchor="end">'
                       f'{fmt(vmax * g / 4, unit)}</text>')
        group_w = panel_w / len(concs)
        bar_w = min(26, (group_w - 16) / len(series))
        for gi, c in enumerate(concs):
            gx = px + gi * group_w + (group_w - bar_w * len(series) - 2 * (len(series) - 1)) / 2
            for si, name in enumerate(series):
                r = next((r for r in rows if r["series"] == name and r["concurrency"] == c), None)
                if not r or r[m] is None:
                    continue
                h = panel_h * r[m] / vmax
                x = gx + si * (bar_w + 2)
                out.append(f'<rect x="{x:.1f}" y="{base_y - h:.1f}" width="{bar_w:.1f}" height="{h:.1f}" '
                           f'fill="{COLORS[si]}"><title>{html.escape(name)} c{c}: {fmt(r[m], unit)} {unit}</title></rect>')
                out.append(f'<text x="{x + bar_w / 2:.1f}" y="{base_y - h - 5:.1f}" font-size="11" fill="{INK2}" '
                           f'text-anchor="middle">{fmt(r[m], unit)}</text>')
            out.append(f'<text x="{px + gi * group_w + group_w / 2:.1f}" y="{base_y + 20}" font-size="14" '
                       f'fill="{INK2}" text-anchor="middle">c{c}</text>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--runs", type=pathlib.Path, default=pathlib.Path("artifacts/runs"))
    p.add_argument("--series", required=True, help="comma list; first is the reference")
    p.add_argument("--metrics", default="ttft_p50,ttft_p99,out_tps_gpu,cache_hit")
    p.add_argument("--title", default="Showcase comparison")
    p.add_argument("--labels", help="comma list of display names for --series")
    p.add_argument("--subtitle", default="Qwen3.5-122B-A10B NVFP4 · 8 × B300 · Dynamo 1.5.0 · agentic coding trace "
                   "(64K median prompt, shared prefixes) · x-axis = concurrent requests")
    p.add_argument("--out", type=pathlib.Path)
    p.add_argument("--png", action="store_true")
    args = p.parse_args()
    series = args.series.split(",")
    metrics = args.metrics.split(",")
    rows = load(args.runs, series)
    text = table(rows, series, metrics)
    print(text)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        labels = args.labels.split(",") if args.labels else series
        svg = chart(rows, series, metrics, args.title, args.subtitle, labels)
        (args.out.parent / f"{args.out.name}.svg").write_text(svg)
        (args.out.parent / f"{args.out.name}.md").write_text(f"# {args.title}\n\n![chart]({args.out.name}.svg)\n\n{text}")
        (args.out.parent / f"{args.out.name}.json").write_text(json.dumps(rows, indent=2) + "\n")
        if args.png:
            import cairosvg
            cairosvg.svg2png(bytestring=svg.encode(), write_to=str(args.out.parent / f"{args.out.name}.png"), scale=2)
        print(f"wrote {args.out}.svg/.md/.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
