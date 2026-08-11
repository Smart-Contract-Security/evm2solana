// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {BaseAdapter} from "./BaseAdapter.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {ScaleUtils} from "../lib/ScaleUtils.sol";

contract CrossAdapter is BaseAdapter {
    string public constant name = "CrossAdapter";

    address public immutable base;
    address public immutable cross;
    address public immutable quote;
    address public immutable oracleBaseCross;
    address public immutable oracleCrossQuote;

    constructor(address _base, address _cross, address _quote, address _oracleBaseCross, address _oracleCrossQuote) {
        base = _base;
        cross = _cross;
        quote = _quote;
        oracleBaseCross = _oracleBaseCross;
        oracleCrossQuote = _oracleCrossQuote;
    }

    function _getQuote(uint256 inAmount, address _base, address _quote) internal view override returns (uint256) {
        bool inverse = ScaleUtils.getDirectionOrRevert(_base, base, _quote, quote);

        if (inverse) {
            inAmount = IPriceOracle(oracleCrossQuote).getQuote(inAmount, quote, cross);
            return IPriceOracle(oracleBaseCross).getQuote(inAmount, cross, base);
        } else {
            inAmount = IPriceOracle(oracleBaseCross).getQuote(inAmount, base, cross);
            return IPriceOracle(oracleCrossQuote).getQuote(inAmount, cross, quote);
        }
    }
}