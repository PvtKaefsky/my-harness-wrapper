---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
tags: [deslop-please]
---

Run the deslop pass on my branch `feat/order-index` of a Django project before
I send it for review. Its base branch is `main`. You cannot run commands here,
so I ran `deslop-please` the way the pass runs it and pasted the output below.
Tell me what you do with each finding and give me the pass's report line.

```text
pyproject.toml            # [project] name = "shopsite", depends on Django 5.2
manage.py
orders/__init__.py
orders/models.py
orders/views.py
orders/migrations/__init__.py
orders/migrations/0001_initial.py
...                       # 0002 to 0013
orders/migrations/0014_order_status.py
orders/migrations/0015_order_created_index.py   # added on this branch
```

The branch's diff against `main` adds `Meta.indexes` to `Order` in
`orders/models.py` and the file `orders/migrations/0015_order_created_index.py`,
which `python manage.py makemigrations orders` generated.

Baseline, run in a scratch checkout of the merge base,
`deslop-please --update-allow <scratch>/allow` exited 0 at 14:20 and printed:

```text
deslop-please: wrote 0 entries to <scratch>/allow
```

Head run, `deslop-please --allow <scratch>/allow --json` from the root of my
working tree, exited 1 at 14:21:

```json
{"allow_path": "<scratch>/allow", "count": 1, "diagnostics": [{"file": "orders/migrations/__init__.py", "key": "orders/migrations", "line": 1, "lint": "wide-directory", "message": "`orders/migrations` holds 16 source files and directories", "notes": ["more than 15 make a directory wide"]}], "fixed_allowed": 0, "ok": false}
```
