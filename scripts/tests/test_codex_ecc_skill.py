#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile

from test_codex_ecc import Fixture


PASSES = 0
EXPECTED = "103e0130dac33a49d26705fc5a2df804980fcab6a0138d65bc7f370a987d49f6"


def check(name, condition):
    global PASSES
    if not condition:
        raise AssertionError(name)
    PASSES += 1
    print(f"PASS {name}", flush=True)


class SkillFixture(Fixture):
    def __init__(self, parent, name, scenario="success", missing_parents=False):
        super().__init__(parent, name)
        self.env["ECC_TEST_CASE"] = scenario
        self.scope = self.home / ".agents/skills"
        self.unrelated = self.scope / "unrelated/keep.txt"
        self.unrelated.parent.mkdir(parents=True)
        self.unrelated.write_bytes(b"unrelated user skill\n")
        self.destination = self.scope / "python-patterns"
        self.source = self.root / "config/codex/ecc-python-patterns"
        self.extra = self.home / "keep.txt"
        self.extra.write_bytes(b"unrecognized home file\n")
        if missing_parents:
            shutil.rmtree(self.home / ".agents")

    def skill_evidence(self):
        directory = self.state / "ecc-skill-probe"
        data = json.loads((directory / "status.json").read_text())
        assert data["log_sha256"] == hashlib.sha256((directory / "diagnostic.log").read_bytes()).hexdigest()
        return data

    def skill_contract(self):
        code, output = self.run("scripts/session-check-codex.sh")
        assert "ECC_SKILL_PLACEMENT_MISSING" not in output, "ECC_SKILL_PLACEMENT_MISSING"
        assert "ECC_SKILL_FILES_PERSISTED" in output, "ECC_SKILL_FILES_NOT_PERSISTED"
        assert "ECC_SKILL_NATIVE_DISCOVERY_NOT_OBSERVED" in output and "ECC_SKILL_INVOCATION_UNVERIFIED" in output, "ECC_SKILL_TASK_MEASUREMENT_NOT_CONSUMED"
        assert code == 2 and "ECC NOT READY" in output and "ECC READY" not in output, "ECC_SKILL_READINESS_PROMOTED"
        return output


