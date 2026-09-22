# Runbook

## Deploying a change under `config/`

In this order:

1. Merge the round to `main`.
2. Where the round changed what `env/setup.sh` does, paste the full contents of
   `env/setup.sh`, read from `main`, unchanged, into the setup-script field of
   the cloud environment at claude.ai → Settings → Environments. Where it did
   not, skip this step.
3. Start a session after the build and read `/home/user/bootstrap.log`. A round
   that skipped step 2 triggers no build. It reaches a session at the next build
   another trigger starts, and `docs/environment.md` lists the triggers under
   "Snapshot caching".

`BOOTSTRAP_VERSION` is bumped in the commit that changes what `env/setup.sh`
does, never on its own. A mismatch means the pasted copy is older than the
repository's, and a paste is due. The comparison does not separate an older
pasted copy from a newer one, such as a copy pasted from an unmerged branch.

The environment variables panel carries the four identity variables
`GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME` and
`GIT_COMMITTER_EMAIL`. No repository needs attaching.

The facts that fix that order:

* A paste is consumed by the build it triggers. The next build needs a new
  paste.
* Pasting identical text does not rebuild. Only the text the dialog holds is
  compared, so a bump to any other file changes nothing.
* A rebuild clones the default branch as it stands at build time, so a paste
  made before the merge spends that version on the old tree.
* A change outside `env/setup.sh` reaches the next build without a paste, and
  no operator action triggers that build.
* The first session after a paste builds the snapshot, whatever it is working
  on.
* A session's log describes its own container, so the build's log is read in a
  session started after the build, not in one already running.

This repository is attached only to record or implement an environment change
the user asked for.

### Cloning a different repository

The init script assigns its own default clone URL where `HARNESS_REPO_URL` is
unset or empty. To clone a different repository, edit that default URL in the
pasted copy of `env/setup.sh`.

## The version line

`scripts/verify.sh` reads the expected version from the same
`export BOOTSTRAP_VERSION=` line the dialog is pasted from, so one edit does
both and the two cannot disagree as text. It reads that line literally rather
than evaluating it, so the value must be bare. It fails on a line that is
absent, appears more than once, cannot be read, matches without producing
output, carries no value, or carries a value outside `[0-9A-Za-z._-]` once
trailing spaces and tabs are trimmed — quotes, trailing comments, a leading tab,
an interior space and a trailing carriage return among them. Only a line
beginning `export` in column 0 is seen, so a second assignment indented or
without `export` is invisible to it and not to the shell.

## Verifying a session

```
bash /opt/my-harness-wrapper/scripts/verify.sh
```

It prints `id`, `$HOME`, `CLAUDE_CONFIG_DIR`, the resolved config directory, the
CLI version, the installed plugins and the manifest, then runs the checks below.
The exit status is 1 where any check failed and 0 otherwise; a check that exits
early also exits 1. It is not a count. A `NOTE` line can appear alongside exit 0
and does not set the exit status.

Two checks exit immediately and stop the run: `FAIL live config dir path` and
`FAIL manifest: ... actual absent`. Every other check runs to the end.

