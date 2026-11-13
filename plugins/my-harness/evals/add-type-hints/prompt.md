---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [python-fp-refactor]
---

Add type hints to this function. Don't change anything else.

```python
import json
import urllib.request


def fetch_overdue(base_url, days, notify):
    with urllib.request.urlopen(f"{base_url}/invoices") as response:
        invoices = json.load(response)
    overdue = []
    for invoice in invoices:
        if invoice["paid"]:
            continue
        if invoice["age_days"] > days:
            overdue.append(invoice["id"])
            if notify:
                print(f"invoice {invoice['id']} is overdue")
    return overdue
```
