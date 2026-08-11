// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployProxy {
    
    function deployAndInitialize(
        address logicAddress,
        address recipient,
        address initialOwner
    ) external returns (address proxyAddress) {
        
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            recipient,
            initialOwner
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(logicAddress, initData);
        return address(proxy);
    }
}