| Line | What it means | What to do |
| --- | --- | --- |
| `FAIL live config dir path` | The resolved config directory is not an absolute path. `CLAUDE_CONFIG_DIR` holds an empty or relative value, or it is unset and `HOME` is relative. The `CLAUDE_CONFIG_DIR ->` line above separates `unset`, `set but empty` and a value. | Unset it, or set an absolute path. |
| `FAIL manifest: ... actual absent` | No bootstrap has run in the resolved config directory. | Read `/home/user/bootstrap.log`. The setup script was never pasted, the snapshot predates it, or the CLI reads a directory bootstrap never wrote. |
| `FAIL manifest.commit`, both sides a commit | Bootstrap ran against an older commit than the repository now holds. | Expected while the snapshot is frozen. Force a rebuild when the delta touches `config/`. |
| `FAIL manifest.commit: ... actual unresolved-manifest` | The manifest carries no readable `commit` field. | Re-run bootstrap. The manifest was hand-edited or its write failed. |
| `FAIL manifest.commit: expected unresolved-repo` | `git -C <repo> rev-parse --short HEAD` produced nothing, so the repository being checked is absent or is not a git repository. | Read the path in the line. The deployed copy is missing, or `HARNESS_DIR` names something else. The two sides carry different defaults, so two unknowns never compare equal and pass. |
| `FAIL expected version` | No expectation could be read from `env/setup.sh`. The `grep` line above names the state: `no such line`, `more than one line`, `not read`, `matched but produced no output`, `present and empty`, or `unparsed value`. | Fix the tree. On `not read`, the `test -f` line above reads `yes` only where a regular file exists that `grep` could not read; it reads `no` for an absent path, a directory, a dangling symlink and an unsearchable parent alike, separating none of those. |
| `FAIL expected version: expected a known internal state` | The script reached a branch it does not define while reading the version line. | Report it as a defect in `scripts/verify.sh`. |
| `FAIL manifest.bootstrap_version` | Either the version in `env/setup.sh` and the version baked into the snapshot disagree, or the manifest field is absent, null, non-string, unreadable, holds no JSON document, sits under a non-object top level, holds more than one value, or yields an unrecognised extraction. | For a disagreement, re-paste `env/setup.sh` and rebuild. For a malformed field, re-run bootstrap. The malformed shapes are reported even when no expectation was read, because judging them needs none. |
| `NOTE manifest.bootstrap_version: ... actual present and empty` | The field exists and holds an empty string. Not counted into the exit status. | Read the `/home/user/bootstrap.log` lines printed above it — two where the log exists, one where it does not. A hand-run of `scripts/bootstrap.sh` produces this, and so does a pasted `env/setup.sh` whose export line lost its value. |
| `compare manifest.bootstrap_version ... -> no` | No expectation was read, so the version comparison did not run. | Act on the `FAIL expected version` line above it. |
| `FAIL manifest.bootstrap_version: expected a known internal state` | The script reached a branch it does not define. | Report it as a defect in `scripts/verify.sh`. |
| `FAIL live config dir agreement: ... actual could not tell` | `claude plugin list --json` exited non-zero, its output is not a JSON array, or the ids could not be read from it. The line names the exit status and the observed type. | Treat `FAIL plugin` as unresolved too. The manifest, payload and git checks remain valid. |
| `FAIL live config dir agreement: ... expected a readable object` | The live `settings.json` is absent, unreadable, holds more than one document, or its top level is not an object. The line above names which. | Re-run bootstrap. A malformed live file is a corrupt delivery, not a delivery that did not happen. |
| `FAIL live config dir agreement: ... plugins-listed=... enabledPlugins=...` | The resolved directory's `settings.json` and the running CLI disagree about whether plugins exist. | Rule out the `settings.json` side first: `command -v jq` is not `none`, the file exists, and it parses. The predicate reads `no` for a missing or malformed file as well as an absent key. |
| `FAIL manifest.config_dir` | The manifest names a directory other than the one resolved. | The manifest was hand-edited, the field is unreadable, or the config directory was copied after bootstrap wrote it. For a copy, re-run bootstrap against the directory now in use. |
| `FAIL payload: ... actual absent` | Either `config/CLAUDE.md` is missing from the repository being checked, or bootstrap never wrote the live `CLAUDE.md`. The two `test -f` lines above separate them. | For a missing delivered file, fix the tree. For a missing live file, read `/home/user/bootstrap.log`: bootstrap's own `test -f`/`cp` lines say which step did not run. |
| `FAIL payload: ... actual differs` | The live `CLAUDE.md` is not byte-identical to the delivered one. | Expected while the snapshot is frozen and `config/CLAUDE.md` has changed since, as with `FAIL manifest.commit`. Otherwise re-run bootstrap. |
| `FAIL payload: ... actual cmp exit=N` | `cmp` could not compare the two files. | Read the exit code. Both `test -f` lines above read `yes`, so the cause is neither file being absent. |
| `FAIL settings.<key>` | The live `settings.json` does not carry the value `config/settings.json` holds for that key. Every key the delivered file carries is checked. The two are compared as JSON values, so key order does not matter, and a live value holding more than the delivered one still carries it. | Expected while the snapshot is frozen and `config/settings.json` has changed since, as with `FAIL manifest.commit`. Otherwise re-run bootstrap: a failed `mv` in its step 4 leaves every delivered key absent from the live file. |
| `FAIL settings: expected a JSON object with at least one key` | `config/settings.json` is absent, unreadable, or carries no key. | Fix the tree. This is a repository fault, not a session fault. |
| `FAIL settings....: actual no expectation could be read` | That key could not be read from `config/settings.json`. | Fix the tree. This is a repository fault, not a session fault. |
| `FAIL settings....: ..., <state>` | The state ends the line and names the cause: `does not carry`, `absent from the live file`, `absent from the delivered file`, `live top level is ...`, `delivered top level is ...`, `live file holds N JSON documents`, `delivered file holds N JSON documents`, or `not determined` where `jq` could not run. | Read the state. A document count other than one, or a non-object top level, is a corrupt file rather than a delivery that did not happen. |
| `FAIL settings....: expected ... present in ...` | `config/settings.json` does not carry that key, or its top level is not an object. The `actual` value names which. | Fix the tree. This is a repository fault, not a session fault. |
| `FAIL PreToolUse attribution guard` | The first live `PreToolUse` command naming `attribution-guard.sh` did not exit 2 on a `gh pr create` body carrying the Claude Code footer. The state ends the line: `exit=N` for a command that ran, `exit=2 without <marker>` for one that exited 2 without the guard's own stderr marker, `no PreToolUse command in <path> references attribution-guard.sh (jq exit=N)`, or `sample input not built (jq exit=N)`. | Read the state. `no PreToolUse command` reads the same for a live `settings.json` that registers no command naming the guard and for one `jq` could not read; the `(jq exit=N)` suffix separates them, `0` for the first and non-zero for the second. On either, the snapshot predates the hook: re-paste `env/setup.sh` and rebuild. `exit=0` means the hook is registered and the guard is not at the path it names. `exit=2 without <marker>` means the registered command is broken shell, `bash -c` exiting 2 on a syntax error. |
| `FAIL config/plugins.tsv` | No file at that path under the repository being checked. | Read the `test -f` line above it. The deployed copy is absent, incomplete, or `HARNESS_DIR` names another tree. |
| `FAIL plugin: ... among the installed ids` | A plugin named in `config/plugins.tsv` is not among the ids `claude plugin list --json` reports. | Read the `claude plugin install ... -> exit=` line in `/home/user/bootstrap.log`, then re-run the install by hand for the current error. |
| `FAIL plugin: ... expected an id list` | No id list could be read, so the plugin could not be tested. | Act on the `FAIL live config dir agreement` line above it. |
| `FAIL git AUTHOR variables` / `FAIL git COMMITTER variables` | That role's `GIT_*_NAME` or `GIT_*_EMAIL` is unset or empty. The line above names which, and separates the two. | Set both in the environment variables panel. Nothing in this repository supplies an identity. |
| `FAIL git AUTHOR identity` / `FAIL git COMMITTER identity`, `... expected an identity of the form Name <email>` | `git var` returned nothing usable for that role. | Read the state on the line above. An empty `GIT_*_NAME` exits 128; a repository git will not read is reported as such. |
| `FAIL git AUTHOR identity` / `FAIL git COMMITTER identity`, `... from that role's GIT_*_NAME and GIT_*_EMAIL` | Git did not resolve that role to the pair the session was given. | Check for a `GIT_CONFIG_KEY_n` overlay or a repository-local `user.*`. |
| `FAIL git AUTHOR identity` / `FAIL git COMMITTER identity`, `... other than the harness default` | The identity is the harness's own, not the operator's. | The panel pair is absent or holds that address, so `git var` fell through to `/root/.gitconfig`. Set the four variables in the panel. |
| `FAIL git identity agreement` | Author and committer name different identities. | Set all four panel variables to one pair. |
| `compare GIT_AUTHOR_IDENT ... -> not run` | One role produced no usable identity, so the agreement test did not run. | Act on that role's `FAIL git ... identity` line above it. |
| `FAIL git commit.gpgsign` / `FAIL git tag.gpgsign` | The effective value inside the clone is not `false`. | Read as `actual [true]`, something re-enabled signing; `docs/environment.md` records what is known about signing here and what is not. Read as `unset`, bootstrap's write did not reach this session. |

