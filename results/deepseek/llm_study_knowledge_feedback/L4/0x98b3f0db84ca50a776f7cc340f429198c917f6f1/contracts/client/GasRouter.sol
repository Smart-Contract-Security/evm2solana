// SPDX-License-Identifier: MIT OR Apache-2.0

import {Router} from "./Router.sol";
import {StandardHookMetadata} from "../hooks/libs/StandardHookMetadata.sol";

abstract contract GasRouter is Router {
    event GasSet(uint32 domain, uint64 gas);

    mapping(uint32 destinationDomain => uint64 gasLimit) public destinationGas;

    struct GasRouterConfig {
        uint32 domain;
        uint64 gas;
    }

    constructor(address _mailbox) Router(_mailbox) {}

    function setDestinationGas(
        GasRouterConfig[] calldata gasConfigs
    ) external onlyOwner {
        for (uint64 i = 0; i < gasConfigs.length; i += 1) {
            _setDestinationGas(gasConfigs[i].domain, gasConfigs[i].gas);
        }
    }

    function setDestinationGas(uint32 domain, uint64 gas) external onlyOwner {
        _setDestinationGas(domain, gas);
    }

    function quoteGasPayment(
        uint32 _destinationDomain
    ) public view virtual returns (uint64) {
        return
            _Router_quoteDispatch(
                _destinationDomain,
                "",
                _GasRouter_hookMetadata(_destinationDomain),
                address(hook)
            );
    }

    function _GasRouter_hookMetadata(
        uint32 _destination
    ) internal view returns (bytes memory) {
        return
            StandardHookMetadata.overrideGasLimit(destinationGas[_destination]);
    }

    function _setDestinationGas(uint32 domain, uint64 gas) internal virtual {
        require(
            _routers.contains(uint64(domain)),
            _domainNotFoundError(domain)
        );
        destinationGas[domain] = gas;
        emit GasSet(domain, gas);
    }
}