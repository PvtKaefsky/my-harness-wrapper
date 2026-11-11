# Runbook

## Deploying a change

A change sessions should receive is any change under `config/`, `scripts/` or
`env/`. For one, in this order:

1. Bump the `export BOOTSTRAP_VERSION=` line of `env/setup.sh` in the round's
   last commit.
2. Merge the round to `main`.
3. Paste the full contents of `env/setup.sh`, read from `main`, unchanged,
   into the setup-script field of the cloud environment at claude.ai →
   Settings → Environments.
4. Start a session after the build and read `/home/user/bootstrap.log`.

A version number is never reused for different contents.

Pull requests here target `main`, the default branch, so a `Closes` line in a
description closes its issue when the pull request merges.

A mismatch between the manifest and the clone, the `FAIL
manifest.bootstrap_version` line of `scripts/verify.sh`, means a paste is due.
The comparison does not separate an older pasted copy from a newer one. A copy
pasted from an unmerged branch is the newer case: after the merge `main` holds
the same text, which does not rebuild, so the next bumped change, or a build
another trigger starts, is what delivers it. A match does not mean no paste is
due. A restored session's manifest and clone both come from its snapshot's
build, so they match while `main` carries a later bumped change no paste has
delivered. The `NOTE remote main head` line of `scripts/verify.sh` reports a
clone whose commit differs from `main`'s head on its origin.

The environment variables panel carries the four identity variables
`GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME` and
`GIT_COMMITTER_EMAIL`, and `HARNESS_ASSIGNEE`, the GitHub login that created
issues and pull requests are assigned to. No repository needs attaching.

The facts that fix that order:

* A paste is consumed by the build it triggers. The next build needs a new
  paste.
* Pasting identical text does not rebuild. Only the text the dialog holds is
  compared, so a bump to any other file changes nothing.
* A rebuild clones `main` as it stands at build time, so a paste made before
  the merge spends that version on the old tree.
* A merged change outside `env/setup.sh` is in the clone of the next build
  without a paste. No operator action other than a paste triggers that build.
* A restored session keeps the `/opt/my-harness-wrapper` clone its snapshot was
  built with.
* The only rebuild an operator controls is a change to the pasted text, so a
  change reaches restored sessions only through a paste.
* The first session after a paste builds the snapshot, whatever it is working
  on.
* A session's log describes its own container, so the build's log is read in a
  session started after the build, not in one already running.

This repository is attached only to record or implement an environment change
the user asked for.

### Cloning a different repository

The init script assigns its own default clone URL where `HARNESS_REPO_URL` is
unset or empty. To clone a different repository, edit that default URL in the
pasted copy of `env/setup.sh`. The cloned branch is the `HARNESS_REF` line of
that copy.

### Moving delivery to `main`

Version `0.1.21` of `env/setup.sh` is the first to clone `main` by name.
Pasted copies `0.1.15` through `0.1.20` clone `feat/claude-harness`. Copies
`0.1.14` and earlier clone the default branch. The move runs in this order:

1. Merge the pull request that moves delivery with "Create a merge commit". A
   squash or rebase merge leaves the harness's own commits off `main`, and
   step 4 deletes their only branch.
2. Paste `env/setup.sh` at `0.1.21`, read from `main`, into the cloud
   environment dialog. Start a new cloud session. Its `bootstrap.log` reads
   `HARNESS_REF -> main`, and its session-start check ends
   `verify.sh -> fail -> 0`. A paste before the merge clones the Codex adapter
   tree, delivers no harness, and spends `0.1.21`.
3. From a checkout of `main` at the merge, in Git Bash, run
   `bash scripts/install-local.sh`. It ends `fails -> 0` and leaves the
   deployed copy on `main`.
4. Delete `feat/claude-harness` only after steps 2 and 3. Until the `0.1.21`
   paste, the pasted `0.1.20` clones `feat/claude-harness`, and without that
   branch its clone fails and the build delivers no harness while exiting 0.
5. In the claude.ai Project instruction's harness table, name `main` for the
   Claude harness and `platform/codex` for the Codex adapter.

## Installing locally

The local install is verified on Windows 11 in Git Bash only. macOS and Linux
are untested.

### Prerequisites

| Tool | Requirement |
| --- | --- |
| Git Bash on Windows, bash elsewhere | The installer and every hook command run in it. Claude Code on Windows runs hook commands in Git Bash. |
| Node | ECC's hook commands are `node -e` commands. |
| `git` | `command -v git` resolves and `git --version` exits 0 in the shell the installer runs in; otherwise the installer refuses before any write. The clone URL is reachable; otherwise the installer counts a failure and stops before writing `CLAUDE.md`. |
| `jq` | `command -v jq` resolves and `jq -n 1` prints `1` in the shell the installer runs in; otherwise the installer refuses before any write. Without it in the hook environment the attribution guard exits 0 without scanning. On Windows, `winget install jqlang.jq`, then restart the terminal and the app. |
| `npm` | `command -v npm` resolves in the shell the installer runs in, for the plugin dependency step. It is checked only where a plugin has an unresolved dependency; then an absent `npm` counts one failure and the run goes on. Node's installer ships it. |

A refusal writes only the config directory, where it was absent, and the
install log. It counts one failure per tool that failed.

### Install

From any checkout of this repository, on any branch, in Git Bash:

```
bash scripts/install-local.sh
```

In PowerShell, `bash scripts/install-local.sh` has run a bash that rejects
carriage returns. It printed `set: pipefail\r: invalid option name` and
`line 16: syntax error near unexpected token $'in\r'`, and stopped before line
24, the script's first write, with nothing written. Which bash PowerShell
resolved was not observed. Run it from Git Bash, or,
where Git is in its default location, from PowerShell as:

```
& "C:\Program Files\Git\bin\bash.exe" scripts/install-local.sh
```

It first checks `jq` and `git` as the prerequisites table states, then clones
branch `main` `--depth 1` into the deployed copy, `my-harness-wrapper` in
`${CLAUDE_CONFIG_DIR-$HOME/.claude}`, from `HARNESS_REPO_URL` where it is set
and non-empty and from the default URL in `env/setup.sh` otherwise, and marks
the clone with the local config key
`harness.installer=install-local`. Where a marked deployed copy
exists, it brings it to the branch's remote head instead and removes every
change and untracked file in it. It refuses a deployed copy path that is a
symlink, a linked worktree, or a repository it did not mark; move such a path
aside to install. A failed clone or refresh, or a deployed copy not at that head
and clean afterwards, or with a tracked file still differing from its blob, prints `delivery -> stopped` and ends the run before
`CLAUDE.md` or `settings.json` is written. A refresh that failed after its
fetch can leave the deployed copy moved. Every later step reads the deployed
copy, not the invoking checkout. Use a credential helper rather than a token in
`HARNESS_REPO_URL`: the URL is stored in the deployed copy's `.git/config`.

After a clone or refresh, the installer re-checks out the tracked files from `HEAD`
where any of them differs from its blob. The lines that report it are in the
table below.

It writes `${CLAUDE_CONFIG_DIR-$HOME/.claude}`, the deployed copy under it, the
global git config and the plugin install directories, and nothing else. It
replaces `CLAUDE.md` there whole, and replaces each `hooks.<event>` array that
`config/settings.json` names. The first run that finds a non-empty `settings.json`, or a `CLAUDE.md`
differing from the payload, copies it to `settings.json.pre-harness` or
`CLAUDE.md.pre-harness` beside it; later runs leave that copy alone. The log
also prints each replaced hook array's prior value. Its log is
`.my-harness-wrapper.install.log` in that directory, rewritten on each run. The
installer creates it under `umask 077` and runs `chmod 600` on it.

| Platform | Mode of the log |
| --- | --- |
| Windows 11, NTFS, Git Bash | `-rw-r--r--` from `ls -l`, 644 from `stat -c %a`, after the installer's `chmod 600`. Git Bash derives these values from the file's ACL; they do not establish which accounts can read it. `Get-Acl` lists only inherited allow entries: full control for the owner, `SYSTEM` and `Administrators`, and read and execute for the machine's local `CodexSandboxUsers` group. |
| Linux, macOS | not observed |

Every line prints a predicate and its observed value. The exit status is the
failure count, clamped to 255, and the last line is `fails -> N`. A session
started after the run carries the harness.

