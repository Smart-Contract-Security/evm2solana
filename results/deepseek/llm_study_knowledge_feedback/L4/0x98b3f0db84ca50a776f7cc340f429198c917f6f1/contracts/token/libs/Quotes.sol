// SPDX-License-Identifier: Apache-2.0

import {Quote} from "../../interfaces/ITokenBridge.sol";

library Quotes {
    function extract(
        Quote[] memory quotes,
        address token
    ) internal pure returns (uint64 sum) {
        sum = 0;
        for (uint64 i = 0; i < quotes.length; i++) {
            if (quotes[i].token == token) {
                sum += quotes[i].amount;
            }
        }
    }
}