In the session that first creates these files, verify fails on the missing
manifest. That is the correct result.

## Reading the session-start check

```
bash /opt/my-harness-wrapper/scripts/session-check.sh
```

The `SessionStart` hook runs it at every session start, and its output arrives
beside the first prompt. It exits 0 in every case.

It names whether this session built the snapshot or restored one, each
repository under `/home/user` with its branch and short HEAD, and `verify.sh`'s
result: every `FAIL` and `NOTE` line, or the `fail -> N` tally where there are
none, or, where it printed neither, its output lines prefixed `verify.sh |` up
to `SESSION_CHECK_OUT_LINE_CAP` of them. A `FAIL` line is decoded by the table
above.

`/home/user/session-check.log` holds every run's output, appended.

`config/CLAUDE.md` requires a session whose check reports a `FAIL` to name it in
its first reply.

## Before every commit

Hand-run `scripts/bootstrap.sh`, `scripts/verify.sh` and
`scripts/session-check.sh` before committing a change to them. Run
`scripts/test-attribution-guard.sh` before committing a change to
`scripts/attribution-guard.sh` or to the test script itself; it exits 0 only
where every case passes. `bash -n` is not
a gate here: it accepts invalid parameter expansion that fails at runtime.
`shellcheck` is not installed in this sandbox. Never execute `env/setup.sh`; run
`bash -n` on it, and exercise the branches a change touches by extracting them
into a scratch script.

Stage the change and invoke every applicable reviewer on the staged diff.
`config/CLAUDE.md`'s Harness section carries the table that decides when a round
ends and what to do, and travels to every session, so it is not restated here.

## Where a change belongs

| Change | Repository | File |
| --- | --- | --- |
| A rule governing every project | this one | `config/CLAUDE.md` |
| A setting or plugin for every session | this one | `config/settings.json`, `config/plugins.tsv` |
| A rule for one project only | that project | its own `CLAUDE.md` |
| A project's lint config, hooks or CI | that project | its own files |
