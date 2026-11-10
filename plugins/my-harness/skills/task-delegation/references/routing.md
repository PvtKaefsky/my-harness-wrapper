# Routing tables

A subtask draws the first row of its table that matches. `SKILL.md` decides
which table a session uses, and what happens where an executor is unavailable.

## Coding table

| Subtask | Executor |
| --- | --- |
| Build, compile or type failure with a dedicated resolver | `ecc:cpp-build-resolver`, `ecc:dart-build-resolver`, `ecc:django-build-resolver`, `ecc:go-build-resolver`, `ecc:java-build-resolver`, `ecc:kotlin-build-resolver`, `ecc:pytorch-build-resolver`, `ecc:react-build-resolver`, `ecc:rust-build-resolver`, `ecc:swift-build-resolver` |
| Any other build or type failure | `ecc:build-error-resolver` |
| Tests written first | `ecc:tdd-guide` |
| End-to-end tests | `ecc:e2e-runner` |
| Documentation only | `ecc:doc-updater` |
| Removing dead code | `ecc:refactor-cleaner` |
| Behavior-preserving simplification | `ecc:code-simplifier` |
| Anything else | `my-harness:executor` |

## Analysis table

| Subtask | Executor |
| --- | --- |
| A sweep across many files or repositories for where something is | `Explore` |
| Tracing an execution path or feature | `ecc:code-explorer` |
| An independent review of a diff, unanchored by the session's view | the ECC reviewers whose subject the diff matches: `ecc:code-reviewer`, the language reviewer for each language in it, and each domain reviewer it touches |
| Design options or a plan | `ecc:architect`, `ecc:planner` |
| Research, a reproduction or a probe in scratch space, anything else | `my-harness:analyst` |

## Where the rows come from

Every `ecc:` executor above has an agent file of the same name under `agents/`
in ECC 2.2.3. `Explore` is built into Claude Code. `my-harness:executor` and
`my-harness:analyst` are this plugin's own agents.
