# Quick human-readable review

Instruction ID: skill/quick-human-readable-review.

## Codex adapter

Follow the wrapper and target AGENTS.md policies first. Interpret Claude/ECC tool and agent names through the currently available native Codex tools; use the configured Windows shell when a procedure says Bash. Slash-command references identify the corresponding harness-workflow skill. Inherit the operator's model choices; Claude model names do not select a Codex model. Never fabricate unavailable tools, reviewers or completion evidence. External actions still require task authorization.

## Harness instructions

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
