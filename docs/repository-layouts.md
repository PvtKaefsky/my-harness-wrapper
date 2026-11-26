# Repository layouts

The top-level layout of a new repository that holds application or library
source. A repository without such source, such as a documentation,
infrastructure or configuration repository, takes no layout.

| Modules | Layout |
| --- | --- |
| One | The single-application layout |
| More than one | The grouped monorepo layout |

A module is a unit with its own manifest that is built, tested or deployed on
its own. Inside a module, the toolchain table decides where source and tests
go. The top level always follows the layout.

## Single-application layout

```
<repo>/
├── .github/            # workflows, issue and pull request templates, labels.json
├── conf/               # Hydra base configuration, only with the experiment layer
├── docs/               # indexed by docs/README.md
├── probe/              # the A/B probe: Dockerfile, compose.yaml, checks.sh
├── research/           # research records, only in a repository with research hypotheses
├── runs/               # run outputs, ignored, only with the experiment layer
├── scripts/            # build, release and maintenance scripts
├── src/                # all source: see the toolchain table
├── tests/              # tests that live outside the source tree
├── .gitignore          # ignores build output and installed dependencies
├── .env.example        # only where the application reads environment variables; never .env
├── <manifest>          # package.json, pyproject.toml, go.mod, Cargo.toml, pom.xml, build.gradle.kts
├── <lockfile>          # the manifest's lockfile, committed
├── Dockerfile          # where used
├── Makefile            # where used
├── LICENSE             # only where the user names a license
└── README.md
```

- The root holds configuration, manifests, these directories and repository
  metadata only. No source file sits at the root.
- Where the toolchain table places source elsewhere, as Go does, the table
  decides, and `src/` is absent.
- `src/`'s internal structure belongs to the project. No subdirectory such as
  `components/`, `services/` or `utils/` is required.
- Build output and installed dependencies are ignored, never committed:
  `dist/`, `build/`, `target/`, `node_modules/`, `.venv/`.

## Toolchain table

| Ecosystem | Source | Tests | Source cited |
| --- | --- | --- | --- |
| JavaScript, TypeScript | `src/` | `tests/`, mirroring `src/` | Turborepo, "Structuring a repository" |
| Python | `src/<package>/` | `tests/` | Python Packaging User Guide, "src layout vs flat layout" |
| Go | the module root, `internal/`, `cmd/<program>/`; no `src/` | `*_test.go` beside the code it tests | go.dev, "Organizing a Go module" |
| Rust | `src/` (`lib.rs`, `main.rs`, `bin/`) | unit tests in their source file; integration tests in `tests/`; `benches/`, `examples/` | The Cargo Book, "Package Layout"; The Rust Programming Language, "Test Organization" |
| Java or Kotlin, Maven or Gradle | `src/main/<language>/`, `src/main/resources/` | `src/test/<language>/` | Maven, "Introduction to the Standard Directory Layout" |

The table lists only ecosystems it can cite. Any other ecosystem takes the
layout its build tool documents, and the change that adds the scaffold names
that source in its pull request description, or in its commit message where
the repository has no pull request.

## Grouped monorepo layout

```
<repo>/
├── .github/
├── apps/               # deployable applications and services
│   └── <app>/          # its own manifest and README.md; inside, the toolchain table
├── libs/               # shared internal libraries
│   └── <lib>/          # its own manifest and README.md; inside, the toolchain table
├── docs/
├── probe/              # the A/B probe, one for the whole repository
├── scripts/            # repository-wide scripts
├── <workspace manifest>
├── <lockfile>
├── <orchestrator config>   # turbo.json or nx.json, only where one is used
├── .gitignore
├── LICENSE             # only where the user names a license
└── README.md
```

