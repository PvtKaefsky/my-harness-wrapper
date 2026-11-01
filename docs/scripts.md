# Scripts

This file carries what each script does, and the facts behind the shape of each
step. `docs/runbook.md` carries how to run them and how to read their output.

## scripts/bootstrap.sh

Delivers `config/` into the session config directory. Run as root by
`env/setup.sh`.

It never sets `-e`. Every step logs its own predicate and observation and keeps
going. Every command that changes state outside this script, or produces a
value the manifest carries, reaches `fails`, with one split recorded under
step 7. The
diagnostic reads do not: `id`, the two `command -v` calls, the `test` and
`readlink` predicates, and step 5's pre-write probe. Step 1's `cd` counts itself
and leaves `SRC` empty, which later steps surface again when their own `test -f`
fails. Step 2 has a fourth case, in its own section.

The logged `fails` is the true count. The exit status is that count clamped to
255, an exit status wrapping at 256.

| Step | What it does |
| --- | --- |
| 1 | Resolves the repository root from the script's own location. |
| 2 | Creates `/root/.claude`, and symlinks `/home/user/.claude` to it where that path is absent. |
| 3 | Copies `config/CLAUDE.md` to `/root/.claude/CLAUDE.md`. |
| 4 | Merges `config/settings.json` into `/root/.claude/settings.json`. |
| 5 | Sets `commit.gpgsign` and `tag.gpgsign` to `false` globally, and the global `core.hooksPath` to `git-hooks/` in the clone. |
| 6 | Installs each plugin named in `config/plugins.tsv`, then runs `scripts/plugin-dependencies.sh` for it. |
| 7 | Writes `/root/.claude/.my-harness-wrapper.manifest.json`. |

### Step 2, the config directory

The symlink is created only where `/home/user/.claude` is absent. An existing
directory there, a symlink pointing elsewhere, and a dangling symlink are each
left untouched: the step repairs nothing it did not create.

The invariant is asserted separately, after that conditional and whether or not
it ran. Both paths go through `readlink -f` and the two results are compared; a
mismatch prints `-> no` and counts into `fails`.

The two `readlink -f` defaults differ, `unresolved-link` against
`unresolved-config`, so two unresolvable paths never compare equal and pass.
`test -d` is what separates a dangling symlink from a live one: `readlink -f`
prints the target path for both.

### Step 4, the settings file

Step 4 has three branches. Both files present: `jq -s '.[0] * .[1]'` merges the
source over the destination. Destination absent: the source is copied whole.
Source absent: `fails` is incremented.

Step 4 must precede step 6, which rewrites the same file at user scope.

`jq`'s `*` operator recurses only where both sides are objects, and otherwise
takes the right-hand value whole. Arrays are replaced rather than combined, at
any depth. Whatever `config/settings.json` holds at a path is what the merge
leaves there, so the merge cannot add to an array already present.

A destination key absent from the source survives. A nested object keeps the
keys the source omits. A sibling hook event survives. A delivered
`hooks.UserPromptSubmit` array leaves none of the entries already registered
there.

A delivered `hooks` array survives step 6's rewrite. That holds for a copied
destination. A merged file, a later CLI version and a differently shaped key
are not covered.

`mktemp` is counted, and an empty path counts as a failure too.

The temporary file is created beside the destination, not in `/tmp`, so the `mv`
is a same-filesystem rename and the destination is replaced whole or not at all.
A cross-filesystem `mv` writes into the destination path directly, and an
interruption partway leaves invalid JSON there rather than the unmerged file.

The temporary file is set to mode 644 before the rename, `mktemp` creating it
at mode 600 and a rename carrying the temporary file's permissions to the
destination. A failed `chmod` discards the temporary file instead of renaming
it, leaving the previous destination in place, so no path installs a file at
the wrong mode.

The `mv` that installs the merged file is counted. A `jq` that succeeds and an
`mv` that fails leave the destination unchanged and the merged file behind at
its `mktemp` path, and `fails` records the `mv`. The `rm -f` on the discard
branch is counted too, so a `jq` or `chmod` failure whose cleanup also fails
counts twice.

### Step 5, the signing keys

The two values are written globally, not per repository. The snapshot is reused,
and later sessions clone fresh repositories after this script has been skipped,
so only `/root/.gitconfig` reaches them.

Identity is not written here. A value written here does not survive the rewrite
of `/root/.gitconfig`, which `docs/environment.md` records under "Identity", and
`git var` reads a role's environment pair above any config file, so a
`user.name` or `user.email` written here cannot reach a role whose variable is
set.

Neither reason reaches a role the environment leaves unset, where the global
file would still hold what this step wrote. That role is what dropping the write
gives up, wherever nothing above that file supplies it. A repository-local
`user.*` and a `GIT_CONFIG_KEY_n` overlay both outrank that file.
`git config --get` never sees a role's environment pair, so it goes on
reporting whatever config resolves to, step 7's read included.

### Step 5, the hooks path

The step delivers `git-hooks/`, which "git-hooks/" below describes, as the
global `core.hooksPath`. It runs in this order:

1. Prints `test -x <clone>/git-hooks/commit-msg`.
2. Prints the prior global and system values, each with its read's exit status.
   A read exiting above 1 counts one failure.
3. Writes nothing where `git-hooks/commit-msg` is absent or not executable, or
   where either prior value holds a path other than the one it would write; it
   prints which, and counts one failure. A prior value equal to it is written again.
4. Otherwise runs `git config --global core.hooksPath <clone>/git-hooks` and
   counts a non-zero exit.

The value is written globally for the reason the signing keys are: later
sessions clone fresh repositories. A repository whose own config sets
`core.hooksPath` overrides it. The manifest's `core_hooks_path` records the
value written, and is empty where the step wrote nothing.

### Step 6, the plugins

The CLI owns `extraKnownMarketplaces` and `enabledPlugins` at user scope.
Neither key is ever hand-written.

After each plugin's install, whatever its exit status, the step runs
`bash "$SRC/scripts/plugin-dependencies.sh" claude <plugin_id>` and counts a
non-zero exit as one failure.

### Step 7, the manifest

`git_user_email` records what `git config --get user.email` answers inside the
clone. Step 5 does not write that key, so the value is whatever config resolves
to, and may be nothing at all. It need not be the email git writes, because
`git var` resolves a role whose email variable is set from that variable
instead. The field is kept for the record, not as evidence of what took effect.
`scripts/verify.sh` prints it without asserting it.

`core_hooks_path` is the value step 5 wrote, or empty.

The manifest is written the same way step 4 writes the settings file: to a
temporary file beside it, set to mode 644, then renamed. A failed write leaves
the previous manifest intact.

The `test -f` line that follows reports that a manifest is present, not that
this run wrote it. A run whose `jq`, `chmod` or `mv` failed leaves the previous
manifest in place, and the line reads `yes` for each. The exit lines above it
and the `fails` count separate the two.

`rev-parse` and the `date -u` that fills `installed_at` count any non-zero exit
into `fails`. `git config --get user.email` counts only exits above 1. Exit 1 is
git's key-not-found, which is a state this field admits, and a repository git
cannot read is already counted by the `rev-parse` above it.

## scripts/install-local.sh

Delivers `config/` into a local Claude config directory from a deployed copy of
`main`. Run by the user from any checkout, in Git Bash on Windows and bash
elsewhere. It carries bootstrap's steps with the same semantics, minus
the `/home/user/.claude` symlink.

It never sets `-e`. Every step prints its predicate and observed value. Its
output goes to the terminal and to `.my-harness-wrapper.install.log` in the
config directory, which each run creates under `umask 077`, runs `chmod 600`
on, then rewrites, the log carrying prior hook commands. `docs/runbook.md`
carries the mode observed per platform. Every command that changes state, or
produces a value the manifest carries, counts into `fails`. A failed write of
the log counts too. The exit status is `fails`, clamped to 255.

The run's last block is one brace group, so bash has parsed the whole file
before step 3 can rewrite it in a deployed copy the script runs from.

| Step | What it does |
| --- | --- |
| 1 | Resolves the invoking checkout from the script's own location, with `CDPATH` cleared, and the config directory as `${CLAUDE_CONFIG_DIR-$HOME/.claude}`, converted with `cygpath -u` where `cygpath` exists. A path that is not absolute stops the run with exit 1 and no log. |
| 2 | Creates the config directory, then checks `jq` and `git`. A failing tool ends the run before step 3. |
| 3 | Clones or refreshes the deployed copy, `my-harness-wrapper` in the config directory. A failure ends the run. |
| 4 | Copies `config/CLAUDE.md` from the deployed copy to `CLAUDE.md` there, first printing `test -f` or `cmp -s` for the file it replaces, and keeping a differing one as `CLAUDE.md.pre-harness` where no such copy exists. |
| 5 | Merges the deployed copy's `config/settings.json` into `settings.json` there, then sets `env.HARNESS_DIR` to the deployed copy. A non-empty `settings.json` is first kept as `settings.json.pre-harness` where no such copy exists. |
| 6 | Sets `commit.gpgsign` and `tag.gpgsign` to `false` globally, printing each prior value and its read's exit status, then the global `core.hooksPath` to the deployed copy's `git-hooks/`. |
| 7 | Installs each plugin named in the deployed copy's `config/plugins.tsv` and runs the deployed copy's `scripts/plugin-dependencies.sh` for it, then prints how many rows carried a `plugin_id`. |
| 8 | Writes `.my-harness-wrapper.manifest.json` there. |

### Step 2, the prerequisites

| Tool | Present where |
| --- | --- |
| `jq` | `command -v jq` resolves it, and `jq -n 1` prints `1`, a trailing carriage return removed |
| `git` | `command -v git` resolves it, and `git --version` exits 0 |

Each check prints its predicate and value lines, then
`prerequisites failing ->` names the tools that failed, or `none`. Each failing
tool counts one failure. Where any fails, the step prints
`delivery -> stopped, not written:` with the deployed copy, `CLAUDE.md`,
`settings.json`, the global git config, the plugins and the manifest, and the
run ends. By then the run has written only the config directory, where it was
absent, and the install log.

`jq.exe` 1.8.2 prints `1` followed by CRLF, so the carriage return is removed
before the comparison. The `jq` check reads stdout only; its exit status is
printed and not compared.

### Step 3, the deployed copy

The branch is `main`. The clone URL is `HARNESS_REPO_URL` where
it is set and non-empty, and the default URL `env/setup.sh` carries otherwise.
The `HARNESS_REPO_URL ->` line names which, as the init script's does. A URL
beginning with `-` is refused. The step unsets `GIT_DIR`, `GIT_WORK_TREE`,
`GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_COMMON_DIR` and
`GIT_ALTERNATE_OBJECT_DIRECTORIES` first, so `git -C` acts on the deployed copy,
and prints which of them were set.

| State of the deployed copy | What runs |
| --- | --- |
| Absent | `git clone -q -c harness.installer=install-local --depth 1 --branch main`, which writes the marker into the clone's local config in the same step |
| A directory, not a symlink, holding a `.git` directory, at the top level of its work tree, with `harness.installer` set to `install-local` in its local config | `remote set-url origin`, `fetch -q --depth 1` of the branch into `refs/remotes/origin/main`, `checkout -f -B main` at that ref, and `clean -ffdx` |
| Anything else: a symlink, a linked worktree, a plain directory, a directory inside another work tree, or a clone the installer did not make | Nothing; counted as a failure |

The installer owns the copy it marked: a refresh discards every change and
untracked file in it. The refresh prints `HEAD` before it runs.

After either path the step prints the copy's `HEAD`, its remote ref, its branch,
whether its local `remote.origin.url` equals the clone URL, its
`status --porcelain` entry count, the
count of index entries marked skip-worktree or assume-unchanged, whether
`config/CLAUDE.md`, `config/settings.json`, `config/plugins.tsv` and
`env/setup.sh` are tracked, and `log -1`. A failed read prints the first line of
git's error. The copy is ready where `HEAD` equals the remote ref, the branch is
`main`, `remote.origin.url` equals the clone URL, the status has
no entries, no index entry is marked, and the four files are tracked. The stored
value is compared, not the `url.<base>.insteadOf` rewrite `remote get-url`
prints, so a rewrite in the user's git config does not fail the check. A clone
URL given as a relative path is stored absolute and fails it.

