#!/usr/bin/env -S python3 -I
import json
import re
import sys
from pathlib import Path

CHECKOUT = "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"
COMMANDS = {
    "Codex delivery suite": "bash scripts/test-codex.sh",
    "Git context suite": "bash scripts/test-codex-git-context.sh",
    "Identity suite": "bash scripts/test-codex-identity.sh",
    "Attribution suite": "bash scripts/test-codex-attribution.sh",
    "Cloud pack suite": "bash scripts/test-cloud-pack.sh",
    "Native skill suite": "python3 -I scripts/tests/test_native_skills.py",
    "Environment setup": 'scratch=$(mktemp -d /tmp/wrapper-ci.XXXXXX)\nscratch=$(cd -- "$scratch" && pwd -P)\nHARNESS_STATE_DIR="$scratch/state" bash env/setup-codex.sh',
    "Hosted CI contract tests": "python3 -I scripts/tests/test_hosted_ci.py",
}
IDENTITY = 'test "$(git rev-parse HEAD)" = "$GITHUB_SHA"'
STEP_NAMES = ["Checkout exact source", "Verify checkout identity", *COMMANDS]


def require(condition, failure):
    if not condition:
        raise ValueError(failure)


def check_workflow(workflow):
    require(set(workflow) == {"name", "on", "permissions", "jobs"}, "HOSTED_WORKFLOW_FIELDS")
    require(workflow["on"] == {"push": {}, "pull_request": {}}, "HOSTED_TRIGGERS")
    require(workflow["permissions"] == {"contents": "read"}, "HOSTED_PERMISSION_BOUNDS")
    require(set(workflow["jobs"]) == {"regression"}, "HOSTED_REQUIRED_JOB")
    job = workflow["jobs"]["regression"]
    require(set(job) == {"name", "runs-on", "timeout-minutes", "steps"}, "HOSTED_JOB_BOUNDS")
    require(job["name"] == "Wrapper regression" and job["runs-on"] == "ubuntu-24.04", "HOSTED_JOB_IDENTITY")
    require(type(job["timeout-minutes"]) is int and 1 <= job["timeout-minutes"] <= 30, "HOSTED_TIMEOUT_BOUNDS")
    steps = job["steps"]
    names = [step.get("name") for step in steps]
    for name in STEP_NAMES:
        require(name in names, "HOSTED_SUITE_COVERAGE_MISSING: " + name)
    require(names == STEP_NAMES, "HOSTED_STEP_ORDER_OR_EXTRA")
    require(steps[0] == {"name": STEP_NAMES[0], "uses": CHECKOUT,
                         "with": {"ref": "${{ github.sha }}", "persist-credentials": False, "set-safe-directory": False}}, "HOSTED_CHECKOUT_IDENTITY")
    for step, command in zip(steps[1:], [IDENTITY, *COMMANDS.values()]):
        require(step == {"name": step["name"], "shell": "bash", "run": command}, "HOSTED_FAILURE_PROPAGATION: " + step["name"])


def check_run(run, jobs, expected_sha):
    require(re.fullmatch(r"[0-9a-f]{40}", expected_sha) is not None, "HOSTED_EXPECTED_SHA_INVALID")
    require(run.get("head_sha") == expected_sha, "HOSTED_SOURCE_STALE")
    require(run.get("event") in {"push", "pull_request"}, "HOSTED_EVENT_INVALID")
    require(run.get("status") == "completed" and run.get("conclusion") == "success", "HOSTED_RUN_NOT_GREEN")
    require(type(run.get("id")) is int, "HOSTED_RUN_ID_MISSING")
    required = [job for job in jobs.get("jobs", []) if job.get("name") == "Wrapper regression"]
    require(len(required) == 1, "HOSTED_REQUIRED_JOB_MISSING")
    job = required[0]
    require(type(job.get("id")) is int and job.get("run_id") == run["id"] and job.get("head_sha") == expected_sha, "HOSTED_JOB_IDENTITY_STALE")
    require(job.get("status") == "completed" and job.get("conclusion") == "success", "HOSTED_JOB_NOT_GREEN")
    steps = job.get("steps", [])
    for name in STEP_NAMES:
        found = [step for step in steps if step.get("name") == name]
        require(len(found) == 1, "HOSTED_STEPS_NOT_EXECUTED: " + name)
        step = found[0]
        require(step.get("status") == "completed" and step.get("conclusion") == "success"
                and step.get("started_at") and step.get("completed_at"), "HOSTED_STEP_NOT_GREEN: " + name)


def main():
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "workflow":
        check_workflow(json.loads(Path(args[1]).read_text()))
        print("PASS HOSTED_WORKFLOW_CONTRACT; execution NOT_OBSERVED")
    elif len(args) == 4 and args[0] == "run":
        check_run(json.loads(Path(args[1]).read_text()), json.loads(Path(args[2]).read_text()), args[3])
        print("PASS HOSTED_EXECUTION_EVIDENCE; supplied records require trusted GitHub provenance")
    else:
        raise ValueError("usage: check-hosted-ci.py workflow PATH | run RUN_JSON JOBS_JSON EXPECTED_SHA")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError) as error:
        print("FAIL " + str(error), file=sys.stderr)
        sys.exit(1)
