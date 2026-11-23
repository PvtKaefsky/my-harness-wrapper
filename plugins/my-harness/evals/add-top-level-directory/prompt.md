---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [repository-setup]
---

This repository holds a Python library:

```
geofmt/
├── src/
│   └── geofmt/
│       ├── __init__.py
│       └── core.py
├── .gitignore
├── pyproject.toml
└── README.md
```

Add a release script that builds the wheel and the sdist and runs `twine check` on them. It isn't part of the package, so it needs a new directory at the top level. Tell me where it goes before you write it.
