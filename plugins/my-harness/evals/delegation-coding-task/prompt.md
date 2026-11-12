---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [task-delegation]
---

Add a `--dry-run` flag to this script: with it, the script prints what it would delete and deletes nothing. Document the flag in the script's usage text too.

```python
import argparse
import os
import time


def main():
    parser = argparse.ArgumentParser(description="Delete files older than N days.")
    parser.add_argument("directory")
    parser.add_argument("--days", type=int, default=30)
    args = parser.parse_args()
    cutoff = time.time() - args.days * 86400
    for name in os.listdir(args.directory):
        path = os.path.join(args.directory, name)
        if os.path.isfile(path) and os.path.getmtime(path) < cutoff:
            os.remove(path)
            print(f"deleted {path}")


if __name__ == "__main__":
    main()
```
