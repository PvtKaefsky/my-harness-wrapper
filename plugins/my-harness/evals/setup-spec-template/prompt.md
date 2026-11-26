---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [repository-setup]
---

This repository keeps one spec per component under `docs/specs/`:

```
gateway/
├── docs/
│   ├── specs/
│   │   └── auth.md
│   └── requirements.md
├── src/
│   └── gateway/
│       ├── auth.py
│       └── ratelimit.py
├── tests/
└── README.md
```

Write the spec for the rate limiter: a token bucket per client key, 10 requests per second with bursts up to 20, and a 429 with a `Retry-After` header once the bucket is empty. Show me the whole file and its path.
