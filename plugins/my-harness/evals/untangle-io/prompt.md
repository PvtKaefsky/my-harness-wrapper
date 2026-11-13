---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [python-fp-refactor]
---

This function is a mess. Can you untangle it?

```python
import csv
import json
from datetime import date


def reprice(input_path, output_path):
    results = []
    with open(input_path) as handle:
        for row in csv.DictReader(handle):
            price = float(row["price"])
            if row["category"] == "clearance":
                price = price * 0.5
            elif date.today().month == 12:
                price = price * 0.9
            if int(row["stock"]) > 100:
                price = price - 1
            results.append({"sku": row["sku"], "price": round(max(price, 0.99), 2)})
    with open(output_path, "w") as handle:
        json.dump(results, handle, indent=2)
    print(f"repriced {len(results)} items")
```
