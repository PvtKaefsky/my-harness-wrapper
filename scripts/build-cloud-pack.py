#!/usr/bin/env -S python3 -I
import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PIN = "d468c521f1a76e7b05d446d805f6ad2afa8ed066"
VERSION = "1.7.0-codex.0"
REPOSITORY = "forever94yu/everything-codex-code"
PACK = ROOT / "config/codex/cloud-pack"
RISKS = {
    "legacy_runtime": r"(?i)claude|sonnet|opus|haiku|AskUserQuestion",
    "agent_assumptions": r"(?i)\bTask\b|subagent|multi.agent",
    "user_state": r"(?i)~/|\$HOME|CODEX_HOME|persistent|instinct",
    "execution_assumptions": r"(?i)\bhooks?\b|\bMCP\b|npx|curl|wget|install\.sh",
}
EXCLUSIONS = {
    "article-writing": "General publishing workflow is outside this coding pack.",
    "autonomous-loops": "Requires unsupported autonomous runtime/process orchestration.",
    "clickhouse-io": "Analytics-specific workflow deferred; no configured ClickHouse execution contract.",
    "configure-ecc": "Installer and user/project configuration writes violate the read-only delivery boundary.",
    "content-engine": "Social publishing workflow is outside this coding pack.",
    "continuous-learning": "Persistent observation hooks and learned user state are not provisioned.",
    "continuous-learning-v2": "Persistent observer and instinct stores are not provisioned.",
    "cost-aware-llm-pipeline": "External model routing, pricing and API budget state require a separate integration.",
    "foundation-models-on-device": "Requires an on-device Apple framework runtime unavailable in this Cloud execution contract.",
    "frontend-slides": "Presentation conversion and design workflow is outside this coding pack.",
    "investor-materials": "Fundraising documents are outside this coding pack.",
    "investor-outreach": "Fundraising communication is outside this coding pack.",
    "liquid-glass-design": "Apple-specific visual design requires SDK/device evidence outside this Cloud contract.",
    "market-research": "Market research and its data integrations are outside this coding pack.",
    "nutrient-document-processing": "Requires a separately authorized external document service and credentials.",
    "plankton-code-quality": "Assumes a separate automatic lint/hook installation; use explicit project verification instead.",
    "project-guidelines-example": "Example project policy must not override unrelated target repositories.",
    "security-scan": "Assumes an external scanner installation/integration; adapted security review uses only available project tools.",
    "skill-stocktake": "Assumes installed skill inventory and local skill-management state absent from this pack.",
    "strategic-compact": "Assumes compaction hooks and persistent session state; completion reports remain conversational.",
    "visa-doc-translate": "Sensitive document translation workflow is outside this coding pack.",
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def main():
    upstream = Path(sys.argv[1]).resolve()
    def git(*args):
        selectors = {"GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_QUARANTINE_PATH", "GIT_GRAFT_FILE", "GIT_SHALLOW_FILE", "GIT_NAMESPACE", "GIT_PREFIX", "GIT_INTERNAL_SUPER_PREFIX", "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT", "GIT_CONFIG_SYSTEM", "GIT_TEMPLATE_DIR"}
        env = {k: v for k, v in os.environ.items() if k not in selectors and not k.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_"))}
        return subprocess.check_output(["git", "-C", str(upstream), *args], env=env)
    if git("rev-parse", "HEAD").decode().strip() != PIN or git("status", "--porcelain"):
        raise SystemExit("PACK_BUILD_SOURCE_NOT_PINNED_CLEAN")
    projections = json.loads((ROOT / "scripts/pack-projection.json").read_text())
    if PACK.exists():
        raise SystemExit("PACK_BUILD_DESTINATION_EXISTS: preserve it; use a disposable checkout to rebuild")
    PACK.mkdir(parents=True)
    records = {}
    selected = {p for item in projections for p in item["sources"]}
    paths = git("ls-tree", "-r", "--name-only", PIN).decode().splitlines()
    special = {"LICENSE", "package.json", ".codex/AGENTS.md", ".codex/config.toml", "hooks/hooks.json", "scripts/install-codex.js", "install.sh"}
    for path in paths:
        group = path.split("/")[0]
        category = None
        if re.fullmatch(r"skills/[^/]+/SKILL.md", path): category = "skills"
        elif re.fullmatch(r"agents/[^/]+\.md", path): category = "roles"
        elif re.fullmatch(r"commands/[^/]+\.md", path): category = "workflows"
        elif group == "rules" and path.endswith(".md"): category = "rules"
        elif re.fullmatch(r"scripts/hooks/[^/]+\.(js|sh)", path): category = "hooks"
        elif path in special: category = "metadata" if path in {"LICENSE", "package.json"} else "configuration"
        if category is None: continue
        raw = git("show", PIN + ":" + path)
        text = raw.decode()
        included = path in selected
        if included:
            status, reason = "adapted", "Topic-based rewrite; runtime APIs, model selection, global state, unsafe execution and automatic activation removed."
        elif category == "hooks" or path.endswith("/hooks.md"):
            status, reason = "excluded", "Automatic shell hooks are not provisioned or trusted; explicit session/verification/commit checkpoints replace supported outcomes."
        elif category == "metadata":
            status, reason = "non-executable", "License notice or package identity only."
        elif group == "skills":
            status, reason = "excluded", EXCLUSIONS[path.split("/")[1]]
        elif group == "commands":
            reason = "Requires external model orchestration unavailable through this read-only pack." if path.startswith("commands/multi-") else "Requires persistent session/instinct stores or process managers not provisioned by this pack."
            status = "excluded"
        else:
            status, reason = "excluded", "Installer/discovery configuration or upstream distribution instructions do not implement this read-only Cloud delivery contract."
        records[path] = {"sha256": digest(raw), "category": category, "status": status, "reason": reason,
                         "audit_hits": {name: len(re.findall(pattern, text)) for name, pattern in RISKS.items()}}
    if set(selected) - set(records): raise SystemExit("PACK_BUILD_SOURCE_MAPPING_MISSING")
    if json.loads(git("show", PIN + ":package.json"))["version"] != VERSION: raise SystemExit("PACK_BUILD_VERSION_MISMATCH")
    dump(PACK / "upstream.json", {"repository": REPOSITORY, "commit": PIN, "package_version": VERSION,
         "audit": "Every selected item is a topic-based instruction projection reviewed against the source headings and risk scan; no upstream executable content is copied. Source SHA-256 values are over exact pinned Git blobs. Excluded sources are not delivered.", "files": records})
    (PACK / "LICENSE").write_bytes(git("show", PIN + ":LICENSE"))
    entries = []
    for item in projections:
        destination = PACK / item["path"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        role = item["id"].startswith("role/")
        text = "# " + item["title"] + "\n\n"
        text += "Instruction ID: `" + item["id"] + "`.\n"
        text += "Requires: " + item["requires"] + ".\n\n"
        text += "Follow project-local AGENTS.md and higher-priority instructions. Use the existing task authorization. If a required tool or decision is absent, report BLOCKED for that step and continue independent authorized work.\n\n"
        if role:
            text += "This role brief does not create an agent. Follow docs/native-review.md in the attached wrapper for bounded role selection, native dispatch and provider receipts. For independent review, pass this verified brief to an available independent native Codex agent with source HEAD, exact staged tree, assigned roles, scope, risk, project rules and marked user-supplied verbatim hunks. Inspect immutable staged tree blobs; do not edit files or the index. A self-review cannot approve its own work.\n\n"
        if item.get("uses"):
            text += "Inputs: " + item["inputs"] + ".\nRead `" + item["uses"] + "` using the verified pack reader before applying these steps.\n\n"
        text += "## Procedure\n\n" + item["body"] + "\n\n"
        text += "## Completion report\n\nReport the input/scope, inspected paths, concrete output or findings, executed checks with exits and case counts, and unavailable dependencies. Separate local evidence from provider invocation."
        if role:
            text += " A review must name source HEAD, staged tree and assigned roles and give APPROVED or NOT_APPROVED, with severity and evidence for every finding. Return inspected paths and actual checks. The coordinator must retain the actual provider dispatch/completion references separately; never invent them. Findings above LOW, a blocked review or no explicit approval block committing."
        text += "\n\nAdapted from `" + "`, `".join(item["sources"]) + "` at upstream `" + PIN + "`; see `LICENSE` and `upstream.json`.\n"
        destination.write_text(text)
        entries.append({k: v for k, v in item.items() if k != "body"})
    dump(PACK / "catalog.json", {"schema_version": 1, "items": entries})
    routes = [("Plan / architecture", "workflow/plan"), ("Implement / TDD", "workflow/tdd"), ("Debug build", "workflow/build-fix"), ("Review", "workflow/code-review"), ("Security", "skill/security-review"), ("Verify completion", "workflow/verify"), ("Python", "skill/python-patterns"), ("Go", "skill/golang-patterns"), ("TypeScript", "skill/coding-standards"), ("Database", "skill/database-migrations")]
    catalog = "# Shared Cloud workflow catalog\n\nUse: apply workflow NAME from the shared Codex pack. These are explicit instruction reads, not native selectors or slash commands.\n\nRun `python3 -I /workspace/my-harness-wrapper/scripts/pack-codex.py read ID` to verify and read one entry and its linked brief. Read project policy first. No setup writes to target repositories.\n\n| Intent | ID | Exact wrapper path | Requirements |\n| --- | --- | --- | --- |\n"
    by_id = {x["id"]: x for x in entries}
    for intent, ident in routes:
        item = by_id[ident]
        catalog += "| " + " | ".join([intent, "`" + ident + "`", "`/workspace/my-harness-wrapper/config/codex/cloud-pack/" + item["path"] + "`", item["requires"]]) + " |\n"
    catalog += "\nThe full lazy inventory (skills, roles, rules and explicit workflows) is `catalog.json`. Before committing, obtain real independent native reviews of the exact staged tree and use `commit-codex.sh`. Briefs alone do not satisfy that gate. Report selected ID, output, checks and capability limits at completion.\n"
    (PACK / "CATALOG.md").write_text(catalog)
    artifacts = {}
    for path in sorted(PACK.rglob("*")):
        if path.is_file():
            name = path.relative_to(PACK).as_posix()
            item = next((x for x in entries if x["path"] == name), None)
            sources = item["sources"] if item else (["LICENSE"] if name == "LICENSE" else [])
            artifacts[name] = {"sha256": digest(path.read_bytes()), "upstream_paths": sources}
    dump(PACK / "manifest.json", {"schema_version": 1, "repository": REPOSITORY, "commit": PIN, "package_version": VERSION, "files": artifacts})
    (ROOT / "config/codex/pack.sha256").write_text(digest((PACK / "manifest.json").read_bytes()) + "\n")
    print(json.dumps({"adapted": {kind: sum(x["id"].startswith(kind + "/") for x in entries) for kind in ["skill", "role", "workflow", "rule"]}, "manifest_sha256": digest((PACK / "manifest.json").read_bytes())}))


if __name__ == "__main__":
    main()