| Ecosystem | Workspace manifest |
| --- | --- |
| JavaScript, TypeScript | `package.json` `workspaces`, or `pnpm-workspace.yaml` `packages`, listing `apps/*` and `libs/*` |
| Go | `go.work`, with a `use` entry per module |
| Rust | `Cargo.toml` `[workspace]` `members` |
| Java or Kotlin | `settings.gradle.kts` `include`, or a parent `pom.xml` with `<packaging>pom</packaging>` and `<modules>` |
| Python | `pyproject.toml` `[tool.uv.workspace]` `members` |

- Apps are thin entry points: an app holds its entry point, configuration and
  the composition of its features.
- Code that more than one app uses lives in `libs/`.
- An app never imports another app.
- Libraries may be grouped by domain, one level deep: `libs/<domain>/<lib>/`.
  The domain level holds no manifest.
- Turborepo names the libraries folder `packages/`. This layout names it
  `libs/`.

## Probe directory

`probe/` holds the files of the A/B probe, which runs the project's scripted
checks in Docker on a baseline tree and a candidate tree.

| File | Role |
| --- | --- |
| `probe/Dockerfile` | the image the checks run in |
| `probe/compose.yaml` | the compose file that runs the image |
| `probe/checks.sh` | the scripted checks |

- The files are committed to the project.
- Both layouts place `probe/` at the top level.
- A grouped monorepo has one `probe/` for all its modules.
- The image needs `bash`, `git`, `gawk`, `grep` and `coreutils`, plus whatever
  the Quick Start command and the project's checks run.

`probe/checks.sh` starts from the `repository-setup` skill's template, whose
two checks come before the project's own. Each check appends one line
`{"id": ..., "status": "pass" | "fail", "seconds": ...}` to
`/results/checks.jsonl` through `record <id> <status> <seconds>`. The
variables `CHECKS_WORK` and `CHECKS_OUT` replace `/work` and
`/results/checks.jsonl` outside the container.

| Check | Passes where |
| --- | --- |
| `quickstart` | the Quick Start command exits 0 in a fresh `git clone` of `/work`, with no network and a 600-second limit |
| `spec-trace` | every scenario ID in a `docs/specs/*.md` file whose first line is `Status: active` appears in exactly one scenario row and matches at least one test file |

- `README.md` marks the Quick Start command as a fenced code block whose info
  string is `sh quickstart`. The check runs the block's lines with
  `bash -euo pipefail`.
- Where the Quick Start needs a secret or the network, `README.md` also
  carries an offline mode in a block whose info string is
  `sh quickstart-offline`, and the check runs that block instead. Where the
  Quick Start has no offline mode, the project removes the check, since the
  probe container has no network and no credential.
- A scenario ID is the first cell of a row under the `## Scenarios` heading of
  a spec: a prefix of capital letters and digits naming the component, a
  hyphen and a number, such as `RATELIMIT-3`.
- A test file is a tracked path under a `test/`, `tests/` or `__tests__/`
  directory, or one named `test_*`, `*_test.*`, `*.test.*`, `*.spec.*`,
  `*Test.*` or `*Tests.*`.
- An ID matches a test file whose content holds it as a whole token, in any
  casing, with `-` or `_` between prefix and number: `RATELIMIT-3` matches
  `test_ratelimit_3_rejects_burst` and `it("RATELIMIT-3 ...")`, and not
  `RATELIMIT-30`.
- The check prints `spec-trace -> <ID> repeated` or
  `spec-trace -> <ID> names no test` for each failing ID.

## Documentation roles

| Path | Role | Template |
| --- | --- | --- |
| `docs/specs/<component>.md` | One component's spec: status, summary, motivation, contract, scenarios, requirements, alternatives, open questions and decisions | `docs/specs/component.md` |
| `docs/requirements.md` | With `docs/specs/`, the index of specs, one row each; without it, the requirement lines | `docs/requirements.md` |
| `docs/glossary.md` | `Term \| Context \| Definition \| Code name \| Avoid`, plus `Kind` where the repository has `research/` | `docs/glossary.md` |
| `docs/architecture.md` | C4 diagram, context map, component edges, dependency rules, domain rules and naming | `docs/architecture.md` |
| `docs/benchmarks/<benchmark>.md` | One benchmark: revision, inputs, configuration, hardware, build and run commands, expected result and a link to the actual run | `docs/benchmarks/benchmark.md` |
| `tests/test_architecture.py` | The Python architecture test: one rule per dependency rule, each asserting its paths exist | `architecture-test/tests/test_architecture.py` |
| `.github/labels.json` | The project's labels in the schema `scripts/labels.sh` reads, with an `area` path map | `github/labels.json` |

