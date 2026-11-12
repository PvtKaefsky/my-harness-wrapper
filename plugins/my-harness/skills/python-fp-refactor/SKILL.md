---
name: python-fp-refactor
description: Separates the decisions in Python code from its I/O and state (files, network, models, global state, time, randomness) into functions on values, keeping its behaviour. Use when the user asks to simplify, untangle or refactor Python code that mixes them, and not otherwise.
---

# Python FP refactor

This skill moves the decisions and computation in Python code into functions
that take values and return values, and leaves I/O and state at the edges.
It runs only on a request to simplify, untangle or refactor.
Where this skill and the session's instructions conflict, the instructions win.

## Scope

This skill works inside a module.
The `hexagonal-architecture` skill covers service boundaries.

The refactor keeps:

- the codebase's style;
- the public interface;
- the exceptions callers rely on;
- the order of side effects;
- the moved code's error handling and validation.

It adds no layer, class hierarchy or framework beyond the extracted functions.

## Steps

1. Establish the scope: every caller of the code, its public interface, and
   the tests that cover it.
2. Run the existing tests and confirm they pass.
3. Where no test covers the logic, write characterization tests through the
   public interface first, and confirm they pass against the old code.
4. Move each decision and computation into a function that takes values and
   returns values. The function performs no I/O and does not mutate its
   inputs. Time and randomness are passed in as arguments.
5. Keep I/O at the edges, in the existing callers. Each caller reads its
   inputs, calls the extracted functions, and writes the results, with its
   side effects in their original order.
6. Where the risk warrants it, compare the old and new code on generated
   inputs through the `python-property-model-tests` skill before the old path
   is deleted.
7. Delete the old path. Add no compatibility shim unless a caller outside the
   repository needs one, and then ask the user before adding it.
8. Run the tests again and confirm they pass.

## Comments and docstrings

Test code and refactored code carry no comments.
Docstrings follow the project's convention.

## Example

Before:

```python
def overdue_ids(path):
    with open(path) as f:
        rows = json.load(f)
    now = time.time()
    return [r["id"] for r in rows if r["due"] < now]
```

After:

```python
def overdue(rows, now):
    return [r["id"] for r in rows if r["due"] < now]


def overdue_ids(path):
    with open(path) as f:
        rows = json.load(f)
    return overdue(rows, time.time())
```

## Delegation

A session that delegates this work to a subagent puts these steps into the
brief's constraints, because a subagent may be unable to load a skill.
