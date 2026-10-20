# Codex adapter

## Scope

The adapter delivers shared working instructions for Codex cloud tasks.
It verifies the delivered payload against the source checkout.
The Claude implementation remains separate.
Setup runs without root access.
The native ECC diagnostic probe uses supported native CLI registration commands.
A separate temporary skills-only experiment copies one unchanged pinned skill
and its upstream license into an already existing user skill scope during setup.
It does not change project files, Git identity, or Git signing settings.
It does not install a Codex CLI or reviewer agents or approve hook trust.
Its bounded ECC installation attempt and retained evidence are described in
[`codex-ecc.md`](codex-ecc.md).

## Files

| Path | Purpose |
| --- | --- |
| `AGENTS.md` | Instructions for developing this wrapper repository. |
| `config/codex/AGENTS.md` | Shared policy read by the agent in each task. |
| `config/codex/version` | Adapter version in `major.minor.patch` form. |
| `env/setup-codex.sh` | Runs regression suites, installs the payload, captures native ECC and one-skill diagnostics, and checks delivery. |
| `scripts/codex-common.sh` | Source fingerprint, state validation, and manifest validation. |
| `scripts/bootstrap-codex.sh` | Creates or refreshes an owned delivery release. |
| `scripts/verify-codex.sh` | Verifies delivery and reports unverified runtime integrations. |
| `scripts/session-check-codex.sh` | Verifies delivery, names the policy, reads retained setup evidence, and fails closed on ECC readiness. |
| `scripts/ecc-codex.sh` | Validates owned state and holds its lock for setup capture or read-only evidence consumption. |
| `scripts/ecc-codex.py` | Runs native probes, bounded user-skill placement, and read-only task measurement with separate evidence. |
| `scripts/test-codex-ecc.sh` | Runs deterministic setup/startup and deletion regressions through isolated copies of the real setup path. |
| `scripts/test-codex-ecc-skill.sh` | Tests real setup placement, separate-process measurement, negative controls, and deletion acceptance. |
| `scripts/tests/` | ECC test runners, bounded fake CLI, and pinned upstream skill/license data fixtures outside discovery roots. |
| `scripts/check-codex-attribution.sh` | Checks one prepared message or body file. |
| `scripts/check-codex-identity.sh` | Requires explicit environment identity and checks Git's resolved roles. |
| `scripts/commit-codex.sh` | Checks identity before invoking Git in the caller's repository. |
| `scripts/test-codex.sh` | Tests delivery, failure handling, and explicit attribution checking in a temporary Git repository. |
| `scripts/test-codex-git-context.sh` | Checks that inherited Git selectors cannot redirect fixture commits or source discovery. |
| `scripts/test-codex-identity.sh` | Exercises blocked and successful commits with conflicting global identity settings. |

## Environment UI

Attach `PvtKaefsky/my-harness-wrapper` at
`/workspace/my-harness-wrapper` alongside the target repositories.
Select the Codex implementation branch while testing an unmerged adapter.
Use `main` after the implementation is merged.
`feat/claude-harness` preserves the original Claude implementation.

