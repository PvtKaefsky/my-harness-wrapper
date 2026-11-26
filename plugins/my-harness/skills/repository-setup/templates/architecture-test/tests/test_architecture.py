"""Architecture test: each rule in RULES forbids code under one path from importing code under another.

A rule is (source, forbidden): two directories relative to the repository root,
both under src/, neither inside the other. The test fails where either
directory is missing or the source holds no Python file, so a rule over a
renamed or deleted path cannot pass vacuously.
"""

import ast
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RULES = [
    ("src/<package>/domain", "src/<package>/adapters"),
]


def module_parts(path):
    """Return the dotted-name parts of a path under src/, without a .py suffix."""
    return list(path.relative_to(ROOT / "src").with_suffix("").parts)


def imported_names(file):
    """Yield every absolute module name a Python file imports, relative imports resolved."""
    package = module_parts(file)[:-1]
    for node in ast.walk(ast.parse(file.read_text(encoding="utf-8"), filename=str(file))):
        if isinstance(node, ast.Import):
            yield from (alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            base = package[: len(package) - node.level + 1] if node.level else []
            module = ".".join(base + ([node.module] if node.module else []))
            yield from (f"{module}.{alias.name}" for alias in node.names)


class ArchitectureTest(unittest.TestCase):
    def test_rules(self):
        for source, forbidden in RULES:
            for path in (source, forbidden):
                self.assertTrue((ROOT / path).is_dir(), f"{path} named by a rule does not exist")
            target = ".".join(module_parts(ROOT / forbidden))
            files = list((ROOT / source).rglob("*.py"))
            self.assertTrue(files, f"{source} named by a rule holds no Python file")
            for file in files:
                for name in imported_names(file):
                    self.assertFalse(
                        name == target or name.startswith(target + "."),
                        f"{file.relative_to(ROOT)} imports {name}, which the rule ({source}, {forbidden}) forbids",
                    )
