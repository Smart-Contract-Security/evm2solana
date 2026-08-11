import json
import random
from pathlib import Path
from collections import defaultdict

CANDIDATE_POOL = Path("logs/build_dataset/candidate_pool.jsonl")
SOLANG_COMPILE_LOGS = Path("logs/empirical/solang/solang_empirical_dataset.jsonl")
SOLANG_ANALYSIS = Path("logs/empirical/solang/solang_compile_analysis.json")
RESULT_FILE = Path("logs/build_dataset/sample.json")

def classify(error_count: int, q1: int, q2: int, q3: int) -> str:
    if error_count <= q1:
        return "L1"
    elif error_count <= q2:
        return "L2"
    elif error_count <= q3:
        return "L3"
    
    return "L4"

if __name__ == "__main__":

    # read pool
    candidate_pool_list = []
    with open(CANDIDATE_POOL,  encoding="utf-8") as f:
        for line in f:
            if line.strip():
                candidate_pool_list.append(json.loads(line))

    # read solang compile
    solang_compile_list = []
    with open(SOLANG_COMPILE_LOGS,  encoding="utf-8") as f:
        for line in f:
            if line.strip():
                solang_compile_list.append(json.loads(line))
            
    error_massage_map = {}
    for item in solang_compile_list:
        address = item["address"].lower()
        error_massage_map[address] = len(set(item.get("errors", [])))

    for item in candidate_pool_list:
        item["error_types"] = error_massage_map[item["address"].lower()]

    # read stratification boundaries from RQ2 analysis
    with open(SOLANG_ANALYSIS, encoding="utf-8") as f:
        analysis = json.load(f)
    quartiles = analysis["unique_errors_per_contract"]
    q1, q2, q3 = int(quartiles["Q1"]), int(quartiles["Q2"]), int(quartiles["Q3"])

    # classify
    buckets = defaultdict(list)
    for item in candidate_pool_list:
        tier = classify(item["error_types"], q1, q2, q3)
        buckets[tier].append(item)

    # random
    seed = random.randint(0, 2 ** 32 - 1)
    random.seed(seed)
    per_tier = 25

    sample_list = []
    layer = ["L1", "L2", "L3", "L4"]
    for tier in layer:
        pool = sorted(buckets[tier], key=lambda x: x["address"])
        for item in random.sample(pool, per_tier):
            sample_list.append({
                "address": item["address"],
                "contract_name": item["contract_name"],
                "tier": tier,
                "error_types": item["error_types"],
                "file_count": item["file_count"],
            })

    sample_result = {
        "seed": seed,
        "layer": {
            "L1": f"[1,{q1}]",
            "L2": f"({q1},{q2}]",
            "L3": f"({q2},{q3}]",
            "L4": f"({q3},+)",
        },
        "per_tier": per_tier,
        "total_contract": len(sample_list),
        "sample_list": sample_list,
    }

    RESULT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(RESULT_FILE, "w", encoding="utf-8") as f:
        json.dump(sample_result, f, ensure_ascii=False, indent=2)