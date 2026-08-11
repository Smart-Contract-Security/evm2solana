from llm_study import config
from llm_study.knowledge import KNOWLEDGE


SYSTEM = (
"""You are an expert at porting EVM Solidity contracts to Solana via the Solang compiler.
Port the given file so it compiles under Solang for Solana. 
Output only the complete source code, with no markdown formatting and no explanations."""
)

if config.KNOWLEDGE_ENABLED:
    SYSTEM += "\n" + KNOWLEDGE

def build_prompt(content: str) -> tuple[str, str]:
    user = f"Port this Solidity file so that it compiles on Solana with solang:\n{content}"
    return SYSTEM, user


def build_compile_prompt(current: str, errors: list[str]) -> tuple[str, str]:
    errors_str = "\n".join(f"- {e}" for e in errors)
    user = (
        "A previous automated porting pass has already been applied to this file, but it produced compilation failures."
        "Your task is to resolve the remaining errors and continue porting from the current state."
        f"Compilation errors in this file:\n{errors_str}\n\n"
        f"File:\n{current}"
    )
    return SYSTEM, user
