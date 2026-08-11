
import re
from scan_pattern import solc_ast
from scan_pattern.solc_ast import SolcParsedResult
from scan_pattern.registry import ScanHit

_CURRENCY_UNITS = {"ether", "gwei", "wei"}
_INT_RE = re.compile(r"^(u?int)(\d*)$")

def int_over_64(name: str | None) -> bool:
    m = _INT_RE.match(name or "")
    if not m:
        return False
    bits = int(m.group(2)) if m.group(2) else 256
    return bits > 64

def _base_expression(node: dict) -> dict:
    return node.get("expression") or {}

def _base_identify_name(node: dict) -> str | None:
    base_expression = _base_expression(node)
    return base_expression.get("name") if base_expression.get("nodeType") == "Identifier" else None

def _base_typestring(node: dict) -> str:
    return (_base_expression(node).get("typeDescriptions") or {}).get("typeString", "")

def match_node(node: dict, parent: dict | None = None) -> list[int]:
    node_type = node.get("nodeType")
    detect_pattern_list: list[int] = []

    # .
    if node_type == "MemberAccess":
        # right of .
        right_name = node.get("memberName")
        # name of left
        left_name = _base_identify_name(node)
        # type of left
        left_typestring = _base_typestring(node)
        
        if right_name == "balance" and left_typestring in ("address", "address payable"):
            detect_pattern_list.append(4)
        if right_name == "delegatecall":
            detect_pattern_list.append(26)
        if right_name in ("send", "transfer") and left_typestring in ("address", "address payable"):
            detect_pattern_list.append(27)

        if left_name == "msg":
            if right_name in ("gas", "gaslimit"):
                detect_pattern_list.append(5)
            elif right_name == "sender":
                detect_pattern_list.append(6)
            elif right_name == "sig":
                detect_pattern_list.append(29)
            elif right_name == "value":
                detect_pattern_list.append(12)
        elif left_name == "tx":
            if right_name == "origin":
                detect_pattern_list.append(24)
            elif right_name == "gasprice":
                detect_pattern_list.append(31)
        elif left_name == "block":
            if right_name in ("timestamp", "number"):
                detect_pattern_list.append(34)
            if right_name == "number":
                detect_pattern_list.append(35)
            elif right_name in ("gaslimit", "coinbase", "difficulty"):
                detect_pattern_list.append(36)
            elif right_name == "blockhash":
                detect_pattern_list.append(33)
        elif left_name == "abi":
            if right_name == "encodePacked":
                detect_pattern_list.append(20)
            elif right_name in ("encodeWithSelector", "encodeWithSignature"):
                detect_pattern_list.append(30)
    
    elif node_type == "FunctionCall":
        expression = _base_expression(node)
        if expression.get("nodeType") == "Identifier":
            name = expression.get("name")
            if name == "ecrecover":
                detect_pattern_list.append(7)
            elif name == "gasleft":
                detect_pattern_list.append(28)
            elif name in ("selfdestruct", "suicide"):
                detect_pattern_list.append(32)
            elif name == "blockhash":
                detect_pattern_list.append(33)
            elif name == "require" and len(node.get("arguments") or []) >= 2:
                detect_pattern_list.append(11)
            elif name == "revert" and node.get("arguments"):
                detect_pattern_list.append(11)

        # member function call: contractInstance.foo()
        elif expression.get("nodeType") == "MemberAccess" and node.get("kind") == "functionCall":
            t = _base_typestring(expression)
            # external call on a contract/interface instance -> needs accounts (3) and a
            # @program_id annotation (15).
            if t.startswith("contract "):
                detect_pattern_list.extend((3, 15))
            # low-level external call: addr.call(...) / addr.staticcall(...)
            if t in ("address", "address payable") and expression.get("memberName") in ("call", "staticcall"):
                detect_pattern_list.extend((3, 15))

    elif node_type == "FunctionCallOptions":
        names = set(node.get("names") or [])
        is_new = _base_expression(node).get("nodeType") == "NewExpression"
        
        if "value" in names:
            detect_pattern_list.append(12)
        if "salt" in names:
            detect_pattern_list.append(9)
        if "gas" in names:
            detect_pattern_list.append(9 if is_new else 25)

    elif node_type == "NewExpression":
        if node.get("typeName", {}).get("nodeType") == "UserDefinedTypeName":
            detect_pattern_list.append(8)

    elif node_type == "ElementaryTypeName":
        if int_over_64(node.get("name")):
            detect_pattern_list.append(2)
        if node.get("name") == "address" and node.get("stateMutability") == "payable":
            detect_pattern_list.append(17)

    elif node_type == "UserDefinedTypeName":
        if ((node.get("typeDescriptions") or {}).get("typeString", "").startswith("contract ")
            and parent is not None
            and parent.get("nodeType") == "VariableDeclaration"
            and not parent.get("stateVariable", False)):
            detect_pattern_list.append(21)
    
    elif node_type == "FunctionDefinition":
        kind = node.get("kind")
        if kind == "constructor":
            detect_pattern_list.append(16)
        elif kind == "receive":
            detect_pattern_list.append(18)
        if kind != "receive" and node.get("stateMutability") == "payable":
            detect_pattern_list.append(17)

    elif node_type == "VariableDeclaration":
        if node.get("indexed"):
            detect_pattern_list.append(23)
    
    elif node_type == "Literal":
        if node.get("subdenomination") in _CURRENCY_UNITS:
            detect_pattern_list.append(38)
        if (node.get("kind") == "number" and (node.get("typeDescriptions") or {}).get("typeString") == "address"):
            detect_pattern_list.append(1)
    
    elif node_type in ("Identifier", "IdentifierPath"):
        name = node.get("name")
        if name == "this":
            detect_pattern_list.append(22)

    elif node_type == "PragmaDirective":
        literals = node.get("literals") or []
        if literals and literals[0] == "solidity":
            detect_pattern_list.append(37)
    
    elif node_type == "TryStatement":
        detect_pattern_list.append(10)
    elif node_type == "InlineAssembly":
        detect_pattern_list.append(13)
    elif node_type == "ErrorDefinition":
        detect_pattern_list.append(11)
    elif node_type == "RevertStatement":
        if node.get("errorCall"):
            detect_pattern_list.append(11 )
    
    return detect_pattern_list


