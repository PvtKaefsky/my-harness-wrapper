import hashlib
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("hosted_ci", ROOT / "scripts/check-hosted-ci.py")
CI = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI)


GIT_SELECTORS = {'GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_QUARANTINE_PATH', 'GIT_GRAFT_FILE', 'GIT_SHALLOW_FILE', 'GIT_NAMESPACE', 'GIT_PREFIX', 'GIT_INTERNAL_SUPER_PREFIX', 'GIT_CONFIG', 'GIT_CONFIG_PARAMETERS', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_SYSTEM', 'GIT_TEMPLATE_DIR'}


def fixture_env(base):
    env = {key: value for key, value in os.environ.items() if key not in GIT_SELECTORS and not key.startswith(('GIT_CONFIG_KEY_', 'GIT_CONFIG_VALUE_'))}
    template = Path(base) / 'template'
    template.mkdir(exist_ok=True)
    env.update(GIT_CONFIG_GLOBAL=str(Path(base) / 'global'), GIT_CONFIG_NOSYSTEM='1', GIT_TEMPLATE_DIR=str(template),
               GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid', GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid')
    return env


class HostedCI(unittest.TestCase):
    def workflow(self):
        return json.loads((ROOT / ".github/workflows/codex.yml").read_text())

    def test_required_coverage(self):
        CI.check_workflow(self.workflow())

    def test_deletion_red_green(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "codex.yml"
            workflow = self.workflow()
            original = workflow["jobs"]["regression"]["steps"].copy()
            workflow["jobs"]["regression"]["steps"] = [s for s in original if s["name"] != "Cloud pack suite"]
            path.write_text(json.dumps(workflow))
            red = subprocess.run(["python3", "-I", str(ROOT / "scripts/check-hosted-ci.py"), "workflow", str(path)], capture_output=True, text=True)
            self.assertEqual(red.returncode, 1)
            self.assertIn("HOSTED_SUITE_COVERAGE_MISSING: Cloud pack suite", red.stderr)
            print("DELETION RED exit=1 HOSTED_SUITE_COVERAGE_MISSING: Cloud pack suite", flush=True)
            workflow["jobs"]["regression"]["steps"] = original
            path.write_text(json.dumps(workflow))
            green = subprocess.run(["python3", "-I", str(ROOT / "scripts/check-hosted-ci.py"), "workflow", str(path)], capture_output=True, text=True)
            self.assertEqual(green.returncode, 0, green.stderr)
            print("DELETION GREEN exit=0", flush=True)

    def test_permission_timeout_and_bypass_bounds(self):
        for mutation in (lambda w: w.update(permissions={"contents": "write"}),
                         lambda w: w["jobs"]["regression"].update(permissions={"actions": "write"}),
                         lambda w: w["jobs"]["regression"].update({"timeout-minutes": 0}),
                         lambda w: w["jobs"]["regression"].update({"continue-on-error": True}),
                         lambda w: w["jobs"]["regression"]["steps"][2].update({"if": "always()"}),
                         lambda w: w["jobs"]["regression"]["steps"][2].update({"continue-on-error": True}),
                         lambda w: w["jobs"]["regression"]["steps"][0]["with"].update(ref="main")):
            with self.subTest(mutation=mutation):
                workflow = self.workflow()
                mutation(workflow)
                with self.assertRaises(ValueError):
                    CI.check_workflow(workflow)

    def test_native_suite_deletion_red_green(self):
        workflow = self.workflow()
        steps = workflow['jobs']['regression']['steps']
        workflow['jobs']['regression']['steps'] = [s for s in steps if s['name'] != 'Native skill suite']
        with self.assertRaisesRegex(ValueError, 'HOSTED_SUITE_COVERAGE_MISSING: Native skill suite'):
            CI.check_workflow(workflow)
        print('DELETION NATIVE CI RED HOSTED_SUITE_COVERAGE_MISSING: Native skill suite', flush=True)
        workflow['jobs']['regression']['steps'] = steps
        CI.check_workflow(workflow)
        print('DELETION NATIVE CI GREEN', flush=True)

    def test_required_commands_preserve_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, command in CI.COMMANDS.items():
                with self.subTest(step=name):
                    script = "env/setup-codex.sh" if name == "Environment setup" else command.removeprefix("bash ").removeprefix("python3 -I ")
                    path = root / script
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("import sys; sys.exit(37)\n" if script.endswith(".py") else "exit 37\n")
                    run = subprocess.run(["bash", "--noprofile", "--norc", "-e", "-o", "pipefail", "-c", command], cwd=root, env=fixture_env(root))
                    self.assertEqual(run.returncode, 37)

    def test_stale_checkout_identity(self):
        command = self.workflow()["jobs"]["regression"]["steps"][1]["run"]
        with tempfile.TemporaryDirectory() as directory:
            env = fixture_env(directory)
            subprocess.run(["git", "init", "-q", directory], env=env, check=True)
            subprocess.run(["git", "-c", "user.name=CI Fixture", "-c", "user.email=ci@example.invalid", "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgSign=false", "commit", "--allow-empty", "-qm", "fixture"], cwd=directory, env=env, check=True)
            sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=directory, env=env, text=True).strip()
            env["GITHUB_SHA"] = sha
            good = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", command], cwd=directory, env=env, capture_output=True)
            self.assertEqual(good.returncode, 0)
            env["GITHUB_SHA"] = "0" * 40
            run = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", command], cwd=directory, env=env, capture_output=True)
            self.assertNotEqual(run.returncode, 0)

    def test_inherited_git_context_preserves_caller(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            caller = root / 'caller'
            env = fixture_env(root)
            subprocess.run(['git', 'init', '-q', str(caller)], env=env, check=True)
            subprocess.run(['git', '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'fixture'], cwd=caller, env=env, check=True)
            (caller / 'staged').write_text('preserve index\n')
            subprocess.run(['git', 'add', 'staged'], cwd=caller, env=env, check=True)
            (caller / 'working').write_text('preserve working bytes\n')

            def snapshot():
                return {str(p.relative_to(caller)): hashlib.sha256(p.read_bytes()).hexdigest()
                        for p in caller.rglob('*') if p.is_file()}

            before = snapshot()
            env.update(GIT_DIR=str(caller / '.git'), GIT_WORK_TREE=str(caller), GIT_COMMON_DIR=str(caller / '.git'),
                       GIT_INDEX_FILE=str(caller / '.git/index'), GIT_OBJECT_DIRECTORY=str(caller / '.git/objects'),
                       GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.worktree', GIT_CONFIG_VALUE_0=str(caller))
            run = subprocess.run(['python3', '-I', str(Path(__file__).resolve()), 'HostedCI.test_stale_checkout_identity'],
                                 env=env, capture_output=True, text=True)
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual(snapshot(), before)

    def evidence(self):
        sha = "a" * 40
        run = {"id": 123, "head_sha": sha, "event": "push", "status": "completed", "conclusion": "success"}
        steps = [{"name": name, "status": "completed", "conclusion": "success", "number": n,
                  "started_at": "2026-10-21T10:00:00Z", "completed_at": "2026-10-21T10:01:00Z"}
                 for n, name in enumerate(CI.STEP_NAMES, 1)]
        jobs = {"jobs": [{"id": 456, "run_id": 123, "head_sha": sha, "name": "Wrapper regression", "status": "completed", "conclusion": "success", "steps": steps}]}
        return run, jobs, sha

    def test_completed_hosted_evidence(self):
        CI.check_run(*self.evidence())

    def test_empty_steps_neutral_failure_stale_and_fabricated_claims(self):
        for mutate in (lambda r, j: j["jobs"][0].update(steps=[]),
                       lambda r, j: r.update(head_sha="b" * 40),
                       lambda r, j: j["jobs"][0].update(conclusion="neutral"),
                       lambda r, j: j["jobs"][0]["steps"][-1].update(conclusion="skipped"),
                       lambda r, j: j["jobs"][0]["steps"][-1].update(conclusion="failure"),
                       lambda r, j: j["jobs"][0]["steps"][-1].update(started_at=None)):
            run, jobs, sha = self.evidence()
            mutate(run, jobs)
            with self.assertRaises(ValueError):
                CI.check_run(run, jobs, sha)
        for fabricated in ({"AUTOMATIC_HOOKS": "OBSERVED_PASS"}, {"NATIVE_SKILLS": "OBSERVED_PASS"}):
            with self.assertRaises(ValueError):
                CI.check_run(fabricated, {"jobs": []}, "a" * 40)


if __name__ == "__main__":
    unittest.main(verbosity=2)
