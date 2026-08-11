import time
from dataclasses import dataclass

from openai import OpenAI

from llm_study import config


@dataclass
class LLMResult:
    text: str
    llm_token: int
    # seconds for this single call
    llm_time: float


class LLMClient:

    def __init__(self):
        provider = config.LLM_PROVIDERS[config.ACTIVE]
        self.model = provider["model"]
        self._extra_body = provider.get("thinking")
        if not provider["api_key"]:
            raise RuntimeError(f"No API key for provider '{config.ACTIVE}'")
        self._client = OpenAI(base_url=provider["base_url"], api_key=provider["api_key"],
                              timeout=config.LLM_TIMEOUT, max_retries=config.LLM_MAX_RETRIES)

    def chat_completion(self, system: str, user: str) -> LLMResult:
        start_time = time.perf_counter()
        response = self._client.chat.completions.create(
            model=self.model,
            temperature=config.LLM_TEMPERATURE,
            max_tokens=config.LLM_MAX_TOKENS,
            timeout=config.LLM_TIMEOUT,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            extra_body=self._extra_body,
        )
        llm_time = time.perf_counter() - start_time
        text = response.choices[0].message.content or ""
        usage = getattr(response, "usage", None)
        return LLMResult(
            text=text,
            llm_token=getattr(usage, "total_tokens", 0) or 0,
            llm_time=llm_time,
        )
