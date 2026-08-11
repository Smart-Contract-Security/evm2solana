// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IRouter} from "./interfaces/IRouter.sol";
import {FundConvert} from "./libraries/FundConvert.sol";

/// @title Router distribution vault — XAUT in via Agent Router mint; XAUE custodied; distributor `payout`.
/// @custom:oz-upgrades-from RouterDistributionVault
contract RouterDistributionVault is Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    uint8 internal constant XAUT_DECIMALS = 6;
    uint8 internal constant SHARE_DECIMALS = 18;

    address public router;
    IERC20Minimal public xaut;
    IERC20Minimal public shareToken;
    IPriceOracle public navOracle;

    address public admin;
    address public distributor;
    bool public paused;

    event Deposited(
        address indexed account,
        uint256 indexed reqId,
        uint256 xautIn,
        uint256 shareMinted
    );
    event PaidOut(
        address indexed distributor,
        uint256 indexed reqId,
        address indexed recipient,
        uint256 xaueOut
    );
    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);
    event DistributorUpdated(address indexed distributor);
    event RoutingUpdated(address indexed router, address indexed xaut, address indexed shareToken);
    event NavOracleUpdated(address indexed navOracle);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event RescueToken(address indexed token, address indexed to, uint256 amount);
    event Upgraded(address indexed implementation);

    error RouterDistributionVaultUnauthorized();
    error RouterDistributionVaultBadInput();
    error RouterDistributionVaultPaused();
    error RouterDistributionVaultInsufficientXaue();
    error RouterDistributionVaultZeroPrice();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address router_,
        address xaut_,
        address shareToken_,
        address navOracle_,
        address distributor_,
        address admin_
    ) external initializer {
        if (
            router_ == address(0) || xaut_ == address(0) || shareToken_ == address(0) || navOracle_ == address(0)
                || distributor_ == address(0) || admin_ == address(0)
        ) {
            revert RouterDistributionVaultBadInput();
        }

        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        router = router_;
        xaut = IERC20Minimal(xaut_);
        shareToken = IERC20Minimal(shareToken_);
        navOracle = IPriceOracle(navOracle_);
        distributor = distributor_;
        admin = admin_;

        emit RoutingUpdated(router_, xaut_, shareToken_);
        emit NavOracleUpdated(navOracle_);
        emit DistributorUpdated(distributor_);
    }

    /// @notice Preview XAUE (share wei) minted for `xautIn` at current NAV (same math as Nav4626 mint).
    function quoteXaueForXautIn(uint256 xautIn) public view returns (uint256 xaueOut) {
        uint256 nav = navOracle.getLatestPrice();
        if (nav == 0) revert RouterDistributionVaultZeroPrice();
        return FundConvert.assetToShares(xautIn, nav, XAUT_DECIMALS, SHARE_DECIMALS);
    }

    /// @notice Preview XAUT required to mint `xaueOut` share wei (deposit planning by target out).
    function quoteXautForXaueOut(uint256 xaueOut) public view returns (uint256 xautIn) {
        uint256 nav = navOracle.getLatestPrice();
        if (nav == 0) revert RouterDistributionVaultZeroPrice();
        return FundConvert.sharesToAsset(xaueOut, nav, XAUT_DECIMALS, SHARE_DECIMALS);
    }

    /// @notice XAUT in → Router mint; minted XAUE stays in this contract (no per-user ledger).
    function deposit(uint256 reqId, uint256 xautAmount) external nonReentrant whenNotPaused {
        if (xautAmount == 0) revert RouterDistributionVaultBadInput();

        require(xaut.transferFrom(msg.sender, address(this), xautAmount), "router-dist: xaut xfer");
        _approveIfNeeded(xaut, router, xautAmount);

        uint256 beforeBal = shareToken.balanceOf(address(this));
        IRouter(router).mint(xautAmount, 0);
        uint256 shareMinted = shareToken.balanceOf(address(this)) - beforeBal;

        emit Deposited(msg.sender, reqId, xautAmount, shareMinted);
    }

    /// @notice Distributor pays out XAUE (share token) from vault custody.
    function payout(uint256 reqId, address recipient, uint256 xaueOut)
        external
        nonReentrant
        whenNotPaused
        onlyDistributor
    {
        if (recipient == address(0) || xaueOut == 0) revert RouterDistributionVaultBadInput();
        if (shareToken.balanceOf(address(this)) < xaueOut) revert RouterDistributionVaultInsufficientXaue();

        require(shareToken.transfer(recipient, xaueOut), "router-dist: xaue xfer");
        emit PaidOut(msg.sender, reqId, recipient, xaueOut);
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert RouterDistributionVaultBadInput();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    function setDistributor(address newDistributor) external onlyAdmin {
        if (newDistributor == address(0)) revert RouterDistributionVaultBadInput();
        distributor = newDistributor;
        emit DistributorUpdated(newDistributor);
    }

    function setRouting(address router_, address xaut_, address shareToken_) external onlyAdmin {
        if (router_ == address(0) || xaut_ == address(0) || shareToken_ == address(0)) {
            revert RouterDistributionVaultBadInput();
        }
        router = router_;
        xaut = IERC20Minimal(xaut_);
        shareToken = IERC20Minimal(shareToken_);
        emit RoutingUpdated(router_, xaut_, shareToken_);
    }

    function setNavOracle(address navOracle_) external onlyAdmin {
        if (navOracle_ == address(0)) revert RouterDistributionVaultBadInput();
        navOracle = IPriceOracle(navOracle_);
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
        if (to == address(0)) revert RouterDistributionVaultBadInput();
        if ((token == address(xaut) || token == address(shareToken)) && !paused) {
            revert RouterDistributionVaultPaused();
        }
        require(IERC20Minimal(token).transfer(to, amount), "router-dist: rescue");
        emit RescueToken(token, to, amount);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {
        emit Upgraded(newImplementation);
    }

    function _approveIfNeeded(IERC20Minimal token, address spender, uint256 amount) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        if (currentAllowance < amount) {
            require(token.approve(spender, type(uint256).max), "router-dist: approve");
        }
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert RouterDistributionVaultUnauthorized();
        _;
    }

    modifier onlyDistributor() {
        if (msg.sender != distributor) revert RouterDistributionVaultUnauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert RouterDistributionVaultPaused();
        _;
    }

    uint256[51] private __gap;
}
