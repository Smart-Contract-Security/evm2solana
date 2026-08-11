import {AccountInfo} from 'solana';

abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address previousOwner, address newOwner);

    constructor() {
        _transferOwnership(tx.accounts.dataAccount.key);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function _checkOwner() internal view {
        require(owner() == tx.accounts.dataAccount.key, "Ownable: caller is not the owner");
    }

    function renounceOwnership() public onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}