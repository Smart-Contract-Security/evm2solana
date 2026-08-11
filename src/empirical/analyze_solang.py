import json
from collections import Counter
from pathlib import Path
from statistics import median, mean, stdev, quantiles

RESULTS_FILE = Path("logs/empirical/solang/solang_empirical_dataset.jsonl")
ANALYSIS_FILE = Path("logs/empirical/solang/solang_compile_analysis.json")


if __name__ == "__main__":
    results = []
    with open(RESULTS_FILE, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                results.append(json.loads(line))

    total = len(results)
    success_count = sum(1 for r in results if r["success"])
    failed = [r for r in results if not r["success"]]

    # Collect all raw error messages across all failed contracts
    all_errors: list[str] = []
    for r in failed:
        all_errors.extend(r.get("errors", []))

    top_errors = Counter(all_errors).most_common(50)

    # Unique error types per failed contract: descriptive statistics
    unique_counts = sorted(len(set(r.get("errors", []))) for r in failed)
    q1, q2, q3 = quantiles(unique_counts, n=4)

    error_distribution = {
        "min": unique_counts[0],
        "Q1": q1,
        "Q2": q2,
        "Q3": q3,
        "max": unique_counts[-1],
        "mean": round(mean(unique_counts), 1),
        "stdev": round(stdev(unique_counts), 1),
    }

    report = {
        "summary": {
            "total": total,
            "success": success_count,
            "failed": len(failed),
            "total_error_messages": len(all_errors),
            "unique_error_messages": len(set(all_errors)),
        },
        "top_errors_by_occurrence": [
            {"message": msg, "count": cnt} for msg, cnt in top_errors
        ],
        "unique_errors_per_contract": error_distribution,
    }

    ANALYSIS_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(ANALYSIS_FILE, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

