# Stages

Each section gives the stage's actions grouped by mode, then the agent's
rules. The modes are defined in `SKILL.md`.

## S0 Opportunity

| Mode | Actions |
| --- | --- |
| Human-owned | Stating the problem; judging its research and practical value |
| AI-assisted | Analysing applications and use cases |
| AI-executable | Finding evidence that the problem exists; finding estimates of its scale; drafting the evidence records |
| Human-verified | The evidence that the problem exists |

The problem and its motivation go to `research/project.md`.

## S1 Prior work

| Mode | Actions |
| --- | --- |
| Human-owned | Approving the research direction |
| AI-assisted | Comparing the proposed solution with existing ones; finding directions for novelty; drafting alternative directions |
| AI-executable | Finding relevant work; organising existing approaches |
| Human-verified | The main sources and claims |

Rules:

- The search never rests on keyword matches alone.
- Each related work is compared on its problem, its mechanism and its
  conditions of applicability.
- Finding no results is reported as a search outcome, never as evidence that
  no such work exists.
- Every material claim cites its source in `research/references.bib`.
- Work that could make the hypothesis obsolete is listed in its own section.

The review goes to `research/state_of_art.md`.

## S2 Hypothesis

| Mode | Actions |
| --- | --- |
| Human-owned | Formulating the hypothesis; setting its scope |
| AI-assisted | Proposing alternative formulations; decomposing it into sub-hypotheses; finding counterexamples; formalising the mathematics; drafting glossary rows |
| Human-verified | That the formalisation matches the researcher's intent |

Rules:

- The hypothesis is a refutable claim, quantitative or qualitative.
- The agent never replaces the hypothesis with one easier to test, and never
  widens its scope.
- The agent marks which statements follow from the formulation and which are
  added assumptions.
- The agent proposes ways to refute the hypothesis.
- Glossary rows cover concepts, mathematically distinct quantities and exposed
  hyperparameters, never classes or helper functions, and avoid nonstandard
  terms.

## S3 Implementation

| Mode | Actions |
| --- | --- |
| Human-owned | The algorithm's mathematics; any change to it |
| AI-assisted | Drafting `design.md`; the implementation plan |
| AI-executable | Writing the code and its unit and integration tests; checking the code against `design.md`; restructuring code without changing semantics |
| Human-verified | The algorithm's central steps; that the code matches the mathematics and the hypothesis |

Rules:

- Before coding, the agent lists the requirements `design.md` sets.
- Where `design.md` is ambiguous, the agent asks; it never picks the reading
  that is easiest to implement.
- The agent adds no normalisation, regularisation, heuristic or other change
  to the algorithm without the researcher's approval.
- Every deviation from `design.md` is recorded in the report and in the
  hypothesis's `history.md`.
- The agent reports every contradiction between `design.md`, the existing code
  and the mathematics.
- An optimisation keeps the algorithm's semantics.
- A hypothesis exposes one or two hyperparameters. A new hyperparameter is an
  experimental change and goes to the researcher as a proposal.
- The module docstring of hypothesis code names its `HYP-<n>`.

## S4 Protocol and runs

| Mode | Actions |
| --- | --- |
| Human-owned | The experimental conditions; the metrics and how they are read |
| AI-assisted | Drafting `evaluation.md`; the depth of control over randomness |
| AI-executable | Logging; experiment configurations; launching runs and collecting results; reproducing the baseline; running the approved grid |
| Human-verified | The protocol; that the baseline matches its published result |

Rules:

- The agent never changes approved experimental conditions.
- Every run saves its configuration; a run that overrides a parameter logs
  the override.
- Failed and interrupted runs are kept and recorded with their status.
- No outlier or result is removed without a rule written in `evaluation.md`.
- The agent compares the runs executed with the runs planned and reports
  every gap.
- The agent reports every difference between expected and observed behaviour.
- Each configuration runs at least three times. Three runs estimate spread;
  they do not establish statistical significance.
- At least one state-of-the-art baseline is reproduced to its published
  result. Every comparison and claim is made against the baseline.
- A modification is compared with the existing approach on the best
  configuration of each side, so neither side is under-elicited.
- Each run records every metric it can, since a metric added later costs
  new runs.
- Each metric in `evaluation.md` states what it measures, how, and how it is
  read.
- Where no logging framework or format is agreed, the agent asks.

The main algorithm's hyperparameter grid widens only on the researcher's
approval, and only in two cases:

1. the hypothesis was not confirmed well enough, and executed runs give
   evidence that the modification moved the optimal configurations;
2. the result is already good and the claim needs strengthening.

## S5 Analysis

| Mode | Actions |
| --- | --- |
| Human-owned | The questions the results must answer; interpreting the results against the hypothesis; the conclusion |
| AI-assisted | Finding patterns and anomalies; a preliminary interpretation |
| AI-executable | The requested figures; the statistics; additional checks |
| Human-verified | The statistical inferences |

Rules:

- The core analysis is exactly what the researcher requested.
- Additional analysis sits in its own section, and each item names the claim
  it tests and why it is proposed.
- A correlation is never reported as causation.
- Statistical significance is never reported as practical significance.
- An unexpected pattern gets proposed checks, never a claim of discovery.
- Every conclusion cites the run IDs it rests on.
- `results.md` cites no run whose metadata marks a dirty tree.
- The conclusion section of `results.md` is the researcher's; the agent
  leaves it empty or carries the researcher's words.

## S6 Handover

| Mode | Actions |
| --- | --- |
| Human-owned | The hypothesis's final status; accepting the handover, by the receiving researcher |
| AI-assisted | The short report |
| AI-executable | Collecting artifact links; appending to `history.md`; checking the package is complete |
| Human-verified | The scientific interpretation |

Rules:

- The agent never rewrites the research history.
- Every material change to the hypothesis or the protocol is recorded.
- Confirmed results, preliminary observations and open questions are kept
  apart.
- The report states which parts of the research were not done.
- The report links the data, configurations, logs and commits.
