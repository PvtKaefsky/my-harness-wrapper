#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid


SHA = "76aaa77df6adc5b889e689007bf99b9a4f74af34"
SOURCE = "affaan-m/ECC"
LIMIT = 65536
LOG_LIMIT = 131072
STATUS_LIMIT = 196608
UNVERIFIED = "UNVERIFIED"


class ProbeFailure(Exception):
    def __init__(self, message, category="unknown"):
        super().__init__(message)
        self.category = category


def redact(value):
    value = re.sub(r"[\x00-\x08\x0b-\x1f\x7f]", "?", str(value))
    value = re.sub(r"(?i)\b(?:https?|ssh)://[^\s\"<>]+", "[URL REDACTED]", value)
    value = re.sub(r"(?im)^.*(?:authorization|cookie|password|secret|api[_-]?key|access[_-]?token|bearer).*$",
                   "[SENSITIVE LINE REDACTED]", value)
    value = re.sub(r"\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]+)\b",
                   "[TOKEN REDACTED]", value)
    return value


def classify(message):
    message = message.lower()
    for category, pattern in [
        ("permission/configuration", r"permission denied|read.only|operation not permitted|config.*(?:denied|invalid)"),
        ("CLI incompatibility", r"unexpected argument|unrecognized|unknown (?:command|option)|unsupported|not found"),
        ("network/proxy", r"proxy|network|resolve host|connection|timed? out|tls|certificate|fetch|http [45]\d\d"),
        ("packaging/cache", r"manifest|cache|invalid json|malformed|reference"),
    ]:
        if re.search(pattern, message):
            return category
    return "unknown"


