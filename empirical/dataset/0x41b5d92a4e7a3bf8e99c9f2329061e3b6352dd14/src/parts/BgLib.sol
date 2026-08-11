// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {RektPunkPalettes as P} from "../RektPunkPalettes.sol";
import {RektPunkSVG as S} from "../RektPunkSVG.sol";

library BgLib {
    function background(uint256 i) external pure returns (string memory) {
        return S.rect(0, 0, 32, 32, P.bg(i));
    }
}
