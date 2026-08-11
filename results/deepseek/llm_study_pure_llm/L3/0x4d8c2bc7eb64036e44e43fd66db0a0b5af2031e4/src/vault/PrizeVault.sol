// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPrizeVault} from "./IPrizeVault.sol";
import {IHatToken} from "../token/IHatToken.sol";
import {IProtocolRegistry} from "../protocol/IProtocolRegistry.sol";
import {ProtocolPhase} from "../protocol/ProtocolPhase.sol";
import {Errors} from "../util/Errors.sol";

contract PrizeVault is IPrizeVault {
    address private _owner;
    bool private _locked;

    IProtocolRegistry public immutable registry;
    IHatToken public immutable hat;

    uint256 public override prizePoolBalance;

    mapping(uint256 => uint256) public stageEmissionBudget;
    mapping(uint256 => uint256) public stageEmissionSpent;
    bool public emissionScheduleFrozen;

    mapping(uint256 => mapping(address => uint256)) public stageAllowance;
    mapping(uint256 => mapping(address => bool)) public stageClaimed;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PrizeShareReceived(uint256 amount);
    event PrizePoolSeeded(uint256 amount);
    event StageEmissionBudgetSet(uint256 indexed stageId, uint256 budget);
    event StageEmissionFrozen();
    event StageAllowanceSet(uint256 indexed stageId, address indexed user, uint256 amount);
    event EmissionClaimed(uint256 indexed stageId, address indexed user, uint256 amount);
    event GrandPrizePaid(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == _owner, "Ownable: caller is not the owner");
        _;
    }

    modifier nonReentrant() {
        require(!_locked, "ReentrancyGuard: reentrant call");
        _locked = true;
        _;
        _locked = false;
    }

    constructor(IProtocolRegistry _registry, IHatToken _hat, address _initialOwner) {
        require(_initialOwner != address(0), "Ownable: new owner is the zero address");
        _owner = _initialOwner;
        emit OwnershipTransferred(address(0), _initialOwner);
        registry = _registry;
        hat = _hat;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function setStageEmissionBudget(uint256 stageId, uint256 budget) external onlyOwner {
        if (emissionScheduleFrozen) revert Errors.AlreadyInitialised();
        if (uint8(registry.phase()) >= uint8(ProtocolPhase.Phase.TGE)) revert Errors.WrongPhase();
        stageEmissionBudget[stageId] = budget;
        emit StageEmissionBudgetSet(stageId, budget);
    }

    function freezeEmissionSchedule() external onlyOwner {
        emissionScheduleFrozen = true;
        emit StageEmissionFrozen();
    }

    function receivePrizeShare(uint256 hatAmount) external override {
        if (msg.sender != registry.hatTrickHook()) revert Errors.NotAuthorized();
        prizePoolBalance += hatAmount;
        emit PrizeShareReceived(hatAmount);
    }

    function seedPrizePool(uint256 amount) external onlyOwner {
        bool success = IERC20(address(hat)).transferFrom(msg.sender, address(this), amount);
        require(success, "SafeERC20: transferFrom failed");
        prizePoolBalance += amount;
        emit PrizePoolSeeded(amount);
    }

    function setStageAllowance(uint256 stageId, address user, uint256 amount) external {
        if (msg.sender != registry.scoringEngine()) revert Errors.NotAuthorized();
        if (uint8(registry.phase()) < uint8(ProtocolPhase.Phase.LIVE)) revert Errors.WrongPhase();
        if (stageClaimed[stageId][user]) revert Errors.AlreadyInitialised();

        uint256 prev = stageAllowance[stageId][user];
        uint256 spent = stageEmissionSpent[stageId];
        if (amount >= prev) {
            uint256 newSpent = spent + (amount - prev);
            if (newSpent > stageEmissionBudget[stageId]) revert Errors.PotentialOverflow();
            stageEmissionSpent[stageId] = newSpent;
        } else {
            stageEmissionSpent[stageId] = spent - (prev - amount);
        }
        stageAllowance[stageId][user] = amount;
        emit StageAllowanceSet(stageId, user, amount);
    }

    function claimEmission(address to, uint256 amount) external override nonReentrant {
        uint256 stageIdMax = 256;
        uint256 stageId = _findUnclaimedStage(msg.sender, stageIdMax);
        require(stageId != type(uint256).max, "no unclaimed stage");
        _claim(stageId, msg.sender, to);
        if (amount != 0) {}
    }

    function claim(uint256 stageId) external nonReentrant {
        _claim(stageId, msg.sender, msg.sender);
    }

    function _claim(uint256 stageId, address user, address to) internal {
        if (stageClaimed[stageId][user]) revert Errors.AlreadyInitialised();
        uint256 amount = stageAllowance[stageId][user];
        if (amount == 0) revert Errors.ZeroAmount();
        stageClaimed[stageId][user] = true;
        hat.mintEmission(to, amount);
        emit EmissionClaimed(stageId, user, amount);
    }

    function _findUnclaimedStage(address user, uint256 maxStage) internal view returns (uint256) {
        for (uint256 i = 0; i < maxStage; ++i) {
            if (stageAllowance[i][user] != 0 && !stageClaimed[i][user]) return i;
        }
        return type(uint256).max;
    }

    function stageEmissionRemaining(uint256 stageId) external view override returns (uint256) {
        uint256 budget = stageEmissionBudget[stageId];
        uint256 spent = stageEmissionSpent[stageId];
        return budget > spent ? budget - spent : 0;
    }

    function payGrandPrize(address to, uint256 amount) external onlyOwner nonReentrant {
        if (uint8(registry.phase()) < uint8(ProtocolPhase.Phase.SETTLED)) revert Errors.WrongPhase();
        if (amount > prizePoolBalance) revert Errors.PotentialOverflow();
        prizePoolBalance -= amount;
        bool success = IERC20(address(hat)).transfer(to, amount);
        require(success, "SafeERC20: transfer failed");
        emit GrandPrizePaid(to, amount);
    }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}