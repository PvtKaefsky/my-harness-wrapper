---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [repository-setup]
---

This repository holds a Python research project:

```
qcomp/
├── src/
│   └── qcomp/
│       ├── __init__.py
│       └── quantize.py
├── tests/
│   └── test_quantize.py
├── Dockerfile
├── pyproject.toml
└── README.md
```

Add the experiment layer: environment settings, a config system, one-command experiment runs inside the Docker image, and somewhere for run outputs to go. List every file you'd add or change, with its path and what it holds, then go ahead.
