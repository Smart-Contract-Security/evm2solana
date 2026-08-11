
import json
from collections import Counter
from pathlib import Path

INPUT_DIR = Path("logs/evaluate_llm/compile/llm_study_knowledge_feedback")
TIERS = ["L1", "L2", "L3", "L4"]
OUTPUT_FILE = Path("logs/evaluate_llm/4_analyze_compile_failures/compile_failures_analysis.json")


def load_tier(tier: str) -> list[dict]:
    path = INPUT_DIR / f"compile_{tier}.jsonl"
    records = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    return records


if __name__ == "__main__":
    tier_summary = {}
    tier_top_errors: dict[str, list] = {}
    all_failed: list[dict] = []
    all_errors: list[str] = []

    for tier in TIERS:
        records = load_tier(tier)
        total = len(records)
        success = sum(1 for r in records if r["success"])
        infra = sum(1 for r in records if r.get("infra_failed", False))
        failed = [r for r in records if not r["success"] and not r.get("infra_failed", False)]

        tier_summary[tier] = {
            "total": total,
            "success": success,
            "failed": len(failed),
            "infra_failed": infra,
        }

        tier_errors: list[str] = []
        for r in failed:
            errs = r.get("errors", [])
            tier_errors.extend(errs)
            all_errors.extend(errs)
        all_failed.extend(failed)

        tier_top_errors[tier] = [
            {"message": msg, "count": cnt}
            for msg, cnt in Counter(tier_errors).most_common(50)
        ]

    report = {
        "summary": {
            "total_projects": sum(tier_summary[t]["total"] for t in TIERS),
            "total_success": sum(tier_summary[t]["success"] for t in TIERS),
            "total_failed": len(all_failed),
            "total_infra_failed": sum(tier_summary[t]["infra_failed"] for t in TIERS),
            "total_error_messages": len(all_errors),
            "unique_error_messages": len(set(all_errors)),
        },
        "tier_summary": tier_summary,
        "top_errors_by_occurrence": [
            {"message": msg, "count": cnt}
            for msg, cnt in Counter(all_errors).most_common(50)
        ],
        "top_errors_by_tier": tier_top_errors,
    }

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
