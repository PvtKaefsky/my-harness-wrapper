#!/usr/bin/env -S python3 -I
import json
import os
import subprocess
import sys
from pathlib import Path


ROLE_BRIEFS = {
    "general": "code-reviewer", "python": "python-reviewer", "shell": "code-reviewer",
    "security": "security-reviewer", "go": "go-reviewer", "database": "database-reviewer",
    "architecture": "architect", "build": "build-error-resolver", "docs": "doc-updater",
    "e2e": "e2e-runner", "go-build": "go-build-resolver", "planning": "planner",
    "refactor": "refactor-cleaner", "tdd": "tdd-guide", "communication": "chief-of-staff",
}


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def source_head():
    result = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], text=True, capture_output=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def required_roles():
    paths = subprocess.check_output(["git", "diff", "--cached", "--name-only", "-z", "--no-renames", "--diff-filter=ACDMRTUXB"]).decode().split("\0")
    roles = {"general"}
    if any(p.endswith(".py") for p in paths): roles.add("python")
    if any(p.endswith(".sh") for p in paths): roles.add("shell")
    if any(p.endswith(".go") for p in paths): roles.add("go")
    if any(p.endswith(".sql") for p in paths): roles.add("database")
    if any(p.startswith(("env/", "scripts/", "config/codex/")) for p in paths): roles.add("security")
    return sorted(roles)


def role_list(value):
    if not isinstance(value, list) or any(not isinstance(x, str) or x not in ROLE_BRIEFS for x in value):
        raise ValueError("INDEPENDENT_REVIEW_ROLE_UNSUPPORTED")
    if len(value) != len(set(value)):
        raise ValueError("INDEPENDENT_REVIEW_ROLE_DUPLICATE")
    return set(value)


def nonempty(value):
    return isinstance(value, str) and bool(value.strip())


def validate_provider_receipt(review, record):
    receipt = review.get("provider_receipt")
    if not isinstance(receipt, dict):
        raise ValueError("INDEPENDENT_REVIEW_PROVIDER_RECEIPT_MISSING")
    if any(not nonempty(receipt.get(key)) for key in ("dispatch_id", "completion_id", "transcript_ref")):
        raise ValueError("INDEPENDENT_REVIEW_PROVIDER_PROOF_MISSING")
    expected = {"provider": "native-codex", "status": "REVIEW_COMPLETED", "reviewer_id": review["reviewer_id"],
                "source_commit": record["source_commit"], "tree": review["tree"], "roles": review["roles"],
                "verdict": review["verdict"], "findings": review["findings"]}
    if any(receipt.get(key) != value for key, value in expected.items()):
        raise ValueError("INDEPENDENT_REVIEW_PROVIDER_RECEIPT_MISMATCH")
    return receipt["completion_id"], receipt["dispatch_id"]


def main():
    subprocess.run(["bash", str(Path(__file__).absolute().parent / "check-codex-hooks.sh")], check=True, stdout=subprocess.DEVNULL)
    tree = git("write-tree")
    roles = required_roles()
    if len(sys.argv) == 2 and sys.argv[1] == "--requirements":
        print(json.dumps({"tree": tree, "source_commit": source_head(), "required_roles": roles,
                          "role_briefs": {role: "role/" + brief for role, brief in ROLE_BRIEFS.items()},
                          "project_role_selection": "REQUIRES_AGENT_INSPECTION"}))
        return
    if len(sys.argv) != 1: raise ValueError("INDEPENDENT_REVIEW_ARGUMENT_INVALID")
    path = os.environ.get("HARNESS_REVIEW_FILE")
    if not path: raise ValueError("INDEPENDENT_REVIEW_MISSING: set HARNESS_REVIEW_FILE to actual provider review evidence")
    with open(path) as stream: record = json.load(stream)
    head = source_head()
    if record.get("tree") != tree or record.get("source_commit") != head:
        raise ValueError("INDEPENDENT_REVIEW_STALE")
    if record.get("provider") != "native-codex" or not nonempty(record.get("implementer_id")):
        raise ValueError("INDEPENDENT_REVIEW_PROVIDER_INVALID")
    if record.get("schema_version") != 2:
        raise ValueError("INDEPENDENT_REVIEW_SCHEMA_INVALID")
    roles = set(roles) | role_list(record.get("required_roles"))
    approved, reviewers, completions, dispatches = set(), set(), set(), set()
    for review in record["reviews"]:
        reviewer = review.get("reviewer_id")
        if not nonempty(reviewer) or reviewer == record["implementer_id"] or not nonempty(review.get("evidence")):
            raise ValueError("INDEPENDENT_REVIEW_NOT_INDEPENDENT")
        if reviewer in reviewers: raise ValueError("INDEPENDENT_REVIEW_DUPLICATE_REVIEWER")
        reviewers.add(reviewer)
        if review.get("tree") != tree or review.get("verdict") != "APPROVED":
            raise ValueError("INDEPENDENT_REVIEW_NOT_APPROVED")
        if not isinstance(review["findings"], list) or any(not isinstance(f, dict) or f.get("severity") != "LOW" for f in review["findings"]):
            raise ValueError("INDEPENDENT_REVIEW_FINDINGS_BLOCK")
        coverage = role_list(review["roles"])
        completion, dispatch = validate_provider_receipt(review, record)
        if completion in completions or dispatch in dispatches:
            raise ValueError("INDEPENDENT_REVIEW_DUPLICATE_PROVIDER_PROOF")
        completions.add(completion)
        dispatches.add(dispatch)
        approved.update(coverage)
    if roles - approved: raise ValueError("INDEPENDENT_REVIEW_ROLES_MISSING: " + ",".join(sorted(roles - approved)))
    if tree != git("write-tree") or head != source_head():
        raise ValueError("INDEPENDENT_REVIEW_STALE")
    print("TREE_APPROVED consistency_only tree=" + tree + " roles=" + ",".join(sorted(roles)))
    print("PASS independent review evidence covers staged tree " + tree + " roles=" + ",".join(sorted(roles)))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, AttributeError, OSError, subprocess.CalledProcessError) as error:
        print("FAIL " + str(error), file=sys.stderr)
        sys.exit(1)
