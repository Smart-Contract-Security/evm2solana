// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./ERC20T_V3.sol";

contract ERC20T_V4 is ERC20T_V3 {
    string public contract1Status;
    string public contract2Issued;
    string public contract3Unissued;
    string public contract4Allocated;
    string public contract5Unallocated;

    function initializeV4() public reinitializer(4) protectedOwner {
        contract1Status = "Minted";
        contract2Issued = "256854.4";
        contract3Unissued = "64213.6";
        contract4Allocated = "0";
        contract5Unallocated = "256854.4";
    }

    function setContract1Status(string memory _contract1Status) external protectedOwner {
        contract1Status = _contract1Status;
    }

    function setContract2Issued(string memory _contract2Issued) external protectedOwner {
        contract2Issued = _contract2Issued;
    }

    function setContract3Unissued(string memory _contract3Unissued) external protectedOwner {
        contract3Unissued = _contract3Unissued;
    }

    function setContract4Allocated(string memory _contract4Allocated) external protectedOwner {
        contract4Allocated = _contract4Allocated;
    }

    function setContract5Unallocated(string memory _contract5Unallocated) external protectedOwner {
        contract5Unallocated = _contract5Unallocated;
    }

    function getVersion() external pure override returns (string memory) {
        return "v.5";
    }
}
