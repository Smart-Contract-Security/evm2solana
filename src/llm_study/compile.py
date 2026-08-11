import json
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

@dataclass
class CompileResult:
    success: bool = False
    error_count: int = 0
    errors: list[str] = field(default_factory=list)
    # relative path -> its errors
    errors_by_file: dict[str, list[str]] = field(default_factory=dict)
    infra_failed: bool = False

def _importmap_args(metadata: dict) -> list[str]:
    args = ["-I", "."]
    remappings = (metadata.get("solc_settings") or {}).get("remappings", [])
    for raw in remappings:
        raw = (raw or "").strip()
        if not raw or "=" not in raw:
            continue
        colon, eq = raw.find(":"), raw.find("=")
        if 0 <= colon < eq:
            raw = raw[colon + 1:]
        args += ["--importmap", raw]
    return args

def solang_compile_project(contract_dir_path: Path, solang_bin: str = "solang",
                           solang_target: str = "solana", timeout: int = 120) -> CompileResult:
    metadata_json = contract_dir_path / "metadata.json"
    try:
        metadata = json.loads(metadata_json.read_text(encoding="utf-8"))
    except Exception:
        metadata = {}

    cdir = str(contract_dir_path.resolve())
    sol_files = [str(f.relative_to(contract_dir_path)) for f in contract_dir_path.rglob("*.sol")]
    if not sol_files:
        return CompileResult(success=False, errors=["no .sol files"], infra_failed=True)

    cmd = ([solang_bin, "compile", "--target", solang_target, "--standard-json"] + _importmap_args(metadata) + sol_files)

    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=cdir)
    except FileNotFoundError:
        return CompileResult(success=False, errors=["solang binary not found"], infra_failed=True)
    except subprocess.TimeoutExpired:
        return CompileResult(success=False, errors=["timeout"], infra_failed=True)

    try:
        out = json.loads(proc.stdout)
    except (json.JSONDecodeError, TypeError):
        return CompileResult(success=False, errors=[(proc.stderr or "")[:1000]], infra_failed=True)

    errors: list[str] = []
    errors_by_file: dict[str, list[str]] = {}
    root = contract_dir_path.resolve()
    for d in out.get("errors", []):
        if d.get("severity") != "error":
            continue
        message = d.get("message", "").strip()
        errors.append(message)
        
        fpath = (d.get("sourceLocation") or {}).get("file")
        if fpath:
            try:
                rel = Path(fpath).resolve().relative_to(root).as_posix()
            except ValueError:
                rel = None
            if rel:
                errors_by_file.setdefault(rel, []).append(message)

    return CompileResult(success=(len(errors) == 0), error_count=len(errors), errors=errors, errors_by_file=errors_by_file)
