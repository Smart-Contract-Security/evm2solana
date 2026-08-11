import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1]))
os.chdir(HERE.parents[2])

from scan_pattern.solc_ast import load_asts
from scan_pattern.detectors import detect_unit, hits_summary


DATASET_DIR = Path("empirical/dataset")
RESULT_FILE = Path("logs/empirical/scan/scan_patterns.json")
SUMMARY =  Path("logs/empirical/scan/summary.json")

if __name__ == "__main__":
    
    all_results = []

    for d in DATASET_DIR.iterdir():
        if (d / "metadata.json").exists():
            
            try:
                parsed = load_asts(d)
                hits = detect_unit(parsed)
                summary = hits_summary(d.name, hits, ast_failed=(not parsed.asts))
            except Exception as e:
                summary = {"address": d.name, "error": str(e), "total": 0}

            all_results.append(summary)

    pattern_counts: dict[str, int] = {}
    contract_counts: dict[str, int] = {}
    ast_failed_count = 0
    for r in all_results:
        if r.get("ast_failed"):
            ast_failed_count += 1
        seen: set[str] = set()
        for pid, count in r.get("by_pattern", {}).items():
            pattern_counts[pid] = pattern_counts.get(pid, 0) + count
            if pid not in seen:
                contract_counts[pid] = contract_counts.get(pid, 0) + 1
                seen.add(pid)

    output = {
        "per_contract_project": all_results,
    }

    summary = {
        "total_contract_projects": len(all_results),
        "ast_failed": ast_failed_count,
        "pattern_counts": dict(sorted(pattern_counts.items(), key=lambda kv: kv[1], reverse=True)),
        "per_pattern": {
            pid: {
                "occurrences": pattern_counts[pid],
                "contract_projects": contract_counts[pid],
            }
            for pid in sorted(pattern_counts, key=int)
        },
    }

    RESULT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(RESULT_FILE, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    with open(SUMMARY, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)