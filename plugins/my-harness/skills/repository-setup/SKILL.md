---
name: repository-setup
description: Sets how a session creates a repository, on GitHub or locally, and which top-level layout a repository holding application or library source takes. Use before creating a repository, and before adding a top-level directory to an existing repository; not for a change inside directories a repository already has.
---

# Repository setup

This skill governs two actions: creating a repository, and adding a top-level
directory to an existing one. The Git workflow rules it names are the
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
- `LICENSE` is added only where the user names a license.
- In an existing repository the session keeps the layout the repository has. In one that holds application or library source, a top-level directory the session must add takes the layout's name for that role, unless the repository already has one serving it; the session reads the layout document before adding it. A repository is restructured only when the user asks.
- Where the layout document cannot be read, the session stops and asks.
