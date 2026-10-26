from typing import Any
import base64
import json
import os
import re
import shlex
import subprocess
import sys
import uuid
from pathlib import Path

from .pack import Pack, decode, digest, safe
from .storage import atomic_write, json_bytes, lock, owner_check

OWNER = b"my-harness-wrapper/codex-local/v2\n"
BEGIN = b"<!-- BEGIN my-harness-wrapper -->\n"
END = b"<!-- END my-harness-wrapper -->\n"
RUNTIME_INPUTS = ["scripts/harness_local", "scripts/codex-local.py", "config/codex/pack",
                  "config/codex/AGENTS.md", "config/codex/local-pack.sha256",
                  "config/codex/version", "AGENTS.md", "README.md", "docs"]


def encoded(data: bytes | None) -> str | None:
    return None if data is None else base64.b64encode(data).decode("ascii")


def decoded(data: str | None) -> bytes | None:
    return None if data is None else base64.b64decode(data, validate=True)


def current_bytes(path: str | Path) -> bytes | None:
    path = safe(path)
    if path.exists() and (not path.is_file() or path.stat().st_nlink != 1):
        raise ValueError("INSTALL_PATH_NOT_ORDINARY: " + str(path))
    return path.read_bytes() if path.exists() else None


def outside_repository(path: Path) -> None:
    for part in [path, *path.parents]:
        if (part / ".git").exists():
            raise ValueError("INSTALL_TARGET_REPOSITORY_FORBIDDEN: " + str(path))


def existing_parent(path: Path) -> Path:
    while not path.exists():
        path = path.parent
    return safe(path)


def trusted_chain(path: Path, boundary: Path) -> None:
    path, boundary = safe(path), safe(boundary)
    if not path.is_relative_to(boundary) or not boundary.is_dir():
        raise ValueError("INSTALL_TRUST_BOUNDARY_INVALID")
    for directory in [path, *path.parents]:
        if directory.exists():
            owner_check(directory)
        if directory == boundary:
            return
    raise ValueError("INSTALL_TRUST_BOUNDARY_INVALID")


def windows_command(command: list[str]) -> str:
    if any(any(character in argument for character in '%!\r\n"') for argument in command):
        raise ValueError("WINDOWS_HOOK_PATH_UNSUPPORTED")
    return " ".join('"' + argument.rstrip("\\") + "\\" *
                    (2 * (len(argument) - len(argument.rstrip("\\")))) + '"'
                    for argument in command)


def registration_root(path: Path, profile: Path, home: Path) -> Path:
    if path in {home / "AGENTS.md", home / "hooks.json"}:
        return home
    if path.parent == home / "agents" and re.fullmatch(r"harness-[a-z0-9-]+\.toml", path.name):
        return home
    skills = profile / ".agents/skills"
    if path.is_relative_to(skills):
        parts = path.relative_to(skills).parts
        if len(parts) == 2 and re.fullmatch(r"harness-[a-z0-9-]+", parts[0]) and parts[1] == "SKILL.md":
            return profile
    raise ValueError("STATE_ARTIFACT_PATH_INVALID")


def registration_check(path: Path, profile: Path, home: Path) -> None:
    path = safe(path)
    boundary = registration_root(path, profile, home)
    outside_repository(boundary)
    directory = path.parent
    while directory.is_relative_to(boundary):
        safe(directory)
        if directory.exists():
            owner_check(directory)
        if directory == boundary:
            break
        directory = directory.parent
    if path.exists():
        current_bytes(path)
        owner_check(path)


def remove_owned(record: dict[str, Any], current: bytes | None) -> bytes | None:
    after, before = decoded(record["after"]), decoded(record["before"])
    if current == after:
        return before
    if current is None:
        raise ValueError("OWNED_FILE_MISSING: " + record["path"])
    if record["kind"] == "policy":
        fragment = decoded(record["fragment"])
        if current.count(fragment) != 1:
            raise ValueError("OWNED_POLICY_MODIFIED")
        return current.replace(fragment, b"", 1)
    if record["kind"] == "hooks":
        data = decode(current)
        original = decode(before) if before else {}
        for event, group in record["groups"].items():
            values = data.get("hooks", {}).get(event, [])
            if values.count(group) != 1:
                raise ValueError("OWNED_HOOK_MODIFIED: " + event)
            values.remove(group)
            if not values and event not in original.get("hooks", {}):
                del data["hooks"][event]
        if not before and data == {"hooks": {}}:
            return None
        return json_bytes(data)
    raise ValueError("OWNED_FILE_MODIFIED: " + record["path"])


