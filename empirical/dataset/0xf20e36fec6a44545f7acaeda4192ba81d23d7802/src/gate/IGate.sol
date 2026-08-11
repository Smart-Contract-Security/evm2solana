// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IGate {
    function denied(address who) external view returns (bool);
}
