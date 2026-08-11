import json
from collections import Counter
from pathlib import Path

RESULTS = Path("logs/empirical/token/token.json")
SUMMARY = Path("logs/empirical/token/analysis.json")

if __name__ == "__main__":
    with open(RESULTS) as f:
        data = json.load(f)

    total = data["use_token_standards"]
    addresses = data["addresses"]

    counter: Counter = Counter()
    multi = 0
    for tokens in addresses.values():
        counter.update(tokens)
        if len(tokens) > 1:
            multi += 1

    SUMMARY.parent.mkdir(parents=True, exist_ok=True)
    SUMMARY.write_text(json.dumps({
        "use_token_standards": total,
        "ERC20": counter["ERC20"],
        "ERC721": counter["ERC721"],
        "ERC1155": counter["ERC1155"],
        "multiple_standards": multi,
    }, indent=2))
