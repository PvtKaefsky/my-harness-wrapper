import argparse
import json
import os
import sys
from pathlib import Path

from . import gitguard
from .install import Installation
from .pack import PIN, Pack, decode
from .storage import json_bytes


def main(root: Path) -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description="Native local Codex harness")
    default_state = Path(os.environ.get("LOCALAPPDATA", str(Path.home() / ".local/state"))) / "my-harness-wrapper/codex"
    parser.add_argument("--state", type=Path, default=Path(os.environ.get("HARNESS_STATE_DIR", default_state)))
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("verify-source")
    body_check = sub.add_parser("check-body")
    body_check.add_argument("path", type=Path)
    read = sub.add_parser("read")
    read.add_argument("--source", action="store_true")
    read.add_argument("ident")
    install = sub.add_parser("install")
    install.add_argument("--profile", type=Path)
    install.add_argument("--codex-home", type=Path)
    install.add_argument("--apply", action="store_true")
    for name in ["doctor", "session-check", "hook", "review-requirements"]:
        sub.add_parser(name)
    for name in ["uninstall", "rollback", "recover"]:
        action = sub.add_parser(name)
        action.add_argument("--apply", action="store_true", required=True)
    approval = sub.add_parser("approve-identity")
    approval.add_argument("--apply", action="store_true", required=True)
    commit_parser = sub.add_parser("commit", add_help=False)
    commit_parser.add_argument("arguments", nargs=argparse.REMAINDER)
    args, extras = parser.parse_known_args()
    if extras and args.command != "commit":
        parser.error("unrecognized arguments: " + " ".join(extras))
    installation = Installation(root, args.state)
    if args.command == "verify-source":
        pack = Pack(root).verify()
        print("PASS PACK_SOURCE_VERIFIED commit=" + PIN
              + " manifest_sha256=" + pack.anchor)
    elif args.command == "check-body":
        if gitguard.ATTRIBUTION.search(args.path.read_text(encoding="utf-8")):
            raise ValueError("BODY_ATTRIBUTION_FORBIDDEN")
        print("PASS ATTRIBUTION_BODY")
    elif args.command == "read":
        directory = root if args.source else installation.verify()[1]
        print(Pack(directory).verify().read(args.ident))
    elif args.command == "install":
        if args.apply:
            print(installation.apply(args.profile, args.codex_home))
        else:
            plan = installation.plan(args.profile, args.codex_home)
            print("INSTALL_PLAN\n" + json.dumps(
                {key: plan[key] for key in ["profile", "codex_home", "source_hash"]},
                ensure_ascii=False))
            print("\n".join(record["path"] for record in plan["artifacts"]))
    elif args.command in {"doctor", "session-check"}:
        manifest, directory = installation.verify()
        print("SOURCE_AND_DELIVERY=VERIFIED release=" + manifest["release"])
        print("SOURCE_COMMIT=" + str(manifest.get("source_commit")))
        print("SOURCE_DIRTY=" + str(manifest.get("source_dirty")))
        print("HOOK_TRUST=REQUIRES_PROVIDER_EVIDENCE")
        print("NATIVE_DISCOVERY=REQUIRES_FRESH_PROVIDER_SESSION")
        print(Pack(directory).verify().catalog())
    elif args.command == "hook":
        raw = sys.stdin.buffer.read(1024 * 1024 + 1)
        if len(raw) > 1024 * 1024:
            raise ValueError("HOOK_INPUT_TOO_LARGE")
        event = decode(raw)
        if not isinstance(event, dict):
            raise ValueError("HOOK_INPUT_INVALID")
        name = event.get("hook_event_name")
        if name == "SessionStart":
            manifest, directory = installation.verify()
            output = {"hookSpecificOutput": {
                "hookEventName": name,
                "additionalContext": "Local harness release " + manifest["release"] + ".\n"
                + "Harness root: " + str(directory) + "\nNative review protocol: "
                + str(directory / "docs/native-review.md") + "\n"
                + Pack(directory).verify().catalog()}}
        elif name == "UserPromptSubmit":
            installation.verify()
            output = {"hookSpecificOutput": {
                "hookEventName": name,
                "additionalContext": "Follow shared and project AGENTS.md. Use TDD and real independent "
                "staged-tree reviews; use the guarded commit command. Do not infer approval from silence."}}
        elif name == "PreToolUse":
            import re
            installation.verify()
            tool = event.get("tool_name", "")
            inputs = event.get("tool_input", {})
            if not isinstance(inputs, dict):
                raise ValueError("HOOK_INPUT_INVALID")
            body = inputs.get("body")
            command = inputs.get("command", inputs.get("cmd", ""))
            denied = isinstance(body, str) and "github" in tool and gitguard.ATTRIBUTION.search(body)
            denied = denied or (tool in {"Bash", "exec_command", "functions.exec_command"}
                                and isinstance(command, str) and re.match(
                                    r"^\s*(?:&\s*)?git(?:\.exe)?\s+commit(?:\s|$)", command, re.I))
            output = {"hookSpecificOutput": {"hookEventName": name,
                      "permissionDecision": "deny", "permissionDecisionReason":
                      "Use the guarded commit command and attribution-free prepared bodies."}} if denied else {}
        else:
            output = {}
        print(json.dumps(output, ensure_ascii=False))
    elif args.command == "review-requirements":
        print(json.dumps(gitguard.requirements()))
    elif args.command == "approve-identity":
        from .storage import atomic_write
        installation.verify()
        atomic_write(installation.state / "approved-identity.json", json_bytes(gitguard.identity()))
        print("PASS LOCAL_GIT_IDENTITY_APPROVED")
    elif args.command == "commit":
        installation.verify()
        approval = installation.state / "approved-identity.json"
        from .install import current_bytes
        approved = current_bytes(approval)
        if approved is not None:
            from .storage import owner_check
            owner_check(approval)
        identity = decode(approved) if approved is not None else None
        print(gitguard.commit(extras + args.arguments, identity, os.environ.get("HARNESS_REVIEW_FILE")))
    else:
        print(getattr(installation, args.command)())
