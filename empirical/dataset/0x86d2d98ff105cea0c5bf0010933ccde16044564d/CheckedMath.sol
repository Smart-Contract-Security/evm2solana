// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.27;

library CheckedMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) { return a + b; }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) { require(b <= a, "underflow"); return a - b; }
    function mul(uint256 a, uint256 b) internal pure returns (uint256) { if (a == 0) return 0; uint256 c = a * b; require(c / a == b, "overflow"); return c; }
    function div(uint256 a, uint256 b) internal pure returns (uint256) { require(b > 0, "div/0"); return a / b; }
}
