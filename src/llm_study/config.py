import os
from pathlib import Path

# Compile
SOLANG_BIN = "solang"
SOLANG_TARGET = "solana"
COMPILE_TIMEOUT: int = 120


TIERS = ["L1", "L2", "L3", "L4"]

# pure_llm / feedback / knowledge_feedback
MODE: str = "pure_llm"

if MODE == "pure_llm":
    FEEDBACK_ROUNDS: int = 0
    KNOWLEDGE_ENABLED: bool = False
elif MODE == "feedback":
    FEEDBACK_ROUNDS: int = 3
    KNOWLEDGE_ENABLED: bool = False
elif MODE == "knowledge_feedback":
    FEEDBACK_ROUNDS: int = 3
    KNOWLEDGE_ENABLED: bool = True
else:
    raise ValueError(f"Unknown MODE: {MODE}")

# LLM
LLM_TEMPERATURE: float = 0.0           # determinism
LLM_MAX_TOKENS: int = 65536            # headroom for reasoning models that split budget
LLM_TIMEOUT: float = 300.0             # seconds per request
LLM_MAX_RETRIES: int = 2               # transient network / 5xx
LLM_THINKING: bool = False             # thinking ON/OFF

LLM_PROVIDERS = {
    "deepseek": {
        "model": "deepseek-v4-pro",
        "base_url": "https://api.deepseek.com",
        "api_key": os.environ.get("DEEPSEEK_API_KEY"),
        "thinking": {"thinking": {"type": "enabled"}} if LLM_THINKING else {"thinking": {"type": "disabled"}},
    },
}

# used LLM
ACTIVE = "deepseek"


RUN_NAME = f"llm_study_{MODE}"
DATASET_DIR = Path("dataset")
RESULTS_DIR = Path("results")/ ACTIVE / RUN_NAME
LOGS_DIR = Path("logs") / RUN_NAME / ACTIVE
# per-tier: compile_<tier>.jsonl / compile_<tier>_summary.json
SOLANG_DIR = LOGS_DIR / "solang"