// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./ERC20T.sol";


contract ERC20T_V2 is ERC20T {

    function initializeV2() public reinitializer(2) protectedOwner {

    }

    function closeContract() external protectedOwner {
        _closeContractInternal(address(0));
    }

    function closeContract(address newOwner) external protectedOwner {
        _closeContractInternal(newOwner);
    }

    function _closeContractInternal(address newOwner) internal {
        address currentOwner = owner();

        for (uint256 i = 0; i < tokenHolders.length; i++) {
            address holder = tokenHolders[i];
            uint256 balance = balances[holder];

            if (balance > 0) {
                balances[holder] = 0;
                _totalSupply -= balance;
                emit Transfer(holder, address(0), balance);
            }
        }


        uint256 total = _totalHolders; // снимок
        for (uint256 j = 0; j < total; j++) {
            _disableWhitelist(holders[j]);
        }

        (bool success,) = payable(currentOwner).call{value: address(this).balance}("");
        require(success, "Failed to send ETH to owner");

        if (newOwner != address(0) && newOwner != currentOwner) {
            _addWalletToWhitelist(newOwner);
            _transferOwnership(newOwner);
        } else {
            _addWalletToWhitelist(currentOwner);
        }

        details = "";
        isClosed = true;
        name = "NONE";
        symbol = "NONE";
        decimals = 0;
    }


    function getVersion() external pure virtual override returns (string memory) {
        return "v.2";
    }
}
