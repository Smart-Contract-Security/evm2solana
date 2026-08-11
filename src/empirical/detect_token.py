import json
import re
from pathlib import Path

EMPIRICAL_DATASET_DIR = Path("empirical/dataset")
RESULT_FILE = Path("logs/empirical/token/token.json")

_TOKEN_PROTOCOLS = {
    "ERC20":   re.compile(r"\bI?ERC20\w*\b"),
    "ERC721":  re.compile(r"\bI?ERC721\w*\b"),
    "ERC1155": re.compile(r"\bI?ERC1155\w*\b"),
}

def _strip_comments(source: str) -> str:
    source = re.sub(r'/\*.*?\*/', '', source, flags=re.DOTALL)
    source = re.sub(r'//[^\n]*', '', source)
    return source

def detect_token(contract_dir: Path) -> set[str]:
    found: set[str] = set()
    for sol in contract_dir.rglob("*.sol"):
        try:
            text = _strip_comments(sol.read_text(encoding="utf-8"))
        except Exception:
            continue
        for name, pat in _TOKEN_PROTOCOLS.items():
            if pat.search(text):
                found.add(name)
    return found

if __name__ == "__main__":
    contract_dirs = [
        d for d in EMPIRICAL_DATASET_DIR.iterdir()
        if d.is_dir() and (d / "metadata.json").exists()
    ]

    results: dict[str, list[str]] = {}

    for d in contract_dirs:
        found = detect_token(d)
        if found:
            results[d.name] = sorted(found)

    report = {
        "total_scanned": len(contract_dirs),
        "use_token_standards": len(results),
        "addresses": results,
    }

    RESULT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(RESULT_FILE, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
