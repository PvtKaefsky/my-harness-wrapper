#!/usr/bin/env -S python3 -I
import hashlib
import json
import os
import re
import stat
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).absolute().parent.parent
PACK = ROOT / "config/codex/cloud-pack"
PIN = "d468c521f1a76e7b05d446d805f6ad2afa8ed066"
REPOSITORY = "forever94yu/everything-codex-code"
VERSION = "1.7.0-codex.0"


def fail(name):
    raise ValueError(name)


def ordinary(path, directory=False):
    for ancestor in [*reversed(path.parents), path]:
        if ancestor.is_symlink(): fail("PACK_PATH_UNSAFE: " + str(ancestor))
    try:
        mode = path.stat().st_mode
    except FileNotFoundError:
        fail("PACK_MISSING: " + str(path))
    if not (stat.S_ISDIR(mode) if directory else stat.S_ISREG(mode)):
        fail("PACK_PATH_UNSAFE: " + str(path))
    if not directory and path.stat().st_size > 1024 * 1024:
        fail("PACK_FILE_TOO_LARGE")
    return path


def raw(path):
    return ordinary(path).read_bytes()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result: fail("PACK_DUPLICATE_KEY")
        result[key] = value
    return result


def parse(path):
    return json.loads(raw(path), object_pairs_hook=unique)


def safe_relative(name):
    if not isinstance(name, str) or not name or "\\" in name:
        fail("PACK_PATH_UNSAFE")
    parts = name.split("/")
    if any(p in {"", ".", ".."} for p in parts) or name.startswith("/"):
        fail("PACK_PATH_UNSAFE")
    return name


def verify():
    ordinary(PACK, True)
    manifest_raw = raw(PACK / "manifest.json")
    expected = raw(ROOT / "config/codex/pack.sha256").decode().strip()
    if not re.fullmatch(r"[a-f0-9]{64}", expected) or sha(manifest_raw) != expected:
        fail("PACK_MANIFEST_STALE_OR_TAMPERED")
    manifest = parse(PACK / "manifest.json")
    if (manifest.get("schema_version"), manifest.get("repository"), manifest.get("commit"), manifest.get("package_version")) != (1, REPOSITORY, PIN, VERSION):
        fail("PACK_UPSTREAM_PIN_INVALID")
    files = manifest["files"]
    if not isinstance(files, dict) or len(files) > 250:
        fail("PACK_MANIFEST_INVALID")
    actual = set()
    for directory, folders, names in os.walk(PACK, followlinks=False):
        for folder in folders: ordinary(Path(directory) / folder, True)
        for name in names:
            path = Path(directory) / name
            ordinary(path)
            actual.add(path.relative_to(PACK).as_posix())
    if actual != set(files) | {"manifest.json"}: fail("PACK_FILE_SET_INVALID")
    for name, record in files.items():
        safe_relative(name)
        if sha(raw(PACK / name)) != record["sha256"]: fail("PACK_BYTES_MODIFIED: " + name)
        if name.endswith(".md"):
            text = raw(PACK / name).decode()
            if re.search(r"(?i)claude|AskUserQuestion|\bsonnet\b|\bopus\b|\bhaiku\b|~/|\$HOME|CODEX_HOME|curl\s.*\||wget\s.*\||ignore (all |previous |higher)|bypass.*trust|codex exec|\bTask\s*\(", text):
                fail("PACK_INSTRUCTION_UNSAFE: " + name)
    upstream = parse(PACK / "upstream.json")
    if (upstream.get("repository"), upstream.get("commit"), upstream.get("package_version")) != (REPOSITORY, PIN, VERSION): fail("PACK_UPSTREAM_PIN_INVALID")
    sources = upstream["files"]
    if sha(raw(PACK / "LICENSE")) != sources["LICENSE"]["sha256"]: fail("PACK_LICENSE_INVALID")
    for name, record in files.items():
        for path in record["upstream_paths"]:
            safe_relative(path)
            if path not in sources or not re.fullmatch(r"[a-f0-9]{64}", sources[path]["sha256"]): fail("PACK_SOURCE_MAPPING_INVALID")
    catalog = parse(PACK / "catalog.json")
    if catalog.get("schema_version") != 1: fail("PACK_CATALOG_INVALID")
    seen = set()
    paths = set()
    items = catalog["items"]
    if not isinstance(items, list) or not items: fail("PACK_CATALOG_INVALID")
    for item in items:
        ident, path = item["id"], safe_relative(item["path"])
        if not re.fullmatch(r"(skill|role|workflow|rule)/[a-z0-9/-]+", ident): fail("PACK_ID_INVALID")
        if ident in seen or path in paths: fail("PACK_DUPLICATE_ID_OR_PATH: " + ident)
        seen.add(ident)
        paths.add(path)
        if path not in files or not item["requires"] or item["sources"] != files[path]["upstream_paths"]: fail("PACK_CATALOG_MAPPING_INVALID")
        if any(sources[p]["status"] != "adapted" for p in item["sources"]): fail("PACK_SOURCE_MAPPING_INVALID")
    if paths != {p for p in files if p.startswith(("skills/", "roles/", "rules/", "workflows/"))}: fail("PACK_CATALOG_INCOMPLETE")
    for item in items:
        if item.get("uses") and item["uses"] not in seen: fail("PACK_CATALOG_LINK_MISSING")
    by_id = {item["id"]: item for item in items}
    for ident in by_id:
        chain = set()
        while ident:
            if ident in chain: fail("PACK_CATALOG_CYCLE")
            chain.add(ident)
            ident = by_id[ident].get("uses")
    if not {"CATALOG.md", "catalog.json", "upstream.json", "LICENSE"} <= set(files): fail("PACK_INDEX_MISSING")
    return manifest, {item["id"]: item for item in items}


def fingerprint():
    paths = [ROOT / "AGENTS.md", ROOT / "README.md"]
    for name in ["config/codex", "env", "scripts", "docs", ".agents"]:
        base = ROOT / name
        ordinary(base, True)
        for directory, folders, names in os.walk(base, followlinks=False):
            folders[:] = sorted(f for f in folders if f != "__pycache__")
            for folder in folders: ordinary(Path(directory) / folder, True)
            paths.extend(Path(directory) / name for name in names if not name.endswith(".pyc"))
    records = [(p.relative_to(ROOT).as_posix(), sha(raw(p))) for p in sorted(paths)]
    return sha(json.dumps(records, separators=(",", ":")).encode())


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "verify"
    if command == "fingerprint":
        print(fingerprint())
        return
    manifest, items = verify()
    if command == "verify":
        print("PASS PACK_SOURCE_VERIFIED commit=" + PIN + " manifest_sha256=" + sha(raw(PACK / "manifest.json")))
    elif command == "read" and len(sys.argv) == 3:
        subprocess.run(["bash", str(ROOT / "scripts/verify-codex.sh")], check=True)
        ident = sys.argv[2]
        if ident not in items: fail("PACK_WORKFLOW_UNKNOWN")
        queue = [ident]
        while queue:
            item = items[queue.pop(0)]
            print("WORKFLOW_INSTRUCTION_READ id=" + item["id"] + " path=" + str(PACK / item["path"]) + " sha256=" + manifest["files"][item["path"]]["sha256"])
            print(raw(PACK / item["path"]).decode())
            if item.get("uses"): queue.append(item["uses"])
    else:
        fail("Usage: pack-codex.py verify|fingerprint|read ID")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print("FAIL " + str(error), file=sys.stderr)
        sys.exit(1)