- A spec file is named by its component's slug, with no number. Its first
  line is `Status: active`, `Status: rejected` or
  `Status: superseded by <path>`.
- Each requirement line lives in one place: the component's spec where
  `docs/specs/` exists, `docs/requirements.md` otherwise.
- The glossary's `Kind` is `concept`, `quantity` or `hyperparameter`, and a
  definition may carry a formula.
- The glossary, the context map and the C4 diagram are text, never images.
- The architecture test walks the imports of every `.py` file under a rule's
  source directory with `ast`, resolving relative imports, and needs no
  dependency.
- The label file holds the families `type`, `area`, `size`, `budget`,
  `research` and `signal`. Where the project also runs `actions/labeler` with
  `sync-labels`, the labeler's labels take a family other than `area`, since
  each tool removes the other's labels.

## Research directory

`research/` holds the records of a repository with research hypotheses.

| Path | Content |
| --- | --- |
| `research/project.md` | Problem, motivation, objectives, scope and expected impact |
| `research/state_of_art.md` | The field and its existing solutions |
| `research/history.md` | Dated, append-only project log |
| `research/project_summary.md` | Current state and each hypothesis's status |
| `research/references.bib` | Shared bibliography |
| `research/infrastructure/` | Shared datasets, baselines, configurations and tools, indexed by its `README.md` |
| `research/HYP-<n>-<slug>/README.md` | The hypothesis document, indexing its directory: status, main hypothesis, motivation, scope, decomposition, dependencies, acceptance and refutation criteria |
| `research/HYP-<n>-<slug>/design.md` | Mathematics, constraints and interface |
| `research/HYP-<n>-<slug>/evaluation.md` | Metrics, repetitions, baselines, randomness control and the planned grid |
| `research/HYP-<n>-<slug>/results.md` | Core and additional analysis, statistics, limits and anomalies, and the researcher's conclusion |
| `research/HYP-<n>-<slug>/history.md` | Dated, append-only hypothesis log |
| `research/HYP-<n>-<slug>/experiments/<name>.yaml` | One experiment, an override of `conf/config.yaml` |

| Unit | Status values |
| --- | --- |
| Hypothesis, sub-hypothesis `H<n>` | `draft`, `approved`, `in progress`, `confirmed`, `refuted`, `inconclusive`, `abandoned` |
| Step `S<n>` | `todo`, `in progress`, `done`, `blocked` |
| Run | `completed`, `failed`, `interrupted` |

- `<n>` in `HYP-<n>` is the number of the issue that tracks the hypothesis.
- A hypothesis document's first line is `Status: <value>`.
- A hypothesis directory's files are created when they are needed.
- Hypothesis code lives in `src/<package>/<hypothesis>/`, its tests in
  `tests/<hypothesis>/`, and its module docstring names its `HYP-<n>`.
- Records name the role behind each decision and change, `researcher` or
  `agent`, with no model name or session link.
- There is no `formulation.md`.

## Experiment layer

The Python experiment layer is the `repository-setup` skill's
`templates/python-experiment/`, whose `README.md` lists its files and
placeholders.

| Path | Role |
| --- | --- |
| `.env.example` | Every environment name with a safe value; `.env` is read through `python-dotenv` and ignored |
| `conf/config.yaml` | Hydra base configuration, reading environment values with `${oc.env:<NAME>}` |
| `research/HYP-<n>-<slug>/experiments/<name>.yaml` | Per-experiment override |
| `runs/<run_id>/` | One run: `config.yaml`, the resolved configuration with secrets as `'***'`; `metadata.json`; the task's results |
| `Makefile` | `build`, `up`, `down`, `test` and `experiment EXP=<name> [HYP=<directory>]`, run in the project's image |

