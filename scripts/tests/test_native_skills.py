#!/usr/bin/env -S python3 -I
import hashlib
import json
import os
import pwd
import runpy
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
NATIVE = 'config/codex/native-skills/harness-python-patterns'
NAME = 'harness-python-patterns'
GIT_SELECTORS = runpy.run_path(str(ROOT / 'scripts/provision-native-skills.py'))['GIT_SELECTORS']


def pwd_account(home):
    account = pwd.getpwuid(os.getuid())
    return pwd.struct_passwd((*account[:5], str(home), account.pw_shell))


def snapshot(root):
    result = {}
    for p in [root, *sorted(root.rglob('*'))]:
        s = p.lstat()
        data = os.readlink(p) if stat.S_ISLNK(s.st_mode) else hashlib.sha256(p.read_bytes()).hexdigest() if p.is_file() else ''
        result[str(p.relative_to(root))] = (s.st_mode, s.st_uid, s.st_gid, s.st_ino, s.st_mtime_ns, data)
    return result


class NativeSkills(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='native-skills-')
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.root = self.base / 'wrapper'
        self.root.mkdir()
        for name in ['config', 'scripts', 'env', 'docs', '.github', '.agents']:
            shutil.copytree(ROOT / name, self.root / name, ignore=shutil.ignore_patterns('__pycache__'))
        for name in ['AGENTS.md', 'README.md']:
            shutil.copy(ROOT / name, self.root / name)
        self.home = self.base / 'home'
        self.home.mkdir(mode=0o700)
        self.link = self.home / '.agents/skills' / NAME
        self.source = self.root / NATIVE
        self.env = {k: v for k, v in os.environ.items() if k not in GIT_SELECTORS and not k.startswith(('GIT_CONFIG_KEY_', 'GIT_CONFIG_VALUE_'))}
        template = self.base / 'template'
        template.mkdir()
        self.env.update(HOME=str(self.home), HARNESS_ENABLE_NATIVE_SKILLS='1', HARNESS_STATE_DIR=str(self.base / 'state'),
                        GIT_CONFIG_GLOBAL=str(self.base / 'global'), GIT_CONFIG_NOSYSTEM='1', GIT_TEMPLATE_DIR=str(template),
                        GIT_AUTHOR_NAME='Fixture', GIT_AUTHOR_EMAIL='fixture@example.invalid',
                        GIT_COMMITTER_NAME='Fixture', GIT_COMMITTER_EMAIL='fixture@example.invalid', FIXTURE_PASSWD_HOME=str(self.home))
        self.env.pop('HARNESS_REVIEW_FILE', None)
        Path(self.env['GIT_CONFIG_GLOBAL']).write_text('[gc]\n\tauto = 0\n[maintenance]\n\tauto = false\n')
        self.cmd('git', 'init', '-q')
        self.cmd('git', 'remote', 'add', 'origin', 'https://github.com/PvtKaefsky/my-harness-wrapper.git')
        self.cmd('git', 'add', '.')
        self.cmd('git', '-c', 'commit.gpgsign=false', 'commit', '-qm', 'test: fixture')
        tools = self.base / 'tools'
        tools.mkdir()
        driver = tools / 'python3'
        identity_driver = tools / 'identity.py'
        identity_driver.write_text('''import os,pwd,runpy,sys
from unittest.mock import patch
args=sys.argv[1:]
account=pwd.getpwuid(os.getuid())
account=pwd.struct_passwd((*account[:5],os.environ['FIXTURE_PASSWD_HOME'],account.pw_shell))
sys.argv=args[1:]
with patch('pwd.getpwuid',return_value=account):
    runpy.run_path(args[1],run_name='__main__')
''')
        executable = shlex.quote(sys.executable)
        driver.write_text('#!/bin/sh\ncase "${2-}" in\n  */scripts/provision-native-skills.py) exec ' + executable + ' -I ' + shlex.quote(str(identity_driver)) + ' "$@" ;;\nesac\nexec ' + executable + ' "$@"\n')
        driver.chmod(0o700)
        self.python = str(driver)
        self.env['PATH'] = str(tools) + os.pathsep + os.environ['PATH']

    def cmd(self, *args, code=0, contains=None, env=None, timeout=120):
        result = subprocess.run(args, cwd=self.root, env=env or self.env, capture_output=True, text=True, timeout=timeout, umask=0o077)
        output = result.stdout + result.stderr
        self.assertEqual(result.returncode, code, output[-7000:])
        if contains:
            self.assertIn(contains, output)
        return output

    def native(self, action='install', **kwargs):
        return self.cmd(self.python, '-I', str(self.root / 'scripts/provision-native-skills.py'), action, **kwargs)

    def setup(self, **kwargs):
        return self.cmd('bash', 'env/setup-codex.sh', **kwargs)

    def stub_suites(self):
        for name in ['test-codex.sh', 'test-codex-git-context.sh', 'test-codex-identity.sh', 'test-codex-attribution.sh', 'test-cloud-pack.sh']:
            (self.root / 'scripts' / name).write_text('#!/usr/bin/env bash\nset -euo pipefail\ntrue\n')

    def test_full_setup_opt_in_and_target_preservation(self):
        target = self.base / 'target'
        target.mkdir()
        self.cmd('git', 'init', '-q', str(target))
        self.cmd('git', '-C', str(target), '-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'test: target fixture')
        (target / 'staged').write_text('index bytes\n')
        self.cmd('git', '-C', str(target), 'add', 'staged')
        (target / 'untracked').write_text('working bytes\n')
        self.cmd('git', '-C', str(target), 'status', '--porcelain=v1')
        before_target = snapshot(target)
        preservation = self.cmd('python3', '-I', str(self.root / 'scripts/check-native-preservation.py'), str(target))
        before_source = snapshot(self.root)
        head = self.cmd('git', 'rev-parse', 'HEAD')
        output = self.setup(timeout=240)
        self.assertIn('NATIVE_SKILL_LINK_VERIFIED', output)
        self.assertEqual(self.link.readlink(), self.source)
        self.assertEqual(self.link.resolve(), self.source.resolve())
        self.assertEqual(snapshot(target), before_target)
        self.assertEqual(self.cmd('python3', '-I', str(self.root / 'scripts/check-native-preservation.py'), str(target)), preservation)
        self.assertEqual(snapshot(self.root), before_source)
        self.assertEqual(self.cmd('git', 'rev-parse', 'HEAD'), head)
        self.assertEqual(self.cmd('git', 'status', '--porcelain=v1'), '')
        print('REAL_SETUP exit=0 strict source bytes/metadata/HEAD/index/status and target bytes/metadata unchanged; LINK_PROVISIONED fixture only', flush=True)

    def repository_source(self, **kwargs):
        return self.cmd('python3', '-I', str(self.root / 'scripts/check-native-source.py'), **kwargs)

    def test_repository_source_exact_real_path(self):
        output = self.repository_source(contains='NATIVE_REPOSITORY_SOURCE_VERIFIED')
        self.assertIn(str(self.root / '.agents/skills' / NAME), output)
        self.assertNotIn('PROVIDER_DISCOVERED', output)
        self.assertNotIn('PROVIDER_INVOKED', output)

    def test_repository_source_deletion_and_mutation_red_green(self):
        skill = self.root / '.agents/skills' / NAME / 'SKILL.md'
        original = skill.read_bytes()
        self.repository_source()
        skill.unlink()
        self.repository_source(code=1, contains='NATIVE_SKILL_SOURCE_MISSING:')
        print('REPOSITORY DELETION RED exit=1 NATIVE_SKILL_SOURCE_MISSING', flush=True)
        skill.write_bytes(original)
        self.repository_source()
        print('REPOSITORY DELETION GREEN exit=0', flush=True)
        skill.write_bytes(original.replace(b'Use EAFP', b'use EAFP', 1))
        self.repository_source(code=1, contains='NATIVE_REPOSITORY_BYTES_MODIFIED:')
        print('REPOSITORY MUTATION RED exit=1 NATIVE_REPOSITORY_BYTES_MODIFIED', flush=True)
        skill.write_bytes(original)
        self.repository_source()
        print('REPOSITORY MUTATION GREEN exit=0', flush=True)

    def test_repository_all_bytes_match_audited_source(self):
        package = self.root / '.agents/skills' / NAME
        for name in ['SKILL.md', 'LICENSE', 'upstream.json']:
            with self.subTest(name=name):
                path = package / name
                original = path.read_bytes()
                path.write_bytes(original + b'\n')
                self.repository_source(code=1, contains='NATIVE_REPOSITORY_BYTES_MODIFIED:')
                path.write_bytes(original)
        self.repository_source()

    def test_repository_index_and_head_bytes_required(self):
        path = '.agents/skills/' + NAME + '/SKILL.md'
        self.cmd('git', 'rm', '--cached', path)
        self.repository_source(code=1, contains='NATIVE_SKILL_SOURCE_UNTRACKED:')
        self.cmd('git', 'add', path)
        blob = self.cmd('git', 'hash-object', '-w', str(self.source / 'LICENSE')).strip()
        self.cmd('git', 'update-index', '--cacheinfo', '100644,' + blob + ',' + path)
        self.repository_source(code=1, contains='NATIVE_SKILL_SOURCE_UNTRACKED:')
        self.cmd('git', 'reset', '-q', 'HEAD', '--', path)
        self.repository_source()

    def test_repository_unsafe_files_and_symlink_escapes(self):
        package = self.root / '.agents/skills' / NAME
        path = package / 'SKILL.md'
        original = path.read_bytes()
        path.chmod(0o755)
        self.repository_source(code=1, contains='NATIVE_SKILL_SOURCE_UNSAFE:')
        path.chmod(0o644)
        path.unlink()
        path.symlink_to(self.source / 'SKILL.md')
        self.repository_source(code=1, contains='NATIVE_SKILL_SOURCE_UNSAFE:')
        path.unlink()
        path.write_bytes(original)
        extra = package / 'run.sh'
        extra.write_text('exit 0\n')
        extra.chmod(0o755)
        self.repository_source(code=1, contains='NATIVE_REPOSITORY_PACKAGE_INCOMPLETE')
        extra.unlink()
        package.rename(self.base / 'escaped')
        package.symlink_to(self.base / 'escaped', target_is_directory=True)
        self.repository_source(code=1, contains='NATIVE_SKILL_PATH_UNSAFE')

    def test_repository_fingerprint_detects_deletion_and_mutation(self):
        tool = str(self.root / 'scripts/pack-codex.py')
        before = self.cmd('python3', '-I', tool, 'fingerprint')
        self.cmd('bash', 'scripts/bootstrap-codex.sh')
        self.cmd('bash', 'scripts/verify-codex.sh')
        path = self.root / '.agents/skills' / NAME / 'SKILL.md'
        original = path.read_bytes()
        path.unlink()
        self.assertNotEqual(before, self.cmd('python3', '-I', tool, 'fingerprint'))
        self.cmd('bash', 'scripts/verify-codex.sh', code=1, contains='source revision or adapter files changed')
        path.write_bytes(original)
        self.assertEqual(before, self.cmd('python3', '-I', tool, 'fingerprint'))
        self.cmd('bash', 'scripts/verify-codex.sh')
        path.write_bytes(original.replace(b'Use EAFP', b'use EAFP', 1))
        self.assertNotEqual(before, self.cmd('python3', '-I', tool, 'fingerprint'))
        self.cmd('bash', 'scripts/verify-codex.sh', code=1, contains='source revision or adapter files changed')
        path.write_bytes(original)
        self.assertEqual(before, self.cmd('python3', '-I', tool, 'fingerprint'))
        self.cmd('bash', 'scripts/verify-codex.sh')

    def test_default_full_setup_strict_preservation_and_fallback(self):
        target = self.base / 'target'
        target.mkdir()
        self.cmd('git', 'init', '-q', str(target))
        (target / 'sentinel').write_text('preserve me\n')
        self.cmd('git', '-C', str(target), 'add', 'sentinel')
        before = snapshot(self.root), snapshot(target), snapshot(self.home)
        env = dict(self.env)
        env.pop('HARNESS_ENABLE_NATIVE_SKILLS')
        output = self.setup(env=env, timeout=240)
        self.assertNotIn('NATIVE_SKILL_LINK_VERIFIED', output)
        self.repository_source(env=env)
        read = subprocess.run(['python3', '-I', str(self.root / 'scripts/pack-codex.py'), 'read', 'skill/python-patterns'],
                              cwd=target, env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(read.returncode, 0, read.stdout + read.stderr)
        self.assertIn('WORKFLOW_INSTRUCTION_READ id=skill/python-patterns', read.stdout)
        self.assertNotIn('PROVIDER_INVOKED', read.stdout)
        self.assertEqual((snapshot(self.root), snapshot(target), snapshot(self.home)), before)
        print('DEFAULT_REAL_SETUP exit=0; strict wrapper/target/HOME bytes and metadata unchanged; fallback read exit=0; native dispatch NOT_OBSERVED', flush=True)

    def test_idempotent_install_and_inspect(self):
        self.native()
        before = snapshot(self.home)
        self.native()
        output = self.native('inspect', contains='NATIVE_SKILL_LINK_VERIFIED')
        self.assertEqual(before, snapshot(self.home))
        self.assertNotIn('PROVIDER_DISCOVERED', output)
        self.assertNotIn('PROVIDER_INVOKED', output)
        self.assertEqual(self.link.parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(self.link.parent.parent.stat().st_mode & 0o777, 0o700)

    def test_source_and_link_deletion_red_green(self):
        skill = self.source / 'SKILL.md'
        original = skill.read_bytes()
        skill.unlink()
        self.native(code=1, contains='NATIVE_SKILL_SOURCE_MISSING:')
        self.native('source', code=1, contains='NATIVE_SKILL_SOURCE_MISSING:')
        self.assertFalse((self.home / '.agents').exists())
        print('DELETION SOURCE RED exit=1 NATIVE_SKILL_SOURCE_MISSING', flush=True)
        skill.write_bytes(original)
        self.native(contains='NATIVE_SKILL_LINK_VERIFIED')
        self.link.unlink()
        self.native('inspect', code=1, contains='NATIVE_SKILL_LINK_ABSENT')
        print('DELETION POINTER RED exit=1 NATIVE_SKILL_LINK_ABSENT', flush=True)
        self.native()
        self.native('inspect')
        print('DELETION SOURCE/POINTER GREEN exit=0; provider discovery remains unproven', flush=True)

    def test_missing_and_unrelated_destination_preservation(self):
        before = snapshot(self.home)
        self.native('inspect', code=1, contains='NATIVE_SKILL_LINK_ABSENT')
        self.assertEqual(before, snapshot(self.home))
        self.link.parent.mkdir(parents=True, mode=0o700)
        for kind in ['file', 'directory', 'foreign-link', 'relative-link']:
            with self.subTest(kind=kind):
                if kind == 'file':
                    self.link.write_text('foreign')
                elif kind == 'directory':
                    self.link.mkdir()
                    (self.link / 'keep').write_text('foreign')
                else:
                    self.link.symlink_to('/outside' if kind == 'foreign-link' else os.path.relpath(self.source, self.link.parent))
                before = snapshot(self.home)
                for action in ['install', 'inspect', 'remove']:
                    self.native(action, code=1, contains='NATIVE_SKILL_LINK_CONFLICT')
                    self.assertEqual(before, snapshot(self.home))
                shutil.rmtree(self.link) if self.link.is_dir() and not self.link.is_symlink() else self.link.unlink()

    def test_unrelated_skill_and_rollback(self):
        other = self.home / '.agents/skills/other'
        other.mkdir(parents=True)
        (other / 'SKILL.md').write_text('third-party bytes')
        before = snapshot(other)
        self.native()
        self.native('remove', contains='NATIVE_SKILL_LINK_REMOVED')
        self.assertFalse(self.link.is_symlink())
        self.assertEqual(before, snapshot(other))
        self.native('inspect', code=1, contains='NATIVE_SKILL_LINK_ABSENT')

    def test_partial_parent_creation_is_recoverable(self):
        (self.home / '.agents').mkdir(mode=0o700)
        self.native()
        self.link.unlink()
        self.native()

    def test_parent_symlink_and_escape_preserved(self):
        external = self.base / 'external'
        external.mkdir()
        (self.home / '.agents').symlink_to(external)
        before = snapshot(self.home), snapshot(external)
        self.native(code=1)
        self.assertEqual((snapshot(self.home), snapshot(external)), before)

    def test_unsafe_parent_mode_preserved(self):
        parent = self.home / '.agents'
        parent.mkdir()
        parent.chmod(0o777)
        before = snapshot(self.home)
        self.native(code=1, contains='NATIVE_SKILL_PARENT_UNSAFE')
        self.assertEqual(snapshot(self.home), before)

    def test_unavailable_mismatched_and_traversal_home(self):
        for value in ['', str(self.base / 'missing'), str(self.home) + '/../home', str(self.base / 'other'), 'relative', '/']:
            with self.subTest(value=value):
                before = snapshot(self.home)
                self.native(code=1, contains='NATIVE_SKILL_HOME_INVALID', env=dict(self.env, HOME=value))
                self.assertEqual(snapshot(self.home), before)

    def test_home_symlink_is_refused(self):
        alias = self.base / 'alias'
        alias.symlink_to(self.home)
        self.native(code=1, contains='NATIVE_SKILL_PATH_UNSAFE', env=dict(self.env, HOME=str(alias), FIXTURE_PASSWD_HOME=str(alias)))

    def test_missing_actual_home_is_not_created(self):
        missing = str(self.base / 'missing')
        self.native(code=1, contains='NATIVE_SKILL_HOME_UNAVAILABLE', env=dict(self.env, HOME=missing, FIXTURE_PASSWD_HOME=missing))
        self.assertFalse(Path(missing).exists())

    def test_target_repository_home_is_refused(self):
        self.cmd('git', 'init', '-q', str(self.home))
        before = snapshot(self.home)
        self.native(code=1, contains='NATIVE_SKILL_HOME_REPOSITORY_FORBIDDEN')
        self.assertEqual(snapshot(self.home), before)

    def test_target_shaped_discovery_parent_is_refused(self):
        parent = self.home / '.agents'
        parent.mkdir()
        (parent / '.git').write_text('gitdir: /outside\n')
        before = snapshot(self.home)
        self.native(code=1, contains='NATIVE_SKILL_HOME_REPOSITORY_FORBIDDEN')
        self.assertEqual(snapshot(self.home), before)

    def test_managed_home_is_refused(self):
        for managed in [self.home, self.home / '.agents', self.home / '.agents/skills', self.link]:
            for populated in [False, True]:
                with self.subTest(managed=managed, populated=populated):
                    if populated:
                        managed.mkdir(parents=True, exist_ok=True)
                        (managed / 'managed-sentinel').write_text('preserve managed bytes')
                    before = snapshot(self.home)
                    self.native(code=1, contains='NATIVE_SKILL_HOME_FORBIDDEN', env=dict(self.env, CODEX_HOME=str(managed)))
                    self.assertEqual(snapshot(self.home), before)
                    if populated:
                        if managed == self.home:
                            (managed / 'managed-sentinel').unlink()
                        else:
                            shutil.rmtree(self.home / '.agents')

    def test_modified_frontmatter_body_and_license(self):
        cases = [('SKILL.md', lambda b: b.replace(b'name: harness-python-patterns', b'name: python-patterns'), 'NATIVE_SKILL_FRONTMATTER_INVALID'),
                 ('SKILL.md', lambda b: b + b'changed\n', 'NATIVE_SKILL_BODY_MODIFIED'),
                 ('LICENSE', lambda b: b + b'changed\n', 'NATIVE_SKILL_LICENSE_INVALID')]
        for name, mutate, error in cases:
            with self.subTest(error=error):
                p = self.source / name
                original = p.read_bytes()
                p.write_bytes(mutate(original))
                self.native(code=1, contains=error)
                self.assertFalse((self.home / '.agents').exists())
                p.write_bytes(original)

    def test_stale_provenance_and_paths(self):
        p = self.source / 'upstream.json'
        original = p.read_bytes()
        for field, value in [('commit', '0' * 40), ('package_version', 'stale'), ('adapted_path', '../escape'), ('adapted_sha256', '0' * 64)]:
            with self.subTest(field=field):
                data = json.loads(original)
                data[field] = value
                p.write_text(json.dumps(data))
                self.native(code=1, contains='NATIVE_SKILL_PROVENANCE_INVALID')
        p.write_bytes(original)

    def test_source_symlink_and_extra_executable(self):
        skill = self.source / 'SKILL.md'
        original = skill.read_bytes()
        skill.unlink()
        skill.symlink_to(self.root / 'config/codex/cloud-pack/skills/python-patterns/SKILL.md')
        self.native(code=1, contains='NATIVE_SKILL_SOURCE_UNSAFE')
        skill.unlink()
        skill.write_bytes(original)
        (self.source / 'run.sh').write_text('false\n')
        self.native(code=1, contains='NATIVE_SKILL_PACKAGE_INCOMPLETE')

    def test_untracked_source_and_wrong_checkout(self):
        self.cmd('git', 'rm', '--cached', NATIVE + '/SKILL.md')
        self.native(code=1, contains='NATIVE_SKILL_SOURCE_UNTRACKED')
        self.cmd('git', 'remote', 'set-url', 'origin', 'https://github.com/example/target.git')
        self.native(code=1, contains='NATIVE_SKILL_CHECKOUT_INVALID')

    def test_uncommitted_source_and_stale_pack_anchor(self):
        p = self.source / 'upstream.json'
        p.write_bytes(p.read_bytes() + b'\n')
        self.native(code=1, contains='NATIVE_SKILL_SOURCE_UNCOMMITTED')
        self.cmd('git', 'checkout', '--', NATIVE + '/upstream.json')
        p = self.root / 'config/codex/pack.sha256'
        p.write_text('0' * 64 + '\n')
        self.native(code=1, contains='NATIVE_SKILL_SOURCE_UNCOMMITTED')

    def test_opt_out_and_invalid_flag_have_no_home_writes(self):
        self.stub_suites()
        before = snapshot(self.home)
        for value in ['0', None]:
            env = dict(self.env)
            if value is None:
                env.pop('HARNESS_ENABLE_NATIVE_SKILLS')
            else:
                env['HARNESS_ENABLE_NATIVE_SKILLS'] = value
            self.setup(env=env)
            self.assertEqual(snapshot(self.home), before)
        self.setup(env=dict(self.env, HARNESS_ENABLE_NATIVE_SKILLS='yes'), code=1, contains='NATIVE_SKILL_OPT_IN_INVALID')
        self.native(env=dict(self.env, HARNESS_ENABLE_NATIVE_SKILLS='0'), code=1, contains='NATIVE_SKILL_OPT_IN_REQUIRED')
        self.assertEqual(snapshot(self.home), before)

    def test_fallback_without_native_capabilities(self):
        self.stub_suites()
        self.setup(env=dict(self.env, HARNESS_ENABLE_NATIVE_SKILLS='0'))
        self.native('inspect', code=1, contains='NATIVE_SKILL_LINK_ABSENT')
        self.cmd('python3', '-I', str(self.root / 'scripts/pack-codex.py'), 'read', 'skill/python-patterns', contains='WORKFLOW_INSTRUCTION_READ id=skill/python-patterns')
        self.assertFalse((self.home / '.agents').exists())

    def test_fallback_after_native_setup_conflict(self):
        self.stub_suites()
        self.link.parent.mkdir(parents=True)
        self.link.write_text('foreign bytes')
        before = snapshot(self.home)
        self.setup(code=1, contains='NATIVE_SKILL_LINK_CONFLICT')
        self.cmd('python3', '-I', str(self.root / 'scripts/pack-codex.py'), 'read', 'skill/python-patterns', contains='WORKFLOW_INSTRUCTION_READ id=skill/python-patterns')
        self.assertEqual(before, snapshot(self.home))

    def test_permission_denial_and_interruption_preserve_foreign_bytes(self):
        module = runpy.run_path(str(self.root / 'scripts/provision-native-skills.py'))
        parent = self.home / '.agents/skills'
        parent.mkdir(parents=True)
        (parent / 'other').write_text('keep')
        before = snapshot(self.home)
        account = pwd_account(self.home)
        with patch.dict(os.environ, self.env), patch('pwd.getpwuid', return_value=account), patch.object(sys, 'argv', ['fixture', 'install']):
            with patch('os.symlink', side_effect=PermissionError('fixture permission denied')):
                with self.assertRaises(PermissionError):
                    module['main']()
        self.assertEqual(snapshot(self.home), before)
        self.native()

    def test_interruption_after_link_creation_is_recoverable(self):
        module = runpy.run_path(str(self.root / 'scripts/provision-native-skills.py'))
        with patch.dict(os.environ, self.env), patch('pwd.getpwuid', return_value=pwd_account(self.home)), patch.object(sys, 'argv', ['fixture', 'install']):
            with patch('os.fsync', side_effect=OSError('fixture interruption')):
                with self.assertRaises(OSError):
                    module['main']()
        before = snapshot(self.home)
        self.native()
        self.assertEqual(snapshot(self.home), before)

    def test_simulated_wrong_owner_is_rejected(self):
        module = runpy.run_path(str(self.root / 'scripts/provision-native-skills.py'))
        s = self.home.stat()
        wrong = os.stat_result((s.st_mode,s.st_ino,s.st_dev,s.st_nlink,s.st_uid+1,s.st_gid,s.st_size,s.st_atime,s.st_mtime,s.st_ctime))
        with patch('os.fstat', return_value=wrong):
            with self.assertRaisesRegex(ValueError, 'NATIVE_SKILL_PARENT_UNSAFE'):
                module['check_directory'](0)

    def test_git_context_does_not_touch_target(self):
        target = self.base / 'target'
        target.mkdir()
        self.cmd('git', 'init', '-q', str(target))
        before = snapshot(target)
        env = dict(self.env, GIT_DIR=str(target / '.git'), GIT_WORK_TREE=str(target), GIT_INDEX_FILE=str(target / '.git/index'),
                   GIT_CONFIG_COUNT='1', GIT_CONFIG_KEY_0='core.worktree', GIT_CONFIG_VALUE_0=str(target))
        self.native(env=env)
        self.assertEqual(before, snapshot(target))

    def test_concurrent_install_preserves_one_pointer(self):
        args = [self.python, '-I', str(self.root / 'scripts/provision-native-skills.py'), 'install']
        runs = [subprocess.Popen(args, cwd=self.root, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(4)]
        for run in runs:
            stdout, stderr = run.communicate(timeout=20)
            self.assertEqual(run.returncode, 0, (stdout + stderr).decode())
        self.assertEqual(self.link.readlink(), self.source)
        self.assertEqual([p.name for p in self.link.parent.iterdir()], [NAME])

    def test_target_snapshot_detects_files_and_git_changes(self):
        target = self.base / 'target'
        target.mkdir()
        self.cmd('git', 'init', '-q', str(target))
        tool = str(self.root / 'scripts/check-native-preservation.py')
        initial = self.cmd('python3', '-I', tool, str(target))
        self.assertEqual(initial, self.cmd('python3', '-I', tool, str(target)))
        (target / 'file').write_text('changed')
        changed = self.cmd('python3', '-I', tool, str(target))
        self.assertNotEqual(initial, changed)
        (target / '.git/config').write_text('changed Git bytes')
        self.assertNotEqual(changed, self.cmd('python3', '-I', tool, str(target)))
        external = self.base / 'external'
        external.write_text('external')
        (target / 'link').symlink_to(external)
        before = self.cmd('python3', '-I', tool, str(target))
        external.write_text('outside change')
        self.assertEqual(before, self.cmd('python3', '-I', tool, str(target)))

    def test_lock_timeout_is_bounded(self):
        self.native()
        module = runpy.run_path(str(self.root / 'scripts/provision-native-skills.py'))
        with patch('fcntl.flock', side_effect=BlockingIOError), patch('time.monotonic', side_effect=[0, 11]):
            with self.assertRaisesRegex(ValueError, 'NATIVE_SKILL_LOCK_TIMEOUT'):
                with module['skill_directory'](self.home, True):
                    self.fail('lock unexpectedly acquired')


if __name__ == '__main__':
    unittest.main(verbosity=2)
