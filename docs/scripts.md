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
| 5 | Sets `commit.gpgsign` and `tag.gpgsign` to `false` globally. |
| 6 | Installs each plugin named in `config/plugins.tsv`. |
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

### Step 6, the plugins

The CLI owns `extraKnownMarketplaces` and `enabledPlugins` at user scope.
Neither key is ever hand-written.

### Step 7, the manifest

`git_user_email` records what `git config --get user.email` answers inside the
clone. Step 5 does not write that key, so the value is whatever config resolves
to, and may be nothing at all. It need not be the email git writes, because
`git var` resolves a role whose email variable is set from that variable
instead. The field is kept for the record, not as evidence of what took effect.
`scripts/verify.sh` prints it without asserting it.

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

Seven values pass through it. Three are git-derived: the contrast `user.email`,
each `git var` ident, and each `*.gpgsign` read. Two come from `env/setup.sh`:
the matched `export` lines, and an export value outside `[0-9A-Za-z._-]`. Two
are the settings probes, one per side. A
value inside that set needs no pass, holding no control byte by construction.
Every other printed value goes out without passing through it, some git output
among them. That is a known gap, not a finding that the others are safe.

### Resolving the config directory

The script resolves the directory Claude Code actually uses, rather than
searching a fixed list of candidate homes. A config directory outside such a
list would report clean.

`CLAUDE_CONFIG_DIR` is read with the colon-less default, because the CLI treats
a set-but-empty value as a value.

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
`manifest.config_dir`, both through `readlink -f`. Its two defaults,
`unresolved-live` and `unresolved-manifest`, differ on purpose, so an
unresolvable live directory and an unreadable manifest value never compare
equal and pass.

A non-zero CLI exit yields `unknown` rather than a guess, because a default
either way is a value manufactured by a failure.

### The plugin checks

Plugin state is read from `claude plugin list --json`, not from the command's
human-readable output, which a wording, format or localisation change moves.

Three states are separated. A non-zero exit, output whose top level is not an
array, and a failure extracting the ids from a well-typed array all give
`CLI_PLUGINS=unknown`; an array with no ids gives `no`; an array with ids gives
`yes`. `unknown` is a `FAIL` in its own right rather than
a guess either way, and it also fails each per-plugin check rather than letting
an untestable id pass.

The per-plugin test compares whole ids, not substrings, so an id that is a
prefix of an installed one does not match.

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
all is reported as not determined. Under `--slurpfile` an absent file and a file
holding no valid JSON both exit 2 with no output, so both reach that state; the
`test -f` line printed above separates them.

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

Each file is slurped into its own variable, and a file that does not yield
exactly one JSON document is reported as that state. Reading both files into one
array aligns them by position, and a live file holding two documents then
displaces the delivered one out of the compared slot.

`settings_probe`, which supplies the displayed value, still emits one line per
document, so for such a file the displayed value is each document's probe in
turn. The state named beside it says how many documents were found.

### Git identity

Identity is checked effective from inside the clone, and need not come from git
config. `git config --get` cannot see a role's environment pair at all, so it is
not authoritative about the identity git will write, whether or not the two
happen to agree. `git var` resolves the same precedence git uses at commit
time, so that is what is asserted. The `user.email` read is shown for contrast
only.

No name or email is written into this repository. Four assertions stand in
place of the literals it used to carry:

| Assertion | What it catches |
| --- | --- |
| All four `GIT_AUTHOR_*` and `GIT_COMMITTER_*` variables set and non-empty | The panel supplying no identity |
| `git var` resolving each role to that role's own pair | Git not reading the pair the session was given |
| Author and committer naming one identity | A commit attributed to two people |
| Neither email being `noreply@anthropic.com` | The harness identity taking over |

The last assertion catches a failure that has occurred here. With the pair
absent, `git var` resolves from `/root/.gitconfig`, which holds
`Claude <noreply@anthropic.com>` after every rewrite. The four are checked
together: a role can be unset and still yield an identity, so the variable
assertions alone miss that case, and a set-but-wrong pair carries no harness
email, so the email assertion alone misses that one.

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

## scripts/session-check.sh

Reports what a session starts with. Run by the `SessionStart` hook
`config/settings.json` registers, and by hand. It exits 0 in every case, so a
failed check never blocks session startup.

`REPO` reads `${HARNESS_DIR:-/opt/my-harness-wrapper}`, the same default
`scripts/verify.sh` reads, so both report on the delivered copy. The hook names
that path literally, delivery putting the clone there.

Each line goes to stdout and is appended to `/home/user/session-check.log`. A
failed append is discarded, so an unwritable log does not change the output.
The log's own state is tested once at the start and printed as
`append to <path> -> appendable` or `not appendable`, so a later reader of a
truncated log can tell that the writes were failing rather than that the
session was quiet.

| Line | What it reports |
| --- | --- |
| `session-check -> exit=N value=...` | When the run started, and `date`'s own exit status. |
| `uptime -s` and `stat -c %y` on the boot log | The two values behind the snapshot verdict. |
| `test -f <boot log> -> yes/no` | Whether the boot log is at the path this script reads. |
| `log mtime >= boot time` | `yes` where this session built the snapshot, `no` where it restored one. |
| `snapshot state -> undetermined, log epoch [...] boot epoch [...]` | Either epoch was missing or non-numeric. Both values are printed. |
| `snapshot state -> undetermined, ... absent` | The boot log is not at the path this script reads, so neither epoch exists. |
| `git -C <dir> rev-parse --abbrev-ref HEAD, --short HEAD` | One line per directory under `/home/user`, with its branch and short HEAD. |
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

