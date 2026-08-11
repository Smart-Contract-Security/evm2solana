// SPDX-License-Identifier: MIT

import {BaseAdapter} from "./BaseAdapter.sol";
import {IDirectRateAdapter} from "../interfaces/IDirectRateAdapter.sol";

enum PostProcess {
    NONE,
    INVERT,
    SCALE_DOWN
}

struct ExchangeRateInfo {
    uint64 rate;
    uint64 lsdDecimals;
    uint64 underlyingDecimals;
    string lsdSymbol;
    string underlyingSymbol;
}

event ConfigSet(address indexed token, address indexed target);
event ConfigRemoved(address indexed token);

/// @title DirectRateAdapter
/// @notice Adapter for tokens where rate comes from a single external call.
contract DirectRateAdapter is BaseAdapter, IDirectRateAdapter {
    struct TokenConfig {
        address target;
        bytes callData;
        PostProcess postProcess;
        uint64 scaleFactor;
        uint64 outputScale;
        uint16 returnOffset;
        address underlying;
        bool isNative;
    }

    uint64 internal constant DEFAULT_OUTPUT_SCALE = 1e18;

    mapping(address => TokenConfig) public configOf;

    address private _owner;

    constructor() {
        _owner = tx.accounts.dataAccount.key;
    }

    modifier onlyOwner() {
        require(tx.accounts.dataAccount.key == _owner, "Not owner");
        _;
    }

    function initialize(address owner) external {
        require(_owner == address(0), "Already initialized");
        _owner = owner;
    }

    // ─── Admin ─────────────────────────────────────────────────────────────────

    function setConfig(address token, TokenConfig calldata config) external onlyOwner {
        _setConfig(token, config);
    }

    function setConfigBatch(address[] calldata tokens, TokenConfig[] calldata configs) external onlyOwner {
        if (tokens.length != configs.length) revert("LengthMismatch");
        for (uint64 i = 0; i < tokens.length; i++) {
            _setConfig(tokens[i], configs[i]);
        }
    }

    function removeConfig(address token) external onlyOwner {
        if (token == address(0)) revert("InvalidAddress");
        delete configOf[token];
        emit ConfigRemoved(token);
    }

    // ─── Queries ───────────────────────────────────────────────────────────────

    function getExchangeRate(address lsdToken) external view returns (ExchangeRateInfo memory info) {
        return _getRate(lsdToken);
    }

    function convertToUnderlying(address lsdToken, uint64 lsdAmount)
        external
        view
        returns (uint64 underlyingAmount, ExchangeRateInfo memory info)
    {
        info = _getRate(lsdToken);
        underlyingAmount = (lsdAmount * info.rate) / (10 ** uint64(info.lsdDecimals));
    }

    // ─── Storage gap ───────────────────────────────────────────────────────────

    uint64[50] private __gap;

    // ─── Internal ──────────────────────────────────────────────────────────────

    function _requireNonZero(address addr) internal pure {
        require(addr != address(0), "Zero address");
    }

    function _setConfig(address token, TokenConfig calldata config) internal {
        if (token == address(0)) revert("InvalidAddress");
        if (config.target == address(0)) revert("Invalid target");
        if (config.callData.length < 4) revert("Calldata too short");
        if (config.postProcess == PostProcess.SCALE_DOWN) {
            if (config.scaleFactor == 0) revert("Scale factor cannot be zero");
        }
        if (config.isNative) {
            if (config.underlying != address(0)) revert("Native must have zero underlying");
        } else {
            if (config.underlying == address(0)) revert("Invalid underlying");
        }
        configOf[token] = config;
        emit ConfigSet(token, config.target);
    }

    function _getRate(address lsdToken) internal view returns (ExchangeRateInfo memory info) {
        _requireNonZero(lsdToken);
        TokenConfig memory cfg = configOf[lsdToken];
        if (cfg.target == address(0)) revert("NotConfigured");

        uint64 rate = _staticCallUint64(cfg.target, cfg.callData, uint64(cfg.returnOffset));

        if (cfg.postProcess == PostProcess.INVERT) {
            if (rate == 0) revert("CallFailed");
            uint64 outScale = cfg.outputScale == 0 ? DEFAULT_OUTPUT_SCALE : cfg.outputScale;
            rate = (outScale * outScale) / rate;
        } else if (cfg.postProcess == PostProcess.SCALE_DOWN) {
            uint64 outScale = cfg.outputScale == 0 ? DEFAULT_OUTPUT_SCALE : cfg.outputScale;
            rate = (rate * outScale) / cfg.scaleFactor;
        }

        if (cfg.isNative) {
            return _buildInfoNative(lsdToken, rate, _getNativeSymbol());
        } else {
            return _buildInfoWithUnderlyingToken(lsdToken, cfg.underlying, rate);
        }
    }

    function _staticCallUint64(address target, bytes memory callData, uint64 offset) internal view returns (uint64) {
        (bool success, bytes memory result) = target.staticcall(callData);
        require(success, "Static call failed");
        require(result.length >= offset + 8, "Return data too short");
        uint64 value;
        assembly {
            value := mload(add(add(result, 32), offset))
        }
        return value;
    }
}