| Line | What it means | What to do |
| --- | --- | --- |
| `command -v jq -> none` | `jq` does not resolve on `PATH`. | Install `jq`, restart the terminal, re-run. |
| `jq -n 1 -> exit=N value=[V]` | The `jq` that resolved ran; it passes where `V` is `1`. | Where `V` is not `1`, replace or remove the `jq` that `command -v jq` names. |
| `command -v git -> none` | `git` does not resolve on `PATH`. | Install Git for Windows, or put `git` on `PATH`. |
| `git --version -> exit=N value=[V]` | The `git` that resolved ran; it passes where `N` is 0. | Where `N` is not 0, replace the `git` that `command -v git` names. |
| `prerequisites failing -> <tools>` | The tools that failed the two checks above, or `none`. | Act on each tool's line. |
| `git -C <copy> config --local --get remote.origin.url equals $HARNESS_REPO_URL -> exit=N yes/no` | Whether the deployed copy's stored origin is the clone URL. A URL beginning with `/`, `X:/` or `X:\` is compared in canonical form where `cygpath` exists, so `/d/...`, `D:/...` and an 8.3 or `/tmp` form of one path read `yes`; any other URL is compared exactly. | Where `no`, read the stored value with `git -C <copy> config --get remote.origin.url`. A relative clone URL is stored absolute and reads `no`: give an absolute one. |
| `delivery -> stopped, not written: ...` | The run stopped before the deployed copy, `CLAUDE.md`, `settings.json`, the global git config, the plugins and the manifest. | Fix each failing tool, then re-run. |
| `cygpath -m <copy>/git-hooks -> exit=N value=...` | Printed only where `cygpath` exists. The value the installer writes into `env.GIT_CONFIG_VALUE_0`, in the `C:/...` form git for Windows reads. | Where `N` is not 0 or the value is `empty`, the triple is not written; one failure. Re-run in Git Bash. |
| `test -x <copy>/git-hooks/commit-msg -> yes/no` | Whether the deployed copy carries an executable `commit-msg`. | Where `no`, the copy predates the hooks, is incomplete, or lost the mode; the triple is not written. |
| `jq GIT_CONFIG_* keys of .env in <dir>/settings.json -> exit=N count=C` | The `GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_<n>` and `GIT_CONFIG_VALUE_<n>` keys the live file's `env` holds before the merge. A non-zero `N` counts the file as foreign. | Nothing, unless the next line names something. |
| `GIT_CONFIG_* the installer did not write -> <list>` / `-> none` | Each such variable in the installer's environment, as `environment:<name>=[<value>]`, or in the live file, as `settings:<name>=[<value>]`, that is not the triple the installer writes. | Nothing where `none`. Otherwise find what set it: a value in the shell's profile, or a key another tool or a hand edit put in `settings.json`'s `env`. Remove it, or fold it into a triple that also carries `core.hooksPath` by hand, then re-run. |
| `GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=<dir> git -C <copy> config --get core.hooksPath -> exit=N value=[V]` | Whether this git reads `core.hooksPath` from the variables. It passes where `N` is 0 and `V` is `<dir>`. | Where it fails, the `not written` line follows; update Git. |
| `env.GIT_CONFIG_COUNT, env.GIT_CONFIG_KEY_0, env.GIT_CONFIG_VALUE_0 -> not written, <cause>` | The triple was not written, for the cause named: the conversion failed, `commit-msg` is absent or not executable, another `GIT_CONFIG_*` is set, or git did not read the value; one failure. The merge still writes `env.HARNESS_DIR`, and no harness hook runs in sessions. | Act on the cause, then re-run. |
| `write env.GIT_CONFIG_COUNT, env.GIT_CONFIG_KEY_0, env.GIT_CONFIG_VALUE_0 -> yes/no` | Whether the merge writes the triple. | Nothing; the lines above decide. |
| `jq -r .env.GIT_CONFIG_COUNT, .env.GIT_CONFIG_KEY_0, .env.GIT_CONFIG_VALUE_0 <dir>/settings.json -> exit=N value=[...]` | The three keys read back after the merge, separated by `?`, each `absent` where missing. Where the triple was to be written and they do not read `1`, `core.hooksPath` and the value, one failure. | Read the merge's lines above it. |
| `git config --global --get-all core.hooksPath, before -> exit=N value=[...]` / `, after -> ...` | The global values before and after the migration. Exit 1 means unset; above 1 counts one failure. | Nothing, unless a `not run` line with a failure sits between them. |
| `global core.hooksPath values naming <copy>/git-hooks -> N, other values -> M` | How many global values name the deployed copy's hooks in any spelling, and how many name another directory. | Nothing. |
| `git config --global --unset-all core.hooksPath -> exit=N` | The removal of the value an earlier install wrote. A non-zero `N` is one failure. | Read the global config file's permissions. |
| `git config --global --unset-all core.hooksPath -> not run, no global value names <copy>/git-hooks` | Nothing to migrate. A value naming another directory stays: git commands outside sessions use it, and inside sessions forwarding runs the hooks it names. | Nothing. |
| `git config --global --unset-all core.hooksPath -> not run, the global read failed (exit=N)` | The `before` read exited above 1, already counted as one failure. | Read the global config file's permissions and syntax, then re-run. |
| `global core.hooksPath values naming <copy>/git-hooks, after -> N` | `N` values still name the deployed copy after the unset, such as one an `[include]` file carries; one failure where no other value was found. | Run `git config --global --show-origin --get-all core.hooksPath`, remove the value from the file it names, then re-run. |
| `git config --global --unset-all core.hooksPath -> not run, the global values also name another path` | The global config holds several values, one of them the deployed copy's; one failure. | Remove the deployed copy's value by hand with `git config --global --unset core.hooksPath <value>`, then re-run. |
| `tracked files in <copy> whose bytes differ from their blob, before the renormalize -> exit=0 count=N of M regular files, the first up to 5 [<paths>]` | After the clone or refresh, `N` of the `M` regular tracked files differ from their blobs. `count=0` means nothing is re-checked out. | Nothing where `N` is 0. Otherwise the `git` lines below run. |
| `tracked files in <copy> whose bytes differ from their blob, before the renormalize -> exit=N count=unread, <cause>` | The measurement failed, and the run stops with one failure. The causes are `git ls-files -s failed`, `git hash-object --no-filters --stdin-paths failed`, and a hash count other than the file count. A tracked file missing from the copy gives the `hash-object` failure. | Run `git -C <copy> ls-files -s` and `git -C <copy> status` by hand for the error. |
| `git -C <copy> rm -q -r --cached -- . -> exit=N` | The index entries are removed and the files are left in place. A non-zero `N` is one failure. | Read git's message above the line. |
| `git -C <copy> reset -q --hard HEAD -> exit=N` | The tracked files are written from `HEAD`. A non-zero `N` is one failure. | Read git's message above the line. |
| `tracked files in <copy> whose bytes differ from their blob, after the renormalize -> exit=0 count=C of M regular files, ...` | The second measurement. `count=0` passes. A count above zero, or a failed measurement, is one failure and the run stops. | Run `git -C <copy> show HEAD:.gitattributes`. Where it fails, the deployed copy's `HEAD` does not hold `.gitattributes`: `main` must carry that file, then re-run the installer. |
| `git -C <copy> rm -q -r --cached -- . and git -C <copy> reset -q --hard HEAD -> not run, no tracked file differs from its blob` | Nothing was re-checked out. | Nothing. |

The plugin step finds the CLI on `PATH`, then at `CLAUDE_CODE_EXECPATH`, then
as the `claude.exe` with the highest `<version>` among
`$LOCALAPPDATA/Claude-Data/*/claude-code/<version>/<build>/claude.exe`. The app
data directory name is any name, such as `claude_<id>` or `anthropicpbc.claude_<id>`.
The `desktop app CLIs under ... -> count=N` line counts the candidates, and the
`claude CLI ->` line names the one used. Where none is found, each plugin's line
names the two commands to run instead, and each counts as a failure.

After each plugin's install or update the plugin step runs the dependency step,
`scripts/plugin-dependencies.sh`. Its lines appear in the install log and, in
the cloud, in `/home/user/bootstrap.log`.

Bootstrap prints the list, `installed before this run`, marketplace update and
plugin update lines for its rows too, in `/home/user/bootstrap.log`. It prints no
desktop app line and no content comparison.

