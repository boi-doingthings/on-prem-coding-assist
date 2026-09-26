# Nemotron 3.5 Lightning: teacher vs pruned student (4 × B300 each, before distillation)

![Pareto](nemotron-teacher-vs-pruned.svg)

| Series | Conc | Valid | Req/s | Out tok/s | GPUs | Out tok/s/GPU | tok/s/user p50 | TTFT p50/p99 ms | ITL p50/p99 ms | E2E p99 ms | SLO |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| nemotron-3.5-lightning-pruned-a2.5b-4xB300-chat | 8 | 32/32 | 8.25 | 2,113 | 4 | 528 | 352.4 | 71/624 | 2.8/3.6 | 1,482 | ✓ |
| nemotron-3.5-lightning-pruned-a2.5b-4xB300-chat | 32 | 128/128 | 18.67 | 4,780 | 4 | 1,195 | 179.6 | 158/249 | 5.6/7.2 | 1,953 | ✓ |
| nemotron-3.5-lightning-pruned-a2.5b-4xB300-chat | 128 | 512/512 | 51.99 | 13,310 | 4 | 3,328 | 127.2 | 199/333 | 7.9/12.2 | 3,295 | ✓ |
| nemotron-3.5-lightning-pruned-a2.5b-4xB300-chat | 256 | 1024/1024 | 96.23 | 24,636 | 4 | 6,159 | 111.7 | 210/818 | 9.0/11.8 | 3,458 | ✓ |
| nemotron-3.5-lightning-teacher-4xB300-chat | 8 | 32/32 | 7.61 | 1,948 | 4 | 487 | 317.2 | 84/482 | 3.2/4.2 | 1,371 | ✓ |
| nemotron-3.5-lightning-teacher-4xB300-chat | 32 | 128/128 | 17.32 | 4,433 | 4 | 1,108 | 167.8 | 193/241 | 6.0/8.1 | 2,186 | ✓ |
| nemotron-3.5-lightning-teacher-4xB300-chat | 128 | 512/512 | 45.73 | 11,707 | 4 | 2,927 | 105.8 | 261/358 | 9.5/13.4 | 3,641 | ✓ |
| nemotron-3.5-lightning-teacher-4xB300-chat | 256 | 1024/1024 | 82.24 | 21,054 | 4 | 5,264 | 92.2 | 217/475 | 10.9/13.2 | 3,554 | ✓ |

SLO: TTFT p99 ≤ 2000 ms and per-user decode ≥ 20 tok/s. Failed points are failures, not low throughput — never average them in.
- **nemotron-3.5-lightning-pruned-a2.5b-4xB300-chat**: highest SLO-passing concurrency = 256 → ≈ 1,707 active users at an assumed 15% duty cycle (fraction of wall-clock a user has a request in flight; measure yours from gateway logs).
- **nemotron-3.5-lightning-teacher-4xB300-chat**: highest SLO-passing concurrency = 256 → ≈ 1,707 active users at an assumed 15% duty cycle (fraction of wall-clock a user has a request in flight; measure yours from gateway logs).
