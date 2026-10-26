import importlib.abc
import importlib.machinery
import importlib.util
import subprocess
import sys
from pathlib import Path
from types import CodeType, ModuleType

package = Path(__file__).resolve().parent / "harness_local"


class SourceOnlyLoader(importlib.machinery.SourceFileLoader):
    def get_code(self, fullname: str) -> CodeType:
        return compile(self.get_data(self.path), self.path, "exec", dont_inherit=True)


class HarnessFinder(importlib.abc.MetaPathFinder):
    def find_spec(self, fullname: str, path: object = None,
                  target: ModuleType | None = None) -> importlib.machinery.ModuleSpec | None:
        if fullname != "harness_local" and not fullname.startswith("harness_local."):
            return None
        location = package.joinpath(*fullname.split(".")[1:])
        is_package = location.is_dir()
        source = location / "__init__.py" if is_package else location.with_suffix(".py")
        if not source.is_file():
            raise ModuleNotFoundError("HARNESS_SOURCE_MODULE_MISSING: " + fullname)
        return importlib.util.spec_from_file_location(
            fullname, source, loader=SourceOnlyLoader(fullname, str(source)),
            submodule_search_locations=[str(location)] if is_package else None)


finder = HarnessFinder()
sys.meta_path.insert(0, finder)
spec = finder.find_spec("harness_local")
module = importlib.util.module_from_spec(spec)
sys.modules["harness_local"] = module
spec.loader.exec_module(module)
from harness_local.cli import main

if __name__ == "__main__":
    try:
        main(Path(__file__).resolve().parent.parent)
    except (ValueError, KeyError, TypeError, AttributeError, OSError, subprocess.CalledProcessError) as error:
        print("FAIL " + str(error), file=sys.stderr)
        sys.exit(1)