| Line | What it means | What to do |
| --- | --- | --- |
| `plugin dependencies of <id> -> claude CLI <cli>` | The dependency step started for that plugin with that CLI. | Nothing. |
| `plugin dependencies -> not run, plugin_id or CLI empty` | An argument was empty; one failure. | Report it as a defect in the calling script. |
| `claude plugin list --json -> exit=N` | The CLI's plugin list exit status. A non-zero `N` stops the step with one failure. | Run `claude plugin list --json` by hand for the error. |
| `jq installPath of <id> from claude plugin list --json -> exit=N count=C value=[...]` | The distinct `installPath` values listed for that id. It passes where `N` is 0 and `C` is 1. The content comparison of a shipped plugin prints the same line. | `C` 0: the plugin is not installed; read its `claude plugin install` line above. `C` above 1: the id is listed with different paths; read `claude plugin list --json`. |
| `cygpath -u <path> -> exit=N value=[...]` | Printed only where `cygpath` exists. The `installPath` converted to the `/c/...` form. | Nothing. |
| `installPath <path> is an absolute path -> no` | The path, converted where possible, is relative; one failure. | Read the `jq installPath` line above. |
| `test -d <path> -> no` | No directory at the `installPath`; one failure. | Reinstall the plugin. |
| `test -f <path>/package.json -> no` | The plugin carries no `package.json`, so it declares no npm dependency. `npm ci in <path> -> not run, no package.json` follows, and the step passes. | Nothing. |
| `jq .dependencies keys <path>/package.json -> exit=N count=C` | `C` names declared. A non-zero `N` means the file does not parse, its top level is not an object, or `dependencies` is not an object; one failure. | Report it to the plugin's maintainers. |
| `dependency name [<name>] matches <pattern> -> no` | A declared name is outside the npm name form; one failure, nothing installed. | Report it to the plugin's maintainers. |
| `test -f <path>/node_modules/<name>/package.json -> yes` or `-> no` | Whether that dependency resolves under the `installPath`. | Nothing; the lines after it decide. |
| `unresolved dependencies of <id> -> <names>` | The names whose test read `no`, or `none`. | Nothing. |
| `npm ci in <path> -> not run, every declared dependency resolves` | Every declared dependency resolves, so nothing runs and the step passes. | On a fresh install, see "Removing the dependency step". |
| `command -v npm -> none` | `npm` does not resolve while a dependency is unresolved; one failure. | Install Node with `npm`, then re-run the installer. |
| `npm ci --omit=dev --ignore-scripts --no-audit --no-fund in <path> -> exit=N` | npm's exit status; npm's own output is above it. A non-zero `N` is one failure. | Read npm's error above it. |
| `unresolved dependencies of <id> after npm ci -> <names>` | The names still unresolved after `npm ci`. Any name is one failure. | Read npm's output above it. |
| `bash <dir>/scripts/plugin-dependencies.sh <cli> <id> -> exit=N` | The step's result as the installer counts it: 0 passes, 1 is one failure. | Read the step's lines above it. |
| `bash <dir>/scripts/plugin-dependencies.sh <CLI> <id> -> not run, no CLI` | No CLI was found, so the step did not run; one failure. | Act on the `claude CLI -> none` line. |
| `desktop app CLIs under <pattern> -> count=N` / `desktop app CLIs under <pattern> -> not searched, <reason>` | The `claude.exe` candidates under `$LOCALAPPDATA/Claude-Data`, which `scripts/verify.sh` also prints. `not searched` gives the reason: an earlier rule found the CLI, or `LOCALAPPDATA` is unset or empty, or `cygpath` is absent. | Nothing, unless `claude CLI -> none` follows. Then `count=0` means no `claude.exe` matched. |
| `claude plugin list --json, before the plugins.tsv rows -> exit=N` / `claude plugin list --json, before the plugins.tsv rows -> not run, no CLI` | The installed ids, read once before the rows. A non-zero `N` is not counted itself. | Where `N` is not 0, each row takes the add and install path, and its own exits count. Run `claude plugin list --json` by hand for the error. |
| `jq .[].id of that output -> exit=N value=[...]` | The ids read from that list, space-separated. | Where `N` is not 0, read the list line above it. |
| `plugin_id <id> installed before this run -> yes` / `... -> no` / `... -> unknown, claude plugin list --json was not read, treated as not installed` | `yes` takes the update path, and `no` the add and install path. `unknown` means the list was not read. | Nothing where `yes` or `no`. With `unknown`, read the list line above. |
| `claude plugin marketplace update <marketplace> -> exit=N` | The update of an installed plugin's marketplace, which re-clones it. A non-zero `N` is one failure. | Run `claude plugin marketplace update <marketplace>` by hand for the error. |
| `claude plugin marketplace update <marketplace> -> not run, plugin_id <id> names no marketplace after an @` | An installed row whose id names no marketplace. One failure, and no update runs. | Fix the row in `config/plugins.tsv`. |
| `claude plugin update <id> -> exit=N` | The update of an installed plugin. The CLI prints `already at the latest version` where the version is unchanged. A non-zero `N` is one failure. | Run `claude plugin update <id>` by hand for the error. Where it printed `already at the latest version`, the comparison below decides whether the files changed. |
| `test -d <copy>/plugins/<name> -> yes, a shipped plugin` / `test -d <copy>/plugins/<name> -> no, not a shipped plugin` | Whether the deployed copy ships the plugin. `no` skips the comparison and the marketplace measurement. | Nothing. |
| `claude plugin list --json, after the update or install of <id> -> exit=N` | The list read for the comparison. A list that yields no single `installPath` reads `not measured` in the comparison, and the plugin is not reinstalled. | Where `N` is not 0, run `claude plugin list --json` by hand. |
| `git -C <copy> ls-tree -r --full-name HEAD -- plugins/<name>/ -> exit=N entries=M` | The committed entries under the plugin's directory in the deployed copy. A non-zero `N` is a failed measurement. `scripts/verify.sh` prints the same line. | Run `git -C <copy> ls-tree -r --full-name HEAD -- plugins/<name>/` by hand for the error. |
| `find <installPath> -type f, .in_use excluded -> exit=N files=M` | The files under the installed plugin, with `.in_use` directories pruned. A non-zero `N` is a failed measurement. `scripts/verify.sh` prints the same line. | Read the message `find` printed above the line. |
| `git -C <installPath> hash-object --no-filters --stdin-paths over those files -> exit=N hashes=M` | The hashes of the files the `find` line counts. A non-zero `N`, or `M` other than that count, is a failed measurement. `scripts/verify.sh` prints the same line. | Reproduce the hashing by hand over the files `find` lists. |
| `compare the files under the installPath of <id> against <copy> HEAD:plugins/<name> -> yes, N files` | The installed files equal the blobs at the deployed copy's `HEAD`. `N` is the number of those blobs. | Nothing. |
| `compare the files under the installPath of <id> against <copy> HEAD:plugins/<name> -> no, <detail>` | The installed files differ. The `<detail>` is `differing=N [<paths>] missing=N [<paths>] extra=N [<paths>], up to 5 named each`. | Nothing here. The uninstall and install lines follow, and the comparison after them decides. |
| `compare the files under the installPath of <id> against <copy> HEAD:plugins/<name> -> not measured, <detail>; no reinstall` | A measurement failed. One failure, and the plugin is left as installed. The `<detail>` is one of `jq exit=N read M installPath values for <id>`, `the installPath of <id> is not an absolute path`, `the installPath <path> of <id> is not a directory`, `git ls-tree exit=N`, `HEAD has no regular files under plugins/<name>/`, `find exit=N`, `git hash-object exit=N gave H hashes for F files`, `the name before the @ of <id> does not match <pattern>`. | Read the measurement line above it with a non-zero exit, and run that command by hand. |
| `claude plugin uninstall <id> --scope user -> exit=N` | The removal before a reinstall. A non-zero `N` is one failure. | Run it by hand for the error. |
| `claude plugin install <id> --scope user --yes -> exit=N` | The reinstall after an uninstall. A non-zero `N` is one failure. | Run it by hand for the error. |
| `claude plugin list --json, after the reinstall of <id> -> exit=N` | The list read for the comparison after the reinstall. | As for the list line after the update or install. |
| `compare the files under the installPath of <id> against <copy> HEAD:plugins/<name>, after the reinstall -> yes, N files` / `... -> no, <detail>` | The comparison after the reinstall. `no` is one failure. The reinstall copies from the marketplace clone, so a clone whose files differ from the deployed copy's `HEAD` reads `no` here. | Where `no`, read the detail, then the marketplace clone lines below. |
| `jq .["<marketplace>"].installLocation <config dir>/plugins/known_marketplaces.json -> exit=N value=[<dir>]` | The clone directory the CLI keeps for the marketplace. An empty value with `exit=0` means the file names no such marketplace. | Where the value is empty or `N` is not 0, the next line reads `not measured`. Read the file. |
| `installLocation of the marketplace of <id> -> not read, plugin_id names no marketplace after an @` | A shipped plugin's row whose id names no marketplace. One failure. | Fix the row in `config/plugins.tsv`. |
| `tracked files in the clone of marketplace <marketplace> whose bytes differ from their blob -> not measured, no single installLocation directory read from <file>` | The clone was not measured. One failure. | Read the `installLocation` line above it. |
| `git -C <dir> rev-parse --show-cdup -> exit=N value=[<path>]` | `<dir>` is the top level of its work tree where `N` is 0 and the value is empty. Otherwise the clone counts one failure with no further line. | Where the value is not empty, `installLocation` names a subdirectory of a repository: read the `installLocation` line above. Where `N` is not 0, the value holds git's first error line. |
| `tracked files in <dir>, the clone of marketplace <marketplace>, whose bytes differ from their blob -> exit=0 count=N of M regular files, ...` | The clone's tracked files that differ from their blobs. Nothing re-checks out the clone, so `N` above zero is one failure. A `count=unread` form reads as in the deployed copy's row. | Run `claude plugin marketplace update <marketplace>`, which re-clones the marketplace, then re-run the installer. |