def main():
    with tempfile.TemporaryDirectory(prefix="codex-ecc-skill-") as temporary:
        parent = Path(temporary)
        positive = SkillFixture(parent, "placement")
        original = positive.unrelated.read_bytes()
        positive.setup()
        data = positive.skill_evidence()
        data_pin = data["source_files"]
        delivered = (positive.destination / "SKILL.md").read_bytes()
        check("real setup entry point: pinned unchanged bytes placed in documented user scope",
              data["placement"] == "PLACED" and data["complete"] is True and data["safely_delivered"] is True and
              data["preexisting"] is False and data["source_files"]["SKILL.md"] == EXPECTED and
              hashlib.sha256(delivered).hexdigest() == EXPECTED and
              delivered == (Path(positive.env["ECC_TEST_FIXTURES"]) / "SKILL.md").read_bytes())
        check("bounded delivery: only skill and required upstream MIT notice",
              set(os.listdir(positive.destination)) == {"SKILL.md", "LICENSE"})
        check("safe destination ownership and permissions", positive.destination.stat().st_uid == os.getuid() and
              positive.destination.stat().st_mode & 0o777 == 0o700 and
              all(p.stat().st_mode & 0o777 == 0o600 for p in positive.destination.iterdir()))
        check("unrelated user skill before/after: identical", positive.unrelated.read_bytes() == original)
        evidence_before = (positive.state / "ecc-skill-probe/status.json").read_bytes()
        native_calls = (positive.home / ".codex/calls").read_bytes()
        positive.skill_contract()
        check("distinct task process: evidence read-only and no CLI modifications",
              evidence_before == (positive.state / "ecc-skill-probe/status.json").read_bytes() and
              native_calls == (positive.home / ".codex/calls").read_bytes())
        check("filesystem delivery cannot establish provider discovery or real invocation",
              data["native_discovery"] == data["skill_invocation"] == data["mcp"] == data["hook_trust"] == data["hook_execution"] == "UNVERIFIED" and
              data["ecc_readiness"] == "ECC NOT READY")
        positive.setup()
        positive.skill_contract()
        check("repeat setup: owned placement reused and unrelated skill preserved",
              positive.skill_evidence()["preexisting"] is True and positive.unrelated.read_bytes() == original and
              (positive.destination / "SKILL.md").read_bytes() == delivered)
        primary = SkillFixture(parent, "native-readonly-no-parents", "readonly", missing_parents=True)
        primary.setup()
        native, native_log = primary.evidence()
        skill = primary.skill_evidence()
        check("primary regression: native read-only failure has no marketplace_path and stays NOT READY",
              native["error_category"] == "permission/configuration" and "Read-only file system" in native_log and
              "marketplace_path" not in native and native["native_registration"] == "UNVERIFIED" and
              native["ecc_readiness"] == "ECC NOT READY")
        check("primary regression: independent pinned source places both files despite missing parents",
              skill["placement"] == "PLACED" and skill["source_kind"] == "wrapper-vendored-one-skill" and
              skill["source_files"] == data_pin and
              all(hashlib.sha256((primary.destination / name).read_bytes()).hexdigest() == checksum for name, checksum in data_pin.items()))
        parents = [primary.home / ".agents", primary.scope, primary.destination]
        metadata = [(path.stat().st_uid, path.stat().st_gid, path.stat().st_mode & 0o777, path.stat().st_ino) for path in parents]
        check("missing parents: owned mode 0700; existing HOME file preserved",
              all(uid == os.getuid() and gid == os.getgid() and mode == 0o700 for uid, gid, mode, inode in metadata) and
              primary.extra.read_bytes() == b"unrecognized home file\n")
        primary.unrelated.parent.mkdir()
        primary.unrelated.write_bytes(original)
        (primary.scope / "unknown.txt").write_bytes(b"unknown scope file\n")
        primary.skill_contract()
        primary.setup()
        primary.skill_contract()
        check("primary repeat: source hashes, parent identities/modes, binding and unrelated contents preserved",
              primary.skill_evidence()["preexisting"] is True and primary.skill_evidence()["source_files"] == data_pin and
              metadata == [(path.stat().st_uid, path.stat().st_gid, path.stat().st_mode & 0o777, path.stat().st_ino) for path in parents] and
              primary.unrelated.read_bytes() == original and (primary.scope / "unknown.txt").read_bytes() == b"unknown scope file\n" and
              primary.extra.read_bytes() == b"unrecognized home file\n")
        check("native success: uses the identical bundled bytes without duplicate skill delivery",
              positive.evidence()[0]["native_registration"] == "VERIFIED" and
              positive.skill_evidence()["source_files"] == primary.skill_evidence()["source_files"] and
              set(primary.destination.iterdir()) == {primary.destination / "SKILL.md", primary.destination / "LICENSE"})

        for name, filename, replacement, marker in (
            ("absent-source", None, None, "ECC_SKILL_PINNED_SOURCE_UNAVAILABLE"),
            ("absent-skill", "SKILL.md", None, "ECC_SKILL_SOURCE_SKILL_ABSENT"),
            ("absent-license", "LICENSE", None, "ECC_SKILL_SOURCE_LICENSE_ABSENT"),
            ("wrong-skill", "SKILL.md", b"changed\n", "ECC_SKILL_SOURCE_SKILL_BYTES_MISMATCH"),
            ("wrong-license", "LICENSE", b"changed\n", "ECC_SKILL_SOURCE_LICENSE_BYTES_MISMATCH"),
            ("wrong-metadata", "source.json", b"{}", "ECC_SKILL_SOURCE_METADATA_INVALID"),
        ):
            fixture = SkillFixture(parent, name, "readonly")
            if filename is None:
                shutil.rmtree(fixture.source)
            elif replacement is None:
                (fixture.source / filename).unlink()
            else:
                (fixture.source / filename).write_bytes(replacement)
            fixture.setup()
            data = fixture.skill_evidence()
            check(f"{name}: ECC_SKILL_SETUP_BLOCKED without touching user skills",
                  data["placement"] == "BLOCKED" and marker in data["error"] and not fixture.destination.exists() and
                  fixture.unrelated.read_bytes() == original)

        for scenario in ("skill-source-absent", "skill-source-changed", "wrong-ref"):
            fixture = SkillFixture(parent, "independent-" + scenario, scenario)
            fixture.setup()
            fixture.skill_contract()
            check(f"native {scenario}: bundled source remains independent",
                  fixture.skill_evidence()["source_files"] == data_pin and
                  (fixture.destination / "SKILL.md").read_bytes() == delivered)

        for name, marker in (
            ("home-unavailable", "ECC_SKILL_HOME_UNAVAILABLE"),
            ("home-absent", "ECC_SKILL_HOME_ABSENT"),
            ("home-readonly", "ECC_SKILL_DIRECTORY_READ_ONLY"),
            ("home-unowned", "ECC_SKILL_DIRECTORY_OWNERSHIP_OR_MODE"),
            ("agents-readonly", "ECC_SKILL_DIRECTORY_READ_ONLY"),
            ("agents-symlink", "ECC_SKILL_SCOPE_PATH_UNSAFE"),
            ("scope-readonly", "ECC_SKILL_DIRECTORY_READ_ONLY"),
            ("scope-symlink-escape", "ECC_SKILL_SCOPE_PATH_UNSAFE"),
            ("home-symlink", "ECC_SKILL_HOME_PATH_UNSAFE"),
            ("home-unsafe-parent", "ECC_SKILL_ANCESTOR_UNSAFE"),
            ("colliding-skill", "ECC_SKILL_DESTINATION_COLLISION"),
            ("identical-unowned-skill", "ECC_SKILL_DESTINATION_COLLISION"),
        ):
            fixture = SkillFixture(parent, name)
            sentinel = fixture.unrelated
            if name == "home-unavailable":
                fixture.env.pop("HOME")
            elif name == "home-absent":
                fixture.env["HOME"] = str(fixture.work / "missing-home")
            elif name == "home-readonly":
                fixture.home.chmod(0o500)
            elif name == "home-unowned":
                fixture.env["HOME"] = "/tmp"
            elif name == "agents-readonly":
                (fixture.home / ".agents").chmod(0o500)
            elif name == "agents-symlink":
                (fixture.home / ".agents").rename(fixture.work / "saved-agents")
                (fixture.home / ".agents").symlink_to(fixture.work / "saved-agents")
                sentinel = fixture.work / "saved-agents/skills/unrelated/keep.txt"
            elif name == "scope-readonly":
                fixture.scope.chmod(0o500)
            elif name == "scope-symlink-escape":
                fixture.scope.rename(fixture.work / "outside")
                fixture.scope.symlink_to(fixture.work / "outside")
                sentinel = fixture.work / "outside/unrelated/keep.txt"
            elif name == "home-symlink":
                link = fixture.work / "home-link"
                link.symlink_to(fixture.home)
                fixture.env["HOME"] = str(link)
            elif name == "home-unsafe-parent":
                alternate = fixture.work / "unsafe-parent/alternate-home/.agents/skills"
                alternate.mkdir(parents=True)
                alternate.parents[2].chmod(0o777)
                fixture.env["HOME"] = str(alternate.parents[1])
            else:
                fixture.destination.mkdir()
                (fixture.destination / "SKILL.md").write_bytes(delivered if name == "identical-unowned-skill" else b"existing user skill\n")
            fixture.setup()
            data = fixture.skill_evidence()
            check(f"{name}: ECC_SKILL_SETUP_BLOCKED ({marker}); unrelated bytes preserved",
                  data["placement"] == "BLOCKED" and marker in data["error"] and sentinel.read_bytes() == original)
            if name in ("colliding-skill", "identical-unowned-skill"):
                check(f"{name}: collision bytes preserved", (fixture.destination / "SKILL.md").read_bytes() ==
                      (delivered if name == "identical-unowned-skill" else b"existing user skill\n"))
            if name == "scope-readonly":
                fixture.scope.chmod(0o700)
            if name == "home-readonly":
                fixture.home.chmod(0o700)
            if name == "agents-readonly":
                (fixture.home / ".agents").chmod(0o700)

        fixture = SkillFixture(parent, "writable-bits-readonly-filesystem", "readonly", missing_parents=True)
        runtime = fixture.root / "scripts/ecc-codex.py"
        runtime.write_text(runtime.read_text().replace('probe = os.open(temporary,', 'raise OSError(30, "Read-only file system")\n                probe = os.open(temporary,'))
        fixture.setup()
        check("HOME writability: actual exclusive create failure blocks despite writable mode bits",
              fixture.home.stat().st_mode & 0o200 != 0 and
              fixture.skill_evidence()["error"] == "ECC_SKILL_HOME_WRITE_FAILED" and
              not (fixture.home / ".agents").exists())

        fixture = SkillFixture(parent, "scope-replaced-during-placement", "readonly")
        runtime = fixture.root / "scripts/ecc-codex.py"
        runtime.write_text(runtime.read_text().replace('check_skill_scope(home, scope, target)\n        recorder.data.update',
            'os.rename(home / ".agents/skills", home / ".agents/saved-skills")\n        os.mkdir(home / ".agents/skills", mode=0o700)\n        check_skill_scope(home, scope, target)\n        recorder.data.update'))
        fixture.setup()
        check("scope replacement during placement: named failure and preserved original contents",
              fixture.skill_evidence()["error"] == "ECC_SKILL_SCOPE_CHANGED" and
              (fixture.home / ".agents/saved-skills/unrelated/keep.txt").read_bytes() == original and
              not fixture.destination.exists())

        fixture = SkillFixture(parent, "native-plugin-missing", "install-failed")
        fixture.setup()
        fixture.skill_contract()
        check("native plugin missing: placement does not promote ECC READY",
              fixture.skill_evidence()["placement"] == "PLACED" and fixture.evidence()[0]["native_registration"] == "UNVERIFIED")

        fixture = SkillFixture(parent, "setup-home-changed", "readonly")
        fixture.setup()
        alternate_home = fixture.work / "alternate-home"
        alternate_home.mkdir()
        alternate = alternate_home / ".agents/skills"
        fixture.env["HOME"] = str(alternate_home)
        fixture.setup()
        data = fixture.skill_evidence()
        check("repeat setup HOME difference: BLOCKED without redirection",
              data["placement"] == "BLOCKED" and "ECC_SKILL_HOME_CHANGED" in data["error"] and
              not (alternate_home / ".agents").exists() and
              (fixture.destination / "SKILL.md").read_bytes() == delivered and fixture.unrelated.read_bytes() == original)
        binding_path = fixture.state / "ecc-skill-probe/scope.json"
        initial_binding = binding_path.read_bytes()
        fixture.setup()
        check("second changed-HOME retry: original scope binding survives blocked record",
              fixture.skill_evidence()["placement"] == "BLOCKED" and not (alternate_home / ".agents").exists() and
              binding_path.read_bytes() == initial_binding)
        status_path = binding_path.parent / "status.json"
        data = fixture.skill_evidence()
        data["complete"] = False
        status_path.write_text(json.dumps(data))
        fixture.setup()
        check("changed-HOME retry after partial attempt: original binding preserved",
              fixture.skill_evidence()["placement"] == "BLOCKED" and not (alternate_home / ".agents").exists() and
              binding_path.read_bytes() == initial_binding)

        fixture = SkillFixture(parent, "missing-binding-home-change")
        fixture.setup()
        directory = fixture.state / "ecc-skill-probe"
        (directory / "scope.json").unlink()
        alternate_home = fixture.work / "alternate-home"
        alternate_home.mkdir()
        alternate = alternate_home / ".agents/skills"
        fixture.env["HOME"] = str(alternate_home)
        for attempt in ("first", "repeat", "partial-record"):
            if attempt == "partial-record":
                data = fixture.skill_evidence()
                data["complete"] = False
                (directory / "status.json").write_text(json.dumps(data))
            fixture.setup()
            data = fixture.skill_evidence()
            check(f"missing binding and changed HOME {attempt}: BLOCKED without replacement binding",
                  data["placement"] == "BLOCKED" and "ECC_SKILL_SCOPE_BINDING_MISSING" in data["error"] and
                  not (directory / "scope.json").exists() and not (alternate_home / ".agents").exists() and
                  (fixture.destination / "SKILL.md").read_bytes() == delivered and fixture.unrelated.read_bytes() == original)

        fixture = SkillFixture(parent, "skill-interrupted", "readonly", missing_parents=True)
        runtime = fixture.root / "scripts/ecc-codex.py"
        runtime_original = runtime.read_text()
        runtime.write_text(runtime_original.replace('os.link(temporary, name,', 'os.kill(os.getpid(), signal.SIGTERM)\n                    os.link(temporary, name,'))
        fixture.setup()
        data = fixture.skill_evidence()
        code, output = fixture.run("scripts/session-check-codex.sh")
        check("interrupted skill setup: incomplete evidence retained with partial destination",
              data["complete"] is False and "ECC_SKILL_SETUP_INTERRUPTED" in data["error"] and
              code == 2 and "ECC_SKILL_EVIDENCE_INCOMPLETE" in output and fixture.destination.exists())
        before_partial = set(fixture.destination.iterdir())
        runtime.write_text(runtime_original)
        fixture.setup()
        check("interrupted placement: repeat preserves partial destination without repair",
              fixture.skill_evidence()["placement"] == "BLOCKED" and
              "ECC_SKILL_DESTINATION_COLLISION" in fixture.skill_evidence()["error"] and
              set(fixture.destination.iterdir()) == before_partial)

        for name, marker in (
            ("missing-evidence", "ECC_SKILL_PLACEMENT_MISSING"),
            ("partial-evidence", "ECC_SKILL_EVIDENCE_INCOMPLETE"),
            ("mismatched-log", "ECC_SKILL_EVIDENCE_INCOMPLETE"),
            ("changed-bytes", "ECC_SKILL_BYTES_CHANGED"),
            ("changed-permissions", "ECC_SKILL_FILE_OWNERSHIP_OR_MODE"),
            ("home-difference", "ECC_SKILL_HOME_CHANGED"),
            ("destination-symlink", "Not a directory"),
            ("binding-missing", "ECC_SKILL_PLACEMENT_MISSING"),
        ):
            fixture = SkillFixture(parent, name)
            fixture.setup()
            path = fixture.state / "ecc-skill-probe/status.json"
            if name == "missing-evidence":
                path.unlink()
            elif name == "partial-evidence":
                data = fixture.skill_evidence()
                data["complete"] = False
                path.write_text(json.dumps(data))
            elif name == "mismatched-log":
                (path.parent / "diagnostic.log").write_text("partial replacement\n")
            elif name == "changed-bytes":
                (fixture.destination / "SKILL.md").write_bytes(b"modified\n")
            elif name == "changed-permissions":
                (fixture.destination / "SKILL.md").chmod(0o700)
            elif name == "home-difference":
                fixture.env["HOME"] = str(fixture.work / "different-home")
            elif name == "binding-missing":
                (path.parent / "scope.json").unlink()
            else:
                fixture.destination.rename(fixture.work / "placed-saved")
                fixture.destination.symlink_to(fixture.work / "placed-saved")
            code, output = fixture.run("scripts/session-check-codex.sh")
            check(f"{name}: task measurement refuses ({marker})", code == 2 and marker in output and
                  "ECC_SKILL_FILES_PERSISTED" not in output and "ECC READY" not in output and
                  fixture.unrelated.read_bytes() == original)
            if name in ("partial-evidence", "mismatched-log", "changed-bytes", "changed-permissions", "destination-symlink", "binding-missing"):
                fixture.setup()
                check(f"{name}: repeat setup preserves conflicting/partial state",
                      fixture.skill_evidence()["placement"] == "BLOCKED" and fixture.unrelated.read_bytes() == original)

        for name, relative, before, after, expected in (
            ("independent-source-deleted", "scripts/ecc-codex.py",
             'content, license_bytes = bundled_skill_source(recorder)',
             'native = json.loads(read_regular(state / "ecc-setup/status.json", STATUS_LIMIT))\n        if not native.get("marketplace_path"):\n            raise ValueError("ECC_SKILL_PINNED_SOURCE_UNAVAILABLE")\n        content, license_bytes = bundled_skill_source(recorder)',
             "ECC_SKILL_PINNED_SOURCE_UNAVAILABLE"),
            ("parent-creation-deleted", "scripts/ecc-codex.py",
             'user_skill_scope(writable=True, create=True)', 'user_skill_scope(writable=True)',
             "ECC_SKILL_SCOPE_PARENT_MISSING"),
            ("placement-deleted", "env/setup-codex.sh", 'if bash "$root/scripts/ecc-codex.sh" skill-setup; then',
             'if true; then', "ECC_SKILL_PLACEMENT_MISSING"),
            ("measurement-deleted", "scripts/session-check-codex.sh", 'bash "$root/scripts/ecc-codex.sh" skill-status || skill_readiness=$?',
             'true', "ECC_SKILL_FILES_NOT_PERSISTED"),
            ("discovery-instruction-deleted", "scripts/ecc-codex.py",
             'print("ECC_SKILL_NATIVE_DISCOVERY_NOT_OBSERVED: inspect provider inventory/selectors before opening SKILL.md")',
             'pass', "ECC_SKILL_TASK_MEASUREMENT_NOT_CONSUMED"),
        ):
            fixture = SkillFixture(parent, name, "readonly", missing_parents=True)
            path = fixture.root / relative
            original_source = path.read_text()
            assert before in original_source
            path.write_text(original_source.replace(before, after))
            fixture.setup()
            try:
                fixture.skill_contract()
            except AssertionError as error:
                actual = fixture.skill_evidence().get("error", str(error)) if name in ("independent-source-deleted", "parent-creation-deleted") else str(error)
                check(f"deletion {name}: acceptance fails by name {expected}", actual == expected)
            else:
                raise AssertionError(f"deletion {name}: was not detected")
            path.write_text(original_source)
            if name == "independent-source-deleted":
                fixture.env["HARNESS_STATE_DIR"] = str(fixture.work / "restored-state")
                fixture.state = Path(fixture.env["HARNESS_STATE_DIR"])
            fixture.setup()
            fixture.skill_contract()
            check(f"deletion {name}: reinstatement passes", True)

        fixture = SkillFixture(parent, "fatal-skill-evidence")
        fixture.setup()
        evidence = fixture.state / "ecc-skill-probe/status.json"
        evidence.unlink()
        evidence.symlink_to(fixture.unrelated)
        code, _ = fixture.run("env/setup-codex.sh")
        check("unsafe skill evidence storage remains fatal", code == 1 and fixture.unrelated.read_bytes() == original)
        fixture = SkillFixture(parent, "unsafe-binding")
        fixture.setup()
        binding_path = fixture.state / "ecc-skill-probe/scope.json"
        binding_path.unlink()
        binding_path.symlink_to(fixture.unrelated)
        code, _ = fixture.run("env/setup-codex.sh")
        check("unsafe scope binding remains fatal and preserves unrelated bytes",
              code == 1 and fixture.unrelated.read_bytes() == original)
    print(f"PASS {PASSES} ECC skill boundary checks (local fixtures only; Cloud discovery/invocation NOT OBSERVED)")


if __name__ == "__main__":
    main()
