import json
import sys
import shutil
from pathlib import Path

DATASET_DIR = Path("empirical/dataset")
MANIFEST = Path("empirical/dataset/manifest.jsonl")
LOG_PATH = Path("logs/empirical/preprocess/dedup_report.json")

def dedup(dry_run: bool = False) -> None:
    lines = MANIFEST.read_text(encoding="utf-8").splitlines()

    sha_groups: dict[str, list[dict]] = {}
    total_records = 0

    for line in lines:
        if not line.strip():
            continue
        record = json.loads(line)
        total_records += 1
        sha = record.get("source_sha256", "")
        sha_groups.setdefault(sha, []).append(record)

    duplicates = {sha: items for sha, items in sha_groups.items() if len(items) > 1}
    to_delete = sum(len(v) - 1 for v in duplicates.values())

    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    all_groups = []

    for sha, items in duplicates.items():
        group = {
            "source_sha256": sha,
            "count": len(items),
            "kept": items[0]["address"],
            "deleted": [item["address"] for item in items[1:]],
        }
        all_groups.append(group)

    output = {
        "summary": {
            "total_records": total_records,
            "unique_contracts": len(sha_groups),
            "duplicate_groups": len(duplicates),
            "to_delete": to_delete,
            "after_dedup": total_records - to_delete,
            "dry_run": dry_run,
        },
        "groups": all_groups,
    }

    with open(LOG_PATH, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)

    if dry_run:
        return

    kept_addresses: set[str] = {items[0]["address"] for items in sha_groups.values()}
    # delete duplicate contract directories
    for group in all_groups:
        for addr in group["deleted"]:
            contract_dir = DATASET_DIR / addr
            if contract_dir.exists():
                shutil.rmtree(contract_dir)

    # Rewrite manifest with only kept records
    kept_lines = [
        line for line in lines
        if line.strip() and json.loads(line).get("address") in kept_addresses
    ]
    MANIFEST.write_text("\n".join(kept_lines) + "\n", encoding="utf-8")
    
if __name__ == "__main__":
    dry_run = "--dry-run" in sys.argv
    dedup(dry_run)

