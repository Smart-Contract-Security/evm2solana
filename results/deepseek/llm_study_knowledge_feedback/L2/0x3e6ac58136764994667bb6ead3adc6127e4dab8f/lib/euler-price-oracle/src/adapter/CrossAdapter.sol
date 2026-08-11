// SPDX-License-Identifier: GPL-2.0-or-later

interface IPriceOracle {
    function getQuote(uint64 inAmount, address base, address quote) external view returns (uint64);
}

/// @title CrossAdapter
/// @custom:security-contact security@euler.xyz
/// @author Euler Labs (https://www.eulerlabs.com/)
/// @notice PriceOracle that chains two PriceOracles.
/// @dev For example, CrossAdapter can price wstETH/USD by querying a wstETH/stETH oracle and a stETH/USD oracle.
contract CrossAdapter {
    /// @notice The name of this adapter.
    string public constant name = "CrossAdapter";
    /// @notice The address of the base asset.
    address public immutable base;
    /// @notice The address of the cross/through asset.
    address public immutable cross;
    /// @notice The address of the quote asset.
    address public immutable quote;
    /// @notice The oracle that resolves base/cross and cross/base.
    /// @dev The oracle MUST be bidirectional.
    address public immutable oracleBaseCross;
    /// @notice The oracle that resolves quote/cross and cross/quote.
    /// @dev The oracle MUST be bidirectional.
    address public immutable oracleCrossQuote;

    /// @notice Deploy a CrossAdapter.
    /// @param _base The address of the base asset.
    /// @param _cross The address of the cross/through asset.
    /// @param _quote The address of the quote asset.
    /// @param _oracleBaseCross The oracle that resolves base/cross and cross/base.
    /// @param _oracleCrossQuote The oracle that resolves quote/cross and cross/quote.
    /// @dev Both cross oracles MUST be bidirectional.
    /// @dev Does not support bid/ask pricing.
    constructor(address _base, address _cross, address _quote, address _oracleBaseCross, address _oracleCrossQuote) {
        base = _base;
        cross = _cross;
        quote = _quote;
        oracleBaseCross = _oracleBaseCross;
        oracleCrossQuote = _oracleCrossQuote;
    }

    /// @notice Get a quote by chaining the cross oracles.
    /// @dev For the inverse direction it calculates quote/cross * cross/base.
    /// For the forward direction it calculates base/cross * cross/quote.
    /// @param inAmount The amount of `base` to convert.
    /// @param _base The token that is being priced.
    /// @param _quote The token that is the unit of account.
    /// @return The converted amount by chaining the cross oracles.
    function getQuote(uint64 inAmount, address _base, address _quote) public view returns (uint64) {
        bool inverse = _getDirectionOrRevert(_base, base, _quote, quote);

        if (inverse) {
            inAmount = IPriceOracle(oracleCrossQuote).getQuote(inAmount, quote, cross);
            return IPriceOracle(oracleBaseCross).getQuote(inAmount, cross, base);
        } else {
            inAmount = IPriceOracle(oracleBaseCross).getQuote(inAmount, base, cross);
            return IPriceOracle(oracleCrossQuote).getQuote(inAmount, cross, quote);
        }
    }

    function _getDirectionOrRevert(address _base, address base_, address _quote, address quote_) private pure returns (bool) {
        if (_base == base_ && _quote == quote_) {
            return false;
        } else if (_base == quote_ && _quote == base_) {
            return true;
        } else {
            revert();
        }
    }
}