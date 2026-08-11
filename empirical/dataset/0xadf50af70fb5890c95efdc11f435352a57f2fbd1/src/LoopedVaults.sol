// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@morpho/interfaces/IMorpho.sol";
import {SharesMathLib} from "@morpho/libraries/SharesMathLib.sol";
import {MorphoLib} from "@morpho/libraries/periphery/MorphoLib.sol";
import {MarketParamsLib} from "@morpho/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "@morpho/libraries/periphery/MorphoBalancesLib.sol";
import "@pendle/interfaces/IPActionMiscV3.sol";
import "@pendle/interfaces/IPActionSwapPTV3.sol";
import "@pendle/interfaces/IPPrincipalToken.sol";
import "./interfaces/IPriceFeed.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

struct MorphoLoop {
    MarketParams marketParams;
    uint256 amountToSupply;
    uint256 amountToBorrow;
    address pendleMarket;
    address SY;
    TokenInput input;
    TokenInput extraInput; // in case borrowed != asset()
}

struct RepayPosition {
    MarketParams marketParams;
    uint256 amountToRepay;
    uint256 amountToWithdraw;
    address pendleMarket;
    address YT;
    TokenOutput output;
    TokenOutput extraOutput;
    uint256 swapToBorrowed;
    uint256 swapToAsset; // in case asset != borrow, we need to do 2 separate swaps
}

/* 
    NOTES ABOUT THE CONTRACT:
        - At any time, withdraws can only be performed for only the amount of idle funds that there are. Contract does not guarantee
            maintaining any amount of idle funds. As unwinding positions before PT expiry would result in extra losses due to fees
            users should mainly expect to withdraw around PT maturity dates
        - Only works with PT tokens as collateral, in order to keep the contract as simple as possible 
        - We do not use limit orders, as very rarely they're worth it (too big of a spread on them) and it would unnecessarily increase the code complexity

*/

