// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./TraitGen.sol";

/**
 * @title  SVGBuilder
 * @notice Builds the Living Terminal SVG fully on-chain.
 *         Each NFT = a unique terminal session.
 */
library SVGBuilder {

    // ---------------------------------------------------------------
    //  LINE POOLS — 12 lines per language, no repeats possible
    // ---------------------------------------------------------------

    function getLine(uint8 language, bytes32 seed, uint8 slot)
        internal pure returns (string memory)
    {
        // Unique seed per slot prevents repeats
        uint8 pick = uint8(uint256(keccak256(abi.encodePacked(seed, slot, language))) % 12);

        if (language == 0) return _solidityLine(pick);
        if (language == 1) return _assemblyLine(pick);
        if (language == 2) return _pythonLine(pick);
        if (language == 3) return _rustLine(pick);
        return _bytecodeLine(pick);
    }

    function _solidityLine(uint8 i) internal pure returns (string memory) {
        if (i == 0)  return "mapping(bytes32 =&gt; bool) usedCodes;";
        if (i == 1)  return "require(!usedCodes[hash], &quot;used&quot;);";
        if (i == 2)  return "_mint(msg.sender, tokenId++);";
        if (i == 3)  return "emit CodeUsed(hash, msg.sender);";
        if (i == 4)  return "(bool ok,) = treasury.call{value:v}(&quot;&quot;);";
        if (i == 5)  return "validCodes[hash] = true;";
        if (i == 6)  return "bytes32 h = keccak256(abi.encodePacked(raw));";
        if (i == 7)  return "require(validCodes[h], &quot;Invalid&quot;);";
        if (i == 8)  return "usedCodes[h] = true;";
        if (i == 9)  return "uint256 tokenId = totalMinted++;";
        if (i == 10) return "require(msg.value == mintPrice);";
        return "emit PermanentURI(tokenURI(id), id);";
    }

    function _assemblyLine(uint8 i) internal pure returns (string memory) {
        if (i == 0)  return "PUSH1 0x00 CALLDATALOAD";
        if (i == 1)  return "KECCAK256 DUP1 SLOAD";
        if (i == 2)  return "JUMPI 0x004a STOP";
        if (i == 3)  return "MSTORE 0x40 RETURN";
        if (i == 4)  return "CALLVALUE ISZERO PUSH1";
        if (i == 5)  return "0x7f3a9c2e CALL";
        if (i == 6)  return "PUSH1 0x60 MLOAD DUP1";
        if (i == 7)  return "SWAP1 PUSH2 0x0100 EXP";
        if (i == 8)  return "DUP2 SLOAD DUP2 AND NOT";
        if (i == 9)  return "PUSH1 0x40 MSTORE RETURN";
        if (i == 10) return "CALLER PUSH1 0x00 SSTORE";
        return "GAS STATICCALL POP STOP";
    }

    function _pythonLine(uint8 i) internal pure returns (string memory) {
        if (i == 0)  return "w3.eth.send_transaction(tx)";
        if (i == 1)  return "hash = Web3.keccak(text=code)";
        if (i == 2)  return "contract.functions.mint(code)";
        if (i == 3)  return "assert tx_receipt.status == 1";
        if (i == 4)  return "nonce = w3.eth.get_tx_count(addr)";
        if (i == 5)  return "abi = json.load(open(&quot;abi.json&quot;))";
        if (i == 6)  return "signed = w3.eth.account.sign_tx(tx)";
        if (i == 7)  return "w3 = Web3(Web3.HTTPProvider(rpc))";
        if (i == 8)  return "contract = w3.eth.contract(addr,abi)";
        if (i == 9)  return "receipt = w3.eth.wait_for_receipt(h)";
        if (i == 10) return "tx = contract.functions.mint(code)";
        return "print(f&quot;minted token {token_id}&quot;)";
    }

    function _rustLine(uint8 i) internal pure returns (string memory) {
        if (i == 0)  return "let hash = keccak256(code.as_bytes());";
        if (i == 1)  return "provider.send_transaction(&amp;tx).await?;";
        if (i == 2)  return "let sig = wallet.sign_hash(hash)?;";
        if (i == 3)  return "U256::from_str(&amp;hex_code).unwrap();";
        if (i == 4)  return "contract.mint(raw_code).call().await;";
        if (i == 5)  return "ethers::types::Bytes::from(input);";
        if (i == 6)  return "let wallet = LocalWallet::new(&amp;mut rng);";
        if (i == 7)  return "let client = SignerMiddleware::new(p,w);";
        if (i == 8)  return "let receipt = pending.await?.unwrap();";
        if (i == 9)  return "println!(&quot;minted: {:?}&quot;, token_id);";
        if (i == 10) return "let gas = provider.estimate_gas(&amp;tx);";
        return "signer.sign_transaction(&amp;mut tx).await;";
    }

    function _bytecodeLine(uint8 i) internal pure returns (string memory) {
        if (i == 0)  return "0x60806040523480156100105760008081fd";
        if (i == 1)  return "0x5b6000546001600160a01b031633146100";
        if (i == 2)  return "0x60405162461bcd60e51b815260040161";
        if (i == 3)  return "0x6000356001600160e01b0319167f7f3a";
        if (i == 4)  return "0x9c2e4f00000000000000000000000000";
        if (i == 5)  return "0x5f3560e01c80634f6ccce714610059";
        if (i == 6)  return "0x608060405234801561001057600080fd";
        if (i == 7)  return "0x5b600080546001600160a01b038316";
        if (i == 8)  return "0x4e6f7420617574686f72697a656400";
        if (i == 9)  return "0x6080604052600080546001600160a0";
        if (i == 10) return "0x1b8019156100235760008082fd5b50";
        return "0x5f3560e01c8063a22cb46514610088";
    }

    // ---------------------------------------------------------------
    //  BUILD — split to avoid stack too deep
    // ---------------------------------------------------------------

    function build(uint256 tokenId, TraitGen.Traits memory t)
        internal pure returns (string memory)
    {
        return string(abi.encodePacked(
            _buildTop(tokenId, t),
            _buildBottom(tokenId, t)
        ));
    }

    function _buildTop(uint256 tokenId, TraitGen.Traits memory t)
        internal pure returns (string memory)
    {
        bytes32 seed   = keccak256(abi.encodePacked(tokenId, "svg"));
        string memory color  = TraitGen.colorHex(t.textColor);
        string memory bg     = TraitGen.bgHex(t.background);
        string memory status = TraitGen.statusName(t.status);
        string memory lang   = TraitGen.languageName(t.language);

        return string(abi.encodePacked(
            _header(bg),
            _scanlines(),
            _title(tokenId, color, status),
            _lines(t, seed, color, lang)
        ));
    }

    function _buildBottom(uint256 tokenId, TraitGen.Traits memory t)
        internal pure returns (string memory)
    {
        string memory color  = TraitGen.colorHex(t.textColor);
        string memory status = TraitGen.statusName(t.status);
        string memory err    = TraitGen.errorName(t.errorType);

        return string(abi.encodePacked(
            _statusBar(color, status, err, tokenId),
            _cursor(color, t.lineCount),
            "</svg>"
        ));
    }

    // ---------------------------------------------------------------
    //  SVG COMPONENTS
    // ---------------------------------------------------------------

    function _header(string memory bg) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" ',
            'viewBox="0 0 500 500" width="500" height="500" ',
            'style="font-family:\'Courier New\',monospace">',
            
            '<rect width="500" height="500" fill="', bg, '"/>',
            '<rect width="500" height="500" fill="none" ',
            'stroke="#003300" stroke-width="8" rx="4"/>'
        ));
    }

    function _scanlines() internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<pattern id="scan" width="1" height="4" patternUnits="userSpaceOnUse">',
            '<rect width="1" height="1" fill="rgba(0,0,0,0.15)"/>',
            '</pattern>',
            '<rect width="500" height="500" fill="url(#scan)" opacity="0.4"/>'
        ));
    }

    function _title(
        uint256 tokenId,
        string memory color,
        string memory status
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="0" y="0" width="500" height="28" fill="rgba(255,255,255,0.05)"/>',
            '<text x="10" y="18" font-family="monospace" fill="', color,
            '" font-size="11" opacity="0.8">',
            'GSTR-', _pad(tokenId), '  [', status, ']  /dev/ghost/session',
            '</text>',
            '<line x1="0" y1="28" x2="500" y2="28" stroke="', color,
            '" stroke-width="0.5" opacity="0.4"/>'
        ));
    }

    function _lines(
        TraitGen.Traits memory t,
        bytes32 seed,
        string memory color,
        string memory lang
    ) internal pure returns (string memory) {
        string memory result = "";
        uint256 yStart = 52;
        uint256 lineH  = 34; // increased spacing — 12 lines fit cleanly

        for (uint8 i = 0; i < t.lineCount; i++) {
            string memory line = getLine(t.language, seed, i);
            uint256 y = yStart + (i * lineH);
            string memory opacity = i == 0 ? "1" : i == 1 ? "0.9" : "0.7";

            result = string(abi.encodePacked(
                result,
                '<text x="12" y="', _str(y), '" font-family="monospace" fill="', color,
                '" font-size="12" opacity="', opacity, '">',
                '<tspan opacity="0.4">&gt; </tspan>',
                line,
                '</text>'
            ));
        }

        // Language badge top right — fixed position avoids text-anchor encoding issue
        result = string(abi.encodePacked(
            result,
            '<text x="410" y="18" font-family="monospace" fill="', color,
            '" font-size="10" opacity="0.5">', lang, '</text>'
        ));

        return result;
    }

    function _statusBar(
        string memory color,
        string memory status,
        string memory err,
        uint256 tokenId
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<rect x="0" y="472" width="500" height="28" fill="rgba(255,255,255,0.05)"/>',
            '<line x1="0" y1="472" x2="500" y2="472" stroke="', color,
            '" stroke-width="0.5" opacity="0.4"/>',
            '<text x="10" y="490" font-family="monospace" fill="', color,
            '" font-size="10" opacity="0.7">',
            'ERR:', err, '  ID:', _pad(tokenId),
            '</text>',
            '<text x="360" y="490" font-family="monospace" fill="', color,
            '" font-size="10" opacity="0.7">',
            status, '@ghost</text>'
        ));
    }

    function _cursor(string memory color, uint8 lineCount) internal pure returns (string memory) {
        uint256 y = 52 + (uint256(lineCount) * 34);
        if (y > 460) y = 460;
        return string(abi.encodePacked(
            '<text x="12" y="', _str(y), '" font-family="monospace" fill="', color, '" font-size="12">',
            '<tspan opacity="0.4">&gt; </tspan>',
            '<tspan>&#x2588;</tspan>',
            '</text>'
        ));
    }

    // ---------------------------------------------------------------
    //  HELPERS
    // ---------------------------------------------------------------

    function _str(uint256 v) internal pure returns (string memory) {
        if (v == 0) return "0";
        uint256 temp = v; uint256 d;
        while (temp != 0) { d++; temp /= 10; }
        bytes memory buf = new bytes(d);
        while (v != 0) { d--; buf[d] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return string(buf);
    }

    function _pad(uint256 v) internal pure returns (string memory) {
        string memory s = _str(v);
        if (v < 10)   return string(abi.encodePacked("000", s));
        if (v < 100)  return string(abi.encodePacked("00",  s));
        if (v < 1000) return string(abi.encodePacked("0",   s));
        return s;
    }
}