def read_regular(path, limit, private=False, dir_fd=None):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=dir_fd)
    with os.fdopen(fd, "rb") as handle:
        info = os.fstat(handle.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise ValueError("not a bounded regular file")
        if private and (info.st_uid != os.getuid() or info.st_mode & 0o077 or info.st_mode & 0o400 == 0):
            raise PermissionError("evidence must be owner-readable and private")
        return handle.read(limit + 1)


def check_target(path):
    if path.is_symlink() or (path.exists() and not stat.S_ISREG(path.stat().st_mode)):
        raise ValueError("unsafe evidence target")


def atomic_write(path, content):
    check_target(path)
    fd, name = tempfile.mkstemp(prefix=".ecc-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        check_target(path)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def evidence_directory(state, create=False, name="ecc-setup"):
    for parent in [state, *state.parents]:
        metadata = parent / ".git"
        if metadata.is_file() or (metadata / "HEAD").exists():
            raise ValueError("evidence must be outside every source repository")
    directory = state / name
    if create and not directory.exists() and not directory.is_symlink():
        directory.mkdir(mode=0o700)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise PermissionError("unsafe evidence directory")
    return directory


class Recorder:
    def __init__(self, directory, commit, digest):
        self.directory = directory
        self.lines = []
        self.deadline = time.monotonic() + 180
        self.child = None
        self.data = dict(schema_version=1, run_id=uuid.uuid4().hex, phase="setup",
                         source_commit=commit, source_sha256=digest, upstream_sha=SHA,
                         upstream_source=SOURCE, started_at=time.time(), complete=False,
                         ecc_readiness="ECC NOT READY", native_registration=UNVERIFIED,
                         cache=UNVERIFIED, effective_revision=UNVERIFIED,
                         skill_invocation=UNVERIFIED, hook_trust=UNVERIFIED,
                         task_plugin_list=UNVERIFIED,
                         hook_execution=UNVERIFIED, already_present_at_setup=UNVERIFIED,
                         install_attempted_in_setup=False, cli_version=UNVERIFIED,
                         marketplace_add_attempted=False, plugin_add_attempted=False,
                         idempotence=UNVERIFIED, events=[])
        self.note("setup-start", "ECC NOT READY; setup-phase probe starting")

    def publish(self):
        log = ("\n".join(self.lines) + "\n").encode()[:LOG_LIMIT]
        self.data["log_sha256"] = hashlib.sha256(log).hexdigest()
        atomic_write(self.directory / "diagnostic.log", log)
        status = (json.dumps(self.data, indent=2) + "\n").encode()
        if len(status) > STATUS_LIMIT:
            raise ValueError("status size bound exceeded")
        atomic_write(self.directory / "status.json", status)

    def note(self, phase, message, **fields):
        message = redact(message)[:4096]
        self.data["last_phase"] = phase
        self.data["events"].append(dict(phase=phase, detail=message, **fields))
        self.lines.append(f"{phase}: {message}")
        self.publish()

    def run(self, phase, arguments, timeout=10):
        self.note(phase, "attempt started", command=" ".join(arguments[:5]), exit_code=None)
        remaining = min(timeout, self.deadline - time.monotonic())
        if remaining <= 0:
            raise ProbeFailure("setup probe total time bound reached")
        output = {"stdout": bytearray(), "stderr": bytearray()}
        result = None
        failure = None
        try:
            self.child = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                          stdin=subprocess.DEVNULL, start_new_session=True)
            with selectors.DefaultSelector() as selector:
                selector.register(self.child.stdout, selectors.EVENT_READ, "stdout")
                selector.register(self.child.stderr, selectors.EVENT_READ, "stderr")
                until = time.monotonic() + remaining
                while selector.get_map():
                    if time.monotonic() >= until:
                        failure = "command timed out"
                        break
                    for key, _ in selector.select(0.1):
                        chunk = os.read(key.fileobj.fileno(), 8192)
                        if not chunk:
                            selector.unregister(key.fileobj)
                        else:
                            output[key.data].extend(chunk)
                            if sum(map(len, output.values())) > LIMIT:
                                failure = "command output exceeded size bound"
                                break
                    if failure:
                        break
                if failure:
                    os.killpg(self.child.pid, signal.SIGKILL)
                result = self.child.wait(timeout=max(0.1, until - time.monotonic()))
        except FileNotFoundError:
            result, failure = 127, "CLI executable not found"
        except OSError as error:
            result, failure = 126, str(error)
        except subprocess.TimeoutExpired:
            failure = "command timed out"
            os.killpg(self.child.pid, signal.SIGKILL)
            result = self.child.wait()
        finally:
            if self.child and self.child.poll() is None:
                os.killpg(self.child.pid, signal.SIGKILL)
                self.child.wait()
            self.child = None
        raw = output["stdout"][:LIMIT].decode(errors="replace")
        stderr = output["stderr"][:LIMIT].decode(errors="replace")
        detail = f"exit={result}; {failure or ''}\nstderr: {stderr}\nstdout: {raw}"
        self.note(phase, detail, exit_code=result, category=classify(failure or stderr or raw) if failure or result else None)
        if failure or result:
            raise ProbeFailure(f"{phase}: {detail}", classify(failure or stderr or raw))
        return raw

    def json_command(self, phase, arguments, key):
        raw = self.run(phase, arguments)
        try:
            value = json.loads(raw)
            if not isinstance(value, dict) or not isinstance(value.get(key), list):
                raise ValueError("unexpected listing shape")
            if not all(isinstance(entry, dict) for entry in value[key]):
                raise ValueError("unexpected listing entries")
            return value[key]
        except (ValueError, TypeError) as error:
            raise ProbeFailure(f"{phase}: malformed JSON listing: {error}", "CLI incompatibility") from error


def ecc_entry(entries, key):
    matches = [entry for entry in entries if entry.get(key) == "ecc"]
    if len(matches) > 1:
        raise ProbeFailure("ambiguous ECC registration", "permission/configuration")
    return matches[0] if matches else None


def source_matches(source):
    return isinstance(source, str) and bool(re.fullmatch(
        r"(?:affaan-m/ECC|https://github\.com/affaan-m/ECC(?:\.git)?)(?:@" + SHA + r")?", source))


def verify_marketplace(recorder, entry):
    if not entry:
        raise ProbeFailure("ECC marketplace missing after registration", "packaging/cache")
    metadata = entry.get("marketplaceSource")
    if not isinstance(metadata, dict) or not isinstance(entry.get("root"), str):
        raise ProbeFailure("malformed marketplace source/root metadata", "CLI incompatibility")
    source = metadata.get("source")
    if not source_matches(source):
        raise ProbeFailure("ECC existing source/ref conflicts or is UNVERIFIED; preserving registration",
                           "permission/configuration")
    root = Path(entry.get("root", ""))
    if not root.is_absolute() or not (root / ".git").exists():
        raise ProbeFailure("effective marketplace Git revision UNVERIFIED", "packaging/cache")
    actual = recorder.run("marketplace-revision", ["git", "-c", "core.fsmonitor=false", "-C", str(root),
                                                    "rev-parse", "HEAD"]).strip()
    recorder.data["effective_revision"] = actual if re.fullmatch(r"[a-f0-9]{40}", actual) else UNVERIFIED
    if actual != SHA:
        raise ProbeFailure("effective marketplace revision differs from selected SHA", "permission/configuration")
    manifest = read_cache_json(root / ".claude-plugin/marketplace.json")
    plugins = manifest.get("plugins")
    if not isinstance(plugins, list):
        raise ProbeFailure("malformed marketplace manifest plugins", "packaging/cache")
    if manifest.get("name") != "ecc" or not any(
        item.get("name") == "ecc" and item.get("source") in ("./", ".")
        for item in plugins if isinstance(item, dict)
    ):
        raise ProbeFailure("ECC marketplace entry does not select repository root", "packaging/cache")
    recorder.note("marketplace-verified", f"effective revision {actual}; root {root}")
    recorder.data["marketplace_path"] = redact(str(root))
    return root


def read_cache_json(path):
    try:
        value = json.loads(read_regular(path, LIMIT))
    except PermissionError as error:
        raise ProbeFailure(f"cache manifest permission failure: {error}", "permission/configuration") from error
    except (OSError, ValueError) as error:
        raise ProbeFailure(f"cache manifest unreadable or invalid: {error}", "packaging/cache") from error
    if not isinstance(value, dict):
        raise ProbeFailure("cache manifest must be an object", "packaging/cache")
    return value


def contained(root, reference):
    if not isinstance(reference, str) or not reference.startswith("./"):
        raise ProbeFailure("cache reference must be relative", "packaging/cache")
    target = root / reference
    try:
        within_root = target.resolve().is_relative_to(root.resolve())
    except (OSError, RuntimeError) as error:
        raise ProbeFailure(f"cache reference cannot be resolved: {error}", "packaging/cache") from error
    if not within_root:
        raise ProbeFailure("cache reference escapes plugin root", "packaging/cache")
    return target


def tree_digest(root, target, deadline):
    digest = hashlib.sha256()
    files = [target]
    count = 0
    total = 0
    while files:
        if time.monotonic() >= deadline:
            raise ProbeFailure("cache validation time bound exceeded", "packaging/cache")
        file = files.pop()
        count += 1
        if count > 10000:
            raise ProbeFailure("cache file count bound exceeded", "packaging/cache")
        if file.is_symlink() or not file.resolve().is_relative_to(root.resolve()):
            raise ProbeFailure("cache contains symlink or escaping path", "packaging/cache")
        if file.is_dir():
            children = []
            with os.scandir(file) as entries:
                for entry in entries:
                    if count + len(files) + len(children) >= 10000:
                        raise ProbeFailure("cache file count bound exceeded", "packaging/cache")
                    children.append(Path(entry.path))
            files.extend(sorted(children, reverse=True))
            continue
        try:
            content = read_regular(file, 32 * 1024 * 1024 - total)
        except (OSError, ValueError) as error:
            raise ProbeFailure(f"cache file unreadable or unsafe: {error}", "packaging/cache") from error
        total += len(content)
        if total > 32 * 1024 * 1024:
            raise ProbeFailure("cache byte bound exceeded", "packaging/cache")
        digest.update(str(file.relative_to(root)).encode() + b"\0" + content)
    return digest.hexdigest()


def verify_cache(recorder, entry, marketplace):
    recorder.data["cache"] = UNVERIFIED
    if not entry or entry.get("pluginId") != "ecc@ecc" or entry.get("installed") is not True or entry.get("enabled") is not True:
        raise ProbeFailure("ECC installed/enabled plugin registration missing", "packaging/cache")
    if entry.get("version") != "2.2.3":
        raise ProbeFailure("ECC installed version differs from pinned package", "packaging/cache")
    native_home = Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
    cache = native_home / "plugins/cache/ecc/ecc/2.2.3"
    if not cache.is_absolute() or cache.is_symlink() or not cache.is_dir():
        raise ProbeFailure("installed ECC cache missing or unsafe", "packaging/cache")
    manifest = read_cache_json(contained(cache, "./.codex-plugin/plugin.json"))
    upstream = read_cache_json(contained(marketplace, "./.codex-plugin/plugin.json"))
    if manifest != upstream or manifest.get("name") != "ecc" or manifest.get("version") != "2.2.3":
        raise ProbeFailure("cached plugin manifest differs from selected marketplace", "packaging/cache")
    interface = manifest.get("interface", {})
    if not isinstance(interface, dict):
        raise ProbeFailure("malformed manifest interface", "packaging/cache")
    refs = {"skills": manifest.get("skills"), "mcpServers": manifest.get("mcpServers"),
            "hooks": manifest.get("hooks"), "composerIcon": interface.get("composerIcon"),
            "logo": interface.get("logo")}
    screenshots = interface.get("screenshots", [])
    if not isinstance(screenshots, list) or len(screenshots) > 64:
        raise ProbeFailure("invalid manifest screenshot references", "packaging/cache")
    refs.update({f"screenshot-{i}": value for i, value in enumerate(screenshots)})
    for label, reference in refs.items():
        target = contained(cache, reference)
        original = contained(marketplace, reference)
        if label == "skills":
            if not target.is_dir() or not (target / "configure-ecc/SKILL.md").is_file():
                raise ProbeFailure("cache skills or representative SKILL.md missing", "packaging/cache")
        elif not target.is_file():
            raise ProbeFailure(f"cache {label} missing", "packaging/cache")
        if tree_digest(cache, target, recorder.deadline) != tree_digest(marketplace, original, recorder.deadline):
            raise ProbeFailure(f"cache {label} differs from selected marketplace", "packaging/cache")
        if label in ("mcpServers", "hooks"):
            read_cache_json(target)
        recorder.note("cache-reference", f"{label}: verified readable in cache and matches marketplace")
    recorder.data["cache"] = "VERIFIED"
    recorder.data["cache_path"] = redact(str(cache))
    recorder.note("cache-verified", f"manifest, skills, MCP, hooks and assets verified at {cache}; hooks not trusted or executed")


def probe(recorder):
    cli = shutil.which("codex")
    if cli is None:
        recorder.run("cli-version", ["codex", "--version"])
    recorder.data["cli_version"] = redact(recorder.run("cli-version", [cli, "--version"]).strip())[:512]
    for arguments, options in [
        (["plugin", "--help"], ["marketplace", "add", "list"]),
        (["plugin", "marketplace", "add", "--help"], ["--ref", "--json"]),
        (["plugin", "marketplace", "list", "--help"], ["--json"]),
        (["plugin", "add", "--help"], ["--json"]),
        (["plugin", "list", "--help"], ["--json"]),
    ]:
        help_text = recorder.run("cli-options", [cli, *arguments])
        if any(option not in help_text for option in options):
            raise ProbeFailure("CLI lacks supported native pinned registration options", "CLI incompatibility")
    before = recorder.json_command("marketplaces-before", [cli, "plugin", "marketplace", "list", "--json"], "marketplaces")
    plugins = recorder.json_command("plugins-before", [cli, "plugin", "list", "--json"], "installed")
    recorder.data["already_present_at_setup"] = ecc_entry(plugins, "name") is not None
    existing = ecc_entry(before, "name")
    if existing:
        verify_marketplace(recorder, existing)
    unrelated = [entry for entry in before if entry.get("name") != "ecc"]
    for attempt in (1, 2):
        recorder.data["install_attempted_in_setup"] = True
        recorder.data["marketplace_add_attempted"] = True
        recorder.run(f"marketplace-add-{attempt}", [cli, "plugin", "marketplace", "add", SOURCE, "--ref", SHA, "--json"], timeout=30)
        marketplaces = recorder.json_command(f"marketplaces-after-{attempt}", [cli, "plugin", "marketplace", "list", "--json"], "marketplaces")
        if [entry for entry in marketplaces if entry.get("name") != "ecc"] != unrelated:
            raise ProbeFailure("unrelated marketplace registrations changed", "permission/configuration")
        root = verify_marketplace(recorder, ecc_entry(marketplaces, "name"))
        recorder.data["plugin_add_attempted"] = True
        recorder.run(f"plugin-add-{attempt}", [cli, "plugin", "add", "ecc@ecc", "--json"], timeout=30)
        installed = recorder.json_command(f"plugins-after-{attempt}", [cli, "plugin", "list", "--json"], "installed")
        entry = ecc_entry(installed, "name")
        verify_cache(recorder, entry, root)
        recorder.note(f"repeat-check-{attempt}", "native registration and cache verified; skill invocation UNVERIFIED")
    recorder.data.update(native_registration="VERIFIED", idempotence="VERIFIED")


def summarize(directory, data):
    print(f"ECC setup evidence: {directory / 'status.json'}; log: {directory / 'diagnostic.log'}")
    for key in ("phase", "last_phase", "complete", "cli_version", "upstream_sha", "effective_revision",
                "already_present_at_setup", "install_attempted_in_setup", "native_registration", "cache",
                "idempotence", "error_category", "error", "task_plugin_list", "skill_invocation", "hook_trust", "hook_execution"):
        if key in data:
            print(f"ECC {key}: {redact(data[key])[:512]}")
    print("ECC NOT READY: fresh-task skill invocation UNVERIFIED; ordinary project work blocked; diagnostic work only")


def status(state, commit, digest):
    try:
        directory = evidence_directory(state)
        data = json.loads(read_regular(directory / "status.json", STATUS_LIMIT, private=True))
        if not isinstance(data, dict) or data.get("schema_version") != 1 or data.get("phase") != "setup":
            raise ValueError("ECC_SETUP_EVIDENCE_INCOMPLETE: invalid schema or phase")
        if data.get("source_commit") != commit or data.get("source_sha256") != digest or data.get("upstream_sha") != SHA:
            raise ValueError("ECC_SETUP_EVIDENCE_STALE: source revision or fingerprint differs")
        summarize(directory, data)
        log = read_regular(directory / "diagnostic.log", LOG_LIMIT, private=True)
        if hashlib.sha256(log).hexdigest() != data.get("log_sha256") or data.get("complete") is not True:
            raise ValueError("ECC_SETUP_EVIDENCE_INCOMPLETE: partial run or mismatched log/status")
    except FileNotFoundError:
        print("ECC_SETUP_EVIDENCE_MISSING: no retained complete evidence; install attempt unknown; possible setup-snapshot boundary")
        print(f"ECC evidence expected at {state / 'ecc-setup'}")
        print("ECC NOT READY: ordinary project work blocked; diagnostic work only")
    except (OSError, ValueError, TypeError) as error:
        print(f"ECC_SETUP_EVIDENCE_INACCESSIBLE_OR_INVALID: {redact(error)}")
        print(f"ECC evidence expected at {state / 'ecc-setup'}")
        print("ECC NOT READY: ordinary project work blocked; diagnostic work only")
    return 2


def setup(state, commit, digest):
    recorder = Recorder(evidence_directory(state, create=True), commit, digest)

    def interrupted(signum, frame):
        raise ProbeFailure(f"setup interrupted by signal {signum}")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    result = 2
    try:
        probe(recorder)
        recorder.data["complete"] = True
        recorder.note("setup-complete", "native ECC registration/cache verified; ECC NOT READY; fresh task skill invocation UNVERIFIED")
        result = 0
    except (ProbeFailure, OSError, ValueError, TypeError, KeyError) as error:
        recorder.data.update(error=redact(error)[:4096], error_category=getattr(error, "category", classify(str(error))),
                             complete="interrupted" not in str(error))
        recorder.note("setup-failed", f"ECC NOT READY; {recorder.data['error_category']}: {error}")
    summarize(recorder.directory, recorder.data)
    return result


SKILL = "python-patterns"
SKILL_SHA256 = "103e0130dac33a49d26705fc5a2df804980fcab6a0138d65bc7f370a987d49f6"
LICENSE_SHA256 = "326146379f01bb137c0a5d3c54770c1aa31076705c8b88a7f6b26a460f6221b2"
SKILL_FILES = {"SKILL.md": SKILL_SHA256, "LICENSE": LICENSE_SHA256}


def skill_binding(directory):
    data = json.loads(read_regular(directory / "scope.json", LIMIT, private=True))
    if not isinstance(data, dict) or data.get("schema_version") != 1 or data.get("upstream_sha") != SHA or data.get("skill_name") != SKILL or data.get("uid") != os.getuid():
        raise ValueError("ECC_SKILL_SCOPE_BINDING_INVALID")
    home = data.get("home")
    if not isinstance(home, str) or not home.startswith("/") or redact(home) != home or str(Path(home)) != home or os.path.normpath(home) != home or home == "/":
        raise ValueError("ECC_SKILL_SCOPE_BINDING_INVALID")
    if data.get("destination") != str(Path(home) / ".agents/skills" / SKILL):
        raise ValueError("ECC_SKILL_SCOPE_BINDING_INVALID")
    return data


def skill_record(state, commit=None, digest=None):
    directory = evidence_directory(state, name="ecc-skill-probe")
    data = json.loads(read_regular(directory / "status.json", STATUS_LIMIT, private=True))
    if not isinstance(data, dict) or data.get("schema_version") != 1 or data.get("phase") != "skill-setup":
        raise ValueError("ECC_SKILL_EVIDENCE_INVALID")
    log = read_regular(directory / "diagnostic.log", LOG_LIMIT, private=True)
    if data.get("complete") is not True or hashlib.sha256(log).hexdigest() != data.get("log_sha256"):
        raise ValueError("ECC_SKILL_EVIDENCE_INCOMPLETE")
    if data.get("upstream_sha") != SHA or data.get("skill_name") != SKILL or data.get("expected_sha256") != SKILL_SHA256:
        raise ValueError("ECC_SKILL_EVIDENCE_INVALID")
    if commit is not None and (data.get("source_commit") != commit or data.get("source_sha256") != digest):
        raise ValueError("ECC_SKILL_EVIDENCE_STALE")
    if data.get("placement") == "PLACED":
        binding = skill_binding(directory)
        if data.get("home") != binding["home"] or data.get("destination") != binding["destination"]:
            raise ValueError("ECC_SKILL_SCOPE_BINDING_MISMATCH")
    return data


def safe_directory(path, owned=False, writable=False):
    if not path.is_absolute() or str(path) != os.path.normpath(str(path)) or path == Path("/"):
        raise ValueError("ECC_SKILL_PATH_UNSAFE")
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    trusted_owners = {os.getuid(), os.fstat(fd).st_uid}
    try:
        for part in path.parts[1:]:
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
            ancestor = os.fstat(fd)
            if ancestor.st_uid not in trusted_owners or (ancestor.st_mode & 0o022 and not ancestor.st_mode & stat.S_ISVTX):
                raise PermissionError("ECC_SKILL_ANCESTOR_UNSAFE")
        info = os.fstat(fd)
        if owned and (info.st_uid != os.getuid() or info.st_mode & 0o022 or info.st_mode & 0o500 != 0o500):
            raise PermissionError("ECC_SKILL_DIRECTORY_OWNERSHIP_OR_MODE")
        if writable and info.st_mode & 0o200 == 0:
            raise PermissionError("ECC_SKILL_DIRECTORY_READ_ONLY")
        return fd
    except BaseException:
        os.close(fd)
        raise


def user_skill_scope(writable=False):
    value = os.environ.get("HOME")
    if not value:
        raise ValueError("ECC_SKILL_HOME_UNAVAILABLE")
    home = Path(value)
    if redact(value) != value or str(home) != value:
        raise ValueError("ECC_SKILL_HOME_UNSAFE")
    fds = []
    try:
        for path in (home, home / ".agents", home / ".agents/skills"):
            fds.append(safe_directory(path, owned=True, writable=writable))
            for parent in (path, *path.parents):
                if (parent / ".git").is_file() or (parent / ".git/HEAD").exists():
                    raise ValueError("ECC_SKILL_SCOPE_INSIDE_REPOSITORY")
        return home, fds.pop()
    finally:
        for fd in fds:
            os.close(fd)


def skill_names(directory, maximum):
    names = set()
    with os.scandir(directory) as entries:
        for entry in entries:
            names.add(entry.name)
            if len(names) > maximum:
                raise ValueError("ECC_SKILL_DIRECTORY_CONTENT_LIMIT")
    return names


def skill_bytes(directory):
    if skill_names(directory, 2) != set(SKILL_FILES):
        raise ValueError("ECC_SKILL_DESTINATION_CONTENT_CONFLICT")
    metadata = {}
    for name, expected in SKILL_FILES.items():
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory)
        with os.fdopen(fd, "rb") as handle:
            info = os.fstat(handle.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
                raise PermissionError("ECC_SKILL_FILE_OWNERSHIP_OR_MODE")
            if info.st_size > LIMIT or hashlib.sha256(handle.read(LIMIT + 1)).hexdigest() != expected:
                raise ValueError("ECC_SKILL_BYTES_CHANGED")
            metadata[name] = dict(sha256=expected, uid=info.st_uid, mode=oct(stat.S_IMODE(info.st_mode)))
    return metadata


class SkillRecorder(Recorder):
    def __init__(self, directory, commit, digest):
        self.directory = directory
        self.lines, self.child = [], None
        self.deadline = time.monotonic() + 30
        self.data = dict(schema_version=1, run_id=uuid.uuid4().hex, phase="skill-setup",
                             source_commit=commit, source_sha256=digest, upstream_source=SOURCE, upstream_sha=SHA,
                             skill_name=SKILL, expected_sha256=SKILL_SHA256, complete=False, started_at=time.time(),
                             placement="BLOCKED", safely_delivered=False, preexisting="UNVERIFIED",
                             native_discovery=UNVERIFIED, skill_invocation=UNVERIFIED, mcp=UNVERIFIED,
                             hook_trust=UNVERIFIED, hook_execution=UNVERIFIED, ecc_readiness="ECC NOT READY", events=[])


def skill_setup(state, commit, digest):
    directory = evidence_directory(state, create=True, name="ecc-skill-probe")
    try:
        binding = skill_binding(directory)
    except FileNotFoundError:
        binding = None
    binding_missing = binding is None and os.path.lexists(directory / "status.json")
    previous = None
    try:
        previous = skill_record(state)
    except (OSError, ValueError, TypeError):
        pass
    recorder = SkillRecorder(directory, commit, digest)
    if binding is not None:
        recorder.data["placement_home"] = binding["home"]
    home_value = os.environ.get("HOME", "")
    if home_value and redact(home_value) == home_value and home_value.startswith("/"):
        recorder.data.update(home=home_value, destination=str(Path(home_value) / ".agents/skills" / SKILL))
    recorder.note("skill-setup-start", "setup placement only; native discovery and invocation UNVERIFIED")

    def interrupted(signum, frame):
        raise ProbeFailure(f"ECC_SKILL_SETUP_INTERRUPTED: signal {signum}")

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    scope = target = None
    try:
        if binding_missing:
            raise ValueError("ECC_SKILL_SCOPE_BINDING_MISSING")
        native_dir = evidence_directory(state)
        native = json.loads(read_regular(native_dir / "status.json", STATUS_LIMIT, private=True))
        native_log = read_regular(native_dir / "diagnostic.log", LOG_LIMIT, private=True)
        if not isinstance(native, dict) or native.get("complete") is not True or native.get("source_commit") != commit or native.get("source_sha256") != digest or native.get("upstream_sha") != SHA or hashlib.sha256(native_log).hexdigest() != native.get("log_sha256"):
            raise ValueError("ECC_SKILL_SOURCE_EVIDENCE_UNAVAILABLE")
        source = native.get("marketplace_path")
        if not isinstance(source, str) or redact(source) != source or native.get("effective_revision") != SHA:
            raise ValueError("ECC_SKILL_PINNED_SOURCE_UNAVAILABLE")
        root = Path(source)
        recorder.data["skill_source"] = str(root / "skills" / SKILL)
        try:
            source_fd = safe_directory(root / "skills" / SKILL, owned=True)
        except FileNotFoundError as error:
            raise ValueError("ECC_SKILL_SOURCE_ABSENT") from error
        try:
            if skill_names(source_fd, 1) != {"SKILL.md"}:
                raise ValueError("ECC_SKILL_SOURCE_RESOURCES_CONFLICT")
            content = read_regular("SKILL.md", LIMIT, dir_fd=source_fd)
        finally:
            os.close(source_fd)
        root_fd = safe_directory(root, owned=True)
        try:
            license_bytes = read_regular("LICENSE", LIMIT, dir_fd=root_fd)
        finally:
            os.close(root_fd)
        actual = recorder.run("skill-source-revision", ["git", "-c", "core.fsmonitor=false", "-C", str(root), "rev-parse", "HEAD"]).strip()
        if actual != SHA:
            raise ValueError("ECC_SKILL_SOURCE_REVISION_MISMATCH")
        recorder.data["source_files"] = {"SKILL.md": hashlib.sha256(content).hexdigest(),
                                         "LICENSE": hashlib.sha256(license_bytes).hexdigest()}
        if recorder.data["source_files"] != SKILL_FILES:
            raise ValueError("ECC_SKILL_SOURCE_BYTES_MISMATCH")
        home, scope = user_skill_scope(writable=True)
        destination = home / ".agents/skills" / SKILL
        recorder.data.update(home=str(home), destination=str(destination))
        if binding is not None and binding["home"] != str(home):
            raise ValueError("ECC_SKILL_HOME_CHANGED")
        try:
            info = os.stat(SKILL, dir_fd=scope, follow_symlinks=False)
            preexisting = True
        except FileNotFoundError:
            preexisting = False
        recorder.data["preexisting"] = preexisting
        if preexisting:
            recorder.data.update(destination_uid=info.st_uid, destination_mode=oct(stat.S_IMODE(info.st_mode)))
        recorder.note("skill-path-checked", "source bytes match pin; user scope safe; destination presence recorded")
        if preexisting:
            if not previous or previous.get("placement") != "PLACED" or previous.get("safely_delivered") is not True or previous.get("destination") != str(destination) or previous.get("home") != str(home):
                raise ValueError("ECC_SKILL_DESTINATION_COLLISION")
        if binding is None:
            binding = dict(schema_version=1, upstream_sha=SHA, skill_name=SKILL, uid=os.getuid(),
                           home=str(home), destination=str(destination))
            atomic_write(directory / "scope.json", (json.dumps(binding, indent=2) + "\n").encode())
            recorder.data["placement_home"] = str(home)
            recorder.note("skill-scope-bound", "initial placement HOME retained across blocked and interrupted attempts")
        if not preexisting:
            os.mkdir(SKILL, mode=0o700, dir_fd=scope)
        target = os.open(SKILL, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=scope)
        info = os.fstat(target)
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
            raise PermissionError("ECC_SKILL_DESTINATION_OWNERSHIP_OR_MODE")
        if not preexisting:
            for name, payload in (("SKILL.md", content), ("LICENSE", license_bytes)):
                temporary = ".stage-" + uuid.uuid4().hex
                fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600, dir_fd=target)
                try:
                    with os.fdopen(fd, "wb") as handle:
                        handle.write(payload)
                        handle.flush()
                        os.fsync(handle.fileno())
                    os.link(temporary, name, src_dir_fd=target, dst_dir_fd=target, follow_symlinks=False)
                finally:
                    os.unlink(temporary, dir_fd=target)
            os.fsync(target)
        recorder.data.update(delivered_files=skill_bytes(target), destination_uid=info.st_uid,
                             destination_mode=oct(stat.S_IMODE(info.st_mode)), placement="PLACED", safely_delivered=True)
        recorder.data["complete"] = True
        recorder.note("skill-setup-complete", "ECC_SKILL_SETUP_PLACED: matching ordinary files; discovery and invocation UNVERIFIED")
        result = 0
    except (ProbeFailure, OSError, ValueError, TypeError, KeyError) as error:
        recorder.data.update(complete="ECC_SKILL_SETUP_INTERRUPTED" not in str(error), error=redact(error)[:4096])
        recorder.note("skill-setup-blocked", f"ECC_SKILL_SETUP_BLOCKED: {error}")
        result = 2
    finally:
        for fd in (target, scope):
            if fd is not None:
                os.close(fd)
    print(f"ECC skill evidence: {recorder.directory / 'status.json'}; log: {recorder.directory / 'diagnostic.log'}")
    print(f"ECC skill setup placement: {recorder.data['placement']}; {recorder.data.get('error', 'ECC_SKILL_SETUP_PLACED')}")
    print("ECC NOT READY; native discovery and real invocation UNVERIFIED")
    return result