The current setup script field (`install_script`) stays exactly as follows:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /workspace/my-harness-wrapper
bash env/setup-codex.sh
```

Paste this into the startup instructions (`start_skill` in cloud onboarding):

```text
The shared wrapper source is /workspace/my-harness-wrapper.
Run bash /workspace/my-harness-wrapper/scripts/session-check-codex.sh once at task start.
If it fails, report the failure and investigate it before relying on the affected capability.
Read /workspace/.harness-wrapper/current/AGENTS.md before working on the task.
Read and apply the target repository's applicable AGENTS.md files as well.
Follow higher-priority platform and user instructions.
Use the existing checkouts under /workspace; cloud tasks are already isolated.
Create a Git worktree only if the user explicitly requests one.
Work in the repository relevant to the task.
Change the wrapper source only when the task requests a wrapper change.
Do not run env/setup.sh or scripts/bootstrap.sh; they deploy the Claude implementation.
Do not assume ECC reviewers or automatic hooks loaded because their files exist.
Report unavailable capabilities and follow the shared policy's review fallback.
```

The startup field contains agent instructions, not shell commands executed by
the setup script.
The payload is outside project roots and is read explicitly by those instructions.
Copying it does not register global Codex instructions.
When `HARNESS_STATE_DIR` is customized, update the startup payload path to match.

Setup requires Bash, Git, jq, Python 3.9 or newer, and GNU/Linux utilities including `flock`,
`realpath`, `sha256sum`, and `mv -T`.
The setup-only ECC probe can download its pinned native marketplace and plugin
through the configured CLI and network policy.
It does not request new credentials or change network policy.
Existing GitHub authentication supplies attached-repository access.
Keep existing network settings unless another integration needs a destination.

The shared workflow uses `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`,
`GIT_COMMITTER_NAME`, `GIT_COMMITTER_EMAIL`, and `HARNESS_ASSIGNEE` for identity
and forge actions.
Enter personal values in environment settings when those actions are required.
Delivery verification does not assert that identity or forge access is configured.
No credential values belong in setup scripts or this repository.

Deployment requires the reviewed source to reach the checkout selected by a
subsequent actual Environment build.
Publication and a fresh task are product-only acceptance boundaries.
Publishing, restoration, and managed-task instruction loading require their own
verification; a passing local setup does not establish them.

## Delivery state

`HARNESS_STATE_DIR` defaults to `/workspace/.harness-wrapper`.
An override must be an absolute canonical path outside the source checkout.
Symlinked state paths are rejected.

```text
.harness-wrapper/
  .owner
  .lock
  ecc-setup/
    diagnostic.log
    status.json
  ecc-skill-probe/
    diagnostic.log
    scope.json
    status.json
  releases/
    release.<generated-id>/
      AGENTS.md
      manifest.json
  current -> releases/release.<generated-id>
