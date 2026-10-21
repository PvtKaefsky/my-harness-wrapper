#!/usr/bin/env -S python3 -I
import contextlib
import fcntl
import hashlib
import json
import os
import pwd
import stat
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).absolute().parent.parent
NAME = "harness-python-patterns"
RELATIVE = "config/codex/native-skills/" + NAME
TARGET = ROOT / RELATIVE
ADAPTED = "skills/python-patterns/SKILL.md"
HEADER = b"---\nname: harness-python-patterns\ndescription: Review Python design, EAFP versus LBYL, resource ownership, typing, and exceptional paths using the shared wrapper's audited Python patterns.\n---\n\n"
GIT_SELECTORS = {'GIT_DIR', 'GIT_WORK_TREE', 'GIT_COMMON_DIR', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY', 'GIT_ALTERNATE_OBJECT_DIRECTORIES', 'GIT_QUARANTINE_PATH', 'GIT_GRAFT_FILE', 'GIT_SHALLOW_FILE', 'GIT_NAMESPACE', 'GIT_PREFIX', 'GIT_INTERNAL_SUPER_PREFIX', 'GIT_CONFIG', 'GIT_CONFIG_PARAMETERS', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_SYSTEM', 'GIT_TEMPLATE_DIR'}


def require(condition, name):
    if not condition:
        raise ValueError(name)


def git(*args):
    env = {k: v for k, v in os.environ.items() if k not in GIT_SELECTORS and not k.startswith(('GIT_CONFIG_KEY_', 'GIT_CONFIG_VALUE_'))}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null')
    return subprocess.check_output(['git', '--no-optional-locks', '-C', str(ROOT), *args], env=env, stderr=subprocess.PIPE, timeout=15)


def safe_ancestors(path):
    require(path.is_absolute() and str(path) == os.path.realpath(path), 'NATIVE_SKILL_PATH_UNSAFE')
    for p in [*reversed(path.parents), path]:
        s = p.lstat()
        require(stat.S_ISDIR(s.st_mode) and s.st_uid in {Path('/').stat().st_uid, os.getuid()}
                and (not s.st_mode & 0o022 or bool(s.st_mode & stat.S_ISVTX)), 'NATIVE_SKILL_PATH_UNSAFE')


def source_bytes(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC | os.O_NONBLOCK)
    except FileNotFoundError:
        raise ValueError('NATIVE_SKILL_SOURCE_MISSING: ' + str(path)) from None
    except OSError as error:
        raise ValueError('NATIVE_SKILL_SOURCE_UNSAFE: ' + str(path)) from error
    with os.fdopen(fd, 'rb') as stream:
        s = os.fstat(stream.fileno())
        require(stat.S_ISREG(s.st_mode) and s.st_uid == os.getuid() and not s.st_mode & 0o133
                and s.st_size <= 1024 * 1024, 'NATIVE_SKILL_SOURCE_UNSAFE: ' + str(path))
        data = stream.read(1024 * 1024 + 1)
        require(len(data) <= 1024 * 1024, 'NATIVE_SKILL_SOURCE_UNSAFE: ' + str(path))
        return data


def repository_at(path):
    marker = path / '.git'
    return marker.is_symlink() or marker.is_file() or (marker.is_dir() and next(marker.iterdir(), None) is not None)


def tracked(path):
    data = source_bytes(ROOT / path)
    try:
        blob = git('rev-parse', '--verify', 'HEAD:' + path).decode().strip()
        require(git('ls-files', '--stage', '--', path).decode().strip() == '100644 ' + blob + ' 0\t' + path, 'NATIVE_SKILL_SOURCE_UNTRACKED: ' + path)
        require(git('show', 'HEAD:' + path) == data, 'NATIVE_SKILL_SOURCE_UNCOMMITTED: ' + path)
    except subprocess.CalledProcessError:
        raise ValueError('NATIVE_SKILL_SOURCE_UNTRACKED: ' + path) from None
    return data


