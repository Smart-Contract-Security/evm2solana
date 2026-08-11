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

    IERC20Minimal public xaut;

    address public admin;
    address public distributor;
    bool public paused;
    IERC20Minimal public shareToken;
    address public router;
    IPriceOracle public navOracle;

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

    error LedgerDistributionVaultUnauthorized();
    error LedgerDistributionVaultBadInput();
    error LedgerDistributionVaultPaused();
    error LedgerDistributionVaultInsufficientXaut();
    error LedgerDistributionVaultInsufficientXaue();
    error LedgerDistributionVaultZeroPrice();

    modifier initializer() {
        require(!_initialized && !_initializing, "Already initialized");
        _initializing = true;
        _;
        _initialized = true;
        _initializing = false;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert LedgerDistributionVaultUnauthorized();
        _;
    }

    modifier onlyDistributor() {
        if (msg.sender != distributor) revert LedgerDistributionVaultUnauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert LedgerDistributionVaultPaused();
        _;
    }

    modifier nonReentrant() {
        // Simple reentrancy guard using a storage variable
        uint256 _status = _reentrancyGuard;
        require(_status != 1, "ReentrancyGuard: reentrant call");
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
            revert LedgerDistributionVaultBadInput();
        }

        xaut = IERC20Minimal(xaut_);
        if (shareToken_ != address(0)) {
            shareToken = IERC20Minimal(shareToken_);
            emit ShareTokenUpdated(shareToken_);
        }
        if (router_ != address(0)) {
            router = router_;
            emit RoutingUpdated(router_, shareToken_);
        }
        if (navOracle_ != address(0)) {
            navOracle = IPriceOracle(navOracle_);
            emit NavOracleUpdated(navOracle_);
        }
        distributor = distributor_;
        admin = admin_;

        emit XautTokenUpdated(xaut_);
        emit DistributorUpdated(distributor_);
    }

    function quoteXaueForXautIn(uint256 xautIn) public view returns (uint256 xaueOut) {
        uint256 nav = navOracle.getLatestPrice();
        if (nav == 0) revert LedgerDistributionVaultZeroPrice();
        return FundConvert.assetToShares(xautIn, nav, XAUT_DECIMALS, SHARE_DECIMALS);
    }

    function quoteXautForXaueOut(uint256 xaueOut) public view returns (uint256 xautIn) {
        uint256 nav = navOracle.getLatestPrice();
        if (nav == 0) revert LedgerDistributionVaultZeroPrice();
        return FundConvert.sharesToAsset(xaueOut, nav, XAUT_DECIMALS, SHARE_DECIMALS);
    }

    function deposit(uint256 reqId, uint256 xautAmount) external nonReentrant whenNotPaused {
        if (xautAmount == 0) revert LedgerDistributionVaultBadInput();
        require(xaut.transferFrom(msg.sender, address(this), xautAmount), "ledger-dist: xaut xfer");
        emit Deposited(msg.sender, reqId, xautAmount);
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
        emit XaueMinted(msg.sender, reqId, xautAmount, xaueMinted);
    }

    /// @notice Distributor sends `xautOut` XAUT to recipient. `reqId` for off-chain order matching only.
    function payout(uint256 reqId, address recipient, uint256 xautOut)
        external
        nonReentrant
        whenNotPaused
        onlyDistributor
    {
        if (recipient == address(0) || xautOut == 0) revert LedgerDistributionVaultBadInput();
        if (xaut.balanceOf(address(this)) < xautOut) revert LedgerDistributionVaultInsufficientXaut();

        require(xaut.transfer(recipient, xautOut), "ledger-dist: xaut xfer");
        emit PaidOut(msg.sender, reqId, recipient, xautOut);
    }

    /// @notice Distributor pays XAUE; mints shortfall from vault XAUT through Agent Router when needed.
    function payoutXaue(uint256 reqId, address recipient, uint256 xaueOut)
        external
        nonReentrant
        whenNotPaused
        onlyDistributor
    {
        if (recipient == address(0) || xaueOut == 0) revert LedgerDistributionVaultBadInput();
        if (address(shareToken) == address(0)) revert LedgerDistributionVaultBadInput();

        uint256 bal = shareToken.balanceOf(address(this));
        if (bal < xaueOut) {
            if (router == address(0)) revert LedgerDistributionVaultInsufficientXaue();
            uint256 shortfall = xaueOut - bal;
            uint256 xautIn = quoteXautForXaueOut(shortfall);
            _mintXaueViaRouter(xautIn);
        }
        if (shareToken.balanceOf(address(this)) < xaueOut) revert LedgerDistributionVaultInsufficientXaue();

        require(shareToken.transfer(recipient, xaueOut), "ledger-dist: xaue xfer");
        emit PaidOutXaue(msg.sender, reqId, recipient, xaueOut);
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert LedgerDistributionVaultBadInput();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    function setDistributor(address newDistributor) external onlyAdmin {
        if (newDistributor == address(0)) revert LedgerDistributionVaultBadInput();
        distributor = newDistributor;
        emit DistributorUpdated(newDistributor);
    }

    function setXautToken(address xaut_) external onlyAdmin {
        if (xaut_ == address(0)) revert LedgerDistributionVaultBadInput();
        xaut = IERC20Minimal(xaut_);
        emit XautTokenUpdated(xaut_);
    }

    function setShareToken(address shareToken_) external onlyAdmin {
        if (shareToken_ == address(0)) revert LedgerDistributionVaultBadInput();
        shareToken = IERC20Minimal(shareToken_);
        emit ShareTokenUpdated(shareToken_);
    }

    function setRouting(address router_, address shareToken_, address navOracle_) external onlyAdmin {
        if (router_ == address(0) || shareToken_ == address(0) || navOracle_ == address(0)) {
            revert LedgerDistributionVaultBadInput();
        }
        router = router_;
        shareToken = IERC20Minimal(shareToken_);
        navOracle = IPriceOracle(navOracle_);
        emit RoutingUpdated(router_, shareToken_);
        emit NavOracleUpdated(navOracle_);
    }

    function pause() external onlyAdmin {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function rescueERC20(address token, address to, uint256 amount) external onlyAdmin {
        if (to == address(0)) revert LedgerDistributionVaultBadInput();
        if ((token == address(xaut) || token == address(shareToken)) && !paused) {
            revert LedgerDistributionVaultPaused();
        }
        require(IERC20Minimal(token).transfer(to, amount), "ledger-dist: rescue");
        emit RescueToken(token, to, amount);
    }

    function _mintXaueViaRouter(uint256 xautAmount) internal returns (uint256 shareMinted) {
        if (xautAmount == 0) revert LedgerDistributionVaultBadInput();
        if (router == address(0)) revert LedgerDistributionVaultBadInput();
        if (xaut.balanceOf(address(this)) < xautAmount) revert LedgerDistributionVaultInsufficientXaut();

        _approveIfNeeded(xaut, router, xautAmount);
        uint256 beforeBal = shareToken.balanceOf(address(this));
        IRouter(router).mint(xautAmount, 0);
        shareMinted = shareToken.balanceOf(address(this)) - beforeBal;
    }

    function _approveIfNeeded(IERC20Minimal token, address spender, uint256 amount) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        if (currentAllowance < amount) {
            require(token.approve(spender, type(uint256).max), "ledger-dist: approve");
        }
    }

    // UUPS upgrade authorization removed – Solang does not support proxy patterns natively.
    // Upgradeability on Solana is handled via program upgrade authority, not via delegatecall proxies.
}