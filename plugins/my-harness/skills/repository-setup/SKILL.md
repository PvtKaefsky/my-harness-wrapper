---
name: repository-setup
description: Sets how a session creates a repository, on GitHub or locally, which top-level layout a repository holding application or library source takes, and the templates it applies for specs, glossary, architecture and its test, research records, the Python experiment layer, benchmark records, probe checks and project labels. Use before creating a repository, before adding a top-level directory to an existing repository, and when the user asks for one of those layers or records; not for other changes inside directories a repository already has.
---

# Repository setup

This skill governs three actions: creating a repository, adding a top-level
directory to an existing one, and applying a template. The Git workflow rules it names are the
session's own instructions. Where this skill and the session's instructions
conflict, the instructions win.

## Creating a repository

- A repository is created only when the user asks for one, on GitHub or as a local repository. On GitHub it is private unless the user names its visibility.
- It is created in this order:
  1. `git init --initial-branch=main`, then `git symbolic-ref HEAD` is read back as `refs/heads/main`.
  2. One commit holding only `README.md`, stating what the repository is.
  3. Where the repository goes on GitHub, it is created empty: no `--add-readme`, `--gitignore`, `--license` or `--template`, and no auto-initialization. Then `main` is pushed. Then the repository's default branch is read back as `main`.
  4. Every later change is made on a working branch, created and named under the Git workflow rules without the user asking; the `README.md` commit does not count as the repository's first commit for those rules. On GitHub, the change reaches `main` through a pull request. In a local-only repository, it stays on its working branch and is merged into `main` only when the user asks.
- The session creates no ruleset or branch protection.
- Where `HEAD` does not read `refs/heads/main`, the forge refuses the create, the default branch reads back as anything other than `main`, or the first push is refused, the session stops and asks. It never renames a default branch or changes repository settings.

## Repository layout

- A repository the session creates that holds application or library source takes a layout from `docs/repository-layouts.md` in the deployed copy: `/opt/my-harness-wrapper/docs/repository-layouts.md` in a cloud session, or that path under the directory `env.HARNESS_DIR` names in a local one. The session reads it once per repository, before it writes the scaffold, the first change after the `README.md` commit. A repository without application or library source, such as a documentation, infrastructure or configuration repository, takes no layout.
- One module takes the single-application layout; more than one takes the grouped layout. A module is a unit with its own manifest that is built, tested or deployed on its own. Where the task does not make clear whether there is one module or several, the session asks.
- Inside a module, the toolchain's documented convention decides where source and tests go. The top level always follows the layout. In a single-module repository the module is the repository root, so where the layout document's toolchain table places source at the module root, as for Go, that table decides.
- The A/B probe's files take the `probe/` role in both layouts: `probe/Dockerfile`, `probe/compose.yaml` and `probe/checks.sh`, in one top-level `probe/` directory. A grouped monorepo has one `probe/` at the top level for all its modules.
- `LICENSE` is added only where the user names a license.
- In an existing repository the session keeps the layout the repository has. In one that holds application or library source, a top-level directory the session must add takes the layout's name for that role, unless the repository already has one serving it; the session reads the layout document before adding it. A repository is restructured only when the user asks.
- Where the layout document cannot be read, the session stops and asks.

## Templates

- The templates are files under `templates/` in this skill's directory. Each lands at its path relative to the template directory named below, with every `<placeholder>` replaced. The layout document states each file's role and the probe checks' rules.
- A template is applied when the session creates a repository it applies to, or when the user asks for its layer or record. In an existing repository a template is applied only on the user's request, and a file the repository already has is kept.

| Template | Applies to | Lands at |
| --- | --- | --- |
| `templates/docs/specs/component.md` | a repository with components to specify, one file per component | `docs/specs/<component>.md` |
| `templates/docs/requirements.md` | a repository with `docs/specs/`; it replaces the requirement lines of `docs/requirements.md` | `docs/requirements.md` |
| `templates/docs/glossary.md` | every repository with a domain; the `Kind` column only where the repository has `research/` | `docs/glossary.md` |
| `templates/docs/architecture.md` | every repository holding application or library source | `docs/architecture.md` |
| `templates/architecture-test/tests/test_architecture.py` | a Python repository whose `docs/architecture.md` states a dependency rule | `tests/test_architecture.py` |
| `templates/python-experiment/` | a Python repository that runs experiments; its `README.md` lists the files and placeholders and is not copied | the project root |
| `templates/research/` | a repository with research hypotheses; the `HYP-n-slug/` files are created per hypothesis, each when it is needed | `research/`, and `research/HYP-<n>-<slug>/` for each hypothesis |
| `templates/docs/benchmarks/benchmark.md` | a benchmark, in any ecosystem | `docs/benchmarks/<benchmark>.md` |
| `templates/probe/checks.sh` | every repository with `probe/`; the project's own checks follow its two | `probe/checks.sh` |
| `templates/github/labels.json` | every repository on GitHub; its `area` paths match the repository's top-level directories | `.github/labels.json` |

- A spec's first line is `Status: active`, `Status: rejected` or `Status: superseded by <path>`. Its `Decisions` table holds only what review established. A test covering a scenario carries the scenario's ID in its name. Where the team names a spec decider, `CODEOWNERS` lists them for `docs/specs/`.
- A glossary row's definition is one sentence. A noun gets one row per state with its own meaning and one row per context where it means something else. `Code name` is the identifier, table or module carrying the term, and `Avoid` lists rejected synonyms. A research glossary has no rows for classes or helpers.
- Each dependency rule in `docs/architecture.md` gets one entry in the architecture test's `RULES`, and the test fails where a path a rule names is missing. The `Naming` table applies only where the project models events, commands or policies. The glossary and the context map are text, never images.
- In a research repository, `HYP-<n>` takes the number of the issue tracking the hypothesis, hypothesis code lives in `src/<package>/<hypothesis>/` with tests mirrored under `tests/<hypothesis>/`, and its module docstring names its `HYP-<n>`. Records name the role behind each decision and change, `researcher` or `agent`, with no model name or session link. There is no `formulation.md`. The `my-harness:research-workflow` skill governs how the records are filled.
- Where the project also runs `actions/labeler` with `sync-labels`, the labeler's labels take a family other than `area`.
