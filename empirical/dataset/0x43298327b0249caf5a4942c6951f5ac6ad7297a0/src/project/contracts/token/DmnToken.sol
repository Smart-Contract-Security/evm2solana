// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {ERC20} from "solady/src/tokens/ERC20.sol";
import "../dmn/Dmn.sol";
import "../library/RandomLib.sol";
import "./IStartableToken.sol";

/// @notice ERC20/native-object synchronization with DAEMONS/DMN public terminology.
contract DmnToken is Dmn, ERC20, Ownable, IStartableToken {
    error AddressCanNotReceiveDmn();
    error OnlyHook();
    error RandomSeedProviderNotSet();

    uint256 public constant UNIT_PER_DMN = 1e18;
    uint256 public constant INITIAL_SUPPLY = 6_666e18;

    address internal immutable _notMintableAccount;
    uint256 internal _startTime;

    address public hook;
    address public pool;

    constructor(address owner_) {
        _initializeOwner(owner_);
        _mint(owner_, INITIAL_SUPPLY);
        _notMintableAccount = owner_;
    }

    modifier canReceiveDmns(address addr) {
        _checkCanReceiveDmns(addr);
        _;
    }

    modifier onlyHook() {
        _checkHook();
        _;
    }

    function _checkCanReceiveDmns(address addr) internal view {
        if (!_canReceiveDmns(addr)) revert AddressCanNotReceiveDmn();
    }

    function _checkHook() internal view {
        if (msg.sender != hook) revert OnlyHook();
    }

    function name() public pure virtual override returns (string memory) {
        return "DAEMON";
    }

    function symbol() public pure virtual override returns (string memory) {
        return "DAEMON";
    }

    function start(address newPool) external onlyHook {
        if (address(randomSeedProvider) == address(0)) revert RandomSeedProviderNotSet();
        pool = newPool;
        _startTime = block.timestamp;
    }

    function isStarted() public view returns (bool) {
        return pool != address(0);
    }

    function setHook(address newHook) external onlyOwner {
        hook = newHook;
    }

    function setRandomSeedProvider(address randomSeedProvider) public onlyOwner {
        _setRandomSeedProvider(randomSeedProvider);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        super._afterTokenTransfer(from, to, amount);
        if (pool == address(0)) return;
        _onTokenTransfer(from, to, amount, createRandom());
    }

    function _onTokenTransfer(address from, address to, uint256 amount, Random memory random) internal virtual {
        if (pool == address(0)) return;

        if (from == pool && to != address(0)) {
            if (_notMintableAccount == to) return;
            require(isStarted(), "not started");
            _mintDmns(to, amount / UNIT_PER_DMN, random);
            return;
        }

        uint256 fromMaxAllowed = balanceOf(from) / UNIT_PER_DMN;
        uint256 fromCount = OwnerDmnsCount(from);
        uint256 fromRemoveCount = fromCount > fromMaxAllowed ? fromCount - fromMaxAllowed : 0;

        uint256 toMaxAllowed = balanceOf(to) / UNIT_PER_DMN;
        uint256 toCount = OwnerDmnsCount(to);
        uint256 toReceiveAllowed = toCount < toMaxAllowed ? toMaxAllowed - toCount : 0;

        if (fromRemoveCount == 0) return;

        if (!_canReceiveDmns(to)) toReceiveAllowed = 0;

        uint256 moveQty = fromRemoveCount < toReceiveAllowed ? fromRemoveCount : toReceiveAllowed;
        if (moveQty > 0) _moveDmns(from, to, moveQty);

        _burnDmns(from, fromRemoveCount - moveQty);
    }

    function _mintDmns(address user, uint256 qty, Random memory random) internal virtual {
        for (uint256 i = 0; i < qty; ++i) {
            _mintDmn(user, random);
        }
    }

    function _burnDmns(address user, uint256 qty) internal virtual {
        for (uint256 i = 0; i < qty; ++i) {
            uint256 count = OwnerDmnsCount(user);
            if (count == 0) break;
            uint256 objectId = this.OwnerDmn(user, count - 1).id;
            _burnDmn(user, objectId);
        }
    }

    function _moveDmns(address from, address to, uint256 qty) internal virtual canReceiveDmns(to) {
        for (uint256 i = 0; i < qty; ++i) {
            uint256 count = OwnerDmnsCount(from);
            if (count == 0) break;
            uint256 objectId = this.OwnerDmn(from, count - 1).id;
            _transferDmn(from, to, objectId);
        }
    }

    function _canReceiveDmns(address addr) internal view virtual returns (bool) {
        return addr != pool && addr != address(0);
    }

    function _givePermit2InfiniteAllowance() internal pure override returns (bool) {
        return false;
    }

    function _validateDmnRecipient(address to) internal view virtual override {
        if (!_canReceiveDmns(to)) revert AddressCanNotReceiveDmn();
    }

    function _afterDmnTransferred(address from, address to, uint256) internal override {
        _transfer(from, to, UNIT_PER_DMN);
    }

    function _afterDmnsListTransferred(address from, address to, uint256[] calldata objectIds) internal override {
        _transfer(from, to, UNIT_PER_DMN * objectIds.length);
    }
}
