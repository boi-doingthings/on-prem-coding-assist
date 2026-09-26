# Session 2 — Faculty workshop (half day, ~3.5 h)

**Audience:** AI/ML, systems, HPC, and software-engineering faculty; postdocs.
**Goal:** faculty can explain the serving stack, use it for teaching, and see
the research agenda (traces → evals → fine-tuning).
**Prerequisite:** a running endpoint on the site's hardware (Phase 1).

| Time | Module | Content | Hands-on |
| ---: | --- | --- | --- |
| 0:00 | Why inference is a systems problem | Prefill vs. decode, KV cache, batching, memory-bandwidth roofline; why MoE and low precision changed the economics | `tools/sizing.py` on 3 models live |
| 0:30 | The open-model landscape | Families, licenses, benchmark reading (SWE-bench vs. LiveCodeBench vs. Terminal-Bench; vendor vs. independent numbers) | Pick a model for your hardware from the catalog |
| 1:00 | NVIDIA Dynamo architecture | Frontend, KV-aware router, workers, NIXL, disaggregation, planner; how it relates to vLLM/SGLang/TRT-LLM and NIM | Read `/health`, send a tool call |
| 1:30 | *Break* | | |
| 1:45 | Benchmarking | TTFT/ITL/throughput, Pareto curves, duty cycle → users; honest-reporting rules; case study of the B300 lab | Run a 3-point sweep, read the chart |
| 2:30 | Coding harnesses in class | OpenCode, Aider, Continue/Cline, OpenHands; which fits which course; academic-integrity patterns | Connect one harness to the endpoint |
| 3:00 | Research flywheel | Consented traces → eval sets → LoRA/SFT with NeMo → serve adapter with Dynamo; project ideas | Discussion: 1 project per faculty |
| 3:20 | Wrap-up | Course integration plan, office hours, ambassador program, DLI resources | Fill the course/research lines of the site profile |

**Project ideas to seed (pick per department)**

- Systems: measure KV-aware vs. round-robin routing on replayed agent traces;
  reproduce the aggregated vs. disaggregated crossover as prompt length grows.
- Architecture: roofline vs. measured decode across A100/H100/B300; NVFP4 vs.
  FP8 vs. BF16 quality/speed trade-off.
- ML: fine-tune a small model on a course's codebase or a low-resource
  language; distill a large campus model into a small one.
- SE education: controlled study of agent-assisted vs. unassisted assignments.
- HCI/Ed: how students actually use coding agents (from consented traces).
