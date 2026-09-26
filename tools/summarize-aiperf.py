#!/usr/bin/env python3
"""Summarize AIPerf run directories into a table, CSV, and a Pareto SVG.

Each run directory is one produced by scripts/run-aiperf.sh (manifest.env +
profile_export_aiperf.json). Runs are grouped into series by a manifest key
(default: run name without the concurrency suffix), which is how a sweep of
one topology/model becomes one curve.

The Pareto chart is the standard way to read inference performance:
  x = output tokens/s per user (interactivity: how fast one student sees text)
  y = output tokens/s per GPU  (efficiency: how many students the box serves)
Moving right costs throughput; every deployment choice is a different curve.

Examples:
  tools/summarize-aiperf.py artifacts/runs/*sweep-qwen* --gpus 3 --out results/sweep
  tools/summarize-aiperf.py DIR... --slo-ttft-ms 2000 --slo-tps-user 20
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import pathlib
import re
import sys

SERIES_COLORS = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948"]
SERIES_COLORS_DARK = ["#3987e5", "#d95926", "#199e70", "#c98500", "#d55181", "#008300", "#9085e9", "#e66767"]
MARKERS = ["circle", "square", "diamond", "triangle"]


def read_manifest(path: pathlib.Path) -> dict[str, str]:
    values = {}
    if path.is_file():
        for line in path.read_text().splitlines():
            if "=" in line:
                key, value = line.split("=", 1)
                values[key] = value
    return values


def metric(data: dict, name: str, stat: str = "avg") -> float | None:
    value = (data.get(name) or {}).get(stat)
    return float(value) if value is not None else None


def load_run(run_dir: pathlib.Path, gpus: int, series_key: str | None) -> dict | None:
    export = run_dir / "profile_export_aiperf.json"
    manifest = read_manifest(run_dir / "manifest.env")
    requested = int(manifest.get("request_count", 0) or 0)
    base = re.sub(r"^\d{8}T\d{6}Z-", "", run_dir.name)
    series = manifest.get(series_key, "") if series_key else re.sub(r"-c\d+(-.*)?$", "", base)
    if manifest.get("gpus", "").isdigit():
        gpus = int(manifest["gpus"])
    row = {
        "run": run_dir.name,
        "gpus": gpus,
        "series": series or base,
        "concurrency": int(manifest.get("concurrency", 0) or 0),
        "isl": manifest.get("isl"),
        "osl": manifest.get("osl"),
        "requested": requested,
    }
    if not export.is_file():
        return {**row, "valid": 0, "status": "no export (crashed or wedged)"}
    data = json.loads(export.read_text())
    valid = int(metric(data, "request_count") or 0)
    errors = sum(int(e.get("count", 0)) for e in data.get("error_summary") or [])
    ok = valid > 0 and errors == 0 and (not requested or valid >= requested) and not data.get("was_cancelled")
    out_tps = metric(data, "output_token_throughput")
    row.update({
        "valid": valid,
        "errors": errors,
        "status": "ok" if ok else "FAILED",
        "req_s": metric(data, "request_throughput"),
        "out_tps": out_tps,
        "out_tps_per_gpu": out_tps / gpus if out_tps else None,
        "tps_user_p50": metric(data, "output_token_throughput_per_user", "p50"),
        "ttft_p50_ms": metric(data, "time_to_first_token", "p50"),
        "ttft_p99_ms": metric(data, "time_to_first_token", "p99"),
        "itl_p50_ms": metric(data, "inter_token_latency", "p50"),
        "itl_p99_ms": metric(data, "inter_token_latency", "p99"),
        "e2e_p99_ms": metric(data, "request_latency", "p99"),
        "isl_observed": metric(data, "input_sequence_length"),
    })
    return row


def fmt(value, digits=0) -> str:
    if value is None:
        return "—"
    return f"{value:,.{digits}f}"


def markdown(rows: list[dict], args) -> str:
    lines = [
        "| Series | Conc | Valid | Req/s | Out tok/s | GPUs | Out tok/s/GPU | tok/s/user p50 "
        "| TTFT p50/p99 ms | ITL p50/p99 ms | E2E p99 ms | SLO |",
        "| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for r in rows:
        if r["status"] != "ok":
            lines.append(f"| {r['series']} | {r['concurrency']} | **{r['status']}** ({r.get('valid', 0)}/{r['requested']}) "
                         "| — | — | — | — | — | — | — | — | ✗ |")
            continue
        lines.append(
            f"| {r['series']} | {r['concurrency']} | {r['valid']}/{r['requested']} | {fmt(r['req_s'], 2)} "
            f"| {fmt(r['out_tps'])} | {r['gpus']} | {fmt(r['out_tps_per_gpu'])} | {fmt(r['tps_user_p50'], 1)} "
            f"| {fmt(r['ttft_p50_ms'])}/{fmt(r['ttft_p99_ms'])} | {fmt(r['itl_p50_ms'], 1)}/{fmt(r['itl_p99_ms'], 1)} "
            f"| {fmt(r['e2e_p99_ms'])} | {'✓' if r['slo_ok'] else '✗'} |")
    lines.append("")
    lines.append(f"SLO: TTFT p99 ≤ {args.slo_ttft_ms:.0f} ms and per-user decode ≥ {args.slo_tps_user:.0f} tok/s. "
                 "Failed points are failures, not low throughput — never average them in.")
    for series in dict.fromkeys(r["series"] for r in rows):
        passing = [r for r in rows if r["series"] == series and r["status"] == "ok" and r["slo_ok"]]
        if passing:
            best = max(passing, key=lambda r: r["concurrency"])
            users = best["concurrency"] / args.duty_cycle
            lines.append(f"- **{series}**: highest SLO-passing concurrency = {best['concurrency']} "
                         f"→ ≈ {users:,.0f} active users at an assumed {args.duty_cycle:.0%} duty cycle "
                         "(fraction of wall-clock a user has a request in flight; measure yours from gateway logs).")
    return "\n".join(lines) + "\n"


def marker(shape: str, x: float, y: float, color: str, ring: str) -> str:
    common = f'class="mk" fill="{color}" stroke="{ring}" stroke-width="2"'
    if shape == "square":
        return f'<rect x="{x - 4.5:.1f}" y="{y - 4.5:.1f}" width="9" height="9" rx="1.5" {common}/>'
    if shape == "diamond":
        return f'<path d="M{x:.1f},{y - 6:.1f} L{x + 6:.1f},{y:.1f} L{x:.1f},{y + 6:.1f} L{x - 6:.1f},{y:.1f} Z" {common}/>'
    if shape == "triangle":
        return f'<path d="M{x:.1f},{y - 6:.1f} L{x + 6:.1f},{y + 4.5:.1f} L{x - 6:.1f},{y + 4.5:.1f} Z" {common}/>'
    return f'<circle cx="{x:.1f}" cy="{y:.1f}" r="5" {common}/>'


def nice_max(value: float) -> float:
    if value <= 0:
        return 1.0
    magnitude = 10 ** (len(str(int(value))) - 1)
    for step in (1, 1.2, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10):
        if step * magnitude >= value:
            return step * magnitude
    return 10 * magnitude


def pareto_svg(rows: list[dict], args) -> str:
    """Colors are presentation attributes (so PowerPoint/cairo render them);
    a CSS media query re-colors for dark mode in browsers."""
    good = [r for r in rows if r["status"] == "ok" and r["tps_user_p50"] and r["out_tps_per_gpu"]]
    series = list(dict.fromkeys(r["series"] for r in good))[:8]
    width, height = 900, 470
    left, right, top, bottom = 72, 290, 56, 56
    pw, ph = width - left - right, height - top - bottom
    xmax = nice_max(max((r["tps_user_p50"] for r in good), default=1) * 1.05)
    ymax = nice_max(max((r["out_tps_per_gpu"] for r in good), default=1) * 1.05)
    sx = lambda v: left + v / xmax * pw  # noqa: E731
    sy = lambda v: top + ph - v / ymax * ph  # noqa: E731
    bg, ink, ink2, grid = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"

    dark = "".join(f".s{i} .line{{stroke:{c}}}.s{i} .mk{{fill:{c}}}" for i, c in enumerate(SERIES_COLORS_DARK))
    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" role="img" '
        f'aria-label="{html.escape(args.title)}" font-family="Helvetica, Arial, sans-serif">',
        "<style>@media (prefers-color-scheme: dark){"
        ".bg{fill:#1a1a19}.mk{stroke:#1a1a19}.grid{stroke:#383835}.t{fill:#ffffff}"
        ".txt{fill:#c3c2b7}.slo{stroke:#c3c2b7}" + dark + "}"
        ".pt:hover .mk{stroke-width:3}</style>",
        f'<rect class="bg" width="{width}" height="{height}" fill="{bg}"/>',
        f'<text class="t" x="{left}" y="24" fill="{ink}" font-size="15" font-weight="600">'
        f"{html.escape(args.title)}</text>",
        f'<text class="txt" x="{left}" y="42" fill="{ink2}" font-size="12">'
        "Each point is one concurrency level (label = c). Up and right is better.</text>",
    ]
    text = lambda x, y, body, anchor="start", extra="": (  # noqa: E731
        f'<text class="txt" x="{x}" y="{y}" fill="{ink2}" font-size="12" text-anchor="{anchor}"{extra}>{body}</text>')
    for i in range(6):
        gx, gy = xmax * i / 5, ymax * i / 5
        out.append(f'<line class="grid" x1="{sx(gx):.1f}" y1="{top}" x2="{sx(gx):.1f}" y2="{top + ph}" '
                   f'stroke="{grid}" stroke-width="1"/>')
        out.append(f'<line class="grid" x1="{left}" y1="{sy(gy):.1f}" x2="{left + pw}" y2="{sy(gy):.1f}" '
                   f'stroke="{grid}" stroke-width="1"/>')
        out.append(text(f"{sx(gx):.1f}", top + ph + 18, f"{gx:,.0f}", "middle"))
        out.append(text(left - 8, f"{sy(gy) + 4:.1f}", f"{gy:,.0f}", "end"))
    out.append(text(f"{left + pw / 2:.0f}", height - 14, "Output tokens/s per user (p50) → more interactive", "middle"))
    out.append(text(0, 0, "Output tokens/s per GPU → more users per box", "middle",
                    f' transform="translate(18 {top + ph / 2:.0f}) rotate(-90)"'))
    if args.slo_tps_user:
        x = sx(args.slo_tps_user)
        out.append(f'<line class="slo" x1="{x:.1f}" y1="{top}" x2="{x:.1f}" y2="{top + ph}" '
                   f'stroke="{ink2}" stroke-width="1"/>')
        out.append(text(f"{x + 4:.1f}", top + 12, f"SLO ≥ {args.slo_tps_user:.0f} tok/s/user"))

    placed: list[tuple[float, float]] = []  # label anchors; skip labels that would collide

    def free(x: float, y: float) -> bool:
        if any(abs(x - px) < 34 and abs(y - py) < 16 for px, py in placed):
            return False
        placed.append((x, y))
        return True

    for i, name in enumerate(series):
        color = SERIES_COLORS[i]
        shape = MARKERS[i % len(MARKERS)]
        pts = sorted((r for r in good if r["series"] == name), key=lambda r: r["concurrency"])
        path = " ".join(f"{'M' if j == 0 else 'L'}{sx(r['tps_user_p50']):.1f},{sy(r['out_tps_per_gpu']):.1f}"
                        for j, r in enumerate(pts))
        line = (f'fill="none" stroke="{color}" stroke-width="2" stroke-linejoin="round" '
                'stroke-linecap="round"')
        out.append(f'<g class="s{i}"><path class="line" d="{path}" {line}/>')
        for r in pts:
            x, y = sx(r["tps_user_p50"]), sy(r["out_tps_per_gpu"])
            tip = (f"{name} — concurrency {r['concurrency']}\n{r['out_tps_per_gpu']:,.0f} tok/s/GPU, "
                   f"{r['tps_user_p50']:,.1f} tok/s/user\nTTFT p99 {fmt(r['ttft_p99_ms'])} ms")
            out.append(f'<g class="pt"><title>{html.escape(tip)}</title>'
                       f'<circle cx="{x:.1f}" cy="{y:.1f}" r="12" fill="{bg}" fill-opacity="0"/>'
                       + marker(shape, x, y, color, bg)
                       + (text(f"{x + 8:.1f}", f"{y - 8:.1f}", f"c{r['concurrency']}")
                          if free(x + 8, y - 8) else "") + "</g>")
        out.append("</g>")
        ly, lx = top + 8 + i * 22, left + pw + 20
        out.append(f'<g class="s{i}"><line class="line" x1="{lx}" y1="{ly}" x2="{lx + 22}" y2="{ly}" {line}/>'
                   + marker(shape, lx + 11, ly, color, bg)
                   + text(lx + 30, ly + 4, html.escape(getattr(args, "label_map", {}).get(name, name)[:40])) + "</g>")
    out.append("</svg>")
    return "\n".join(out) + "\n"


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("runs", nargs="+", type=pathlib.Path)
    p.add_argument("--gpus", type=int, default=1,
                   help="GPUs serving the endpoint when manifest.env has no gpus= entry")
    p.add_argument("--series-key", help="manifest.env key to group by (default: run name minus -cN)")
    p.add_argument("--slo-ttft-ms", type=float, default=2000)
    p.add_argument("--slo-tps-user", type=float, default=20)
    p.add_argument("--duty-cycle", type=float, default=0.15,
                   help="fraction of time an active user has a request in flight (coding agents: 0.1-0.5)")
    p.add_argument("--title", default="Throughput vs interactivity")
    p.add_argument("--labels", help="display names as series=label pairs separated by ;")
    p.add_argument("--out", type=pathlib.Path, help="write <out>.md, <out>.csv, <out>.svg")
    args = p.parse_args()

    args.label_map = dict(pair.split("=", 1) for pair in args.labels.split(";")) if args.labels else {}
    rows = [r for d in args.runs if d.is_dir() and (r := load_run(d, args.gpus, args.series_key))]
    if not rows:
        print("No run directories found.", file=sys.stderr)
        return 2
    rows.sort(key=lambda r: (r["series"], r["concurrency"]))
    for r in rows:
        r["slo_ok"] = (r["status"] == "ok" and (r.get("ttft_p99_ms") or 1e12) <= args.slo_ttft_ms
                       and (r.get("tps_user_p50") or 0) >= args.slo_tps_user)

    table = markdown(rows, args)
    print(table)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        # Append extensions: with_suffix() would truncate names like "qwen3.6-…".
        path = lambda ext: args.out.parent / f"{args.out.name}.{ext}"  # noqa: E731
        path("md").write_text(f"# {args.title}\n\n![Pareto]({args.out.name}.svg)\n\n{table}")
        with path("csv").open("w", newline="") as handle:
            fields = list(dict.fromkeys(k for r in rows for k in r))
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        path("svg").write_text(pareto_svg(rows, args))
        print(f"wrote {args.out}.md/.csv/.svg")
    return 0


if __name__ == "__main__":
    sys.exit(main())
