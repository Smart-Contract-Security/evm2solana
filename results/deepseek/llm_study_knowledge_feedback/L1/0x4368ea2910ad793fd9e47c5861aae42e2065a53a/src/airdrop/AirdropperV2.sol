@program_id("AirdropperV2")

import {AccountMeta} from 'solana';

interface SPLToken {
    function transfer(address from, address to, uint64 amount) external;
}

contract AirdropperV2 {
    address private _owner;

    @payer(payer)
    @space(8 + 32)
    constructor(address payer) {
        _owner = payer;
    }

    function airdropTokens(
        address[] calldata recipients,
        uint64[] calldata amounts
    ) external {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");

        uint64 length = uint64(recipients.length);
        address tokenAccount = tx.accounts.tokenAccount.key;
        
        for (uint64 i = 0; i < length; i++) {
            SPLToken(tokenAccount).transfer(
                _owner,
                recipients[i],
                amounts[i]
            );
        }
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _owner = newOwner;
    }
}