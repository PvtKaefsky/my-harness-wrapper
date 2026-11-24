---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [task-delegation]
---

I'm running you in the terminal CLI, in a clone of `acme/reports` whose default branch is `main`. This session lists no tool that starts another session. Add a `--limit N` flag to `report.py` that prints only the first N rows, and a test for it in `tests/test_report.py`. Don't edit anything yet: tell me how you will carry it out.

```python
import argparse
import csv


def main():
    parser = argparse.ArgumentParser(description="Print a CSV report.")
    parser.add_argument("path")
    args = parser.parse_args()
    with open(args.path, newline="") as handle:
        for row in csv.reader(handle):
            print(", ".join(row))


if __name__ == "__main__":
    main()
```
