// SPDX-License-Identifier: MIT

import {IRouter} from "./interfaces/IRouter.sol";
import {FundConvert} from "./libraries/FundConvert.sol";

interface IPriceOracle {
    function getLatestPrice() external view returns (uint64);
}

interface IERC20Minimal {
    function transferFrom(address from, address to, uint64 amount) external returns (bool);
    function transfer(address to, uint64 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint64);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
}

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

    event Deposited(address indexed account, uint64 indexed reqId, uint64 xautIn);
    event PaidOut(
        address indexed distributor,
        uint64 indexed reqId,
        address indexed recipient,
        uint64 xautOut
    );
    event PaidOutXaue(
        address indexed distributor,
        uint64 indexed reqId,
        address indexed recipient,
        uint64 xaueOut
    );
    event XaueMinted(
        address indexed distributor,
        uint64 indexed reqId,
        uint64 xautIn,
        uint64 xaueMinted
    );
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event DistributorUpdated(address indexed distributor);
    event XautTokenUpdated(address indexed xaut);
    event ShareTokenUpdated(address indexed shareToken);
    event RoutingUpdated(address indexed router, address indexed shareToken);
    event NavOracleUpdated(address indexed navOracle);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event RescueToken(address indexed token, address indexed to, uint64 amount);
    event Upgraded(address indexed implementation);

    bool private initialized;

    function initialize(
        address xaut_,
        address shareToken_,
        address router_,
        address navOracle_,
        address distributor_,
        address admin_
    ) external {
        require(!initialized, "Already initialized");
        if (xaut_ == address(0) || distributor_ == address(0) || admin_ == address(0)) {
            revert("Bad input");
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

        initialized = true;
    }

    function quoteXaueForXautIn(uint64 xautIn) public view returns (uint64 xaueOut) {
        uint64 nav = IPriceOracle(navOracle).getLatestPrice();
        if (nav == 0) revert("Zero price");
        return FundConvert.assetToShares(xautIn, nav, XAUT_DECIMALS, SHARE_DECIMALS);
    }

    function quoteXautForXaueOut(uint64 xaueOut) public view returns (uint64 xautIn) {
        uint64 nav = IPriceOracle(navOracle).getLatestPrice();
        if (nav == 0) revert("Zero price");
        return FundConvert.sharesToAsset(xaueOut, nav, XAUT_DECIMALS, SHARE_DECIMALS);
    }

    function deposit(uint64 reqId, uint64 xautAmount) external nonReentrant whenNotPaused {
        if (xautAmount == 0) revert("Bad input");
        require(IERC20Minimal(xaut).transferFrom(tx.accounts.dataAccount.key, address(this), xautAmount), "ledger-dist: xaut xfer");
        emit Deposited(tx.accounts.dataAccount.key, reqId, xautAmount);
    }

    /// @notice Distributor mints XAUE into vault custody using vault XAUT via Agent Router (caller must be Nav4626-whitelisted).
    function mintXaue(uint64 reqId, uint64 xautAmount)
        external
        nonReentrant
        whenNotPaused
        onlyDistributor
        returns (uint64 xaueMinted)
    {
        xaueMinted = _mintXaueViaRouter(xautAmount);
        emit XaueMinted(tx.accounts.dataAccount.key, reqId, xautAmount, xaueMinted);
    }

    /// @notice Distributor sends `xautOut` XAUT to recipient. `reqId` for off-chain order matching only.
    function payout(uint64 reqId, address recipient, uint64 xautOut)
        external
        nonReentrant
        whenNotPaused
        onlyDistributor
    {
        if (recipient == address(0) || xautOut == 0) revert("Bad input");
        if (IERC20Minimal(xaut).balanceOf(address(this)) < xautOut) revert("Insufficient Xaut");

        require(IERC20Minimal(xaut).transfer(recipient, xautOut), "ledger-dist: xaut xfer");
        emit PaidOut(tx.accounts.dataAccount.key, reqId, recipient, xautOut);
    }

    /// @notice Distributor pays XAUE; mints shortfall from vault XAUT through Agent Router when needed.
    function payoutXaue(uint64 reqId, address recipient, uint64 xaueOut)
        external
        nonReentrant
        whenNotPaused
        onlyDistributor
    {
        if (recipient == address(0) || xaueOut == 0) revert("Bad input");
        if (shareToken == address(0)) revert("Bad input");

        uint64 bal = IERC20Minimal(shareToken).balanceOf(address(this));
        if (bal < xaueOut) {
            if (router == address(0)) revert("Insufficient Xaue");
            uint64 shortfall = xaueOut - bal;
            uint64 xautIn = quoteXautForXaueOut(shortfall);
            _mintXaueViaRouter(xautIn);
        }
        if (IERC20Minimal(shareToken).balanceOf(address(this)) < xaueOut) revert("Insufficient Xaue");

        require(IERC20Minimal(shareToken).transfer(recipient, xaueOut), "ledger-dist: xaue xfer");
        emit PaidOutXaue(tx.accounts.dataAccount.key, reqId, recipient, xaueOut);
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert("Bad input");
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    function setDistributor(address newDistributor) external onlyAdmin {
        if (newDistributor == address(0)) revert("Bad input");
        distributor = newDistributor;
        emit DistributorUpdated(newDistributor);
    }

    function setXautToken(address xaut_) external onlyAdmin {
        if (xaut_ == address(0)) revert("Bad input");
        xaut = xaut_;
        emit XautTokenUpdated(xaut_);
    }

    function setShareToken(address shareToken_) external onlyAdmin {
        if (shareToken_ == address(0)) revert("Bad input");
        shareToken = shareToken_;
        emit ShareTokenUpdated(shareToken_);
    }

    function setRouting(address router_, address shareToken_, address navOracle_) external onlyAdmin {
        if (router_ == address(0) || shareToken_ == address(0) || navOracle_ == address(0)) {
            revert("Bad input");
        }
        router = router_;
        shareToken = shareToken_;
        navOracle = navOracle_;
        emit RoutingUpdated(router_, shareToken_);
        emit NavOracleUpdated(navOracle_);
    }

    function pause() external onlyAdmin {
        paused = true;
        emit Paused(tx.accounts.dataAccount.key);
    }

    function unpause() external onlyAdmin {
        paused = false;
        emit Unpaused(tx.accounts.dataAccount.key);
    }

    function rescueERC20(address token, address to, uint64 amount) external onlyAdmin {
        if (to == address(0)) revert("Bad input");
        if ((token == xaut || token == shareToken) && !paused) {
            revert("Paused");
        }
        require(IERC20Minimal(token).transfer(to, amount), "ledger-dist: rescue");
        emit RescueToken(token, to, amount);
    }

    function _mintXaueViaRouter(uint64 xautAmount) internal returns (uint64 shareMinted) {
        if (xautAmount == 0) revert("Bad input");
        if (router == address(0)) revert("Bad input");
        if (IERC20Minimal(xaut).balanceOf(address(this)) < xautAmount) revert("Insufficient Xaut");

        _approveIfNeeded(xaut, router, xautAmount);
        uint64 beforeBal = IERC20Minimal(shareToken).balanceOf(address(this));
        IRouter(router).mint(xautAmount, 0);
        shareMinted = IERC20Minimal(shareToken).balanceOf(address(this)) - beforeBal;
    }

    function _approveIfNeeded(address token, address spender, uint64 amount) internal {
        uint64 currentAllowance = IERC20Minimal(token).allowance(address(this), spender);
        if (currentAllowance < amount) {
            require(IERC20Minimal(token).approve(spender, type(uint64).max), "ledger-dist: approve");
        }
    }

    modifier onlyAdmin() {
        if (tx.accounts.dataAccount.key != admin) revert("Unauthorized");
        _;
    }

    modifier onlyDistributor() {
        if (tx.accounts.dataAccount.key != distributor) revert("Unauthorized");
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert("Paused");
        _;
    }

    modifier nonReentrant() {
        _;
    }

    uint256[51] private __gap;
}