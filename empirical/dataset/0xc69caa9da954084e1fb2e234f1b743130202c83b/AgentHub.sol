// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title AgentSettlementHub
 * @dev Manages income distribution for autonomous Web3 agents.
 * Programmatically routes creator fees and keeps agents funded for gas.
 */
contract AgentSettlementHub {
    address public immutable creator;
    uint256 public creatorFeeBps; // Basis points (e.g., 1000 = 10%)
    
    struct Agent {
        string agentType; // "estate", "chaos_monkey", or "negotiator"
        uint256 totalEarned;
        bool registered;
    }

    mapping(address => Agent) public agents;
    mapping(address => uint256) public agentGasBalances; // Funds agents keep for gas
    uint256 public totalCreatorPayouts;

    event AgentRegistered(address indexed agentAddress, string agentType);
    event IncomeProcessed(address indexed agentAddress, uint256 totalAmount, uint256 creatorCut, uint256 agentGasCut);
    event CreatorWithdrew(address indexed creator, uint256 amount);
    event GasWithdrawn(address indexed agentAddress, uint256 amount);

    modifier onlyCreator() {
        require(msg.sender == creator, "Only creator can call");
        _;
    }

    modifier onlyRegisteredAgent() {
        require(agents[msg.sender].registered, "Only registered agents can call");
        _;
    }

    constructor(uint256 _creatorFeeBps) {
        require(_creatorFeeBps <= 5000, "Fee cannot exceed 50%");
        creator = msg.sender;
        creatorFeeBps = _creatorFeeBps;
    }

    function registerAgent(address _agentAddress, string calldata _agentType) external onlyCreator {
        require(!agents[_agentAddress].registered, "Agent already registered");
        agents[_agentAddress] = Agent({
            agentType: _agentType,
            totalEarned: 0,
            registered: true
        });
        emit AgentRegistered(_agentAddress, _agentType);
    }

    /**
     * @notice Agents call this to deposit earned revenue (e.g., bounties or fees).
     * @dev Splits the payment between the creator and the agent's gas balance.
     */
    function depositIncome() external payable onlyRegisteredAgent {
        uint256 amount = msg.value;
        require(amount > 0, "Must deposit more than 0");

        uint256 creatorCut = (amount * creatorFeeBps) / 10000;
        uint256 agentCut = amount - creatorCut;

        agents[msg.sender].totalEarned += amount;
        agentGasBalances[msg.sender] += agentCut;
        
        // Directly send creator cut to secure wallet
        (bool success, ) = payable(creator).call{value: creatorCut}("");
        require(success, "Creator transfer failed");
        
        totalCreatorPayouts += creatorCut;

        emit IncomeProcessed(msg.sender, amount, creatorCut, agentCut);
    }

    /**
     * @notice Allows an agent to withdraw its stored gas funds to its wallet.
     */
    function withdrawGas(uint256 _amount) external onlyRegisteredAgent {
        require(agentGasBalances[msg.sender] >= _amount, "Insufficient gas balance");
        agentGasBalances[msg.sender] -= _amount;
        
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        require(success, "Gas withdrawal failed");
        
        emit GasWithdrawn(msg.sender, _amount);
    }

    // Fallback to receive directly (e.g. general tips or unclassified bounties)
    receive() external payable {
        if (agents[msg.sender].registered) {
            // If registered, treat as standard income
            uint256 creatorCut = (msg.value * creatorFeeBps) / 10000;
            agentGasBalances[msg.sender] += (msg.value - creatorCut);
            payable(creator).transfer(creatorCut);
        } else {
            // If unknown, default 100% to creator treasury
            payable(creator).transfer(msg.value);
        }
    }
}