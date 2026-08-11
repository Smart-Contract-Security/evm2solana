// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IRebasingAdapter {
    event ConfigSet(address indexed token, address underlying, bool isNative);
    event ConfigRemoved(address indexed token);
}
