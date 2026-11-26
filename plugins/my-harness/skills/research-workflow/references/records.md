# Research records

## Layout

| Path | Content |
| --- | --- |
| `research/project.md` | Problem, motivation, objectives, scope and expected impact; what rarely changes |
| `research/state_of_art.md` | Review of the field, existing solutions and the state of the art |
| `research/history.md` | Append-only log of project events and changes of direction |
| `research/project_summary.md` | Current state of the project and its results |
| `research/references.bib` | Shared bibliography |
| `research/infrastructure/` | Shared datasets, baseline implementations, configurations and tools |
| `docs/glossary.md` | The one glossary: `Term \| Context \| Definition \| Code name \| Avoid \| Kind`, `Kind` being `concept`, `quantity` or `hyperparameter` |
| `research/HYP-<n>-<slug>/README.md` | The hypothesis document: main hypothesis, motivation and mechanism, scope, sub-hypotheses, steps, dependencies, acceptance criteria, status; it indexes its directory |
| `research/HYP-<n>-<slug>/design.md` | The design: the implementation's mathematics, constraints and interface |
| `research/HYP-<n>-<slug>/evaluation.md` | The protocol: conditions, metrics, baseline, statistical requirements, outlier rules |
| `research/HYP-<n>-<slug>/results.md` | Core analysis, additional analysis, statistics, limits and anomalies, and the researcher's conclusion |
| `research/HYP-<n>-<slug>/history.md` | Append-only log of changes to the hypothesis, its design and its status |
| `research/HYP-<n>-<slug>/experiments/<name>.yaml` | One experiment: an override of the base configuration |
| `src/<package>/<hypothesis>/` | The hypothesis's code, with tests mirrored under the tests directory |
| `runs/` | Run outputs; ignored by git |

Project records hold everything that is not specific to one hypothesis.
Nothing is duplicated between project and hypothesis records. A hypothesis
directory's files are created when they are needed. Where the repository-setup
skill gives a template for a record, the record takes the template's sections.

## IDs and status

| Unit | ID | Status values |
| --- | --- | --- |
| Hypothesis | `HYP-<n>`, `<n>` being the number of the issue that tracks it | `draft`, `approved`, `in progress`, `confirmed`, `refuted`, `inconclusive`, `abandoned` |
| Sub-hypothesis | `H1`, `H2`, numbered inside its hypothesis | as a hypothesis |
| Research step | `S1`, `S2`, numbered inside its hypothesis | `todo`, `in progress`, `done`, `blocked` |
| Experiment | `<name>`, its file name | none |
| Run | the run ID in its `metadata.json` | `completed`, `failed`, `interrupted` |

A sub-hypothesis is a testable claim the main hypothesis needs. A research
step is an action the test needs and makes no claim. Neither gets its own
directory or document; both live in the hypothesis document with their
status and links to the experiments behind them. A bare `S0` to `S6` names a
stage; a research step is named with its hypothesis, as `HYP-12 S2`.

## Runs

Each run writes, under `runs/`:

| File | Content |
| --- | --- |
| `config.yaml` | The resolved parameters of the run |
| `metadata.json` | Run ID, commit, a flag for a dirty tree, seed, environment, status |
| metrics, logs, artifacts | As `evaluation.md` sets |

A shared experiment tracker is used only where the team has agreed on one.
Otherwise the agent asks before adding one.

## Provenance

Research records name the role behind each decision and change: `researcher`
or `agent`. They carry no model name and no session link. Commits, pull
requests and comments carry no attribution.

## Documentation events

| Event | Record updated |
| --- | --- |
| A project starts | The project records are created |
| A new independent hypothesis | A new `research/HYP-<n>-<slug>/` |
| A hypothesis is decomposed | Its `README.md` |
| The mathematics changes | `design.md`, with an entry in the hypothesis's `history.md` |
| The protocol changes | `evaluation.md` |
| A new experiment | A new `experiments/<name>.yaml` |
| A new run | Its outputs under `runs/`, written by the code |
| A significant result | `results.md` |
| A hypothesis's status changes | Its `README.md` and `history.md`, and `research/project_summary.md` |

Rules:

- A new hypothesis is created only for an independent testable claim with its
  own mechanism.
- A hyperparameter change, an ablation, a bug fix or a robustness check is an
  experiment or a change inside the hypothesis, never a new hypothesis.
- No record is written for each agent action.
- Intermediate observations stay in machine logs or exploratory reports.
- History entries are dated and appended; earlier entries are never edited.
- A review or ponytail finding that would change an `approved` document, or
  the semantics of code that implements one, is declined and reported as a
  proposal.
