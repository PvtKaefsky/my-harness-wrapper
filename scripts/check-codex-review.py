#!/usr/bin/env -S python3 -I
import json
import os
import subprocess
import sys
from pathlib import Path


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def required_roles():
    paths = git("diff", "--cached", "--name-only", "--diff-filter=ACDMRTUXB").splitlines()
    roles = {"general"}
    if any(p.endswith(".py") for p in paths): roles.add("python")
    if any(p.endswith(".sh") for p in paths): roles.add("shell")
    if any(p.startswith(("env/", "scripts/", "config/codex/")) for p in paths): roles.add("security")
    return sorted(roles)


def main():
    subprocess.run(["bash", str(Path(__file__).absolute().parent / "check-codex-hooks.sh")], check=True, stdout=subprocess.DEVNULL)
    tree = git("write-tree")
    roles = required_roles()
    if len(sys.argv) == 2 and sys.argv[1] == "--requirements":
        print(json.dumps({"tree": tree, "source_commit": git("rev-parse", "HEAD"), "required_roles": roles}))
        return
    path = os.environ.get("HARNESS_REVIEW_FILE")
    if not path: raise ValueError("INDEPENDENT_REVIEW_MISSING: set HARNESS_REVIEW_FILE to actual provider review evidence")
    with open(path) as stream: record = json.load(stream)
    head = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], text=True, capture_output=True)
    if record.get("tree") != tree or record.get("source_commit") != (head.stdout.strip() if head.returncode == 0 else ""):
        raise ValueError("INDEPENDENT_REVIEW_STALE")
    if record.get("provider") != "native-codex" or not record.get("implementer_id"):
        raise ValueError("INDEPENDENT_REVIEW_PROVIDER_INVALID")
    approved = set()
    for review in record["reviews"]:
        if not review.get("reviewer_id") or review["reviewer_id"] == record["implementer_id"] or not review.get("evidence"):
            raise ValueError("INDEPENDENT_REVIEW_NOT_INDEPENDENT")
        if review.get("tree") != tree or review.get("verdict") != "APPROVED":
            raise ValueError("INDEPENDENT_REVIEW_NOT_APPROVED")
        if any(f.get("severity") != "LOW" for f in review["findings"]):
            raise ValueError("INDEPENDENT_REVIEW_FINDINGS_BLOCK")
        approved.update(review["roles"])
    if set(roles) - approved: raise ValueError("INDEPENDENT_REVIEW_ROLES_MISSING: " + ",".join(sorted(set(roles) - approved)))
    print("PASS independent review evidence covers staged tree " + tree + " roles=" + ",".join(roles))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print("FAIL " + str(error), file=sys.stderr)
        sys.exit(1)
