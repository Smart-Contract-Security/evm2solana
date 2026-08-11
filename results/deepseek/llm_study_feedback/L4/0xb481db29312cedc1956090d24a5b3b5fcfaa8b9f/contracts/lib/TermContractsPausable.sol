// SPDX-License-Identifier: CC-BY-NC-ND-4.0
pragma solidity ^0.8.22;

interface ITermController {
    function termContractsPaused() external view returns (bool);
}

abstract contract TermContractsPausable {
    error TermContractsPaused();

    modifier whileTermContractsNotPaused(address controller) {
        if (ITermController(controller).termContractsPaused()) {
            revert TermContractsPaused();
        }
        _;
    }
}