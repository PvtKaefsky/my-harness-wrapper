"""HYP-1: example hypothesis task; replace it with the code of the hypothesis this directory tests."""

import json
from pathlib import Path


def run(seed: int, data_dir: str, run_dir: str) -> None:
    """Write metrics.json holding the seed and data_dir to run_dir."""
    metrics = {"seed": seed, "data_dir": data_dir}
    Path(run_dir, "metrics.json").write_text(json.dumps(metrics) + "\n", encoding="utf-8")
