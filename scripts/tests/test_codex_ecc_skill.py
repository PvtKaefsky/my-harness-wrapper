#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import shutil
import shlex
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
    def __init__(self, parent, name, scenario="success"):
        super().__init__(parent, name)
        self.env["ECC_TEST_CASE"] = scenario
        self.scope = self.home / ".agents/skills"
        self.unrelated = self.scope / "unrelated/keep.txt"
        self.unrelated.parent.mkdir(parents=True)
        self.unrelated.write_bytes(b"unrelated user skill\n")
        self.destination = self.scope / "python-patterns"

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
        delivered = (positive.destination / "SKILL.md").read_bytes()
        check("real setup entry point: pinned unchanged bytes placed in documented user scope",
              data["placement"] == "PLACED" and data["complete"] is True and data["safely_delivered"] is True and
              data["preexisting"] is False and data["source_files"]["SKILL.md"] == EXPECTED and
              hashlib.sha256(delivered).hexdigest() == EXPECTED and
              delivered == (Path(positive.env["ECC_TEST_FIXTURES"]) / "python-patterns.md").read_bytes())
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
        for name, scenario, marker in (
            ("absent-source", "skill-source-absent", "ECC_SKILL_SOURCE_ABSENT"),
            ("revision-mismatch", "wrong-ref", "ECC_SKILL_PINNED_SOURCE_UNAVAILABLE"),
            ("source-byte-mismatch", "skill-source-changed", "ECC_SKILL_SOURCE_BYTES_MISMATCH"),
        ):
            fixture = SkillFixture(parent, name, scenario)
            fixture.setup()
            data = fixture.skill_evidence()
            check(f"{name}: ECC_SKILL_SETUP_BLOCKED without touching user skills",
                  data["placement"] == "BLOCKED" and marker in data["error"] and not fixture.destination.exists() and
                  fixture.unrelated.read_bytes() == original)

        for name, marker in (
            ("home-unavailable", "ECC_SKILL_HOME_UNAVAILABLE"),
            ("home-absent", "No such file"),
            ("scope-absent", "No such file"),
            ("scope-readonly", "ECC_SKILL_DIRECTORY_READ_ONLY"),
            ("scope-symlink-escape", "Not a directory"),
            ("home-symlink", "Not a directory"),
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
            elif name == "scope-absent":
                fixture.unrelated.parent.rename(fixture.work / "unrelated-saved")
                fixture.scope.rmdir()
                sentinel = fixture.work / "unrelated-saved/keep.txt"
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

        fixture = SkillFixture(parent, "native-plugin-missing", "install-failed")
        fixture.setup()
        fixture.skill_contract()
        check("native plugin missing: placement does not promote ECC READY",
              fixture.skill_evidence()["placement"] == "PLACED" and fixture.evidence()[0]["native_registration"] == "UNVERIFIED")

        fixture = SkillFixture(parent, "setup-home-changed")
        fixture.setup()
        alternate = fixture.work / "alternate-home/.agents/skills"
        alternate.mkdir(parents=True)
        fixture.env["HOME"] = str(alternate.parents[1])
        fixture.setup()
        data = fixture.skill_evidence()
        check("repeat setup HOME difference: BLOCKED without redirection",
              data["placement"] == "BLOCKED" and "ECC_SKILL_HOME_CHANGED" in data["error"] and
              not (alternate / "python-patterns").exists() and
              (fixture.destination / "SKILL.md").read_bytes() == delivered and fixture.unrelated.read_bytes() == original)
        binding_path = fixture.state / "ecc-skill-probe/scope.json"
        initial_binding = binding_path.read_bytes()
        fixture.setup()
        check("second changed-HOME retry: original scope binding survives blocked record",
              fixture.skill_evidence()["placement"] == "BLOCKED" and not (alternate / "python-patterns").exists() and
              binding_path.read_bytes() == initial_binding)
        status_path = binding_path.parent / "status.json"
        data = fixture.skill_evidence()
        data["complete"] = False
        status_path.write_text(json.dumps(data))
        fixture.setup()
        check("changed-HOME retry after partial attempt: original binding preserved",
              fixture.skill_evidence()["placement"] == "BLOCKED" and not (alternate / "python-patterns").exists() and
              binding_path.read_bytes() == initial_binding)

        fixture = SkillFixture(parent, "missing-binding-home-change")
        fixture.setup()
        directory = fixture.state / "ecc-skill-probe"
        (directory / "scope.json").unlink()
        alternate = fixture.work / "alternate-home/.agents/skills"
        alternate.mkdir(parents=True)
        fixture.env["HOME"] = str(alternate.parents[1])
        for attempt in ("first", "repeat", "partial-record"):
            if attempt == "partial-record":
                data = fixture.skill_evidence()
                data["complete"] = False
                (directory / "status.json").write_text(json.dumps(data))
            fixture.setup()
            data = fixture.skill_evidence()
            check(f"missing binding and changed HOME {attempt}: BLOCKED without replacement binding",
                  data["placement"] == "BLOCKED" and "ECC_SKILL_SCOPE_BINDING_MISSING" in data["error"] and
                  not (directory / "scope.json").exists() and not (alternate / "python-patterns").exists() and
                  (fixture.destination / "SKILL.md").read_bytes() == delivered and fixture.unrelated.read_bytes() == original)

        fixture = SkillFixture(parent, "skill-interrupted")
        git = fixture.bin / "git"
        git.write_text('#!/usr/bin/env bash\nif [ -f "$HARNESS_STATE_DIR/ecc-skill-probe/status.json" ] && '
                       '[ ! -f "$CODEX_HOME/interrupted-once" ]; then\n'
                       '  : > "$CODEX_HOME/interrupted-once"\n  kill -TERM "$PPID"\n  exit 143\nfi\nexec ' +
                       shlex.quote(shutil.which("git")) + ' "$@"\n')
        git.chmod(0o700)
        fixture.setup()
        data = fixture.skill_evidence()
        code, output = fixture.run("scripts/session-check-codex.sh")
        check("interrupted skill setup: incomplete evidence retained without placement",
              data["complete"] is False and "ECC_SKILL_SETUP_INTERRUPTED" in data["error"] and
              code == 2 and "ECC_SKILL_EVIDENCE_INCOMPLETE" in output and not fixture.destination.exists())

        for name, marker in (
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
            if name == "partial-evidence":
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
            ("placement-deleted", "env/setup-codex.sh", 'if bash "$root/scripts/ecc-codex.sh" skill-setup; then',
             'if true; then', "ECC_SKILL_PLACEMENT_MISSING"),
            ("measurement-deleted", "scripts/session-check-codex.sh", 'bash "$root/scripts/ecc-codex.sh" skill-status || skill_readiness=$?',
             'true', "ECC_SKILL_FILES_NOT_PERSISTED"),
            ("discovery-instruction-deleted", "scripts/ecc-codex.py",
             'print("ECC_SKILL_NATIVE_DISCOVERY_NOT_OBSERVED: inspect provider inventory/selectors before opening SKILL.md")',
             'pass', "ECC_SKILL_TASK_MEASUREMENT_NOT_CONSUMED"),
        ):
            fixture = SkillFixture(parent, name)
            path = fixture.root / relative
            original_source = path.read_text()
            assert before in original_source
            path.write_text(original_source.replace(before, after))
            fixture.setup()
            try:
                fixture.skill_contract()
            except AssertionError as error:
                check(f"deletion {name}: acceptance fails by name {expected}", str(error) == expected)
            else:
                raise AssertionError(f"deletion {name}: was not detected")
            path.write_text(original_source)
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
