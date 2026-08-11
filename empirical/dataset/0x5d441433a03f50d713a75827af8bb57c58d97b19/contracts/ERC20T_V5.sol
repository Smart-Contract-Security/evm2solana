// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./ERC20T_V3.sol";

contract ERC20T_V5 is ERC20T_V3 {
    uint256 internal allocatedQTY;
    uint256 internal unallocatedQTY;

    string public contract1Status;
    uint256 public contract2Issued;
    uint256 public contract3Unissued;
    uint256 public contract4Allocated;
    uint256 public contract5Unallocated;

    function initializeV5() public reinitializer(5) protectedOwner {
        contract1Status = "Minted";
        contract2Issued = 2998422;
        contract3Unissued = 0;
        contract4Allocated = 0;
        contract5Unallocated = 2998422;
    }

    function setContract1Status(string memory _contract1Status) external protectedOwner {
        contract1Status = _contract1Status;
    }

    function setContract2Issued(uint256 _contract2Issued) external protectedOwner {
        contract2Issued = _contract2Issued;
    }

    function setContract3Unissued(uint256 _contract3Unissued) external protectedOwner {
        contract3Unissued = _contract3Unissued;
    }

    function setContract4Allocated(uint256 _contract4Allocated) external protectedOwner {
        contract4Allocated = _contract4Allocated;
    }

    function setContract5Unallocated(uint256 _contract5Unallocated) external protectedOwner {
        contract5Unallocated = _contract5Unallocated;
    }

    function getVersion() external pure override returns (string memory) {
        return "v.5";
    }
}
