// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal ERC20 interface. Works with tokens that return bool or no value.
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Minimal Morpho Blue interface needed for this strategy.
interface IMorpho {
    struct MarketParams {
        address loanToken;       // apxUSD
        address collateralToken; // sDOLA
        address oracle;
        address irm;
        uint256 lltv;
    }

    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes calldata data
    ) external;

    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 sharesBorrowed);

    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256 assetsRepaid, uint256 sharesRepaid);

    function withdrawCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        address receiver
    ) external;

    function flashLoan(address token, uint256 assets, bytes calldata data) external;

    function position(bytes32 id, address user)
        external
        view
        returns (uint256 supplyShares, uint128 borrowShares, uint128 collateral);

    function idToMarketParams(bytes32 id)
        external
        view
        returns (
            address loanToken,
            address collateralToken,
            address oracle,
            address irm,
            uint256 lltv
        );

    function setAuthorization(address authorized, bool newIsAuthorized) external;

}

library SafeERC20Lite {
    function safeTransfer(IERC20 token, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, amount), "TRANSFER_FAILED");
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 amount) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, amount), "TRANSFER_FROM_FAILED");
    }

    /// @notice Force-approve pattern for USDT-like tokens that require allowance to be zeroed first.
    function forceApprove(IERC20 token, address spender, uint256 amount) internal {
        (bool success, bytes memory returndata) =
            address(token).call(abi.encodeWithSelector(token.approve.selector, spender, amount));

        if (success && (returndata.length == 0 || abi.decode(returndata, (bool)))) return;

        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, 0), "APPROVE_ZERO_FAILED");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, amount), "APPROVE_FAILED");
    }

    function _callOptionalReturn(IERC20 token, bytes memory data, string memory errorMessage) private {
        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, errorMessage);
        if (returndata.length > 0) require(abi.decode(returndata, (bool)), errorMessage);
    }
}

