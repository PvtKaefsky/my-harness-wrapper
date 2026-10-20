#!/usr/bin/env python3
import json
import os
from pathlib import Path
import signal
import subprocess
import sys


SHA = "76aaa77df6adc5b889e689007bf99b9a4f74af34"
scenario = os.environ.get("ECC_TEST_CASE", "success")
home = Path(os.environ["CODEX_HOME"])
home.mkdir(exist_ok=True)
record = home / "fake.json"
state = json.loads(record.read_text()) if record.exists() else {"marketplace": False, "installed": False, "installs": 0, "adds": 0}
args = sys.argv[1:]
root = home / "marketplaces/ecc"
cache = home / "plugins/cache/ecc/ecc/2.2.3"


def save():
    record.write_text(json.dumps(state))


def emit(value):
    print(json.dumps(value))


def package():
    root.mkdir(parents=True, exist_ok=True)
    if not (root / ".git").exists():
        subprocess.run(["git", "init", "-q", str(root)], check=True)
    (root / ".git/HEAD").write_text(("0" * 40 if scenario == "wrong-ref" else SHA) + "\n")
    manifest = {"name": "ecc", "version": "2.2.3", "skills": "./skills/", "mcpServers": "./.mcp.json",
                "hooks": "./hooks/codex-hooks.json", "interface": {"composerIcon": "./assets/ecc-icon.svg", "logo": "./assets/hero.png"}}
    if scenario == "null-interface":
        manifest["interface"] = None
    files = {".codex-plugin/plugin.json": json.dumps(manifest),
             ".claude-plugin/marketplace.json": json.dumps({"name": "ecc", "plugins": [{"name": "ecc", "source": "./"}]}),
             "skills/configure-ecc/SKILL.md": "stub skill; never invoked\n", ".mcp.json": "{}",
             "hooks/codex-hooks.json": "{}", "assets/ecc-icon.svg": "stub icon", "assets/hero.png": "stub image"}
    fixtures = Path(os.environ["ECC_TEST_FIXTURES"])
    if scenario != "skill-source-absent":
        files["skills/python-patterns/SKILL.md"] = (fixtures / "SKILL.md").read_text()
    files["LICENSE"] = (fixtures / "LICENSE").read_text()
    if scenario == "skill-source-changed":
        files["skills/python-patterns/SKILL.md"] += "changed\n"
    for name, content in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    if scenario == "null-marketplace-plugins":
        (root / ".claude-plugin/marketplace.json").write_text('{"name":"ecc","plugins":null}')


if scenario in ("installed", "wrong-source", "wrong-ref") and not state["marketplace"]:
    package()
    state["marketplace"] = True
    if scenario == "installed":
        import shutil
        shutil.copytree(root, cache, dirs_exist_ok=True)
        state["installed"] = True
    save()

with (home / "calls").open("a") as calls:
    calls.write(" ".join(args) + "\n")

if args == ["--version"]:
    print("codex-cli 0.159.2 (STUB)")
elif args and args[-1] == "--help":
    print("Usage: codex plugin add list " + ("" if scenario == "no-marketplace" else "marketplace ") + "--json " +
          ("" if scenario == "no-pin-option" else "--ref REF"))
elif args == ["plugin", "marketplace", "list", "--json"]:
    entries = [{"name": "unrelated", "root": "/unrelated", "marketplaceSource": {"sourceType": "git", "source": "other/repo"}}]
    if state["marketplace"]:
        entries.append({"name": "ecc", "root": str(root), "marketplaceSource": {"sourceType": "git",
                        "source": "other/ECC" if scenario == "wrong-source" else "https://github.com/affaan-m/ECC.git"}})
        if scenario == "null-marketplace-source":
            entries[-1]["marketplaceSource"] = None
    emit({"marketplaces": entries})
elif args == ["plugin", "list", "--json"]:
    if state["installed"] and scenario in ("malformed", "empty"):
        print("{invalid" if scenario == "malformed" else "")
    else:
        emit({"installed": [{"pluginId": "ecc@ecc", "name": "ecc", "marketplaceName": "ecc", "version": "2.2.3",
                             "installed": True, "enabled": True, "source": {"source": "local", "path": str(root)}}]
              if state["installed"] else [], "available": []})
elif args[:4] == ["plugin", "marketplace", "add", "affaan-m/ECC"]:
    assert args[4:] == ["--ref", SHA, "--json"], args
    state["adds"] += 1
    save()
    if scenario == "ref-rejected":
        print("unsupported pinned ref argument", file=sys.stderr)
        sys.exit(2)
    if scenario == "network":
        print("proxy connection failed to https://user:password@host.invalid/?token=hidden", file=sys.stderr)
        print("proxy connection refused", file=sys.stderr)
        sys.exit(8)
    if scenario == "readonly":
        print("Error: failed to create marketplace install directory /run/codex-environment/codex-home/.tmp/marketplaces: Read-only file system (os error 30)", file=sys.stderr)
        sys.exit(13)
    if scenario == "redaction":
        print("Authorization: Bearer credential-value", file=sys.stderr)
        print("fetch https://user:pass@host.invalid/?key=url-secret", file=sys.stderr)
        print("token ghp_abc123456789", file=sys.stderr)
        print("proxy connection failed", file=sys.stderr)
        sys.exit(8)
    if scenario == "interrupted":
        os.kill(os.getppid(), signal.SIGTERM)
        sys.exit(143)
    if scenario == "oversized":
        print("z" * 100000)
        sys.exit(3)
    already = state["marketplace"]
    package()
    state["marketplace"] = True
    save()
    emit({"marketplaceName": "ecc", "installedRoot": str(root), "alreadyAdded": already})
elif args == ["plugin", "add", "ecc@ecc", "--json"]:
    if scenario == "install-failed":
        print("installer failed: diagnostic sentinel", file=sys.stderr)
        sys.exit(19)
    if not state["installed"]:
        import shutil
        shutil.copytree(root, cache, dirs_exist_ok=True)
        state["installed"] = True
        state["installs"] += 1
        if scenario == "broken-cache":
            (cache / "assets/hero.png").unlink()
        if scenario == "unreadable-cache":
            (cache / ".codex-plugin/plugin.json").chmod(0)
        if scenario == "malformed-manifest":
            (cache / ".codex-plugin/plugin.json").write_text("{}")
        if scenario == "fifo-manifest":
            (cache / ".codex-plugin/plugin.json").unlink()
            os.mkfifo(cache / ".codex-plugin/plugin.json")
        if scenario == "fifo-skill":
            os.mkfifo(cache / "skills/fifo")
        if scenario == "many-cache-entries":
            for index in range(10001):
                (cache / "skills" / str(index)).touch()
        if scenario == "looping-cache-reference":
            (cache / "assets/hero.png").unlink()
            (cache / "assets/hero.png").symlink_to("hero.png")
    save()
    emit({"pluginId": "ecc@ecc", "name": "ecc", "marketplaceName": "ecc", "version": "2.2.3", "installedPath": str(cache)})
else:
    print("unsupported fake command", file=sys.stderr)
    sys.exit(2)
