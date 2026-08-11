import shutil
import json, re, subprocess
import sys
from pathlib import Path

EMPIRICAL_DATASET_PATH = Path("empirical/dataset/")
RESULTS_FILE = Path("logs/empirical/preprocess/solc_empirical_dataset.jsonl")
MANIFEST = Path("empirical/dataset/manifest.jsonl")

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

def collect_source_files(contract_dir_path: Path) -> dict[str, str]:
    source_files: dict[str, str] = {}
    for file in contract_dir_path.rglob("*.sol"):
        relative_posix_path = file.relative_to(contract_dir_path).as_posix()
        try:
            source_files[relative_posix_path] = file.read_text(encoding="utf-8")
        except Exception:
            continue
    return source_files

def build_standard_json(source_files, settings):
    settings = dict(settings) if settings else {}
    settings.setdefault("outputSelection", {"*": {"*": ["abi"]}})
    return {
        "language": "Solidity",
        "sources": {name: {"content": content} for name, content in source_files.items()},
        "settings": settings,
    }

def compile_project(contract_dir_path: Path, timeout: int) -> dict:
    address = contract_dir_path.name
    metadata_json = contract_dir_path / "metadata.json"

    result_dict: dict = {
        "address": address,
        "success": False,
        "error_count": 0,
        "errors": [],
        "compiler_version": "",
        "solc_used": "",
    }

    if not metadata_json.exists():
        result_dict["errors"] = ["metadata.json missing"]
        return result_dict

    try:
        metadata = json.loads(metadata_json.read_text("utf-8"))
    except Exception as e:
        result_dict["errors"] = [f"metadata.json: {e}"]
        return result_dict
    
    compiler_version = metadata.get("compiler_version", "")
    result_dict["compiler_version"] = compiler_version

    switch_result = switch_solc_version(compiler_version)
    if not switch_result["success"]:
        result_dict["errors"] = switch_result["errors"]
        return result_dict

    result_dict["solc_used"] = switch_result["version"]

    source_files = collect_source_files(contract_dir_path)
    if not source_files:
        result_dict["errors"] = ["no solidity source files"]
        return result_dict

    standard_json = build_standard_json(source_files, metadata.get("solc_settings"))
    try:
        process = subprocess.run(
            ["solc", "--standard-json"], 
            input = json.dumps(standard_json),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except FileNotFoundError:
        result_dict["errors"] = [f"solc binary not found"]
        return result_dict
    except subprocess.TimeoutExpired:
        result_dict["errors"] = ["time out"]
        return result_dict

    try:
        run_output = json.loads(process.stdout)
    except json.JSONDecodeError:
        result_dict["errors"] = [process.stderr[:500] if process.stderr else ""]
        return result_dict

    errors: list[str] = []

    for diagnostic in run_output.get("errors", []):
        message = diagnostic.get("formattedMessage", diagnostic.get("message", str(diagnostic))).strip()
        if diagnostic.get("severity") == "error":
            errors.append(message)

    result_dict["success"] = len(errors) == 0
    result_dict["error_count"] = len(errors)
    result_dict["errors"] = errors

    return result_dict

if __name__ == "__main__":
    
    dry_run = "--dry-run" in sys.argv

    contract_dirs = [
        d for d in EMPIRICAL_DATASET_PATH.iterdir()
        if d.is_dir() and (d / "metadata.json").exists()
    ]

    RESULTS_FILE.parent.mkdir(parents=True, exist_ok=True)
    results: list[dict] = []

    with open(RESULTS_FILE, "w", encoding="utf-8") as fout:
        for contract_dir in contract_dirs:
            result_dict = compile_project(contract_dir, timeout=120)
            fout.write(json.dumps(result_dict, ensure_ascii=False) + "\n")
            results.append(result_dict)


    total = len(results)
    success_count = sum(1 for r in results if r["success"])
    failed_count = total - success_count

    if dry_run:
        pass
    else:
        kept = {r["address"] for r in results if r["success"]}

        # delete compile not success contract
        for r in results:
            if not r["success"]:
                contract_dir = EMPIRICAL_DATASET_PATH / r["address"]
                if contract_dir.exists():
                    shutil.rmtree(contract_dir)

        # Rewrite manifest
        manifest_lines = [
            line for line in MANIFEST.read_text(encoding="utf-8").splitlines()
            if line.strip() and json.loads(line).get("address") in kept
        ]
        MANIFEST.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")

    summary =  {
        "total": total,
        "success": success_count,
        "failed": failed_count,
        "dry_run": dry_run,
        "failed_addresses": [r["address"] for r in results if not r["success"]],
    }
    SUMMARY_FILE = RESULTS_FILE.parent / "solc_compile_summary.json"
    with open(SUMMARY_FILE, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)    