Git for Windows stores a clone source given as `/d/...` as `D:/...`, and one
under `/tmp` as the `%TEMP%` path, often in 8.3 short form. Where `cygpath`
exists, `url_canon` therefore compares a URL beginning with `/`, `X:/` or `X:\`
in the canonical form `scripts/verify.sh`'s `canon_path` uses: `cygpath -u`,
`readlink -f`, `cygpath -m -l`, ASCII letters lowercased. Every other URL, and
every URL where `cygpath` is absent, is compared exactly. The limits of
`canon_path` under "Comparing paths" apply. A side whose last conversion fails
is compared unconverted, and so reads `no`. The line prints `yes` or `no` only,
never either URL. The check confirms the form git stored the clone URL in. It
does not authenticate the origin: a refresh sets the URL before it fetches.

Where a command fails, or the copy is not ready, the step
counts one failure, prints `delivery -> stopped`, and the run ends before steps
4 to 8. `CLAUDE.md`, `settings.json` and the manifest stay as they were. The
deployed copy does not: a refresh that failed after its `fetch` may have moved
it, and the hooks of the previous install run its scripts from then on.

During a refresh, `checkout -f` and `clean` rewrite the deployed copy in place.
A hook firing in a running session in that window can find a script absent, and
its command then exits 0 without running it.

The clone URL is stored in the copy's `.git/config`, and git's own messages,
which reach the log, can carry it. A URL carrying a token keeps it there; a
credential helper keeps it out.

Steps 4 to 8 read only the deployed copy, apart from step 8's `user.email`,
which is read in the invoking checkout as before. The invoking checkout is
printed on the `SRC ->` line.

### Step 5, the settings file

The merge is `jq -s '.[0] * .[1] * {env: {HARNESS_DIR: $h}}'`, the live file
first. A key the live file holds and the delivered file does not is kept; a key
both hold takes the delivered value, recursing into objects as bootstrap's step
4 does. An array is replaced whole, so a live `hooks.<event>` array for an event
the delivered file names is replaced by the delivered one. Before the merge the
step prints the delivered top-level keys whose live value differs, and the live
value of each `hooks.<event>` the delivered file
names, or `"absent"`. Where the live file is absent or empty, the delivered file is
merged over an empty object.

The program reads every document in both files and fails unless it read
exactly two, so a live file holding more than one document fails the step
instead of displacing the delivered file.

The result goes to a temporary file beside the destination and is renamed over
it, as in bootstrap. The temporary file takes the destination's existing mode,
read with `stat -c %a` or, where that fails, `stat -f %Lp`, and 600 where no
destination exists or no mode is read; the `mode for` line prints it. A failed
`jq`, `chmod` or `mv` leaves the previous file in place.

On Windows, Git Bash converts a `/d/...` path argument to `D:/...` when it
starts the native `jq.exe`, so `env.HARNESS_DIR`, `config_dir` and
`local_checkout` are stored in that form. Git Bash reads either form as the same
path. `jq.exe` also writes CRLF line endings, which every JSON reader here
accepts.

`env.HARNESS_DIR` is the only key the installer writes that
`config/settings.json` does not carry. The CLI sets each `env` key in the
environment of every hook and tool process, so the hook commands resolve the
scripts in the deployed copy. The line after the merge prints the value read
back.

### Step 6, the hooks path

The step runs as bootstrap's step 5 under "Step 5, the hooks path", with three
differences. The value written is the deployed copy's `git-hooks/` converted
with `cygpath -m` where `cygpath` exists, so git for Windows reads a
`C:/...` path; the `cygpath -m` line prints the conversion, and a failed one
writes nothing and counts one failure. A prior value is compared with that
value through `url_canon`, so another spelling of the same directory counts as
equal. Deleting the deployed copy without unsetting the value leaves it naming a
deleted directory, which `docs/runbook.md` covers under "Removing a local
install".

The value applies to every repository on the machine, the user's own commits
included.

### Step 7, the plugins

The CLI is taken from the first of three sources that yields one: `command -v
claude`, `CLAUDE_CODE_EXECPATH` where it names a file, and the highest-sorting
`claude.exe` under `$LOCALAPPDATA/Claude-Data/claude_*/claude-code/*/*/`, by
`sort -V` on the full path. Claude Code sets `CLAUDE_CODE_EXECPATH` in the
processes it starts. The desktop app keeps its bundled CLI under
`$LOCALAPPDATA` and puts none on `PATH`. Where no source yields one, each
plugin's line names the two commands to run instead and counts one failure.

After each plugin's install, whatever its exit status, the step runs
`bash "$DEPLOY/scripts/plugin-dependencies.sh" "$CLI" <plugin_id>` with the CLI
it found, and counts a non-zero exit as one failure. Where no CLI is found, the
dependency step is not run and counts one failure of its own.

### Step 8, the manifest

The fields are bootstrap's, plus `local_checkout`, the deployed copy's path.
`core_hooks_path` is the value step 6 wrote, or empty.
`bootstrap_version` is read from the `export BOOTSTRAP_VERSION=` line of
`env/setup.sh` in the deployed copy, with the shapes `scripts/verify.sh` rejects
counted as a failure and written empty. `config_dir` is the converted path from
step 1. `scripts/session-check.sh` takes the local branch on a non-empty
`local_checkout`.

## scripts/plugin-dependencies.sh

Installs a delivered plugin's npm dependencies where its install left any
unresolved. Run once per plugin, after that plugin's install, by
`scripts/bootstrap.sh` step 6 and `scripts/install-local.sh` step 7. Both run it
as `bash <harness>/scripts/plugin-dependencies.sh <CLI> <plugin_id>`, so the two
loops share one implementation.

| Argument | Value |
| --- | --- |
| 1 | The CLI to run: `claude` in bootstrap, the CLI `scripts/install-local.sh` step 7 found locally. |
| 2 | The `plugin_id` from `config/plugins.tsv`. |

| Step | What it does |
| --- | --- |
| 1 | Runs `<CLI> plugin list --json` and reads the distinct `installPath` values of the entries whose `id` is the plugin id. Exactly one passes. |
| 2 | Converts that path with `cygpath -u` where `cygpath` exists, since the Windows CLI reports it in the `C:\...` form. The result must be absolute and name a directory. |
| 3 | Reads the keys of `dependencies` in `package.json` there. An absent `package.json` declares none: the step prints `npm ci in <path> -> not run, no package.json` and exits 0. An absent `dependencies` key declares none too. Each name must match the npm name form, an optional `@scope/` and a name, neither beginning with `.`, which keeps each tested path inside `node_modules`. |
| 4 | Tests `node_modules/<name>/package.json` under that path for each name, one `test -f` line each, then prints the unresolved names or `none`. |
| 5 | Where every name resolves, prints `npm ci in <path> -> not run, every declared dependency resolves` and exits 0. |
| 6 | Otherwise prints `command -v npm`, runs `npm ci --omit=dev --ignore-scripts --no-audit --no-fund` in that path, prints its exit status, and repeats step 4. |

It exits 0 where every declared name resolves at the end, and 1 otherwise: an
empty argument, a failed plugin list, an `installPath` count other than one, a
path that is not absolute or not a directory, an unreadable `package.json`, a
name outside the npm form, an absent `npm`, a failed `npm ci`, or a name still
unresolved after it. Each case prints its predicate line before the exit. The
caller counts exit 1 as one failure and goes on to the next plugin.

`npm ci` installs the versions `package-lock.json` pins, and fails where that
file is absent or disagrees with `package.json`. `--omit=dev` leaves out
`devDependencies`. `--ignore-scripts` runs no lifecycle script of the plugin or
of any dependency. `npm ci` removes an existing `node_modules` before it
installs. The names read in step 3 only build test paths; npm reads the
lockfile.

The test is the presence of `node_modules/<name>/package.json`. It does not
separate a dependency npm installed from one put there by other means, and it
reads neither the installed version nor the dependency's own dependencies.

The step exists because the CLI installs `ecc@ecc` 2.2.3 without its npm
dependencies; `docs/environment.md` records the observations under "ECC's npm
dependencies". `docs/runbook.md` carries when the step can be removed.

## git-hooks/

The directory the global `core.hooksPath` names. It holds one file per hook name
git looks up in that directory, and `lib/`.

| Hook names | Count |
| --- | --- |
| `applypatch-msg`, `pre-applypatch`, `post-applypatch`, `pre-commit`, `pre-merge-commit`, `prepare-commit-msg`, `commit-msg`, `post-commit`, `pre-rebase`, `post-checkout`, `post-merge`, `pre-push`, `pre-receive`, `update`, `proc-receive`, `post-receive`, `post-update`, `reference-transaction`, `push-to-checkout`, `pre-auto-gc`, `post-rewrite`, `sendemail-validate`, `p4-changelist`, `p4-prepare-changelist`, `p4-post-changelist`, `p4-pre-submit`, `post-index-change` | 27 |

`fsmonitor-watchman` is absent: git runs it from the path `core.fsmonitor`
names, not by name from the hooks directory.

Every hook file is the same three lines. It sets `HOOK_DIR` to its own directory,
taken from `$0`, and sources `lib/dispatch.sh`; where that file cannot be read
it prints so and exits 1. The hooks read no `HARNESS_DIR` and run no `jq`, so a
shell the user starts runs them as a session does.

| File | Role |
| --- | --- |
| `lib/dispatch.sh` | Runs the message check for `commit-msg`, then forwards every hook to the repository's own hook. |
| `lib/attribution.ere` | The attribution pattern, one line, read by `lib/dispatch.sh` and by `scripts/attribution-guard.sh`. |

| Hook | What runs |
| --- | --- |
| `commit-msg` | The message check; where it passes, forwarding. |
| `push-to-checkout` | Forwarding; where the repository has no such hook, git's default for a push to a checked-out branch under `receive.denyCurrentBranch=updateInstead`. |
| `proc-receive` | Forwarding; where the repository has no such hook, exit 1 with a line naming the path looked up. |
| Every other name | Forwarding; where the repository has no such hook, exit 0. |

The two defaults exist because the presence of those two hooks changes what git
does. The `push-to-checkout` default runs `update-index -q --ignore-submodules
--refresh`, `diff-files --quiet --ignore-submodules`, `diff-index --quiet
--cached --ignore-submodules` against `HEAD`, or the empty tree where `HEAD` is
unborn, and `read-tree -u -m <new commit>`, refusing with git's own message at
the first that fails.

### The message check

The pattern is read from `lib/attribution.ere`, one trailing carriage return
removed. A file that is absent, empty or more than one line refuses the commit
with a line saying the message was not checked.

| Alternative, matched case-insensitively as an ERE | Matches |
| --- | --- |
| `Generated (with\|by) \[?Claude Code` | The Claude Code footer. |
| `claude\.ai/code/session_` | A session link, the URL of a `Claude-Session` trailer among them. |
| `^[[:space:]]*Co-Authored-By:([^<]*[^[:alnum:]_<-])?Claude([^[:alnum:]_]\|$)` | A `Co-Authored-By:` line whose name, before any `<`, carries the word `Claude` not preceded by a hyphen. |
| `^[[:space:]]*Co-Authored-By:.*@([[:alnum:]-]+\.)*anthropic\.com([^[:alnum:].-]\|$)` | A `Co-Authored-By:` line with an `anthropic.com` address. |
| `^[[:space:]]*Claude-Session:` | Any `Claude-Session:` line. |

A `Co-Authored-By:` line naming anyone else passes, a hyphenated name such as
`Jean-Claude` among them. The hook runs for the user's
own commits too.

The message is scanned as git will record it. Comment lines and everything from
the scissors line on are dropped where git's cleanup would drop them, and kept
otherwise:

| `commit.cleanup` | `GIT_EDITOR` in the hook | Dropped |
| --- | --- | --- |
| `strip` | any | comment lines, and the scissors line and all after it |
| `whitespace`, `verbatim` | any | nothing |
| unset, `default`, `scissors` or another value | `:` | nothing |
| `scissors` | anything else | the scissors line and all after it |
| unset, `default` or another value | anything else | comment lines, and the scissors line and all after it |

Git sets `GIT_EDITOR=:` in the hook's environment where no editor runs, as for
`git commit -m` or `-F`. A comment line begins with `core.commentString`, or
`core.commentChar`, whichever config sets last, `#` by default. The scissors
line is that string followed by
` ------------------------ >8 ------------------------`. Where the value is
`auto`, a line beginning with any of `#;@!$%^&|:` counts as a comment.

| Outcome | Exit | Output on stderr |
| --- | --- | --- |
| A line matched | 1 | `harness commit-msg: matched line -> <line>`, the line through the control-byte replacement `scripts/verify.sh` uses, then `harness commit-msg: remove that attribution line from the commit message, then commit again.` |
| The pattern file unusable, `awk` unable to read the message, or `grep` exiting above 1 | 1 | `harness commit-msg: <cause>` |
| Nothing matched | the forwarded hook's | the forwarded hook's |

The hook rejects; it never edits the message. A rejected commit does not reach
the repository's own `commit-msg`.

`git merge` runs `commit-msg` on the merge message, so a merge message carrying
the pattern is rejected.

### Forwarding

The repository's own hook is `<hooks dir>/<name>`, where `<hooks dir>` is the
directory git would run hooks from without the harness. `hook_configured_dir`
reads every `core.hooksPath` value with one git process,
`git config --show-scope --type=path --get-all core.hooksPath`, and takes the
last value of the worktree, local, global and system scopes, in that order. It
skips an empty value and a value naming this directory by `test -ef`, and
returns the first other value, resolved against the hook's working directory
where it is relative. Git resolves a relative `core.hooksPath` against the
directory it starts the hook in, and `--type=path` expands a leading `~`. The
command scope is never taken: it holds a `GIT_CONFIG_KEY_n` overlay or a
`git -c` value. Exit 1 from that command means no scope sets a value; any other
non-zero exit refuses with a line naming it.

| Lookup result | `<hooks dir>` |
| --- | --- |
| A worktree, local, global or system value naming another directory | That value |
| No such value | `<common dir>/hooks` |

`hook_common_dir` finds the git dir in the shell, starting no process, by the
first row that applies; it looks only at the working directory, never a parent:

| Row | Git dir |
| --- | --- |
| `GIT_COMMON_DIR` set | None; the common dir is `GIT_COMMON_DIR` |
| `GIT_DIR` set | `GIT_DIR` |
| A `.git` directory in the working directory, holding `HEAD`, `objects/` and `refs/` | That directory |
| A `.git` file in the working directory, its first line `gitdir: <path>` | `<path>`, relative to the working directory unless absolute |
| The working directory itself holding `HEAD`, `objects/` and `refs/` | The working directory, as in a bare repository |

The common dir is then the first line of `<git dir>/commondir`, relative to the
git dir unless absolute, where that file exists, and the git dir otherwise. A
trailing carriage return is removed from the `.git` file's line, and trailing
whitespace from the `commondir` line. Where no row applies, a `.git` directory
lacks those entries, or a `.git` file or `commondir` cannot be read or holds no
path, the common dir is `git rev-parse --git-common-dir`; where that fails too,
the hook exits 1 with a line saying the repository's hook was not looked up.

githooks(5) states that git starts a hook in the top of the working tree, or in
the git dir of a bare repository. `git init` and `git clone` run
`reference-transaction` with `GIT_DIR` set before the new repository answers
`rev-parse`, so the `GIT_DIR` row decides there. A hook run by hand from a
subdirectory finds no row and takes the `rev-parse` fallback.

A global value naming this directory, as the cloud's is, is skipped, so the
lookup reaches the next scope or `<common dir>/hooks`. In a linked worktree the
common dir is the main repository's git directory; in a bare repository
receiving a push it is the repository itself, as git uses for `hooks/` without
the harness.

| State of `<hooks dir>/<name>` | Result |
| --- | --- |
| Absent | The default for that hook name, above. |
| `<hooks dir>` is this directory, or the file is the running hook file, by `test -ef` | Not run; the default. |
| A file, not executable | Not run; the line `harness <name>: <path> was not run, it is not executable.`, then the default. |
| An executable file | Run by `exec` with the same arguments, standard input, environment and working directory; its exit status is the hook's. |

Git also skips a non-executable hook. Git for Windows counts a file beginning
with `#!` as executable.

### File mode and line endings

Every hook file is committed with mode `100755`, set on Windows with
`git update-index --chmod=+x`. `lib/` is not a hook and stays `100644`.

A checkout under `core.autocrlf=true` writes the hook files with CRLF line
endings. Git for Windows runs them.

### Accepted gaps

| Path | Effect |
| --- | --- |
| A repository whose own config sets `core.hooksPath` | That value overrides the global one, so neither the message check nor forwarding runs there. `scripts/session-check.sh` prints the effective value with its origin. |
| `git commit --no-verify`, `git merge --no-verify` | Git skips `commit-msg`. |
| `git rebase`, `git cherry-pick` | Git runs no `commit-msg`, so a message they carry over is not checked. |
| `git commit --cleanup=<mode>` | The flag does not reach the hook; the table above decides from config and `GIT_EDITOR`. With an editor and no `commit.cleanup`, `--cleanup=whitespace` or `--cleanup=scissors` records comment lines the hook dropped, so an attribution line beginning with the comment character passes. With `commit.cleanup=whitespace` or `verbatim`, a `git commit -v` diff below the scissors line is scanned although git cuts it. |
| `core.commentChar=auto` | A line beginning with any candidate character is dropped as a comment where cleanup drops comments. |
| `git am` | Git runs `applypatch-msg`, which only forwards, and no `commit-msg`. |
| `git commit-tree` and other plumbing | Git runs no hook. |
| A commit made on GitHub by a tool outside the attribution guard's `PreToolUse` matcher | No local hook runs. |
| A commit made by a program that does not run git hooks | No hook runs. |
| A hook name a later git version adds | No file carries it, so git finds none and the repository's own hook of that name does not run. |
| A tool that installs hooks into the directory `core.hooksPath` names | It finds the harness files there. `git lfs install --local` 3.7.0 printed `Hook already exists: pre-push` and installed nothing, so a repository without its own LFS hooks gets none, and its pushes do not upload LFS objects through `pre-push`. Placing LFS's hooks in `<common dir>/hooks` by hand restores them through forwarding; `git lfs update --manual` 3.7.0 prints their contents, and names the directory `core.hooksPath` names as the place to add them, which is the deployed copy. `--force`, which git-lfs suggests, is the step to avoid: the forced hook install row sets out its effect. |
| A forced hook install, such as `git lfs install --force` or `git lfs update --force` | It overwrites the harness files of those hook names in the deployed copy, so in every repository those names run the tool's hooks and forward to none, and each repository's own hooks of those names stop running. `git lfs install --local --force` 3.7.0 replaced `pre-push`, `post-checkout`, `post-commit` and `post-merge`, and left `commit-msg`, so the attribution check kept working. `scripts/verify.sh` then reports `FAIL deployed copy changes` naming the files. Locally, re-running `scripts/install-local.sh` restores them; in the cloud, `git -C /opt/my-harness-wrapper checkout -- git-hooks` does. |
| A tool that refuses to install hooks while `core.hooksPath` is set, such as `pre-commit install` | It refuses in every repository. |

Every hook git runs starts bash. Forwarding starts one git process, the
`core.hooksPath` lookup, and a second where the `rev-parse` fallback above runs.
One commit and one checkout ran 13 `reference-transaction` hooks on Git for
Windows 2.51.0.

| Git for Windows 2.51.0, one repository | `git commit --allow-empty` | `git checkout` of another branch |
| --- | --- | --- |
| No `core.hooksPath` | about 80 ms | about 60 ms |
| `git-hooks/`, the common dir from `git rev-parse` | about 800 ms | about 680 ms |
| `git-hooks/`, the common dir from `hook_common_dir` | about 450 ms | about 320 ms |

One hook run alone took about 47 ms with `hook_common_dir` and about 83 ms with
`git rev-parse`; `bash -c :` alone took about 41 ms. Those runs predate the
`core.hooksPath` lookup.

With the lookup, measured on Git for Windows 2.56.0 on one Windows 11 machine,
each value the mean of 20 runs for a single command and of 10 runs for a commit
or checkout:

| Command | Time |
| --- | --- |
| `bash -c :` | about 146 ms |
| `git config --show-scope --type=path --get-all core.hooksPath` | about 156 ms |
| `reference-transaction prepared`, the hooks before the lookup | about 158 ms |
| `reference-transaction prepared`, the hooks with the lookup | about 337 ms |
| `git commit --allow-empty`: no hooks, the hooks before the lookup, the hooks with the lookup | about 534 ms, 2295 ms, 3473 ms |
| `git checkout` of another branch: no hooks, the hooks before the lookup, the hooks with the lookup | about 412 ms, 2162 ms, 3519 ms |

That machine ran `bash -c :` in about 146 ms against about 41 ms in the runs
above, so each table compares only within itself. The lookup adds about one git
process to each hook run.

## How the hook commands resolve the harness directory

The `PreToolUse`, `PostToolUse` and `SessionStart` commands in
`config/settings.json` set `h=${HARNESS_DIR:-/opt/my-harness-wrapper}` and run
the script under `$h`. A cloud session's hook processes carry no `HARNESS_DIR`,
so `h` is the cloud clone. A local install's `settings.json` carries
`env.HARNESS_DIR`, so `h` is the deployed copy. The committed file is one text
for both targets.

The commands use only POSIX parameter expansion, `[ -f ]` and double quotes,
which the Linux hook shell and Git Bash both run. A deployed copy path carrying
a space or non-ASCII characters is passed whole, `$h` being quoted. Each command
prints nothing and exits 0 where the script is absent from `$h`, except the
`SessionStart` command, which prints `test -f $h/scripts/session-check.sh -> no`.

Claude Code on Windows runs a hook command through Git Bash. Four backslashes
inside double quotes in a command reach the program it runs as one, where bash
alone gives two. None of the three commands carries a backslash. The
`UserPromptSubmit` command's one backslash, in `'\''`, reaches bash intact.

## scripts/verify.sh

Run inside a session, by hand. Reports what bootstrap left behind, and where the
session has drifted from the repository. Not run at boot.

`docs/runbook.md` decodes every `FAIL` and `NOTE` line it emits.

### The repository under test

`REPO` reads `${HARNESS_DIR:-/opt/my-harness-wrapper}`, the copy the init
script cloned. That copy is the reference, not the script's own location: a
hand-run from an attached checkout must still report on what was delivered.
A path derived from `${BASH_SOURCE[0]}` would report clean for a stale or absent
deployment. `scripts/bootstrap.sh` derives its own `SRC` instead, because it
must read the tree it ships with.

`HARNESS_DIR` names another tree for a hand-run. It is read with `${x:-y}`, so
a set-but-empty value falls back to the default rather than emptying every
path built from it.

### sanitize

Observed values are interpolated into lines an operator reads on a terminal. A
value carrying ESC, CR or BS can erase or rewrite the line it sits on, the
script's own `FAIL` lines included.

`sanitize` turns newlines into spaces, and other C0 controls and DEL into `?`.
Characters are replaced rather than deleted, so the observation is not silently
altered. The range is C0 plus DEL only, because `tr -c '[:print:]'` would mangle
multi-byte UTF-8. Both `tr` calls run under `LC_ALL=C`, so those byte ranges
mean what they say.

These values pass through it:

| Source | Values |
| --- | --- |
| git | the contrast `user.email`, each `git var` ident and the pair it is compared against, each `*.gpgsign` read, the `core.hooksPath` read and its canonical form, each hook-check commit's stderr line, the `status --porcelain` entries, git's first stderr line from that status, the top-level path, and the branch |
| `env/setup.sh` | the matched `export` lines, and an export value outside `[0-9A-Za-z._-]` |
| the settings files | the delivered key list, both settings probes, the carrying state, and the live `env.HARNESS_DIR` |
| the hook commands | each guard check's stderr |
| the CLI | the plugin id list, and each `installPath` and the path converted from it |
| a plugin's `package.json` | a dependency name outside the npm name form |
| the environment | `HARNESS_ASSIGNEE`, and a `GIT_*_EMAIL` value that fails the address form |

A version value inside `[0-9A-Za-z._-]` needs no pass, holding no control byte
by construction. Every other printed value goes out without passing through it,
some git output among them. That is a known gap, not a finding that the others
are safe.

### Resolving the config directory

The script resolves the directory Claude Code actually uses, rather than
searching a fixed list of candidate homes. A config directory outside such a
list would report clean.

`CLAUDE_CONFIG_DIR` is read with the colon-less default, because the CLI treats
a set-but-empty value as a value.

Where `cygpath` exists, the resolved directory is converted with `cygpath -u`
before the absolute-path gate, and the conversion is printed. A hook process the
Windows CLI starts receives `CLAUDE_CONFIG_DIR` in the `C:/...` form, which the
gate would reject. A failed or empty conversion keeps the original value.
Without `cygpath` no line is printed.

### Comparing paths

Every path comparison passes both sides through `canon_path`. Where `cygpath`
exists, it converts the path with `cygpath -u`, resolves it with `readlink -f`,
converts the result with `cygpath -m -l`, and lowercases ASCII letters; the
printed predicate names those steps. Where `cygpath` is absent, it is
`readlink -f` alone, compared case-sensitively.

| Form of one directory | Canonical form |
| --- | --- |
| `C:/Users/<long name>/...`, `/c/Users/<long name>/...` | `c:/users/<long name>/...` |
| An 8.3 short name, `C:/Users/88DF~1/...` or `/c/Users/88DF~1/...` | the long form, expanded by `cygpath -l` |
| Git Bash's `/tmp/...` mount | the long form of `%TEMP%\...` |

`readlink -f` does not expand 8.3 short names, and `cygpath -u` maps a
`%TEMP%` path to `/tmp`, so without the last step those forms of one directory
compare unequal. Non-ASCII letters are compared case-sensitively: `tr` runs
under `LC_ALL=C`. A side that does not resolve yields nothing, and each
comparison keeps its own differing defaults. The `cygpath` steps take `--`
before the path. The printed canonical values pass through `sanitize`.

| Limit | Effect |
| --- | --- |
| `cygpath -l` expands a short name only in a path that exists | A missing last component keeps its 8.3 form, so a missing directory compares unequal to its long form. |
| ASCII case is folded on every Windows path | Two directories differing only in ASCII case, in an NTFS directory set case-sensitive, compare equal. |
| A relative `HARNESS_DIR` or `env.HARNESS_DIR` | It resolves against the working directory `scripts/verify.sh` runs in, as before canonicalization. |

The resolution runs ahead of the `claude` calls. The CLI honours a relative
`CLAUDE_CONFIG_DIR` by creating that directory under the operator's working
directory, so invoking it before this gate has a side effect on a bad value.

### The config-directory checks

Two checks assert something about the resolved directory.

`FAIL live config dir agreement` compares the live CLI's plugin state against
that directory's own `settings.json`. The CLI is the witness, that file being a
snapshot artifact that cannot contradict the resolution the script just made.

The settings side reports four states rather than a boolean: the key present,
the key absent, a top level that is not an object, and a file that is absent,
unreadable or holds a count of documents other than one. Only the first two
are compared; the rest fail as their own state.

`FAIL manifest.config_dir` compares the resolved directory against
`manifest.config_dir`, both through `canon_path`. Where `cygpath` exists the
manifest value is first converted with `cygpath -u`, since the local installer
stores it in the `C:/...` form, and the printed line shows both. Its two defaults,
`unresolved-live` and `unresolved-manifest`, differ on purpose, so an
unresolvable live directory and an unreadable manifest value never compare
equal and pass.

A non-zero CLI exit yields `unknown` rather than a guess, because a default
either way is a value manufactured by a failure.

### The plugin checks

Plugin state is read from `claude plugin list --json`, not from the command's
human-readable output, which a wording, format or localisation change moves.

The CLI is found the way `scripts/install-local.sh`'s step 7 finds it, and the
`claude CLI ->` line names it and its source. Where none is found, the list is
not run and its exit reads 127, which gives `CLI_PLUGINS=unknown`.

Three states are separated. A non-zero exit, output whose top level is not an
array, and a failure extracting the ids from a well-typed array all give
`CLI_PLUGINS=unknown`; an array with no ids gives `no`; an array with ids gives
`yes`. `unknown` is a `FAIL` in its own right rather than
a guess either way, and it also fails each per-plugin check rather than letting
an untestable id pass.

The per-plugin test compares whole ids, not substrings, so an id that is a
prefix of an installed one does not match.

For each `config/plugins.tsv` plugin found in the list, `plugin_deps_check`
reads its `installPath` from the same `claude plugin list --json` output,
converts it with `cygpath -u` where `cygpath` exists, and tests
`node_modules/<name>/package.json` there for each name in `package.json`'s
`dependencies`. Each unresolved name is its own `FAIL`. An `installPath` count
other than one, a path that is not absolute or not a directory, an unreadable
`package.json` and a name outside the npm name form are each a `FAIL` too. An
absent `package.json` declares no dependencies and is not one. The predicate is
the one `scripts/plugin-dependencies.sh` tests, with the same limits.

An absent `config/plugins.tsv` is a `FAIL`, not a skipped check. Reading no
rows and having no file to read produce different output, so the check's
silence and its failure are never the same line.

`/home/user/bootstrap.log` records an install, never the current
`claude plugin list`, so it cannot witness what these checks assert. In a
restored session it is also an artifact of a different container.

### The expected version

`docs/runbook.md`, under "The version line", carries where the expectation is
read from and every line shape the read rejects.

Trailing blanks are trimmed with `[!$' \t']` rather than `[:blank:]`, which is
locale-dependent: under `C.UTF-8` `[:blank:]` also trims U+3000, building an
expectation bash never produces.

`grep -a` is used. Without it, a NUL byte anywhere in `env/setup.sh` makes GNU
grep 3.11 write `binary file matches` to stderr and nothing to stdout, which
reaches the read as a match that produced no output. Before grep 3.5 that notice
went to stdout, which the read reports as an unparsed value. Both fail closed.

### The manifest version field

`// ""` cannot express "present and empty": it also fires on absent, null and
false, routing several broken-manifest shapes into one branch. The script
extracts the distinguishable states instead, and lets only present-and-empty go
uncounted.

`jq -r` emits one line per value, so more than one line is more than one
value — a multi-document manifest, or a version string containing a newline.
Both are caught before either can interpolate a newline into a single-line
message.

The comparison against the expected version is gated on an expectation having
been read. The manifest-shape failures are not gated, so a broken manifest is
reported whether or not `env/setup.sh` could be parsed.

Present-and-empty is a `NOTE` where an expectation was read, and does not set
the exit status. Where none was read, the comparison line says so and no `NOTE`
is emitted. The script cannot observe how the field came to be empty, so it
states only what it read.

### The delivered payload

`config/CLAUDE.md` is compared byte for byte against the live `CLAUDE.md` with
`cmp -s`. Step 3 of `scripts/bootstrap.sh` copies the file whole rather than
merging it, so equality is the right test here where containment is the right
test for the settings file.

The absent cases are separated before the comparison runs, and each names which
side is missing: a repository without `config/CLAUDE.md`, and a config
directory bootstrap never wrote. `cmp`'s exit 1 is a difference and its exits
above 1 are a failure to compare, which are reported as different states rather
than folded together.

`scripts/bootstrap.sh` counts a missing `config/CLAUDE.md` into `fails`, and
that count reaches only the log and that script's exit status, neither of which
`scripts/verify.sh` reads. No manifest field records it.

### The delivered keys

Every key `config/settings.json` carries is compared against the live
`settings.json` as a JSON value, not as text. The list of keys is read from the
delivered file rather than written into the script, so a key added to the
payload is checked without the script being edited; a delivered file that is
not an object, or carries no key at all, is a `FAIL` of its own.

The merge is additive, so a key the live file carries and the delivered file no
longer names is left in place and is not reported. Neither script prunes the
live file. The CLI rewrites the live file and reorders its keys, so a text
comparison would fail on a file carrying the right values.

The test is that the live value carries the delivered one, not that the two are
equal. `scripts/bootstrap.sh`'s step 4 merges the delivered file over the live
one with `jq`'s `*`, which keeps a key the live file already held under the same
object. A live `hooks` object carrying an event the delivered file does not name
is a correct delivery, and an equality test would fail it.

Carrying is tested with that same operator: the check passes where merging the
delivered value into the live value would change nothing.

Each side's value is wrapped in a single-key object before the merge, and the
key is read back out. `*` applied to two bare values is not a merge: on two
numbers it multiplies, so a live `0` would carry any delivered number and a
delivered `1` would be carried by any live number; on a string and a number it
repeats; on two arrays, two booleans or two nulls it raises an error, so
identical values would fail. Wrapping restricts `*` to the object merge
`scripts/bootstrap.sh` itself performs, which recurses into objects and takes
the right-hand value whole for everything else. A differing scalar, a differing
array and an absent key then each fail, and equal values of any type carry.

The comparison reports a named state, not an exit status: `carries`, `does not
carry`, absent from the live or the delivered file, a non-object top level on
either side, or a document count other than one. A `jq` that could not run at
all is reported as not determined. An absent file and a file holding no valid
JSON both make the slurping `jq -s` exit 2 with no output, so both reach that
state; the `test -f` line printed above separates them.

Both sides go through one `jq` program reporting three states: a top level that
is not an object, a key absent, and a key present with its value. That program
supplies the value printed on a failure, not the verdict. Its `jq -S` sorts
object keys recursively so the printed value is stable between runs.

The verdict's key-order independence comes from `jq`'s own structural equality
inside the carrying test, which holds without `-S`: `{a:1,b:2} == {b:2,a:1}` is
true. Arrays keep their order under that equality, which this comparison needs:
`hooks.UserPromptSubmit` is an array whose order decides which hook runs first.

A key absent from `config/settings.json` fails as a repository fault. A key
absent from the live file, or holding a different value, fails with both sides
printed.

Each file is slurped by its own `jq -c -s .`, read as a positional argument,
into its own array, and the two arrays are piped into the comparing `jq` as two
inputs. A file that does not yield exactly one JSON document is reported as that
state. Reading both files into one array aligns them by position, and a live
file holding two documents then displaces the delivered one out of the compared
slot. `--slurpfile` is not used: `jq.exe` on Windows cannot open a path carrying
non-ASCII characters through it, and opens the same path given as a positional
argument.

`jq.exe` on Windows ends each output line with CRLF. The delivered key list and
the plugin id list have every CR removed before they are split into lines.

`settings_probe`, which supplies the displayed value, still emits one line per
document, so for such a file the displayed value is each document's probe in
turn. The state named beside it says how many documents were found.

### The deployed copy's state

Three probes run on the repository under test, after the `rev-parse --git-dir`
probe and gated on it. Each runs `git` with `GIT_DIR`, `GIT_WORK_TREE`,
`GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_COMMON_DIR` and
`GIT_ALTERNATE_OBJECT_DIRECTORIES` removed from its environment.

| Probe | Passes where | Fails on |
| --- | --- | --- |
| Top level | `rev-parse --show-toplevel` and the repository under test have one canonical form through `canon_path` | a parent repository's top level; a non-zero exit |
| `FAIL deployed copy branch` | `symbolic-ref -q HEAD` prints `refs/heads/main` | another ref, a tag among them; a detached `HEAD`, exit 1; any other non-zero exit; a failed top-level probe |
| `FAIL deployed copy changes` | `status --porcelain` exits 0 with no output and nothing on stderr, and `ls-files -v` lists no entry tagged `S` or lowercase | any status entry, modified, staged or untracked; any stderr output; a non-zero exit; a status that ran past 10 seconds; a marked index entry; a failed top-level probe |

The branch probe runs before the status probe. The status command carries
`--untracked-files=all`, `--ignore-submodules=none`, `-c core.fsmonitor=false`,
`-c core.quotePath=true` and `--no-optional-locks`, so no git config setting
hides an untracked file or a submodule, no configured monitor answers for the
work tree, non-ASCII path bytes are C-quoted, and the index is not rewritten.
It runs under `timeout 10` where `timeout` exists. A failing line prints the
entry count and the first five entries, each cut to 120 bytes, joined by
` | `, through `sanitize`. The branch, the top-level path and git's first stderr
line are each cut to 120 bytes too.

A sparse checkout marks entries skip-worktree, so it fails the changes check.
A repository under test named by a Windows 8.3 short path or through the `/tmp`
mount passes the top-level probe where `cygpath` exists.

A cloud clone made by `env/setup.sh` and a deployed copy the installer cloned
or refreshed pass all three.

The checks cannot separate these states from a clean copy:

| State | Why |
| --- | --- |
| A clean copy at another commit on the same branch | `status` compares against the copy's own `HEAD`; `FAIL manifest.commit` catches it |
| A change confined to a file the copy's ignore rules match, including `.git/info/exclude` and the global excludes file | `status` omits ignored files |
| A mode-only change where `core.fileMode` is `false`, its default on Windows | `status` does not compare modes |
| A clean filter, `.git/info/attributes` entry or other setting in the copy's `.git` that rewrites what `status` compares | nothing reads the copy's `.git` configuration |
| A change to `scripts/verify.sh` or `scripts/session-check.sh` in the copy that removes these checks | the `SessionStart` hook runs both from the copy they check |

The checks report drift in the copy. They do not establish its integrity
against a change made to defeat them.

### The remote main head

After the deployed copy's state, the script reads the copy's full `HEAD` with
`rev-parse --verify -q HEAD`, and the head of `refs/heads/main` on its origin
with `ls-remote -- <URL> refs/heads/main`, the URL read from the copy's
`remote.origin.url`. `ls-remote` runs from `/`, outside the copy, so the copy's
own config, such as `remote.origin.uploadpack`, `core.sshCommand` or a proxy,
does not apply to it; the user's global and system config do. The read runs
under `timeout -k 2 5`, with `GIT_TERMINAL_PROMPT=0`, stdin from `/dev/null`
and stderr discarded, so it adds at most 7 seconds to the run and the origin
URL is never printed. Where `timeout` is absent the read does not run. Both
reads use the `GIT_*`-stripped `git` the copy's other probes use. A head is
read only from a line of 40 or 64 hex digits, a tab and `refs/heads/main`.

| `not read` state | What it establishes |
| --- | --- |
| `timed out after 5s (exit=124)` | The read ran past its bound. |
| `timed out after 5s (exit=137)` | The read ran past its bound, or `git` was killed by `SIGKILL` from outside. |
| `(timeout or env exit=N)`, `N` 125 to 127 | `timeout` or `env` failed to run `git`. |
| `(git exit=N)` | `git ls-remote` failed. The cause is not captured, stderr being discarded: an unreachable host, refused authentication, a missing repository, a TLS error and a relative origin URL, which resolves from `/`, all read the same. |
| `no refs/heads/main line (git exit=0)` | No `refs/heads/main` line of the expected shape was returned. An origin without `main` and one that hides the ref read the same. |
| `git -C <repo> config --get remote.origin.url -> exit=N` | The copy has no readable origin URL; `exit=0 value=empty` where the key holds an empty value. |

The run's other bounded steps, the status probe and `claude plugin list`
among them, are not bounded together; `scripts/session-check.sh`'s 20-second
bound reports a run that exceeds it.

Equal values print a `compare` line. Differing values, and a value that was
not read, print a `NOTE`, which does not set the exit status. The comparison
separates a copy at `main`'s head from one that is not. It does not separate a
difference that touches the delivered files from one that does not, nor an
origin `main` that moved forward from one that was rewound. A `NOTE` line makes
`scripts/session-check.sh` print the `FAIL` and `NOTE` lines instead of the
`fail -> N` tally.

### Git identity

Identity is checked effective from inside the clone, and need not come from git
config. `git config --get` cannot see a role's environment pair at all, so it is
not authoritative about the identity git will write, whether or not the two
happen to agree. `git var` resolves the same precedence git uses at commit
time, so that is what is asserted. The `user.email` read is shown for contrast
only.

No name or email is written into this repository. Five assertions stand in
place of the literals it used to carry:

| Assertion | What it catches |
| --- | --- |
| All four `GIT_AUTHOR_*` and `GIT_COMMITTER_*` variables set and non-empty | The panel supplying no identity |
| `git var` resolving each role to that role's own pair | Git not reading the pair the session was given |
| Author and committer naming one identity | A commit attributed to two people |
| Neither email being `noreply@anthropic.com` | The harness identity taking over |
| Each set email holding the address form | An email that is not in the form of an address |

The harness-default assertion catches a failure that has occurred here. With
the pair absent, `git var` resolves from `/root/.gitconfig`, which holds
`Claude <noreply@anthropic.com>` after every rewrite. The first four are checked
together: a role can be unset and still yield an identity, so the variable
assertions alone miss that case, and a set-but-wrong pair carries no harness
email, so the harness-default assertion alone misses that one.

Deriving the expected identity from the same variables `git var` reads makes
that third assertion narrow: it tests that git honours the pair, not that the
pair is the right one. What the pair is cannot be asserted from inside the
repository without naming a person in it. The harness-default test is what
keeps the set false-negative closed.

Each role variable has three states, not two: an empty variable is not an
absent one. This is the same three-state idiom as the `CLAUDE_CONFIG_DIR` read
above. An empty role-variable name is one cause of exit 128; an absent variable
with an empty `user.name` in config, and no identity resolvable at all, produce
the same exit, so the exit does not identify the state. The script reports the
state from the variable, never from the exit. The state is keyed per role
inside the loop, because `GIT_COMMITTER_IDENT` does not read the AUTHOR
pair, and reporting the AUTHOR pair beside a COMMITTER failure would name
variables that did not cause it.

| Role variable state | `git var GIT_AUTHOR_IDENT` |
| --- | --- |
| absent | falls through to config; exit 0 where config resolves an identity, 128 where it does not |
| `GIT_AUTHOR_EMAIL` set but empty | `Name <>`, exit 0 |
| `GIT_AUTHOR_NAME` set but empty | `fatal: empty ident name`, exit 128 |

The ident is trimmed from `Name <email> <unix-ts> <tz>` to `Name <email>` with
`%`, not `%%`. Git strips `<`, `>` and newlines from both fields before writing
an ident: `a<b>c@example.com` comes back as `abc@example.com`. So exactly one
`>` can appear, but shortest-suffix removal does not depend on that holding. With `%%`, a second `> ` would truncate to a
prefix that can equal the expected identity. The email is read back out of the
trimmed ident with `##*<`, sound for the same reason: no `<` survives inside
either field, so the last one is always the delimiter.

An ident that does not parse to `Name <email>` is a `FAIL` of its own. The email
test and the agreement test are both gated on the parse having succeeded, so an
error string is never compared as if it were an address. Where either role did
not parse, the agreement test prints `not run` and names which role, rather than
finding two identical diagnostic strings and reporting them as one identity.

### The email address form

Each role's `GIT_*_EMAIL` is checked against the address form where it is set
and non-empty. An unset or empty variable is already a `FAIL git <ROLE>
variables` line, and is not checked again.

| State | Line |
| --- | --- |
| The address form | `GIT_<ROLE>_EMAIL address form -> yes` |
| Not the address form | `FAIL git <ROLE> email: expected GIT_<ROLE>_EMAIL to hold one @, ..., actual [<value>] with <causes>` |

The causes are listed together where several hold, in the style of the
assignee check:

| Cause | Test |
| --- | --- |
| `<N> @ signs` | The value holds other than exactly one `@`. No other cause is tested. |
| `an empty local part` | Nothing precedes the `@`. |
| `whitespace, < or > in the local part` | The part before the `@` holds a space, tab, newline, carriage return, vertical tab, form feed, `<` or `>`. |
| `a domain of a single label` | The part after the `@` holds no `.`. |
| `an empty domain label` | A label between dots, or at either end, is empty. |
| `a domain label longer than 63 characters` | A label holds more than 63 characters. |
| `a domain label carrying a character other than an ASCII letter, digit or hyphen` | A label holds a character outside `A-Z`, `a-z`, `0-9` and `-`, spelled out so the locale cannot widen it. |
| `a domain label with a leading or trailing hyphen` | A label starts or ends with `-`. |
| `a check that did not complete (email_causes exit=N)` | The function that tests the form exited non-zero. |

The variable is checked, not the `git var` ident: git strips `<` and `>` from an
ident, so the ident cannot show them. The value is printed through `sanitize`.
The check tests the form, not that the address receives mail or that GitHub
links it to an account. A control character other than whitespace, and a `"`, pass in
the local part.

### The assignee login

`HARNESS_ASSIGNEE` is the GitHub login that `config/CLAUDE.md`'s Issues rules
assign created issues and pull requests to. The assertion runs after the
identity agreement test.

| State | Line |
| --- | --- |
| Unset | `FAIL HARNESS_ASSIGNEE: expected a GitHub login set and non-empty, actual unset` |
| Set but empty | `FAIL HARNESS_ASSIGNEE: expected a GitHub login set and non-empty, actual set but empty` |
| Set, not a login's form | `FAIL HARNESS_ASSIGNEE: expected a GitHub login of at most 39 letters, digits and single hyphens with no leading or trailing hyphen, actual [<value>] with <causes>` |
| Set, a login's form | no `FAIL` line |

The causes are listed together where several hold:

| Cause | Test |
| --- | --- |
| `a character other than a letter, digit or hyphen` | a character outside `A-Z`, `a-z`, `0-9` and `-`, spelled out rather than as a range so the locale cannot widen it |
| `a leading or trailing hyphen` | the value starts or ends with `-` |
| `consecutive hyphens` | the value contains `--` |
| `<N> bytes` | the value is longer than 39 bytes |

The value is printed through `sanitize` on its own `HARNESS_ASSIGNEE ->` line;
a login is not a secret. The assertion tests the login's form, not that the
account exists.

### The signing keys

Both keys are checked, because bootstrap writes both. `docs/environment.md`,
under "Identity", records that the two values read back unchanged across a
rewrite of `/root/.gitconfig`; under "Unresolved" it leaves open what triggers a
rewrite and which component performs it.

The read is effective, not `--global`: repository-local config wins over the
global value bootstrap writes, so reading `--global` would hide a local
override.

Git has no environment override for these two the way it has for identity, which
is why this reads config at all. That is not a claim that `git config --get`
always reports what git will use: with `GIT_CONFIG` set it reads that file alone
while every other git command ignores it, so a wrong value could report clean.
`GIT_CONFIG_GLOBAL`, `GIT_CONFIG_SYSTEM` and the
`GIT_CONFIG_COUNT`/`KEY_n`/`VALUE_n` triple do not diverge that way, because
every git command honours them: they redirect where config is read without
making this read disagree with what git uses.

The reported value and the verdict are gated on the `rev-parse` probe above
the identity loop.
`git -C <dir> config --get` answers from global scope with exit 0 when git will
not read `<dir>` — not a repository, or dubious ownership — so without that
gate the check would silently test the global value it exists to bypass, while a
repository-local `true` went unreported.

### The hooks path

The effective `core.hooksPath` is read inside the repository under test, gated
on the same `rev-parse` probe, and compared with `<repo>/git-hooks` through
`canon_path`. A relative value resolves against the directory `verify.sh` runs
in. The read line prints the value and its canonical form, or `unset (git
exit=1)`, `unreadable (git exit=N)`, `present with empty value`, or `repo
unreadable`. Anything but a match is `FAIL core.hooksPath`.

The read is effective, not `--global`, as for the signing keys. It does not
show what another repository reads: a repository whose own config sets
`core.hooksPath` overrides the global value there, and
`scripts/session-check.sh` prints that per repository.

### The commit-msg hook check

`verify.sh` makes a repository in a `mktemp -d` directory and commits through
whatever `core.hooksPath` git resolves there, with no override. Each git command
runs with the repository-redirecting `GIT_*` variables unset, under the 10-second
`timeout` the status read uses where `timeout` exists, and with
`-c user.name=verify.sh -c user.email=verify@example.com -c commit.gpgsign=false`,
which a role's environment pair still outranks.

| Case | Message | Passes where |
| --- | --- | --- |
| `a message carrying a Co-Authored-By: Claude trailer` | `verify.sh rejected case`, a blank line, and `Co-Authored-By: Claude <noreply@anthropic.com>` | `git commit --allow-empty -F` exits non-zero and its stderr carries `harness commit-msg: matched line ->` |
| `a clean message` | `verify.sh clean case` | `git commit --allow-empty -F` exits 0 |
| `a repository's own pre-commit hook exiting 1` | `verify.sh forwarding case`, after `verify.sh` writes an executable `.git/hooks/pre-commit` that prints `verify.sh: the repository's own pre-commit hook ran` and exits 1 | `git commit --allow-empty -F` exits non-zero and its stderr carries that line |

Each case prints `git commit through the effective core.hooksPath, <case> ->
exit=N [<line>]`, the line being the first stderr line carrying the case's
marker, else the first carrying `harness `, else the first stderr line, cut to
120 bytes. A failing case is `FAIL commit-msg hook, <case>` for the first two
and `FAIL hook forwarding, <case>` for the third. Where `mktemp -d`, `git
init`, `git add` or the hook write fails, the cases after it print `not run`
with that cause and fail. The directory is then removed, and
`rm -rf <temporary repository> -> exit=N` printed; a non-zero exit is
`FAIL commit-msg hook cleanup`.

The check tests that a commit through the effective configuration is refused
on the pattern, allowed without it, and stopped by the repository's own
`pre-commit`. It does not test any other hook name, or the hook files' mode in
the deployed copy. It adds a `git init`, a `git add` and three commits to the
run, which `scripts/session-check.sh` bounds at 20 seconds in all; a scratch
install on Windows ran the whole of `verify.sh` in about 8 seconds.

## scripts/session-check.sh

Reports what a session starts with. Run by the `SessionStart` hook
`config/settings.json` registers, and by hand. It exits 0 in every case, so a
failed check never blocks session startup.

`REPO` reads `${HARNESS_DIR:-/opt/my-harness-wrapper}`, the same default
`scripts/verify.sh` reads, so both report on the delivered copy. The hook
resolves the script's own path the same way.

The script reads `local_checkout` from the manifest in
`${CLAUDE_CONFIG_DIR-$HOME/.claude}`, converted with `cygpath -u` where
`cygpath` exists. A non-empty string takes the local branch; an absent field,
manifest or `jq` takes the cloud branch, whose output is the script's output
before the local branch existed. The read prints nothing in the cloud branch.

| Branch | Log | Lines before the `verify.sh` block |
| --- | --- | --- |
| Cloud | `/home/user/session-check.log` | The boot-time comparison and, per directory under `/home/user`, its branch line and its `core.hooksPath` line, as the table below sets out. |
| Local | `session-check.log` in the config directory | `jq -r .local_checkout <manifest> -> <path>`, `test -f <install log> -> yes/no`, and, where it exists, `stat -c %y <install log> -> <mtime>` and `tail -n 1 <install log> -> fails -> N`, then the working directory's `core.hooksPath` line. No line names `/home/user`. The path and the log line pass through the control-byte replacement. |

Each line goes to stdout and is appended to the log. A
failed append is discarded, so an unwritable log does not change the output.
The log's own state is tested once at the start and printed as
`append to <path> -> appendable` or `not appendable`, so a later reader of a
truncated log can tell that the writes were failing rather than that the
session was quiet.

| Line | What it reports |
| --- | --- |
| `session-check -> exit=N value=...` | When the run started, and `date`'s own exit status. |
| `uptime -s` and `stat -c %y` on the boot log | The two values behind the boot-time comparison. |
| `test -f <boot log> -> yes/no` | Whether the boot log is at the path this script reads. |
| `log mtime >= boot time -> yes/no` | Whether the boot log's mtime is at or after the boot time. `docs/runbook.md`, under "Reading the session-start check", carries what each value does and does not establish. |
| `snapshot state -> undetermined, log epoch [...] boot epoch [...]` | Either epoch was missing or non-numeric. Both values are printed. |
| `snapshot state -> undetermined, ... absent` | The boot log is not at the path this script reads, so neither epoch exists. |
| `git -C <dir> rev-parse --abbrev-ref HEAD, --short HEAD` | One line per directory under `/home/user`, with its branch and short HEAD. |
| `git -C <dir> config --show-origin --get core.hooksPath -> exit=N value=[<origin> <value>]` | The effective `core.hooksPath` and the file that sets it: in the cloud, after each repository's branch line; locally, for the working directory, after the install log lines. Exit 1 means unset. A value whose origin is the repository's own config overrides the harness's. Tabs and control bytes are replaced. No verdict is printed. |
| `ls -d /home/user/*/ -> none` | No directory was found under `/home/user`. |
| `git -C <dir> rev-parse --git-dir -> exit=N` | A directory git would not read. The exit code stands in place of a reason: git also refuses a real repository over dubious ownership. |
| `verify.sh FAIL ...`, `verify.sh NOTE ...` | Every `FAIL` and `NOTE` line it printed. |
| `verify.sh -> fail -> N ...` | Its tally, where it printed no `FAIL` or `NOTE` line. |
| `verify.sh -> no 'fail ->' line ...` | It printed neither. The line states the file's total line count and how many follow, capped at `SESSION_CHECK_OUT_LINE_CAP`. |
| `verify.sh \| ...` | Those lines, one each. |
| `test -f <verify.sh> -> yes/no` | Whether `scripts/verify.sh` is at the path this script reads. |
| `verify.sh -> not run, ... absent` | `scripts/verify.sh` is not at the path this script reads. |
| `verify.sh -> timed out ...` | The inner bound elapsed and the process group was killed. |
| `mktemp -> empty, verify.sh not run` | No temporary file could be made for the output, so the check was skipped. |

An absent `/home/user/bootstrap.log`, an absent `scripts/verify.sh`, and a
directory git would not read each produce a line naming the path or the
predicate rather than a conclusion about why.

The boot-time comparison needs both epochs. Each is tested on its own, because
testing them joined lets one empty value pass while the other supplies the
digits, and the comparison then runs against an empty operand and reads `no`.
Either one missing or non-numeric reports undetermined instead,
with both values printed.

The boot epoch is computed only where `uptime -s` exited 0, so output from a
failed call cannot reach the comparison.

The echoed `verify.sh` output is capped at `SESSION_CHECK_OUT_LINE_CAP` lines,
40 by default. The line above it states the file's total and how many follow.
The two agree on every input but one: a file whose last bytes are NUL with no
trailing newline. `grep -a -c ''` counts that remainder as a line while `read`
drops the NUL bytes, leaves the variable empty and stops, so the header reads
one higher than the number of lines that follow. That is a known gap. Every line is read from the file rather than from a
captured variable, because a command substitution strips trailing newlines,
which counts an empty output as one line and drops trailing blank lines.

`/home/user/session-check.log` is appended to on every session start and is
never rotated.

Every `grep` reading that file passes `-a`, for the reason `env/setup.sh`'s
version line needs it: without it a NUL byte anywhere makes GNU grep treat the
whole file as binary. On such a file `-q` still matches while the retrieval
prints nothing, so the `FAIL` and `NOTE` branch emits nothing and the tally is
not found, and `grep -c ''` counts one line more than the file holds.

A NUL byte inside a line is still dropped rather than replaced. Each line is
read into a shell variable, which cannot hold one, so the control-byte
replacement never sees it and its guarantee that an observation is altered
visibly does not reach that byte.

### The verify.sh bound

The inner bound is strictly shorter than the hook's timeout, so the script
reports a timeout rather than being killed mid-report.
`SESSION_CHECK_VERIFY_TIMEOUT` defaults to 20 seconds and
`SESSION_CHECK_VERIFY_KILL_AFTER` to 5, against the hook's 30.

`timeout` runs without `--foreground`, so it places the child in its own process
group and signals that group.

`timeout -k` escalates to `SIGKILL` only while the process it waits on is still
alive. A grandchild ignoring `SIGTERM` outlives a direct child that does not:
`bash scripts/verify.sh` exits on the signal, `timeout` returns 124 at once, and
the grandchild is never killed. The script therefore kills the process group
itself once `timeout` returns.

`verify.sh`'s output is captured to a file rather than through a command
substitution, because a surviving grandchild holds the substitution's pipe open
and the read blocks after `timeout` has exited.

Without the group kill a `SIGTERM`-ignoring grandchild outlives the check and
the script does not return. With it the script returns at the inner bound and no
such process remains.

### The SessionStart hook

`config/settings.json` registers it with matcher `startup`. The command resolves
the script under `${HARNESS_DIR:-/opt/my-harness-wrapper}`, and guards on its
presence with `if`, not with `&&` and `||`, which would
print the absent-file line when the script exists and fails. The `else` branch
prints `test -f <path> -> no`, so a session where delivery never happened is
distinguishable from one where the check ran and found nothing wrong. Every
session carries the hook, whatever it has attached.

## scripts/attribution-guard.sh

Blocks a pull request, issue, comment, review or review reply body, or a commit
a GitHub tool makes, carrying a
Claude Code attribution line, and reports one that a pull request create call
returns. Run by the `PreToolUse` and `PostToolUse` hooks `config/settings.json`
registers, which pass the hook input to it on stdin as JSON. The `PreToolUse`
hook matches these tool names exactly.

| Tool | Writes |
| --- | --- |
| `Bash` | Any command; the guard scans only the writes the table below names. |
| `mcp__github__create_pull_request`, `mcp__github__update_pull_request` | A pull request description. |
| `mcp__github__issue_write` | An issue. |
| `mcp__github__add_issue_comment`, `mcp__github__update_issue_comment` | An issue or pull request conversation comment. |
| `mcp__github__add_reply_to_pull_request_comment` | A reply to a pull request review comment. |
| `mcp__github__pull_request_review_write` | A pull request review body. |
| `mcp__github__add_comment_to_pending_review` | A comment in a pending pull request review. |
| `mcp__github__push_files`, `mcp__github__create_or_update_file`, `mcp__github__delete_file` | A commit on GitHub, with its message. |
| `mcp__github__merge_pull_request` | A merge commit, with its title and message. |
| `mcp__github__enable_pr_auto_merge` | A merge that GitHub makes later. Whether its input carries a commit message is not verified. |

The `PostToolUse` hook matches `mcp__github__create_pull_request` only. No
comment, review or reply path has been observed appending the footer itself;
`docs/environment.md` records that as unmeasured under "The footer on comments,
reviews and replies".

An input whose `hook_event_name` is `PostToolUse` takes the path under
"The PostToolUse path" below. Any other input, one with no `hook_event_name`
among them, takes the `PreToolUse` path this table describes.

| `tool_name` | What is scanned |
| --- | --- |
| `Bash` | The command, and every file it passes as a body, where the command runs `gh pr create`, `gh pr edit`, `gh pr comment`, `gh pr review`, `gh issue create`, `gh issue edit`, `gh issue comment`, or `gh api` against an endpoint carrying `/pulls` or `/issues`. Any other command is left alone. |
| `mcp__github__push_files`, `mcp__github__create_or_update_file`, `mcp__github__delete_file`, `mcp__github__merge_pull_request`, `mcp__github__enable_pr_auto_merge` | Every string in `tool_input`, at any depth, except file contents: a `content` key at the top level and in each object of a `files` array. A document whose contents quote the footer stays writable. An input carrying no message, as `enable_pr_auto_merge`'s may, passes. |
| Anything else | Every string in `tool_input`, at any depth. |

A body file is taken from four token forms: `--body-file <path>`,
`--body-file=<path>`, `-F <name>=@<path>` for any field name, and
`body=@<path>` after any flag spelling. A field named anything but `body` is
recognised only after `-F`.

In a command that runs `gh pr create`, `gh pr edit`, `gh pr comment`,
`gh pr review`, `gh issue create`, `gh issue edit` or `gh issue comment`, `-F`
is the short form of `--body-file`,
and the argument after it is taken as a body file in three spellings:
`-F <path>`, `-F=<path>` and `-F<path>`. `gh` 2.101.0 accepts all three on both
`gh pr` commands, and accepts `-F` clustered behind another short flag on
`gh pr create`, as in `-dF<path>`. `gh` 2.63.2 opens the named file as the body
for all three spellings on each of the three `gh issue` commands. `gh` 2.89.0
lists `-b, --body` and `-F, --body-file` for both `gh pr comment` and
`gh pr review`. The guard covers the three spellings and not
the clustered one. A `-F` token is recognised only at the start of the command
or after whitespace. One run of surrounding quotes is stripped from the
path. A path that is not a readable regular file is skipped. The first mebibyte
of the file is scanned.

The match is case-insensitive, against the pattern in
`git-hooks/lib/attribution.ere`, which the `commit-msg` hook also reads; "The
message check" under "git-hooks/" lists its alternatives. The guard finds the
file from its own path, `${BASH_SOURCE[0]}`, as
`../git-hooks/lib/attribution.ere`, and removes one trailing carriage return.

| Outcome | Exit | Output |
| --- | --- | --- |
| A line matched | 2 | The matched line and the instruction to remove it, on stderr. |
| The pattern file absent, empty or more than one line, or `grep` exiting above 1, where a body would be scanned | 2 | `attribution-guard: <cause>, so the body was not checked.` and the instruction to restore the file, on stderr. |
| Nothing matched | 0 | None. |
| Input that is not a JSON object, carries no `tool_name`, or arrives with no `jq` on `PATH` | 0 | None. |

Scoping the `Bash` branch to pull request, issue, comment and review writes
keeps documentation quoting the footer writable. A `grep` for the footer text, or a `gh issue list`
searching for it, is not such a write, and is not scanned. A `gh api` read
against a `/pulls` or `/issues` endpoint is scanned like a write, so one whose
command carries the pattern is blocked.

A matched line goes to stderr through the same control-byte replacement
`scripts/verify.sh` uses, so a body carrying ESC or CR cannot rewrite the line
an operator reads. The line printed is a line of the body or of a body file, so
a body file the command names by mistake can put one of its lines in front of
the session.

These paths reach a pull request, issue, comment, review or reply body without
being scanned. Each is accepted, not handled.

| Path | Why it is missed |
| --- | --- |
| `--body "$(cat notes.md)"`, or any other shell substitution | The hook receives the command before the shell expands it, so the body text is not in what it reads. |
| `curl`, `wget` or a script posting to `/repos/<owner>/<repo>/pulls` or `/issues` | None of `gh pr`, `gh issue` or `gh api` appears in the command, so the command is not classified as a write. |
| `gh api graphql` mutating a pull request or an issue | The endpoint is `/graphql`, and the classifier requires `/pulls` or `/issues`. |
| A commit message sent through `Bash`: `gh pr merge --subject` or `--body`, or `gh api` against `/contents/` or `/git/commits` | None of these is classified as a write, so the command is not scanned. |
| A body-file path carrying a space | The path is read up to the first space, and the truncated path is then skipped as unreadable. |
| A body file past its first mebibyte | Only the first mebibyte is read. |
| A `--body-file` flag and its path on different lines of a continued command | Each token form is matched within one line. |
| A `Co-Authored-By:` or `Claude-Session:` trailer written inside a one-line command, as in `--body $'x\n\nCo-Authored-By: ...'` | The trailer alternatives are anchored at a line start, and the command text carries `\n` literally, so the trailer starts no line. |
| `-F` clustered behind another short flag, as in `-dF <path>` or `-dF<path>` | Only a `-F` token standing alone is recognised. |
| A body read from standard input, `-F -` or `--body-file -` | The path `-` is not a regular file, so it is skipped. |
| A body-file path carrying a variable, a `~` or another shell expansion | The hook receives the command before the shell expands it, so the path is read literally and skipped where no such file exists. |
| A relative body-file path after a `cd` in the same command | The path is resolved against the hook's working directory, not the directory the command changes to. |
| An issue created or edited through any tool but `mcp__github__issue_write` and `Bash` | The `PreToolUse` matcher names no other issue tool, so the guard does not run. |
| A footer added to a pull request description after the tool call | The `PreToolUse` path sees the tool call, and the footer is not in it. The `PostToolUse` path covers the create call. `docs/environment.md` records the footer under "What the harness supplies regardless". |

Nothing is printed when the guard is inert — `jq` absent, or the script absent
from the path the hook names — so a session cannot tell an inert guard from one
that found nothing. `scripts/verify.sh` is what separates them.

### The PostToolUse path

It acts only on `mcp__github__create_pull_request`. Any other `tool_name` exits
0, the issue tool among them, so an issue create has no `PostToolUse` path.

The first row that fits decides the outcome.

| Input | Exit | Output |
| --- | --- | --- |
| Hook input over 1 MiB | 2 | That the input was not checked, and the instruction to resend the description unchanged through `mcp__github__update_pull_request`, on stderr. |
| A string field named `body` in `tool_response`, at any depth, matching the pattern above | 2 | The match with up to 80 characters either side, and the same instruction, on stderr. |
| One or more string fields named `body`, none matching | 0 | None. |
| `tool_response` an object whose `isError` is `true`, or whose `error` is a non-empty string or object | 0 | None. |
| Anything else | 2 | That no string field named `body` was found, and the same instruction, on stderr. |

The depth search covers `tool_response` itself and every string in it that
parses as JSON, one level deep, so a `body` inside a JSON-encoded text content
block is found.

The instruction line is
`attribution-guard: resend the description this create call sent, unchanged, through mcp__github__update_pull_request.`

These gaps are accepted, not handled.

| Gap | Effect |
| --- | --- |
| A failure reported in any shape other than the two the table names | Read as a successful create with no `body`, so it draws the instruction. |
| A `body` that is `null`, as for a pull request with an empty description | Not a string field, so it draws the instruction. |
| A `body` inside a string that is JSON-encoded twice | Not found, so it draws the instruction. |
| A footer added after the create call returns | Not in the response, so the guard does not see it. |
| `jq` absent | The guard exits 0 before reading the event, as on the `PreToolUse` path. |

Exit 2 on `PostToolUse` does not undo the create. It puts the stderr text in
front of the session after the call has run.

### The verify.sh assertion

Both assertions run the live command with the `HARNESS_DIR` a hook process
would receive: the live `settings.json`'s `env.HARNESS_DIR` where it is a
string, and unset otherwise, whatever the caller's own `HARNESS_DIR` holds. The
`jq -r .env.HARNESS_DIR` line before them prints that value. A local install
missing that key therefore fails both assertions, as its hooks would find no
guard. Where the value is present, it is compared against `REPO`,
both through `canon_path`,
and a difference is `FAIL hook harness dir`: the hooks would run another tree's
scripts than the one every other check reads.

`scripts/verify.sh` runs the first live `PreToolUse` command whose text names
`attribution-guard.sh` against a sample `gh pr create` body carrying the
footer, and expects exit 2 with the guard's own
`attribution-guard: matched line ->` marker on stderr. Where no `PreToolUse`
command names it, the check fails with a line saying so. The selection reads
the command's text, not what it runs: a command naming the script without
running it is selected and fails the exit check, and a command running the
guard under another name is not selected. The exit status alone does not
distinguish a guard that matched from a `PreToolUse` command whose shell syntax
is broken, `bash -c` exiting 2 for both. The assertion runs the command the
live `settings.json` registers, so it trusts that file as much as the session
running it already does. It tests the delivered hook, not this file, so it
fails in a session whose snapshot predates the hook.

A second assertion does the same for the first live `PostToolUse` command whose
text names `attribution-guard.sh`. It feeds that command a
`mcp__github__create_pull_request` response whose `body` carries the footer, and
expects exit 2 with `attribution-guard: matched line in the response body ->` on
stderr, which the guard prints only on a footer match. The
selection, the broken-shell ambiguity and the trust in the live file are as
above. A guard that predates the `PostToolUse` path scans the clean
`tool_input` instead, exits 0, and fails the assertion.

Each of the two commands is then run on an input carrying no footer, and
expected to exit 0: a `gh pr create` body for the `PreToolUse` command, and a
`mcp__github__create_pull_request` response whose `body` carries no footer for
the `PostToolUse` command. Any other exit is a `FAIL` naming that input, with
the first line of the command's stderr, cut to 120 bytes. A command that exits 2 with the guard's
marker on every input passes the footer assertion and fails this one. The
function `guard_clean_check` runs both. Where the command or the sample input
is missing, it prints the same state the footer assertion prints, and fails
too.

## scripts/test-attribution-guard.sh

Runs `scripts/attribution-guard.sh` from its own directory against a fixed set
of cases, directly and through the `PreToolUse` command and matcher of the
tree's `config/settings.json`. It is run by hand only. Neither `scripts/verify.sh` nor
`scripts/session-check.sh` runs it.

Each case pipes one JSON hook input into the guard: a tool call as the
`PreToolUse` hook passes it, or, for the create response cases, a
`PostToolUse` event carrying `tool_response`. A case marked as through the
delivered hook runs only where its `tool_name` matches that entry's matcher as
a whole string, and then runs the entry's command with `HARNESS_DIR` set to the
tree's root; an unmatched tool exits 0, as a hook that does not fire. Body
files are written into a `mktemp -d` directory, which is the
working directory while the cases run and is removed on exit.

| Line | What it reports |
| --- | --- |
| `test -f <guard> -> yes/no` | Whether the guard is at the path the script reads. |
| `command -v jq -> <path>/none` | Whether `jq` is on `PATH`. The cases are built with it. |
| `test -f <settings> -> yes/no` | Whether the tree's `config/settings.json` is at the path the script reads. |
| `PreToolUse matcher naming attribution-guard.sh in <settings> -> <matcher>/none` | The matcher of the first `PreToolUse` entry in the tree's `config/settings.json` whose command names the guard. `none` stops the run. |
| `<case> -> expected exit=N, actual ..., pass/FAIL` | One line per case. |
| `fail -> N` | The number of failed cases. `not run` where the guard or `jq` is absent, or where no `PreToolUse` entry names the guard. |

A case expecting exit 2 passes only where the guard's stderr also carries its
marker: `attribution-guard: matched line ->` for a `PreToolUse` case, and the
resend instruction line for a `PostToolUse` case. The script exits 0 where every case
passed, and 1 otherwise.

| Case | Input | Expected exit |
| --- | --- | --- |
| `gh pr create --body`, three cases | A body ending in each footer form: `Generated with`, `Generated by`, and the session link | 2 |
| `gh pr create --body-file <file>`, three cases | A body file ending in each footer form | 2 |
| `gh pr create --body-file=<file>` | A body file ending in the `Generated by` footer | 2 |
| `gh pr edit --body-file <file>` | The same file | 2 |
| `gh pr create -F <file>`, `-F=<file>`, `-F<file>` and `-F "<file>"` | The same file | 2 |
| `gh pr edit -F <file>` | The same file | 2 |
| `gh api repos/o/r/pulls -F body=@<file>` | The same file | 2 |
| Pull request tool `body`, three cases | A body ending in each footer form | 2 |
| `gh pr create --body`, clean | A body with no footer | 0 |
| `gh pr create --body-file <file>`, clean | A body file with no footer | 0 |
| `gh pr create -F <file>`, clean | A body file with no footer | 0 |
| Pull request tool `body`, clean | A body with no footer | 0 |
| Pull request tool `body`, `Co-Authored-By` naming Claude, with an `anthropic.com` address, and a `Claude-Session` trailer | A body ending in each trailer | 2 |
| Pull request tool `body`, `Co-Authored-By` naming a person | A body ending in that trailer | 0 |
| Pull request tool `body`, pattern file absent | A clean body, scanned by a copy of the guard in a tree with no `git-hooks/`; passes on the marker `so the body was not checked` | 2 |
| `grep` for the footer | A command carrying the footer that is not a pull request operation | 0 |
| Input that is not JSON | `not json` | 0 |
| `gh issue create --body`, three cases | A body ending in each footer form | 2 |
| `gh issue create --body-file <file>`, `-F <file>`, `-F=<file>` and `-F<file>` | A body file ending in the `Generated by` footer | 2 |
| `gh issue create -F "<file>"` | The same file | 2 |
| `gh issue edit --body-file <file>` and `-F <file>` | The same file | 2 |
| `gh issue comment --body-file <file>` and `-F <file>` | The same file | 2 |
| `gh api repos/o/r/issues -F body=@<file>` | The same file | 2 |
| Issue tool `body`, three cases | An `mcp__github__issue_write` create whose `body` ends in each footer form | 2 |
| `gh issue create --body`, clean | A body with no footer | 0 |
| Issue tool `body`, clean | A body with no footer | 0 |
| `gh issue list` searching for the footer | A command carrying the footer that is not a write | 0 |
| `gh issue commentary` with a body file carrying the footer | A subcommand name that only begins with `comment` | 0 |
| `gh pr comment` and `gh pr review --comment`, `--body` and `-b` | A body ending in a `---` rule and the `Generated by` footer | 2 |
| `gh pr comment` and `gh pr review --comment`, `--body-file <file>` and `-F <file>` | A body file ending in the `Generated by` footer | 2 |
| `gh pr comment` and `gh pr review --comment`, `--body`, clean | A body with no footer | 0 |
| `gh pr comment` and `gh pr review --comment`, `-F <file>`, clean | A body file with no footer | 0 |
| `gh pr comments` and `gh pr reviews` with a body file carrying the footer | A subcommand name that only begins with `comment` or `review` | 0 |
| `gh pr comment -F <file>` and `gh pr review --comment -F <file>`, through the delivered hook | A body file ending in the `Generated by` footer | 2 |
| `gh pr comment -F <file>`, through the delivered hook, clean | A body file with no footer | 0 |
| `mcp__github__add_issue_comment`, `mcp__github__update_issue_comment`, `mcp__github__add_reply_to_pull_request_comment`, `mcp__github__pull_request_review_write` and `mcp__github__add_comment_to_pending_review`, through the delivered hook | Each tool's own fields, with a `body` ending in a `---` rule and the `Generated by` footer | 2 |
| The same five tools, through the delivered hook, clean | A `body` with no footer | 0 |
| `mcp__github__push_files`, `mcp__github__create_or_update_file`, `mcp__github__delete_file`, `mcp__github__merge_pull_request` and `mcp__github__enable_pr_auto_merge`, through the delivered hook, two cases each | Each tool's fields, with a commit message ending in the `Generated by` footer, and in a `Co-Authored-By` trailer naming Claude; for `enable_pr_auto_merge` the message is put in a `commitBody` field, a name not checked against its schema | 2 |
| The same five tools, through the delivered hook, clean | A commit message with no footer | 0 |
| `mcp__github__push_files` and `mcp__github__create_or_update_file`, through the delivered hook, footer in file contents only | A clean message, and file `content` ending in the `Generated by` footer | 0 |
| `mcp__github__enable_pr_auto_merge` with no message, through the delivered hook | An owner, a repository and a pull request number only | 0 |
| A tool outside the delivered matcher, through the delivered hook | `mcp__github__get_me` with a `body` carrying the footer | 0 |
| Create response with a `body` carrying the marker | A `body` ending in a `---` rule and the `Generated by` footer carrying a session link | 2 |
| Create response with a clean `body` | A `body` with no footer | 0 |
| Create response with no `body` | An `id` and a `url` only | 2 |
| Create error response | `isError` set to `true` | 0 |
| Create error response with an error string | A non-empty `error` string and no `body` | 0 |
| Create response with an empty error and a `body` carrying the marker | An empty `error` string beside that `body` | 2 |
| Create response over 1 MiB with a clean `body` | A `body` of 1,100,000 bytes with no footer | 2 |
| Update response with a `body` carrying the marker | A `PostToolUse` event whose `tool_name` is `mcp__github__update_pull_request` | 0 |
| Create response text content carrying a `body` with the marker | A text content block whose JSON-encoded text carries that `body` | 2 |

## scripts/check-hook-matchers.sh

Compares the tool names the `PreToolUse` and `PostToolUse` matchers of its own
tree's `config/settings.json` name with a file of a session's tool names, one
per line. Run by hand only; `docs/runbook.md` carries the procedure under
"Checking the hook matchers".

Each matcher is split on `|`, empty alternatives kept. An alternative of
letters, digits, `_` and `-` is a tool name and is compared whole against the
file. An empty matcher and `*` match every tool and are printed as not
compared; an entry with no `matcher` key reads as empty. Any other alternative,
an empty one among them, is printed as not a
literal tool name and counted as uncompared. A non-object top level or `hooks`,
a `PreToolUse` or `PostToolUse` value that is not an array, an entry that is
not an object, a `matcher` key holding anything but a string, and a matcher
carrying a control character each make `jq` fail, and the check does not run.
The file's lines have CR and surrounding blanks removed, and empty lines are
skipped.

| Line | What it reports |
| --- | --- |
| `test -f <settings> -> yes/no` | Whether the tree's `config/settings.json` is at the path the script reads. |
| `command -v jq -> <path>/none` | Whether `jq` is on `PATH`. |
| `tool names file argument -> absent` | No file was named. |
| `test -f <file> -> yes/no`, `test -r <file> -> yes/no` | Whether the named file exists and is readable. |
| `jq PreToolUse and PostToolUse matchers of <settings> -> exit=N count=C [<error>]` | The matchers read, with `jq`'s first error line where `N` is not 0. |
| `PreToolUse entries -> N`, `PostToolUse entries -> N` | The entries read for each event. |
| `distinct tool names in <file> -> N` | The names read from the file. |
| `<event> matcher -> [<matcher>]` | One line per matcher. |
| `<event> matcher [<matcher>] -> matches every tool, not compared` | An empty matcher or `*`. |
| `<event> matcher alternative [<text>] -> not a literal tool name, not compared` | An alternative counted as uncompared. |
| `<event> matcher name <name> in the tool names file -> yes/no` | One line per name the matcher carries. |
| `MISSING <name>: ...` | A matcher name absent from the file. |
| `UNMATCHED <name>: ...` | A `mcp__github__` name in the file that no matcher names, for a person to judge whether it writes a body the guard should scan. |
| `UNMATCHED check -> not run, ...` | An empty matcher or `*` was read, or an alternative was not compared, so no `UNMATCHED` line is printed. |
| `compared -> N`, `uncompared -> N` | The names compared, and the alternatives counted as uncompared. |
| `unmatched mcp__github__ names -> N` | The `UNMATCHED` count. |
| `missing -> N` | The `MISSING` count, one per matcher entry naming the name. `not run` where no file was named, the settings file or the names file is absent or unreadable, `jq` is absent or failed, `PreToolUse` or `PostToolUse` has no entry, or the file holds no name. |

| Exit | Where |
| --- | --- |
| 0 | Nothing is missing, at least one name was compared, and no alternative is uncompared. |
| 1 | Any name is missing. |
| 2 | The check did not run, no name was compared, or an alternative is uncompared. |

`UNMATCHED` lines do not set the exit status.

## config/plugins.tsv

`README.md` carries the format.

Bootstrap, the local installer and verify read the file on descriptor 3, so the
loop body — `claude plugin install` in the first two, `grep` in verify — cannot
consume it from stdin. The loop's `|| [ -n "${mp_source:-}" ]` clause processes
a final line carrying no trailing newline.

`scripts/install-local.sh` and `scripts/verify.sh` remove one trailing CR from
`marketplace_source` and `plugin_id`, a Windows checkout carrying the file with
CRLF line endings. `scripts/bootstrap.sh` does not, its Linux clone carrying LF.

A `read` that fails on an I/O error mid-file ends the loop the same way
end-of-file does, leaving later rows unread and nothing counted. That gap is
accepted, not handled.

The two loops diverge on a row whose `plugin_id` is empty:
`scripts/bootstrap.sh` counts it into `fails`, `scripts/verify.sh` skips it
silently.

`read` strips leading and trailing runs of IFS whitespace, and a tab is IFS
whitespace here, so `marketplace_source` is never empty while `plugin_id` holds
a value. A row with a stray leading tab is read as a `marketplace_source` with
no `plugin_id`, which `scripts/bootstrap.sh` counts. A row with a leading space
is read as a `marketplace_source` of one space, which the marketplace call then
fails on, and that is counted too.

## env/setup.sh

`docs/environment.md` carries this script's provenance under "Delivery", and
its exit-code rule as established fact 5.

It is the only file the repository does not deliver. `BOOTSTRAP_VERSION` is
bumped in the last commit of any change under `config/`, `scripts/` or `env/`,
and the file is pasted after the merge. A mismatch between the manifest and the
clone means a paste is due. A version number is never reused for different
contents. `docs/runbook.md`, under "Deploying a change", carries the order and
what the comparison cannot separate.

It fetches the repository rather than reading an attached checkout. The clone
URL comes from `HARNESS_REPO_URL` where that variable is set and non-empty, and
from the script's own default, this repository's URL, where it is unset or
empty. A value the environment supplies is never overwritten. The destination
is the literal `/opt/my-harness-wrapper`. The cloned branch is the literal
`main`.

| Line | What it reports |
| --- | --- |
| `BOOTSTRAP_VERSION=` | The version the pasted text carries. |
| `HARNESS_DIR ->` | The clone destination. |
| `HARNESS_REF ->` | The cloned branch. |
| `HARNESS_REPO_URL -> <state>; clone URL from <environment\|default>` | The variable's state, and which of the two supplied the URL. Never the value itself. |
| `command -v git ->` | Whether git is on `PATH`. |
| `test -e <dir> -> yes/no` | Whether anything already occupies the destination. |
| `git clone --depth 1 --branch ... -> exit=N` | The clone's exit status. |
| `git -C <dir> log -1 ...` | The cloned commit and its date. |
| `test -f <dir>/scripts/bootstrap.sh -> yes/no` | Whether the clone carries the delivery step. |
| `bootstrap_exit=N` | `scripts/bootstrap.sh`'s exit status. |
| `bootstrap -> skipped, ...` | Why the delivery step did not run. |

The URL's state is reported with the three-state idiom `scripts/verify.sh` uses
for `CLAUDE_CONFIG_DIR`: an empty variable is not an absent one. Both of those
two states take the default, and the line names which source supplied the URL.
The script never prints the value itself.

That is not a guarantee that a credential-bearing URL stays out of the log.
`git clone` runs under the script's own redirection, and git writes the remote
it is cloning into its progress and error text, so a URL of the form
`https://user:token@host/repo` reaches `/home/user/bootstrap.log` through git
rather than through this script. A deploy key or a public repository avoids it.

The script does not delete the destination before cloning. `git clone` into an
existing non-empty directory exits non-zero, which skips bootstrap and is
named in the log, so a directory the image already carries fails closed rather
than being overwritten or silently delivered from.

Each skip path prints its reason and reaches `exit 0`. An absent `git`, a
failed clone, and a clone without `scripts/bootstrap.sh` are three distinct
lines. Neither an absent nor an empty `HARNESS_REPO_URL` skips bootstrap.
