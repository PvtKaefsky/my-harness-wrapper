---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [task-delegation]
---

Why does this return None when I pass it an empty list? I expected 0.

```python
def average(values):
    total = 0
    for value in values:
        total += value
        if values:
            return total / len(values)
```
