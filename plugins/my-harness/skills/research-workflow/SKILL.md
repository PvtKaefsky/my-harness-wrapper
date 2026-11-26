---
name: research-workflow
description: Sets what an agent decides and what it only proposes in scientific research work, where the researcher owns every scientific decision and the agent executes the approved design. Use for tasks on research hypotheses, experiments and runs, at any stage from problem statement and literature review through design, implementation, runs, analysis and handover; not for the Hypothesis property-based testing library, which python-property-model-tests covers.
---

# Research workflow

This skill governs a task that works on a research hypothesis, an experiment
or a run. Where this skill and the session's instructions conflict, the
instructions win.

## The boundary

The researcher owns these decisions: the problem, the hypotheses, the scope,
the method, the experimental design, the interpretation of results and the
conclusions. The agent executes the approved design. Every change the agent
wants to make to an approved hypothesis, design, protocol or algorithm is a
proposal in its reply, with its reason, and is not applied. Each proposal
starts with the label `Proposal:`.

The agent keeps three things apart in every report: what it observed, what it
infers, and what it assumes. A correlation it reports is stated as not
establishing causation.

## Modes

Each action in a task has one mode. Actions in one stage can have different
modes.

| Mode | The agent may |
| --- | --- |
| Human-owned | Give information and recommendations. The researcher decides. |
| AI-assisted | Draft, compare and propose. The researcher makes each decision the draft contains. |
| AI-executable | Do the action within the approved specification without asking. |
| Human-verified | Do the action and report it as unverified until the researcher has checked it. |

## Task specification

A non-trivial research task names these fields; one specification can cover
related tasks. Where a field the work needs is missing, the agent asks before
starting.

| Field | Content |
| --- | --- |
| Stage | `S0` to `S6` |
| IDs | The `HYP-<n>`, sub-hypothesis, step and experiment it serves |
| Objective | What the task produces |
| Context | The hypothesis document, `design.md` and `evaluation.md` it rests on |
| Scope | What the agent may change |
| Constraints | What the agent must not change |
| Artifacts | What the task delivers |
| Acceptance | How the work is accepted |
| Modes | The mode of each action |
| Approvals | What needs the researcher's approval before it is done |

## Stages

`references/stages.md` holds each stage's modes and the agent's rules for it.
The agent reads the section of the stage its task is in before starting.

| Stage | Outputs | Complete when |
| --- | --- | --- |
| S0 Opportunity | Problem statement, motivation, evidence the problem exists, potential impact, scope of applicability, references | The problem is stated, its existence is supported, its impact is estimated, and the researcher decides to continue |
| S1 Prior work | Literature review, state-of-the-art comparison, novelty assessment, alternative directions | The difference from existing work, the risks to novelty and the alternative directions are stated |
| S2 Hypothesis | Hypothesis and scope in the hypothesis document, glossary rows, predictions and refutation criteria | The researcher has approved the hypothesis, its scope, its mathematical terms and its refutation criteria |
| S3 Implementation | `design.md`, code, tests, the session's report, a commit, the environment specification, glossary rows | The code matches `design.md`, the tests pass, the researcher has checked the algorithm's central steps, and the code is committed |
| S4 Protocol and runs | `evaluation.md`, experiment files, run outputs, a reproduced baseline | The runs leave enough artifacts for an independent check and a handover |
| S5 Analysis | Core analysis, additional analysis, statistics, figures, limits and anomalies in `results.md` | The core checks are done, additional observations are recorded, and the researcher has written the conclusion |
| S6 Handover | History entries, links to every artifact, a list of what was not done | Another researcher can restore the configuration and continue without asking the author |

## Change categories

| Category | Examples | Decided by |
| --- | --- | --- |
| Implementation | Refactoring, a faster computation with the same semantics | The agent, within the task |
| Experimental | The hyperparameter grid, the number of repetitions, a metric, a new hyperparameter | The researcher; the agent proposes |
| Scientific | The hypothesis, the mathematical mechanism, the scope | The researcher; the agent proposes |

## Escalation

The agent stops the affected work and asks the researcher when:

1. the hypothesis or the specification contradicts itself;
2. the task needs a change to the algorithm's mathematics;
3. a change to the experimental protocol is needed;
4. a problem could make the results invalid;
5. the scope of the research would have to widen;
6. results differ materially from published results;
7. the expected behaviour cannot be determined from the specification.

The stop states the problem, its cause, the options, the consequence of each
option, and the agent's recommendation, and ends with the question the
researcher must answer, written as a direct question.

## Records

`references/records.md` holds the records layout, the hypothesis IDs, the
status values, run storage, provenance and the table of which record each
event updates. A document whose `Status:` line is `approved` changes only
where the task asks for that change; any other change to it is a proposal in
the reply. History files are dated and appended to, never rewritten.

## Definition of done

A research task is done when its report gives:

- the result;
- the files and artifacts changed;
- the configurations used;
- the tests run and their results;
- known limits;
- deviations from `design.md` or `evaluation.md`;
- open questions;
- the commits and run IDs.
