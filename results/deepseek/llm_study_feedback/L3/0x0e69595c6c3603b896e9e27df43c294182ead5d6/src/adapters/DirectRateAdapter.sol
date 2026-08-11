// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IDirectRateAdapter} from "../interfaces/IDirectRateAdapter.sol";

/// @title DirectRateAdapter
/// @notice Adapter for tokens where rate comes from a single external call.
contract DirectRateAdapter is IDirectRateAdapter {
    enum PostProcess {
        NONE,
        INVERT,
        SCALE_DOWN
    }

    struct TokenConfig {
        address target;
        bytes callData;
        PostProcess postProcess;
        uint256 scaleFactor;
        uint256 outputScale;
        uint16 returnOffset;
        address underlying;
        bool isNative;
    }

    struct ExchangeRateInfo {
        uint256 rate;
        uint8 lsdDecimals;
        string underlyingSymbol;
        address underlyingToken;
    }

    error LengthMismatch();
    error InvalidAddress();
    error InvalidConfig(string reason);
    error NotConfigured();
    error CallFailed();

    uint256 internal constant DEFAULT_OUTPUT_SCALE = 1e18;

    mapping(address => TokenConfig) public configOf;

    address private _owner;

    event ConfigSet(address indexed token, address indexed target);
    event ConfigRemoved(address indexed token);

    modifier onlyOwner() {
        require(tx.accounts[0].key == _owner, "Ownable: caller is not the owner");
        _;
    }

    constructor() {
        _owner = tx.accounts[0].key;
    }

    function initialize(address _ownerAddr) external {
        require(_owner == address(0), "Already initialized");
        require(_ownerAddr != address(0), "Invalid owner");
        _owner = _ownerAddr;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid new owner");
        _owner = newOwner;
    }

    // ─── Admin ─────────────────────────────────────────────────────────────────

    function setConfig(address token, TokenConfig calldata config) external onlyOwner {
        _setConfig(token, config);
    }

    function setConfigBatch(address[] calldata tokens, TokenConfig[] calldata configs) external onlyOwner {
        if (tokens.length != configs.length) revert LengthMismatch();
        for (uint256 i = 0; i < tokens.length; i++) {
            _setConfig(tokens[i], configs[i]);
        }
    }

    function removeConfig(address token) external onlyOwner {
        if (token == address(0)) revert InvalidAddress();
        delete configOf[token];
        emit ConfigRemoved(token);
    }

    // ─── Queries ───────────────────────────────────────────────────────────────

    function getExchangeRate(address lsdToken) external view returns (ExchangeRateInfo memory info) {
        return _getRate(lsdToken);
    }

    function convertToUnderlying(address lsdToken, uint256 lsdAmount)
        external
        view
        returns (uint256 underlyingAmount, ExchangeRateInfo memory info)
    {
        info = _getRate(lsdToken);
        underlyingAmount = (lsdAmount * info.rate) / (10 ** uint256(info.lsdDecimals));
    }

    // ─── Storage gap ───────────────────────────────────────────────────────────

    uint256[50] private __gap;

    // ─── Internal ──────────────────────────────────────────────────────────────

    function _setConfig(address token, TokenConfig calldata config) internal {
        if (token == address(0)) revert InvalidAddress();
        if (config.target == address(0)) revert InvalidConfig("Invalid target");
        if (config.callData.length < 4) revert InvalidConfig("Calldata too short");
        if (config.postProcess == PostProcess.SCALE_DOWN) {
            if (config.scaleFactor == 0) revert InvalidConfig("Scale factor cannot be zero");
        }
        if (config.isNative) {
            if (config.underlying != address(0)) revert InvalidConfig("Native must have zero underlying");
        } else {
            if (config.underlying == address(0)) revert InvalidConfig("Invalid underlying");
        }
        configOf[token] = config;
        emit ConfigSet(token, config.target);
    }

    function _getRate(address lsdToken) internal view returns (ExchangeRateInfo memory info) {
        _requireNonZero(lsdToken);
        TokenConfig memory cfg = configOf[lsdToken];
        if (cfg.target == address(0)) revert NotConfigured();

        uint256 rate = _staticCallUint256(cfg.target, cfg.callData, uint256(cfg.returnOffset));

        if (cfg.postProcess == PostProcess.INVERT) {
            if (rate == 0) revert CallFailed();
            uint256 outScale = cfg.outputScale == 0 ? DEFAULT_OUTPUT_SCALE : cfg.outputScale;
            rate = (outScale * outScale) / rate;
        } else if (cfg.postProcess == PostProcess.SCALE_DOWN) {
            uint256 outScale = cfg.outputScale == 0 ? DEFAULT_OUTPUT_SCALE : cfg.outputScale;
            rate = (rate * outScale) / cfg.scaleFactor;
        }

        if (cfg.isNative) {
            return _buildInfoNative(lsdToken, rate, _getNativeSymbol());
        } else {
            return _buildInfoWithUnderlyingToken(lsdToken, cfg.underlying, rate);
        }
    }

    function _requireNonZero(address addr) internal pure {
        require(addr != address(0));
    }

    function _staticCallUint256(address target, bytes memory data, uint256 offset) internal view returns (uint256) {
        (bool success, bytes memory returndata) = target.call{value: 0}(data);
        require(success);
        return abi.decode(returndata, (uint256));
    }

    function _buildInfoNative(address lsdToken, uint256 rate, string memory symbol) internal view returns (ExchangeRateInfo memory) {
        return ExchangeRateInfo({
            rate: rate,
            lsdDecimals: 18,
            underlyingSymbol: symbol,
            underlyingToken: address(0)
        });
    }

    function _buildInfoWithUnderlyingToken(address lsdToken, address underlying, uint256 rate) internal view returns (ExchangeRateInfo memory) {
        return ExchangeRateInfo({
            rate: rate,
            lsdDecimals: 18,
            underlyingSymbol: "",
            underlyingToken: underlying
        });
    }

    function _getNativeSymbol() internal pure returns (string memory) {
        return "SOL";
    }
}