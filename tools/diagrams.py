#!/usr/bin/env python3
"""Generate the presentation architecture diagrams (16:9 SVG, optional PNG).

    tools/diagrams.py                     # writes edu/diagrams/*.svg
    tools/diagrams.py --png               # also *.png at 2x (needs cairosvg)

All colors are presentation attributes (no CSS variables) so the SVGs import
cleanly into PowerPoint/Keynote/Google Slides. Edit the layouts below; the
helpers keep typography and colors consistent across diagrams.
"""

from __future__ import annotations

import argparse
import html
import pathlib

W, H = 1600, 900
FONT = "Helvetica, Arial, sans-serif"

# Role colors: (fill, stroke, text)
C = {
    "client": ("#e8f1fc", "#2a78d6", "#0d366b"),
    "dynamo": ("#eef7df", "#5f9400", "#233a00"),     # NVIDIA-green family
    "dynamo_strong": ("#76b900", "#5f9400", "#ffffff"),
    "engine": ("#ffffff", "#5f9400", "#233a00"),
    "kv": ("#fdeee6", "#eb6834", "#6b2a0e"),
    "infra": ("#f0efec", "#8a8984", "#2e2d2a"),
    "gpu": ("#1f1f1d", "#1f1f1d", "#ffffff"),
    "note": ("#fcfcfb", "#c9c8c2", "#52514e"),
    "warn": ("#fdecec", "#e34948", "#6e1414"),
}
INK, INK2, BG = "#0b0b0b", "#52514e", "#fcfcfb"
ARROW = {"default": "#52514e", "kv": "#eb6834", "dynamo": "#5f9400", "client": "#2a78d6"}


class Svg:
    def __init__(self, title: str, subtitle: str = ""):
        self.parts: list[str] = []
        self.title, self.subtitle = title, subtitle

    def add(self, s: str) -> None:
        self.parts.append(s)

    def text(self, x, y, s, size=18, color=INK, weight="400", anchor="start", italic=False):
        style = ' font-style="italic"' if italic else ""
        for i, line in enumerate(str(s).split("\n")):
            self.add(f'<text x="{x}" y="{y + i * size * 1.25:.1f}" font-size="{size}" fill="{color}" '
                     f'font-weight="{weight}" text-anchor="{anchor}"{style}>{html.escape(line)}</text>')

    def box(self, x, y, w, h, role="dynamo", title="", body="", r=10, title_size=19, body_size=14,
            dashed=False, align="middle"):
        fill, stroke, tc = C[role]
        dash = ' stroke-dasharray="7 5"' if dashed else ""
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}" '
                 f'stroke="{stroke}" stroke-width="2"{dash}/>')
        cx = x + w / 2 if align == "middle" else x + 16
        lines = body.split("\n") if body else []
        tlines = title.split("\n") if title else []
        total = len(tlines) * title_size * 1.25 + len(lines) * body_size * 1.3 + (6 if tlines and lines else 0)
        ty = y + h / 2 - total / 2 + (title_size if tlines else body_size) * 0.8
        if title:
            self.text(cx, ty, title, title_size, tc, "700", align)
            ty += (len(tlines) - 1) * title_size * 1.25 + title_size * 0.5 + body_size * 1.1
        for i, line in enumerate(lines):
            self.text(cx, ty + i * body_size * 1.3, line, body_size, tc if role != "note" else INK2, "400", align)

    def arrow(self, pts, kind="default", width=2.5, label="", label_at=0.5, dashed=False, both=False,
              label_dy=-8, label_size=14):
        color = ARROW[kind]
        mid = f"m{kind}"
        d = "M" + " L".join(f"{x:.1f},{y:.1f}" for x, y in pts)
        dash = ' stroke-dasharray="8 6"' if dashed else ""
        start = f' marker-start="url(#{mid}s)"' if both else ""
        self.add(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{width}"{dash} '
                 f'marker-end="url(#{mid})"{start}/>')
        if label:
            (x1, y1), (x2, y2) = pts[0], pts[-1]
            if len(pts) > 2:
                (x1, y1), (x2, y2) = pts[len(pts) // 2 - 1], pts[len(pts) // 2]
            lx, ly = x1 + (x2 - x1) * label_at, y1 + (y2 - y1) * label_at
            self.text(lx, ly + label_dy, label, label_size, color, "600", "middle")

    def gpu(self, x, y, w=120, h=64, label="GPU", sub="", role="gpu"):
        fill, stroke, tc = C[role]
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
        self.text(x + w / 2, y + h / 2 - (4 if sub else -6), label, 16, tc, "700", "middle")
        if sub:
            self.text(x + w / 2, y + h / 2 + 16, sub, 12, tc, "400", "middle")

    def render(self) -> str:
        defs = "".join(
            f'<marker id="m{k}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
            f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{v}"/></marker>'
            f'<marker id="m{k}s" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="7" markerHeight="7" '
            f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{v}"/></marker>'
            for k, v in ARROW.items())
        head = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
                f'font-family="{FONT}" role="img" aria-label="{html.escape(self.title)}">',
                f"<defs>{defs}</defs>", f'<rect width="{W}" height="{H}" fill="{BG}"/>']
        self.parts, body = [], self.parts
        self.text(60, 70, self.title, 36, INK, "700")
        if self.subtitle:
            self.text(60, 108, self.subtitle, 20, INK2)
        return "\n".join(head + self.parts + body + ["</svg>"]) + "\n"


