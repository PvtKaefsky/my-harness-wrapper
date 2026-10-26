from typing import Any
import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / "scripts" / "codex-local.py"



def private_fixture(path: Path, allow_world_write: bool = False, inherit_only: bool = False, delete_child: bool = False) -> None:
    if os.name != "nt":
        path.chmod(0o777 if allow_world_write else 0o700)
        return
    import ctypes
    from ctypes import wintypes
    api = ctypes.WinDLL("advapi32", use_last_error=True)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    restricted = ctypes.c_void_p()
    token = wintypes.HANDLE()
    sid = wintypes.LPWSTR()
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    api.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE)]
    api.GetTokenInformation.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p,
                                        wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
    api.ConvertSidToStringSidW.argtypes = [ctypes.c_void_p, ctypes.POINTER(wintypes.LPWSTR)]
    api.ConvertStringSecurityDescriptorToSecurityDescriptorW.argtypes = [
        wintypes.LPCWSTR, wintypes.DWORD, ctypes.POINTER(ctypes.c_void_p), ctypes.c_void_p]
    api.SetFileSecurityW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, ctypes.c_void_p]
    kernel.LocalFree.argtypes = [ctypes.c_void_p]
    try:
        if not api.OpenProcessToken(kernel.GetCurrentProcess(), 8, ctypes.byref(token)):
            raise OSError("Cannot inspect disposable fixture user")
        size = wintypes.DWORD()
        api.GetTokenInformation(token, 1, None, 0, ctypes.byref(size))
        buffer = ctypes.create_string_buffer(size.value)
        if not api.GetTokenInformation(token, 1, buffer, size, ctypes.byref(size)):
            raise OSError("Cannot resolve disposable fixture user")
        user = ctypes.cast(buffer, ctypes.POINTER(ctypes.c_void_p))[0]
        if not api.ConvertSidToStringSidW(user, ctypes.byref(sid)):
            raise OSError("Cannot resolve disposable fixture owner")
        sddl = "O:" + sid.value + "D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FA;;;" + sid.value + ")"
        if allow_world_write:
            sddl += "(A;OICI" + ("IO" if inherit_only else "") + (";DC;;;WD)" if delete_child else ";FW;;;WD)")
        if not api.ConvertStringSecurityDescriptorToSecurityDescriptorW(
                sddl, 1, ctypes.byref(restricted), None):
            raise OSError("Cannot create private fixture descriptor")
        if not api.SetFileSecurityW(str(path), 0x80000005, restricted):
            raise OSError("Cannot secure disposable fixture")
    finally:
        if token:
            kernel.CloseHandle(token)
        for value in [sid, restricted]:
            if value:
                kernel.LocalFree(value)


class LocalHarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory(prefix="harness-local-")
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name) / "Виктор user"
        self.base.mkdir()
        private_fixture(self.base)
        self.profile = self.base / "profile"
        self.state = self.base / "state"
        self.target = self.base / "target"
        self.target.mkdir()
        self.environment = {key: value for key, value in os.environ.items()
                            if not key.startswith(("GIT_", "HARNESS_")) and key != "CODEX_HOME"}
        self.environment.update(GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM="1")
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture User")
        self.git("config", "user.email", "fixture@example.invalid")

    def git(self, *args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", "-C", str(self.target), *args], capture_output=True,
            text=True, encoding="utf-8", check=check, env=self.environment,
        )

    def run_cli(self, *args: object, expected: int = 0, source: Path = ROOT, stdin: str | None = None, env: dict[str, str] | None = None) -> str:
        environment = dict(self.environment)
        allowed = {"HARNESS_REVIEW_FILE", "GIT_DIR", "GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL",
                   "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"}
        for key, value in (env or {}).items():
            if key not in allowed:
                continue
            if key in {"HARNESS_REVIEW_FILE", "GIT_DIR"}:
                self.assertTrue(Path(value).resolve().is_relative_to(self.base.resolve()),
                                "Fixture environment points outside its disposable root")
            environment[key] = value
        environment["CODEX_HOME"] = str(self.profile / ".codex")
        command = [sys.executable, "-X", "utf8", "-I", str(source / "scripts/codex-local.py"),
                   "--state", str(self.state), *map(str, args)]
        result = subprocess.run(command, cwd=self.target, input=stdin,
                                capture_output=True, text=True, encoding="utf-8",
                                env=environment, errors="replace")
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result.stdout + result.stderr

    def install(self, *extra: object) -> str:
        return self.run_cli("install", "--profile", self.profile, "--apply", *extra)

    def test_source_and_full_workflow_reader(self) -> None:
        self.assertIn("PACK_SOURCE_VERIFIED", self.run_cli("verify-source"))
        output = self.run_cli("read", "--source", "workflow/tdd")
        self.assertIn("WORKFLOW_INSTRUCTION_READ", output)
        self.assertIn("skill/tdd-workflow", output)

    def test_full_upstream_body_preserved(self) -> None:
        self.assertTrue((ROOT / "config/codex/pack/upstream.json").is_file(), "Native pack missing")
        source = json.loads((ROOT / "config/codex/pack/upstream.json").read_text())
        self.assertEqual(source["commit"], "d468c521f1a76e7b05d446d805f6ad2afa8ed066")
        body = (ROOT / "config/codex/pack/roles/code-reviewer.md").read_text()
        self.assertIn("Confidence-Based Filtering", body)
        self.assertIn("Hardcoded credentials", body)

    def test_dry_run_writes_nothing(self) -> None:
        output = self.run_cli("install", "--profile", self.profile)
        self.assertIn("INSTALL_PLAN", output)
        self.assertFalse(self.profile.exists())
        self.assertFalse(self.state.exists())

    def test_install_native_assets_and_verify(self) -> None:
        self.install()
        self.assertIn("SOURCE_AND_DELIVERY=VERIFIED", self.run_cli("doctor"))
        skills = list((self.profile / ".agents/skills").glob("harness-*/SKILL.md"))
        agents = list((self.profile / ".codex/agents").glob("harness-*.toml"))
        self.assertEqual(len(skills), 58)
        self.assertEqual(len(agents), 14)
        for path in agents:
            agent = tomllib.loads(path.read_text(encoding="utf-8"))
            self.assertTrue(agent["name"].startswith("harness-"))
            self.assertIn("developer_instructions", agent)
            self.assertNotIn("model", agent)
        self.assertFalse((self.target / ".agents").exists())
        self.assertFalse((self.target / ".codex").exists())

    def test_preserve_policy_hooks_and_configuration(self) -> None:
        home = self.profile / ".codex"
        home.mkdir(parents=True)
        original = b"# Personal policy\r\n\r\nKeep my preferences.\r\n"
        (home / "AGENTS.md").write_bytes(original)
        configuration = b'model = "user-choice"\n'
        (home / "config.toml").write_bytes(configuration)
        other = {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "echo retained"}]}]}}
        (home / "hooks.json").write_text(json.dumps(other), encoding="utf-8")
        self.install()
        self.assertTrue((home / "AGENTS.md").read_bytes().startswith(original))
        self.assertEqual((home / "config.toml").read_bytes(), configuration)
        self.assertEqual(json.loads((home / "hooks.json").read_text())["hooks"]["Stop"],
                         other["hooks"]["Stop"])
        self.run_cli("uninstall", "--apply")
        self.assertEqual((home / "AGENTS.md").read_bytes(), original)
        self.assertEqual(json.loads((home / "hooks.json").read_text()), other)
        self.assertEqual((home / "config.toml").read_bytes(), configuration)

    def test_unowned_collision_stops_without_partial_install(self) -> None:
        collision = self.profile / ".agents/skills/harness-python-patterns/SKILL.md"
        collision.parent.mkdir(parents=True)
        collision.write_text("User-owned content", encoding="utf-8")
        self.run_cli("install", "--profile", self.profile, "--apply", expected=1)
        self.assertEqual(collision.read_text(), "User-owned content")
        self.assertFalse((self.profile / ".codex/AGENTS.md").exists())

    def test_modified_owned_file_blocks_upgrade_and_uninstall(self) -> None:
        self.install()
        path = self.profile / ".agents/skills/harness-python-patterns/SKILL.md"
        path.write_text("My modified instructions", encoding="utf-8")
        self.run_cli("install", "--profile", self.profile, "--apply", expected=1)
        self.run_cli("uninstall", "--apply", expected=1)
        self.assertEqual(path.read_text(), "My modified instructions")

    def test_idempotent_install_and_rollback(self) -> None:
        self.install()
        before = (self.state / "active.json").read_bytes()
        self.install()
        self.assertEqual((self.state / "active.json").read_bytes(), before)
        self.run_cli("rollback", "--apply")
        self.assertFalse((self.profile / ".agents/skills/harness-python-patterns/SKILL.md").exists())

    def test_shadowed_policy_reported(self) -> None:
        home = self.profile / ".codex"
        home.mkdir(parents=True)
        (home / "AGENTS.override.md").write_text("Override policy", encoding="utf-8")
        self.run_cli("install", "--profile", self.profile, "--apply", expected=1)
        self.assertFalse((home / "AGENTS.md").exists())

    def test_session_hook_is_context_not_fake_trust(self) -> None:
        self.install()
        self.assertIn("HOOK_TRUST=REQUIRES_PROVIDER_EVIDENCE", self.run_cli("doctor"))
        event = json.dumps({"hook_event_name": "SessionStart", "source": "startup",
                            "cwd": str(self.target)})
        output = self.run_cli("hook", stdin=event)
        self.assertEqual(json.loads(output)["hookSpecificOutput"]["hookEventName"], "SessionStart")
        self.assertIn("workflow/plan", output)

    def test_hook_unknown_event_and_malformed_input(self) -> None:
        self.run_cli("hook", stdin="{", expected=1)
        self.assertEqual(json.loads(self.run_cli("hook", stdin=json.dumps({
            "hook_event_name": "UnknownEvent"}))), {})

    def test_git_identity_and_review_remain_fail_closed(self) -> None:
        (self.target / "file.txt").write_text("hello\n", encoding="utf-8", newline="\n")
        self.git("add", "file.txt")
        self.run_cli("commit", "-m", "feat: fixture", expected=1)
        self.assertNotEqual(self.git("rev-parse", "--verify", "HEAD", check=False).returncode, 0)
        output = self.run_cli("review-requirements")
        self.assertEqual(json.loads(output)["required_roles"], ["general"])

    def test_unrelated_hooks_survive_user_changes(self) -> None:
        self.install()
        path = self.profile / ".codex/hooks.json"
        data = json.loads(path.read_text())
        data["hooks"]["Stop"] = [{"hooks": [{"type": "command", "command": "echo later"}]}]
        path.write_text(json.dumps(data), encoding="utf-8")
        self.run_cli("uninstall", "--apply")
        self.assertEqual(json.loads(path.read_text())["hooks"]["Stop"][0]["hooks"][0]["command"],
                         "echo later")

    def test_tampered_pack_rejected(self) -> None:
        copy = self.base / "source"
        shutil.copytree(ROOT, copy, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        artifact = copy / "config/codex/pack/roles/code-reviewer.md"
        self.assertTrue(artifact.is_file(), "Native pack missing")
        artifact.write_text("tampered\n", encoding="utf-8")
        self.run_cli("verify-source", source=copy, expected=1)


    def source_copy(self) -> Path:
        copy = self.base / "copy"
        shutil.copytree(ROOT, copy, ignore=shutil.ignore_patterns(".git", "__pycache__"))
        return copy

    def receipt(self) -> tuple[Path, dict[str, Any]]:
        requirement = json.loads(self.run_cli("review-requirements"))
        roles = requirement["required_roles"]
        receipt = {"provider": "native-codex", "status": "REVIEW_COMPLETED",
                   "reviewer_id": "synthetic-fixture-reviewer",
                   "source_commit": requirement["source_commit"], "tree": requirement["tree"],
                   "roles": roles, "verdict": "APPROVED", "findings": [],
                   "dispatch_id": "synthetic-fixture-dispatch",
                   "completion_id": "synthetic-fixture-completion",
                   "transcript_ref": "synthetic fixture only"}
        review = {"reviewer_id": receipt["reviewer_id"], "tree": requirement["tree"],
                  "roles": roles, "verdict": "APPROVED", "findings": [],
                  "evidence": "Synthetic protocol fixture, not provider acceptance",
                  "provider_receipt": receipt}
        record = {"schema_version": 2, "provider": "native-codex",
                  "implementer_id": "synthetic-fixture-implementer",
                  **requirement, "reviews": [review]}
        path = self.base / "review.json"
        path.write_text(json.dumps(record), encoding="utf-8")
        return path, record

    def staged_fixture(self) -> None:
        self.install()
        (self.target / "file.txt").write_text("first\n", encoding="utf-8", newline="\n")
        self.git("add", "file.txt")
        self.run_cli("approve-identity", "--apply")

    def test_protocol_fixture_commit_and_stale_tree(self) -> None:
        self.staged_fixture()
        path, record = self.receipt()
        environment = dict(os.environ, HARNESS_REVIEW_FILE=str(path))
        (self.target / "file.txt").write_text("second\n", encoding="utf-8", newline="\n")
        self.git("add", "file.txt")
        self.assertIn("INDEPENDENT_REVIEW_STALE",
                      self.run_cli("commit", "-m", "feat: fixture", expected=1, env=environment))
        path, record = self.receipt()
        self.assertIn("GUARDED_COMMIT_PASSED",
                      self.run_cli("commit", "-m", "feat: fixture", env=environment))
        self.assertEqual(self.git("log", "-1", "--format=%an <%ae>").stdout.strip(),
                         "Fixture User <fixture@example.invalid>")

    def test_reject_self_negative_and_missing_proof(self) -> None:
        self.staged_fixture()
        path, record = self.receipt()
        environment = dict(os.environ, HARNESS_REVIEW_FILE=str(path))
        for mutation, failure in [("self", "INDEPENDENT_REVIEW_NOT_INDEPENDENT"),
                                  ("verdict", "INDEPENDENT_REVIEW_NOT_APPROVED"),
                                  ("proof", "INDEPENDENT_REVIEW_PROVIDER_PROOF_MISSING")]:
            changed = json.loads(json.dumps(record))
            if mutation == "self":
                changed["implementer_id"] = changed["reviews"][0]["reviewer_id"]
            elif mutation == "verdict":
                changed["reviews"][0]["verdict"] = "NOT_APPROVED"
            else:
                changed["reviews"][0]["provider_receipt"]["completion_id"] = ""
            path.write_text(json.dumps(changed), encoding="utf-8")
            self.assertIn(failure, self.run_cli("commit", "-m", "feat: fixture", expected=1, env=environment))
        self.assertNotEqual(self.git("rev-parse", "--verify", "HEAD", check=False).returncode, 0)

    def test_unsafe_commit_arguments_and_attribution(self) -> None:
        self.staged_fixture()
        path, record = self.receipt()
        environment = dict(os.environ, HARNESS_REVIEW_FILE=str(path))
        self.assertIn("COMMIT_ARGUMENT_UNSAFE", self.run_cli(
            "commit", "--all", "-m", "feat: fixture", expected=1, env=environment))
        self.assertIn("COMMIT_ATTRIBUTION_FORBIDDEN", self.run_cli(
            "commit", "-m", "feat: fixture\n\nCo-Authored-By: Agent <agent@example.invalid>",
            expected=1, env=environment))

    def test_identity_environment_override_rejected(self) -> None:
        self.staged_fixture()
        path, record = self.receipt()
        environment = dict(os.environ, HARNESS_REVIEW_FILE=str(path),
                           GIT_AUTHOR_NAME="Different", GIT_AUTHOR_EMAIL="different@example.invalid")
        self.assertIn("GIT_IDENTITY", self.run_cli(
            "commit", "-m", "feat: fixture", expected=1, env=environment))

    def test_project_git_hook_blocks_without_disabling(self) -> None:
        self.staged_fixture()
        path = self.target / ".git/hooks/pre-commit"
        path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8", newline="\n")
        path.chmod(0o755)
        self.assertIn("COMMIT_HOOK_REVIEW_BOUNDARY",
                      self.run_cli("review-requirements", expected=1))
        self.assertTrue(path.exists())

    def test_upgrade_and_rollback_restore_previous_release(self) -> None:
        home = self.profile / ".codex"
        home.mkdir(parents=True)
        (home / "AGENTS.md").write_bytes(b"Personal policy without newline")
        self.install()
        active_before = (self.state / "active.json").read_bytes()
        copy = self.source_copy()
        with open(copy / "scripts/codex-local.py", "ab") as stream:
            stream.write(b"\n")
        self.run_cli("install", "--profile", self.profile, "--apply", source=copy)
        self.assertNotEqual((self.state / "active.json").read_bytes(), active_before)
        self.run_cli("rollback", "--apply")
        self.assertEqual((self.state / "active.json").read_bytes(), active_before)
        self.run_cli("doctor")
        self.run_cli("uninstall", "--apply")
        self.assertEqual((home / "AGENTS.md").read_bytes(), b"Personal policy without newline")

    def test_recovery_preserves_expected_and_refuses_concurrent_edits(self) -> None:
        self.install()
        active = (self.state / "active.json").read_bytes()
        info = json.loads(active)
        manifest = json.loads((self.state / "releases" / info["release"] / "manifest.json").read_text())
        artifact = next(r for r in manifest["artifacts"] if r["kind"] == "file")
        import base64
        before = Path(artifact["path"]).read_bytes()
        replacement = b"interrupted transaction"
        records = [{"path": item["path"], "expected": item["after"], "after": item["after"]}
                   for item in manifest["artifacts"]]
        next(item for item in records if item["path"] == artifact["path"])["after"] = base64.b64encode(replacement).decode()
        journal = {"schema_version": 1, "active_before": base64.b64encode(active).decode(),
                   "active_after": None, "records": records}
        (self.state / "journal.json").write_text(json.dumps(journal))
        Path(artifact["path"]).write_bytes(b"Concurrent user change")
        self.run_cli("recover", "--apply", expected=1)
        self.assertEqual(Path(artifact["path"]).read_bytes(), b"Concurrent user change")
        Path(artifact["path"]).write_bytes(replacement)
        self.run_cli("recover", "--apply")
        self.assertEqual(Path(artifact["path"]).read_bytes(), before)
        self.run_cli("doctor")

    def test_hook_denies_only_supported_direct_commands_and_bodies(self) -> None:
        self.install()
        for tool, inputs in [("exec_command", {"cmd": "git commit -m message"}),
                             ("mcp__github_create_issue", {"body": "Generated by Agent"})]:
            event = json.dumps({"hook_event_name": "PreToolUse", "tool_name": tool,
                                "tool_input": inputs})
            output = json.loads(self.run_cli("hook", stdin=event))
            self.assertEqual(output["hookSpecificOutput"]["permissionDecision"], "deny")
        event = json.dumps({"hook_event_name": "PreToolUse", "tool_name": "exec_command",
                            "tool_input": {"cmd": "git status"}})
        self.assertEqual(json.loads(self.run_cli("hook", stdin=event)), {})

    def test_source_imports_not_shadowed_by_target_modules(self) -> None:
        for name in ["json.py", "subprocess.py", "hashlib.py"]:
            (self.target / name).write_text("raise RuntimeError('target module executed')\n")
        self.assertIn("PACK_SOURCE_VERIFIED", self.run_cli("verify-source"))

    def test_relative_and_repository_state_rejected(self) -> None:
        command = [sys.executable, "-X", "utf8", "-I", str(CLI),
                   "--state", "relative", "verify-source"]
        result = subprocess.run(command, cwd=self.target, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.state = self.target / "state"
        self.assertIn("INSTALL_TARGET_REPOSITORY_FORBIDDEN",
                      self.run_cli("install", "--profile", self.profile, "--apply", expected=1))

    def test_extra_installed_runtime_and_pack_files_rejected(self) -> None:
        self.install()
        info = json.loads((self.state / "active.json").read_bytes())
        directory = self.state / "releases" / info["release"]
        (directory / "scripts/unregistered.py").write_text("unexpected")
        self.assertIn("INSTALLED_RUNTIME_FILE_SET_MISMATCH",
                      self.run_cli("doctor", expected=1))
        copy = self.source_copy()
        (copy / "config/codex/pack/unregistered.md").write_text("unexpected")
        self.assertIn("PACK_FILE_SET_MISMATCH",
                      self.run_cli("verify-source", source=copy, expected=1))

    def test_offline_rebuild_matches_anchor(self) -> None:
        destination = self.base / "rebuilt"
        result = subprocess.run(
            [sys.executable, "-X", "utf8", "-I", str(ROOT / "scripts/build-pack.py"),
             "--output", str(destination)], capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual((destination / "manifest.json").read_bytes(),
                         (ROOT / "config/codex/pack/manifest.json").read_bytes())

    def test_original_source_and_selected_bodies_match(self) -> None:
        import hashlib
        inventory = json.loads((ROOT / "config/codex/source-inventory.json").read_text())
        catalog = json.loads((ROOT / "config/codex/catalog.json").read_text())
        for item in catalog["items"]:
            emitted = (ROOT / "config/codex/pack" / item["path"]).read_bytes()
            for name in item["sources"]:
                raw = (ROOT / "config/codex/upstream" / name).read_bytes()
                self.assertEqual(hashlib.sha256(raw).hexdigest(), inventory["files"][name]["sha256"])
                body = raw.decode("utf-8")
                if body.startswith("---"):
                    end = body.find("\n---", 3)
                    body = body[end + 4:].lstrip("\r\n")
                self.assertIn(body.encode("utf-8"), emitted)

    def test_git_line_ending_conversion_preserves_hashed_assets(self) -> None:
        shutil.copyfile(ROOT / ".gitattributes", self.target / ".gitattributes")
        artifact = self.target / "config/codex/pack/example.md"
        artifact.parent.mkdir(parents=True)
        artifact.write_bytes(b"exact\r\nupstream\r\n")
        self.git("config", "core.autocrlf", "true")
        self.git("add", ".gitattributes", "config/codex/pack/example.md")
        raw = subprocess.check_output(["git", "-C", str(self.target),
                                       "show", ":config/codex/pack/example.md"])
        self.assertEqual(raw, artifact.read_bytes())

    def test_windows_lane_and_documentation_index(self) -> None:
        workflow = json.loads((ROOT / ".github/workflows/codex.yml").read_text())
        job = workflow["jobs"]["regression"]
        self.assertIn("windows-latest", job["strategy"]["matrix"]["os"])
        self.assertTrue(any("test_local.py" in step.get("run", "") for step in job["steps"]))
        index = (ROOT / "docs/README.md").read_text()
        for path in (ROOT / "docs").glob("*.md"):
            if path.name != "README.md":
                self.assertIn(path.name, index)


    def test_prepared_body_both_allowed_and_denied(self) -> None:
        path = self.base / "body.md"
        path.write_text("A normal factual issue body.\n", encoding="utf-8")
        self.assertIn("PASS ATTRIBUTION_BODY", self.run_cli("check-body", path))
        path.write_text("Generated by Agent\n", encoding="utf-8")
        self.assertIn("BODY_ATTRIBUTION_FORBIDDEN",
                      self.run_cli("check-body", path, expected=1))

    def test_hard_link_registration_rejected(self) -> None:
        self.install()
        path = self.profile / ".agents/skills/harness-python-patterns/SKILL.md"
        os.link(path, self.base / "alias.md")
        self.assertIn("INSTALL_PATH_NOT_ORDINARY", self.run_cli("doctor", expected=1))

    def test_unowned_state_not_reused(self) -> None:
        self.state.mkdir()
        (self.state / "personal.txt").write_text("untouched")
        self.run_cli("install", "--profile", self.profile, "--apply", expected=1)
        self.assertEqual((self.state / "personal.txt").read_text(), "untouched")
        self.assertFalse((self.profile / ".codex/AGENTS.md").exists())

    def test_custom_codex_home_is_not_replaced_by_profile_default(self) -> None:
        home = self.base / "custom codex"
        self.run_cli("install", "--profile", self.profile, "--codex-home", home, "--apply")
        self.assertTrue((home / "AGENTS.md").exists())
        self.assertFalse((self.profile / ".codex").exists())
        self.run_cli("doctor")
        self.run_cli("uninstall", "--apply")

    def test_reparse_profile_is_rejected(self) -> None:
        outside = self.base / "outside"
        outside.mkdir()
        link = self.base / "link"
        try:
            os.symlink(outside, link, target_is_directory=True)
        except OSError as error:
            self.skipTest("Symlink creation unavailable: " + str(error))
        self.assertIn("PATH_REPARSE_POINT", self.run_cli(
            "install", "--profile", link, "--apply", expected=1))
        self.assertEqual(list(outside.iterdir()), [])

    def test_malicious_recovery_path_cannot_write_unrelated_file(self) -> None:
        self.install()
        import base64
        active = (self.state / "active.json").read_bytes()
        unrelated = self.base / "unrelated.txt"
        unrelated.write_bytes(b"keep")
        journal = {"schema_version": 1, "active_before": base64.b64encode(active).decode(),
                   "active_after": None, "records": [{
                       "path": str(unrelated), "expected": base64.b64encode(b"keep").decode(),
                       "after": base64.b64encode(b"overwrite").decode()}]}
        (self.state / "journal.json").write_text(json.dumps(journal))
        self.assertIn("RECOVERY_ARTIFACT_SET_INVALID",
                      self.run_cli("recover", "--apply", expected=1))
        self.assertEqual(unrelated.read_bytes(), b"keep")


    def test_registered_runtime_mutation_rejected(self) -> None:
        self.install()
        pointer = json.loads((self.state / "active.json").read_bytes())
        path = self.state / "releases" / pointer["release"] / "scripts/codex-local.py"
        with open(path, "ab") as stream:
            stream.write(b"\n")
        self.assertIn("INSTALLED_RUNTIME_MODIFIED",
                      self.run_cli("doctor", expected=1))

    def test_installed_hook_ignores_poisoned_bytecode_and_refuses_sourceless_fallback(self) -> None:
        import importlib.util
        import marshal
        import struct
        self.install()
        active = json.loads((self.state / "active.json").read_bytes())
        release = self.state / "releases" / active["release"]
        source = release / "scripts/harness_local/storage.py"
        cache = source.parent / "__pycache__" / ("storage." + sys.implementation.cache_tag + ".pyc")
        cache.parent.mkdir(exist_ok=True)
        payload = compile(source.read_bytes() + b'\nprint("DISPOSABLE_CACHE_EXECUTED")\n', str(source), "exec")
        bytecode = importlib.util.MAGIC_NUMBER + struct.pack(
            "<III", 0, int(source.stat().st_mtime), source.stat().st_size) + marshal.dumps(payload)
        cache.write_bytes(bytecode)
        private_fixture(cache, allow_world_write=True)
        self.run_cli("doctor")
        event = json.dumps({"hook_event_name": "UnknownEvent"})
        self.assertEqual(self.run_cli("hook", source=release, stdin=event).strip(), "{}")
        (source.parent / "storage.pyc").write_bytes(bytecode)
        source.unlink()
        result = subprocess.run([sys.executable, "-X", "utf8", "-I", str(release / "scripts/codex-local.py"),
                                 "--state", str(self.state), "hook"], input=event, cwd=self.target,
                                capture_output=True, text=True, encoding="utf-8", env=self.environment)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("HARNESS_SOURCE_MODULE_MISSING", result.stderr)
        self.assertNotIn("DISPOSABLE_CACHE_EXECUTED", result.stdout + result.stderr)

    def test_source_metadata_ignores_target_git_selectors(self) -> None:
        expected = subprocess.check_output(["git", "-C", str(ROOT), "rev-parse", "HEAD"]).decode().strip()
        environment = dict(os.environ, GIT_DIR=str(self.target / ".git"))
        self.run_cli("install", "--profile", self.profile, "--apply", env=environment)
        pointer = json.loads((self.state / "active.json").read_bytes())
        manifest = json.loads((self.state / "releases" / pointer["release"] / "manifest.json").read_bytes())
        self.assertEqual(manifest["source_commit"], expected)
        self.assertEqual(manifest["adapter_version"], "2.0.0")
        self.assertTrue((self.state / "releases" / pointer["release"] / "docs/native-review.md").exists())


    def test_world_writable_state_rejected(self) -> None:
        self.install()
        private_fixture(self.state, allow_world_write=True)
        output = self.run_cli("doctor", expected=1)
        self.assertTrue("STATE_ACL_BROAD_WRITE" in output or "STATE_OWNER_OR_PERMISSIONS_UNSAFE" in output)

    def catalog_source(self, add: bool = False) -> Path:
        import hashlib
        source = self.source_copy()
        path = source / "config/codex/catalog.json"
        catalog = json.loads(path.read_text())
        if add:
            item = dict(next(item for item in catalog["items"] if item["id"] == "skill/api-design"))
            item.update(id="skill/api-design-extra", path="skills/api-design-extra/SKILL.md")
            catalog["items"].append(item)
        else:
            catalog["items"] = [item for item in catalog["items"] if item["id"] != "skill/api-design"]
        path.write_text(json.dumps(catalog), encoding="utf-8")
        generated = source / "generated-pack"
        subprocess.run([sys.executable, "-X", "utf8", "-I", str(source / "scripts/build-pack.py"),
                        "--output", str(generated)], check=True, capture_output=True)
        destination = source / "config/codex/pack"
        self.assertTrue(destination.resolve().is_relative_to(self.base.resolve()))
        self.assertTrue(generated.resolve().is_relative_to(self.base.resolve()))
        shutil.rmtree(destination)
        shutil.move(str(generated), str(destination))
        anchor = hashlib.sha256((destination / "manifest.json").read_bytes()).hexdigest()
        (source / "config/codex/local-pack.sha256").write_text(anchor + "\n", encoding="ascii")
        return source

    def test_catalog_retirement_does_not_return_on_upgrade_or_uninstall(self) -> None:
        self.install()
        source = self.catalog_source()
        retired = self.profile / ".agents/skills/harness-api-design/SKILL.md"
        self.run_cli("install", "--profile", self.profile, "--apply", source=source)
        self.assertFalse(retired.exists())
        with open(source / "scripts/codex-local.py", "ab") as stream:
            stream.write(b"\n")
        self.run_cli("install", "--profile", self.profile, "--apply", source=source)
        self.assertFalse(retired.exists(), "A retired package returned during another upgrade")
        self.run_cli("uninstall", "--apply")
        self.assertFalse(retired.exists(), "A retired package returned during uninstall")

    def test_catalog_retirement_can_rollback_to_complete_predecessor(self) -> None:
        self.install()
        source = self.catalog_source()
        self.run_cli("install", "--profile", self.profile, "--apply", source=source)
        self.run_cli("rollback", "--apply")
        self.assertTrue((self.profile / ".agents/skills/harness-api-design/SKILL.md").exists())
        self.run_cli("doctor")

    def test_rollback_rejects_modified_predecessor_before_writes(self) -> None:
        self.install()
        old = json.loads((self.state / "active.json").read_bytes())
        path = self.state / "releases" / old["release"] / "scripts/codex-local.py"
        with open(path, "ab") as stream:
            stream.write(b"\n")
        source = self.source_copy()
        with open(source / "scripts/codex-local.py", "ab") as stream:
            stream.write(b"\n")
        self.run_cli("install", "--profile", self.profile, "--apply", source=source)
        active = (self.state / "active.json").read_bytes()
        self.assertIn("INSTALLED_RUNTIME_MODIFIED", self.run_cli("rollback", "--apply", expected=1))
        self.assertEqual((self.state / "active.json").read_bytes(), active)
        self.run_cli("doctor")

    def test_nested_unsafe_agent_directory_blocks_before_install_writes(self) -> None:
        directory = self.profile / ".codex/agents"
        directory.mkdir(parents=True)
        private_fixture(directory, allow_world_write=True)
        self.run_cli("install", "--profile", self.profile, "--apply", expected=1)
        self.assertFalse((self.profile / ".codex/AGENTS.md").exists())

    def test_modified_registration_acl_blocks_doctor(self) -> None:
        self.install()
        path = self.profile / ".codex/agents/harness-code-reviewer.toml"
        private_fixture(path, allow_world_write=True)
        self.run_cli("doctor", expected=1)

    def test_fixture_install_does_not_use_inherited_real_home(self) -> None:
        from unittest.mock import patch
        foreign = self.base / "foreign-home"
        with patch.dict(os.environ, {"CODEX_HOME": str(foreign)}):
            self.install()
        self.assertTrue((self.profile / ".codex/AGENTS.md").exists())
        self.assertFalse(foreign.exists())

    @unittest.skipUnless(os.name == "nt", "Windows command-hook runner")
    def test_registered_windows_hook_executes_through_comspec(self) -> None:
        self.install()
        data = json.loads((self.profile / ".codex/hooks.json").read_bytes())
        command = data["hooks"]["SessionStart"][0]["hooks"][0]["commandWindows"]
        runner = subprocess.list2cmdline([os.environ["COMSPEC"], "/C"]) + ' "' + command + '"'
        event = json.dumps({"hook_event_name": "SessionStart", "source": "startup"})
        result = subprocess.run(runner, input=event, cwd=self.target, capture_output=True,
                                text=True, encoding="utf-8", errors="replace")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(json.loads(result.stdout)["hookSpecificOutput"]["hookEventName"], "SessionStart")

    def test_interrupted_rollback_of_added_package_recovers_transition(self) -> None:
        self.install()
        source = self.catalog_source(add=True)
        self.run_cli("install", "--profile", self.profile, "--apply", source=source)
        active = (self.state / "active.json").read_bytes()
        module = source / "scripts/harness_local/install.py"
        original = module.read_text(encoding="utf-8")
        selector = "                atomic_write(path, value)"
        self.assertEqual(original.count(selector), 1)
        module.write_text(original.replace(selector, selector + "\n                raise OSError('fixture interruption')"),
                          encoding="utf-8")
        self.run_cli("rollback", "--apply", source=source, expected=1)
        self.assertTrue((self.state / "journal.json").exists())
        self.run_cli("recover", "--apply")
        self.assertEqual((self.state / "active.json").read_bytes(), active)
        self.assertTrue((self.profile / ".agents/skills/harness-api-design-extra/SKILL.md").exists())
        self.run_cli("doctor")


    @unittest.skipUnless(os.name == "nt", "Windows inheritable ACLs")
    def test_inherit_only_unsafe_destination_blocks_before_writes(self) -> None:
        directory = self.profile / ".codex/agents"
        directory.mkdir(parents=True)
        private_fixture(directory, allow_world_write=True, inherit_only=True)
        self.run_cli("install", "--profile", self.profile, "--apply", expected=1)
        self.assertFalse((self.profile / ".codex/AGENTS.md").exists())

    def test_unsafe_discovery_ancestor_blocks_install_and_doctor(self) -> None:
        directory = self.profile / ".agents"
        (directory / "skills").mkdir(parents=True)
        private_fixture(directory / "skills")
        private_fixture(directory, allow_world_write=True)
        self.run_cli("install", "--profile", self.profile, "--apply", expected=1)
        self.assertFalse((self.profile / ".codex/AGENTS.md").exists())
        private_fixture(directory)
        self.install()
        private_fixture(directory, allow_world_write=True)
        self.run_cli("doctor", expected=1)

    def test_state_trust_boundary_remains_checked_after_creation(self) -> None:
        boundary = self.base / "private-state-parent"
        boundary.mkdir()
        self.state = boundary / "new-parent/state"
        self.install()
        private_fixture(self.state.parent)
        private_fixture(boundary, allow_world_write=True)
        self.run_cli("doctor", expected=1)
        self.run_cli("rollback", "--apply", expected=1)

    @unittest.skipUnless(os.name == "nt", "Windows directory deletion ACL")
    def test_delete_child_permission_blocks_install_and_doctor(self) -> None:
        directory = self.profile / ".codex/agents"
        directory.mkdir(parents=True)
        private_fixture(directory, allow_world_write=True, delete_child=True)
        self.run_cli("install", "--profile", self.profile, "--apply", expected=1)
        private_fixture(directory)
        self.install()
        private_fixture(directory, allow_world_write=True, delete_child=True)
        self.run_cli("doctor", expected=1)

    @unittest.skipUnless(os.name == "nt", "Windows process token default owner")
    def test_current_windows_token_default_owner_is_accepted(self) -> None:
        import runpy
        runpy.run_path(str(CLI))
        directory = self.base / "default-process-owner"
        directory.mkdir()
        sys.modules["harness_local.storage"].owner_check(directory)

    @unittest.skipUnless(os.name == "nt", "Windows command expansion")
    def test_expansion_characters_rejected_before_install_writes(self) -> None:
        for name in ["state%HARNESS_EXPANSION%", "state!HARNESS_EXPANSION!"]:
            self.state = self.base / name
            self.assertIn("WINDOWS_HOOK_PATH_UNSUPPORTED", self.run_cli(
                "install", "--profile", self.profile, "--apply", expected=1))
            self.assertFalse(self.state.exists())
            self.assertFalse((self.profile / ".codex/AGENTS.md").exists())

    @unittest.skipUnless(os.name == "nt", "Windows command quoting")
    def test_windows_shell_metacharacters_are_quoted_without_spaces(self) -> None:
        import runpy
        runpy.run_path(str(CLI))
        windows_command = sys.modules["harness_local.install"].windows_command
        argument = r"C:\harness&ver^(safe)|value"
        command = windows_command([sys.executable, "-c", "import sys;print(sys.argv[1])", argument])
        runner = subprocess.list2cmdline([os.environ["COMSPEC"], "/C"]) + ' "' + command + '"'
        result = subprocess.run(runner, capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout.strip(), argument)

if __name__ == "__main__":
    unittest.main()
