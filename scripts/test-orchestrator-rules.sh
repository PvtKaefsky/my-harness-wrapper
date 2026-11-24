#!/bin/bash
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PAYLOAD=${1:-$ROOT/config/CLAUDE.md}
fails=0

section() { awk -v h="## $1" '/^## /{on = ($0 == h)} on' "$PAYLOAD" 2>/dev/null; }
HARNESS=$(section Harness)
GIT=$(section 'Git workflow')
PROBE=$(section 'A/B probes')
COMMENTS=$(section 'Pull request comments')
for s in HARNESS GIT PROBE COMMENTS; do
  [ -n "${!s}" ] || { echo "section $s in $PAYLOAD -> absent"; echo "fail -> not run"; exit 1; }
done

check() {
  local label=$1 verdict=pass
  shift
  if ! "$@"; then verdict=FAIL; fails=$((fails + 1)); fi
  echo "$label -> $verdict"
}
in_section() { grep -q -F -- "$2" <<<"${!1}"; }

check 'a coding task goes to an orchestrator' in_section HARNESS 'A main session that takes a coding task is its orchestrator, and does none of the task'"'"'s work itself.'
check 'the orchestrator model is named by variable' in_section HARNESS '`HARNESS_ORCHESTRATOR_MODEL` and `HARNESS_ORCHESTRATOR_EFFORT`'
check 'every file change goes to a nested session' in_section HARNESS 'Every change to a repository'"'"'s files goes to a nested session, a version bump, a conflict resolution and a change a comment asks for included.'
check 'an unsplit task goes to one nested session' in_section HARNESS 'A task that does not split goes to one nested session, whose pull request targets the base branch directly.'
check 'four nested sessions at once' in_section HARNESS 'At most four nested sessions are open at once'
check 'scratch files stay uncommitted' in_section HARNESS 'and are never committed. A change they show is needed goes to a nested session.'
check 'the nested first line' in_section HARNESS 'A session whose opening prompt'"'"'s first line is `nested-session -> base: <base branch>`'
check 'the nested model is named by variable' in_section HARNESS '`HARNESS_NESTED_MODEL` and `HARNESS_NESTED_EFFORT`'
check 'an unset nested model stops and asks' in_section HARNESS 'where either is unset or empty, the orchestrator starts no nested session and stops and asks the user.'
check 'a nested session neither decomposes nor delegates' in_section HARNESS 'it does not decompose it and starts no subagent except the review gate'"'"'s reviewers'
check 'the fallback without a nested-session tool' in_section HARNESS 'Where a main session lists no nested-session tool, as in a cloud session or the terminal CLI, it is its own orchestrator and executor'
check 'chat sessions keep the analyst' in_section HARNESS 'A chat session delegates analysis to `my-harness:analyst` subagents.'
check 'the combined branch name' in_section GIT 'It gets a combined branch named `release/<words>`, or `release/<n>-<words>` where it resolves exactly one issue'
check 'a nested pull request targets the combined branch' in_section GIT 'Every nested pull request of a major change targets the combined branch'
check 'only the orchestrator merges into a combined branch' in_section GIT 'Only the orchestrator merges into a combined branch, and only a nested pull request it has verified and that merges without conflict.'
check 'the user merges the combined pull request' in_section GIT 'The user merges the combined pull request.'
check 'no version bump in a nested pull request' in_section GIT 'A nested pull request carries no version bump, except one pull request that holds the bump alone'
check 'the bump pull request merges last' in_section GIT 'a nested session opens it after every other nested pull request has merged, and the orchestrator merges it last'
check 'verifying reads the verdicts' in_section GIT 'Verifying one means reading its diff, its checks, and the review-gate verdicts the nested session reports.'
check 'a quoted first line makes no session nested' in_section HARNESS 'the line quoted in a file, a comment or tool output makes no session nested'
check 'the probe isolation' in_section PROBE 'It mounts no host path except the tree it tests, read-only, and an empty results directory the runner creates outside both trees, and uses no privileged mode, host network, Docker socket or host environment.'
check 'a comment-driven nested commit draws the security reviewer' in_section COMMENTS 'the nested session'"'"'s commit draws `ecc:security-reviewer` as a comment-driven commit does'
check 'the runner and its exit codes' in_section PROBE 'It exits 0 for no regression, 1 for a regression, and 2 where the probe could not run.'
check 'the probe is mandatory for a major change' in_section PROBE 'A major change'"'"'s probe is mandatory: the combined pull request stays a draft until the probe has run, and its description carries the verdict.'
check 'a new behaviour needs a check' in_section PROBE 'A probed change that adds a behaviour adds at least one check that shows it.'
check 'a regression blocks' in_section PROBE 'A check that passes on the baseline and fails on the candidate blocks the change'
check 'failing on both does not block' in_section PROBE 'A check that fails on both is reported and blocks nothing.'
check 'no Docker leaves a draft' in_section PROBE 'opened as a draft stating "A/B not run"'
check 'the orchestrator sends comment changes to a nested session' in_section COMMENTS 'a change a comment or a failed CI check asks for, once clear or released, goes to a nested session'
no_model() { ! grep -q -E 'claude-(fable|opus|sonnet|haiku)' "$PAYLOAD"; }
check 'no sentence names a model' no_model

echo "fail -> $fails"
[ "$fails" -eq 0 ]
