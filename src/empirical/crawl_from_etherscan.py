import os
import requests
import time
import json
import re
import hashlib
import logging

from datetime import datetime, timezone
from pathlib import Path
from dotenv import load_dotenv
from requests.exceptions import ConnectionError, ProxyError, ChunkedEncodingError

# Global
load_dotenv(".env", override=True)
etherscan_url="https://api.etherscan.io/v2/api"
out_dir = Path("empirical/dataset/")
logs_path = Path("logs/empirical/crawl/")

def time_sleep():
    # free, 5 calls in 1 seconds
    time.sleep(0.25)

MAX_RETRIES = 3
RETRY_WAIT = 10
def _get_with_retry(session, params):
    last_error = None
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            time_sleep()
            return session.get(etherscan_url, params=params, timeout=60)
        except (ProxyError, ConnectionError, ChunkedEncodingError) as e:
            last_error = e
            if attempt < MAX_RETRIES:
                time.sleep(RETRY_WAIT)
    raise last_error

def sanitize_name(name: str) -> str:
    cleaned = re.sub(r"[^\w.-]", "_", name or "")
    return cleaned or "Contract"

def setup_logging() -> None:
    logs_path.mkdir(parents=True, exist_ok=True)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    log_file = logs_path / f"crawl_from_etherscan_{ts}.log"
    logging.basicConfig(
        level=logging.INFO,
        handlers=[
            logging.FileHandler(log_file, mode="w", encoding="utf-8")
        ],
    )

def compiler_over_08(compiler_version: str) -> bool:
    m = re.search(r"v(\d+)\.(\d+)", compiler_version or "")
    if not m:
        return False
    major, minor = int(m.group(1)), int(m.group(2))
    return (major, minor) >= (0, 8)

def get_latest_block(session, api_key):

    responses = _get_with_retry(session, params={
        "apikey": api_key, "chainid": 1, "module": "proxy", "action": "eth_blockNumber"})
    
    responses_json = responses.json()
    result = responses_json.get("result")
    if result and isinstance(result, str) and result.startswith("0x"):
        return int(result,16)
    return None

def get_block_transactions(session, api_key, block_number):

    responses = _get_with_retry(session, params={
        "apikey": api_key, "chainid": 1, "module": "proxy", 
        "action": "eth_getBlockByNumber", "tag": hex(block_number), "boolean": "true"})

    responses_json = responses.json()
    result = responses_json.get("result")
    if result and isinstance(result, dict):
        return result.get("transactions") or []

    return []

def get_created_address(session, api_key, tx_hash):

    responses = _get_with_retry(session, params={
        "apikey": api_key, "chainid": 1, "module": "proxy", "action": "eth_getTransactionReceipt", "txhash": tx_hash})
    
    responses_json = responses.json()
    result = responses_json.get("result")
    if result and isinstance(result, dict):
        address = result.get("contractAddress")
        if address:
            return address
    return None

def get_source_code(session, api_key, address):
    
    responses = _get_with_retry(session, params={
        "apikey": api_key, "chainid": 1, "module": "contract", "action": "getsourcecode", "address": address})

    responses_json = responses.json()
    if responses_json.get("status") == "1" and isinstance(responses_json.get("result"), list) and responses_json.get("result"):
        data = responses_json["result"][0]
        if not data.get("SourceCode"):
            return None
        return data
    return None

def parse_source_code(source_code: str, contract_name: str):
    text = source_code.strip()

    # no {}
    if not text.startswith("{"):
        return {f"{sanitize_name(contract_name)}.sol": source_code}, {}

    # {{...}} -> {...} for json.loads
    if text.startswith("{{") and text.endswith("}}"):
        text = text[1:-1]

    try:
        obj = json.loads(text)
    except json.JSONDecodeError:
        return {f"{sanitize_name(contract_name)}.sol": source_code}, {}

    # Standard JSON Input.
    if isinstance(obj, dict) and isinstance(obj.get("sources"), dict):
        files: dict[str, str] = {}
        for path, value in obj["sources"].items():
            content = value.get("content") if isinstance(value, dict) else None
            if content is not None:
                files[path] = content
        if files:
            return files, obj.get("settings", {}) or {}
    
    # Older Etherscan format: top-level keys are file paths (no "sources" wrapper).
    # Each value is {"content": "..."} or {"source": "..."}.
    if isinstance(obj, dict):
        files = {}
        for path, value in obj.items():
            if isinstance(value, dict):
                content = value.get("content") or value.get("source")
                if content is not None:
                    files[path] = content
        if files:
            return files, {}
    
    return {f"{sanitize_name(contract_name)}.sol": source_code}, {}


def safe_relpath(base: Path, rel: str) -> Path:
    rel = rel.replace("\\", "/")
    parts = [p for p in rel.split("/") if p not in ("", ".", "..")]
    if not parts:
        parts = ["source.sol"]
    return base.joinpath(*parts)

def save_contract(out_dir: Path, address: str, info: dict) -> dict:
    contract_name = info.get("ContractName", "")
    source_code = info.get("SourceCode", "")
    files, settings = parse_source_code(source_code, contract_name)

    contract_dir = out_dir / address
    contract_dir.mkdir(parents=True, exist_ok=True)

    for rel_path, content in files.items():
        dest = safe_relpath(contract_dir, rel_path)
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(content, encoding="utf-8")

    source_hash = hashlib.sha256(source_code.encode("utf-8")).hexdigest()
    record = {
        "address": address,
        "contract_name": contract_name,
        "compiler_version": info.get("CompilerVersion", ""),
        "file_count": len(files),
        "source_sha256": source_hash,
        "fetched_at": datetime.now(timezone.utc).isoformat(),
    }
    metadata = dict(record)
    if settings:
        metadata["solc_settings"] = settings
    (contract_dir / "metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    return record        


def crawl_and_verfy(session, api_key):

    # log
    setup_logging()

    # collect
    collected_contract_number = 0
    limit_collect = 600

    # find latest block
    # block = get_latest_block(session, api_key)
    
    # resume from last session
    # 2025  -  22606143
    # 2024  -  19993250
    block = 19993250

    if block is None:
        return

    start_block = block
    end_block = 0
  
    for b in range(start_block, end_block, -1):
        if collected_contract_number >= limit_collect:
            break
        transactions = get_block_transactions(session, api_key, b)
        logging.info("block %s: %s txs", b, len(transactions))

        for tx in transactions:
            if collected_contract_number >= limit_collect:
                break

            if tx.get("to") in (None, ""):
                address = get_created_address(session, api_key, tx.get("hash"))
                if address:
                    # avoid duplicates on resume
                    if (out_dir / address).exists():
                        continue
                    info = get_source_code(session, api_key, address)
                    if info:
                        # compile > 0.8
                        if not compiler_over_08(info.get("CompilerVersion", "")):
                            continue
                    
                        record = save_contract(out_dir, address, info)
                        manifest_path = Path(out_dir) / "manifest.jsonl"
                        with manifest_path.open("a", encoding="utf-8") as f:
                            f.write(json.dumps(record, ensure_ascii=False) + "\n")
                        
                        collected_contract_number += 1
                        logging.info("saved %s", address)



if __name__ == "__main__":
    api_key = os.environ.get("ETHERSCAN_API_KEY")
    session = requests.Session()

    # proxy
    proxy = os.environ.get("HTTPS_PROXY")
    if proxy:
        session.proxies = {"http": proxy, "https": proxy}

    
    crawl_and_verfy(session, api_key)


