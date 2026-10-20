#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[2]
PASSES = 0


def check(name, condition):
    global PASSES
    if not condition:
        raise AssertionError(name)
    PASSES += 1
    print(f"PASS {name}", flush=True)


class Fixture:
    def __init__(self, parent, name):
        self.work = parent / name
        self.work.mkdir()
        self.root = self.work / "source"
        for directory in ("config", "scripts", "env"):
            shutil.copytree(ROOT / directory, self.root / directory)
        for suite in ("test-attribution-guard.sh", "test-codex.sh", "test-codex-git-context.sh", "test-codex-identity.sh", "test-codex-ecc.sh"):
            (self.root / "scripts" / suite).write_text("#!/usr/bin/env bash\nexit 0\n")
        self.home = self.work / "home"
        self.home.mkdir()
        self.state = self.work / "state"
        self.bin = self.work / "bin"
        self.bin.mkdir()
        shutil.copy2(ROOT / "scripts/tests/fake_codex_ecc.py", self.bin / "codex")
        (self.bin / "codex").chmod(0o700)
        self.env = dict(os.environ, HOME=str(self.home), HARNESS_STATE_DIR=str(self.state),
                        PATH=f"{self.bin}:{os.environ['PATH']}", ECC_TEST_CASE=name,
                        GIT_CONFIG_GLOBAL=str(self.home / "gitconfig"), GIT_CONFIG_NOSYSTEM="1")
        self.env.pop("CODEX_HOME", None)
        for key in tuple(self.env):
            if key.startswith("GIT_") and key not in ("GIT_CONFIG_GLOBAL", "GIT_CONFIG_NOSYSTEM"):
                self.env.pop(key)
        subprocess.run(["git", "init", "-q", str(self.root)], env=self.env, check=True)
        subprocess.run(["git", "-C", str(self.root), "add", "."], env=self.env, check=True)
        subprocess.run(["git", "-C", str(self.root), "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                        "-c", "commit.gpgsign=false", "commit", "-qm", "test: initialize setup fixture"], env=self.env, check=True)

    def run(self, path):
        result = subprocess.run(["bash", str(self.root / path)], env=self.env, capture_output=True, text=True, timeout=15)
        return result.returncode, result.stdout + result.stderr

    def setup(self):
        code, output = self.run("env/setup-codex.sh")
        assert code == 0, output
        return output

    def evidence(self):
        directory = self.state / "ecc-setup"
        data = json.loads((directory / "status.json").read_text())
        log = (directory / "diagnostic.log").read_text()
        assert data["log_sha256"] == hashlib.sha256(log.encode()).hexdigest()
        return data, log

    def contract(self):
        code, output = self.run("scripts/session-check-codex.sh")
        assert "ECC_SETUP_EVIDENCE_MISSING" not in output, "ECC_SETUP_EVIDENCE_MISSING"
        assert code == 2 and "ECC NOT READY" in output, "ECC_TASK_READINESS_NOT_CONSUMED"
        return output


def main():
    with tempfile.TemporaryDirectory(prefix="codex-ecc-") as temporary:
        parent = Path(temporary)
        categories = {"no-marketplace": "CLI incompatibility", "no-pin-option": "CLI incompatibility",
                      "wrong-source": "permission/configuration", "wrong-ref": "permission/configuration",
                      "ref-rejected": "CLI incompatibility", "network": "network/proxy", "readonly": "permission/configuration",
                      "install-failed": "unknown", "malformed": "CLI incompatibility", "empty": "CLI incompatibility",
                      "broken-cache": "packaging/cache", "unreadable-cache": "permission/configuration",
                      "malformed-manifest": "packaging/cache", "interrupted": "unknown", "oversized": "unknown"}
        categories.update({"null-marketplace-source": "CLI incompatibility", "null-interface": "packaging/cache",
                           "null-marketplace-plugins": "packaging/cache", "fifo-manifest": "packaging/cache",
                           "fifo-skill": "packaging/cache", "many-cache-entries": "packaging/cache",
                           "looping-cache-reference": "packaging/cache"})
        for name, category in categories.items():
            fixture = Fixture(parent, name)
            started = time.monotonic()
            fixture.setup()
            data, log = fixture.evidence()
            check(f"{name}: setup failure retains classified private evidence", data.get("error_category") == category and
                  data["ecc_readiness"] == "ECC NOT READY" and "ECC NOT READY" in log)
            output = fixture.contract()
            check(f"{name}: separate task process consumes persisted evidence", str(fixture.state / "ecc-setup") in output or
                  "ECC_SETUP_EVIDENCE_INCOMPLETE" in output)
            calls = (fixture.home / ".codex/calls").read_text()
            fixture.run("scripts/session-check-codex.sh")
            check(f"{name}: task verification never modifies native plugins", calls == (fixture.home / ".codex/calls").read_text())
            if name in ("wrong-source", "wrong-ref"):
                check(f"{name}: conflicting registration preserved", "marketplace add affaan-m/ECC --ref" not in calls)
            if name in ("fifo-manifest", "fifo-skill", "many-cache-entries"):
                check(f"{name}: cache validation remains bounded", time.monotonic() - started < 15)

        fixture = Fixture(parent, "missing-cli")
        (fixture.bin / "codex").unlink()
        fixture.env["PATH"] = f"{fixture.bin}:/usr/bin:/bin"
        fixture.setup()
        data, _ = fixture.evidence()
        check("missing CLI: early failure persists before next process", data["events"][1]["phase"] == "cli-version" and
              data["error_category"] == "CLI incompatibility")
        fixture.contract()

        for name in ("success", "installed"):
            fixture = Fixture(parent, name)
            fixture.setup()
            data, _ = fixture.evidence()
            output = fixture.contract()
            check(f"{name}: registration/cache success cannot claim skill acceptance", data["native_registration"] == "VERIFIED" and
                  data["cache"] == "VERIFIED" and data["idempotence"] == "VERIFIED" and data["skill_invocation"] == "UNVERIFIED" and
                  data["task_plugin_list"] == "UNVERIFIED" and
                  "ECC NOT READY" in output and "ECC READY" not in output)
            check(f"{name}: setup attempted distinguished from previously present", data["already_present_at_setup"] == (name == "installed") and
                  data["install_attempted_in_setup"] is True)
            for file in ("status.json", "diagnostic.log"):
                check(f"{name}: {file} is private regular evidence", (fixture.state / "ecc-setup" / file).stat().st_mode & 0o777 == 0o600)
            fixture.setup()
            native = json.loads((fixture.home / ".codex/fake.json").read_text())
            check(f"{name}: repeat setup does not duplicate installation", native["installs"] == (0 if name == "installed" else 1) and native["adds"] == 4)
            data, log = fixture.evidence()
            check(f"{name}: unrelated marketplace retained", "unrelated" in log)
            if name == "success":
                success = fixture

        fixture = Fixture(parent, "redaction")
        fixture.setup()
        data, log = fixture.evidence()
        saved = json.dumps(data) + log
        check("safe redaction retains useful stderr", all(secret not in saved for secret in
              ("credential-value", "user:pass", "url-secret", "ghp_abc123456789")) and "proxy connection failed" in saved)
        fixture.contract()

        evidence = success.state / "ecc-setup"
        status_path = evidence / "status.json"
        log_path = evidence / "diagnostic.log"
        original = status_path.read_text()
        log = log_path.read_text()
        for name, change, marker in (
            ("stale", lambda d: d.update(source_sha256="0" * 64), "ECC_SETUP_EVIDENCE_STALE"),
            ("partial", lambda d: d.update(complete=False), "ECC_SETUP_EVIDENCE_INCOMPLETE"),
            ("wrong-log-digest", lambda d: d.update(log_sha256="0" * 64), "ECC_SETUP_EVIDENCE_INCOMPLETE"),
        ):
            data = json.loads(original)
            change(data)
            status_path.write_text(json.dumps(data))
            code, output = success.run("scripts/session-check-codex.sh")
            check(f"{name}: task refuses evidence", code == 2 and marker in output)
        status_path.write_text(original)
        for file in (status_path, log_path):
            content = file.read_text()
            file.unlink()
            code, output = success.run("scripts/session-check-codex.sh")
            check(f"missing {file.name}: attempt remains unknown", code == 2 and "ECC_SETUP_EVIDENCE_MISSING" in output and "attempt unknown" in output)
            outside = success.work / "preserved"
            outside.write_text("preserve\n")
            file.symlink_to(outside)
            code, output = success.run("scripts/session-check-codex.sh")
            check(f"symlinked {file.name}: task refuses evidence", code == 2 and "INACCESSIBLE_OR_INVALID" in output)
            code, output = success.run("env/setup-codex.sh")
            check(f"symlinked {file.name}: setup refuses overwrite", code != 0 and outside.read_text() == "preserve\n")
            file.unlink()
            file.write_text(content)
            file.chmod(0o600)
        log_path.write_text(log)
        log_path.chmod(0)
        code, output = success.run("scripts/session-check-codex.sh")
        check("inaccessible log: task blocks readiness", code == 2 and "INACCESSIBLE_OR_INVALID" in output)
        log_path.chmod(0o600)

        for name, path, before, after, expected in (
            ("setup-probe-deleted", "env/setup-codex.sh", 'if bash "$root/scripts/ecc-codex.sh" setup; then', "if true; then", "ECC_SETUP_EVIDENCE_MISSING"),
            ("task-consumption-deleted", "scripts/session-check-codex.sh", 'bash "$root/scripts/ecc-codex.sh" status || readiness=$?', "true", "ECC_TASK_READINESS_NOT_CONSUMED"),
        ):
            fixture = Fixture(parent, name)
            path = fixture.root / path
            original = path.read_text()
            assert before in original
            path.write_text(original.replace(before, after))
            fixture.setup()
            try:
                fixture.contract()
            except AssertionError as error:
                check(f"deletion {name}: fails by name {expected}", str(error) == expected)
            else:
                raise AssertionError(f"deletion {name}: regression was not detected")
            path.write_text(original)
            fixture.setup()
            fixture.contract()
            check(f"deletion {name}: restored implementation passes", True)

        for name in ("actual-source-change", "actual-commit-change"):
            fixture = Fixture(parent, name)
            fixture.setup()
            if name == "actual-source-change":
                with (fixture.root / "config/codex/AGENTS.md").open("a") as policy:
                    policy.write("\nchanged source\n")
            else:
                subprocess.run(["git", "-C", str(fixture.root), "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                                "-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "test: changed commit"],
                               env=fixture.env, check=True)
            code, output = fixture.run("scripts/session-check-codex.sh")
            check(f"{name}: delivery failure still consumes stale ECC evidence", code == 1 and "FAIL source revision" in output and
                  "ECC_SETUP_EVIDENCE_STALE" in output and "ECC NOT READY" in output)

        fixture = Fixture(parent, "fatal-build")
        (fixture.root / "scripts/test-codex.sh").write_text("#!/usr/bin/env bash\nexit 31\n")
        code, output = fixture.run("env/setup-codex.sh")
        check("required wrapper regression failure remains fatal", code == 31 and not fixture.state.exists())
    print(f"PASS {PASSES} ECC setup/startup checks (STUB CLI; Cloud acceptance NOT OBSERVED)")


if __name__ == "__main__":
    main()