def legend(s: Svg, x, y, items):
    for i, (role, label) in enumerate(items):
        fill, stroke, _ = C[role]
        s.add(f'<rect x="{x + i * 230}" y="{y}" width="22" height="16" rx="3" fill="{fill}" stroke="{stroke}" stroke-width="2"/>')
        s.text(x + i * 230 + 30, y + 14, label, 15, INK2)


# ---------------------------------------------------------------- diagrams

def dynamo_architecture() -> Svg:
    s = Svg("NVIDIA Dynamo: one serving layer for every open model",
            "OpenAI/Anthropic-compatible APIs in front, KV-aware routing in the middle, any engine on any NVIDIA GPU behind")
    # clients
    s.box(60, 170, 260, 520, "client", "", "")
    s.text(190, 205, "Clients", 22, C["client"][2], "700", "middle")
    for i, (t, b) in enumerate([("Coding agents", "OpenCode · Cline · Codex\nQwen Code · Pi · Aider"),
                                ("Chat & course tools", "Open WebUI · LibreChat"),
                                ("Evals & research", "Harbor · mini-SWE-agent\nOpenHands SDK · AIPerf")]):
        s.box(80, 230 + i * 150, 220, 125, "note", t, b, title_size=17, body_size=13)
    # gateway
    s.box(345, 300, 140, 200, "infra", "Campus\ngateway", "keys · quotas\nlimits · logs", title_size=17, body_size=13)
    s.arrow([(320, 400), (345, 400)], "client")
    # frontend + router
    s.box(560, 170, 300, 250, "dynamo", "Frontend", "OpenAI /v1/chat/completions\n/v1/responses\nAnthropic /v1/messages\n"
          "chat template · tokenizer\ntool & reasoning parsers", body_size=14)
    s.box(560, 440, 300, 250, "dynamo_strong", "KV-aware router", "global index of every\nworker's cached KV blocks\n"
          "cost = uncached prefill\n+ current load\n→ pick the cheapest worker", body_size=15)
    s.arrow([(485, 360), (560, 360)], "client", label="HTTP", label_dy=-8, label_size=13)
    s.arrow([(710, 420), (710, 440)], "dynamo")
    # workers
    s.box(950, 170, 590, 520, "dynamo", "", "")
    s.text(1245, 205, "Workers (Slurm job or Kubernetes pods)", 20, C["dynamo"][2], "700", "middle")
    s.box(970, 230, 225, 200, "engine", "Prefill workers", "read the prompt\n(compute-bound)\nbuild KV cache", body_size=14)
    s.box(1295, 230, 225, 200, "engine", "Decode workers", "generate tokens\n(memory-bound)\nhold many streams", body_size=14)
    s.arrow([(1195, 320), (1295, 320)], "kv", width=5, label="NIXL", label_dy=-12, label_size=15)
    s.text(1245, 350, "KV transfer", 13, ARROW["kv"], "600", "middle")
    s.text(1245, 368, "NVLink/RDMA", 13, ARROW["kv"], "400", "middle")
    s.box(970, 450, 550, 90, "engine", "…or aggregated workers (prefill + decode on one GPU)", "", title_size=15)
    s.text(1245, 575, "Engines: vLLM · SGLang · TensorRT-LLM", 16, C["dynamo"][2], "700", "middle")
    for i in range(8):
        s.gpu(975 + i * 68, 600, 60, 55, "GPU", "", "gpu")
    s.text(1245, 677, "A100 · H100 · H200 · B200 · B300", 14, INK2, "400", "middle")
    # router <-> workers: requests out, KV events back
    s.arrow([(860, 540), (950, 540)], "dynamo", width=3, label="requests", label_dy=-10, label_size=13)
    s.arrow([(950, 620), (860, 620)], "kv", width=2.5, dashed=True, label="KV events", label_dy=24, label_size=13)
    # planes
    y = 740
    s.box(60, y, 360, 110, "infra", "Discovery plane", "etcd · Kubernetes · file\n(who is serving what)", body_size=14)
    s.box(440, y, 360, 110, "infra", "Event & request planes", "ZMQ/NATS events · TCP requests", body_size=14)
    s.box(820, y, 340, 110, "dynamo", "Planner", "SLA-driven autoscaling of\nprefill vs decode pools", body_size=14)
    s.box(1180, y, 360, 110, "infra", "Observability", "Prometheus metrics · traces\nGrafana dashboards", body_size=14)
    return s


