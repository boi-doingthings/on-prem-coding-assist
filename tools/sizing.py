#!/usr/bin/env python3
"""Estimate whether an open model fits a GPU tier and how much KV cache remains.

Dependency-free. Reads a Hugging Face config.json (local file, local HF cache,
or the public Hub) plus the safetensors index to get the real checkpoint size.

This is a first-order planning tool for workshops, not a substitute for the
engine's own startup log ("Available KV cache memory ... tokens"). Always
record the engine-reported number next to this estimate.

Examples:
  tools/sizing.py nvidia/Qwen3.5-122B-A10B-NVFP4 --kv-dtype fp8
  tools/sizing.py openai/gpt-oss-20b --gpus A100-40GB,L40S,H100 --context 32768
  tools/sizing.py --weights-gb 16 --layers 36 --kv-heads 8 --head-dim 128 \
      --name "my 8B" --gpus A100-40GB
"""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import pathlib
import sys
import urllib.error
import urllib.request

GIB = 1024**3

# Memory is the marketing GB figure converted to GiB-ish usable capacity is
# left to the engine; we use the vendor number in GB (1e9) for transparency.
# bw = HBM/GDDR bandwidth TB/s. fp8/fp4 = native tensor-core support.
GPUS: dict[str, dict[str, object]] = {
    "A100-40GB": {"mem_gb": 40, "bw_tbs": 1.555, "fp8": False, "fp4": False, "arch": "Ampere"},
    "A100-80GB": {"mem_gb": 80, "bw_tbs": 2.039, "fp8": False, "fp4": False, "arch": "Ampere"},
    "L40S": {"mem_gb": 48, "bw_tbs": 0.864, "fp8": True, "fp4": False, "arch": "Ada"},
    "H100": {"mem_gb": 80, "bw_tbs": 3.35, "fp8": True, "fp4": False, "arch": "Hopper"},
    "H100-NVL": {"mem_gb": 94, "bw_tbs": 3.9, "fp8": True, "fp4": False, "arch": "Hopper"},
    "H200": {"mem_gb": 141, "bw_tbs": 4.8, "fp8": True, "fp4": False, "arch": "Hopper"},
    "RTX-PRO-6000": {"mem_gb": 96, "bw_tbs": 1.6, "fp8": True, "fp4": True, "arch": "Blackwell"},
    "B200": {"mem_gb": 180, "bw_tbs": 8.0, "fp8": True, "fp4": True, "arch": "Blackwell"},
    "B300": {"mem_gb": 288, "bw_tbs": 8.0, "fp8": True, "fp4": True, "arch": "Blackwell Ultra"},
}
DEFAULT_GPUS = "A100-40GB,A100-80GB,H100,H200,B200,B300"

DTYPE_BYTES = {"fp32": 4.0, "bf16": 2.0, "fp16": 2.0, "fp8": 1.0, "int8": 1.0, "fp4": 0.5}


def fetch_json(model: str, filename: str, cache_dir: str | None) -> dict | None:
    """Look in a local path, then the HF cache, then the public Hub."""
    local = pathlib.Path(model)
    if local.is_dir() and (local / filename).is_file():
        return json.loads((local / filename).read_text())
    if local.is_file() and filename == "config.json":
        return json.loads(local.read_text())

    roots = [cache_dir] if cache_dir else []
    roots += [os.environ.get("HF_HOME", ""), os.path.expanduser("~/.cache/huggingface")]
    slug = "models--" + model.replace("/", "--")
    for root in filter(None, roots):
        hits = glob.glob(os.path.join(root, "hub", slug, "snapshots", "*", filename))
        hits += glob.glob(os.path.join(root, slug, "snapshots", "*", filename))
        if hits:
            return json.loads(pathlib.Path(sorted(hits)[-1]).read_text())

    url = f"https://huggingface.co/{model}/resolve/main/{filename}"
    headers = {"User-Agent": "dynamo-edu-sizing/1"}
    if os.environ.get("HF_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['HF_TOKEN']}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=20) as r:
            return json.load(r)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return None


def checkpoint_bytes(model: str, cache_dir: str | None) -> float | None:
    """Checkpoint size from the shard index, local safetensors, or Hub metadata."""
    index = fetch_json(model, "model.safetensors.index.json", cache_dir)
    total = (index or {}).get("metadata", {}).get("total_size")
    if total:
        return float(total)
    roots = [model] + [os.path.join(r, "hub", "models--" + model.replace("/", "--"), "snapshots", "*")
                       for r in filter(None, [cache_dir, os.environ.get("HF_HOME"),
                                              os.path.expanduser("~/.cache/huggingface")])]
    for root in roots:
        files = glob.glob(os.path.join(root, "*.safetensors"))
        if files:
            return float(sum(os.path.getsize(f) for f in files))
    url = f"https://huggingface.co/api/models/{model}"
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "dynamo-edu-sizing/1"}),
                                    timeout=20) as r:
            info = json.load(r)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError):
        return None
    params = (info.get("safetensors") or {}).get("parameters") or {}
    width = {"F32": 4, "BF16": 2, "F16": 2, "F8_E4M3": 1, "F8_E5M2": 1, "I8": 1, "U8": 1, "I32": 4}
    return float(sum(n * width.get(dtype, 2) for dtype, n in params.items())) or None


