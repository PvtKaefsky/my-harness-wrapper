---
name: python-property-model-tests
description: Writes tests that a Python unit keeps a property across many inputs or sequences of operations. Use for parsers, serializers, data transformations, state machines, caches and numeric code, and when the user asks for property-based, Hypothesis, invariant or model-based tests.
---

# Python property and model tests

General pytest usage, fixtures and coverage belong to the `python-testing` skill. Where this skill and the session's instructions conflict, the instructions win.

## Scope of a property test

A property test counts as the small test that each unit of new non-trivial logic gets. Each test checks one property. This skill is never a reason to test a trivial change.

## Tool choice

| Situation | Tool |
| --- | --- |
| The project already depends on Hypothesis | Hypothesis |
| The user asks for Hypothesis | Hypothesis, as a development dependency |
| Neither, and the session can ask | Hypothesis once the user agrees |
| Neither, and the session cannot ask | A seeded standard-library loop, and the reply says Hypothesis was not added |

The seeded loop draws inputs from `random.Random(1729)` in a `for` loop and passes each input to the assertion message, as in `assert decode(encode(v)) == v, repr(v)`.

## The property

The session states the property in one sentence before writing any code. The test name carries it in short form.

| Kind | Form |
| --- | --- |
| Round trip | `decode(encode(x)) == x` |
| Invariant | `len(sort(xs)) == len(xs)` |
| Idempotence | `f(f(x)) == f(x)` |
| Ordering law | A comparison is transitive, or a sort is stable |
| Metamorphic relation | `filter_rows(rows)` is a subset of `filter_rows(rows + extra)` |
| Reference model | `fast(x) == simple(x)` for a plainly correct simplified implementation |

## Input strategies

Strategies are drawn from the domain's types and from the code's own validation, covering accepted and rejected inputs. Edge values are included: empty collections, zero, negatives, boundaries, maximum lengths, non-ASCII text, and NaN and infinity where floats are accepted. A strategy that builds valid inputs directly replaces a filter that discards most inputs.

```python
from hypothesis import example, given, strategies as st

@given(st.text())
@example("")
@example("\x00")
def test_decode_inverts_encode(value):
    assert decode(encode(value)) == value
```

## Sequences of operations

Sequences of operations use `hypothesis.stateful.RuleBasedStateMachine`. The machine holds the system under test and a simplified in-memory model, such as a `dict`. Each `rule` applies one operation to both. An `invariant` compares the system with the model after each step. A `precondition` limits a rule to states where it applies. An `initialize` rule builds both before other rules run. The machine's `TestCase` attribute is the collected test.

```python
from hypothesis import strategies as st
from hypothesis.stateful import RuleBasedStateMachine, initialize, invariant, precondition, rule

class StoreMachine(RuleBasedStateMachine):
    @initialize()
    def start(self):
        self.store = Store()
        self.model = {}

    @rule(key=st.text(), value=st.integers())
    def put(self, key, value):
        self.store.put(key, value)
        self.model[key] = value

    @precondition(lambda self: self.model)
    @rule(data=st.data())
    def delete(self, data):
        key = data.draw(st.sampled_from(sorted(self.model)))
        self.store.delete(key)
        del self.model[key]

    @invariant()
    def matches_model(self):
        assert dict(self.store.items()) == self.model

TestStore = StoreMachine.TestCase
```

## Failing examples

A failing input Hypothesis finds is kept as an `@example(...)` on the property test or as a separate regression test with that input.

## Determinism in CI

CI loads the project's Hypothesis settings profile. Where the project has none, the session registers one in `conftest.py`:

```python
import os
from hypothesis import settings

settings.register_profile("ci", derandomize=True, database=None)
settings.load_profile(os.environ.get("HYPOTHESIS_PROFILE", "default"))
```

## Checking each test

Each test is checked once to fail when the property's code is broken. The session breaks that code, sees the failure, and restores it.

## Code style

Test code carries no comments. Docstrings follow the project.

## Delegation

A session that delegates this work to a subagent puts these steps into the brief's constraints, because a subagent may be unable to load a skill.