### Removing the dependency step

The dependency step can be deleted once a fresh install, into a config
directory with no copy of the plugin, logs
`npm ci in <path> -> not run, every declared dependency resolves` for every
plugin. The plugin or the CLI then delivers the dependencies itself. A re-run
over an existing install logs the same line after an earlier `npm ci`, so only
a fresh install shows it.

### Removing a local install

Remove the hooks path first. A `core.hooksPath` naming a deleted directory makes
git find no hooks at all, so every repository's own hooks stop running without
any message.

1. Remove `env.GIT_CONFIG_COUNT`, `env.GIT_CONFIG_KEY_0` and
   `env.GIT_CONFIG_VALUE_0` from `${CLAUDE_CONFIG_DIR-$HOME/.claude}/settings.json`,
   with no session running.
2. Read the global value an install before the triple left:

   ```
   git config --global --get core.hooksPath
   ```

3. Where it names `${CLAUDE_CONFIG_DIR-$HOME/.claude}/my-harness-wrapper/git-hooks`,
   in any spelling, unset it:

   ```
   git config --global --unset core.hooksPath
   ```

4. In `${CLAUDE_CONFIG_DIR-$HOME/.claude}`, move `CLAUDE.md.pre-harness` and
   `settings.json.pre-harness` back over `CLAUDE.md` and `settings.json` where
   they exist; otherwise remove `CLAUDE.md`, and remove from `settings.json` the
   keys `config/settings.json` carries and `env.HARNESS_DIR`.
5. Remove `my-harness-wrapper`, `.my-harness-wrapper.manifest.json`,
   `.my-harness-wrapper.install.log` and `session-check.log` there.
6. Uninstall the harness's own plugin and remove its marketplace. The payload
   removed in step 4 is what names its skill:

   ```
   claude plugin uninstall my-harness@my-harness-wrapper
   ```

   ```
   claude plugin marketplace remove my-harness-wrapper
   ```

7. Optionally uninstall the other plugins `config/plugins.tsv` names with
   `claude plugin uninstall <plugin_id>`, and unset `commit.gpgsign` and
   `tag.gpgsign` globally.

A copy of the plugin installed through claude.ai is removed there, not by
these steps.

### Update

```
bash scripts/install-local.sh
```

Run from any checkout, on any branch. The hook commands run the scripts in the
deployed copy, so a merge to `main` reaches local sessions only when the
installer runs again. A branch switch, a pull or an edit in a checkout
changes no session.

For each plugin already installed, the installer runs `claude plugin marketplace
update <marketplace>`, then `claude plugin update <plugin_id>`. A version bump in
`plugins/my-harness/.claude-plugin/plugin.json` that has reached the marketplace
clone therefore takes effect on the next run, with no `claude plugin` command
run by hand. A shipped plugin whose installed files differ from the deployed copy
is uninstalled and installed again. The plugin comes from the marketplace clone
named in `config/plugins.tsv`, not from the deployed copy.

### Renormalizing a Windows checkout

A checkout of this repository made before `.gitattributes` was committed keeps
CRLF line endings, and its `git ls-files --eol` reads `w/crlf`. Run these steps
once, from that checkout, after its `HEAD` holds `.gitattributes`. Without that
file in `HEAD`, the reset writes CRLF again under `core.autocrlf=true`.

1. Commit or stash every local change. `git reset --hard` discards uncommitted
   changes.
2. Run:

   ```
   git rm -r --cached -q .
   git reset --hard HEAD
   ```

3. Run `git ls-files --eol`. Every text file reads `w/lf`.

### Verify

```
d="${CLAUDE_CONFIG_DIR-$HOME/.claude}/my-harness-wrapper"; HARNESS_DIR="$d" bash "$d/scripts/verify.sh"
```

A local session's hook processes carry `HARNESS_DIR` from `settings.json`, so
the session-start check needs no setting.

## Packaging the plugin for claude.ai

The package is the form in which the `my-harness` plugin is uploaded to
claude.ai for Cowork sessions. Issue #72 records what was observed in a Cowork
session: no `CLAUDE.md`, no harness manifest, and ECC present under
`~/.claude/plugins/synced/`.

1. From a checkout of `main` at the merge, write the package. It is a zip of
   the contents of `plugins/my-harness/`, named `my-harness.plugin`, with
   `.claude-plugin/plugin.json` at the archive root:

   ```
   git archive --format=zip --output=my-harness.plugin main:plugins/my-harness
   ```

2. Upload `my-harness.plugin` through claude.ai and accept it there.
3. Repeat both steps after every change to the plugin.

`git archive` packs the committed tree, so an uncommitted edit is not in the
package. The package is not committed to this repository.

| Fact | State |
| --- | --- |
| The command writes a zip holding `.claude-plugin/plugin.json`, `agents/`, `hooks/` and `skills/` at its root | Verified with git 2.56 in Git Bash. |
| claude.ai accepts the package and a Cowork session loads it | Not verified. It cannot be exercised from a Claude Code session. |
| A Claude Code session holding both an installed plugin and a synced copy of the same name | Observed for `ecc` only: `claude plugin list` reports `ecc@synced` as not loaded because the installed `ecc@ecc` takes precedence. Not observed for `my-harness`, and the line reports the list's state, not what a session loaded. |

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
CLI it found and its version, the installed plugins and the manifest, then runs
the checks below.
The exit status is 1 where any check failed and 0 otherwise; a check that exits
early also exits 1. It is not a count. A `NOTE` line can appear alongside exit 0
and does not set the exit status.

Two checks exit immediately and stop the run: `FAIL live config dir path` and
`FAIL manifest: ... actual absent`. Every other check runs to the end.

