// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IAssetRegistry} from "./interfaces/IAssetRegistry.sol";
import {IAccessController} from "./interfaces/IAccessController.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {Errors} from "./libs/Errors.sol";

contract AssetRegistry is IAssetRegistry {
    IAccessController public immutable access;

    mapping(address => AssetConfig) private _assets;
    mapping(bytes32 => bool) private _pairs;
    address[] private _listed;

    modifier onlyAdmin() {
        if (!access.hasRole(access.ADMIN_ROLE(), msg.sender)) revert Errors.NotAuthorized();
        _;
    }

    modifier onlyParam() {
        if (!access.hasRole(access.PARAM_MANAGER_ROLE(), msg.sender)) revert Errors.NotAuthorized();
        _;
    }

    constructor(address access_) {
        if (access_ == address(0)) revert Errors.ZeroAddress();
        access = IAccessController(access_);
    }

    function addAsset(
        address token,
        address vault,
        uint8 decimals_,
        address oracle,
        uint256 maxSwapNotional,
        uint16 minCoverageBps,
        uint16 depegDisableBps,
        uint32 oracleHeartbeat
    ) external onlyAdmin {
        if (token == address(0) || vault == address(0) || oracle == address(0)) revert Errors.ZeroAddress();
        if (_assets[token].listed) revert Errors.AssetAlreadyListed();
        if (decimals_ == 0 || decimals_ > 30) revert Errors.InvalidParam();
        if (minCoverageBps == 0 || minCoverageBps > 10_000) revert Errors.InvalidParam();
        if (depegDisableBps == 0 || depegDisableBps > 10_000) revert Errors.InvalidParam();
        if (oracleHeartbeat == 0 || oracleHeartbeat > 7 days) revert Errors.InvalidParam();
        // Sanity-check the oracle responds and reports a believable stablecoin price
        _validateOracle(oracle);

        _assets[token] = AssetConfig({
            token: token,
            vault: vault,
            decimals: decimals_,
            oracle: oracle,
            listed: true,
            maxSwapNotional: maxSwapNotional,
            minCoverageBps: minCoverageBps,
            depegDisableBps: depegDisableBps,
            oracleHeartbeat: oracleHeartbeat
        });
        _listed.push(token);
        emit AssetAdded(token, vault, oracle);
    }

    function enablePair(address a, address b) external onlyAdmin {
        if (a == b) revert Errors.SameAsset();
        if (!_assets[a].listed || !_assets[b].listed) revert Errors.AssetNotListed();
        _pairs[_pairKey(a, b)] = true;
        emit PairEnabled(a, b);
    }

    function disablePair(address a, address b) external onlyAdmin {
        _pairs[_pairKey(a, b)] = false;
        emit PairDisabled(a, b);
    }

    function setParams(
        address token,
        uint256 maxSwapNotional,
        uint16 minCoverageBps,
        uint16 depegDisableBps,
        uint32 oracleHeartbeat
    ) external onlyParam {
        AssetConfig storage c = _assets[token];
        if (!c.listed) revert Errors.AssetNotListed();
        if (minCoverageBps == 0 || minCoverageBps > 10_000) revert Errors.InvalidParam();
        if (depegDisableBps == 0 || depegDisableBps > 10_000) revert Errors.InvalidParam();
        if (oracleHeartbeat == 0) revert Errors.InvalidParam();
        c.maxSwapNotional = maxSwapNotional;
        c.minCoverageBps = minCoverageBps;
        c.depegDisableBps = depegDisableBps;
        c.oracleHeartbeat = oracleHeartbeat;
        emit AssetParamsUpdated(token);
    }

    function setOracle(address token, address oracle) external onlyParam {
        if (oracle == address(0)) revert Errors.ZeroAddress();
        AssetConfig storage c = _assets[token];
        if (!c.listed) revert Errors.AssetNotListed();
        _validateOracle(oracle);
        c.oracle = oracle;
        emit AssetParamsUpdated(token);
    }

    /// @notice Defensive sanity check on an oracle at registration time.
    ///         A stablecoin feed should report a positive answer close to $1
    ///         from a complete round. Catches bricked or mis-configured feeds early.
    function _validateOracle(address oracle) internal view {
        IAggregatorV3 o = IAggregatorV3(oracle);
        uint8 d = o.decimals();
        if (d == 0 || d > 30) revert Errors.InvalidParam();
        (uint80 roundId, int256 answer, , uint256 updatedAt, uint80 answeredInRound) = o.latestRoundData();
        if (answer <= 0) revert Errors.InvalidOraclePrice();
        if (updatedAt == 0) revert Errors.StaleOracle();
        if (answeredInRound < roundId) revert Errors.StaleOracle();
        // Reject obviously-wrong stablecoin feeds: must be within +/- 50% of $1.
        uint256 priceWad = d == 18
            ? uint256(answer)
            : d < 18 ? uint256(answer) * (10 ** (18 - d)) : uint256(answer) / (10 ** (d - 18));
        if (priceWad < 5e17 || priceWad > 15e17) revert Errors.InvalidOraclePrice();
    }

    function listedAssets() external view returns (address[] memory) {
        return _listed;
    }

    function getAsset(address token) external view returns (AssetConfig memory) {
        return _assets[token];
    }

    function isListed(address token) external view returns (bool) {
        return _assets[token].listed;
    }

    function vaultOf(address token) external view returns (address) {
        return _assets[token].vault;
    }

    function isPairEnabled(address a, address b) external view returns (bool) {
        if (a == b) return false;
        return _pairs[_pairKey(a, b)];
    }

    function _pairKey(address a, address b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }
}
