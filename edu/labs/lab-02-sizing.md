# Lab 2 — Will it fit? Sizing a model to your GPUs (45 min)

**You will:** predict memory, KV-cache capacity, and decode speed for real
models on your hardware, deploy one, and compare prediction to the engine's
own numbers.

## 1. The three budgets

```text
GPU memory x utilization (0.9) = weights + KV cache + activations/graphs
KV bytes per token = 2 (K,V) x attention_layers x kv_heads x head_dim x bytes
                     (MLA models: latent_rank + rope_dim per layer; hybrid
                      Mamba/DeltaNet layers hold constant state, not KV)
decode tokens/s per stream  <~  memory bandwidth / bytes read per token
                                (dense: all weights; MoE: active params only)
```

## 2. Predict

```bash
tools/sizing.py Qwen/Qwen3-0.6B --gpus A100-40GB,H100,B300 --tp 1 --context 32768 --kv-dtype bf16
tools/sizing.py openai/gpt-oss-20b --gpus A100-40GB,L40S,H100 --tp 1 --active-params-b 3.6
tools/sizing.py nvidia/Qwen3.5-122B-A10B-NVFP4 --gpus H200,B200,B300 --tp 1,2 \
  --context 262144 --active-params-b 10
```

Fill in for your site's target model:

| GPU | TP | Fits? | KV tokens (predicted) | KV tokens (engine log) | Error % |
| --- | ---: | --- | ---: | ---: | ---: |
| | | | | | |

Calibration measured in this lab (one B300, vllm-runtime 1.3.0):

| Model | Predicted KV tokens | vLLM reported | Error |
| --- | ---: | ---: | ---: |
| Qwen3.5-122B-A10B NVFP4, FP8 KV | 13.81M | 13.56M | +2% |
| gpt-oss-20b, BF16 KV | 9.74M | 9.21M | +6% |
| Qwen3.6-35B-A3B FP8, BF16 KV, util 0.85 | 9.83M | 8.90M | +10% |

The estimate is an upper bound: it ignores per-sequence linear-attention/SSM
state and allocator granularity. Always record the engine's number.

## 3. Discuss

1. Why does a 122B-parameter MoE decode faster per user than a 32B dense model?
2. Why does a hybrid (linear-attention + attention) model hold ~4× more
   sessions than a pure-attention model of the same size?
3. On A100 there is no FP8/FP4 tensor-core support. What are your options
   for a checkpoint published only in FP8? (weight-only Marlin kernels, a
   BF16 or INT4/AWQ checkpoint, or a smaller model.)
4. When is TP=2 better than two TP=1 replicas? (Model does not fit; or you
   need lower latency per user; otherwise replicas usually win on throughput.)
