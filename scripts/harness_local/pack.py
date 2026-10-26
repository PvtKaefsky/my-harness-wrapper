from typing import Any
import hashlib
import json
import os
import re
from pathlib import Path

PIN = "d468c521f1a76e7b05d446d805f6ad2afa8ed066"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe(path: str | Path) -> Path:
    if ".." in Path(path).parts:
        raise ValueError("PATH_NOT_CANONICAL")
    path = Path(path).absolute()
    for part in [*reversed(path.parents), path]:
        if part.is_symlink() or (hasattr(part, "is_junction") and part.is_junction()):
            raise ValueError("PATH_REPARSE_POINT: " + str(part))
    return path


def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("JSON_DUPLICATE_KEY: " + key)
        result[key] = value
    return result


def decode(data: bytes | str) -> Any:
    return json.loads(data, object_pairs_hook=unique)


class Pack:
    def __init__(self, root: str | Path) -> None:
        self.root = safe(root)
        self.path = self.root / "config/codex/pack"

    def verify(self) -> "Pack":
        safe(self.path)
        manifest_bytes = (self.path / "manifest.json").read_bytes()
        anchor = (self.root / "config/codex/local-pack.sha256").read_text(encoding="ascii").strip()
        if digest(manifest_bytes) != anchor:
            raise ValueError("PACK_MANIFEST_STALE_OR_TAMPERED")
        manifest = decode(manifest_bytes)
        if manifest["schema_version"] != 3 or manifest["upstream_commit"] != PIN:
            raise ValueError("PACK_SCHEMA_INVALID")
        expected = manifest["files"]
        found = set()
        for directory, dirs, names in os.walk(self.path, followlinks=False):
            for name in [*dirs, *names]:
                safe(Path(directory) / name)
            for name in names:
                relative = (Path(directory) / name).relative_to(self.path).as_posix()
                if relative != "manifest.json":
                    found.add(relative)
        if found != set(expected):
            raise ValueError("PACK_FILE_SET_MISMATCH")
        for name, record in expected.items():
            if name.startswith("/") or "\\" in name or ".." in Path(name).parts or ":" in name:
                raise ValueError("PACK_PATH_UNSAFE")
            path = safe(self.path / name)
            if not path.is_file() or path.stat().st_size > 4 * 1024 * 1024:
                raise ValueError("PACK_FILE_INVALID")
            if digest(path.read_bytes()) != record["sha256"]:
                raise ValueError("PACK_ARTIFACT_TAMPERED: " + name)
        catalog = decode((self.path / "catalog.json").read_bytes())
        self.items = {}
        paths = set()
        for item in catalog["items"]:
            ident, name = item["id"], item["path"]
            if not re.fullmatch(r"(skill|role|workflow|rule)/[a-z0-9/-]+", ident):
                raise ValueError("PACK_ID_INVALID")
            if ident in self.items or name in paths or name not in expected:
                raise ValueError("PACK_CATALOG_INVALID")
            if item["sources"] != expected[name].get("upstream_paths"):
                raise ValueError("PACK_SOURCE_MAPPING_INVALID")
            self.items[ident] = item
            paths.add(name)
        for ident in self.items:
            chain = set()
            while ident:
                if ident in chain or ident not in self.items:
                    raise ValueError("PACK_CATALOG_CYCLE_OR_MISSING_LINK")
                chain.add(ident)
                ident = self.items[ident].get("uses")
        self.anchor = anchor
        return self

    def read(self, ident: str) -> str:
        if ident not in self.items:
            raise ValueError("PACK_WORKFLOW_UNKNOWN: " + ident)
        output = []
        while ident:
            item = self.items[ident]
            raw = (self.path / item["path"]).read_bytes()
            output.append("WORKFLOW_INSTRUCTION_READ id=" + ident + " sha256=" + digest(raw))
            output.append(raw.decode("utf-8"))
            ident = item.get("uses")
        return "\n".join(output)

    def catalog(self) -> str:
        return (self.path / "CATALOG.md").read_text(encoding="utf-8")
