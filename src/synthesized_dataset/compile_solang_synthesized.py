import json
import re
import subprocess
from pathlib import Path

SYNTHESIZED_DATASET_PATH = Path("synthesized_dataset")
RESULTS_FILE = Path("logs/synthesized_dataset/solang_synthesized.jsonl")
SUMMARY_FILE = Path("logs/synthesized_dataset/solang_synthesized_summary.json")

# 01_address_length.sol -> "1"; 30b_abi_selector.sol -> "30b"
_PATTERN_RE = re.compile(r"^(\d+)([ab])?_")


def pattern_label(filename: str) -> str:
    m = _PATTERN_RE.match(filename)
    if not m:
        return filename
    return str(int(m.group(1))) + (m.group(2) or "")


def compile_one(sol_file: Path) -> dict:
    name = sol_file.name
    result: dict = {
        "file": name,
        "pattern": pattern_label(name),
        "visibility": "rejected",
        "errors": [],
    }

    cmd = ["solang", "compile", "--target", "solana", "--standard-json", str(sol_file)]
    try:
        process = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except FileNotFoundError:
        result["errors"] = ["solang binary not found"]
        return result
    except subprocess.TimeoutExpired:
        result["errors"] = ["time out"]
        return result

    try:
        run_output = json.loads(process.stdout)
    except (json.JSONDecodeError, TypeError):
        result["errors"] = [process.stderr[:500] if process.stderr else ""]
        return result

    # Use message, not formattedMessage: solang puts absolute paths in formattedMessage.
    errors = [
        diagnostic.get("message", str(diagnostic)).strip()
        for diagnostic in run_output.get("errors", [])
        if diagnostic.get("severity") == "error"
    ]
    result["visibility"] = "rejected" if errors else "silently_accepted"
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
    silent = [r["pattern"] for r in results if r["visibility"] == "silently_accepted"]
    rejected = [r["pattern"] for r in results if r["visibility"] == "rejected"]
    solang_version = subprocess.run(
        ["solang", "--version"], capture_output=True, text=True
    ).stdout.strip()

    summary = {
        "total": total,
        "silently_accepted": len(silent),
        "rejected": len(rejected),
        "silently_accepted_patterns": silent,
        "rejected_patterns": rejected,
        "solang_version": solang_version,
    }
    with open(SUMMARY_FILE, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
