import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1]))
os.chdir(HERE.parents[2])

from dotenv import load_dotenv
load_dotenv(".env")

from llm_study import config
from llm_study.compile import solang_compile_project
from llm_study.project_io import iter_projects, output_results, LLMLog
from llm_study.prompt import build_prompt, build_compile_prompt
from llm_study.client import LLMClient


def _chat(client: LLMClient, system: str, user: str, retries: int = 2):
    last = None
    for _ in range(retries + 1):
        try:
            return client.chat_completion(system, user)
        except Exception as e:
            last = e
    raise last


def translate_project(project, client: LLMClient, run_log):
    converted: dict[str, str] = {}
    for rel in sorted(project.source_files):
        system, user = build_prompt(project.source_files[rel])
        r = _chat(client, system, user)
        converted[rel] = r.text
        run_log.record_file(project, rel, r)

    # solang compiler-feedback repair loop
    out_dir = config.RESULTS_DIR / project.tier / project.address
    for _ in range(config.FEEDBACK_ROUNDS):
        # files on disk so solang can compile them
        output_results(project, converted)
        cr = solang_compile_project(out_dir)
        if cr.success or cr.infra_failed or not cr.errors:
            break
        targets = cr.errors_by_file or {rel: cr.errors for rel in converted}
        for rel, file_errors in targets.items():
            if rel not in converted:
                continue
            system, user = build_compile_prompt(converted[rel], file_errors)
            r = _chat(client, system, user)
            converted[rel] = r.text
            run_log.record_file(project, rel, r)
    return converted


if __name__ == "__main__":
    client = LLMClient()
    for tier in config.TIERS:
        run_log = LLMLog(client.model, tier)
        count = 0
        for project in iter_projects(tier):
            count += 1
            try:
                converted = translate_project(project, client, run_log)
                output_results(project, converted)
            except Exception as exc:
                output_results(project, {})
                run_log.error(project, exc)
        run_log.finish(count)
