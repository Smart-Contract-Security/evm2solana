import json
import subprocess
from pathlib import Path

EMPIRICAL_DATASET_PATH = Path("empirical/dataset")
RESULTS_FILE = Path("logs/empirical/solang/solang_empirical_dataset.jsonl")
SUMMARY_FILE = Path("logs/empirical/solang/solang_compile_summary.json")

def _build_import_args(metadata: dict) -> list[str]:
    args = ["-I", "."]
    remappings = (metadata.get("solc_settings") or {}).get("remappings", [])
    for raw in remappings:
        raw = raw.strip()
        if not raw or "=" not in raw:
            continue
        colon, eq = raw.find(":"), raw.find("=")
        if 0 <= colon < eq:
            raw = raw[colon + 1:]
        args += ["--importmap", raw]
    return args


def compile_project(contract_dir_path: Path) -> dict:
    address = contract_dir_path.name
    metadata_json = contract_dir_path / "metadata.json"
    cdir = str(contract_dir_path.resolve())

    result_dict: dict = {
        "address": address,
        "success": False,
        "error_count": 0,
        "errors": [],
    }
   
    try:
        metadata = json.loads(metadata_json.read_text("utf-8"))
    except Exception:
        metadata = {}

    sol_files = [str(f.relative_to(contract_dir_path)) for f in contract_dir_path.rglob("*.sol")]
    if not sol_files:
        result_dict["errors"] = ["no .sol files"]
        return result_dict

    cmd = (["solang", "compile", "--target", "solana", "--standard-json"]
           + _build_import_args(metadata)
           + sol_files)

    try:
        process = subprocess.run(cmd, capture_output=True, text=True, timeout=120, cwd=cdir)
    except FileNotFoundError:
        result_dict["errors"] = ["solang binary not found"]
        return result_dict
    except subprocess.TimeoutExpired:
        result_dict["errors"] = ["time out"]
        return result_dict

    try:
        run_output = json.loads(process.stdout)
    except (json.JSONDecodeError, TypeError):
        result_dict["errors"] = [process.stderr[:500] if process.stderr else ""]
        return result_dict

    errors: list[str] = []
    # Use message, not formattedMessage: solang includes absolute paths in the formattedMessage.
    for diagnostic in run_output.get("errors", []):
        message = diagnostic.get("message", str(diagnostic)).strip()
        if diagnostic.get("severity") == "error":
            errors.append(message)    

    result_dict["success"] = len(errors) == 0
    result_dict["error_count"] = len(errors)
    result_dict["errors"] = errors
    return result_dict


if __name__ == "__main__":
    contract_dirs = [
        d for d in EMPIRICAL_DATASET_PATH.iterdir()
        if d.is_dir() and (d / "metadata.json").exists()
    ]

    RESULTS_FILE.parent.mkdir(parents=True, exist_ok=True)
    results: list[dict] = []

    with open(RESULTS_FILE, "w", encoding="utf-8") as fout:
        for contract_dir in contract_dirs:
            result_dict = compile_project(contract_dir)
            fout.write(json.dumps(result_dict, ensure_ascii=False) + "\n")
            results.append(result_dict)
            
    total = len(results)
    success_count = sum(1 for r in results if r["success"])

    solang_version = subprocess.run(["solang", "--version"], capture_output=True, text=True).stdout.strip()
    summary = {
        "total": total,
        "success": success_count,
        "failed": total - success_count,
        "solang_version": solang_version,
    }

    with open(SUMMARY_FILE, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)
