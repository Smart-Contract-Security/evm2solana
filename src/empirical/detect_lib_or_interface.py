import json
import re
import sys
import shutil
from pathlib import Path

DATASET_DIR = Path("empirical/dataset")
MANIFEST = DATASET_DIR / "manifest.jsonl"
REPORT_FILE = Path("logs/empirical/preprocess/lib_interface_report.json")

RE_DECL = re.compile(r'\b(?:abstract\s+)?(?P<kind>contract|library|interface)\s+\w+')


def _strip_comments(source: str) -> str:
    source = re.sub(r'/\*.*?\*/', '', source, flags=re.DOTALL)
    source = re.sub(r'//[^\n]*', '', source)
    return source


def is_pure_lib_or_interface(contract_dir: Path) -> bool:
    kinds: set[str] = set()
    for sol in contract_dir.rglob("*.sol"):
        try:
            text = _strip_comments(sol.read_text(encoding="utf-8"))
        except Exception:
            continue
        kinds |= {m.group("kind") for m in RE_DECL.finditer(text)}
    return bool(kinds) and "contract" not in kinds


if __name__ == "__main__":
    dry_run = "--dry-run" in sys.argv

    dirs = [d for d in DATASET_DIR.iterdir()
            if d.is_dir() and (d / "metadata.json").exists()]

    to_delete = [d.name for d in dirs if is_pure_lib_or_interface(d)]
    to_delete_set = set(to_delete)

    report = {
        "total": len(dirs),
        "pure_lib_or_interface": len(to_delete),
        "remaining": len(dirs) - len(to_delete),
        "dry_run": dry_run,
        "deleted_addresses": to_delete,
    }

    REPORT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(REPORT_FILE, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    if not dry_run:
        for addr in to_delete:
            contract_dir = DATASET_DIR / addr
            if contract_dir.exists():
                shutil.rmtree(contract_dir)

        kept_lines = [
            line for line in MANIFEST.read_text(encoding="utf-8").splitlines()
            if line.strip() and json.loads(line).get("address") not in to_delete_set
        ]
        MANIFEST.write_text("\n".join(kept_lines) + "\n", encoding="utf-8")
