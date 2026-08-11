import difflib
import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1]))
os.chdir(HERE.parents[2])

from llm_study import config

PROMPT_STRATEGIES = ["llm_study_pure_llm", "llm_study_feedback", "llm_study_knowledge_feedback"]

def diff_file(original_file: Path, ported_file: Path) -> dict:
    original_lines = original_file.read_text(encoding="utf-8", errors="replace").splitlines()
    ported_lines = ported_file.read_text(encoding="utf-8", errors="replace").splitlines()

    removed: list[str] = []
    added: list[str] = []

    for line in difflib.unified_diff(original_lines, ported_lines, lineterm=""):
        if line.startswith("+++") or line.startswith("---") or line.startswith("@@"):
            continue
        if line.startswith("+"):
            added.append(line[1:])
        elif line.startswith("-"):
            removed.append(line[1:])
    
    return {
        "original_lines": len(original_lines),
        "ported_lines": len(ported_lines),
        "added": added,
        "removed": removed,
    }


def diff_project(original_dir: Path, ported_dir: Path, output_file: Path) -> None:
    records: list[dict] = []

    for original_file in sorted(original_dir.rglob("*.sol")):
        relative_path = original_file.relative_to(original_dir)
        ported_file = ported_dir / relative_path

        if not ported_file.exists():
            records.append({"file": relative_path.as_posix(), "error": "missing_ported"})
            continue
        
        diff_dict = diff_file(original_file, ported_file)
        records.append({
            "file": relative_path.as_posix(),
            "original_lines": diff_dict["original_lines"],
            "ported_lines": diff_dict["ported_lines"],
            "added": diff_dict["added"],
            "removed": diff_dict["removed"],
        })

    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")

if __name__ == "__main__":
    original_dir = config.DATASET_DIR.resolve()

    for strategy in PROMPT_STRATEGIES:
        ported_dir = Path("results") / config.ACTIVE / strategy

        if not ported_dir.is_dir():
            continue

        for tier in config.TIERS:
            ported_tier = ported_dir / tier
            if not ported_tier.is_dir():
                continue
            for ported_project in sorted(ported_tier.iterdir()):
                if not ported_project.is_dir():
                    continue
                address = ported_project.name
                original_project = original_dir / tier / address

                output_file = Path("logs") / "evaluate_llm" / "diff" / strategy / address / "diff_text.json"
                diff_project(original_project, ported_project, output_file)
            