```

Bootstrap creates a private state directory when that path does not exist.
It refuses an existing directory without the expected ownership marker and
layout, including an empty directory.
Choose a new path instead of deleting an unrecognized directory.
The ownership marker prevents accidental replacement; it is not authentication.

Bootstrap takes an exclusive lock with a ten-second wait limit.
Verification takes a shared lock with the same limit.
A complete release is prepared before an atomic replacement of `current`.
Cleanup preserves a release already published through `current`, including when
setup is interrupted immediately after publication.
Repeated bootstrap reuses the release when its commit, source fingerprint, and
recorded dirty flag match the checkout.
Older releases remain available and are not deleted automatically.

Bootstrap validates an existing release before replacing it.
A changed payload, malformed manifest, missing payload, or unexpected symlink
stops bootstrap without repairing or overwriting that release.
Preserve local edits and select a new state directory to recover.
An interrupted first-time initialization can leave an incomplete state directory;
preserve it and select a new path if validation rejects it.

## Verification

Run from any working directory:

```bash
bash /workspace/my-harness-wrapper/scripts/verify-codex.sh
```

Exit zero means the delivery checks passed.
Exit nonzero means a required check failed.
The session check reports delivery verification and retained ECC evidence
separately, preserving a delivery failure's exit status.
Otherwise it returns nonzero while ECC readiness is not demonstrated.
The setup script ends with delivery-only verification so an expected ECC probe
failure permits a diagnostic task to read the retained evidence.
Wrapper build and integrity failures remain fatal.

The manifest records the adapter version, full source commit, checkout dirty
flag at installation, source fingerprint, and payload checksum.
It contains no environment variables or credential values.
The source fingerprint covers the payload, version, setup, bootstrap,
verification, startup, common helpers, explicit attribution checker, identity
checker, guarded commit command, ECC helpers, both ECC suites, and pinned upstream skill/license data fixtures.
ECC diagnostics are not part of the adapter release or its manifest.
The dirty flag describes installation time and is not a live status check.
An installation made with uncommitted files reports a `NOTE`; the recorded
commit alone does not reproduce those files.

| Output | Meaning and action |
| --- | --- |
| `PASS Codex payload, manifest, source revision, and adapter checksum` | Delivery matches the checked source files. |
| `FAIL source revision or adapter files changed` | Rerun setup to install the current checkout. |
| `FAIL deployed payload differs from its manifest` | Preserve the modified payload and install into a new state directory. |
| `FAIL manifest is malformed` | Preserve the release and install into a new state directory. |
| `FAIL state directory is not owned by this adapter` | Choose a new state path. |
| `UNVERIFIED managed-task instruction loading, ECC reviewers, and automatic hooks` | These integrations were not exercised by delivery verification. |

A checksum match distinguishes matching bytes from changed bytes.
It does not establish who produced the files or that Codex read them.
A matching commit identifies the local source revision; it does not establish
remote freshness or reproducibility of uncommitted files.

## Commit identity

From the target repository, use the guarded command with the usual commit
arguments:

```bash
bash /workspace/my-harness-wrapper/scripts/commit-codex.sh -F /tmp/commit-message.txt
```

The command checks `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`,
and `GIT_COMMITTER_EMAIL` before invoking Git.
Each must be exported, nonempty, and contain a non-whitespace character.
Both Git roles must resolve to the corresponding variables and name the same
identity.
Diagnostics name missing or mismatched variables without printing their values.
The command exits one without invoking `git commit` when a check fails.
Global `user.name` and `user.email` do not satisfy the required variables.
Correct missing values in environment settings and recheck after they reach the
running task.

Check identity without making a commit:

```bash
bash /workspace/my-harness-wrapper/scripts/check-codex-identity.sh
```

The guard preserves the caller's working directory, Git context, commit
arguments, signing configuration, and Git's exit status.
Explicit author-selection options retain Git's usual behavior.
The guard does not rewrite commits or verify GitHub's email-to-account mapping.
It is an explicit command, not an installed Git or Codex hook.
Raw `git commit` can bypass it; the shared policy requires the guarded command.
Delivery setup and verification remain usable without a personal identity.

## Attribution

Prepare a message or forge body in a file and check it before posting:

```bash
bash /workspace/my-harness-wrapper/scripts/check-codex-attribution.sh /tmp/body.md
```

The checker reads the whole file without executing its contents.
It rejects author trailers, Claude and Codex session trailers, generated-by
footers naming Claude Code, Codex, or OpenAI, and recognized session links.
Exit zero means no configured pattern matched.
Exit two means an attribution pattern matched.
Exit one means the arguments or file could not be checked.
The patterns are conservative text checks, not a Markdown or Git parser.
They can match quoted examples and do not recognize every possible attribution.
The checker is explicitly invoked and does not intercept commits or tool calls.
The existing Claude hook and its tests remain unchanged.

## ECC and automatic hooks

ECC upstream documents native Codex installation with:

```bash
codex plugin marketplace add affaan-m/ECC
codex plugin add ecc@ecc
codex plugin list --json
```

The repository-owned setup probe uses native commands with the selected fixed
upstream SHA, after inspecting the setup executable's supported options.
It never falls back to floating main.
Task startup reads retained evidence and the recorded user-skill bytes.
It never installs, overwrites, links, moves, or registers plugins or skills.
Native inventory and a provider-dispatched invocation require a fresh diagnostic
task after operator-controlled publication, as specified in `codex-ecc.md`.
The CLI's installation state does not establish managed cloud task discovery.
Do not relocate or overwrite managed `CODEX_HOME` to force installation.
ECC's native hook documentation requires review and trust separately from plugin
installation.
Do not bypass trust.

The shared policy requires independent review before a commit.
If a required reviewer cannot run, finish implementation and tests, leave the
changes uncommitted, and ask how to proceed.
Claude reviewer names and model identifiers are not automatically Codex roles.
The adapter does not create role definitions or a Codex tool-event adapter.
Automatic attribution blocking and post-create attribution handling remain
unimplemented.
The explicit startup command blocks ordinary work while ECC is not ready.
See [`codex-ecc.md`](codex-ecc.md) for the diagnostic-only exception and the
separate skill and hook acceptance stages.

References:

* [ECC Codex plugin](https://github.com/affaan-m/ECC/blob/main/.codex-plugin/README.md)
* [Codex AGENTS.md documentation](https://developers.openai.com/codex/guides/agents-md)

## Development checks

```bash
bash scripts/test-attribution-guard.sh
bash scripts/test-codex.sh
bash scripts/test-codex-git-context.sh
bash scripts/test-codex-identity.sh
bash scripts/test-codex-ecc.sh
bash scripts/test-codex-ecc-skill.sh
bash env/setup-codex.sh
```

The Codex suite creates a temporary checkout and never commits in the real one.
Local adapter Git operations discard inherited repository, index, object, and
configuration selectors before selecting their source or fixture checkout.
The regression suite verifies that a caller repository's HEAD, index, objects,
and working files remain unchanged under inherited selectors.
Its temporary state and files are removed at exit.
Use `HARNESS_STATE_DIR` with a new absolute scratch path to exercise complete
setup without changing the default installation.
Bump `config/codex/version` when changing Codex delivery behavior.
The Claude `BOOTSTRAP_VERSION` changes only with a Claude deployment change.
Obtain the applicable independent reviews on the staged diff before committing.
