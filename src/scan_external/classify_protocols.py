import json
import re
from pathlib import Path

PROTOCOLS_FILE = Path("logs/empirical/external/protocols.json")
RESULT_FILE = Path("logs/empirical/external/protocol_classification.json")

NO_SUPPORT = {
    "Uniswap": re.compile(r"Uniswap|^ISwapRouter$|^INonfungiblePositionManager$|^IV3SwapRouter$|^IUniversalRouter$|^IDAIPermit$|^IPoolManager$|^IHooks$|^IExtsload$|^IExttload$|^IProtocolFees$|^IAllowanceTransfer$|^IDexFactory$|^IDexRouter$|^IRouter$|^IFactory$"),
    "Aave": re.compile(r"Aave|^ILendingPool|^IPoolAddressesProvider$|^IFlashLoan.*Receiver$"),
    "Balancer": re.compile(r"Balancer|^IVaultAuthority$"),
    "Curve": re.compile(r"Curve|^IStableSwap$"),
    "Chainlink": re.compile(r"Aggregator(V3|V2V3)Interface|Chainlink"),
    "LayerZero": re.compile(r"LayerZero|^ILayerZero|^IMessageLibManager$|^IMessaging"),
    "Term Finance": re.compile(r"^ITerm"),
    "Creator Token Standards": re.compile(r"^ITransferValidator|^ICreatorToken"),
}

SEMANTIC_GAP = {
    "ERC-20": re.compile(r"^IERC20"),
    "ERC-721": re.compile(r"^I?ERC721"),
    "ERC-1155": re.compile(r"^IERC1155"),
    "ERC-1363": re.compile(r"^IERC1363"),
    "ERC-4626": re.compile(r"^IERC4626"),
    "ERC-777": re.compile(r"^IERC777"),
    "ERC-6909": re.compile(r"^IERC6909"),
    "Wrapped Ether": re.compile(r"^IWETH"),
}

if __name__ == "__main__":
    report = json.load(open(PROTOCOLS_FILE, encoding="utf-8"))
    addresses = report["addresses"]

    no_support_per = {k: 0 for k in NO_SUPPORT}
    no_support_projects = 0
    no_support_addresses = []
    semantic_gap_per = {k: 0 for k in SEMANTIC_GAP}
    semantic_gap_projects = 0
    semantic_gap_addresses = []
    undetermined_projects = 0
    undetermined_addresses = []
    projects_with_not_implemented = set()
    for addr, v in addresses.items():
        not_implemented = v["not_implemented"]
        if not not_implemented:
            continue
        projects_with_not_implemented.add(addr)

        hit_no_support = False
        for name, pat in NO_SUPPORT.items():
            if any(pat.search(x) for x in not_implemented):
                no_support_per[name] += 1
                hit_no_support = True
        if hit_no_support:
            no_support_projects += 1
            no_support_addresses.append(addr)
        hit_semantic = False
        for name, pat in SEMANTIC_GAP.items():
            if any(pat.search(x) for x in not_implemented):
                semantic_gap_per[name] += 1
                hit_semantic = True
        if hit_semantic:
            semantic_gap_projects += 1
            semantic_gap_addresses.append(addr)
        hit_undetermined = False
        for ni in not_implemented:
            if not any(pat.search(ni) for pat in NO_SUPPORT.values()) and \
               not any(pat.search(ni) for pat in SEMANTIC_GAP.values()):
                hit_undetermined = True
                break
        if hit_undetermined:
            undetermined_projects += 1
            undetermined_addresses.append(addr)

    out = {
        "projects_with_not_implemented": len(projects_with_not_implemented),
        "no_support_per_protocol": dict(sorted(no_support_per.items(), key=lambda kv: -kv[1])),
        "no_support_projects": no_support_projects,
        "no_support_addresses": sorted(no_support_addresses),
        "semantic_gap_per_protocol": dict(sorted(semantic_gap_per.items(), key=lambda kv: -kv[1])),
        "semantic_gap_projects": semantic_gap_projects,
        "semantic_gap_addresses": sorted(semantic_gap_addresses),
        "undetermined_projects": undetermined_projects,
        "undetermined_addresses": sorted(undetermined_addresses),
    }

    RESULT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(RESULT_FILE, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
