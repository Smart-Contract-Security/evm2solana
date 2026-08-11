import json
import re
import subprocess
from collections import Counter
from pathlib import Path

EMPIRICAL_DATASET_DIR = Path("empirical/dataset")
RESULT_FILE = Path("logs/empirical/external/protocols.json")
COMPILE_TIMEOUT = 120

def load_asts(project_dir: Path) -> dict[str, dict]:
    metadata = json.loads((project_dir / "metadata.json").read_text("utf-8"))

    m = re.search(r"(\d+)\.(\d+)\.(\d+)", metadata.get("compiler_version", ""))
    if not m:
        return {}
    version = f"{m.group(1)}.{m.group(2)}.{m.group(3)}"

    r = subprocess.run(["solc-select", "use", version], capture_output=True, text=True)
    if r.returncode != 0:
        return {}

    sources = {
        f.relative_to(project_dir).as_posix(): f.read_text("utf-8", errors="replace")
        for f in project_dir.rglob("*.sol")
    }
    remappings = (metadata.get("solc_settings") or {}).get("remappings", [])
    remappings = [r for r in remappings if isinstance(r, str) and r.strip()]

    standard_json = {
        "language": "Solidity",
        "sources": {name: {"content": content} for name, content in sources.items()},
        "settings": {
            "remappings": remappings,
            "outputSelection": {"*": {"": ["ast"]}},
        },
    }

    try:
        proc = subprocess.run(
            ["solc", "--standard-json"],
            input=json.dumps(standard_json),
            capture_output=True, text=True,
            timeout=COMPILE_TIMEOUT,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        return {}

    try:
        output = json.loads(proc.stdout)
    except (json.JSONDecodeError, TypeError):
        return {}

    return {fp: info["ast"] for fp, info in output.get("sources", {}).items() if "ast" in info}


def classify_interfaces(asts: dict[str, dict]) -> tuple[list[str], list[str], list[str]]:
    id_to_name: dict[int, str] = {}
    interface_ids: set[int] = set()
    implemented_ids: set[int] = set()
    has_function: dict[int, bool] = {}
    chain: dict[int, list[int]] = {}

    for tree in asts.values():
        for node in tree.get("nodes", []) or []:
            if node.get("nodeType") != "ContractDefinition":
                continue
            cid = node.get("id")
            if not isinstance(cid, int):
                continue
            id_to_name[cid] = node.get("name", "?")
            has_function[cid] = any(
                m.get("nodeType") == "FunctionDefinition"
                for m in node.get("nodes", []) or []
            )
            raw_chain = node.get("linearizedBaseContracts") or []
            chain[cid] = [b for b in raw_chain if isinstance(b, int)]

            if node.get("contractKind") == "interface":
                interface_ids.add(cid)
            elif node.get("contractKind") == "contract" and not node.get("abstract"):
                implemented_ids.update(chain[cid])

    decl_only_ids = set()
    for i in interface_ids:
        ancestor_ids = chain.get(i) or [i]
        if not any(has_function.get(b, False) for b in ancestor_ids):
            decl_only_ids.add(i)
    
    implemented_names = {id_to_name[i] for i in interface_ids & implemented_ids}
    decl_only_names = {id_to_name[i] for i in decl_only_ids - implemented_ids} - implemented_names
    not_implemented_names = ({id_to_name[i] for i in interface_ids - implemented_ids}
                             - implemented_names - decl_only_names)
    return sorted(not_implemented_names), sorted(implemented_names), sorted(decl_only_names)


if __name__ == "__main__":
    contract_dirs = [
        d for d in EMPIRICAL_DATASET_DIR.iterdir()
        if d.is_dir() and (d / "metadata.json").exists()
    ]

    used_interface_counter: Counter = Counter()
    not_implemented_interface_counter: Counter = Counter()
    implemented_interface_counter: Counter = Counter()
    decl_only_interface_counter: Counter = Counter()
    addresses: dict[str, dict[str, list[str]]] = {}
    ast_failed_addresses: list[str] = []
    projects_with_interface = 0
    projects_with_not_implemented = 0
    projects_with_implemented = 0
    projects_with_decl_only = 0

    for d in contract_dirs:
        asts = load_asts(d)
        if not asts:
            ast_failed_addresses.append(d.name)
            continue
        not_implemented, implemented, decl_only = classify_interfaces(asts)
        used = sorted(set(not_implemented) | set(implemented))
        used_interface_counter.update(used)
        not_implemented_interface_counter.update(not_implemented)
        implemented_interface_counter.update(implemented)
        decl_only_interface_counter.update(decl_only)
        if used:
            projects_with_interface += 1
        if not_implemented:
            projects_with_not_implemented += 1
        if implemented:
            projects_with_implemented += 1
        if decl_only:
            projects_with_decl_only += 1
        if used or decl_only:
            addresses[d.name] = {
                "not_implemented": not_implemented,
                "implemented": implemented,
                "declaration_only": decl_only,
            }

    report = {
        "total_scanned": len(contract_dirs),
        "ast_failed": len(ast_failed_addresses),
        "ast_succeeded": len(contract_dirs) - len(ast_failed_addresses),
        "ast_failed_addresses": sorted(ast_failed_addresses),
        "projects_with_interface": projects_with_interface,
        "projects_with_not_implemented": projects_with_not_implemented,
        "projects_with_implemented": projects_with_implemented,
        "projects_with_declaration_only": projects_with_decl_only,
        "projects_per_used_interface": dict(used_interface_counter.most_common()),
        "projects_per_not_implemented_interface": dict(not_implemented_interface_counter.most_common()),
        "projects_per_implemented_interface": dict(implemented_interface_counter.most_common()),
        "projects_per_declaration_only_interface": dict(decl_only_interface_counter.most_common()),
        "addresses": addresses,
    }

    RESULT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(RESULT_FILE, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)
