import json
from pathlib import Path

EMPIRICAL_DATASET_MANIFEST = Path("empirical/dataset/manifest.jsonl")
SOLANG_COMPILE_LOGS = Path("logs/empirical/solang/solang_empirical_dataset.jsonl")
CANDIDATE_POOL = Path("logs/build_dataset/candidate_pool.jsonl")
FILTER_REPORT = Path("logs/build_dataset/filter_report.json")


if __name__ == "__main__":
    dataset = [json.loads(line) for line in open(EMPIRICAL_DATASET_MANIFEST, encoding="utf-8") if line.strip()]

    solang_success = []
    solang_success_set = set()
    with open(SOLANG_COMPILE_LOGS, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                record = json.loads(line)
                if record["success"]:
                    solang_success.append(record["address"])
                    solang_success_set.add(record["address"].lower())

    candidate_pool = [item for item in dataset if item["address"].lower() not in solang_success_set]

    CANDIDATE_POOL.parent.mkdir(parents=True, exist_ok=True)
    with open(CANDIDATE_POOL, "w", encoding="utf-8") as f:
        for item in candidate_pool:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")

    filter_report = {
        "total_original": len(dataset),
        "excluded_solang_success": {
            "count": len(solang_success),
            "reason": "solang compiled successfully, no porting needed",
            "addresses": solang_success,
        },
        "candidate_pool_count": len(candidate_pool),
    }
    with open(FILTER_REPORT, "w", encoding="utf-8") as f:
        json.dump(filter_report, f, ensure_ascii=False, indent=2)
