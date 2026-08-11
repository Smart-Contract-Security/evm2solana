// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract TestToken is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    uint8 private _customDecimals;
    
    struct Proposal {
        string description;
        uint256 voteCount;
        bool executed;
    }

    mapping(uint256 => Proposal) public proposals;
    

    constructor(uint256 initialSupply) ERC20("Test Token", "TST") {
        _customDecimals = uint8(17);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
        
      _mint(msg.sender, initialSupply * (10 ** uint256(_customDecimals)));
    
    }

    
    function decimals() public view override returns (uint8) {
        return _customDecimals;
    }
  

    event ProposalCreated(uint256 id, string description);
    event Voted(uint256 id, address voter, uint256 weight);
    event ProposalExecuted(uint256 id);

    function createProposal(uint256 id, string memory description) public onlyRole(GOVERNANCE_ROLE) { 
        require(bytes(proposals[id].description).length == 0, "Already exists");
        proposals[id] = Proposal(description, 0, false);
        emit ProposalCreated(id, description);
    }

    function vote(uint256 id, uint256 weight) public {
        Proposal storage p = proposals[id];
        require(!p.executed, "Executed");
        require(balanceOf(msg.sender) >= weight, "Not enough tokens");
        p.voteCount += weight;
        emit Voted(id, msg.sender, weight);
    }

    function executeProposal(uint256 id) public onlyRole(GOVERNANCE_ROLE) {
        Proposal storage p = proposals[id];
        require(!p.executed, "Executed");
        require(p.voteCount > 0, "No votes");
        p.executed = true;
        emit ProposalExecuted(id);
    }
    
}