def add_owned(spec: dict[str, Any], before: bytes | None) -> dict[str, Any]:
    result = dict(spec)
    result["before"] = encoded(before)
    if spec["kind"] == "policy":
        if before and (BEGIN in before or END in before):
            raise ValueError("POLICY_MARKER_COLLISION")
        fragment = decoded(spec["fragment"])
        if before and not before.endswith(b"\n") and not fragment.startswith(b"\n"):
            fragment = b"\n" + fragment
        result["fragment"] = encoded(fragment)
        result["after"] = encoded((before or b"") + fragment)
    elif spec["kind"] == "hooks":
        data = decode(before) if before else {"hooks": {}}
        if not isinstance(data, dict) or not isinstance(data.get("hooks", {}), dict):
            raise ValueError("HOOK_CONFIG_INVALID")
        data.setdefault("hooks", {})
        for event, group in spec["groups"].items():
            values = data["hooks"].setdefault(event, [])
            if not isinstance(values, list):
                raise ValueError("HOOK_CONFIG_INVALID")
            if group in values:
                raise ValueError("HOOK_REGISTRATION_COLLISION")
            values.append(group)
        result["after"] = encoded(json_bytes(data))
    else:
        if before is not None:
            raise ValueError("UNOWNED_FILE_COLLISION: " + spec["path"])
    return result


