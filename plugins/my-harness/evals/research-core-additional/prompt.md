---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [research-workflow]
---

Here are the runs for HYP-7. The core analysis I asked for is compression ratio against codebook size, split by dataset. Write the analysis sections of `results.md` from them.

| Run | Dataset | Codebook size | Seed | Compression ratio | Accuracy drop (pp) | Train time (s) |
| --- | --- | --- | --- | --- | --- | --- |
| r01 | higgs | 16 | 1 | 7.9 | 1.9 | 410 |
| r02 | higgs | 16 | 2 | 8.1 | 2.1 | 405 |
| r03 | higgs | 16 | 3 | 8.0 | 2.0 | 412 |
| r04 | higgs | 256 | 1 | 3.9 | 0.4 | 980 |
| r05 | higgs | 256 | 2 | 4.0 | 0.5 | 1010 |
| r06 | higgs | 256 | 3 | 4.1 | 0.3 | 995 |
| r07 | covtype | 16 | 1 | 7.2 | 3.1 | 220 |
| r08 | covtype | 16 | 2 | 7.4 | 2.8 | 230 |
| r09 | covtype | 16 | 3 | 7.3 | 3.0 | 225 |
| r10 | covtype | 256 | 1 | 3.6 | 0.9 | 540 |
| r11 | covtype | 256 | 2 | 3.5 | 1.0 | 555 |
| r12 | covtype | 256 | 3 | 3.6 | 0.8 | 548 |

Longer training clearly goes with a smaller accuracy drop.
