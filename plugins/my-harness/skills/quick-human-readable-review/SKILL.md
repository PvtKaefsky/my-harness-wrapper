---
name: quick-human-readable-review
description: Shapes a summary of a finished stage of work, a run, a benchmark or an experiment series, with the outcome first, then confirmed results with their evidence, open questions and one next step. Use whenever the user asks for the outcome, results or summary of such work; it is not a code review and does not apply to a request to review code or a diff.
---

# Quick human-readable review

This skill sets the shape of a summary of a finished stage of work or a series
of experiments.
Where this skill and the session's instructions conflict, the instructions win.
Where a task prompt gives a report shape, that shape wins over this skill's.

## Language

The summary is written in the user's language.
Numbers, units, identifiers, commands, paths and commit hashes stay exactly as
they appear in the source.

## Parts of the summary

| Part | Content |
| --- | --- |
| Outcome | One or two sentences stating what the stage or series established. It comes first. |
| Confirmed results | Each result with its evidence: the command, commit or run that produced it, and its numbers with their run counts, seeds or spread. |
| Open questions | Each question with the one observation that would settle it. |
| Next step | One concrete action. |

Runs being compared appear as a table, one row per run, with the same columns
for every row.
A reason appears only where it changes what the reader does, in one clause.

## Confirmed and open results

A result is confirmed only when its evidence passes this test: a value that
distinguishes states names the states it cannot tell apart, and is checked in
both directions, so that the state produces the value and no other state does.
Each of these is an open question:

- a result from a single run;
- a result checked in one direction only;
- a value that more than one state produces.

## Closing lines

Where the session's instructions set closing lines for a reply that reports a
code change, those lines stay as set.
The summary does not repeat their content.

## Skeleton

```
<Outcome in one or two sentences.>

Confirmed
- <result>: <numbers>, <n runs, seeds or spread>. Evidence: <command, commit or run>.

Open
- <question>. Settled by: <one observation>.

| Run | <parameter> | <metric> | Runs | Spread |
| --- | --- | --- | --- | --- |
| <id> | <value> | <value> | <n> | <value> |

Next: <one concrete step>.
```