def verify_source():
    safe_ancestors(ROOT)
    require(ROOT.stat().st_uid == os.getuid() and not ROOT.stat().st_mode & 0o022, 'NATIVE_SKILL_SOURCE_UNSAFE')
    require(git('rev-parse', '--show-toplevel').decode().strip() == str(ROOT)
            and git('rev-parse', '--absolute-git-dir').decode().strip() == str(ROOT / '.git'), 'NATIVE_SKILL_CHECKOUT_INVALID')
    require(git('remote', 'get-url', 'origin').decode().strip() in {
        'https://github.com/PvtKaefsky/my-harness-wrapper.git', 'https://github.com/PvtKaefsky/my-harness-wrapper',
        'git@github.com:PvtKaefsky/my-harness-wrapper.git', 'ssh://git@github.com/PvtKaefsky/my-harness-wrapper.git'}, 'NATIVE_SKILL_CHECKOUT_INVALID')
    for p in ROOT.parents:
        require(not repository_at(p), 'NATIVE_SKILL_CHECKOUT_NESTED')
    safe_ancestors(TARGET)
    skill = source_bytes(TARGET / 'SKILL.md')
    require({p.name for p in TARGET.iterdir()} == {'SKILL.md', 'LICENSE', 'upstream.json'}, 'NATIVE_SKILL_PACKAGE_INCOMPLETE')
    for path in ['scripts/pack-codex.py', 'config/codex/pack.sha256', 'config/codex/cloud-pack/manifest.json']:
        tracked(path)
    check = subprocess.run([sys.executable, '-I', str(ROOT / 'scripts/pack-codex.py'), 'verify'], capture_output=True, text=True, timeout=15)
    require(check.returncode == 0, 'NATIVE_SKILL_PACK_INVALID: ' + check.stdout.strip() + check.stderr.strip())
    pack = ROOT / 'config/codex/cloud-pack'
    manifest = json.loads((pack / 'manifest.json').read_bytes())
    upstream = json.loads((pack / 'upstream.json').read_bytes())
    require(skill.startswith(HEADER), 'NATIVE_SKILL_FRONTMATTER_INVALID')
    require(skill[len(HEADER):] == (pack / ADAPTED).read_bytes(), 'NATIVE_SKILL_BODY_MODIFIED')
    require(source_bytes(TARGET / 'LICENSE') == (pack / 'LICENSE').read_bytes(), 'NATIVE_SKILL_LICENSE_INVALID')
    expected = {k: upstream[k] for k in ['repository', 'commit', 'package_version']}
    expected.update(schema_version=1, pack_manifest_sha256=hashlib.sha256((pack / 'manifest.json').read_bytes()).hexdigest(),
                    adapted_path=ADAPTED, adapted_sha256=manifest['files'][ADAPTED]['sha256'],
                    files={p: upstream['files'][p] for p in ['LICENSE', ADAPTED]})
    require(json.loads(source_bytes(TARGET / 'upstream.json')) == expected, 'NATIVE_SKILL_PROVENANCE_INVALID')
    for name in ['SKILL.md', 'LICENSE', 'upstream.json']:
        tracked(RELATIVE + '/' + name)
    digest = hashlib.sha256(skill).hexdigest()
    print('NATIVE_SKILL_SOURCE_VERIFIED source=' + str(TARGET) + ' sha256=' + digest + ' head=' + git('rev-parse', 'HEAD').decode().strip())