def agg_vs_disagg() -> Svg:
    s = Svg("Aggregated vs disaggregated serving",
            "Prefill (reading the prompt) and decode (writing tokens) stress GPUs differently. Disaggregation lets each scale separately.")
    # left: aggregated
    s.box(60, 150, 700, 600, "note", "", "")
    s.text(410, 190, "Aggregated", 26, INK, "700", "middle")
    s.text(410, 220, "every GPU runs prefill and decode", 16, INK2, "400", "middle")
    s.box(110, 250, 600, 60, "dynamo_strong", "KV-aware router", "", title_size=18)
    for i in range(4):
        x = 110 + i * 152
        s.arrow([(x + 68, 310), (x + 68, 350)], "dynamo")
        s.box(x, 350, 136, 150, "engine", f"Worker {i + 1}", "prefill\n+ decode", body_size=14, title_size=16)
        s.gpu(x + 8, 515, 120, 50, "GPU", "", "gpu")
    s.text(410, 610, "+ simplest · best when prompts are short or cache hits are high", 16, C["dynamo"][2], "600", "middle")
    s.text(410, 640, "– a long new prompt stalls every stream on that GPU", 16, C["warn"][1], "600", "middle")
    # timeline aggregated
    s.text(110, 690, "GPU timeline", 14, INK2, "600")
    tx = 220
    for w, kind in [(40, "d"), (40, "d"), (170, "p"), (40, "d"), (40, "d"), (40, "d")]:
        fill = "#eb6834" if kind == "p" else "#76b900"
        s.add(f'<rect x="{tx}" y="676" width="{w - 4}" height="22" rx="3" fill="{fill}"/>')
        tx += w
    s.text(305, 718, "long prefill → token stall (ITL spike)", 13, C["warn"][1], "600", "middle")
    s.add('<rect x="500" y="680" width="14" height="14" rx="2" fill="#76b900"/>')
    s.text(520, 692, "decode step", 13, INK2)
    s.add('<rect x="610" y="680" width="14" height="14" rx="2" fill="#eb6834"/>')
    s.text(630, 692, "prefill", 13, INK2)
    # right: disaggregated
    s.box(840, 150, 700, 600, "note", "", "")
    s.text(1190, 190, "Disaggregated", 26, INK, "700", "middle")
    s.text(1190, 220, "specialized pools, KV moved over NIXL", 16, INK2, "400", "middle")
    s.box(890, 250, 600, 60, "dynamo_strong", "KV-aware router", "", title_size=18)
    s.arrow([(990, 310), (990, 350)], "dynamo")
    s.box(890, 350, 200, 150, "engine", "Prefill pool", "compute-bound\nbig batches of\nprompt tokens", body_size=14, title_size=16)
    for i in range(2):
        s.gpu(900 + i * 95, 515, 85, 50, "GPU", "", "gpu")
    s.arrow([(1090, 425), (1180, 425)], "kv", width=5, label="NIXL", label_dy=-10)
    s.text(1135, 455, "KV blocks", 13, ARROW["kv"], "600", "middle")
    s.box(1180, 350, 310, 150, "engine", "Decode pool", "bandwidth-bound\nhundreds of streams\nsteady token rate", body_size=14, title_size=16)
    for i in range(3):
        s.gpu(1190 + i * 100, 515, 90, 50, "GPU", "", "gpu")
    s.arrow([(1335, 310), (1335, 350)], "dynamo", dashed=True)
    s.text(1190, 610, "+ steady inter-token latency under long prompts", 16, C["dynamo"][2], "600", "middle")
    s.text(1190, 640, "+ size prefill vs decode GPUs to the workload (xPyD)", 16, C["dynamo"][2], "600", "middle")
    s.text(1190, 670, "– KV transfer cost; one prefill pool can become the bottleneck", 16, C["warn"][1], "600", "middle")
    s.text(1190, 718, "Measure both: the winner depends on prompt length, reuse and SLO", 15, INK2, "400", "middle", italic=True)
    legend(s, 560, 800, [("dynamo_strong", "Dynamo"), ("engine", "engine worker"), ("kv", "KV cache data"), ("gpu", "GPU")])
    return s


