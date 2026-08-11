// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IPoolShareAdapter {
    event ConfigSet(address indexed token, address numeratorTarget, address denominatorTarget);
    event ConfigRemoved(address indexed token);
}
