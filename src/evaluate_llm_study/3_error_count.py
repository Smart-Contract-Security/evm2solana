import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1]))
os.chdir(HERE.parents[2])

from llm_study import config

PROMPT_STRATEGIES = ["llm_study_pure_llm", "llm_study_feedback", "llm_study_knowledge_feedback"]
CASES = ["dataset"] + PROMPT_STRATEGIES
COMPILE_DIR = Path("logs") / "evaluate_llm" / "compile"
OUTPUT_FILE = Path("logs") / "evaluate_llm" / "error_count" / "error_count.json"

def load_tier(case: str, tier: str) -> list[dict]:
    path = COMPILE_DIR / case / f"compile_{tier}.jsonl"
    records = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.strip():
            records.append(json.loads(line))
    return records

def scan_tier(records: list[dict]) -> dict:
    success = 0
    infra_failed = 0
    failed = 0
    total_errors = 0
    unique_errors: set[str] = set()

    for r in records:
        if r["success"]:
            success += 1
        elif r.get("infra_failed", False):
            infra_failed += 1
        else:
            failed += 1
            errors = r.get("errors", [])
            total_errors += len(errors)
            unique_errors.update(errors)

    return {
        "total": len(records),
        "success": success,
        "infra_failed": infra_failed,
        "failed": failed,
        "total_errors": total_errors,
        "unique_errors": len(unique_errors),
        "_unique_set": unique_errors,
    }  

if __name__ == "__main__":
    summary: dict = {"cases": {}}

    for case in CASES:
        per_tier = {}
        total = {"total": 0, "success": 0, "infra_failed": 0, "failed": 0, "total_errors": 0}
        all_unique: set[str] = set()

        for tier in config.TIERS:
            scan_dict = scan_tier(load_tier(case, tier))
            all_unique.update(scan_dict.pop("_unique_set"))
            per_tier[tier] = scan_dict
            for key in total:
                total[key] += scan_dict[key]

        total["unique_errors"] = len(all_unique)
        summary["cases"][case] = {"overall": total, "per_tier": per_tier}

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