contract LoopedVault is ERC4626Upgradeable, OwnableUpgradeable, ReentrancyGuard {
    using Math for uint256;
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;

    address public morpho;

    uint256 public lastTotalAssets;
    uint256 public lastUpdate;
    uint256 public updateInterval;

    uint256 public protocolFee;
    uint256 public timelockPeriod;

    address public pendleRouter;

    address public pricefeed;
    address public feeRecipient;
    address public allocator;

    uint256 public positionMaxSlippage;
    uint256 public constant SLIPPAGE_PRECISION = 10_000;

    uint256 public vestingInterest;
    uint256 public vestingDuration;
    uint256 public depositCap;

    uint8 public constant MAX_NUMBER_MARKETS = 15;

    mapping(Id => bool) public isMarketEnabled;
    mapping(Id => uint256) public index;
    mapping(Id => uint256) public scheduledAdd;
    MarketParams[] public morphoPositions;

    constructor() {
        _disableInitializers();
    }

    function initiailize(
        address _token,
        address _pendleRouter,
        address _morpho,
        address _feeRecipient,
        address _allocator,
        address _pricefeed
    ) external initializer {
        __Ownable_init(msg.sender);
        __ERC4626_init(IERC20(_token));

        pendleRouter = _pendleRouter;
        morpho = _morpho;
        feeRecipient = _feeRecipient;
        allocator = _allocator;
        pricefeed = _pricefeed;
        lastUpdate = block.timestamp;
        vestingDuration = 1 hours;
        updateInterval = 6 hours;
        depositCap = 1_000_000e6; // $1m
        positionMaxSlippage = 100;
        protocolFee = 800;
    }

    modifier updateTotalAssets() {
        _updateTotalAssets();
        _;
    }

    modifier onlyMorpho() {
        require(msg.sender == morpho, "can only be called by Morpho");
        _;
    }

    modifier onlyAllocator() {
        require(msg.sender == allocator, "can only be called by Allocator");
        _;
    }

    /// An edge case here would be if a PT-XYZ/DAI position is underwater,
    /// as the oracle used by Maker uses hardcoded values.
    /// This would make the position result negative for the vault, when in reality,
    /// The lowest value it could have is 0.
    /// Though, in case that happens, there'd be >$100m DAI lost in bad debt, so that's probably a bigger problem

    // ~70k gas per position
    function _updateTotalAssets() public {
        if (block.timestamp - lastUpdate >= updateInterval) {
            uint256 totalPositionsValue;

            for (uint256 i; i < morphoPositions.length; i++) {
                MarketParams memory mp = morphoPositions[i];
                Id id = mp.id();

                uint256 collateral = IMorpho(morpho).collateral(id, address(this));
                if (collateral == 0) continue;

                uint256 collateralPrice = IPriceFeed(pricefeed).getPrice(mp.collateralToken);
                uint256 collateralAmount = collateral * collateralPrice / (10 ** IERC20Metadata(mp.collateralToken).decimals());

                uint256 borrowed = IMorpho(morpho).expectedBorrowAssets(mp, address(this));

                uint256 borrowedPrice = IPriceFeed(pricefeed).getPrice(mp.loanToken);
                uint256 borrowedAmount = borrowed * borrowedPrice / (10 ** IERC20Metadata(mp.loanToken).decimals());

                // If a position is in bad debt, we don't want it to negatively affect the totalAssets
                // The lowest value a position can have is 0.
                if (collateralAmount < borrowedAmount) continue;
                else totalPositionsValue += collateralAmount - borrowedAmount;
            }

            uint256 usdcPrice = IPriceFeed(pricefeed).getPrice(asset());
            uint256 _idleBalance = idleBalance();

            // The following below might revert if the total collateral is less than the total borrowed.
            // This would mean that the positions are in bad debt and should be liquidated. Reverting is OK in that case.

            uint256 newTotalAssets = totalPositionsValue * (10 ** IERC20Metadata(asset()).decimals()) / usdcPrice + _idleBalance;

            if (newTotalAssets > lastTotalAssets) {
                vestingInterest = newTotalAssets - lastTotalAssets;
                uint256 fee = protocolFee * vestingInterest / 10_000;

                uint256 feeShares = _convertToShares(fee, Math.Rounding.Floor);
                _mint(feeRecipient, feeShares);

                vestingInterest -= fee;
            } else {
                vestingInterest = 0;
            }

            lastTotalAssets = newTotalAssets;
            lastUpdate = block.timestamp;
        }
    }

    // 1. Supplies collateral to Morpho
    // 2. In the callback, borrows.
    // 3. Swaps the borrowed funds for the collateral token
    // 3.1 If the borrowed asset is not the underlying asset, does a second swap from the underlying asset
    // 4. Any excess funds are supplied as extra collateral

    function loopToMorpho(MorphoLoop calldata params) external updateTotalAssets onlyAllocator nonReentrant {
        Id id = params.marketParams.id();
        require(isMarketEnabled[id], "market must be enabled");

        bytes memory data = abi.encode(params);

        IMorpho(morpho).supplyCollateral(params.marketParams, params.amountToSupply, address(this), data);
    }

    function onMorphoSupplyCollateral(uint256 assets, bytes calldata data) external onlyMorpho {
        MorphoLoop memory ml = abi.decode(data, (MorphoLoop));

        uint256 usdcBalPre = idleBalance();

        IMorpho(morpho).borrow(ml.marketParams, ml.amountToBorrow, 0, address(this), address(this));

        address collateralToken = ml.marketParams.collateralToken;
        address borrowToken = ml.marketParams.loanToken;
        uint256 amountOut;

        IERC20(borrowToken).approve(pendleRouter, type(uint256).max);

        /// Here input can actually be any amount provided by the bot
        /// @dev so if we have dust leftover DAI, we can actually just use it with the next mint
        uint256 syOut = IPActionMiscV3(pendleRouter).mintSyFromToken(address(this), ml.SY, 0, ml.input);

        if (borrowToken != asset()) {
            // In cases where borrowed token is not asset, we'll need to do 2 swaps
            IERC20(asset()).approve(pendleRouter, type(uint256).max);

            syOut += IPActionMiscV3(pendleRouter).mintSyFromToken(address(this), ml.SY, 0, ml.extraInput);
            IERC20(asset()).approve(pendleRouter, 0);
        }

        ApproxParams memory ap;
        LimitOrderData memory orderData;

        IERC20(ml.SY).approve(pendleRouter, syOut);
        (amountOut,) =
            IPActionSwapPTV3(pendleRouter).swapExactSyForPt(address(this), ml.pendleMarket, syOut, 0, ap, orderData);

        IERC20(borrowToken).approve(pendleRouter, 0);

        // technically this is our slippage protection, so we can go
        // without individual swap slippage

        require(amountOut >= assets, "collateral not enough");
        IERC20(collateralToken).approve(morpho, amountOut);

        if (amountOut > assets) {
            uint256 diff = amountOut - assets;
            IMorpho(morpho).supplyCollateral(ml.marketParams, diff, address(this), "");
            // here we supply the extra collateral token we have in the end.
        }

        uint256 usdcBalPost = idleBalance();
        uint256 usdcOut = usdcBalPre - usdcBalPost;

        uint256 positionUSDCValue =
            _requireWithinLimits(collateralToken, borrowToken, amountOut, ml.amountToBorrow, usdcOut, true);

        if (positionUSDCValue > usdcOut) {
            lastTotalAssets += positionUSDCValue - usdcOut;
        } else {
            lastTotalAssets -= usdcOut - positionUSDCValue;
        }
    }

    // 1. Repays the debt
    // 2. Withdraws the collateral from Morpho
    // 3 Swaps Collateral -> borrowed asset
    // 3.1 If borrowed != asset(), makes another swap collateral -> asset()
    // 4. Since the swapping doesnt support exactOutput, we'll likely be left with some dust in borrowed token (which will be unaccounted for in totalAssets())
    // Params will be calculated to make sure this is always a negligible amount +  if it is non-negligible, allocator can use it when opening a new position
    function repayPosition(RepayPosition memory params) external updateTotalAssets onlyAllocator nonReentrant {
        bytes memory data = abi.encode(params);
        if (params.amountToRepay == type(uint256).max) {
            Id id = params.marketParams.id();

            uint256 repayShares = IMorpho(morpho).borrowShares(id, address(this));
            IMorpho(morpho).repay(params.marketParams, 0, repayShares, address(this), data);
        } else {
            IMorpho(morpho).repay(params.marketParams, params.amountToRepay, 0, address(this), data);
        }
    }

    function onMorphoRepay(uint256 assets, bytes calldata data) external onlyMorpho {
        RepayPosition memory params = abi.decode(data, (RepayPosition));
        MarketParams memory mp = params.marketParams;
        address collateral = mp.collateralToken;
        address borrow = mp.loanToken;
        uint256 usdcBalPre = idleBalance();

        if (params.amountToWithdraw == type(uint256).max) {
            Id id = mp.id();

            params.amountToWithdraw = IMorpho(morpho).collateral(id, address(this));
        }

        IMorpho(morpho).withdrawCollateral(mp, params.amountToWithdraw, address(this), address(this));

        IERC20(collateral).approve(pendleRouter, type(uint256).max);

        if (IPPrincipalToken(collateral).isExpired()) {
            // Redeem to borrowed asset
            IPActionMiscV3(pendleRouter).redeemPyToToken(address(this), params.YT, params.swapToBorrowed, params.output);

            if (borrow != asset()) {
                // Redeem to underlying asset
                IPActionMiscV3(pendleRouter).redeemPyToToken(
                    address(this), params.YT, params.swapToAsset, params.extraOutput
                );
            }
        } else {
            LimitOrderData memory orderData;

            // Swap to borrowed asset
            IPActionSwapPTV3(pendleRouter).swapExactPtForToken(
                address(this), params.pendleMarket, params.swapToBorrowed, params.output, orderData
            );

            if (borrow != asset()) {
                // Swap to underlying asset
                IPActionSwapPTV3(pendleRouter).swapExactPtForToken(
                    address(this), params.pendleMarket, params.swapToAsset, params.extraOutput, orderData
                );
            }
        }

        IERC20(collateral).approve(pendleRouter, 0);

        uint256 usdcBalPost = idleBalance();
        uint256 usdcBalIn = usdcBalPost - usdcBalPre;
        if (borrow == asset()) usdcBalIn -= assets; // this amount will be repaid after the callback, so we subtract it

        uint256 positionValueUSDC =
            _requireWithinLimits(collateral, borrow, params.amountToWithdraw, assets, usdcBalIn, false);

        if (usdcBalIn > positionValueUSDC) {
            lastTotalAssets += usdcBalIn - positionValueUSDC;
        } else {
            lastTotalAssets -= positionValueUSDC - usdcBalIn;
        }

        IERC20(borrow).approve(morpho, assets);
    }

    function _requireWithinLimits(
        address collateral,
        address borrow,
        uint256 totalCollateral,
        uint256 totalBorrow,
        uint256 usdcOut,
        bool isOpen
    ) internal view returns (uint256) {
        uint256 collatPrice = IPriceFeed(pricefeed).getPrice(collateral);
        uint256 totalCollateralValue = totalCollateral * collatPrice / (10 ** IERC20Metadata(collateral).decimals());

        uint256 borrowedPrice = IPriceFeed(pricefeed).getPrice(borrow);
        uint256 totalBorrowedValue = totalBorrow * borrowedPrice / (10 ** IERC20Metadata(borrow).decimals());

        uint256 usdcPrice = IPriceFeed(pricefeed).getPrice(asset());
        uint256 positionUSDCValue =
            (totalCollateralValue - totalBorrowedValue) * (10 ** IERC20Metadata(asset()).decimals()) / usdcPrice;

        if (isOpen) {
            require(
                positionUSDCValue >= usdcOut * (SLIPPAGE_PRECISION - positionMaxSlippage) / SLIPPAGE_PRECISION,
                "slippage too high"
            );
        } else {
            require(
                positionUSDCValue * (SLIPPAGE_PRECISION - positionMaxSlippage) / SLIPPAGE_PRECISION <= usdcOut,
                "slippage too high"
            );
        }
        return positionUSDCValue;
    }

    function totalAssets() public view override returns (uint256) {
        return lastTotalAssets - _vestingInterest();
    }

    function _vestingInterest() internal view returns (uint256) {
        if (block.timestamp - lastUpdate >= vestingDuration) return 0;

        uint256 __vestingInterest =
            vestingInterest - ((block.timestamp - lastUpdate) * vestingInterest / vestingDuration);
        return __vestingInterest;
    }

    function scheduleAddMarket(Id id) external nonReentrant onlyOwner {
        require(isMarketEnabled[id] == false, "Market already enabled");
        scheduledAdd[id] = block.timestamp;
    }

    function addMarket(MarketParams calldata mp) external nonReentrant onlyOwner {
        Id id = mp.id();

        require(isMarketEnabled[id] == false, "Market already enabled");
        require(
            scheduledAdd[id] != 0 && block.timestamp - scheduledAdd[id] >= timelockPeriod,
            "market must go through timelock"
        );
        require(morphoPositions.length < MAX_NUMBER_MARKETS, "too many active markets");

        isMarketEnabled[id] = true;
        index[id] = morphoPositions.length;
        morphoPositions.push(mp);

        delete scheduledAdd[id];
    }

    // We do not need to wait timelock in order to remove a market
    // If a griefer sends dust as collateral, we'll just chain repay position with market removal.
    function removeMarket(MarketParams calldata mp) external nonReentrant onlyOwner {
        Id id = mp.id();
        require(isMarketEnabled[id], "market not enabled");

        uint256 collateral = IMorpho(morpho).collateral(id, address(this));
        require(collateral == 0, "account has non-zero collateral in the market");

        uint256 lastIndex = morphoPositions.length - 1;
        uint256 marketIndex = index[id];

        if (marketIndex != lastIndex) {
            morphoPositions[marketIndex] = morphoPositions[lastIndex];
            Id temp = morphoPositions[lastIndex].id();
            index[temp] = marketIndex;
        }

        morphoPositions.pop();
        delete index[id];

        isMarketEnabled[id] = false;
    }

    function setTimelockPeriod(uint256 newTimelockPeriod) external onlyOwner {
        require(newTimelockPeriod >= 1 days, "timelock must be at least 1 day");
        timelockPeriod = newTimelockPeriod;
    }

    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        require(_feeRecipient != address(0), "fee recipient can't be address(0)");
        feeRecipient = _feeRecipient;
    }

    // If it hasn't been updated soon, this would charge the new protocol fee on the old yield, thats ok
    function setProtocolFee(uint256 _protocolFee) external onlyOwner {
        require(_protocolFee <= 5000, "protocol fee can be up to 50%");
        protocolFee = _protocolFee;
    }

    function setUpdateInterval(uint256 _updateInterval) external onlyOwner {
        require(_updateInterval >= 15 minutes, "update interval must be at least 15 minutes");
        require(_updateInterval >= vestingDuration, "update interval must be longer than vesting duration");
        updateInterval = _updateInterval;
    }

    function setVestingDuration(uint256 _vestingDuration) external onlyOwner {
        require(_vestingDuration >= 10 minutes, "vesting duration must be at least 10 minutes");
        require(_vestingDuration <= updateInterval, "vestingDuration can't be longer than update interval");
        require(block.timestamp - lastUpdate >= _vestingDuration, "there should be no ongoing vesting");
        require(block.timestamp - lastUpdate >= vestingDuration, "there should be no ongoing vesting");
        vestingDuration = _vestingDuration;
    }

    function setAllocator(address _allocator) external onlyOwner {
        require(_allocator != address(0), "allocator can't be address(0)");
        allocator = _allocator;
    }

    function setPositionMaxSlippage(uint256 _maxSlippage) external onlyOwner {
        require(_maxSlippage <= 1000, "slippage can be up to 10%");
        positionMaxSlippage = _maxSlippage;
    }

    function setPriceFeed(address _pricefeed) external onlyOwner {
        require(_pricefeed != address(0), "can't be address(0)");
        pricefeed = _pricefeed;
    }

    // We have deposit cap, because in certain scenario there might no be enough liquidity to borrow from
    // In this situation, new depositors will just dilute the current yield
    function setDepositCap(uint256 _depositCap) external {
        require(msg.sender == owner() || msg.sender == allocator, "cap can only be changed by owner or allocator");
        depositCap = _depositCap;
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
    {
        lastTotalAssets += assets;
        require(lastTotalAssets <= depositCap, "deposit cap exceeded");
        super._deposit(caller, receiver, assets, shares);
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
    {
        uint256 _idleBalance = idleBalance();
        require(_idleBalance >= assets, "not enough balance in the contract");

        lastTotalAssets -= assets;
        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function deposit(uint256 assets, address receiver) public override updateTotalAssets returns (uint256 shares) {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override updateTotalAssets returns (uint256 assets) {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        updateTotalAssets
        returns (uint256 shares)
    {
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        updateTotalAssets
        returns (uint256 assets)
    {
        return super.redeem(shares, receiver, owner);
    }

    function idleBalance() public view returns (uint256 amount) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function maxDeposit(address user) public view override returns (uint256) {
        if (lastTotalAssets >= depositCap) return 0;
        uint256 remaining = depositCap - lastTotalAssets;
        uint256 userBal = IERC20(asset()).balanceOf(user);
        uint256 max = userBal < remaining ? userBal : remaining;
        return max;
    }

    function maxWithdraw(address user) public view override returns (uint256) {
        uint256 sharesValue = super.maxWithdraw(user);
        uint256 _idleBalance = idleBalance();

        uint256 max = sharesValue < _idleBalance ? sharesValue : _idleBalance;
        return max;
    }

    // helper view function

    function name() public pure override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return "Looped USDC";
    }

    function symbol() public pure override(ERC20Upgradeable, IERC20Metadata) returns (string memory) {
        return "loopUSDC";
    }

    function getId(MarketParams calldata marketParams) public pure returns (Id id) {
        return marketParams.id();
    }
}
