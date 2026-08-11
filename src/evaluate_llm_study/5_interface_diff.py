import json
import os
import sys
import subprocess
import re
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1]))
os.chdir(HERE.parents[2])

from empirical.compile_solc import switch_solc_version, build_standard_json

OUTPUT = Path("logs/evaluate_llm/interface_diff")
BUILD_DIR = OUTPUT / "build"
SCALAR_MAP = {"address": "publicKey", "bool": "bool", "string": "string", "bytes": {"vec": "u8"}}
OUTPUT_FILE = OUTPUT / "interface_diff.json"

def iter_cs_projects() -> list[dict]:
    root = HERE.parents[2] 
    COMPILE_DIR = root / "logs/evaluate_llm/compile/llm_study_knowledge_feedback"
    PORTED_ROOT = root / "results/deepseek/llm_study_knowledge_feedback"
    ORIGINAL_ROOT = root / "dataset"
    TIERS = ["L1", "L2", "L3", "L4"]

    projects = []
    for tier in TIERS:
        path = COMPILE_DIR / f"compile_{tier}.jsonl"
        if not path.exists():
            continue
        with open(path, encoding="utf-8") as f:
            for line in f:
                if not line.strip():
                    continue
                r = json.loads(line)
                if not r.get("success") or r.get("infra_failed"):
                    continue
                addr = r["address"]
                projects.append({
                    "tier": tier,
                    "address": addr,
                    "ported_dir": PORTED_ROOT / tier / addr,
                    "original_dir": ORIGINAL_ROOT / tier / addr,
                })
    return projects

def compile_original(directory: Path) -> dict:
    sources = {}
    for file in directory.rglob("*.sol"):
        key = file.relative_to(directory).as_posix()
        sources[key] = file.read_text(encoding="utf-8", errors="replace")

    metadata_file = directory / "metadata.json"
    if not metadata_file.exists():
        return {"error": "metadata.json missing"}
    metadata = json.loads(metadata_file.read_text("utf-8"))

    switch_result = switch_solc_version(metadata.get("compiler_version", ""))
    if not switch_result["success"]:
        return {"error": switch_result["errors"][0]}
    
    standard_json = build_standard_json(sources, metadata.get("solc_settings"))
    process = subprocess.run(["solc", "--standard-json"], input=json.dumps(standard_json), 
                            capture_output=True, text=True, timeout=180)
    output = json.loads(process.stdout or "{}")
    fatal_errors = []
    for diagnostic  in output.get("errors", []):
        if diagnostic.get("severity") == "error":
            fatal_errors.append(diagnostic.get("message", ""))

    if fatal_errors:
        return {"error": fatal_errors[0][:200]}

    target_name = metadata.get("contract_name")
    all_contracts = {}
    for file_contracts in output.get("contracts", {}).values():
        for name, contract_data in file_contracts.items():
            all_contracts[name] = contract_data.get("abi", [])

    if target_name and target_name in all_contracts:
        return {"name": target_name, "abi": all_contracts[target_name]}
    
    if not all_contracts:
        return {"error": "no contracts"}

    return {"error": f"contract {target_name} not in solc output"}

def compile_ported(directory: Path, out_dir: Path, contract_name: str) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    sources = []
    for file in directory.rglob("*.sol"):
        sources.append(str(file.relative_to(directory)))

    cmd = ["solang", "compile", "--target", "solana", "--output", str(out_dir.resolve()), "-I", "."]
    cmd.extend(sources)
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300, cwd=str(directory),)
    idls = sorted(out_dir.glob("*.json"))
    if not idls:
        return {"error": (proc.stderr or proc.stdout or "solang produced no IDL")[:200]}

    chosen = idls[0]
    for p in idls:
        if p.stem == contract_name:
            chosen = p
            break

    return {"name": chosen.stem, "idl": json.loads(chosen.read_text("utf-8"))}

def expected_idl_type(evm_type: str):
    if evm_type in SCALAR_MAP:
        return SCALAR_MAP[evm_type]
    fixed = re.fullmatch(r"bytes([1-9]|[12][0-9]|3[0-2])", evm_type)
    if fixed:
        return {"array": ["u8", int(fixed.group(1))]}
    integer = re.fullmatch(r"(u?)int(\d*)", evm_type)
    if integer:
        return f"{'u' if integer.group(1) else 'i'}{integer.group(2) or '256'}"
    return None        

def bit_width(idl_type) -> int | None:
    if not isinstance(idl_type, str):
        return None
    match = re.fullmatch(r"[ui](\d+)", idl_type)
    if match is None:
        return None
    return int(match.group(1))


