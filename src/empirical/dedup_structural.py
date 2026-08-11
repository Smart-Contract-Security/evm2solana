import collections
import hashlib
import json
import re
import shutil
from pathlib import Path

DATASET_DIR = Path("empirical/dataset")
MANIFEST = Path("empirical/dataset/manifest.jsonl")
DUP_DIR = Path("empirical/duplicate_templates")
REPORT = Path("logs/empirical/preprocess/dedup_structural_report.json")

# https://docs.soliditylang.org/en/latest/grammar.html
KEYWORDS = set((
    # keywords
    """
    pragma import as is abstract contract interface library internal external private public
    constructor pure view payable override function fallback receive virtual returns
    modifier struct enum type immutable constant indexed event anonymous error using address
    payable bool string bytes fixed ufixed memory storage calldata delete new from revert
    global true false unchecked if else for while do continue break try catch
    return emit assembly mapping leave let switch case default bytes
    wei gwei ether seconds minutes hours days weeks years
    int uint unicode hex
    """
).split())


def skeleton(contract_dir: Path) -> str:
    parts = []
    for p in contract_dir.rglob("*.sol"):
        try:
            parts.append(p.read_text(encoding="utf-8", errors="ignore"))
        except Exception:
            pass
    blob = "".join(sorted(parts))
    # strip comments
    # // or /*
    blob = re.sub(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
                  lambda m: "" if m.group(0)[:2] in ("//", "/*") else "S", blob, flags=re.S)
    # fold sized elementary types to their base keyword (uintN/intN/bytesN/fixedMxN)
    blob = re.sub(r"\b(u?int)\d*\b", r"\1", blob)
    blob = re.sub(r"\bbytes([1-9]|[12]\d|3[0-2])\b", "bytes", blob)
    blob = re.sub(r"\b(u?fixed)\d+x\d+\b", r"\1", blob)
    # numbers / addresses
    blob = re.sub(r"0x[0-9a-fA-F]+|\d+", "N", blob)
    blob = re.sub(r"[A-Za-z_]\w*",
                  lambda m: m.group(0) if m.group(0) in KEYWORDS else "I", blob)
    blob = re.sub(r"\s+", "", blob)
    return hashlib.sha256(blob.encode()).hexdigest()


def coverage(sizes: list[int], k: int) -> int:
    return sum(sizes[:k])


def gini(sizes: list[int]) -> float:
    xs = sorted(sizes)
    n, s = len(xs), sum(xs)
    return (2 * sum((i + 1) * v for i, v in enumerate(xs))) / (n * s) - (n + 1) / n


if __name__ == "__main__":
    records = [json.loads(l) for l in MANIFEST.read_text(encoding="utf-8").splitlines() if l.strip()]

    clusters: dict[str, list[str]] = collections.defaultdict(list)
    for r in records:
        d = DATASET_DIR / r["address"]
        if d.is_dir():
            clusters[skeleton(d)].append(r["address"])

    reps: set[str] = set()
    dup_to_rep: dict[str, str] = {}
    clusters_info = []
    for h, addrs in clusters.items():
        # lexicographically smallest
        rep = min(addrs)
        reps.add(rep)
        for a in addrs:
            if a != rep:
                dup_to_rep[a] = rep
        clusters_info.append({"rep": rep, "size": len(addrs),
                              "members": sorted(addrs)})

    # move redundant copies aside (representatives stay in empirical/dataset/)
    DUP_DIR.mkdir(parents=True, exist_ok=True)
    moved = 0
    for a in dup_to_rep:
        src, dst = DATASET_DIR / a, DUP_DIR / a
        if src.is_dir() and not dst.exists():
            shutil.move(str(src), str(dst))
            moved += 1

    # rewrite manifest to the kept representatives (preserve original order)
    with open(MANIFEST, "w", encoding="utf-8") as f:
        for r in records:
            if r["address"] in reps:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")

    # report: concentration stats (paper) + full cluster mapping (reproducibility)
    sizes = sorted((c["size"] for c in clusters_info), reverse=True)
    tot, nd = sum(sizes), len(sizes)

    report = {
        "original": tot,
        "distinct": nd,
        "redundant": tot - nd,
        "redundant_pct": round(100 * (tot - nd) / tot, 1),
        "singletons": sum(1 for s in sizes if s == 1),
        "largest_template": sizes[0],
        "gini": round(gini(sizes), 3),
        "topk_coverage": {str(k): {"deployments": coverage(sizes, k),
                                   "pct": round(100 * coverage(sizes, k) / tot, 1)}
                          for k in (1, 5, 10, 20, 50, 100)},
        "moved_to_backup": moved,
        "duplicate_clusters": sorted([c for c in clusters_info if c["size"] > 1],
                                     key=lambda x: -x["size"]),
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