def skill_status(state, commit, digest):
    print(f"ECC skill evidence: {state / 'ecc-skill-probe/status.json'}; log: {state / 'ecc-skill-probe/diagnostic.log'}")
    scope = target = None
    try:
        data = skill_record(state, commit, digest)
        if data.get("placement") != "PLACED" or data.get("safely_delivered") is not True:
            raise ValueError("ECC_SKILL_SETUP_BLOCKED: " + str(data.get("error", "placement unavailable")))
        if os.environ.get("HOME") != data.get("home"):
            raise ValueError("ECC_SKILL_HOME_CHANGED")
        home, scope = user_skill_scope()
        destination = home / ".agents/skills" / SKILL
        if data.get("home") != str(home) or data.get("destination") != str(destination):
            raise ValueError("ECC_SKILL_HOME_CHANGED")
        target = os.open(SKILL, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=scope)
        info = os.fstat(target)
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700 or info.st_uid != data.get("destination_uid") or oct(stat.S_IMODE(info.st_mode)) != data.get("destination_mode"):
            raise PermissionError("ECC_SKILL_DESTINATION_OWNERSHIP_OR_MODE")
        if skill_bytes(target) != data.get("delivered_files"):
            raise ValueError("ECC_SKILL_DELIVERY_EVIDENCE_MISMATCH")
        print(f"ECC_SKILL_FILES_PERSISTED: {destination / 'SKILL.md'}; sha256={SKILL_SHA256}")
        print("ECC skill setup placement: PLACED; task files: MATCH; filesystem observation only")
    except FileNotFoundError:
        print("ECC_SKILL_PLACEMENT_MISSING: retained setup evidence or delivered files absent")
    except (OSError, ValueError, TypeError) as error:
        print(f"ECC_SKILL_MEASUREMENT_BLOCKED: {redact(error)[:4096]}")
    finally:
        for fd in (target, scope):
            if fd is not None:
                os.close(fd)
    print("ECC_SKILL_NATIVE_DISCOVERY_NOT_OBSERVED: inspect provider inventory/selectors before opening SKILL.md")
    print("ECC_SKILL_INVOCATION_UNVERIFIED: exactly one provider-dispatched read-only $python-patterns action needs an invocation marker")
    print("ECC NOT READY; MCP, hook trust and execution UNVERIFIED; ordinary project work blocked")
    return 2


def main():
    mode, state, commit, digest = sys.argv[1:]
    try:
        return {"setup": setup, "status": status, "skill-setup": skill_setup,
                "skill-status": skill_status}[mode](Path(state), commit, digest)
    except (OSError, ValueError) as error:
        print(f"ECC NOT READY: unsafe or inaccessible evidence storage: {redact(error)}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
