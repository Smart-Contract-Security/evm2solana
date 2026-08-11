import datetime
import json
from pathlib import Path
from dataclasses import dataclass, field

from llm_study import config


@dataclass
class Project:
    address: str
    directory: Path
    metadata: dict
    tier: str = ""                                              # L1/L2/L3/L4
    source_files: dict[str, str] = field(default_factory=dict)  # relative path: source


def load_project(directory: Path) -> Project:
    directory = Path(directory)
    try:
        metadata_json = json.loads((directory / "metadata.json").read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        metadata_json = {}

    source_files_dict = {}
    for f in directory.rglob("*.sol"):
        key = f.relative_to(directory).as_posix()
        source_files_dict[key] = f.read_text(encoding="utf-8")

    address = metadata_json.get("address") or directory.name
    return Project(address=address, directory=directory, metadata=metadata_json, 
                tier=directory.parent.name, source_files=source_files_dict)


def iter_projects(tier: str):
    for addr_dir in sorted(config.DATASET_DIR.glob(f"{tier}/*")):
        if addr_dir.is_dir() and (addr_dir / "metadata.json").exists():
            yield load_project(addr_dir)


def output_results(project: Project, converted: dict[str, str]) -> None:
    base = config.RESULTS_DIR / project.tier / project.address
    base.mkdir(parents=True, exist_ok=True)
    (base / "metadata.json").write_text(json.dumps(project.metadata), encoding="utf-8")
    for rel, content in converted.items():
        file = base / rel
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content, encoding="utf-8")


class LLMLog:

    def __init__(self, model: str, tier: str):
        config.LOGS_DIR.mkdir(parents=True, exist_ok=True)
        self.model = model
        self.path = config.LOGS_DIR / f"llm_{tier}.jsonl"
        self.path.write_text("", encoding="utf-8")
        self.total_tokens = 0
        self.total_llm_time = 0.0
        self.total_files = 0

    def _write(self, obj: dict) -> None:
        with self.path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(obj, ensure_ascii=False) + "\n")

    def record_file(self, project, rel, result) -> None:
        self.total_tokens += result.llm_token
        self.total_llm_time += result.llm_time
        self.total_files += 1
        self._write({
            "project": project.address,
            "file": rel,
            "llm_token": result.llm_token,
            "llm_time": result.llm_time,
        })


    def error(self, project, exc) -> None:
        self._write({
            "project": project.address,
            "error": str(exc),
        })

    def finish(self, project_count: int) -> None:
        self._write({
            "timestamp": datetime.datetime.now().isoformat(),
            "project_count": project_count,
            "total_files": self.total_files,
            "total_tokens": self.total_tokens,
            "total_llm_time": self.total_llm_time,
            "model": self.model,
        })
