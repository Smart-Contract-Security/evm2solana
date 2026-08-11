// SPDX-License-Identifier: MIT

interface IDirectRateAdapter {
    enum PostProcess {
        NONE,
        INVERT,
        SCALE_DOWN
    }

    event ConfigSet(address token, address target);
    event ConfigRemoved(address token);
}