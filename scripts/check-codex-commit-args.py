#!/usr/bin/env -S python3 -I
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).absolute().parent


def main():
    args = iter(sys.argv[1:])
    messages = []
    for arg in args:
        if arg in {"-m", "--message", "-F", "--file"}:
            value = next(args, None)
            if value is None or value == "-": raise ValueError("COMMIT_MESSAGE_FILE_OR_VALUE_REQUIRED")
            messages.append(Path(value).read_text() if arg in {"-F", "--file"} else value)
        elif arg.startswith("--message=") or (arg.startswith("-m") and not arg.startswith("--")):
            messages.append(arg.split("=", 1)[1] if arg.startswith("--") else arg[2:])
        elif arg.startswith("--file=") or (arg.startswith("-F") and not arg.startswith("--")):
            value = arg.split("=", 1)[1] if arg.startswith("--") else arg[2:]
            if value == "-": raise ValueError("COMMIT_MESSAGE_FILE_OR_VALUE_REQUIRED")
            messages.append(Path(value).read_text())
        elif arg in {"--quiet", "-q", "--verbose", "-v", "--no-edit", "--allow-empty", "--allow-empty-message", "--no-gpg-sign", "--signoff", "-s", "-S", "--gpg-sign"}:
            pass
        elif arg.startswith(("--gpg-sign=", "--cleanup=")) or (arg.startswith("-S") and not arg.startswith("--")):
            pass
        else:
            raise ValueError("COMMIT_ARGUMENT_UNSAFE: only staged-tree message/signing/output options are supported")
    if not messages: raise ValueError("COMMIT_EXPLICIT_MESSAGE_REQUIRED")
    with tempfile.TemporaryDirectory(prefix="codex-commit-message-") as directory:
        path = Path(directory) / "message"
        path.write_text("\n\n".join(messages))
        subprocess.run(["bash", str(ROOT / "check-codex-attribution.sh"), str(path)], check=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print("FAIL " + str(error), file=sys.stderr)
        sys.exit(1)
