import json
import re
import subprocess
from pathlib import Path

SYNTHESIZED_DATASET_PATH = Path("synthesized_dataset")
RESULTS_FILE = Path("logs/synthesized_dataset/solc_synthesized.jsonl")
SUMMARY_FILE = Path("logs/synthesized_dataset/solc_synthesized_summary.json")

# 01_address_length.sol -> "1"; 11a_error_definitions.sol -> "11a"
_PATTERN_RE = re.compile(r"^(\d+)([ab])?_")


def pattern_label(filename: str) -> str:
    m = _PATTERN_RE.match(filename)
    if not m:
        return filename
    return str(int(m.group(1))) + (m.group(2) or "")


def build_standard_json(name: str, content: str) -> dict:
    # Request abi for all contracts to force full analysis; we only read errors.
    return {
        "language": "Solidity",
        "sources": {name: {"content": content}},
        "settings": {"outputSelection": {"*": {"*": ["abi"]}}},
    }


def compile_one(sol_file: Path) -> dict:
    name = sol_file.name
    result: dict = {
        "file": name,
        "pattern": pattern_label(name),
        "success": False,
        "errors": [],
    }

    standard_json = build_standard_json(name, sol_file.read_text("utf-8"))
    try:
        process = subprocess.run(
            ["solc", "--standard-json"],
            input=json.dumps(standard_json),
            capture_output=True,
            text=True,
            timeout=60,
        )
    except FileNotFoundError:
        result["errors"] = ["solc binary not found"]
        return result
    except subprocess.TimeoutExpired:
        result["errors"] = ["time out"]
        return result

    try:
        run_output = json.loads(process.stdout)
    except json.JSONDecodeError:
        result["errors"] = [process.stderr[:500] if process.stderr else ""]
        return result

    errors = [
        diagnostic.get("message", str(diagnostic)).strip()
        for diagnostic in run_output.get("errors", [])
        if diagnostic.get("severity") == "error"
    ]
    result["success"] = len(errors) == 0
    result["errors"] = errors
    return result


if __name__ == "__main__":
    sol_files = sorted(SYNTHESIZED_DATASET_PATH.glob("*.sol"))
    RESULTS_FILE.parent.mkdir(parents=True, exist_ok=True)

    results: list[dict] = []
    with open(RESULTS_FILE, "w", encoding="utf-8") as fout:
        for sol_file in sol_files:
            result_dict = compile_one(sol_file)
            fout.write(json.dumps(result_dict, ensure_ascii=False) + "\n")
            results.append(result_dict)

    total = len(results)
    success = sum(1 for r in results if r["success"])
    solc_version = subprocess.run(
        ["solc", "--version"], capture_output=True, text=True
    ).stdout.strip().splitlines()[-1]

    summary = {
        "total": total,
        "success": success,
        "failed": total - success,
        "failed_files": [r["file"] for r in results if not r["success"]],
        "solc_version": solc_version,
    }
    with open(SUMMARY_FILE, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