def kv_routing() -> Svg:
    s = Svg("KV-aware routing: send each request where its prefix is already cached",
            "Agent turns resend the whole conversation. Reusing cached KV turns seconds of prefill into a lookup.")
    # request
    s.text(60, 175, "Incoming agent turn (prompt split into KV blocks)", 18, INK, "700")
    blocks = [("sys", "system + tools"), ("A", "repo files"), ("B", "turn 1"), ("C", "turn 2"), ("new", "new tool output")]
    x = 60
    for key, label in blocks:
        role = "kv" if key != "new" else "note"
        s.box(x, 195, 150, 60, role, key if key != "new" else "D", label, title_size=18, body_size=12)
        x += 158
    s.text(x + 10, 232, "≈ 60K tokens, 90% seen before", 16, INK2)
    # workers
    workers = [("Worker 1", ["sys", "A", "B", "C"], 4, 0.6), ("Worker 2", ["sys"], 1, 0.3), ("Worker 3", ["sys", "A"], 2, 0.9)]
    for i, (name, cached, overlap, load) in enumerate(workers):
        y = 330 + i * 150
        s.box(60, y, 300, 120, "engine", name, f"cached: {' '.join(cached)}", title_size=18, body_size=14)
        bx = 380
        for key, _ in blocks:
            hit = key in cached or (key == "sys")
            hit = key in cached
            fill = "#eb6834" if hit else "#e4e3df"
            s.add(f'<rect x="{bx}" y="{y + 42}" width="54" height="36" rx="4" fill="{fill}"/>')
            s.text(bx + 27, y + 66, "D" if key == "new" else key, 14, "#ffffff" if hit else INK2, "700", "middle")
            bx += 60
        s.text(690, y + 50, f"overlap {overlap}/5 blocks", 16, INK, "600")
        s.text(690, y + 75, f"load {int(load * 100)}%", 16, INK2)
        cost = (5 - overlap) * 1.0 + load * 2
        s.text(880, y + 62, f"cost {cost:.1f}", 20, C["dynamo"][2] if i == 0 else INK2, "700")
    s.box(1040, 330, 500, 420, "dynamo", "", "")
    s.text(1290, 375, "Router decision", 24, C["dynamo"][2], "700", "middle")
    s.text(1290, 425, "cost = prefill of uncached blocks", 18, C["dynamo"][2], "600", "middle")
    s.text(1290, 453, "+ weight × current load", 18, C["dynamo"][2], "600", "middle")
    s.text(1290, 515, "Pick Worker 1: only block D to prefill", 20, INK, "700", "middle")
    s.text(1290, 575, "Round-robin picks whoever is next:", 17, C["warn"][1], "600", "middle")
    s.text(1290, 600, "2 times in 3 it recomputes ~40–50K tokens", 17, C["warn"][1], "600", "middle")
    s.text(1290, 650, "Index kept current by KV events", 16, INK2, "400", "middle")
    s.text(1290, 675, "(block stored / evicted) from every worker", 16, INK2, "400", "middle")
    s.arrow([(960, 392), (1040, 392)], "dynamo", width=3)
    s.text(60, 830, "Measured on 8 × B300, multi-turn agent sessions (same GPUs, same model, only the router changed):",
           17, INK2, "400", italic=True)
    s.text(60, 860, "prefix-cache hits 70% vs 34% · first token 1.7–1.8× faster · +35–51% output tokens/s per GPU.",
           19, C["dynamo"][2], "700")
    return s


