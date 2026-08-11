//SPDX-License-Identifier: CC-BY-NC-ND-4.0

import {ITermController} from "../interfaces/ITermController.sol";

abstract contract TermContractsPausable {

    modifier whileTermContractsNotPaused(address controller) {
        ITermController c = ITermController(controller);
        if (c.termContractsPaused()) {
            revert();
        }
        _;
    }

}