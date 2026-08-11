// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {FundConvert} from "./libraries/FundConvert.sol";

/// @title Ledger distribution vault — XAUT in / XAUT or XAUE out; XAUE via Agent Router mint on demand.
contract LedgerDistributionVault {
    uint8 internal constant XAUT_DECIMALS = 6;
    uint8 internal constant SHARE_DECIMALS = 18;

    address public xaut;
    address public admin;
    address public distributor;
    bool public paused;
    address public shareToken;
    address public router;
    address public navOracle;

    bool private _initialized;
    bool private _initializing;

    event Deposited(address indexed account, uint256 indexed reqId, uint256 xautIn);
    event PaidOut(
        address indexed distributor,
        uint256 indexed reqId,
        address indexed recipient,
        uint256 xautOut
    );
    event PaidOutXaue(
        address indexed distributor,
        uint256 indexed reqId,
        address indexed recipient,
        uint256 xaueOut
    );
    event XaueMinted(
        address indexed distributor,
        uint256 indexed reqId,
        uint256 xautIn,
        uint256 xaueMinted
    );
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event DistributorUpdated(address indexed distributor);
    event XautTokenUpdated(address indexed xaut);
    event ShareTokenUpdated(address indexed shareToken);
    event RoutingUpdated(address indexed router, address indexed shareToken);
    event NavOracleUpdated(address indexed navOracle);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event RescueToken(address indexed token, address indexed to, uint256 amount);
    event Upgraded(address indexed implementation);

    string constant LedgerDistributionVaultUnauthorized = "LedgerDistributionVaultUnauthorized";
    string constant LedgerDistributionVaultBadInput = "LedgerDistributionVaultBadInput";
    string constant LedgerDistributionVaultPaused = "LedgerDistributionVaultPaused";
    string constant LedgerDistributionVaultInsufficientXaut = "LedgerDistributionVaultInsufficientXaut";
    string constant LedgerDistributionVaultInsufficientXaue = "LedgerDistributionVaultInsufficientXaue";
    string constant LedgerDistributionVaultZeroPrice = "LedgerDistributionVaultZeroPrice";

    modifier initializer() {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _initializing = true;
        _;
        _initializing = false;
    }

    modifier onlyAdmin() {
        if (tx.origin != admin) revert(LedgerDistributionVaultUnauthorized);
        _;
    }

    modifier onlyDistributor() {
        if (tx.origin != distributor) revert(LedgerDistributionVaultUnauthorized);
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert(LedgerDistributionVaultPaused);
        _;
    }

    modifier nonReentrant() {
        uint256 _status = _reentrancyGuard;
        require(_status != 1, "Reentrant call");
        _reentrancyGuard = 1;
        _;
        _reentrancyGuard = 0;
    }

    uint256 private _reentrancyGuard;

    function initialize(
        address xaut_,
        address shareToken_,
        address router_,
        address navOracle_,
        address distributor_,
        address admin_
    ) external initializer {
        if (xaut_ == address(0) || distributor_ == address(0) || admin_ == address(0)) {
            revert(LedgerDistributionVaultBadInput);
        }

        xaut = xaut_;
        if (shareToken_ != address(0)) {
            shareToken = shareToken_;
            emit ShareTokenUpdated(shareToken_);
        }
        if (router_ != address(0)) {
            router = router_;
            emit RoutingUpdated(router_, shareToken_);
        }
        if (navOracle_ != address(0)) {
            navOracle = navOracle_;
            emit NavOracleUpdated(navOracle_);
        }
        distributor = distributor_;
        admin = admin_;

        emit XautTokenUpdated(xaut_);
        emit DistributorUpdated(distributor_);
    }

    function quoteXaueForXautIn(uint256 xautIn) public view returns (uint256 xaueOut) {
        uint256 nav = IPriceOracle(navOracle).getLatestPrice();
        if (nav == 0) revert(LedgerDistributionVaultZeroPrice);
        return FundConvert.assetToShares(xautIn, nav, XAUT_DECIMALS, SHARE_DECIMALS);
    }

    function quoteXautForXaueOut(uint256 xaueOut) public view returns (uint256 xautIn) {
        uint256 nav = IPriceOracle(navOracle).getLatestPrice();
        if (nav == 0) revert(LedgerDistributionVaultZeroPrice);
        return FundConvert.sharesToAsset(xaueOut, nav, XAUT_DECIMALS, SHARE_DECIMALS);
    }

    function deposit(uint256 reqId, uint256 xautAmount) external nonReentrant whenNotPaused {
        if (xautAmount == 0) revert(LedgerDistributionVaultBadInput);
        require(IERC20Minimal(xaut).transferFrom(tx.origin, address(this), xautAmount), "ledger-dist: xaut xfer");
        emit Deposited(tx.origin, reqId, xautAmount);
    }

    /// @notice Distributor mints XAUE into vault custody using vault XAUT via Agent Router (caller must be Nav4626-whitelisted).
    function mintXaue(uint256 reqId, uint256 xautAmount)
        external
        nonReentrant
        whenNotPaused
        onlyDistributor
        returns (uint256 xaueMinted)
    {
        xaueMinted = _mintXaueViaRouter(xautAmount);
        emit XaueMinted(tx.origin, reqId, xautAmount, xaueMinted);
    }

    /// @notice Distributor sends `xautOut` XAUT to recipient. `reqId` for off-chain order matching only.
    function payout(uint256 reqId, address recipient, uint256 xautOut)
        external
        nonReentrant
        whenNotPaused
        onlyDistributor
    {
        if (recipient == address(0) || xautOut == 0) revert(LedgerDistributionVaultBadInput);
        if (IERC20Minimal(xaut).balanceOf(address(this)) < xautOut) revert(LedgerDistributionVaultInsufficientXaut);

        require(IERC20Minimal(xaut).transfer(recipient, xautOut), "ledger-dist: xaut xfer");
        emit PaidOut(tx.origin, reqId, recipient, xautOut);
    }

    /// @notice Distributor pays XAUE; mints shortfall from vault XAUT through Agent Router when needed.
    function payoutXaue(uint256 reqId, address recipient, uint256 xaueOut)
        external
        nonReentrant
        whenNotPaused
        onlyDistributor
    {
        if (recipient == address(0) || xaueOut == 0) revert(LedgerDistributionVaultBadInput);
        if (shareToken == address(0)) revert(LedgerDistributionVaultBadInput);

        uint256 bal = IERC20Minimal(shareToken).balanceOf(address(this));
        if (bal < xaueOut) {
            if (router == address(0)) revert(LedgerDistributionVaultInsufficientXaue);
            uint256 shortfall = xaueOut - bal;
            uint256 xautIn = quoteXautForXaueOut(shortfall);
            _mintXaueViaRouter(xautIn);
        }
        if (IERC20Minimal(shareToken).balanceOf(address(this)) < xaueOut) revert(LedgerDistributionVaultInsufficientXaue);

        require(IERC20Minimal(shareToken).transfer(recipient, xaueOut), "ledger-dist: xaue xfer");
        emit PaidOutXaue(tx.origin, reqId, recipient, xaueOut);
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert(LedgerDistributionVaultBadInput);
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    function setDistributor(address newDistributor) external onlyAdmin {
        if (newDistributor == address(0)) revert(LedgerDistributionVaultBadInput);
        distributor = newDistributor;
        emit DistributorUpdated(newDistributor);
    }

    function setXautToken(address xaut_) external onlyAdmin {
        if (xaut_ == address(0)) revert(LedgerDistributionVaultBadInput);
        xaut = xaut_;
        emit XautTokenUpdated(xaut_);
    }

    function setShareToken(address shareToken_) external onlyAdmin {
        if (shareToken_ == address(0)) revert(LedgerDistributionVaultBadInput);
        shareToken = shareToken_;
        emit ShareTokenUpdated(shareToken_);
    }

    function setRouting(address router_, address shareToken_, address navOracle_) external onlyAdmin {
        if (router_ == address(0) || shareToken_ == address(0) || navOracle_ == address(0)) {
            revert(LedgerDistributionVaultBadInput);
        }
        router = router_;
        shareToken = shareToken_;
        navOracle = navOracle_;
        emit RoutingUpdated(router_, shareToken_);
        emit NavOracleUpdated(navOracle_);
    }

    function pause() external onlyAdmin {
        paused = true;
        emit Paused(tx.origin);
    }

    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused(tx.origin);
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyAdmin {
        if (to == address(0)) revert(LedgerDistributionVaultBadInput);
        if ((token == xaut || token == shareToken) && !paused) {
            revert(LedgerDistributionVaultPaused);
        }
        require(IERC20Minimal(token).transfer(to, amount), "ledger-dist: rescue");
        emit RescueToken(token, to, amount);
    }

    function _mintXaueViaRouter(uint256 xautAmount) internal returns (uint256 shareMinted) {
        if (xautAmount == 0) revert(LedgerDistributionVaultBadInput);
        if (router == address(0)) revert(LedgerDistributionVaultBadInput);
        if (IERC20Minimal(xaut).balanceOf(address(this)) < xautAmount) revert(LedgerDistributionVaultInsufficientXaut);

        _approveIfNeeded(xaut, router, xautAmount);
        uint256 beforeBal = IERC20Minimal(shareToken).balanceOf(address(this));
        IRouter(router).mint(xautAmount, 0);
        shareMinted = IERC20Minimal(shareToken).balanceOf(address(this)) - beforeBal;
    }

    function _approveIfNeeded(address token, address spender, uint256 amount) internal {
        uint256 currentAllowance = IERC20Minimal(token).allowance(address(this), spender);
        if (currentAllowance < amount) {
            require(IERC20Minimal(token).approve(spender, type(uint256).max), "ledger-dist: approve");
        }
    }
}