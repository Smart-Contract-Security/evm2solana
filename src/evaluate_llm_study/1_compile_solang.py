import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1]))   # src/ on path -> `import llm_study`
os.chdir(HERE.parents[2])                   # repo root -> config's relative paths resolve

from llm_study import config
from llm_study.compile import solang_compile_project

PROMPT_STRATEGIES = ["llm_study_pure_llm", "llm_study_feedback", "llm_study_knowledge_feedback"]
DATASET_DIR = config.DATASET_DIR
OUTPUT_BASE = Path("logs") / "evaluate_llm" / "compile"


def compile_tier(source_root: Path, output_dir: Path, tier: str) -> None:
    tier_dir = source_root / tier
    contract_dirs = sorted(
        d for d in tier_dir.iterdir()
        if d.is_dir() and (d / "metadata.json").exists()
    ) if tier_dir.is_dir() else []
    if not contract_dirs:
        return

    output_dir.mkdir(parents=True, exist_ok=True)
    results = []
    with open(output_dir / f"compile_{tier}.jsonl", "w", encoding="utf-8") as fout:
        for contract_dir in contract_dirs:
            cr = solang_compile_project(contract_dir, config.SOLANG_BIN,
                                        config.SOLANG_TARGET, config.COMPILE_TIMEOUT)
            entry = {"address": contract_dir.name, "tier": tier, "success": cr.success,
                     "error_count": cr.error_count, "errors": cr.errors,
                     "errors_by_file": cr.errors_by_file, "infra_failed": cr.infra_failed}
            fout.write(json.dumps(entry, ensure_ascii=False) + "\n")
            results.append(entry)

    total = len(results)
    success_count = sum(1 for r in results if r["success"])
    infra_failed_count = sum(1 for r in results if r["infra_failed"])
    solang_version = subprocess.run(
        [config.SOLANG_BIN, "--version"], capture_output=True, text=True).stdout.strip()
    summary = {"tier": tier, "total": total, "success": success_count,
               "failed": total - success_count, "infra_failed": infra_failed_count,
               "solang_version": solang_version}
    (output_dir / f"compile_{tier}_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

if __name__ == "__main__":
    for tier in config.TIERS:
        compile_tier(DATASET_DIR, OUTPUT_BASE / "dataset", tier)

    for strategy in PROMPT_STRATEGIES:
        source_root = Path("results") / config.ACTIVE / strategy
        for tier in config.TIERS:
            compile_tier(source_root, OUTPUT_BASE / strategy, tier)
