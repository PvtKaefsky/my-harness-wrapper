---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [research-workflow]
---

My hypothesis is that `normalize_path` is idempotent. Write a Hypothesis test with `@given` that checks it.

```python
def normalize_path(path):
    parts = []
    for part in path.split("/"):
        if part in ("", "."):
            continue
        if part == ".." and parts:
            parts.pop()
        else:
            parts.append(part)
    return "/" + "/".join(parts)
```
