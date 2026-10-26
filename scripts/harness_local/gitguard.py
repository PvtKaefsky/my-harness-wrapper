from typing import Any
import json
import os
import re
import subprocess
from pathlib import Path

from .pack import decode, safe

ROLES = {"general", "python", "shell", "security", "go", "database", "architecture",
         "build", "docs", "e2e", "go-build", "planning", "refactor", "tdd", "communication"}
ATTRIBUTION = re.compile(
    r"^\s*(?:Co-Authored-By|[\w-]+-Session):|Generated (?:with|by)\s+|"
    r"https?://\S*/(?:code/session_|codex/tasks/)|chatgpt\.com/(?:codex|c)/",
    re.IGNORECASE | re.MULTILINE)


def git(*args: str, check: bool = True) -> str:
    result = subprocess.run(["git", *args], capture_output=True, check=check)
    return result.stdout.decode("utf-8", errors="strict").strip()


def head() -> str:
    return git("rev-parse", "--verify", "HEAD", check=False)


def hooks_check() -> None:
    directory = Path(git("rev-parse", "--path-format=absolute", "--git-path", "hooks"))
    for name in ["pre-commit", "prepare-commit-msg", "commit-msg", "post-commit",
                 "post-rewrite", "post-index-change", "reference-transaction"]:
        for suffix in ["", ".exe"] if os.name == "nt" else [""]:
            path = directory / (name + suffix)
            if path.is_file() and os.access(path, os.X_OK):
                raise ValueError("COMMIT_HOOK_REVIEW_BOUNDARY: " + name)


def requirements() -> dict[str, Any]:
    hooks_check()
    names = subprocess.check_output(["git", "diff", "--cached", "--name-only", "-z",
                                     "--no-renames", "--diff-filter=ACDMRTUXB"]).decode("utf-8").split("\0")
    roles = {"general"}
    if any(p.endswith(".py") for p in names):
        roles.add("python")
    if any(p.endswith((".sh", ".ps1", ".psm1")) for p in names):
        roles.add("shell")
    if any(p.endswith(".go") for p in names):
        roles.add("go")
    if any(p.endswith(".sql") for p in names):
        roles.add("database")
    if any(p.startswith(("scripts/", "env/", "config/codex/")) for p in names):
        roles.add("security")
    return {"source_commit": head(), "tree": git("write-tree"),
            "required_roles": sorted(roles)}


def review_check(path: str | Path | None) -> dict[str, Any]:
    if path is None:
        raise ValueError("INDEPENDENT_REVIEW_MISSING")
    required = requirements()
    record = decode(safe(path).read_bytes())
    if record.get("schema_version") != 2 or record.get("provider") != "native-codex":
        raise ValueError("INDEPENDENT_REVIEW_SCHEMA_INVALID")
    if any(record.get(key) != required[key] for key in ("source_commit", "tree")):
        raise ValueError("INDEPENDENT_REVIEW_STALE")
    implementer = record.get("implementer_id")
    extra = record.get("required_roles")
    if not isinstance(implementer, str) or not implementer.strip() or not isinstance(extra, list):
        raise ValueError("INDEPENDENT_REVIEW_PROVIDER_INVALID")
    if any(role not in ROLES for role in extra) or len(set(extra)) != len(extra):
        raise ValueError("INDEPENDENT_REVIEW_ROLE_UNSUPPORTED")
    covered, reviewers, dispatches, completions = set(), set(), set(), set()
    for review in record["reviews"]:
        reviewer = review.get("reviewer_id")
        roles = review.get("roles")
        findings = review.get("findings")
        if not isinstance(reviewer, str) or not reviewer.strip() or reviewer == implementer:
            raise ValueError("INDEPENDENT_REVIEW_NOT_INDEPENDENT")
        if reviewer in reviewers:
            raise ValueError("INDEPENDENT_REVIEW_DUPLICATE_REVIEWER")
        reviewers.add(reviewer)
        if (not isinstance(roles, list) or len(set(roles)) != len(roles)
                or any(role not in ROLES for role in roles)):
            raise ValueError("INDEPENDENT_REVIEW_ROLE_UNSUPPORTED")
        if review.get("tree") != required["tree"] or review.get("verdict") != "APPROVED":
            raise ValueError("INDEPENDENT_REVIEW_NOT_APPROVED")
        if not isinstance(findings, list) or any(
                not isinstance(finding, dict) or finding.get("severity") != "LOW"
                for finding in findings):
            raise ValueError("INDEPENDENT_REVIEW_FINDINGS_BLOCK")
        receipt = review.get("provider_receipt")
        expected = {"provider": "native-codex", "status": "REVIEW_COMPLETED",
                    "reviewer_id": reviewer, "source_commit": record["source_commit"],
                    "tree": record["tree"], "roles": roles,
                    "verdict": "APPROVED", "findings": findings}
        if not isinstance(receipt, dict) or any(receipt.get(k) != v for k, v in expected.items()):
            raise ValueError("INDEPENDENT_REVIEW_PROVIDER_RECEIPT_MISMATCH")
        for key in ["dispatch_id", "completion_id", "transcript_ref"]:
            if not isinstance(receipt.get(key), str) or not receipt[key].strip():
                raise ValueError("INDEPENDENT_REVIEW_PROVIDER_PROOF_MISSING")
        if receipt["dispatch_id"] in dispatches or receipt["completion_id"] in completions:
            raise ValueError("INDEPENDENT_REVIEW_DUPLICATE_PROVIDER_PROOF")
        if not isinstance(review.get("evidence"), str) or not review["evidence"].strip():
            raise ValueError("INDEPENDENT_REVIEW_PROVIDER_PROOF_MISSING")
        dispatches.add(receipt["dispatch_id"])
        completions.add(receipt["completion_id"])
        covered.update(roles)
    if (set(required["required_roles"]) | set(extra)) - covered:
        raise ValueError("INDEPENDENT_REVIEW_ROLES_MISSING")
    return required


