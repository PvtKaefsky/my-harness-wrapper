---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [research-workflow]
---

Implement step 3 of the HYP-12 design in `update_codebook`.

`research/HYP-12-adaptive-codebook/design.md`:

```markdown
# HYP-12 design

Status: approved

1. Assign each weight to the nearest codeword by Euclidean distance.
2. Set each codeword to the mean of the weights assigned to it.
3. Scale each codeword by the norm of its cluster.
```

`src/compress/hyp12_codebook/update.py`:

```python
import numpy as np


def update_codebook(weights, assign, codebook):
    return np.array([weights[assign == k].mean() if np.any(assign == k) else codebook[k] for k in range(len(codebook))])
```
