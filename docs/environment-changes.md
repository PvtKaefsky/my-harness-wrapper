# Environment changes

The procedure for making one. `config/CLAUDE.md`'s Environment changes section
decides whether a change is one and where it is recorded. This file carries the
steps that apply once it is.

## Authoring tests for a new rule

Two tests apply to a rule being added. The generalize-before-filing exception in
`config/CLAUDE.md` does not carry over to them: a rule failing one of these is
not relocated to the project.

| Test | A rule that fails it |
| --- | --- |
| Has a bound on the recurring work it creates | is not added at all, and that it was not added is reported to the user |
| Says what happens when it cannot be satisfied | is added, with the stop-and-ask default written in |

A rule that creates recurring work — per commit, per turn, or per review round —
has a bound on that work. The bound is checked at review rather than stated in
the rule.

A rule stated without exception, whether phrased as never, always, no
exceptions, or categorically in other words, states what happens when it cannot
be satisfied: it names the state in which following it would leave the session
unable to proceed, and says what to do in that state. The default is to stop and
ask. A rule with no such state says nothing about it.

## The evidence record for a new control

A control is a hook, a rule, a gate or a permission. Each control an environment
change adds gets one record, written in the commit that adds the control, in
`docs/environment.md` under the section for the control's subject.

| Field | What the record states |
| --- | --- |
| Incident | The event the control answers, and the commit, pull request, issue or path that records it. |
| Blocked input | One input the control must block. |
| Permitted neighbour | One input close to the blocked one that the control must pass. |
| Bypass | An alternate path that could reach the same outcome without meeting the control. |
| Host and revision | The host the blocked input and the permitted neighbour were shown on, and the revision they were shown at. |
| Cost | The control's false blocks, the latency it adds, and the upkeep it needs. |
| Owner | Who decides to change or remove the control. |
| Removal condition | The state in which the control is removed. |

A field with nothing to record says so, and is not left out. The record states
no secret, credential, token or key, and no name or location of one. Where the
blocked input or the permitted neighbour cannot be shown, the session stops and
asks before adding the control.

Reference for the practice of recording evidence for a control:
`guide/core/agent-harness.md` in
`https://github.com/FlorianBruniaux/claude-code-ultimate-guide` at commit
`f1f8df9`.

## Checking a plugin source

Before a row is added to `config/plugins.tsv`, or the source of a row is
changed, the source's author and name are looked up in
`examples/commands/resources/threat-db.yaml` of
`https://github.com/FlorianBruniaux/claude-code-ultimate-guide`. The session
resolves that repository's default branch to a commit SHA on the forge, and
reads the file from the forge at that SHA.

The result is recorded in `docs/environment.md`, under the section for the
plugin, in the commit that adds or changes the row. The record states:

| Field | What the record states |
| --- | --- |
| Commit | The full SHA the file was read at. |
| Searched | The author and the name looked up. |
| Result | `listed`, with the entry found quoted in full, or `not listed`. |

A source that is not listed has not been shown safe by the lookup, and the
result alone does not decide whether the row is added. Where the source is
listed, the file cannot be read, or its structure is not the one the lookup
expects, the session stops and asks before adding or changing the row.
