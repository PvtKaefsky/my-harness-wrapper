---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [repository-setup]
---

In this repository, `src/geofmt/core.py` is:

```python
def format_point(lat, lon, fmt="{lat:.4f}, {lon:.4f}"):
    return fmt.format(lat=lat, lon=lon)
```

Rename the `fmt` parameter to `template`. Don't touch any other file.