| Line | What it means | What to do |
| --- | --- | --- |
| `FAIL live config dir path` | The resolved config directory is not an absolute path. `CLAUDE_CONFIG_DIR` holds an empty or relative value, or it is unset and `HOME` is relative. The `CLAUDE_CONFIG_DIR ->` line above separates `unset`, `set but empty` and a value. | Unset it, or set an absolute path. |
| `cygpath -u <dir> -> exit=N value=...` | Printed only where `cygpath` exists, as in Git Bash. The resolved config directory converted to the `/c/...` form; a Windows hook process receives `CLAUDE_CONFIG_DIR` as `C:/...`. A non-zero exit or empty value keeps the unconverted path. | Nothing, unless `FAIL live config dir path` follows it. |
| `claude CLI -> none from none` | No CLI was found on `PATH`, at `CLAUDE_CODE_EXECPATH`, or under `$LOCALAPPDATA/Claude-Data`. The plugin list then reads exit 127. | Act on the `FAIL live config dir agreement: ... could not tell` line it produces. |
| `readlink -f, cygpath -m -l, ASCII lowercased <dir> -> <path>`, or `readlink -f <dir> -> <path>` without `cygpath` | The resolved config directory in the canonical form every path comparison uses: 8.3 short names and the `/tmp` mount expanded to the long Windows form, ASCII letters lowercased. `unresolved` where a step produced nothing. The `resolves to` values in `FAIL manifest.config_dir` and `FAIL hook harness dir`, and the top-level check, use the same form. | Nothing, unless a `FAIL` naming a path follows. |
| `jq -r .env.HARNESS_DIR <settings> -> ... value=absent` | The live `settings.json` carries no `env.HARNESS_DIR`, so the two guard checks run the hook commands with `HARNESS_DIR` unset, as a cloud session does. | Expected in the cloud. Locally, re-run `scripts/install-local.sh`. |
| `FAIL hook harness dir` | The live `env.HARNESS_DIR` and the repository under test resolve to different directories, so the hooks run another tree's scripts. | Run `scripts/verify.sh` with `HARNESS_DIR` naming the deployed copy, `${CLAUDE_CONFIG_DIR-$HOME/.claude}/my-harness-wrapper`, or re-run `scripts/install-local.sh`. A value naming a working checkout is an install older than the deployed copy. |
| `FAIL manifest: ... actual absent` | No bootstrap has run in the resolved config directory. | Read `/home/user/bootstrap.log`. The setup script was never pasted, the snapshot predates it, or the CLI reads a directory bootstrap never wrote. Locally, run `scripts/install-local.sh`. |
| `FAIL manifest.commit`, both sides a commit | Bootstrap ran against an older commit than the repository now holds. | Expected while the snapshot is frozen. Where the delta touches `config/`, `scripts/` or `env/`, a paste is due. |
| `FAIL manifest.commit: ... actual unresolved-manifest` | The manifest carries no readable `commit` field. | Re-run bootstrap. The manifest was hand-edited or its write failed. |
| `FAIL manifest.commit: expected unresolved-repo` | `git -C <repo> rev-parse --short HEAD` produced nothing, so the repository being checked is absent or is not a git repository. | Read the path in the line. The deployed copy is missing, or `HARNESS_DIR` names something else. The two sides carry different defaults, so two unknowns never compare equal and pass. |
| `git -C <repo> rev-parse --show-toplevel names <repo> -> ...` | Whether the repository under test is the top level of its own work tree: `yes`, `no, the top level is [<path>]`, `no, the top level [<path>] did not resolve through canon_path`, `unreadable (git exit=N)`, or `repo unreadable` where the `rev-parse --git-dir` line above is non-zero. Anything but `yes` fails both checks below without running them. | Read the path. `HARNESS_DIR` names a directory inside another repository, or the deployed copy lost its `.git`. |
| `git -C <repo> symbolic-ref -q HEAD -> ...` | The repository under test's branch as a full ref: `[refs/heads/<name>]`, `detached HEAD (git exit=1)`, `unreadable (git exit=N)`, or `not read`. | Nothing, unless `FAIL deployed copy branch` follows it. |
| `FAIL deployed copy branch` | The repository under test is not on `refs/heads/main`, is detached, is not the top level of its work tree, or git could not read its branch. | Locally, re-run `scripts/install-local.sh`, which checks the branch out at its remote head. In the cloud, rebuild. Where the repository under test is a working checkout, run against the deployed copy instead. |
| `git -C <repo> status --porcelain --untracked-files=all --ignore-submodules=none -> ...` | The repository under test's uncommitted and untracked entries against its own `HEAD`: `no entries`, a count with up to five entries of up to 120 bytes each joined by ` \| `, `unreadable` with git's first error line, `unreadable, git wrote to stderr`, `timed out after 10s`, or `not read`. | Nothing, unless `FAIL deployed copy changes` follows it. |
| `git -C <repo> ls-files -v, entries marked skip-worktree or assume-unchanged -> N` | How many index entries hide their file from `status`, `unreadable (git exit=N)`, or `not read`. | Nothing, unless `FAIL deployed copy changes` follows it. |
| `FAIL deployed copy changes` | The repository under test has an entry differing from its `HEAD`, an index entry marked skip-worktree or assume-unchanged, or a status git could not read in full. A forced hook install, such as `git lfs install --force` or `git lfs update --force`, produces entries under `git-hooks/` for the hook names it writes; any other write into `git-hooks/` produces the same entries. A changed hook file that no longer sources `lib/dispatch.sh` forwards to nothing, so every repository's own hook of that name has stopped running. | Entries under `git-hooks/`: read the first lines of each changed file to see what wrote it, then, locally, re-run `bash scripts/install-local.sh`; in the cloud, run `git -C /opt/my-harness-wrapper checkout -- git-hooks`. Other entries: in the cloud, read them, since nothing in this repository writes into the clone; locally, re-run `bash scripts/install-local.sh`, which discards them. Where the repository under test is a working checkout, run against the deployed copy instead. |
| `git -C <repo> rev-parse --verify -q HEAD -> [<sha>]` | The deployed commit, in full. `unreadable (git exit=N) [...]`, or `not read, repo unreadable`, where git gave no commit. | Nothing; the `NOTE remote main head` or `compare the deployed commit` line below decides. |
| `git ls-remote -- <origin URL of <repo>> refs/heads/main, under timeout 5s -> [<sha>]` | The head of `main` on the URL the deployed copy's `remote.origin.url` names, read from outside the copy with a 5-second bound and no credential prompt. `not read` states: `timed out after 5s (exit=124)`, `(timeout or env exit=N)`, `(git exit=N)`, `no refs/heads/main line (git exit=0)`, `command -v timeout -> none`, `git ... config --get remote.origin.url -> exit=N` or `-> exit=0 value=empty`, or `repo unreadable`. The origin URL is never printed. | Nothing; the line below decides. |
| `compare the deployed commit against the head of refs/heads/main on origin -> yes, both <sha>` | The deployed copy is at `main`'s head on its origin. It does not establish that the `env/setup.sh` pasted into the environment dialog matches `main`'s. | Nothing. |
| `NOTE remote main head: ... actual <sha>; not counted into the exit status` | The deployed commit differs from `main`'s head on its origin. The states that produce it include a cloud clone that predates a merge to `main`, a local install not re-run since `main` moved, an origin `main` that was rewound, a deployed copy holding commits not on origin's `main`, and an origin URL naming another repository than the one the copy was cloned from. It does not establish that the difference touches `config/`, `scripts/` or `env/`, or that a paste is due: a merge changing only documentation reads the same. | In the cloud, run `git log --oneline <deployed>..main -- config scripts env` in an up-to-date checkout of `main`; where it lists a commit, paste `env/setup.sh` from `main`. Locally, re-run `scripts/install-local.sh`. |
| `NOTE remote main head: expected a head from ... actual not read ...` / `... expected the deployed commit ...` | The comparison did not run: the remote head or the deployed commit was not read. Not counted into the exit status. | Read the state. `timed out` means the read ran past its bound. `git exit=N` is a failed `git ls-remote` whose cause is not captured: an unreachable host, refused authentication, a missing repository and a TLS error read the same; run `git ls-remote <URL> refs/heads/main` by hand for the error. |
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
| `FAIL PreToolUse attribution guard` | The first live `PreToolUse` command naming `attribution-guard.sh` did not exit 2 on a `gh pr create` body carrying the Claude Code footer. The state ends the line: `exit=N` for a command that ran, `exit=2 without <marker>` for one that exited 2 without the guard's own stderr marker, `no PreToolUse command in <path> references attribution-guard.sh (jq exit=N)`, or `sample input not built (jq exit=N)`. | Read the state. `no PreToolUse command` reads the same for a live `settings.json` that registers no command naming the guard and for one `jq` could not read; the `(jq exit=N)` suffix separates them, `0` for the first and non-zero for the second. On either, the snapshot predates the hook: re-paste `env/setup.sh` and rebuild. `exit=0` means the hook is registered and the guard is not at the path it names: in a local install, read the `jq -r .env.HARNESS_DIR` line above, since an absent value sends the command to `/opt/my-harness-wrapper`. `exit=2 without <marker>` means the registered command is broken shell, `bash -c` exiting 2 on a syntax error. |
| `run the live <event> command on <clean input> -> ...` | The first live `PreToolUse` or `PostToolUse` command naming `attribution-guard.sh`, run on an input carrying no footer: a `gh pr create` body for `PreToolUse`, a `mcp__github__create_pull_request` response `body` for `PostToolUse`. `exit=0`, or `exit=N [<first stderr line>]`, or one of the two not-run states the footer check prints. | Nothing, unless `FAIL <event> attribution guard: expected exit=0` follows it. |
| `FAIL PreToolUse attribution guard: expected exit=0 ... on a gh pr create body without the footer` / `FAIL PostToolUse attribution guard: expected exit=0 ... on a create response whose body carries no footer` | That command did not exit 0 on the clean input the line names. A command that blocks every input fails here while passing the footer check. | Read the state. `exit=2` carrying the guard's marker means the registered command or the guard it runs blocks clean bodies: compare the live hook command with `config/settings.json`, and the guard at the path it names with `scripts/attribution-guard.sh`. The not-run states read as for the footer check. |
| `FAIL PostToolUse attribution guard` | The first live `PostToolUse` command naming `attribution-guard.sh` did not exit 2 on a `mcp__github__create_pull_request` response whose `body` carries the Claude Code footer. The state ends the line in the same four forms as `FAIL PreToolUse attribution guard`, the marker being `attribution-guard: matched line in the response body ->`. The guard prints that marker only on a footer match, so exit 2 from its size cap or from a response with no `body` fails the check. | Read the state as for `FAIL PreToolUse attribution guard`. `exit=0` also means the guard at the path the command names predates its `PostToolUse` path: re-paste `env/setup.sh` and rebuild. |
| `FAIL config/plugins.tsv` | No file at that path under the repository being checked. | Read the `test -f` line above it. The deployed copy is absent, incomplete, or `HARNESS_DIR` names another tree. |
| `FAIL plugin: ... among the installed ids` | A plugin named in `config/plugins.tsv` is not among the ids `claude plugin list --json` reports. | Read the `claude plugin install ... -> exit=` line in `/home/user/bootstrap.log`, then re-run the install by hand for the current error. |
| `FAIL plugin: ... expected an id list` | No id list could be read, so the plugin could not be tested. | Act on the `FAIL live config dir agreement` line above it. |
| `jq installPath of <id> from claude plugin list --json -> exit=N count=C value=[...]` | Printed for each listed `config/plugins.tsv` plugin, and again by the content comparison of a shipped plugin: the distinct `installPath` values the list carries for it. | Nothing, unless `FAIL plugin installPath` follows it. |
| `FAIL plugin installPath: expected one installPath` | The list carries no `installPath` for that id, or several different ones, or `jq` could not read it. | Read `claude plugin list --json` by hand. Re-run the installer, or rebuild in the cloud. |
| `FAIL plugin installPath: expected an absolute installPath` | The `installPath`, converted with `cygpath -u` where it exists, is relative. | Read `claude plugin list --json` by hand. |
| `test -d <path> -> yes` or `-> no` | Whether a directory exists at the `installPath`. | Nothing, unless `FAIL plugin installPath` follows it. |
| `FAIL plugin installPath: expected a directory` | The CLI lists the plugin at a path that does not exist. | Re-run the installer, or rebuild in the cloud. |
| `test -f <path>/package.json -> yes` or `-> no` | Whether the plugin carries a `package.json`. `no` means it declares no npm dependency, and nothing further is checked for it. | Nothing. |
| `jq .dependencies keys <path>/package.json -> exit=N count=C` | `C` dependency names declared. | Nothing, unless `FAIL plugin dependencies` follows it. |
| `FAIL plugin dependencies: expected an object or no dependencies key` | The plugin's `package.json` does not parse, its top level is not an object, or its `dependencies` is not an object. | Report it to the plugin's maintainers. |
| `FAIL plugin dependency: expected a package name matching` | A declared name is outside the npm name form, so no path was tested for it. | Report it to the plugin's maintainers. |
| `test -f <path>/node_modules/<name>/package.json -> yes` | That declared dependency resolves under the `installPath`. | Nothing. |
| `test -f <path>/node_modules/<name>/package.json -> no` | That declared dependency does not resolve. `FAIL plugin dependency` follows it. | Act on the `FAIL` line. |
| `FAIL plugin dependency: expected <name>, declared by <id>, to resolve` | No `node_modules/<name>/package.json` under the `installPath`; the plugin's code that requires it fails to load, ECC's `SessionStart` hook among it. | Locally, re-run `scripts/install-local.sh` and read its dependency step lines. In the cloud, read those lines in `/home/user/bootstrap.log`, then rebuild. |
| `jq enabled of <id> from claude plugin list --json -> exit=N value=[...]` | Printed for each listed `config/plugins.tsv` plugin: the distinct `enabled` values the list carries for it, space-separated. | Nothing, unless `FAIL plugin enabled` follows it. |
| `FAIL plugin enabled` | The plugin is installed and an entry for it does not carry `enabled` true: it is disabled at some scope, the field is absent, or `jq` could not read the list. | Run `claude plugin enable '<id>'`, then start a new session. |
| `test -d <repo>/plugins/<name> -> yes` or `-> no` | Whether the repository under test ships that plugin. `no` means it ships none, as for `ecc@ecc`, and no version is compared. | Nothing. |
| `test -f <repo>/plugins/<name>/.claude-plugin/plugin.json -> yes` or `-> no` | Whether the shipped plugin directory holds a manifest. | Nothing, unless `FAIL plugin version: expected a manifest` follows it. |
| `FAIL plugin version: expected a manifest` | The repository under test holds `plugins/<name>` without `.claude-plugin/plugin.json`. | Fix the tree. This is a repository fault, not a session fault. |
| `jq .version <manifest> -> exit=N value=[...]` | The version the repository under test ships for that plugin. | Nothing, unless `FAIL plugin version: expected one non-empty string version` follows it. |
| `FAIL plugin version: expected one non-empty string version` | The shipped `plugin.json` does not parse, its top level is not an object, or its `version` is absent, empty or not a string. | Fix the tree. This is a repository fault, not a session fault. |
| `jq version of <id> from claude plugin list --json -> exit=N count=C value=[...]` | The distinct installed versions the list carries for that id. | Nothing, unless `FAIL plugin version: expected one installed version` follows it. |
| `FAIL plugin version: expected one installed version` | An entry for that id carries a version that is not a string, the entries carry several different versions, or `jq` could not read the list. `count=0` with a non-zero exit is the first or the last. | Read `claude plugin list --json` by hand. |
| `FAIL plugin version: expected <id> installed at version` | The installed plugin's version differs from the one the repository under test ships. The states that produce it include an installer run that predates a version bump, and a repository under test older than the installed plugin. | Locally, re-run `scripts/install-local.sh`, which updates the installed plugin, then start a new session. Where the versions still differ, read `claude plugin list --json` by hand. In the cloud, rebuild. |
| `FAIL plugin version: expected the name` | The id's part before `@` falls outside `[A-Za-z0-9][A-Za-z0-9._-]*`, so no manifest path was built from it. | Fix the row in `config/plugins.tsv`. |
| `compare the installed version of <id> against <manifest> -> yes, both <version>` | The installed plugin and the repository under test carry the same version. Their files are compared by the content check below. | Nothing. |
| `compare the files under the installPath of <id> against <repo> HEAD:plugins/<name> -> yes, N files` | The files under the installed plugin equal the blobs at `$REPO` HEAD, `N` in number. | Nothing. |
| `FAIL plugin contents: expected the files under the installPath of <id> to equal <repo> HEAD:plugins/<name>, actual <detail>` | The installed files differ from the blobs at `$REPO` HEAD, a file is missing or extra, or a measurement failed. The `<detail>` has the forms listed under `scripts/install-local.sh`'s plugin table. Shipped plugins only. | Locally, re-run `scripts/install-local.sh`, which reinstalls the plugin. In the cloud, rebuild. |
| `git -C <repo> ls-tree ...`, `find <installPath> ...`, `git -C <installPath> hash-object ...` | The measurements behind the content check, with the same meaning as in the `scripts/install-local.sh` plugin table. | Nothing, unless `FAIL plugin contents` follows. |
| `FAIL git AUTHOR variables` / `FAIL git COMMITTER variables` | That role's `GIT_*_NAME` or `GIT_*_EMAIL` is unset or empty. The line above names which, and separates the two. | Set both in the environment variables panel. Nothing in this repository supplies an identity. |
| `FAIL git AUTHOR identity` / `FAIL git COMMITTER identity`, `... expected an identity of the form Name <email>` | `git var` returned nothing usable for that role. | Read the state on the line above. An empty `GIT_*_NAME` exits 128; a repository git will not read is reported as such. |
| `FAIL git AUTHOR identity` / `FAIL git COMMITTER identity`, `... from that role's GIT_*_NAME and GIT_*_EMAIL` | Git did not resolve that role to the pair the session was given. | Check for a `GIT_CONFIG_KEY_n` overlay or a repository-local `user.*`. |
| `FAIL git AUTHOR identity` / `FAIL git COMMITTER identity`, `... other than the harness default` | The identity is the harness's own, not the operator's. | The panel pair is absent or holds that address, so `git var` fell through to `/root/.gitconfig`. Set the four variables in the panel. |
| `GIT_AUTHOR_EMAIL address form -> yes` / `GIT_COMMITTER_EMAIL address form -> yes` | That variable is set and holds the address form. | Nothing. |
| `FAIL git AUTHOR email` / `FAIL git COMMITTER email` | That role's `GIT_*_EMAIL` is set and is not an address. The line ends with the value and each cause: `<N> @ signs`, an empty local part, whitespace, `<` or `>` in the local part, a domain of a single label, an empty domain label, a label longer than 63 characters, a label carrying a character other than an ASCII letter, digit or hyphen, or a label with a leading or trailing hyphen. | Correct the variable in the environment variables panel. Every commit made before the correction carries the invalid email. |
| `FAIL git identity agreement` | Author and committer name different identities. | Set all four panel variables to one pair. |
| `compare GIT_AUTHOR_IDENT ... -> not run` | One role produced no usable identity, so the agreement test did not run. | Act on that role's `FAIL git ... identity` line above it. |
| `FAIL HARNESS_ASSIGNEE: ... set and non-empty` | `HARNESS_ASSIGNEE` is unset or empty. The `actual` value separates `unset` and `set but empty`. | Set it in the environment variables panel to the GitHub login that issues and pull requests are assigned to. |
| `FAIL HARNESS_ASSIGNEE: ... a GitHub login of at most 39 ...` | The value is not a login's form. The line ends with each cause: a character other than a letter, digit or hyphen, a leading or trailing hyphen, consecutive hyphens, or its length in bytes. | Correct the value in the panel. |
| `FAIL git commit.gpgsign` / `FAIL git tag.gpgsign` | The effective value inside the clone is not `false`. | Read as `actual [true]`, something re-enabled signing; `docs/environment.md` records what is known about signing here and what is not. Read as `unset`, bootstrap's write did not reach this session. |
| `git hooks delivery -> local` / `-> cloud` | Local where the manifest's `local_checkout` is non-empty. Local runs the three rows below and the commit checks under the live file's triple. | Nothing. |
| `FAIL manifest.local_checkout` | `jq` could not read the manifest to take the delivery from, so the run took cloud delivery. | Read `cat <manifest>` above; re-run the installer to rewrite it. |
| `git config --global --get-all core.hooksPath -> ...` | Printed under local delivery only. The global values, or `unset (git exit=1)`, or `unreadable (git exit=N)`. | Nothing, unless `FAIL global core.hooksPath` follows it. |
| `FAIL global core.hooksPath` | Under local delivery, a global value still names the deployed copy's hooks, so the harness hooks run for every git command on the machine; or the global config could not be read. | Re-run `scripts/install-local.sh` and read its migration lines, or unset the value as "Removing a local install" step 3 does. |
| `jq .env.GIT_CONFIG_COUNT, .env.GIT_CONFIG_KEY_0, .env.GIT_CONFIG_VALUE_0 <dir>/settings.json -> exit=N value=[...] [...] [...] (resolves to ...)` | Printed under local delivery only. The live file's three keys, `absent` where missing, and the value's canonical form. | Nothing, unless `FAIL settings git hooks triple` follows it. |
| `FAIL settings git hooks triple` | The live file does not carry `GIT_CONFIG_COUNT` `1`, `GIT_CONFIG_KEY_0` `core.hooksPath`, and a `GIT_CONFIG_VALUE_0` naming `<repo>/git-hooks`, so a session started now runs no harness hook. | Re-run `scripts/install-local.sh` and read its `GIT_CONFIG_*` lines. |
| `git -C <repo> config --get core.hooksPath -> ...` | The effective value inside the clone and its canonical form, `unset (git exit=1)`, `unreadable (git exit=N)`, `present with empty value`, or `repo unreadable`. Under local delivery the line names the live file's triple it ran under, or `with no GIT_CONFIG_* triple`. | Nothing, unless `FAIL core.hooksPath` follows it. |
| `compare core.hooksPath against <repo>/git-hooks -> yes` | The effective value names the delivered hook directory. | Nothing. |
| `FAIL core.hooksPath` | The effective value does not resolve to `<repo>/git-hooks`. | Under local delivery, act on `FAIL settings git hooks triple` first. Read as `unset`, the install's write did not happen or did not survive: read the install log's `GIT_CONFIG_*` lines, or in the cloud `/home/user/bootstrap.log`'s `core.hooksPath` lines; in the cloud the value may also have been lost to a rewrite of `/root/.gitconfig`. Read as another path, a global or system value the installer left, or a repository-local value in the clone, is in force: `git -C <repo> config --show-origin --get core.hooksPath` names the file. |
| `git commit through the effective core.hooksPath, <case> -> exit=N [<line>]` | The result of one commit in a temporary repository: `<case>` is `a message carrying a Co-Authored-By: Claude trailer`, `a clean message`, or one of the two `hook forwarding` cases below. `not run, <cause>` where the temporary repository could not be made. | Nothing, unless `FAIL commit-msg hook` follows it. |
| `FAIL commit-msg hook, a message carrying a Co-Authored-By: Claude trailer` | The commit was not refused with `harness commit-msg: matched line ->`. | Act on `FAIL core.hooksPath` first. With the path correct, read the line: `exit=0` means the hook did not run or did not match, so compare `<repo>/git-hooks/commit-msg`, its mode and `lib/attribution.ere` with the repository; a `harness commit-msg:` line other than the marker names the hook's own failure. |
| `FAIL commit-msg hook, a clean message` | A commit with a clean message failed. | Read the line. A `harness <name>:` line is the hooks' own refusal; any other is git's, such as an identity or signing failure. |
| `FAIL commit-msg hook, <case>: ... not run, <cause>` / `FAIL hook forwarding, <case>: ... not run, <cause>` | `mktemp -d`, `git init`, `git add`, the write of `.git/hooks/pre-commit` or `.githooks/pre-commit`, or the `git config core.hooksPath .githooks` write failed, so the commits after it did not run. | Read the cause. A `harness reference-transaction:` cause is the hooks refusing `git init`. |
| `FAIL hook forwarding, a repository's own pre-commit hook exiting 1` | A commit in a repository whose own `pre-commit` prints a marker and exits 1 was not stopped with that marker, so repositories' own hooks do not run through the harness hooks. | Act on `FAIL core.hooksPath` first. Then compare `<repo>/git-hooks/pre-commit` and `lib/dispatch.sh` with the repository. |
| `FAIL hook forwarding, a repository whose own core.hooksPath names its pre-commit hook exiting 1` | A commit in a repository whose local `core.hooksPath` is `.githooks` was not stopped by `.githooks/pre-commit`'s marker. An `actual` line carrying the previous case's marker means forwarding ran `.git/hooks/pre-commit` instead. | Act on `FAIL core.hooksPath` first. Then compare `lib/dispatch.sh`'s `hook_configured_dir` with the repository. |
| `rm -rf <temporary repository> -> exit=N` | The temporary repository's removal. | Nothing, unless `FAIL commit-msg hook cleanup` follows it. |
| `FAIL commit-msg hook cleanup` | The temporary repository could not be removed. | Remove the `mktemp -d` directory under the temporary directory by hand. |

