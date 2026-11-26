Status: active

# <Component>

## Summary

<One paragraph: what the component does and for whom.>

## Motivation

<The problem the component solves.>

## Contract

### Behaviour

<What the component does, stated as facts.>

### Interfaces

| Command or call | Signature | Result |
| --- | --- | --- |
| `<command>` | `<one canonical signature>` | <what it returns or changes> |

### Configuration

| Name | Default | Meaning |
| --- | --- | --- |
| `<NAME>` | `<value>` | <what it sets> |

## Scenarios

| ID | Example | Given | When (actor and command) | Then (outcome, or "none") |
| --- | --- | --- | --- | --- |
| <PREFIX>-1 | The one when <situation> | <state before> | <actor> runs `<command>` | <outcome> |
| <PREFIX>-2 | The one when <edge case> | <state before> | <actor> runs `<command>` | none |

## Requirements

- <One testable line.> Check: `<test name or probe check id>`.

## Alternatives

| Alternative | Why not taken |
| --- | --- |
| <option> | <one clause> |

## Open questions

| Where | Question | Owner | Status |
| --- | --- | --- | --- |
| <section> | <question> | <role or login> | open |

## Decisions

| Decision | PR | Decided by | Dissent |
| --- | --- | --- | --- |
| <what review established> | #<n> | <role or login> | <none, or the objection> |
