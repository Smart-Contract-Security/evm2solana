// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.34;

import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin-contracts/interfaces/IERC20Metadata.sol";
import {Math} from "@openzeppelin-contracts/utils/math/Math.sol";

import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IAssetHandler} from "./interfaces/IAssetHandler.sol";
import {IdHEDGEPoolFactory} from "./interfaces/IdHEDGEPoolFactory.sol";
import {IdHEDGEPoolLogic} from "./interfaces/IdHEDGEPoolLogic.sol";

import {IOracleModule} from "../../interfaces/IOracleModule.sol";
import {USD_ISO_ADDRESS} from "../../libraries/Constants.sol";

/// @title SimpleOracleModule
/// @notice Resolves per-asset USD prices from four sources in order:
///         USD synthetic → dhedge AssetHandler → PoolFactory.isPool fallback
///         → DYTM-set additional oracle.
/// @dev Cross-rate math returns `outAmount = inAmount × (basePrice/baseScale)
///      / (quotePrice/quoteScale)`, where `price / scale = USD per raw unit`.
///      DYTM is for ERC20 lending; non-ERC20 assets revert via `_getDecimals`.
/// @author dhedge
contract SimpleOracleModule is IOracleModule, Ownable {
    using Math for uint256;

    /////////////////////////////////////////////
    //                 Errors                  //
    /////////////////////////////////////////////

    error SimpleOracleModule__ZeroAddress();
    error SimpleOracleModule__ZeroValue();
    error SimpleOracleModule__PriceNotFound(address asset);
    error SimpleOracleModule__StalePrice(address asset, uint256 staleness);
    error SimpleOracleModule__AssetInAssetHandler(address asset);
    error SimpleOracleModule__AssetIsPool(address asset);
    error SimpleOracleModule__NotERC20(address asset);

    /////////////////////////////////////////////
    //                 Events                  //
    /////////////////////////////////////////////

    event AdditionalOracleSet(address indexed asset, address indexed oracle, uint256 maxStaleness);
    event AdditionalOracleUnset(address indexed asset);

    /////////////////////////////////////////////
    //                  Types                  //
    /////////////////////////////////////////////

    /// @param scale `10 ** (assetDecimals + oracleDecimals)`, cached at set time.
    struct AdditionalOracleData {
        AggregatorV3Interface oracle;
        uint256 maxStaleness;
        uint256 scale;
    }

    /////////////////////////////////////////////
    //                Constants                //
    /////////////////////////////////////////////

    /// @dev Reserved low range: ISO 4217 fiat codes + EVM precompile real-estate.
    ///      No real ERC20 lives here.
    uint256 private constant _ADDRESS_RESERVED_RANGE = 0xffffffff;

    /////////////////////////////////////////////
    //                Storage                  //
    /////////////////////////////////////////////

    IdHEDGEPoolFactory public immutable POOL_FACTORY;

    /// @notice dhedge `AssetHandler`, captured at construction from
    ///         `POOL_FACTORY.getAssetHandler()`.
    IAssetHandler public immutable ASSET_HANDLER;

    /// @notice DYTM-set oracle entries for assets NOT in the dhedge AssetHandler.
    mapping(address asset => AdditionalOracleData data) public additionalOracles;

    /////////////////////////////////////////////
    //              Constructor                //
    /////////////////////////////////////////////

    constructor(address admin, address poolFactory) Ownable(admin) {
        require(
            admin != address(0) && poolFactory != address(0),
            SimpleOracleModule__ZeroAddress()
        );
        POOL_FACTORY = IdHEDGEPoolFactory(poolFactory);

        address handler = IdHEDGEPoolFactory(poolFactory).getAssetHandler();
        require(handler != address(0), SimpleOracleModule__ZeroAddress());
        ASSET_HANDLER = IAssetHandler(handler);
    }

    /////////////////////////////////////////////
    //              External API               //
    /////////////////////////////////////////////

    /// @inheritdoc IOracleModule
    function getQuote(
        uint256 inAmount,
        address base,
        address quote
    ) external view returns (uint256 outAmount) {
        return _getQuote(inAmount, base, quote);
    }

    /////////////////////////////////////////////
    //            Owner Functions              //
    /////////////////////////////////////////////

    /// @notice Set a local oracle entry for an asset NOT in the dhedge handler
    ///         and NOT recognized as a dhedge pool.
    ///         Pass `oracle = address(0)` to unset.
    /// @dev 1. Reverts if the asset is already registered in the dhedge handler
    ///         OR is a dhedge pool — branches 2/3 of `_getPrice` would shadow
    ///         this entry, so we refuse to store dead state.
    ///      2. If an asset listed here is later added on the dhedge side, the
    ///         entry here gets shadowed by branches 2/3 of `_getPrice` and is
    ///         left as harmless dead state.
    function setAdditionalOracle(
        address asset,
        address oracle,
        uint256 maxStaleness
    ) external onlyOwner {
        require(asset != address(0), SimpleOracleModule__ZeroAddress());
        require(maxStaleness > 0 || oracle == address(0), SimpleOracleModule__ZeroValue());

        if (ASSET_HANDLER.priceAggregators(asset) != address(0)) {
            revert SimpleOracleModule__AssetInAssetHandler(asset);
        }
        if (POOL_FACTORY.isPool(asset)) {
            revert SimpleOracleModule__AssetIsPool(asset);
        }

        if (oracle == address(0)) {
            delete additionalOracles[asset];
            emit AdditionalOracleUnset(asset);
            return;
        }

        uint8 assetDecimals = _getDecimals(asset);
        uint8 oracleDecimals = AggregatorV3Interface(oracle).decimals();
        additionalOracles[asset] = AdditionalOracleData({
            oracle: AggregatorV3Interface(oracle),
            maxStaleness: maxStaleness,
            scale: 10 ** (uint256(assetDecimals) + uint256(oracleDecimals))
        });
        emit AdditionalOracleSet(asset, oracle, maxStaleness);
    }

    /////////////////////////////////////////////
    //           Internal Functions            //
    /////////////////////////////////////////////

    function _getQuote(
        uint256 inAmount,
        address base,
        address quote
    ) internal view returns (uint256 outAmount) {
        if (base == quote) {
            return inAmount;
        }

        (uint256 basePriceUSD, uint256 baseScale) = _getPrice(base);
        (uint256 quotePriceUSD, uint256 quoteScale) = _getPrice(quote);

        // outAmount = (inAmount * basePriceUSD * quoteScale) / (quotePriceUSD * baseScale)
        // Split via integer scaleRatio (exact since both scales are powers of 10)
        // to keep the inner `mulDiv` operand from overflowing 256 bits.
        if (quoteScale >= baseScale) {
            uint256 scaleRatio = quoteScale / baseScale;
            return inAmount.mulDiv(basePriceUSD * scaleRatio, quotePriceUSD);
        } else {
            uint256 scaleRatio = baseScale / quoteScale;
            return inAmount.mulDiv(basePriceUSD, quotePriceUSD * scaleRatio);
        }
    }

    function _getPrice(address asset) internal view returns (uint256 priceUSD, uint256 scale) {
        // 1. USD synthetic — short-circuits before _getDecimals.
        if (asset == USD_ISO_ADDRESS) {
            return (1e18, 1e36);
        }

        // 2. dhedge AssetHandler — returns 18-dec USD; enforces freshness internally.
        if (ASSET_HANDLER.priceAggregators(asset) != address(0)) {
            uint256 price18 = ASSET_HANDLER.getUSDPrice(asset);
            return (price18, 10 ** (uint256(_getDecimals(asset)) + 18));
        }

        // 3. isPool fallback — vault.tokenPrice() is 18-dec WAD; vault tokens are 18-dec.
        if (POOL_FACTORY.isPool(asset)) {
            return (IdHEDGEPoolLogic(asset).tokenPrice(), 1e36);
        }

        // 4. Additional oracle — DYTM-set Chainlink-style feed.
        AdditionalOracleData memory data = additionalOracles[asset];
        if (address(data.oracle) != address(0)) {
            (, int256 answer, , uint256 updatedAt, ) = data.oracle.latestRoundData();
            require(answer > 0, SimpleOracleModule__PriceNotFound(asset));
            uint256 staleness = block.timestamp - updatedAt;
            require(staleness <= data.maxStaleness, SimpleOracleModule__StalePrice(asset, staleness));
            return (uint256(answer), data.scale);
        }

        revert SimpleOracleModule__PriceNotFound(asset);
    }

    /// @dev Reverts for reserved-range addresses and non-ERC20 contracts.
    function _getDecimals(address asset) internal view returns (uint8) {
        require(uint160(asset) > _ADDRESS_RESERVED_RANGE, SimpleOracleModule__NotERC20(asset));
        (bool success, bytes memory data) =
            asset.staticcall(abi.encodeCall(IERC20Metadata.decimals, ()));
        require(success && data.length == 32, SimpleOracleModule__NotERC20(asset));
        return abi.decode(data, (uint8));
    }
}