In the session that first creates these files, verify fails on the missing
manifest. That is the correct result.

## Checking the hook matchers

The attribution guard's hooks name GitHub tools exactly, so a tool renamed in a
session drops out of the guard without a `FAIL`. To check a session's tool
names against the matchers:

1. In the session to check, have it write the name of every tool it has, one
   per line, to a file, for example `/tmp/tool-names.txt`.
2. Run the script from the tree whose matchers are to be checked, the deployed
   copy for a delivered session:

   ```
   bash /opt/my-harness-wrapper/scripts/check-hook-matchers.sh /tmp/tool-names.txt
   ```

   Locally, use `${CLAUDE_CONFIG_DIR-$HOME/.claude}/my-harness-wrapper` in
   place of `/opt/my-harness-wrapper`.
3. Read the result.

| Line | What to do |
| --- | --- |
| `MISSING <name>` | The file lacks that name. Where the file holds the tool under a new name, replace the name in `config/settings.json`'s matcher and in `docs/scripts.md`'s tool table under `scripts/attribution-guard.sh`. Where it holds none, change nothing: confirm the session listed every tool, deferred ones included, and that its GitHub MCP server is connected, then re-run. Never remove a name from a matcher on this check alone. |
| `UNMATCHED <name>` | Decide whether that tool writes a pull request, issue, comment or review body, or makes a commit. Where it does, add it to the `PreToolUse` matcher and to that tool table. |
| `missing -> not run` | Act on the line above it that failed: `tool names file argument -> absent`, a `test -f` or `test -r ... -> no`, `command -v jq -> none`, a `jq ... matchers ... -> exit=N` with its error, `count=0`, `<event> entries -> 0`, or `distinct tool names ... -> 0`. |
| `uncompared -> N`, `N` above 0 | A matcher alternative is not a literal tool name, so the tools it matches were not checked. Read its `not compared` line and check that matcher by hand. |

