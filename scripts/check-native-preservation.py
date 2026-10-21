#!/usr/bin/env -S python3 -I
import hashlib
import json
import os
import stat
import sys
from pathlib import Path


def snapshot(value):
    root = Path(value)
    if not root.is_absolute() or str(root) != os.path.realpath(root) or not root.is_dir():
        raise ValueError('TARGET_SNAPSHOT_PATH_UNSAFE')
    if not (root / '.git').is_dir() or (root / '.git').is_symlink():
        raise ValueError('TARGET_SNAPSHOT_EXTERNAL_GIT_UNSUPPORTED')
    records = []
    pending = [root]
    while pending:
        p = pending.pop()
        s = p.lstat()
        data = ''
        if p.name == '.git' and not stat.S_ISDIR(s.st_mode):
            raise ValueError('TARGET_SNAPSHOT_EXTERNAL_GIT_UNSUPPORTED')
        if stat.S_ISLNK(s.st_mode):
            data = os.readlink(p)
        elif stat.S_ISDIR(s.st_mode):
            pending.extend(sorted(p.iterdir(), reverse=True))
        elif stat.S_ISREG(s.st_mode):
            digest = hashlib.sha256()
            with os.fdopen(os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC), 'rb') as stream:
                if os.fstat(stream.fileno()) != s:
                    raise ValueError('TARGET_SNAPSHOT_CHANGED_DURING_READ')
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
                after = os.fstat(stream.fileno())
                if (s.st_ino, s.st_size, s.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
                    raise ValueError('TARGET_SNAPSHOT_CHANGED_DURING_READ')
            data = digest.hexdigest()
        else:
            raise ValueError('TARGET_SNAPSHOT_SPECIAL_FILE_UNSUPPORTED')
        records.append((str(p.relative_to(root)), s.st_mode, s.st_uid, s.st_gid, s.st_ino, s.st_mtime_ns, data))
        if len(records) + len(pending) > 1000000:
            raise ValueError('TARGET_SNAPSHOT_LIMIT_EXCEEDED')
    return hashlib.sha256(json.dumps(records, separators=(',', ':')).encode()).hexdigest()


if __name__ == '__main__':
    try:
        if len(sys.argv) != 2:
            raise ValueError('usage: check-native-preservation.py /absolute/target')
        print('TARGET_SNAPSHOT_SHA256=' + snapshot(sys.argv[1]))
    except (ValueError, OSError) as error:
        print('FAIL ' + str(error), file=sys.stderr)
        sys.exit(1)
