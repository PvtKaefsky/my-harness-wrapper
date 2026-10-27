import argparse
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PIN = "d468c521f1a76e7b05d446d805f6ad2afa8ed066"


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def build(target: Path, sources: Path) -> str:
    provenance = json.loads((ROOT / "config/codex/source-inventory.json").read_text(encoding="utf-8"))
    catalog = json.loads((ROOT / "config/codex/catalog.json").read_text(encoding="utf-8"))
    if target.exists():
        raise ValueError("PACK_DESTINATION_EXISTS")
    target.mkdir(parents=True)
    records, included = {}, {}
    for item in catalog["items"]:
        sections = []
        for name in item["sources"]:
            raw = (sources / name).read_bytes()
            actual = hashlib.sha256(raw).hexdigest()
            if actual != provenance["files"][name]["sha256"]:
                raise ValueError("UPSTREAM_SOURCE_CHANGED: " + name)
            included[name] = {"sha256": actual, "status": "full-body-preserved"}
            text = raw.decode("utf-8")
            if text.startswith("---"):
                end = text.find("\n---", 3)
                if end == -1:
                    raise ValueError("UPSTREAM_METADATA_MALFORMED")
                text = text[end + 4:].lstrip("\r\n")
            sections.append(text)
        header = (
            "# " + item["title"] + "\n\nInstruction ID: " + item["id"] + ".\n\n"
            "## Codex adapter\n\nFollow the wrapper and target AGENTS.md policies first. "
            "Interpret Claude/ECC tool and agent names through the currently available native Codex tools; "
            "use the configured Windows shell when a procedure says Bash. Slash-command references "
            "identify the corresponding harness-workflow skill. Inherit the operator's model choices; "
            "Claude model names do not select a Codex model. Never fabricate unavailable tools, "
            "reviewers or completion evidence. External actions still require task authorization.\n\n"
            "## Upstream instructions\n\n")
        data = (header + "\n\n".join(sections)).encode("utf-8")
        path = target / item["path"]
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        records[item["path"]] = {"sha256": hashlib.sha256(data).hexdigest(),
                                 "upstream_paths": item["sources"]}
    license_data = (sources / "LICENSE").read_bytes()
    if hashlib.sha256(license_data).hexdigest() != provenance["files"]["LICENSE"]["sha256"]:
        raise ValueError("UPSTREAM_LICENSE_CHANGED")
    (target / "LICENSE").write_bytes(license_data)
    write_json(target / "catalog.json", catalog)
    write_json(target / "upstream.json", {
        "repository": "forever94yu/everything-codex-code", "commit": PIN,
        "adaptation": "Original bodies retained; Claude metadata replaced by native Codex registration.",
        "files": included,
    })
    (target / "CATALOG.md").write_text(
        "# Shared local workflow catalog\n\n" + "\n".join(
            "- " + item["id"] + ": " + item["title"] for item in catalog["items"]
        ) + "\n", encoding="utf-8", newline="\n")
    for name in ("LICENSE", "catalog.json", "upstream.json", "CATALOG.md"):
        records[name] = {"sha256": hashlib.sha256((target / name).read_bytes()).hexdigest()}
    write_json(target / "manifest.json", {"schema_version": 3, "upstream_commit": PIN, "files": records})
    return hashlib.sha256((target / "manifest.json").read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--upstream-checkout", type=Path)
    args = parser.parse_args()
    source = ROOT / "config/codex/upstream"
    if args.upstream_checkout:
        catalog = json.loads((ROOT / "config/codex/catalog.json").read_text(encoding="utf-8"))
        names = {"LICENSE"} | {name for item in catalog["items"] for name in item["sources"]}
        for name in sorted(names):
            data = subprocess.check_output(["git", "-C", str(args.upstream_checkout),
                                            "show", PIN + ":" + name])
            destination = source / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(data)
    anchor = build(args.output, source)
    print("LOCAL_PACK_BUILT manifest_sha256=" + anchor)


if __name__ == "__main__":
    main()
