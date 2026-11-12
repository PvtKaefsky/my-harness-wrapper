from typing import Any
import os
import shutil
import subprocess
from pathlib import Path

from .pack import decode, safe


def read(root: Path) -> list[dict[str, Any]]:
    items = decode(safe(root / "config/codex/addons.json").read_bytes())
    if not isinstance(items, list):
        raise ValueError("ADDON_LIST_INVALID")
    names = set()
    for item in items:
        if not isinstance(item, dict) or not isinstance(item.get("name"), str) or item["name"] in names:
            raise ValueError("ADDON_LIST_INVALID")
        names.add(item["name"])
        if not isinstance(item.get("source"), str) or ("plugin_id" in item) == ("skill_path" in item):
            raise ValueError("ADDON_LIST_INVALID")
        if "plugin_id" in item and not isinstance(item["plugin_id"], str):
            raise ValueError("ADDON_LIST_INVALID")
        if "skill_path" in item:
            path = item["skill_path"]
            if not isinstance(path, str) or Path(path).is_absolute() or ".." in Path(path).parts:
                raise ValueError("ADDON_LIST_INVALID")
        for operation in ["install", "update"]:
            commands = item.get(operation)
            if not isinstance(commands, list) or not commands:
                raise ValueError("ADDON_LIST_INVALID")
            for command in commands:
                if (not isinstance(command, list) or not command or command[0] not in {"codex", "npx"}
                        or not all(isinstance(argument, str) and argument and
                                   not any(character in argument for character in '\x00\r\n')
                                   for argument in command)):
                    raise ValueError("ADDON_LIST_INVALID")
    return items


def environment(profile: Path, home: Path) -> dict[str, str]:
    overrides = dict(HOME=str(profile), USERPROFILE=str(profile), CODEX_HOME=str(home))
    if profile != Path.home():
        overrides.update(APPDATA=str(profile / "AppData/Roaming"),
                         LOCALAPPDATA=str(profile / "AppData/Local"),
                         XDG_CONFIG_HOME=str(profile / ".config"),
                         XDG_CACHE_HOME=str(profile / ".cache"),
                         XDG_STATE_HOME=str(profile / ".state"),
                         npm_config_cache=str(profile / ".npm-cache"),
                         npm_config_userconfig=str(profile / ".npmrc"),
                         npm_config_globalconfig=str(profile / "global.npmrc"))
    replaced = {key.upper() for key in overrides}
    return {key: value for key, value in os.environ.items() if key.upper() not in replaced} | overrides


def execute(command: list[str], values: dict[str, str], capture: bool = False) -> subprocess.CompletedProcess[str]:
    path = values.get("PATH", "")
    if not isinstance(path, str) or "\x00" in path:
        raise ValueError("ADDON_PATH_INVALID")
    executable = None
    for entry in path.split(os.pathsep):
        directory = Path(entry)
        if directory.is_absolute():
            executable = shutil.which(str(directory / command[0]))
            if executable is not None:
                break
    if executable is None:
        raise ValueError("ADDON_EXECUTABLE_MISSING: " + command[0])
    if (os.name == "nt" and Path(executable).suffix.lower() in {".cmd", ".bat"}
            and any(character in executable for character in '%!^&|<>()\r\n"')):
        raise ValueError("ADDON_EXECUTABLE_PATH_UNSUPPORTED")
    return subprocess.run([executable, *command[1:]], env=values, cwd=values["USERPROFILE"], capture_output=capture,
                          text=True, encoding="utf-8", errors="replace")


def present(items: list[dict[str, Any]], profile: Path, home: Path) -> dict[str, bool]:
    installed = []
    if any("plugin_id" in item for item in items):
        result = execute(["codex", "plugin", "list", "--json"], environment(profile, home), capture=True)
        if result.returncode:
            raise ValueError("ADDON_LIST_COMMAND exit=" + str(result.returncode))
        try:
            data = decode(result.stdout)
        except (ValueError, TypeError) as error:
            raise ValueError("ADDON_LIST_OUTPUT_INVALID") from error
        if not isinstance(data, dict) or not isinstance(data.get("installed"), list):
            raise ValueError("ADDON_LIST_OUTPUT_INVALID")
        installed = data["installed"]
    return {item["name"]:
            any(isinstance(row, dict) and row.get("pluginId") == item["plugin_id"]
                and row.get("installed") is True for row in installed)
            if "plugin_id" in item else safe(profile / item["skill_path"]).is_file()
            for item in items}


def plan(root: Path) -> str:
    return "\n".join("ADDON_PLAN " + item["name"] + " " + operation + ": " + " ".join(command)
                     for item in read(root) for operation in ["install", "update"] for command in item[operation])


def check(root: Path, profile: Path, home: Path) -> bool:
    success = True
    for item in read(root):
        try:
            found = present([item], profile, home)[item["name"]]
        except (ValueError, OSError) as error:
            print("FAIL ADDON_CHECK " + item["name"] + " " + str(error))
            found = False
        print(("PASS ADDON_PRESENT " if found else "FAIL ADDON_MISSING ") + item["name"])
        success = success and found
    return success


def apply(root: Path, profile: Path, home: Path) -> None:
    items = read(root)
    states = present(items, profile, home)
    values = environment(profile, home)
    for item in items:
        operation = "update" if states[item["name"]] else "install"
        for command in item[operation]:
            result = execute(command, values)
            print(("PASS" if result.returncode == 0 else "FAIL") + " ADDON_COMMAND "
                  + " ".join(command) + " exit=" + str(result.returncode), flush=True)
            if result.returncode:
                raise ValueError("ADDON_INSTALL_FAILED: " + item["name"])
        if not present([item], profile, home)[item["name"]]:
            raise ValueError("ADDON_MISSING: " + item["name"])