def request_lifecycle() -> Svg:
    s = Svg("Anatomy of one LLM request",
            "Why time-to-first-token and tokens-per-second are different problems")
    s.box(60, 170, 330, 170, "client", "Prompt in", "system + tools + files +\nconversation\n(1K – 200K tokens)", body_size=15)
    s.arrow([(390, 255), (470, 255)], "client", width=3)
    s.box(470, 150, 460, 210, "kv", "PREFILL", "all prompt tokens in parallel\ncompute-bound (tensor cores, FP8/FP4)\n→ builds the KV cache\n→ sets TIME TO FIRST TOKEN", body_size=15, title_size=24)
    s.arrow([(930, 255), (1010, 255)], "dynamo", width=3)
    s.box(1010, 150, 530, 210, "dynamo", "DECODE", "one token per step for every stream\nmemory-bandwidth-bound (reads weights + KV)\n→ sets TOKENS/S PER USER\nbatching many users → TOKENS/S PER GPU", body_size=15, title_size=24)
    s.text(60, 430, "What the KV cache costs", 24, INK, "700")
    s.text(520, 430, "KV bytes per token · memory for one 64K-token session (BF16 KV; FP8 halves it)", 15, INK2)
    rows = [("Qwen3-32B (dense attention)", 256, "16 GiB"),
            ("DeepSeek-V3 / Kimi-K2 (MLA)", 69, "4.3 GiB"),
            ("gpt-oss-120b (half sliding window)", 36, "2.3 GiB"),
            ("Qwen3.5-122B-A10B (hybrid, ¼ attention)", 24, "1.5 GiB"),
            ("Nemotron-3-Nano (hybrid Mamba)", 6, "0.4 GiB")]
    for i, (name, kib, note) in enumerate(rows):
        y = 470 + i * 62
        s.text(60, y + 28, name, 17, INK)
        s.add(f'<rect x="520" y="{y + 8}" width="{kib * 2.8:.0f}" height="28" rx="4" fill="#eb6834"/>')
        s.text(532 + kib * 2.8, y + 28, f"{kib} KiB/token · {note}", 15, INK2)
    s.text(60, 810, "Architecture decides how many students fit: KV per token × context × concurrent sessions ≤ free GPU memory.",
           17, INK2, "400", italic=True)
    s.text(60, 840, "Decode speed ≈ memory bandwidth ÷ bytes read per token → MoE (few active params) + FP4/FP8 decode fastest.",
           17, INK2, "400", italic=True)
    return s


def campus_service() -> Svg:
    s = Svg("Campus AI service on idle GPUs",
            "Research jobs keep priority; the service harvests idle cycles and restarts in minutes from a shared model cache")
    s.box(60, 170, 280, 480, "client", "", "")
    s.text(200, 205, "Users", 22, C["client"][2], "700", "middle")
    for i, (t, b) in enumerate([("Students", "coding agents in\nterminal & IDE"), ("Faculty & staff", "Open WebUI chat\ncourse tools"),
                                ("Researchers", "evals · batch jobs\ntrace studies")]):
        s.box(80, 230 + i * 135, 240, 115, "note", t, b, title_size=17, body_size=14)
    s.box(390, 170, 300, 480, "infra", "", "")
    s.text(540, 205, "Gateway (CPU VM)", 20, C["infra"][2], "700", "middle")
    s.box(410, 230, 260, 120, "infra", "SSO + per-course keys", "LiteLLM virtual keys\nOpen WebUI (OIDC)", title_size=16, body_size=14)
    s.box(410, 365, 260, 120, "infra", "Fairness", "rpm/tpm per key\nconcurrency cap below\nthe measured cliff", title_size=16, body_size=13)
    s.box(410, 500, 260, 130, "infra", "Usage & governance", "usage metadata by default\nprompt text only with\nopt-in consent", title_size=16, body_size=13)
    s.arrow([(340, 410), (390, 410)], "client", width=3)
    s.box(740, 170, 480, 480, "dynamo", "", "")
    s.text(980, 205, "Slurm cluster (idle GPU nodes)", 20, C["dynamo"][2], "700", "middle")
    s.box(760, 230, 440, 110, "dynamo_strong", "Dynamo frontend + KV router", "serve.sbatch · preemptible QOS · --requeue", title_size=18, body_size=14)
    for i in range(4):
        s.gpu(770 + i * 108, 370, 96, 70, f"GPU {i}", "replica", "gpu")
        s.gpu(770 + i * 108, 455, 96, 70, f"GPU {i + 4}", "replica", "gpu")
    s.text(980, 560, "A100 → B300: same launcher, model profile per tier", 15, C["dynamo"][2], "600", "middle")
    s.text(980, 590, "watchdog: real 1-token probe → requeue", 15, C["dynamo"][2], "600", "middle")
    s.arrow([(690, 400), (740, 400)], "dynamo", width=3)
    s.box(1270, 170, 270, 220, "infra", "Shared storage", "model cache (weights)\ncompile cache\nrestart = load, not download", title_size=17, body_size=14)
    s.box(1270, 420, 270, 230, "kv", "Research data (opt-in)", "consented traces → eval sets\n→ LoRA / SFT with NeMo\n→ served as adapters", title_size=17, body_size=14)
    s.arrow([(1270, 280), (1220, 280)], "default", dashed=True)
    s.arrow([(1220, 540), (1270, 540)], "kv", dashed=True)
    s.box(60, 700, 1480, 150, "note", "", "")
    s.text(80, 740, "Serving patterns", 19, INK, "700")
    pats = [("Preemptible QOS", "research jobs preempt; Slurm requeues"), ("Serving windows", "nights · weekends · term breaks"),
            ("Reserved slice", "one node for the service"), ("Burst replicas", "extra jobs join the same frontend")]
    for i, (t, b) in enumerate(pats):
        s.text(80 + i * 370, 785, t, 17, C["dynamo"][2], "700")
        s.text(80 + i * 370, 812, b, 15, INK2)
    return s


