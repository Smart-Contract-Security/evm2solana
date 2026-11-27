import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1]))
os.chdir(HERE.parents[2])

from scan_pattern.solc_ast import load_asts
from scan_pattern.detectors import detect_unit, hits_summary, _pid_key


DATASET_DIR = Path("empirical/dataset")
RESULT_DIR = Path("logs/empirical/scan")
RESULT_PARTS = 3
SUMMARY = RESULT_DIR / "summary.json"

if __name__ == "__main__":
    
    all_results = []

    for d in sorted(DATASET_DIR.iterdir()):
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
    class_counts: dict[str, int] = {}
    class_projects: dict[str, int] = {}
    for r in all_results:
        if r.get("ast_failed"):
            ast_failed_count += 1
        seen: set[str] = set()
        for pid, count in r.get("by_pattern", {}).items():
            pattern_counts[pid] = pattern_counts.get(pid, 0) + count
            if pid not in seen:
                contract_counts[pid] = contract_counts.get(pid, 0) + 1
                seen.add(pid)
        for cls, n in r.get("by_class", {}).items():
            class_counts[cls] = class_counts.get(cls, 0) + n
            class_projects[cls] = class_projects.get(cls, 0) + 1


    summary = {
        "total_contract_projects": len(all_results),
        "ast_failed": ast_failed_count,
        "pattern_counts": dict(sorted(pattern_counts.items(), key=lambda kv: kv[1], reverse=True)),
        "per_pattern": {
            pid: {
                "occurrences": pattern_counts[pid],
                "contract_projects": contract_counts[pid],
            }
            for pid in sorted(pattern_counts, key=_pid_key)
        },
        "per_class": {
            cls: {
                "occurrences": class_counts[cls],
                "contract_projects": class_projects[cls],
            }
            for cls in sorted(class_counts)
        },
    }

    RESULT_DIR.mkdir(parents=True, exist_ok=True)
    size = -(-len(all_results) // RESULT_PARTS)
    for i in range(RESULT_PARTS):
        part = {"per_contract_project": all_results[i * size:(i + 1) * size]}
        with open(RESULT_DIR / f"scan_patterns_{i + 1}.json", "w", encoding="utf-8") as f:
            json.dump(part, f, ensure_ascii=False, indent=2)

    with open(SUMMARY, "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)