/// @notice One-user helper for opening/closing a Morpho sDOLA collateral / apxUSD debt position.
/// @dev NOT AUDITED. Use tiny test amounts first. Position is owned by `owner`, not by this contract.
contract MorphoApxSdolaFlashLeverage {
    using SafeERC20Lite for IERC20;

    address public immutable owner;
    IMorpho public immutable morpho;
    IERC20 public immutable apxUsd; // Morpho loan token.
    IERC20 public immutable sDola;  // Morpho collateral token.

    // User-specified target market from the Morpho URL.
    bytes32 public constant EXPECTED_MARKET_ID =
        0xa3724490242354d512a92b79d779fa2037845233f0096c9acac36a1033097aee;

    IMorpho.MarketParams public marketParams;
    bytes32 public immutable marketId;

    // 0 = none, 1 = opening with sDOLA flash loan, 2 = closing with apxUSD flash loan.
    uint8 private flashMode;
    bool private entered;

    struct OpenData {
        uint256 initialSdola;
        uint256 apxUsdDebtToBorrow;
        address swapTarget;
        address swapSpender;
        bytes swapApxUsdToSdolaCalldata;
        uint256 minSdolaReceivedFromSwap;
    }

    struct CloseData {
        address swapTarget;
        address swapSpender;
        bytes swapSdolaToApxUsdCalldata;
        uint256 maxSdolaToSell;
        uint256 minApxUsdReceivedFromSwap;
        uint256 minSdolaReturnedToOwner;
    }

    event Opened(
        uint256 initialSdola,
        uint256 flashSdola,
        uint256 apxUsdDebtBorrowed,
        uint256 sdolaReceivedFromSwap
    );
    event Closed(uint256 apxUsdFlashLoan, uint256 sdolaWithdrawn, uint256 apxUsdReceivedFromSwap);
    event Swept(address indexed token, uint256 amount);
    event EthSwept(uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "ONLY_OWNER");
        _;
    }

    modifier nonReentrant() {
        require(!entered, "REENTRANT");
        entered = true;
        _;
        entered = false;
    }

    modifier notExpired(uint256 deadline) {
        require(block.timestamp <= deadline, "EXPIRED");
        _;
    }

    constructor(
        address _morpho,
        address _apxUsd,
        address _sDola,
        address _oracle,
        address _irm,
        uint256 _lltv
    ) {
        require(_morpho != address(0), "BAD_MORPHO");
        require(_apxUsd != address(0), "BAD_APXUSD");
        require(_sDola != address(0), "BAD_SDOLA");
        require(_oracle != address(0), "BAD_ORACLE");

        owner = msg.sender;
        morpho = IMorpho(_morpho);
        apxUsd = IERC20(_apxUsd);
        sDola = IERC20(_sDola);

        IMorpho.MarketParams memory params = IMorpho.MarketParams({
            loanToken: _apxUsd,
            collateralToken: _sDola,
            oracle: _oracle,
            irm: _irm,
            lltv: _lltv
        });

        bytes32 computedId = computeMarketId(params);
        require(computedId == EXPECTED_MARKET_ID, "WRONG_MARKET_PARAMS");

        marketParams = params;
        marketId = computedId;
    }

    receive() external payable {}

    function computeMarketId(IMorpho.MarketParams memory params) public pure returns (bytes32) {
        return keccak256(abi.encode(params));
    }

    /// @notice Open using: user already owns sDOLA -> flash-borrow sDOLA -> supply collateral -> borrow apxUSD -> swap apxUSD to sDOLA -> repay flash loan.
    /// @param initialSdola Amount of your own sDOLA to pull from your wallet. Requires prior sDOLA approval to this contract.
    /// @param flashSdola Amount of sDOLA to flash-borrow from Morpho.
    /// @param apxUsdDebtToBorrow Amount of apxUSD debt to create in Morpho.
    /// @param swapTarget Address to call with swap calldata, e.g. aggregator/router transaction `to` address.
    /// @param swapSpender Address approved to pull apxUSD from this contract, e.g. aggregator allowance spender. Often same as swapTarget, but not always.
    /// @param swapApxUsdToSdolaCalldata Calldata for swapTarget. Output recipient MUST be this contract.
    /// @param minSdolaReceivedFromSwap Minimum sDOLA that the swap must send to this contract.
    /// @param deadline Unix timestamp after which this call reverts.
    function openFlashFromCollateral(
        uint256 initialSdola,
        uint256 flashSdola,
        uint256 apxUsdDebtToBorrow,
        address swapTarget,
        address swapSpender,
        bytes calldata swapApxUsdToSdolaCalldata,
        uint256 minSdolaReceivedFromSwap,
        uint256 deadline
    ) external onlyOwner nonReentrant notExpired(deadline) {
        require(flashMode == 0, "FLASH_BUSY");
        require(initialSdola > 0, "ZERO_INITIAL_SDOLA");
        require(flashSdola > 0, "ZERO_FLASH_SDOLA");
        require(apxUsdDebtToBorrow > 0, "ZERO_DEBT");
        _validateSwap(swapTarget, swapSpender, swapApxUsdToSdolaCalldata);

        sDola.safeTransferFrom(owner, address(this), initialSdola);

        flashMode = 1;
        morpho.flashLoan(
            address(sDola),
            flashSdola,
            abi.encode(
                OpenData({
                    initialSdola: initialSdola,
                    apxUsdDebtToBorrow: apxUsdDebtToBorrow,
                    swapTarget: swapTarget,
                    swapSpender: swapSpender,
                    swapApxUsdToSdolaCalldata: swapApxUsdToSdolaCalldata,
                    minSdolaReceivedFromSwap: minSdolaReceivedFromSwap
                })
            )
        );
        require(flashMode == 0, "FLASH_NOT_CLEARED");
        sDola.forceApprove(address(morpho), 0);

        _sweep(address(apxUsd));
        _sweep(address(sDola));
    }

    /// @notice Close using: flash-borrow apxUSD -> repay all Morpho debt -> withdraw all sDOLA -> swap enough sDOLA to apxUSD -> repay flash loan -> send leftovers to owner.
    /// @param apxUsdFlashLoan Amount of apxUSD to flash-borrow. Use slightly more than current debt to cover accrued interest/rounding.
    /// @param swapTarget Address to call with swap calldata, e.g. aggregator/router transaction `to` address.
    /// @param swapSpender Address approved to pull sDOLA from this contract, e.g. aggregator allowance spender. Often same as swapTarget, but not always.
    /// @param swapSdolaToApxUsdCalldata Calldata for swapTarget. Output recipient MUST be this contract.
    /// @param maxSdolaToSell Maximum sDOLA this contract may approve to the swapSpender for the close swap.
    /// @param minApxUsdReceivedFromSwap Minimum apxUSD that the swap must send to this contract.
    /// @param minSdolaReturnedToOwner Minimum sDOLA left after the close swap; protects you from overselling collateral.
    /// @param deadline Unix timestamp after which this call reverts.
    function closeFlash(
        uint256 apxUsdFlashLoan,
        address swapTarget,
        address swapSpender,
        bytes calldata swapSdolaToApxUsdCalldata,
        uint256 maxSdolaToSell,
        uint256 minApxUsdReceivedFromSwap,
        uint256 minSdolaReturnedToOwner,
        uint256 deadline
    ) external onlyOwner nonReentrant notExpired(deadline) {
        require(flashMode == 0, "FLASH_BUSY");
        require(apxUsdFlashLoan > 0, "ZERO_FLASH_APXUSD");
        require(maxSdolaToSell > 0, "ZERO_MAX_SDOLA_TO_SELL");
        _validateSwap(swapTarget, swapSpender, swapSdolaToApxUsdCalldata);

        flashMode = 2;
        morpho.flashLoan(
            address(apxUsd),
            apxUsdFlashLoan,
            abi.encode(
                CloseData({
                    swapTarget: swapTarget,
                    swapSpender: swapSpender,
                    swapSdolaToApxUsdCalldata: swapSdolaToApxUsdCalldata,
                    maxSdolaToSell: maxSdolaToSell,
                    minApxUsdReceivedFromSwap: minApxUsdReceivedFromSwap,
                    minSdolaReturnedToOwner: minSdolaReturnedToOwner
                })
            )
        );
        require(flashMode == 0, "FLASH_NOT_CLEARED");
        apxUsd.forceApprove(address(morpho), 0);

        _sweep(address(apxUsd));
        _sweep(address(sDola));
    }

    /// @notice Morpho flash-loan callback. Morpho calls this, then pulls repayment via transferFrom.
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        require(msg.sender == address(morpho), "ONLY_MORPHO");

        uint8 mode = flashMode;
        require(mode == 1 || mode == 2, "NO_ACTIVE_FLASH");

        if (mode == 1) {
            OpenData memory decoded = abi.decode(data, (OpenData));
            _handleOpenFlash(assets, decoded);
        } else {
            CloseData memory decoded = abi.decode(data, (CloseData));
            _handleCloseFlash(assets, decoded);
        }

        flashMode = 0;
    }

    function _handleOpenFlash(uint256 flashSdola, OpenData memory decoded) internal {
        uint256 totalSdolaToSupply = decoded.initialSdola + flashSdola;

        sDola.forceApprove(address(morpho), totalSdolaToSupply);
        morpho.supplyCollateral(marketParams, totalSdolaToSupply, owner, "");
        sDola.forceApprove(address(morpho), 0);

        morpho.borrow(marketParams, decoded.apxUsdDebtToBorrow, 0, owner, address(this));

        apxUsd.forceApprove(decoded.swapSpender, decoded.apxUsdDebtToBorrow);
        uint256 beforeSdola = sDola.balanceOf(address(this));
        _callSwap(decoded.swapTarget, decoded.swapApxUsdToSdolaCalldata);
        apxUsd.forceApprove(decoded.swapSpender, 0);

        uint256 sdolaReceived = sDola.balanceOf(address(this)) - beforeSdola;
        require(sdolaReceived >= decoded.minSdolaReceivedFromSwap, "OPEN_SWAP_SLIPPAGE");
        require(sDola.balanceOf(address(this)) >= flashSdola, "NOT_ENOUGH_SDOLA_FOR_FLASH_REPAY");

        // Morpho will pull the flash-borrowed sDOLA after this callback returns.
        sDola.forceApprove(address(morpho), flashSdola);

        emit Opened(decoded.initialSdola, flashSdola, decoded.apxUsdDebtToBorrow, sdolaReceived);
    }

    function _handleCloseFlash(uint256 apxUsdFlashLoan, CloseData memory decoded) internal {
        (, uint128 borrowShares, uint128 collateral) = morpho.position(marketId, owner);
        require(borrowShares > 0, "NO_DEBT");
        require(collateral > 0, "NO_COLLATERAL");

        // Repay all borrow shares. Morpho docs recommend shares for full repayment to avoid rounding issues.
        apxUsd.forceApprove(address(morpho), apxUsdFlashLoan);
        morpho.repay(marketParams, 0, uint256(borrowShares), owner, "");
        apxUsd.forceApprove(address(morpho), 0);

        morpho.withdrawCollateral(marketParams, uint256(collateral), owner, address(this));
        require(sDola.balanceOf(address(this)) >= uint256(collateral), "COLLATERAL_NOT_RECEIVED");
        require(decoded.maxSdolaToSell <= sDola.balanceOf(address(this)), "MAX_SELL_GT_BALANCE");

        sDola.forceApprove(decoded.swapSpender, decoded.maxSdolaToSell);
        uint256 beforeApxUsd = apxUsd.balanceOf(address(this));
        _callSwap(decoded.swapTarget, decoded.swapSdolaToApxUsdCalldata);
        sDola.forceApprove(decoded.swapSpender, 0);

        uint256 apxUsdReceived = apxUsd.balanceOf(address(this)) - beforeApxUsd;
        require(apxUsdReceived >= decoded.minApxUsdReceivedFromSwap, "CLOSE_SWAP_SLIPPAGE");
        require(apxUsd.balanceOf(address(this)) >= apxUsdFlashLoan, "NOT_ENOUGH_APXUSD_FOR_FLASH_REPAY");
        require(sDola.balanceOf(address(this)) >= decoded.minSdolaReturnedToOwner, "TOO_MUCH_SDOLA_SOLD");

        // Morpho will pull the flash-borrowed apxUSD after this callback returns.
        apxUsd.forceApprove(address(morpho), apxUsdFlashLoan);

        emit Closed(apxUsdFlashLoan, uint256(collateral), apxUsdReceived);
    }

    function _validateSwap(address target, address spender, bytes calldata swapCalldata) internal pure {
        require(target != address(0), "BAD_SWAP_TARGET");
        require(spender != address(0), "BAD_SWAP_SPENDER");
        require(swapCalldata.length > 0, "EMPTY_SWAP");
    }

    function _callSwap(address target, bytes memory swapCalldata) internal {
        (bool ok, bytes memory returndata) = target.call(swapCalldata);
        if (!ok) {
            if (returndata.length > 0) {
                assembly {
                    let returndataSize := mload(returndata)
                    revert(add(32, returndata), returndataSize)
                }
            }
            revert("SWAP_FAILED");
        }
    }

    function _sweep(address tokenAddress) internal {
        IERC20 token = IERC20(tokenAddress);
        uint256 bal = token.balanceOf(address(this));
        if (bal > 0) {
            token.safeTransfer(owner, bal);
            emit Swept(tokenAddress, bal);
        }
    }

    function rescueToken(address tokenAddress) external onlyOwner nonReentrant {
        _sweep(tokenAddress);
    }

    function rescueETH() external onlyOwner nonReentrant {
        uint256 bal = address(this).balance;
        require(bal > 0, "NO_ETH");
        (bool ok,) = owner.call{value: bal}("");
        require(ok, "ETH_SEND_FAILED");
        emit EthSwept(bal);
    }
}