def identity() -> dict[str, str]:
    result = {}
    for role in ["AUTHOR", "COMMITTER"]:
        value = git("var", "GIT_" + role + "_IDENT")
        found = re.fullmatch(r"(.+) <([^<>]+)> \d+ [+-]\d{4}", value)
        if not found:
            raise ValueError("GIT_IDENTITY_UNRESOLVED")
        result[role] = {"name": found[1], "email": found[2]}
    if result["AUTHOR"] != result["COMMITTER"]:
        raise ValueError("GIT_IDENTITY_MISMATCH")
    return result["AUTHOR"]


def message_check(args: list[str]) -> None:
    messages = []
    iterator = iter(args)
    for arg in iterator:
        if arg in {"-m", "--message", "-F", "--file"}:
            value = next(iterator, None)
            if value is None or value == "-":
                raise ValueError("COMMIT_EXPLICIT_MESSAGE_REQUIRED")
            messages.append(Path(value).read_text(encoding="utf-8")
                            if arg in {"-F", "--file"} else value)
        elif arg.startswith("--message=") or (arg.startswith("-m") and not arg.startswith("--")):
            messages.append(arg.split("=", 1)[1] if arg.startswith("--") else arg[2:])
        elif arg.startswith("--file=") or (arg.startswith("-F") and not arg.startswith("--")):
            value = arg.split("=", 1)[1] if arg.startswith("--") else arg[2:]
            if value == "-":
                raise ValueError("COMMIT_EXPLICIT_MESSAGE_REQUIRED")
            messages.append(Path(value).read_text(encoding="utf-8"))
        elif arg in {"-q", "--quiet", "-v", "--verbose", "--no-edit", "--allow-empty",
                     "--no-gpg-sign", "--signoff", "-s", "-S", "--gpg-sign"}:
            continue
        elif arg.startswith(("--gpg-sign=", "--cleanup=")) or (
                arg.startswith("-S") and not arg.startswith("--")):
            continue
        else:
            raise ValueError("COMMIT_ARGUMENT_UNSAFE")
    if not messages or not any(message.strip() for message in messages):
        raise ValueError("COMMIT_EXPLICIT_MESSAGE_REQUIRED")
    if ATTRIBUTION.search("\n\n".join(messages)):
        raise ValueError("COMMIT_ATTRIBUTION_FORBIDDEN")


def commit(args: list[str], approval: dict[str, str] | None, review: str | Path | None) -> str:
    if not approval or identity() != approval:
        raise ValueError("GIT_IDENTITY_NOT_APPROVED")
    message_check(args)
    subprocess.run(["git", "diff", "--cached", "--check"], check=True)
    approved = review_check(review)
    if approved != requirements():
        raise ValueError("INDEPENDENT_REVIEW_STALE")
    subprocess.run(["git", "commit", *args], check=True)
    return "GUARDED_COMMIT_PASSED commit=" + head()