The snapshot verdict needs both epochs. Each is tested on its own, because
testing them joined lets one empty value pass while the other supplies the
digits, and the comparison then runs against an empty operand and reports a
restored snapshot. Either one missing or non-numeric reports undetermined
instead, with both values printed.

The boot epoch is computed only where `uptime -s` exited 0, so output from a
failed call cannot reach the verdict.

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

`config/settings.json` registers it with matcher `startup`. The command guards
on the script's own presence with `if`, not with `&&` and `||`, which would
print the absent-file line when the script exists and fails. The `else` branch
prints `test -f <path> -> no`, so a session where delivery never happened is
distinguishable from one where the check ran and found nothing wrong. Every
session carries the hook, whatever it has attached.

## scripts/attribution-guard.sh

Blocks a pull request body carrying a Claude Code attribution line. Run by the
`PreToolUse` hook `config/settings.json` registers, which passes the tool call
to it on stdin as JSON.

| `tool_name` | What is scanned |
| --- | --- |
| `Bash` | The command, and every file it passes as a body, where the command runs `gh pr create`, `gh pr edit`, or `gh api` against an endpoint carrying `/pulls`. Any other command is left alone. |
| Anything else | Every string in `tool_input`, at any depth. |

A body file is taken from four token forms: `--body-file <path>`,
`--body-file=<path>`, `-F <name>=@<path>` for any field name, and
`body=@<path>` after any flag spelling. A field named anything but `body` is
recognised only after `-F`. One run of surrounding quotes is stripped from the
path. A path that is not a readable regular file is skipped. The first mebibyte
of the file is scanned.

The match is case-insensitive, against `Generated (with|by) \[?Claude Code` and
`claude.ai/code/session_`.

| Outcome | Exit | Output |
| --- | --- | --- |
| A line matched | 2 | The matched line and the instruction to remove it, on stderr. |
| Nothing matched | 0 | None. |
| Input that is not a JSON object, carries no `tool_name`, or arrives with no `jq` on `PATH` | 0 | None. |

Scoping the `Bash` branch to pull request operations keeps documentation
quoting the footer writable. A `grep` for the footer text is not a pull request
operation, and is not scanned.

A matched line goes to stderr through the same control-byte replacement
`scripts/verify.sh` uses, so a body carrying ESC or CR cannot rewrite the line
an operator reads. The line printed is a line of the body or of a body file, so
a body file the command names by mistake can put one of its lines in front of
the session.

These paths reach a pull request body without being scanned. Each is accepted,
not handled.

| Path | Why it is missed |
| --- | --- |
| `--body "$(cat notes.md)"`, a heredoc, or any other shell substitution | The hook receives the command before the shell expands it, so the body text is not in what it reads. |
| `curl`, `wget` or a script posting to `/repos/<owner>/<repo>/pulls` | Neither `gh pr` nor `gh api` appears in the command, so the command is not classified as a pull request operation. |
| `gh api graphql` mutating a pull request | The endpoint is `/graphql`, and the classifier requires `/pulls`. |
| A body-file path carrying a space | The path is read up to the first space, and the truncated path is then skipped as unreadable. |
| A body file past its first mebibyte | Only the first mebibyte is read. |
| A `--body-file` flag and its path on different lines of a continued command | Each token form is matched within one line. |
| A footer added to a pull request description after the tool call | The hook sees the tool call, and the footer is not in it. `docs/environment.md` records this under "What the harness supplies regardless". |

Nothing is printed when the guard is inert — `jq` absent, or the script absent
from the path the hook names — so a session cannot tell an inert guard from one
that found nothing. `scripts/verify.sh` is what separates them.

`scripts/verify.sh` runs the live `PreToolUse` command against a sample
`gh pr create` body carrying the footer, and expects exit 2 with the guard's
own `attribution-guard: matched line ->` marker on stderr. The exit status
alone does not distinguish a guard that matched from a `PreToolUse` command
whose shell syntax is broken, `bash -c` exiting 2 for both. The assertion runs
whatever command the live `settings.json` registers, so it trusts that file as
much as the session running it already does. It tests the delivered hook, not
this file, so it fails in a session whose snapshot predates the hook.

## config/plugins.tsv

`README.md` carries the format.

Both scripts read the file on descriptor 3, so the loop body — `claude plugin
install` in bootstrap, `grep` in verify — cannot consume it from stdin. The
loop's `|| [ -n "${mp_source:-}" ]` clause processes a final line carrying no
trailing newline.

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
the only signal that the pasted copy has fallen behind. It is bumped in the
commit that changes what `env/setup.sh` does, never on its own. A mismatch
means the pasted copy is older than the repository's, and a paste is due.

It fetches the repository rather than reading an attached checkout. The clone
URL comes from `HARNESS_REPO_URL` where that variable is set and non-empty, and
from the script's own default, this repository's URL, where it is unset or
empty. A value the environment supplies is never overwritten. The destination
is the literal `/opt/my-harness-wrapper`.

| Line | What it reports |
| --- | --- |
| `BOOTSTRAP_VERSION=` | The version the pasted text carries. |
| `HARNESS_DIR ->` | The clone destination. |
| `HARNESS_REPO_URL -> <state>; clone URL from <environment\|default>` | The variable's state, and which of the two supplied the URL. Never the value itself. |
| `command -v git ->` | Whether git is on `PATH`. |
| `test -e <dir> -> yes/no` | Whether anything already occupies the destination. |
| `git clone --depth 1 ... -> exit=N` | The clone's exit status. |
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
