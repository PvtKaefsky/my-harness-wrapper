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


def read_regular(path, limit, private=False):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
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


def evidence_directory(state, create=False):
    for parent in [state, *state.parents]:
        metadata = parent / ".git"
        if metadata.is_file() or (metadata / "HEAD").exists():
            raise ValueError("evidence must be outside every source repository")
    directory = state / "ecc-setup"
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


def main():
    mode, state, commit, digest = sys.argv[1:]
    try:
        return (setup if mode == "setup" else status)(Path(state), commit, digest)
    except (OSError, ValueError) as error:
        print(f"ECC NOT READY: unsafe or inaccessible evidence storage: {redact(error)}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