def text_config(config: dict) -> dict:
    for key in ("text_config", "llm_config", "language_config"):
        if isinstance(config.get(key), dict):
            merged = dict(config[key])
            merged.setdefault("quantization_config", config.get("quantization_config"))
            return merged
    return config


def attention_layout(cfg: dict) -> tuple[int, int, str]:
    """Return (kv-bearing layers, sliding-window layers, description)."""
    layers = int(cfg.get("num_hidden_layers") or cfg.get("n_layers") or 0)
    types = cfg.get("layer_types")
    if isinstance(types, list) and types:
        full = sum(1 for t in types if t in ("full_attention", "attention", "global_attention"))
        sliding = sum(1 for t in types if "sliding" in str(t) or "local" in str(t))
        other = len(types) - full - sliding
        desc = f"{full} full-attention"
        if sliding:
            desc += f", {sliding} sliding-window"
        if other:
            desc += f", {other} linear/SSM (constant state, not KV)"
        return full, sliding, desc
    pattern = cfg.get("hybrid_override_pattern")  # Nemotron-H style: '*' = attention
    if isinstance(pattern, str) and pattern:
        full = pattern.count("*")
        return full, 0, f"{full} attention of {len(pattern)} hybrid blocks (rest Mamba/MLP/MoE)"
    return layers, 0, f"{layers} full-attention"


