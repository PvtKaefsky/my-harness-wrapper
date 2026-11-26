---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [repository-setup]
---

This Python repository states one dependency rule in `docs/architecture.md`:

```
| Rule | Paths |
| --- | --- |
| domain never imports adapters | `src/billing/domain`, `src/billing/adapters` |
```

```
billing/
├── docs/
│   └── architecture.md
├── src/
│   └── billing/
│       ├── domain/
│       └── adapters/
├── tests/
├── pyproject.toml
└── README.md
```

Add a test that enforces that rule, so CI catches a violation. Show me the whole test file and its path.
