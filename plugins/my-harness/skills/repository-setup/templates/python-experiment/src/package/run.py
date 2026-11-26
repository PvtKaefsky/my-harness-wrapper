"""Run one experiment: compose its configuration, call its task, and record the run under runs/."""

import json
import platform
import re
import signal
import subprocess
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path
from types import FrameType
from typing import Any, NoReturn

from dotenv import load_dotenv
from hydra import compose, initialize_config_dir
from hydra.utils import call
from omegaconf import DictConfig, OmegaConf

SECRET = re.compile(r"(^|[_-])(secrets?|passwords?|passwd|token|key|apikey|credentials?|auth)([_-]|$)", re.IGNORECASE)
CAMEL = re.compile(r"(?<=[a-z0-9])(?=[A-Z])")


def redact(value: Any) -> Any:
    """Return a copy of a plain config value with every secret key's value set to '***'.

    A key is secret when SECRET matches it after CAMEL splits its camelCase words with "_".
    """
    if isinstance(value, dict):
        return {k: "***" if SECRET.search(CAMEL.sub("_", str(k))) else redact(v) for k, v in value.items()}
    if isinstance(value, list):
        return [redact(v) for v in value]
    return value


def git(*args: str) -> str:
    """Return the stripped output of a git command run in the current directory; raise if it fails."""
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout.strip()


def run(cfg: DictConfig) -> Path:
    """Call cfg.task with run_dir set to a new directory under runs/ and return that directory.

    The directory holds config.yaml, the resolved configuration with secrets redacted, and
    metadata.json with run_id, experiment, commit, dirty, seed, environment and status.
    Status is interrupted on KeyboardInterrupt, failed when the task raises anything else, or completed;
    the exception is re-raised.
    """
    commit, dirty = git("rev-parse", "HEAD"), git("status", "--porcelain") != ""
    run_id = f"{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{uuid.uuid4().hex[:8]}"
    config = OmegaConf.to_container(cfg, resolve=True)
    run_dir = Path("runs") / run_id
    run_dir.mkdir(parents=True)
    (run_dir / "config.yaml").write_text(OmegaConf.to_yaml(redact(config)), encoding="utf-8")
    metadata = {
        "run_id": run_id,
        "experiment": config.get("experiment"),
        "commit": commit,
        "dirty": dirty,
        "seed": config.get("seed"),
        "environment": {"python": platform.python_version(), "platform": platform.platform()},
        "status": "running",
    }
    try:
        call(cfg.task, run_dir=str(run_dir))
        metadata["status"] = "completed"
    except KeyboardInterrupt:
        metadata["status"] = "interrupted"
        raise
    except BaseException:
        metadata["status"] = "failed"
        raise
    finally:
        (run_dir / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    return run_dir


def interrupt(signum: int, frame: FrameType | None) -> NoReturn:
    """Raise KeyboardInterrupt, so SIGTERM ends a run as interrupted."""
    raise KeyboardInterrupt


def main(argv: list[str] | None = None) -> None:
    """Load .env, compose conf/config.yaml, merge the experiment override file named in argv, and run it."""
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        raise SystemExit("usage: python -m <package>.run research/HYP-<n>-<slug>/experiments/<name>.yaml")
    load_dotenv(".env")
    signal.signal(signal.SIGTERM, interrupt)
    with initialize_config_dir(config_dir=str(Path("conf").resolve()), version_base=None):
        cfg = compose("config")
    OmegaConf.set_struct(cfg, False)
    cfg = OmegaConf.merge(cfg, OmegaConf.load(args[0]), {"experiment": args[0]})
    run(cfg)


if __name__ == "__main__":
    main()