def research_flywheel() -> Svg:
    s = Svg("From usage to campus-tuned models: the research flywheel",
            "Every stage is useful on its own; consent and governance come first")
    import math
    cx, cy, rx, ry = 800, 525, 560, 300
    stages = [("1  Serve", "open models on idle GPUs\n(Dynamo)", "dynamo_strong"),
              ("2  Capture", "consented traces\n(gateway · harness · ATIF)", "kv"),
              ("3  Curate", "dedupe · PII · outcome\n(NeMo Curator)", "infra"),
              ("4  Evaluate", "campus eval set + public\n(Harbor · NeMo Evaluator)", "client"),
              ("5  Fine-tune", "LoRA/SFT → GRPO\n(NeMo AutoModel · RL · Gym)", "dynamo"),
              ("6  Deploy & A/B", "LoRA adapters in Dynamo\nper-course aliases", "dynamo")]
    pos = []
    for i in range(len(stages)):
        a = -math.pi / 2 + i * 2 * math.pi / len(stages)
        pos.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    for i in range(len(stages)):
        (x1, y1), (x2, y2) = pos[i], pos[(i + 1) % len(stages)]
        dx, dy = x2 - x1, y2 - y1
        # leave each 300x124 box at its border (+14 px gap) along the center line
        t = min(164 / abs(dx) if dx else 1e9, 76 / abs(dy) if dy else 1e9)
        s.arrow([(x1 + dx * t, y1 + dy * t), (x2 - dx * t, y2 - dy * t)], "dynamo", width=3)
    for (t, b, role), (x, y) in zip(stages, pos):
        s.box(x - 150, y - 62, 300, 124, role, t, b, title_size=19, body_size=14)
    s.box(cx - 170, cy - 70, 340, 140, "note", "Consent · IRB · retention", "opt-in keys · de-identification\nlicense checks on outputs", title_size=17, body_size=14)
    return s


def showcase_topologies() -> Svg:
    s = Svg("Showcase topologies on one 8 × B300 node",
            "Same model (Qwen3.5-122B-A10B NVFP4), same Dynamo 1.5.0, same trace — only the serving layout changes")
    layouts = [("A. Aggregated ×8, KV router", ["agg"] * 8, "KV-aware router on :8000"),
               ("B. Aggregated ×8, round-robin", ["agg"] * 8, "round-robin router on :8001 (same workers)"),
               ("C. Disaggregated 2P + 6D", ["P"] * 2 + ["D"] * 6, "NIXL KV transfer prefill → decode"),
               ("D. Disaggregated 4P + 4D", ["P"] * 4 + ["D"] * 4, "more prefill for long prompts")]
    for j, (title, roles, note) in enumerate(layouts):
        y = 160 + j * 180
        s.text(60, y + 30, title, 22, INK, "700")
        s.text(60, y + 58, note, 16, INK2)
        for i, role in enumerate(roles):
            x = 560 + i * 122
            label = {"agg": "P+D", "P": "Prefill", "D": "Decode"}[role]
            fill = {"agg": "#76b900", "P": "#eb6834", "D": "#2a78d6"}[role]
            s.add(f'<rect x="{x}" y="{y}" width="110" height="110" rx="8" fill="{fill}"/>')
            s.text(x + 55, y + 50, f"B300 {i}", 16, "#ffffff", "700", "middle")
            s.text(x + 55, y + 76, label, 15, "#ffffff", "400", "middle")
        if roles[0] == "P":
            n = roles.count("P")
            s.arrow([(560 + n * 122 - 12, y + 125), (560 + n * 122 + 110, y + 125)], "kv", width=3, label="NIXL", label_dy=18)
    return s


