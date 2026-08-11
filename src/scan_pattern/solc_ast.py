# 1 find right solc version
# 2 solc parses  .sol files

import json
import re
import subprocess
from pathlib import Path

from dataclasses import dataclass, field

COMPILE_TIMEOUT: int = 120

@dataclass
class SolcParsedResult:
    asts: dict[str, dict] = field(default_factory=dict)
    sources: dict[str, str] = field(default_factory=dict)


def _parse_semver(version: str):
    # Example: "compiler_version": "v0.8.19+commit.7dd6d404",
    # we get (0,8,19)
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", version or "")
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3))
    return None

def switch_solc_version(compiler_version: str):
    version = _parse_semver(compiler_version)
    
    if not version:
        return {"success": False, "errors": ["can not find compiler version"]}

    version_str = f"{version[0]}.{version[1]}.{version[2]}"
    switch_result = subprocess.run(["solc-select", "use", version_str],  capture_output=True, text=True)
    
    if switch_result.returncode != 0:
        return {"success": False, "errors": [f"solc {version_str} not installed, skipped"]}

    # switch succes
    return {"success": True, "version": version_str}

def build_standard_json(source_files, metadata):
    remappings = (metadata.get("solc_settings") or {}).get("remappings", [])
    remappings = [r for r in remappings if isinstance(r, str) and r.strip()]
    
    return {
        "language": "Solidity",
        "sources": {name: {"content": content} for name, content in source_files.items()},
        "settings": {
            "remappings": remappings, 
            "outputSelection": {"*": {"": ["ast"]}},
        },
    }

def load_asts(project_dir: Path, timeout: int = COMPILE_TIMEOUT) -> SolcParsedResult:
    project_dir = Path(project_dir)
    metadata = _load_metadata(project_dir)
    switch_result = switch_solc_version(metadata.get("compiler_version", ""))
    if not switch_result["success"]:
        return SolcParsedResult(asts={}, sources={})

    sources = {
        f.relative_to(project_dir).as_posix(): f.read_text("utf-8", errors="replace")
        for f in project_dir.rglob("*.sol")
    }

    # build standard json
    standard_json = build_standard_json(sources, metadata)

    # run solc
    try:
        process = subprocess.run(
            ["solc", "--standard-json"],
            input=json.dumps(standard_json),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return SolcParsedResult(asts={}, sources=sources)

    asts: dict[str, dict] = {}
    try:
        output = json.loads(process.stdout)
    except (json.JSONDecodeError, TypeError):
        return SolcParsedResult(asts={}, sources=sources)

    for file_path, info in output.get("sources", {}).items():
        if "ast" in info:
            asts[file_path] = info["ast"]
    
    return SolcParsedResult(asts=asts, sources=sources)


def _load_metadata(project_dir: Path) -> dict:
    try:
        return json.loads((project_dir / "metadata.json").read_text("utf-8"))
    except Exception:
        return {}

def _parse_solc_src(src: str) -> tuple[int, int] | None:
    split_tuple = (src or "").split(":")
    if len(split_tuple) < 2:
        return None
    
    try:
        return int(split_tuple[0]), int(split_tuple[1])
    except ValueError:
        return None


def find_line_in_source(solc_src: str, source: str) -> int:
    parsed_solc_src = _parse_solc_src(solc_src)
    if parsed_solc_src is None:
        return 0
    
    start,_ = parsed_solc_src
    prefix = source.encode("utf-8")[:start]
    return prefix.count(b"\n") + 1

def find_snippet_in_source(solc_src: str, source: str) -> str:
    parsed_solc_src = _parse_solc_src(solc_src)
    if parsed_solc_src is None:
        return ""
    start,len = parsed_solc_src
    raw = source.encode("utf-8")[start:start + len]
    return raw.decode("utf-8", errors="replace")