The file is the session's own report. A name in it that equals a matcher name
reads as present whether or not the session has the tool. Only names it omits
are detected. A renamed tool outside `mcp__github__` produces no `UNMATCHED`
line.

## Reading a git hook's output

The hooks in `git-hooks/` run in every repository whose effective
`core.hooksPath` names them, and print on stderr only. In the cloud that is
every git command; locally it is only the git commands Claude Code sessions
start, so these lines appear only inside a session. A commit a hook rejects
is made again without the rejected line; no hook is bypassed with
`--no-verify`.

| Line | What it means | What to do |
| --- | --- | --- |
| `harness commit-msg: matched line -> <line>` | The commit message carries that attribution line, and the commit was refused. | Remove the line, then commit again. |
| `harness commit-msg: <path>/attribution.ere holds no single pattern line, ...` | The pattern file is absent, empty or several lines, so every commit is refused. | Re-run `scripts/install-local.sh`, or rebuild in the cloud. |
| `harness commit-msg: awk could not read the message file ...` / `... grep could not apply ...` | The check could not run, so the commit was refused. | Read the exit status; report it as a defect in `git-hooks/lib/dispatch.sh`. |
| `harness <name>: the repository's git directory was not found from <dir>, and git rev-parse --git-common-dir -> exit=N, ...` | The hook could not find the repository, so it refused rather than skip the repository's own hook. | Run the git command from inside the repository. A `.git` file whose first line is not `gitdir: <path>` also leads here. |
| `harness <name>: git config --show-scope --type=path --get-all core.hooksPath -> exit=N, ...` | The lookup of the hooks directory git would use without the harness failed, so the hook refused rather than skip the repository's own hook. | Run `git config --show-scope --get-all core.hooksPath` in the repository for git's error, such as an unreadable config file or a `~user` path naming no user, and correct it. |
| `harness <name>: <path> was not run, it is not executable.` | The repository's own hook exists without the executable bit, which git also skips. | `chmod +x <path>` where it should run. |
| `harness <name>: <dir>/lib/dispatch.sh could not be read; ...` | The hook directory is incomplete, so the hook refused. | Re-run `scripts/install-local.sh`, or rebuild in the cloud. |
| `harness push-to-checkout: Working directory has unstaged changes` and git's other `updateInstead` refusals | The repository has no `push-to-checkout` hook, and git's default refused the push. | As without the harness: clean the target repository's working tree. |
| `harness proc-receive: the repository has no executable proc-receive hook at <path>.` | `receive.procReceiveRefs` is set and the repository has no hook to serve it. | As without the harness: install the hook, or unset the key. |
| `Hook already exists: pre-push`, from `git lfs install` or `git lfs update`, in the cloud or locally inside a Claude Code session | git-lfs found the harness hooks in the directory `core.hooksPath` names and installed nothing, so the repository has no LFS hooks unless it already had them. | Locally, run `git lfs install` in a terminal outside the session: it reads no triple and installs into the repository's own hooks, which the harness hooks forward to inside sessions. In the cloud, take each hook's contents from `git lfs update --manual`, and write them into the repository's own `<common dir>/hooks`, `.git/hooks` in a plain clone, not into the path it names, which is the harness directory; the harness hooks forward to them. Never run the suggested `--force`: it overwrites the harness hooks in the deployed copy for every repository, as `FAIL deployed copy changes` then shows. |
| `attribution-guard: <path> holds no single pattern line, so the body was not checked.` | The attribution guard found no usable pattern file in the harness tree, so it blocked the write. | Restore the tree: re-run `scripts/install-local.sh`, or rebuild in the cloud. |

