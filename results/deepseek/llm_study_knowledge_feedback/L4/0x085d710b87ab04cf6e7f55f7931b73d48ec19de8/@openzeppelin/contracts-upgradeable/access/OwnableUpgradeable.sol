// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (access/Ownable.sol)

abstract contract OwnableUpgradeable {
    address private _owner;

    bool private _initializing;
    bool private _initialized;

    event OwnershipTransferred(address previousOwner, address newOwner);

    modifier onlyInitializing() {
        require(_initializing, "Ownable: not initializing");
        _;
    }

    modifier initializer() {
        require(!_initialized, "Ownable: already initialized");
        _initializing = true;
        _;
        _initializing = false;
        _initialized = true;
    }

    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
        _transferOwnership(tx.accounts.dataAccount.key);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == tx.accounts.dataAccount.key, "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    uint256[49] private __gap;
}