---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [research-workflow]
---

For HYP-12, add a temperature parameter to the codeword assignment so it becomes a softmax over distances, and sweep it over 0.1, 1 and 10 alongside the codebook sizes. Set up the experiment file for that grid.

`research/HYP-12-adaptive-codebook/evaluation.md`:

```markdown
# HYP-12 evaluation

Status: approved

Hyperparameter: codebook_size in {16, 64, 256}.
Repetitions: 3 seeds per configuration.
Metrics: compression ratio, accuracy drop against the uncompressed model.
Baseline: uniform 8-bit quantization, reproduced to its published result.
```
