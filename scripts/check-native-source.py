#!/usr/bin/env -S python3 -I
import hashlib
import runpy
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).absolute().parent.parent
SOURCE = runpy.run_path(str(ROOT / 'scripts/provision-native-skills.py'))
RELATIVE = '.agents/skills/harness-python-patterns'
PACKAGE = ROOT / RELATIVE


def verify():
    try:
        SOURCE['safe_ancestors'](PACKAGE)
    except FileNotFoundError:
        raise ValueError('NATIVE_SKILL_SOURCE_MISSING: ' + str(PACKAGE)) from None
    skill = SOURCE['source_bytes'](PACKAGE / 'SKILL.md')
    SOURCE['require']({p.name for p in PACKAGE.iterdir()} == {'SKILL.md', 'LICENSE', 'upstream.json'},
                      'NATIVE_REPOSITORY_PACKAGE_INCOMPLETE')
    SOURCE['verify_source']()
    for name in ['SKILL.md', 'LICENSE', 'upstream.json']:
        data = SOURCE['source_bytes'](PACKAGE / name)
        SOURCE['require'](data == SOURCE['source_bytes'](SOURCE['TARGET'] / name), 'NATIVE_REPOSITORY_BYTES_MODIFIED: ' + name)
        SOURCE['tracked'](RELATIVE + '/' + name)
    print('NATIVE_REPOSITORY_SOURCE_VERIFIED scope=repository source=' + str(PACKAGE)
          + ' sha256=' + hashlib.sha256(skill).hexdigest()
          + ' head=' + SOURCE['git']('rev-parse', 'HEAD').decode().strip())


if __name__ == '__main__':
    try:
        if len(sys.argv) != 1:
            raise ValueError('usage: check-native-source.py')
        verify()
    except (ValueError, KeyError, TypeError, OSError, subprocess.SubprocessError) as error:
        print('FAIL ' + str(error), file=sys.stderr)
        sys.exit(1)