class Installation:
    def __init__(self, source: str | Path, state: str | Path) -> None:
        if not Path(state).is_absolute():
            raise ValueError("STATE_PATH_NOT_ABSOLUTE")
        self.source = safe(source)
        self.state = safe(state)
        if self.state == self.source or self.state.is_relative_to(self.source):
            raise ValueError("STATE_SOURCE_OVERLAP")
        outside_repository(self.state)

    def load(self) -> tuple[dict[str, Any], dict[str, Any], Path]:
        trusted_chain(self.state.parent, existing_parent(self.state.parent))
        if current_bytes(self.state / ".owner") != OWNER:
            raise ValueError("STATE_NOT_OWNED")
        owner_check(self.state / ".owner")
        owner_check(self.state)
        if (self.state / "journal.json").exists():
            raise ValueError("INSTALL_INTERRUPTED: run recover --apply")
        owner_check(self.state / "active.json")
        active = decode(current_bytes(self.state / "active.json"))
        manifest, directory = self.read_release(active)
        return active, manifest, directory

    def read_release(self, active: dict[str, Any]) -> tuple[dict[str, Any], Path]:
        if not re.fullmatch(r"release-[a-f0-9]{32}", active["release"]):
            raise ValueError("STATE_RELEASE_INVALID")
        directory = safe(self.state / "releases" / active["release"])
        owner_check(self.state / "releases")
        owner_check(directory)
        metadata = safe(directory / "manifest.json")
        owner_check(metadata)
        raw = current_bytes(metadata)
        if digest(raw) != active["manifest_sha256"]:
            raise ValueError("STATE_MANIFEST_MODIFIED")
        manifest = decode(raw)
        boundaries = manifest.get("trust_boundaries")
        roots = {"state": self.state, "profile": safe(manifest["profile"]),
                 "home": safe(manifest["codex_home"])}
        if not isinstance(boundaries, dict) or set(boundaries) != set(roots):
            raise ValueError("INSTALL_TRUST_BOUNDARY_INVALID")
        for name, root in roots.items():
            trusted_chain(root, Path(boundaries[name]))
        for record in manifest["artifacts"]:
            path = safe(record["path"])
            profile = safe(manifest["profile"])
            home = safe(manifest["codex_home"])
            registration_root(path, profile, home)
        return manifest, directory

    def specifications(self, pack: Pack, release: Path, profile: Path, home: Path) -> list[dict[str, Any]]:
        cli = release / "scripts/codex-local.py"
        command = [sys.executable, "-X", "utf8", "-I", str(cli),
                   "--state", str(self.state), "hook"]
        windows = windows_command(command) if os.name == "nt" else subprocess.list2cmdline(command)
        groups = {
            "SessionStart": {"matcher": "^(startup|resume|compact|fork|clear)$", "hooks": [{
                "type": "command", "command": shlex.join(command), "commandWindows": windows,
                "timeout": 10, "statusMessage": "Harness startup verification"}]},
            "UserPromptSubmit": {"hooks": [{
                "type": "command", "command": shlex.join(command), "commandWindows": windows,
                "timeout": 10, "statusMessage": "Harness working-policy reminder"}]},
            "PreToolUse": {"matcher": "^(Bash|exec_command|functions.exec_command|mcp__.*github.*)$",
                           "hooks": [{"type": "command", "command": shlex.join(command),
                                      "commandWindows": windows, "timeout": 10,
                                      "statusMessage": "Harness explicit tool guard"}]},
        }
        policy = (self.source / "config/codex/AGENTS.md").read_bytes()
        policy = policy.replace(b"{{HARNESS_ROOT}}", str(release).encode("utf-8"))
        policy = policy.replace(b"{{HARNESS_STATE}}", str(self.state).encode("utf-8"))
        fragment = BEGIN + policy.rstrip() + b"\n" + END
        specs = [{"path": str(home / "AGENTS.md"), "kind": "policy",
                  "fragment": encoded(fragment)},
                 {"path": str(home / "hooks.json"), "kind": "hooks", "groups": groups}]
        for ident, item in pack.items.items():
            kind, name = ident.split("/", 1)
            if kind not in {"skill", "workflow", "role"}:
                continue
            instructions = pack.read(ident)
            if kind == "role":
                agent = "harness-" + name
                raw = ("name = " + json.dumps(agent) + "\ndescription = " +
                       json.dumps(item["title"]) + "\ndeveloper_instructions = " +
                       json.dumps(instructions, ensure_ascii=False) + "\n").encode("utf-8")
                path = home / "agents" / (agent + ".toml")
            else:
                native = "harness-" + ("workflow-" if kind == "workflow" else "") + name
                raw = ("---\nname: " + native + "\ndescription: " +
                       json.dumps(item["title"] + ". Apply the harness " + ident +
                                  " within the user's current task authorization.") +
                       "\n---\n\n" + instructions).encode("utf-8")
                path = profile / ".agents/skills" / native / "SKILL.md"
            specs.append({"path": str(path), "kind": "file", "after": encoded(raw)})
        return specs

    def source_hash(self) -> str:
        records = []
        for name in RUNTIME_INPUTS:
            entry = self.source / name
            files = [entry] if entry.is_file() else sorted(entry.rglob("*"))
            for path in files:
                safe(path)
                if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc":
                    records.append((path.relative_to(self.source).as_posix(), digest(path.read_bytes())))
        return digest(json_bytes(records))

    def verify_runtime(self, manifest: dict[str, Any], directory: Path) -> None:
        checked = set()
        for name, expected in manifest["runtime"].items():
            path = safe(directory / name)
            for parent in [path, *path.parents]:
                if not parent.is_relative_to(directory):
                    break
                if parent not in checked:
                    owner_check(parent)
                    checked.add(parent)
            if digest(current_bytes(path)) != expected:
                raise ValueError("INSTALLED_RUNTIME_MODIFIED: " + name)
        found = {path.relative_to(directory).as_posix() for path in directory.rglob("*")
                 if path.is_file() and "__pycache__" not in path.parts
                 and path.suffix != ".pyc" and path != directory / "manifest.json"}
        if found != set(manifest["runtime"]):
            raise ValueError("INSTALLED_RUNTIME_FILE_SET_MISMATCH")
        Pack(directory).verify()

    def verify(self) -> tuple[dict[str, Any], Path]:
        active, manifest, directory = self.load()
        self.verify_runtime(manifest, directory)
        for record in manifest["artifacts"]:
            registration_check(Path(record["path"]), Path(manifest["profile"]), Path(manifest["codex_home"]))
            remove_owned(record, current_bytes(record["path"]))
        return manifest, directory

    def plan(self, profile: str | Path | None = None, codex_home: str | Path | None = None,
             trust_boundaries: dict[str, str] | None = None) -> dict[str, Any]:
        pack = Pack(self.source).verify()
        old = None
        if (self.state / "active.json").exists():
            old = self.load()[1]
        profile = safe(profile or (old["profile"] if old else Path.home()))
        home = safe(codex_home or (old["codex_home"] if old else
                                  os.environ.get("CODEX_HOME", str(profile / ".codex"))))
        outside_repository(profile / ".agents")
        outside_repository(home)
        boundaries = old["trust_boundaries"] if old else trust_boundaries or {
            "state": str(existing_parent(self.state.parent)),
            "profile": str(profile if profile.exists() else existing_parent(profile.parent)),
            "home": str(profile if home.is_relative_to(profile) and profile.exists()
                        else existing_parent(home.parent))}
        for name, destination in {"state": self.state, "profile": profile, "home": home}.items():
            trusted_chain(destination, Path(boundaries[name]))
        if self.state.is_relative_to(profile / ".agents") or self.state.is_relative_to(home):
            raise ValueError("STATE_DISCOVERY_OVERLAP")
        if current_bytes(home / "AGENTS.override.md"):
            raise ValueError("POLICY_SHADOWED_BY_OVERRIDE")
        if old and (str(profile) != old["profile"] or str(home) != old["codex_home"]):
            raise ValueError("INSTALL_ROOT_CHANGE_REQUIRES_UNINSTALL")
        release_id = "release-" + uuid.uuid4().hex
        release = self.state / "releases" / release_id
        previous = {record["path"]: record for record in old["artifacts"]} if old else {}
        records = []
        for spec in self.specifications(pack, release, profile, home):
            registration_check(Path(spec["path"]), profile, home)
            current = current_bytes(spec["path"])
            before = remove_owned(previous.pop(spec["path"]), current) if spec["path"] in previous else current
            record = add_owned(spec, before)
            record["expected"] = encoded(current)
            records.append(record)
        retired = []
        for record in previous.values():
            registration_check(Path(record["path"]), profile, home)
            current = current_bytes(record["path"])
            retired.append({"path": record["path"], "expected": encoded(current),
                            "after": encoded(remove_owned(record, current))})
        selectors = {"GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE",
                     "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_PREFIX",
                     "GIT_CONFIG", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
                     "GIT_CONFIG_SYSTEM", "GIT_TEMPLATE_DIR", "GIT_SHALLOW_FILE",
                     "GIT_NAMESPACE", "GIT_QUARANTINE_PATH", "GIT_GRAFT_FILE",
                     "GIT_INTERNAL_SUPER_PREFIX"}
        environment = {key: value for key, value in os.environ.items()
                       if key not in selectors and not key.startswith(("GIT_CONFIG_KEY_", "GIT_CONFIG_VALUE_"))}
        source_head = subprocess.run(["git", "--no-optional-locks", "-C", str(self.source),
                                      "rev-parse", "--verify", "HEAD"],
                                     env=environment, capture_output=True)
        source_status = subprocess.run(["git", "--no-optional-locks", "-C", str(self.source),
                                        "status", "--porcelain"], env=environment, capture_output=True)
        version = (self.source / "config/codex/version").read_text(encoding="ascii").strip()
        if not re.fullmatch(r"\d+\.\d+\.\d+", version):
            raise ValueError("ADAPTER_VERSION_INVALID")
        return {"schema_version": 3, "adapter_version": version, "release": release_id,
                "source_commit": source_head.stdout.decode("ascii").strip() if source_head.returncode == 0 else None,
                "source_dirty": bool(source_status.stdout) if source_status.returncode == 0 else None,
                "trust_boundaries": boundaries,
                "source_checkout": str(self.source), "profile": str(profile),
                "codex_home": str(home), "source_hash": self.source_hash(),
                "pack_sha256": pack.anchor, "artifacts": records, "retirements": retired}

    def transact(self, records: list[dict[str, Any]], active: dict[str, Any] | None) -> None:
        journal = {"schema_version": 1, "active_before": encoded(current_bytes(self.state / "active.json")),
                   "active_after": encoded(json_bytes(active)) if active else None, "records": records}
        atomic_write(self.state / "journal.json", json_bytes(journal))
        for record in records:
            path = safe(record["path"])
            if current_bytes(path) != decoded(record["expected"]):
                raise ValueError("INSTALL_CONCURRENT_CHANGE: " + str(path))
            value = decoded(record["after"])
            if value is None:
                if path.exists():
                    path.unlink()
            else:
                atomic_write(path, value)
        if active:
            atomic_write(self.state / "active.json", json_bytes(active))
        elif (self.state / "active.json").exists():
            (self.state / "active.json").unlink()
        (self.state / "journal.json").unlink()

    def apply(self, profile: str | Path | None = None, codex_home: str | Path | None = None) -> str:
        candidate = self.plan(profile, codex_home)
        if self.state.exists() and current_bytes(self.state / ".owner") != OWNER:
            raise ValueError("STATE_NOT_OWNED")
        with lock(self.state):
            if not (self.state / ".owner").exists():
                atomic_write(self.state / ".owner", OWNER)
            candidate = self.plan(profile, codex_home, candidate["trust_boundaries"])
            prior = self.load()[0] if (self.state / "active.json").exists() else None
            if prior and all(self.load()[1].get(key) == candidate[key]
                             for key in ["source_hash", "source_commit", "source_dirty"]):
                self.verify()
                return "PASS INSTALL_ALREADY_CURRENT"
            release = safe(self.state / "releases" / candidate["release"])
            release.mkdir(parents=True, mode=0o700)
            runtime = {}
            for name in RUNTIME_INPUTS:
                entry = self.source / name
                paths = [entry] if entry.is_file() else sorted(entry.rglob("*"))
                for path in paths:
                    if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc":
                        relative = path.relative_to(self.source)
                        data = safe(path).read_bytes()
                        atomic_write(release / relative, data)
                        runtime[relative.as_posix()] = digest(data)
            candidate["runtime"] = runtime
            candidate["parent"] = prior
            atomic_write(release / "manifest.json", json_bytes(candidate))
            active = {"release": candidate["release"],
                      "manifest_sha256": digest((release / "manifest.json").read_bytes())}
            self.transact(candidate["artifacts"] + candidate["retirements"], active)
        return "PASS INSTALL_APPLIED release=" + candidate["release"]

    def uninstall(self) -> str:
        with lock(self.state):
            active, manifest, directory = self.load()
            records = []
            for record in manifest["artifacts"]:
                registration_check(Path(record["path"]), Path(manifest["profile"]), Path(manifest["codex_home"]))
                current = current_bytes(record["path"])
                records.append({"path": record["path"], "expected": encoded(current),
                                "after": encoded(remove_owned(record, current))})
            self.transact(records, None)
        return "PASS UNINSTALLED"

    def rollback(self) -> str:
        manifest = self.load()[1]
        if manifest.get("parent") is None:
            return self.uninstall()
        with lock(self.state):
            active, manifest, directory = self.load()
            parent = manifest["parent"]
            old, predecessor = self.read_release(parent)
            self.verify_runtime(old, predecessor)
            previous = {record["path"]: record for record in old["artifacts"]}
            changes = []
            for record in manifest["artifacts"]:
                registration_check(Path(record["path"]), Path(manifest["profile"]), Path(manifest["codex_home"]))
                actual = current_bytes(record["path"])
                before = remove_owned(record, actual)
                if record["path"] in previous:
                    specification = dict(previous.pop(record["path"]))
                    after = decoded(add_owned(specification, before)["after"])
                else:
                    after = before
                changes.append({"path": record["path"], "expected": encoded(actual),
                                "after": encoded(after)})
            for record in previous.values():
                registration_check(Path(record["path"]), Path(old["profile"]), Path(old["codex_home"]))
                actual = current_bytes(record["path"])
                restored = add_owned(record, actual)
                changes.append({"path": record["path"], "expected": encoded(actual),
                                "after": restored["after"]})
            self.transact(changes, parent)
        return "PASS ROLLED_BACK release=" + parent["release"]

    def recover(self) -> str:
        trusted_chain(self.state.parent, existing_parent(self.state.parent))
        if current_bytes(self.state / ".owner") != OWNER:
            raise ValueError("STATE_NOT_OWNED")
        with lock(self.state):
            owner_check(self.state / ".owner")
            owner_check(self.state / "journal.json")
            journal = decode((self.state / "journal.json").read_bytes())
            if journal.get("schema_version") != 1:
                raise ValueError("RECOVERY_SCHEMA_INVALID")
            references = [journal.get("active_before"), journal.get("active_after")]
            if not any(references):
                raise ValueError("RECOVERY_MANIFEST_MISSING")
            allowed = set()
            for index, reference in enumerate(references):
                if not reference:
                    continue
                manifest, directory = self.read_release(decode(decoded(reference)))
                if index == 0:
                    self.verify_runtime(manifest, directory)
                for record in manifest["artifacts"]:
                    registration_check(Path(record["path"]), Path(manifest["profile"]), Path(manifest["codex_home"]))
                    allowed.add(record["path"])
            paths = [record["path"] for record in journal["records"]]
            if set(paths) != allowed or len(set(paths)) != len(paths):
                raise ValueError("RECOVERY_ARTIFACT_SET_INVALID")
            for record in journal["records"]:
                actual = current_bytes(record["path"])
                if actual not in {decoded(record["after"]), decoded(record["expected"])}:
                    raise ValueError("RECOVERY_CONCURRENT_CHANGE")
            for record in reversed(journal["records"]):
                path = safe(record["path"])
                actual = current_bytes(path)
                if actual not in {decoded(record["after"]), decoded(record["expected"])}:
                    raise ValueError("RECOVERY_CONCURRENT_CHANGE")
                before = decoded(record["expected"])
                if before is None:
                    if path.exists():
                        path.unlink()
                else:
                    atomic_write(path, before)
            active = decoded(journal["active_before"])
            if active is None:
                if (self.state / "active.json").exists():
                    (self.state / "active.json").unlink()
            else:
                atomic_write(self.state / "active.json", active)
            (self.state / "journal.json").unlink()
        return "PASS RECOVERED"
