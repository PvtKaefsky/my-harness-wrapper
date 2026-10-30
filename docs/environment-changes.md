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