## Reading the session-start check

```
bash /opt/my-harness-wrapper/scripts/session-check.sh
```

The `SessionStart` hook runs it at every session start, and its output arrives
beside the first prompt. It exits 0 in every case.

In a cloud session it prints whether `/home/user/bootstrap.log`'s mtime is at or
after the boot time, and each repository under `/home/user` with its branch and
short HEAD. In a local session, one whose manifest carries `local_checkout`, it
names that deployed copy, the installer's log and the log's mtime instead. In
both it names `verify.sh`'s result: every `FAIL` and `NOTE` line, or the
`fail -> N` tally where there are none, or, where it printed neither, its
output lines prefixed `verify.sh |` up to `SESSION_CHECK_OUT_LINE_CAP` of them.
A `FAIL` line is decoded by the table above.

The `verify.sh` run is stopped at `SESSION_CHECK_VERIFY_TIMEOUT`, 75 seconds by
default, and killed `SESSION_CHECK_VERIFY_KILL_AFTER`, 5 seconds by default,
later, inside the `SessionStart` hook timeout of 90 seconds that
`config/settings.json` sets.

| Line | What it establishes | What it does not establish |
| --- | --- | --- |
| `verify.sh -> timed out after <N>s, process group killed (exit=124)`, or `(exit=137)` | `verify.sh` ran past `SESSION_CHECK_VERIFY_TIMEOUT`, default 75 seconds, and its process group was killed after `SESSION_CHECK_VERIFY_KILL_AFTER`, default 5 seconds. | Which check was slow. |
| `log mtime >= boot time -> yes` | `/home/user/bootstrap.log` was last written at or after `uptime -s`'s boot time. | That this session built the snapshot: any write to the log after boot, such as a hand-run of the init script, also reads `yes`. |
| `log mtime >= boot time -> no` | The log was last written before the boot time. | That this session restored a snapshot: any log last written before the boot time reads `no`, whatever wrote it. |
| `git -C <dir> config --show-origin --get core.hooksPath -> exit=N value=[<origin> <value>]` | The value git uses in that repository and the file that sets it. In the cloud, an origin inside the repository's own `.git/config` means the harness hooks do not run there. Locally, the origin `command line:` is the session's `GIT_CONFIG_*` triple, which outranks the repository's own value. | That the directory it names holds the harness hooks, or that they work. `scripts/verify.sh` checks that for the deployed copy only. |

`/home/user/session-check.log` holds every run's output, appended. Locally the
file is `session-check.log` in the config directory.

`config/CLAUDE.md` requires a session whose check reports a `FAIL` to name it in
its first reply.

## Before every commit

Hand-run `scripts/bootstrap.sh`, `scripts/verify.sh` and
`scripts/session-check.sh` before committing a change to them. Hand-run
`scripts/install-local.sh` against a copy of the config directory, with
`CLAUDE_CONFIG_DIR` naming the copy, never against the live one. That run
exercises `scripts/plugin-dependencies.sh` through a deployed copy cloned from a
local repository whose `main` carries the change, named in `HARNESS_REPO_URL`.
Run
`scripts/test-attribution-guard.sh` before committing a change to
`scripts/attribution-guard.sh` or to the test script itself; it exits 0 only
where every case passes. Run
`scripts/test-hook-forwarding.sh` before committing a change to `git-hooks/`
or to that script. It exits 0 only where every case passes, and it needs a
checkout holding commit `5f3f87a`. `bash -n` is not
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