def home_path():
    require(os.getuid() == os.geteuid(), 'NATIVE_SKILL_IDENTITY_INVALID')
    value = os.environ.get('HOME', '')
    account = pwd.getpwuid(os.getuid())
    require(bool(value) and value == account.pw_dir and value != '/' and str(Path(value)) == value, 'NATIVE_SKILL_HOME_INVALID')
    home = Path(value)
    try:
        safe_ancestors(home)
    except FileNotFoundError:
        raise ValueError('NATIVE_SKILL_HOME_UNAVAILABLE') from None
    require(home.stat().st_uid == os.getuid() and not home.stat().st_mode & 0o022, 'NATIVE_SKILL_HOME_UNSAFE')
    for p in home.parents:
        require(not repository_at(p), 'NATIVE_SKILL_HOME_REPOSITORY_FORBIDDEN')
    require(not os.path.lexists(home / '.git'), 'NATIVE_SKILL_HOME_REPOSITORY_FORBIDDEN')
    forbidden = [Path('/etc/codex'), Path('/run/codex-environment')]
    if os.environ.get('CODEX_HOME'):
        forbidden.append(Path(os.path.realpath(os.environ['CODEX_HOME'])))
    destinations = [home, home / '.agents', home / '.agents/skills', home / '.agents/skills' / NAME]
    require(not any(p == destination or p in destination.parents for p in forbidden for destination in destinations), 'NATIVE_SKILL_HOME_FORBIDDEN')
    return home


def check_directory(fd):
    s = os.fstat(fd)
    require(s.st_uid == os.getuid() and not s.st_mode & 0o022, 'NATIVE_SKILL_PARENT_UNSAFE')
    try:
        os.stat('.git', dir_fd=fd, follow_symlinks=False)
    except FileNotFoundError:
        return
    raise ValueError('NATIVE_SKILL_HOME_REPOSITORY_FORBIDDEN')


@contextlib.contextmanager
def skill_directory(home, create, exclusive=False):
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
    with contextlib.ExitStack() as stack:
        fd = os.open('/', flags)
        stack.callback(os.close, fd)
        for part in home.parts[1:]:
            fd = os.open(part, flags, dir_fd=fd)
            stack.callback(os.close, fd)
        check_directory(fd)
        for part in ['.agents', 'skills']:
            try:
                child = os.open(part, flags, dir_fd=fd)
            except FileNotFoundError:
                if not create:
                    yield None
                    return
                try:
                    os.mkdir(part, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
                child = os.open(part, flags, dir_fd=fd)
            stack.callback(os.close, child)
            check_directory(child)
            fd = child
        deadline = time.monotonic() + 10
        while True:
            try:
                fcntl.flock(fd, (fcntl.LOCK_EX if create or exclusive else fcntl.LOCK_SH) | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                require(time.monotonic() < deadline, 'NATIVE_SKILL_LOCK_TIMEOUT')
                time.sleep(0.05)
        yield fd


def link_present(fd):
    if fd is None:
        return False
    try:
        s = os.stat(NAME, dir_fd=fd, follow_symlinks=False)
    except FileNotFoundError:
        return False
    require(stat.S_ISLNK(s.st_mode) and s.st_uid == os.getuid()
            and os.readlink(NAME, dir_fd=fd) == str(TARGET), 'NATIVE_SKILL_LINK_CONFLICT')
    return True


def main():
    args = sys.argv[1:]
    require(len(args) == 1 and args[0] in {'source', 'inspect', 'install', 'remove'}, 'usage: provision-native-skills.py source|inspect|install|remove')
    action = args[0]
    if action in {'install', 'remove'}:
        require(os.environ.get('HARNESS_ENABLE_NATIVE_SKILLS') == '1', 'NATIVE_SKILL_OPT_IN_REQUIRED')
    verify_source()
    if action == 'source':
        return
    home = home_path()
    with skill_directory(home, action == 'install', action == 'remove') as fd:
        present = link_present(fd)
        if action == 'install' and not present:
            try:
                os.symlink(str(TARGET), NAME, dir_fd=fd)
            except FileExistsError:
                require(link_present(fd), 'NATIVE_SKILL_LINK_CONFLICT')
            os.fsync(fd)
            present = link_present(fd)
        if action == 'remove' and present:
            os.unlink(NAME, dir_fd=fd)
            os.fsync(fd)
            print('NATIVE_SKILL_LINK_REMOVED')
            return
        require(present, 'NATIVE_SKILL_LINK_ABSENT')
        print('NATIVE_SKILL_LINK_VERIFIED path=' + str(home / '.agents/skills' / NAME) + ' source=' + str(TARGET))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print('FAIL ' + str(error), file=sys.stderr)
        sys.exit(1)
