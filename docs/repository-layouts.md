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
├── .github/            # workflows, issue and pull request templates
├── docs/               # indexed by docs/README.md
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