def kv_bytes_per_token(cfg: dict, kv_dtype_bytes: float) -> tuple[float, float, str]:
    """Return (bytes/token for unbounded layers, bytes/token for sliding layers, note)."""
    full, sliding, desc = attention_layout(cfg)
    if cfg.get("kv_lora_rank"):  # MLA (DeepSeek/Kimi/GLM-5 style): one latent vector per layer
        per_layer = (int(cfg["kv_lora_rank"]) + int(cfg.get("qk_rope_head_dim", 64))) * kv_dtype_bytes
        return full * per_layer, 0.0, f"MLA latent cache, {desc}"
    heads = int(cfg.get("num_attention_heads") or 1)
    kv_heads = int(cfg.get("num_key_value_heads") or heads)
    head_dim = int(cfg.get("head_dim") or (int(cfg.get("hidden_size", 0)) // heads))
    per_layer = 2 * kv_heads * head_dim * kv_dtype_bytes
    return full * per_layer, sliding * per_layer, f"GQA {kv_heads} KV heads x {head_dim}, {desc}"


def checkpoint_precision(cfg: dict) -> str:
    q = cfg.get("quantization_config") or {}
    text = json.dumps(q).lower()
    if "nvfp4" in text or "modelopt_fp4" in text or '"fp4"' in text:
        return "nvfp4"
    if "mxfp4" in text:
        return "mxfp4"
    if "fp8" in text or "float8" in text:
        return "fp8"
    if "awq" in text or "gptq" in text or "int4" in text:
        return "int4"
    return str(cfg.get("torch_dtype") or cfg.get("dtype") or "bf16")


def precision_note(precision: str, gpu: dict) -> str:
    if precision == "nvfp4" and not gpu["fp4"]:
        return "NVFP4 not native: use FP8/BF16 checkpoint"
    if precision == "fp8" and not gpu["fp8"]:
        return "FP8 not native: weight-only (Marlin) path, slower"
    if precision == "mxfp4" and not gpu["fp4"]:
        return "MXFP4 via Marlin/Triton kernels"
    return ""


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("model", nargs="?", help="HF repo id, local dir, or config.json path")
    p.add_argument("--gpus", default=DEFAULT_GPUS, help=f"comma list from: {', '.join(GPUS)}")
    p.add_argument("--tp", default="1,2,4,8", help="tensor/expert-parallel sizes to evaluate")
    p.add_argument("--context", type=int, default=65536, help="tokens per active session (agentic coding: 32K-128K)")
    p.add_argument("--kv-dtype", default="fp8", choices=sorted(DTYPE_BYTES))
    p.add_argument("--gpu-mem-util", type=float, default=0.90, help="engine memory fraction (vLLM default 0.9)")
    p.add_argument("--reserve-gb", type=float, default=6.0, help="per-GPU activations/CUDA graphs/workspace")
    p.add_argument("--cache-dir", default=None, help="HF_HOME to search for cached configs")
    p.add_argument("--weights-gb", type=float, help="override checkpoint size in GB (1e9 bytes)")
    p.add_argument("--active-params-b", type=float, help="active params (B) for MoE decode roofline")
    p.add_argument("--weight-bits", type=float, help="bits/param for the roofline if not derivable")
    p.add_argument("--name", help="display name for manual mode")
    p.add_argument("--layers", type=int)
    p.add_argument("--kv-heads", type=int)
    p.add_argument("--head-dim", type=int)
    p.add_argument("--json", action="store_true", help="emit machine-readable rows")
    args = p.parse_args()

    cfg: dict = {}
    weights_bytes: float | None = args.weights_gb * 1e9 if args.weights_gb else None
    if args.model:
        raw = fetch_json(args.model, "config.json", args.cache_dir)
        if raw is None and not args.layers:
            print(f"Could not load config.json for {args.model}; pass --layers/--kv-heads/--head-dim.", file=sys.stderr)
            return 2
        cfg = text_config(raw or {})
        if weights_bytes is None:
            weights_bytes = checkpoint_bytes(args.model, args.cache_dir)
    if args.layers:
        cfg["num_hidden_layers"] = args.layers
        cfg.pop("layer_types", None)
    if args.kv_heads:
        cfg["num_key_value_heads"] = args.kv_heads
        cfg.setdefault("num_attention_heads", args.kv_heads)
    if args.head_dim:
        cfg["head_dim"] = args.head_dim
    if weights_bytes is None:
        print("Checkpoint size unknown (no safetensors index); pass --weights-gb.", file=sys.stderr)
        return 2

    name = args.name or args.model
    precision = checkpoint_precision(cfg)
    kv_full, kv_sliding, kv_note = kv_bytes_per_token(cfg, DTYPE_BYTES[args.kv_dtype])
    window = int(cfg.get("sliding_window") or 0)
    per_session = kv_full * args.context + kv_sliding * min(args.context, window or args.context)
    kv_heads = int(cfg.get("num_key_value_heads") or cfg.get("num_attention_heads") or 1)

    active_bytes = None
    if args.active_params_b:
        bits = args.weight_bits or {"nvfp4": 4.5, "mxfp4": 4.25, "int4": 4.5, "fp8": 8}.get(precision, 16)
        active_bytes = args.active_params_b * 1e9 * bits / 8
    elif not cfg.get("num_experts") and not cfg.get("n_routed_experts") and not cfg.get("num_local_experts"):
        active_bytes = weights_bytes  # dense: every weight is read per decode step

    print(f"\nModel: {name}")
    print(f"  checkpoint: {weights_bytes / 1e9:.1f} GB on disk, precision={precision}, max_position={cfg.get('max_position_embeddings', '?')}")
    print(f"  KV cache ({args.kv_dtype}): {kv_note}; {kv_full / 1024:.1f} KiB/token"
          + (f" (+{kv_sliding / 1024:.1f} KiB/token sliding, capped at {window})" if kv_sliding else ""))
    print(f"  one {args.context:,}-token session needs {per_session / GIB:.2f} GiB of KV\n")

    header = f"{'GPU':<13}{'TP':>3} {'weights/GPU':>12} {'fits':>5} {'KV pool':>9} {'KV tokens':>12} {'sessions@ctx':>13} {'decode ceiling':>15}  notes"
    print(header)
    print("-" * len(header))
    rows = []
    for gpu_name in args.gpus.split(","):
        gpu = GPUS.get(gpu_name.strip())
        if gpu is None:
            print(f"unknown GPU {gpu_name!r}; choose from {', '.join(GPUS)}", file=sys.stderr)
            return 2
        for tp in (int(t) for t in args.tp.split(",")):
            budget = float(gpu["mem_gb"]) * 1e9 * args.gpu_mem_util - args.reserve_gb * 1e9
            w_per_gpu = weights_bytes / tp
            kv_pool = tp * (budget - w_per_gpu)
            # KV heads are sharded across TP; below that they are replicated.
            kv_pool_eff = kv_pool * min(tp, kv_heads) / tp if not cfg.get("kv_lora_rank") else kv_pool / tp
            fits = kv_pool_eff > per_session
            tokens = int(kv_pool_eff / kv_full) if kv_full and fits else 0
            sessions = int(kv_pool_eff // per_session) if fits and per_session else 0
            ceiling = ""
            if active_bytes and fits:
                # Bandwidth roofline for a single stream; real ITL is typically 50-70% of this.
                ceiling = f"{float(gpu['bw_tbs']) * 1e12 * tp / active_bytes:,.0f} tok/s"
            note = precision_note(precision, gpu)
            rows.append({"gpu": gpu_name, "tp": tp, "fits": fits, "weights_per_gpu_gb": w_per_gpu / 1e9,
                         "kv_pool_gib": kv_pool_eff / GIB, "kv_tokens": tokens, "sessions": sessions, "note": note})
            print(f"{gpu_name:<13}{tp:>3} {w_per_gpu / 1e9:>10.1f}GB {'yes' if fits else 'no':>5} "
                  f"{max(kv_pool_eff, 0) / GIB:>7.1f}Gi {tokens:>12,} {sessions:>13,} {ceiling:>15}  {note}")
    print("\nsessions@ctx = sessions that can hold a full context simultaneously (worst case; prefix sharing"
          "\nand shorter real contexts raise this). Decode ceiling = memory-bandwidth roofline for one stream.")
    if args.json:
        print(json.dumps(rows, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