def compare_argument(evm_type: str, actual) -> str | None:
    expected = expected_idl_type(evm_type)
    if expected is None or expected == actual:
        return None
    wide = bit_width(expected)
    narrow = bit_width(actual)
    if wide and narrow and narrow < wide:
        return "TYPE_NARROWED"
    return "TYPE_OTHER"

def compare(abi: list, idl: dict) -> list[dict]:
    instructions = {}
    for ix in idl.get("instructions", []):
        if "name" in ix:
            instructions[ix["name"]] = ix

    divergences = []

    for function in abi:
        if function.get("type") != "function":
            continue
        name = function["name"]
        inputs = function.get("inputs", [])
        types = []
        for i in inputs:
                types.append(i.get("type", ""))
        signature = name + "(" + ",".join(types) + ")"
        instruction = instructions.get(name)
        
        if instruction is None:
            divergences.append({"kind": "MISSING", "function": signature})
            continue

        args = instruction.get("args", [])
        if len(args) != len(inputs):
            divergences.append({"kind": "ARITY", "function": signature, "evm": len(inputs), "solana": len(args)})
            continue
        
        for i in range(len(inputs)):
            evm_type = inputs[i].get("type", "")
            solana_type = args[i].get("type", "")
            kind = compare_argument(evm_type, solana_type)
            if kind:
                divergences.append({"kind": kind, "function": signature, "position": i, "evm": evm_type, "solana": solana_type})

        is_mutable = function.get("stateMutability") not in ("view", "pure")
        if is_mutable:
            has_signer = False
            for account in instruction.get("accounts", []):
                if account.get("isSigner"):
                    has_signer = True
                    break
            
            if not has_signer:
                account_names = []
                for a in instruction.get("accounts", []):
                    account_names.append(a.get("name"))
                divergences.append({"kind": "NO SIGNER", "function": signature, "accounts": account_names,})

    constructor = None
    for function in abi:
        if function.get("type") == "constructor":
            constructor = function
            break
    
    initializer = instructions.get("new")

    if constructor is not None and initializer is not None:
        evm_count = len(constructor.get("inputs", []))
        solana_count = len(initializer.get("args", []))
        if evm_count != solana_count:
            divergences.append({"kind": "Constructor Arity", "function": "constructor", "evm": evm_count, "solana": solana_count,})

    return divergences

def diff_project(project: dict) -> dict:
    record = {"tier": project["tier"], "address": project["address"]}
    original = compile_original(project["original_dir"])
    if "abi" not in original:
        record["status"] = "solc compile failure"
        record["error"] = original["error"]
        return record

    ported = compile_ported(project["ported_dir"], 
                            BUILD_DIR / project["tier"] / project["address"],
                            original["name"])

    if "idl" not in ported:
        record["status"] = "solang compile failure"
        record["error"] = ported["error"]
        return record

    divergences = compare(original["abi"], ported["idl"])
    counts: dict[str, int] = {}
    for divergence in divergences:
        counts[divergence["kind"]] = counts.get(divergence["kind"], 0) + 1

    return {
        "tier": project["tier"],
        "address": project["address"],
        "status": "COMPARED",
        "contract": original["name"],
        "evm_functions": sum(1 for f in original["abi"] if f.get("type") == "function"),
        "solana_instructions": len(ported["idl"].get("instructions", [])),
        "divergent": bool(divergences),
        "divergence_counts": counts,
        "divergences": divergences,        
    }  
    
 
if __name__ == "__main__":
    results = [diff_project(p) for p in iter_cs_projects()]
    compared = [r for r in results if r["status"] == "COMPARED"]

    totals: dict[str, int] = {}
    for record in compared:
        for kind, number in record["divergence_counts"].items():
            totals[kind] = totals.get(kind, 0) + number

    totals = dict(sorted(totals.items(), key=lambda x: x[1], reverse=True))
    
    blocked: dict[str, int] = {}
    for r in results:
        if r["status"] != "COMPARED":
            blocked[r["status"]] = blocked.get(r["status"], 0) + 1
    
    report = {
        "projects": len(results),
        "compared": len(compared),
        "divergent": sum(1 for r in compared if r["divergent"]),
        "blocked": blocked,
        "divergences_by_kind": totals,
        "projects_by_kind": {kind: sum(1 for r in compared if kind in r["divergence_counts"])
                             for kind in totals},
        "per_project": results,
    }

    OUTPUT.mkdir(parents=True, exist_ok=True)
    OUTPUT_FILE.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")    