---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [quick-human-readable-review]
---

I ran the cache benchmark three times after switching the LRU to a segmented one. What's the outcome?

Baseline (old LRU), from last week: p50 4.1 ms, p99 38 ms, hit rate 71.2%, 12,400 req/s.

Run 1: p50 3.6 ms, p99 22 ms, hit rate 78.9%, 13,900 req/s
Run 2: p50 3.7 ms, p99 24 ms, hit rate 79.3%, 13,700 req/s
Run 3: p50 3.6 ms, p99 41 ms, hit rate 78.7%, 13,800 req/s

Run 3 had a GC pause logged at 00:14:32 that lasted 180 ms. Memory use was 2.1 GB in all three runs, against 1.8 GB for the baseline.