def _walk_with_parent(node, parent=None):
    if isinstance(node, dict):
        is_node = "nodeType" in node
        if is_node:
            yield node, parent
        next_parent = node if is_node else parent
        for value in node.values():
            yield from _walk_with_parent(value, next_parent)
    elif isinstance(node, list):
        for item in node:
            yield from _walk_with_parent(item, parent)

def detect_unit(parsed: SolcParsedResult) -> list[ScanHit]:
    hits: list[ScanHit] = []
    for file_name in sorted(parsed.asts):
        tree = parsed.asts[file_name]
        source = parsed.sources.get(file_name, "")
        for node, parent in _walk_with_parent(tree):
            if (node.get("nodeType") == "UserDefinedTypeName" and parent is not None 
                and parent.get("nodeType") == "NewExpression"):
                continue
            ids = match_node(node, parent)
            if not ids:
                continue
            src = node.get("src", "")
            line = solc_ast.find_line_in_source(src, source)
            code_snippet = solc_ast.find_snippet_in_source(src, source)
            for pid in ids:
                hits.append(ScanHit(pattern_id=pid, file=file_name, line=line, code_snippet=code_snippet))
    hits.sort(key=lambda h: (h.file, h.line, h.pattern_id))
    return hits

def hits_summary(address: str, hits: list[ScanHit], ast_failed: bool = False) -> dict:
    by_pattern: dict[str, int] = {}
    for h in hits:
        key = str(h.pattern_id)
        by_pattern[key] = by_pattern.get(key, 0) + 1
    return {
        "address": address,
        "ast_failed": ast_failed,
        "total": len(hits),
        "distinct_patterns": len({h.pattern_id for h in hits}),
        "by_pattern": dict(sorted(by_pattern.items(), key=lambda kv: int(kv[0]))),
        "hits": [h.to_dict() for h in hits],
    }