- `metadata.json` holds `run_id`, `experiment`, `commit`, `dirty`, `seed`,
  `environment` and `status`.
- A run with `dirty: true` is cited by no `results.md`.
- `runs/` is ignored. A shared experiment tracker is added only where the team
  has agreed one.

## Sources

| Source | Establishes |
| --- | --- |
| Turborepo, "Structuring a repository", `turborepo.dev/docs/crafting-your-repository/structuring-a-repository` | `apps/` for applications and services, and `packages/` for libraries and tooling. Workspaces declared by `package.json` `workspaces` or `pnpm-workspace.yaml` `packages`, with `apps/*` and `packages/*`. Each package has its own `package.json`. Packages commonly keep source in `src/`, which is not required. Nested globs such as `apps/**` are unsupported, a package inside another package is an error, and a grouping glob such as `packages/group/*` works where the group directory has no `package.json`. It states nothing on tests. |
| Nx, "Monorepo Folder Structure", `nx.dev/docs/kb/folder-structure` | The grouped layout: applications under `apps/`, reusable code under `libs/`. An application holds the deployable shell, its entry point, configuration and the composition of features, and most code lives in `libs/`. Libraries are grouped by the application or domain they serve, and grouping folders may nest. It does not state that an app never imports another app. |
| Python Packaging User Guide, "src layout vs flat layout", `packaging.python.org/en/latest/discussions/src-layout-vs-flat-layout/` | The src layout keeps the importable package in `src/<package>/`, which prevents the in-development copy from being imported by accident. It states nothing on tests. |
| go.dev, "Organizing a Go module", `go.dev/doc/modules/layout` | Package and command code at the module root; supporting packages in `internal/`; several commands under `cmd/<program>/`. No layout uses `src/`. Its examples place each `*_test.go` beside the code it tests. |
| go.dev, "Tutorial: Getting started with multi-module workspaces", `go.dev/doc/tutorial/workspaces` | A `go.work` file lists each module directory with a `use` directive. |
| The Cargo Book, "Package Layout", `doc.rust-lang.org/cargo/guide/project-layout.html` | `src/lib.rs`, `src/main.rs` and `src/bin/`; `benches/`, `examples/` and integration tests in `tests/`. |
| The Rust Programming Language, "Test Organization", `doc.rust-lang.org/book/ch11-03-test-organization.html` | Unit tests live in the source file they test, in a `#[cfg(test)]` module. |
| The Cargo Book, "Workspaces", `doc.rust-lang.org/cargo/reference/workspaces.html` | A root `Cargo.toml` `[workspace]` table whose `members` lists member directories, globs allowed. |
| Maven, "Introduction to the Standard Directory Layout", `maven.apache.org/guides/introduction/introduction-to-the-standard-directory-layout.html` | `src/main/java`, `src/main/resources`, `src/test/java` and `src/test/resources`; other source types in sibling subdirectories, such as `src/main/antlr`; `target/` for build output. |
| Maven, "Introduction to the POM", `maven.apache.org/guides/introduction/introduction-to-the-pom.html` | An aggregator `pom.xml` sets `<packaging>pom</packaging>` and lists each module in `<modules>`. |
| Gradle, "Multi-Project Builds", `docs.gradle.org/current/userguide/multi_project_builds.html` | `settings.gradle.kts` declares subprojects with `include`. |
| uv, "Using workspaces", `docs.astral.sh/uv/concepts/projects/workspaces/` | A root `pyproject.toml` `[tool.uv.workspace]` table whose `members` lists member directories, globs allowed, each holding its own `pyproject.toml`. |

The JavaScript and TypeScript `tests/` directory and the Python `tests/`
directory are this layout's choice; neither source places tests.
`src/main/kotlin` and `src/test/kotlin` follow the Maven layout's per-language
subdirectories; the Maven page names only `java`.