def campus_to_factory() -> Svg:
    s = Svg("From campus lab to AI factory",
            "The serving layer is the same Dynamo; what students learn on idle Slurm nodes transfers to NVIDIA's production stack")
    s.text(430, 170, "Campus lab (this repository)", 22, C["client"][2], "700", "middle")
    s.text(1170, 170, "NVIDIA AI factory (DSX OS)", 22, C["dynamo"][2], "700", "middle")
    layers = [
        ("5  Consume", "LiteLLM gateway · Open WebUI\nper-course keys · quotas", "infra",
         "NVCF — NVIDIA Cloud Functions\nserverless · scale-to-zero · multi-tenant", "infra"),
        ("4  Orchestrate", "serve.sbatch + serve.sh\none node · preemptible · requeue", "infra",
         "Grove\ngang + topology-aware multi-node scheduling", "infra"),
        ("3  Serve", "NVIDIA Dynamo 1.5 · KV router · NIXL\nvLLM engine · agg or disagg", "dynamo_strong",
         "NVIDIA Dynamo · KV router · NIXL\nPlanner · TRT-LLM / vLLM / SGLang", "dynamo_strong"),
        ("2  Enable hardware", "host driver R580+ · container toolkit\nEnroot / Apptainer · nvidia-smi sampling", "infra",
         "GPU Operator + Network Operator\nDCGM · MIG · RDMA / GPUDirect", "infra"),
        ("1  Provision", "university Slurm cluster\nshared NFS model cache", "infra",
         "Base Command Manager\nbare metal → Kubernetes", "infra"),
    ]
    for i, (layer, left, lrole, right, rrole) in enumerate(layers):
        y = 200 + i * 128
        s.text(60, y + 62, layer, 18, INK, "700")
        s.box(230, y, 400, 108, lrole, "", left, body_size=16)
        s.box(970, y, 400, 108, rrole, "", right, body_size=16)
        if lrole == "dynamo_strong":
            s.arrow([(630, y + 54), (970, y + 54)], "dynamo", width=4, both=True, label="same software, same skills", label_dy=-12, label_size=16)
        else:
            s.arrow([(630, y + 54), (970, y + 54)], "default", width=2, dashed=True, label="scales up to", label_dy=-10, label_size=14)
    s.text(1400, 262, "▲ consumption", 14, INK2)
    s.text(1400, 780, "▼ hardware", 14, INK2)
    s.text(60, 860, "Measured here (8 × B300): KV-aware routing +51% tok/s/GPU on agent sessions; 4P+4D disaggregation +12% tok/s/GPU and 7× smoother streaming on the agentic trace.",
           16, INK2, "400", italic=True)
    return s


DIAGRAMS = {
    "dynamo-architecture": dynamo_architecture,
    "aggregated-vs-disaggregated": agg_vs_disagg,
    "kv-aware-routing": kv_routing,
    "request-lifecycle": request_lifecycle,
    "campus-service": campus_service,
    "research-flywheel": research_flywheel,
    "showcase-topologies": showcase_topologies,
    "campus-to-ai-factory": campus_to_factory,
}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1] / "edu" / "diagrams")
    p.add_argument("--png", action="store_true", help="also render 2x PNG (pip install cairosvg)")
    p.add_argument("only", nargs="*", help=f"subset of: {', '.join(DIAGRAMS)}")
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    for name, build in DIAGRAMS.items():
        if args.only and name not in args.only:
            continue
        svg = build().render()
        (args.out / f"{name}.svg").write_text(svg)
        if args.png:
            import cairosvg
            cairosvg.svg2png(bytestring=svg.encode(), write_to=str(args.out / f"{name}.png"), output_width=W * 2)
        print(f"wrote {args.out / name}.svg" + (" + .png" if args.png else ""))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
