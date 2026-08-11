import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1]))
os.chdir(HERE.parents[2])

from llm_study import config

PROMPT_STRATEGIES = ["llm_study_pure_llm", "llm_study_feedback", "llm_study_knowledge_feedback"]
DIFF_DIR = Path("logs") / "evaluate_llm" / "diff"
OUTPUT_FILE = DIFF_DIR / "diff_text_analysis.json"

def classify_line(line: str) -> str:
    stripped = line.strip()
    if stripped == "":
        return "blank"
    if stripped.startswith(("//", "/*", "*", "*/")):
        return "comment"
    return "code"


def scan_original(dataset_dir: Path) -> dict:
    counts = {"code": 0, "comment": 0, "blank": 0}
    file_count = 0
    for tier in config.TIERS:
        for sol in (dataset_dir / tier).rglob("*.sol"):
            file_count += 1
            text = sol.read_text(encoding="utf-8", errors="replace")
            for line in text.splitlines():
                counts[classify_line(line)] += 1
    total = sum(counts.values())
    return {
        "files": file_count,
        "total_lines": total,
        "code": counts["code"],
        "comment": counts["comment"],
        "blank": counts["blank"],
    }

def pct(part: int, whole: int) -> float:
    return 100.0 * part / whole if whole else 0.0

def scan_mode(mode_dir: Path) -> dict:
    added = {"code": 0, "comment": 0, "blank": 0}
    removed = {"code": 0, "comment": 0, "blank": 0}
    projects = 0
    files = 0

    for diff_file in sorted(mode_dir.glob("*/diff_text.json")):
        projects += 1
        for record in json.loads(diff_file.read_text(encoding="utf-8")):
            if "added" not in record or "removed" not in record:
                continue
            files += 1
            for line in record["added"]:
                added[classify_line(line)] += 1
            for line in record["removed"]:
                removed[classify_line(line)] += 1

    return {
        "projects": projects,
        "files": files,
        "added": added,
        "removed": removed,
    }


if __name__ == "__main__":
    dataset_dir = config.DATASET_DIR.resolve()
    original = scan_original(dataset_dir)

    summary: dict = {"original": original, "strategies": {}}
    for strategy in PROMPT_STRATEGIES :
        stats = scan_mode(DIFF_DIR / strategy)

        summary["strategies"][strategy] = {
            "projects": stats["projects"],
            "files": stats["files"],
            "removed_breakdown": {
                k: {"lines": v, "pct_of_original": round(pct(v, original[k]), 1)}
                for k, v in stats["removed"].items()
            },
            "added_breakdown": {
                k: {"lines": v, "pct_of_original": round(pct(v, original[k]), 1)}
                for k, v in stats["added"].items()
            },
        }

    OUTPUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
