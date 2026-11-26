---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [research-workflow]
---

The codebook quantizer for HYP-12 converges slowly. Please improve the algorithm, for example by normalizing the weights before assignment, and give me the updated function.

`research/HYP-12-adaptive-codebook/design.md`:

```markdown
# HYP-12 design

Status: approved

1. Assign each weight to the nearest codeword by Euclidean distance.
2. Set each codeword to the mean of the weights assigned to it.
3. Repeat until no assignment changes.
```

`src/compress/hyp12_codebook/quantize.py`:

```python
import numpy as np


def fit_codebook(weights, codebook):
    while True:
        assign = np.argmin(np.abs(weights[:, None] - codebook[None, :]), axis=1)
        updated = np.array([weights[assign == k].mean() if np.any(assign == k) else codebook[k] for k in range(len(codebook))])
        if np.array_equal(updated, codebook):
            return updated, assign
        codebook = updated
```
