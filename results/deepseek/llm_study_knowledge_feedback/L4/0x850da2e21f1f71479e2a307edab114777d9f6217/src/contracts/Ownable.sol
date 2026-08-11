import {AccountMeta} from 'solana';

contract Ownable {
    bytes32 internal constant OWNER_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    event AdminChanged(address previousAdmin, address newAdmin);

    address private _ownerAddress;

    @payer(payer)
    @space(48)
    constructor(address payer) {
        assert(OWNER_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
        _setOwner(payer);
    }

    function owner() public view returns (address) {
        return _owner();
    }

    function setOwner(address newOwner) external onlyOwner {
        _setOwner(newOwner);
    }

    function _owner() internal view returns (address) {
        return _ownerAddress;
    }

    function _setOwner(address newOwner) internal {
        emit AdminChanged(_owner(), newOwner);
        _ownerAddress = newOwner;
    }

    function _onlyOwner() internal view {
        require(tx.accounts.dataAccount.key == _owner(), "ARM: Only owner can call this function.");
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }
}