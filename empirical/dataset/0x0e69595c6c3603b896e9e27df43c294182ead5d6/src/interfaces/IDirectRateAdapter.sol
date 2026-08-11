// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IDirectRateAdapter {
    enum PostProcess {
        NONE,
        INVERT,
        SCALE_DOWN
    }

    event ConfigSet(address indexed token, address target);
    event ConfigRemoved(address indexed token);
}
