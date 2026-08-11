// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC1155Receiver} from "./interfaces/IERC1155Receiver.sol";
import {IERC165} from "./interfaces/IERC165.sol";
import {IERC721Receiver} from "./interfaces/IERC721Receiver.sol";
import {IStudioToken} from "./interfaces/IStudioToken.sol";
import {IStudioVault} from "./interfaces/IStudioVault.sol";
import {StudioToken} from "./StudioToken.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title StudioVault
/// @notice Governance vault that controls token supply and executes approved treasury actions.
/// @dev Owns the `StudioToken` instance and enforces proposal lifecycle checks before execution.
contract StudioVault is IStudioVault, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error AlreadyClaimed();
    error AlreadyVoted();
    error ArraysLengthMismatch();
    error DurationOutOfBounds();
    error ERC721InDistribute();
    error EthSendFailed();
    error ExternalCallFailed();
    error InvalidAssetType();
    error InvalidProposalType();
    error InvalidSubtype();
    error InvalidTargetParam();
    error NoVotingPower();
    error NotDistribution();
    error NotExecuted();
    error NotTokenOwner();
    error NothingToClaim();
    error ProposalAlreadyExecuted();
    error ProposalIsCancelled();
    error ProposalExpired();
    error ProposalNotInOrder();
    error ProposalNotPassed();
    error RecipientSelf();
    error SelfCallForbidden();
    error StudioTokenCallForbidden();
    error TargetNotCancellable();
    error ThresholdOutOfBounds();
    error VotingClosed();
    error InvalidTargetProposal();
    error ZeroAddress();
    error ZeroAmount();
    error ZeroTargets();
    error ZeroTotalSupply();

    uint16 public constant PARAM_CHANGE_THRESHOLD_BPS_DEFAULT = 5000;
    uint32 public constant PARAM_CHANGE_DURATION_DEFAULT = 86400;
    uint16 public constant DISTRIBUTE_THRESHOLD_BPS_DEFAULT = 5000;
    uint32 public constant DISTRIBUTE_DURATION_DEFAULT = 86400;
    uint16 public constant SUPPLY_OP_THRESHOLD_BPS_DEFAULT = 5000;
    uint32 public constant SUPPLY_OP_DURATION_DEFAULT = 86400;
    uint16 public constant TRANSFER_THRESHOLD_BPS_DEFAULT = 5000;
    uint32 public constant TRANSFER_DURATION_DEFAULT = 86400;
    uint16 public constant EXTERNAL_CALL_THRESHOLD_BPS_DEFAULT = 5000;
    uint32 public constant EXTERNAL_CALL_DURATION_DEFAULT = 86400;
    uint16 public constant CANCEL_THRESHOLD_BPS_DEFAULT = 5000;
    uint32 public constant CANCEL_DURATION_DEFAULT = 86400;
    uint32 public constant EXECUTION_WINDOW_DEFAULT = 86400;
    uint16 public constant MIN_THRESHOLD_BPS = 1;

    uint256 public proposalCount;
    uint256 public queueHead;
    uint32 public executionWindow;
    IStudioToken public immutable studioToken;
    mapping(uint8 => uint16) public thresholdBps;
    mapping(uint8 => uint32) public durationSeconds;
    mapping(uint256 => Proposal) private _proposals;
    mapping(uint256 => mapping(address => bool)) public voted;
    mapping(uint256 => mapping(address => bool)) public claimed;

    enum AssetType {
        ERC20,
        ERC721,
        ERC1155,
        NATIVE
    }

    enum T2Subtype {
        MINT,
        FORCE_TRANSFER
    }

    /// @param name_ Name for the freshly deployed `StudioToken`.
    /// @param symbol_ Symbol for the freshly deployed `StudioToken`.
    /// @param initialSupply Initial token amount minted during bootstrap.
    /// @param initialHolder Recipient of the initial bootstrap mint.
    constructor(string memory name_, string memory symbol_, uint256 initialSupply, address initialHolder) {
        if (bytes(name_).length == 0 || bytes(symbol_).length == 0) revert ZeroAmount();
        if (initialHolder == address(0)) revert ZeroAddress();
        if (initialSupply == 0) revert ZeroAmount();

        studioToken = IStudioToken(address(new StudioToken(name_, symbol_)));
        queueHead = 1;

        thresholdBps[uint8(ProposalType.ParamChange)] = PARAM_CHANGE_THRESHOLD_BPS_DEFAULT;
        thresholdBps[uint8(ProposalType.Distribute)] = DISTRIBUTE_THRESHOLD_BPS_DEFAULT;
        thresholdBps[uint8(ProposalType.SupplyOp)] = SUPPLY_OP_THRESHOLD_BPS_DEFAULT;
        thresholdBps[uint8(ProposalType.Transfer)] = TRANSFER_THRESHOLD_BPS_DEFAULT;
        thresholdBps[uint8(ProposalType.ExternalCall)] = EXTERNAL_CALL_THRESHOLD_BPS_DEFAULT;
        thresholdBps[uint8(ProposalType.Cancel)] = CANCEL_THRESHOLD_BPS_DEFAULT;

        durationSeconds[uint8(ProposalType.ParamChange)] = PARAM_CHANGE_DURATION_DEFAULT;
        durationSeconds[uint8(ProposalType.Distribute)] = DISTRIBUTE_DURATION_DEFAULT;
        durationSeconds[uint8(ProposalType.SupplyOp)] = SUPPLY_OP_DURATION_DEFAULT;
        durationSeconds[uint8(ProposalType.Transfer)] = TRANSFER_DURATION_DEFAULT;
        durationSeconds[uint8(ProposalType.ExternalCall)] = EXTERNAL_CALL_DURATION_DEFAULT;
        durationSeconds[uint8(ProposalType.Cancel)] = CANCEL_DURATION_DEFAULT;
        executionWindow = EXECUTION_WINDOW_DEFAULT;

        studioToken.mint(initialHolder, initialSupply);
        emit StudioTokenDeployed(address(studioToken));
    }

    /// @notice Accepts native token transfers into the vault.
    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    /// @inheritdoc IStudioVault
    function claim(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.proposalType != uint8(ProposalType.Distribute)) revert NotDistribution();
        if (!proposal.executed) revert NotExecuted();
        if (claimed[proposalId][msg.sender]) revert AlreadyClaimed();

        (uint8 assetType, address asset, uint256 tokenId,) =
            abi.decode(proposal.data, (uint8, address, uint256, uint256));
        uint256 holderVotesAtSnapshot = studioToken.getPastVotes(msg.sender, proposal.distSnapshotBlock);
        uint256 totalSupplyAtSnapshot = proposal.totalSupplyAtDistSnapshot;
        if (totalSupplyAtSnapshot == 0) revert ZeroTotalSupply();

        uint256 delivered =
            Math.mulDiv(holderVotesAtSnapshot, proposal.balanceAtDistSnapshot, totalSupplyAtSnapshot, Math.Rounding.Floor);
        uint256 currentBalance = _assetBalance(uint8(assetType), asset, tokenId);
        if (delivered > currentBalance) {
            delivered = currentBalance;
        }
        if (delivered == 0) revert NothingToClaim();

        claimed[proposalId][msg.sender] = true;
        _transferAsset(uint8(assetType), asset, tokenId, delivered, msg.sender);

        emit ClaimedDistribution(proposalId, msg.sender, delivered);
    }

    /// @inheritdoc IStudioVault
    function createProposal(uint8 proposalType, bytes calldata data) external nonReentrant returns (uint256 proposalId) {
        if (studioToken.balanceOf(msg.sender) == 0) revert NoVotingPower();

        if (proposalType == uint8(ProposalType.ParamChange)) {
            return _createProposalParamChange(data);
        }
        if (proposalType == uint8(ProposalType.Distribute)) {
            return _createProposalDistribute(data);
        }
        if (proposalType == uint8(ProposalType.SupplyOp)) {
            return _createProposalSupplyOp(data);
        }
        if (proposalType == uint8(ProposalType.Transfer)) {
            return _createProposalTransfer(data);
        }
        if (proposalType == uint8(ProposalType.ExternalCall)) {
            return _createProposalExternalCall(data);
        }

        revert InvalidProposalType();
    }

    /// @inheritdoc IStudioVault
    function createCancelProposal(uint256 targetProposalId) external nonReentrant returns (uint256 proposalId) {
        if (studioToken.balanceOf(msg.sender) == 0) revert NoVotingPower();
        return _createProposalCancel(abi.encode(targetProposalId));
    }

    /// @inheritdoc IStudioVault
    function execute(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = _proposals[proposalId];
        uint8 proposalType = proposal.proposalType;

        if (proposalType != uint8(ProposalType.Cancel)) {
            uint256 head = getQueueHead();
            if (proposalId != head) revert ProposalNotInOrder();
        }

        ProposalState state = proposalState(proposalId);
        if (state == ProposalState.Expired) revert ProposalExpired();
        if (state != ProposalState.Passed) revert ProposalNotPassed();

        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (block.timestamp > proposal.votingDeadline + proposal.executionWindowAtCreate) revert ProposalExpired();

        proposal.executed = true;

        if (proposalType == uint8(ProposalType.ParamChange)) {
            _executeDispatchParamChange(proposal.data);
        } else if (proposalType == uint8(ProposalType.Distribute)) {
            _executeDispatchDistribute(proposalId, proposal.data);
        } else if (proposalType == uint8(ProposalType.SupplyOp)) {
            _executeDispatchSupplyOp(proposal.data, proposal.creator);
        } else if (proposalType == uint8(ProposalType.Transfer)) {
            _executeDispatchTransfer(proposal.data);
        } else if (proposalType == uint8(ProposalType.ExternalCall)) {
            _executeDispatchExternalCall(proposalId, proposal.data);
        } else if (proposalType == uint8(ProposalType.Cancel)) {
            _executeDispatchCancel(proposalId, proposal.data);
        } else {
            revert InvalidProposalType();
        }

        if (queueHead == 0) {
            queueHead = 1;
        }
        while (queueHead <= proposalCount && _isSkippableInQueue(queueHead)) {
            queueHead++;
        }

        emit ProposalExecuted(proposalId, msg.sender);
    }

    /// @inheritdoc IStudioVault
    function vote(uint256 proposalId) external nonReentrant {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (proposal.cancelled) revert ProposalIsCancelled();
        if (block.timestamp > proposal.votingDeadline) revert VotingClosed();
        if (voted[proposalId][msg.sender]) revert AlreadyVoted();

        uint256 weight = studioToken.getPastVotes(msg.sender, proposal.snapshotBlock);
        if (weight == 0) revert NoVotingPower();

        voted[proposalId][msg.sender] = true;
        proposal.yesVotes += weight;
        emit VoteCast(proposalId, msg.sender, weight, proposal.yesVotes);

        uint256 tsSnap = studioToken.getPastTotalSupply(proposal.snapshotBlock);
        if (
            proposal.passedAt == 0
                && tsSnap > 0
                && proposal.yesVotes * 10000 >= uint256(proposal.thresholdBpsAtCreate) * tsSnap
        ) {
            proposal.passedAt = block.timestamp;
            emit ProposalPassed(proposalId, proposal.passedAt);
        }
    }

    /// @inheritdoc IStudioVault
    function getClaimable(uint256 proposalId, address holder) external view returns (uint256 amount) {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.proposalType != uint8(ProposalType.Distribute) || !proposal.executed || claimed[proposalId][holder]) {
            return 0;
        }

        (uint8 assetType, address asset, uint256 tokenId,) =
            abi.decode(proposal.data, (uint8, address, uint256, uint256));
        uint256 holderVotesAtSnapshot = studioToken.getPastVotes(holder, proposal.distSnapshotBlock);
        uint256 totalSupplyAtSnapshot = proposal.totalSupplyAtDistSnapshot;
        if (holderVotesAtSnapshot == 0 || totalSupplyAtSnapshot == 0) {
            return 0;
        }

        uint256 formulaShare =
            Math.mulDiv(holderVotesAtSnapshot, proposal.balanceAtDistSnapshot, totalSupplyAtSnapshot, Math.Rounding.Floor);
        uint256 currentBalance = _assetBalance(uint8(assetType), asset, tokenId);
        return formulaShare > currentBalance ? currentBalance : formulaShare;
    }

    /// @inheritdoc IStudioVault
    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal) {
        return _proposals[proposalId];
    }

    /// @inheritdoc IStudioVault
    function getQueueHead() public view returns (uint256 head) {
        head = queueHead == 0 ? 1 : queueHead;
        while (head <= proposalCount && _isSkippableInQueue(head)) {
            head++;
        }

        if (head > proposalCount) {
            return proposalCount + 1;
        }
    }

    /// @inheritdoc IStudioVault
    function proposalState(uint256 proposalId) public view returns (IStudioVault.ProposalState state) {
        if (proposalId == 0 || proposalId > proposalCount) {
            return ProposalState.Defeated;
        }

        Proposal storage proposal = _proposals[proposalId];
        if (proposal.executed) {
            return ProposalState.Executed;
        }
        if (proposal.cancelled) {
            return ProposalState.Cancelled;
        }
        if (proposal.passedAt > 0) {
            if (block.timestamp > proposal.votingDeadline + proposal.executionWindowAtCreate) {
                return ProposalState.Expired;
            }
            return ProposalState.Passed;
        }
        if (block.timestamp > proposal.votingDeadline) {
            return ProposalState.Defeated;
        }

        return ProposalState.Active;
    }

    /// @notice Handles safe ERC721 transfers into the vault.
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data)
        external
        returns (bytes4)
    {
        operator;
        data;
        emit ReceivedERC721(msg.sender, from, tokenId);
        return this.onERC721Received.selector;
    }

    /// @notice Handles safe ERC1155 single transfers into the vault.
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data)
        external
        returns (bytes4)
    {
        operator;
        data;
        emit ReceivedERC1155(msg.sender, from, id, value);
        return this.onERC1155Received.selector;
    }

    /// @notice Handles safe ERC1155 batch transfers into the vault.
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4) {
        operator;
        data;
        emit ReceivedERC1155Batch(msg.sender, from, ids, values);
        return this.onERC1155BatchReceived.selector;
    }

    /// @notice Returns whether this contract supports an interface ID.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC721Receiver).interfaceId
            || interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IStudioVault).interfaceId;
    }

    function _createProposalCore(uint8 proposalType, bytes memory data, uint256 customVotingDeadline)
        private
        returns (uint256 proposalId)
    {
        proposalId = ++proposalCount;
        uint256 snapshotBlock = block.number - 1;
        uint16 thresholdAtCreate = thresholdBps[proposalType];
        uint32 windowAtCreate = executionWindow;
        uint256 votingDeadline =
            customVotingDeadline == 0 ? block.timestamp + durationSeconds[proposalType] : customVotingDeadline;

        Proposal storage proposal = _proposals[proposalId];
        proposal.proposalType = proposalType;
        proposal.creator = msg.sender;
        proposal.createdAtBlock = block.number;
        proposal.snapshotBlock = snapshotBlock;
        proposal.votingDeadline = votingDeadline;
        proposal.thresholdBpsAtCreate = thresholdAtCreate;
        proposal.executionWindowAtCreate = windowAtCreate;
        proposal.data = data;

        emit ProposalCreated(
            proposalId, proposalType, msg.sender, data, snapshotBlock, votingDeadline, thresholdAtCreate, windowAtCreate
        );

        uint256 creatorWeight = studioToken.getPastVotes(msg.sender, snapshotBlock);
        uint256 tsSnap = studioToken.getPastTotalSupply(snapshotBlock);
        proposal.yesVotes = creatorWeight;
        voted[proposalId][msg.sender] = true;
        emit VoteCast(proposalId, msg.sender, creatorWeight, creatorWeight);

        if (tsSnap > 0 && creatorWeight * 10000 >= uint256(thresholdAtCreate) * tsSnap) {
            proposal.passedAt = block.timestamp;
            emit ProposalPassed(proposalId, proposal.passedAt);
        }
    }

    function _createProposalTransfer(bytes calldata data) private returns (uint256 proposalId) {
        (uint8 assetType, address asset,, uint256 amount, address recipient) =
            abi.decode(data, (uint8, address, uint256, uint256, address));
        if (recipient == address(0)) revert ZeroAddress();
        if (recipient == address(this)) revert RecipientSelf();
        if (assetType > uint8(AssetType.NATIVE)) revert InvalidAssetType();
        if (assetType != uint8(AssetType.ERC721) && amount == 0) revert ZeroAmount();
        if (assetType != uint8(AssetType.NATIVE) && asset == address(0)) revert ZeroAddress();
        return _createProposalCore(uint8(ProposalType.Transfer), data, 0);
    }

    function _createProposalSupplyOp(bytes calldata data) private returns (uint256 proposalId) {
        (uint8 subtype, address from, address to, uint256 amount) = abi.decode(data, (uint8, address, address, uint256));
        if (subtype > uint8(T2Subtype.FORCE_TRANSFER)) revert InvalidSubtype();
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (from == to && from != address(0)) revert RecipientSelf();

        if (subtype == uint8(T2Subtype.MINT)) {
            if (from != address(0)) revert ZeroAddress();
        } else {
            if (from == address(0)) revert ZeroAddress();
            if (from != msg.sender) revert NotTokenOwner();
        }

        return _createProposalCore(uint8(ProposalType.SupplyOp), data, 0);
    }

    function _createProposalParamChange(bytes calldata data) private returns (uint256 proposalId) {
        (uint8 targetParam, uint256 newValue) = abi.decode(data, (uint8, uint256));
        if (targetParam > 12) revert InvalidTargetParam();

        if (_isThresholdParam(targetParam)) {
            if (newValue < MIN_THRESHOLD_BPS || newValue > 10000) revert ThresholdOutOfBounds();
        } else {
            if (newValue == 0 || newValue > type(uint32).max) revert DurationOutOfBounds();
        }

        return _createProposalCore(uint8(ProposalType.ParamChange), data, 0);
    }

    function _createProposalDistribute(bytes calldata data) private returns (uint256 proposalId) {
        (uint8 assetType, address asset,, uint256 amount) = abi.decode(data, (uint8, address, uint256, uint256));
        if (assetType == uint8(AssetType.ERC721)) revert ERC721InDistribute();
        if (assetType > uint8(AssetType.NATIVE)) revert InvalidAssetType();
        if (amount == 0) revert ZeroAmount();
        if (assetType != uint8(AssetType.NATIVE) && asset == address(0)) revert ZeroAddress();
        return _createProposalCore(uint8(ProposalType.Distribute), data, 0);
    }

    function _createProposalExternalCall(bytes calldata data) private returns (uint256 proposalId) {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            abi.decode(data, (address[], uint256[], bytes[]));
        if (targets.length == 0) revert ZeroTargets();
        if (targets.length != values.length || targets.length != calldatas.length) revert ArraysLengthMismatch();
        return _createProposalCore(uint8(ProposalType.ExternalCall), data, 0);
    }

    function _createProposalCancel(bytes memory data) private returns (uint256 proposalId) {
        uint256 targetProposalId = abi.decode(data, (uint256));
        if (targetProposalId == 0 || targetProposalId > proposalCount) revert InvalidTargetProposal();
        if (targetProposalId == proposalCount + 1) revert InvalidTargetProposal();
        if (proposalState(targetProposalId) != ProposalState.Passed) revert TargetNotCancellable();

        Proposal storage target = _proposals[targetProposalId];
        uint256 targetExpiry = target.votingDeadline + target.executionWindowAtCreate;
        uint256 desiredDeadline = block.timestamp + durationSeconds[uint8(ProposalType.Cancel)];
        uint256 cappedDeadline = desiredDeadline < targetExpiry ? desiredDeadline : targetExpiry;

        return _createProposalCore(uint8(ProposalType.Cancel), data, cappedDeadline);
    }

    function _executeDispatchTransfer(bytes memory data) private {
        (uint8 assetType, address asset, uint256 tokenId, uint256 amount, address recipient) =
            abi.decode(data, (uint8, address, uint256, uint256, address));
        _transferAsset(assetType, asset, tokenId, amount, recipient);
    }

    function _executeDispatchSupplyOp(bytes memory data, address creator) private {
        (uint8 subtype, address from, address to, uint256 amount) = abi.decode(data, (uint8, address, address, uint256));

        if (subtype == uint8(T2Subtype.MINT)) {
            if (from != address(0)) revert ZeroAddress();
            studioToken.mint(to, amount);
            return;
        }
        if (subtype == uint8(T2Subtype.FORCE_TRANSFER)) {
            if (from != creator) revert NotTokenOwner();
            studioToken.forceTransfer(from, to, amount);
            return;
        }
        revert InvalidSubtype();
    }

    function _executeDispatchParamChange(bytes memory data) private {
        (uint8 targetParam, uint256 newValue) = abi.decode(data, (uint8, uint256));
        if (targetParam > 12) revert InvalidTargetParam();

        if (_isThresholdParam(targetParam)) {
            if (newValue < MIN_THRESHOLD_BPS || newValue > 10000) revert ThresholdOutOfBounds();
        } else if (newValue == 0 || newValue > type(uint32).max) {
            revert DurationOutOfBounds();
        }

        uint256 oldValue = _readGovernanceParam(targetParam);
        _writeGovernanceParam(targetParam, newValue);
        emit GovernanceParamChanged(targetParam, oldValue, newValue);
    }

    function _executeDispatchDistribute(uint256 proposalId, bytes memory data) private {
        Proposal storage proposal = _proposals[proposalId];
        (uint8 assetType, address asset, uint256 tokenId, uint256 amount) = abi.decode(data, (uint8, address, uint256, uint256));

        if (assetType == uint8(AssetType.ERC721)) revert ERC721InDistribute();
        uint256 distSnapshotBlock = proposal.snapshotBlock;
        uint256 totalSupplyAtSnapshot = studioToken.getPastTotalSupply(distSnapshotBlock);
        if (totalSupplyAtSnapshot == 0) revert ZeroTotalSupply();

        uint256 balanceAtSnapshot = _assetBalance(assetType, asset, tokenId);
        uint256 pool = Math.min(amount, balanceAtSnapshot);

        proposal.distSnapshotBlock = distSnapshotBlock;
        proposal.totalSupplyAtDistSnapshot = totalSupplyAtSnapshot;
        proposal.balanceAtDistSnapshot = pool;

        emit DistributionSnapshot(proposalId, asset, pool, totalSupplyAtSnapshot, distSnapshotBlock);
    }

    function _executeDispatchExternalCall(uint256 proposalId, bytes memory data) private {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas) =
            abi.decode(data, (address[], uint256[], bytes[]));

        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];
            uint256 value = values[i];
            bytes memory callData = calldatas[i];

            if (target == address(this)) revert SelfCallForbidden();
            if (target == address(studioToken)) revert StudioTokenCallForbidden();

            (bool success,) = target.call{value: value}(callData);
            if (!success) revert ExternalCallFailed();

            bytes4 selector = callData.length >= 4 ? bytes4(callData) : bytes4(0);
            emit T5BatchEntryExecuted(proposalId, i, target, value, selector);
        }
    }

    function _executeDispatchCancel(uint256 cancelProposalId, bytes memory data) private {
        uint256 targetProposalId = abi.decode(data, (uint256));
        if (targetProposalId == 0 || targetProposalId > proposalCount) revert InvalidTargetProposal();
        if (proposalState(targetProposalId) != ProposalState.Passed) revert TargetNotCancellable();

        Proposal storage target = _proposals[targetProposalId];
        target.cancelled = true;
        emit ProposalCancelled(targetProposalId, cancelProposalId);
    }

    function _readGovernanceParam(uint8 targetParam) private view returns (uint256) {
        if (targetParam == 0) return thresholdBps[uint8(ProposalType.ParamChange)];
        if (targetParam == 1) return durationSeconds[uint8(ProposalType.ParamChange)];
        if (targetParam == 2) return thresholdBps[uint8(ProposalType.Distribute)];
        if (targetParam == 3) return durationSeconds[uint8(ProposalType.Distribute)];
        if (targetParam == 4) return thresholdBps[uint8(ProposalType.SupplyOp)];
        if (targetParam == 5) return durationSeconds[uint8(ProposalType.SupplyOp)];
        if (targetParam == 6) return thresholdBps[uint8(ProposalType.Transfer)];
        if (targetParam == 7) return durationSeconds[uint8(ProposalType.Transfer)];
        if (targetParam == 8) return thresholdBps[uint8(ProposalType.ExternalCall)];
        if (targetParam == 9) return durationSeconds[uint8(ProposalType.ExternalCall)];
        if (targetParam == 10) return executionWindow;
        if (targetParam == 11) return thresholdBps[uint8(ProposalType.Cancel)];
        if (targetParam == 12) return durationSeconds[uint8(ProposalType.Cancel)];
        revert InvalidTargetParam();
    }

    function _writeGovernanceParam(uint8 targetParam, uint256 newValue) private {
        if (targetParam == 0) {
            thresholdBps[uint8(ProposalType.ParamChange)] = uint16(newValue);
            return;
        }
        if (targetParam == 1) {
            durationSeconds[uint8(ProposalType.ParamChange)] = uint32(newValue);
            return;
        }
        if (targetParam == 2) {
            thresholdBps[uint8(ProposalType.Distribute)] = uint16(newValue);
            return;
        }
        if (targetParam == 3) {
            durationSeconds[uint8(ProposalType.Distribute)] = uint32(newValue);
            return;
        }
        if (targetParam == 4) {
            thresholdBps[uint8(ProposalType.SupplyOp)] = uint16(newValue);
            return;
        }
        if (targetParam == 5) {
            durationSeconds[uint8(ProposalType.SupplyOp)] = uint32(newValue);
            return;
        }
        if (targetParam == 6) {
            thresholdBps[uint8(ProposalType.Transfer)] = uint16(newValue);
            return;
        }
        if (targetParam == 7) {
            durationSeconds[uint8(ProposalType.Transfer)] = uint32(newValue);
            return;
        }
        if (targetParam == 8) {
            thresholdBps[uint8(ProposalType.ExternalCall)] = uint16(newValue);
            return;
        }
        if (targetParam == 9) {
            durationSeconds[uint8(ProposalType.ExternalCall)] = uint32(newValue);
            return;
        }
        if (targetParam == 10) {
            executionWindow = uint32(newValue);
            return;
        }
        if (targetParam == 11) {
            thresholdBps[uint8(ProposalType.Cancel)] = uint16(newValue);
            return;
        }
        if (targetParam == 12) {
            durationSeconds[uint8(ProposalType.Cancel)] = uint32(newValue);
            return;
        }
        revert InvalidTargetParam();
    }

    function _transferAsset(uint8 assetType, address asset, uint256 tokenId, uint256 amount, address recipient) private {
        if (assetType == uint8(AssetType.NATIVE)) {
            (bool success,) = payable(recipient).call{value: amount}("");
            if (!success) revert EthSendFailed();
            return;
        }

        if (assetType == uint8(AssetType.ERC20)) {
            IERC20(asset).safeTransfer(recipient, amount);
            return;
        }

        if (assetType == uint8(AssetType.ERC721)) {
            IERC721(asset).safeTransferFrom(address(this), recipient, tokenId);
            return;
        }

        if (assetType == uint8(AssetType.ERC1155)) {
            IERC1155(asset).safeTransferFrom(address(this), recipient, tokenId, amount, "");
            return;
        }

        revert InvalidAssetType();
    }

    function _assetBalance(uint8 assetType, address asset, uint256 tokenId) private view returns (uint256) {
        if (assetType == uint8(AssetType.NATIVE)) return address(this).balance;
        if (assetType == uint8(AssetType.ERC20)) return IERC20(asset).balanceOf(address(this));
        if (assetType == uint8(AssetType.ERC1155)) return IERC1155(asset).balanceOf(address(this), tokenId);
        if (assetType == uint8(AssetType.ERC721)) return IERC721(asset).ownerOf(tokenId) == address(this) ? 1 : 0;
        revert InvalidAssetType();
    }

    function _isThresholdParam(uint8 targetParam) private pure returns (bool) {
        return targetParam == 0 || targetParam == 2 || targetParam == 4 || targetParam == 6 || targetParam == 8
            || targetParam == 11;
    }

    function _isSkippableInQueue(uint256 proposalId) private view returns (bool) {
        Proposal storage proposal = _proposals[proposalId];
        if (proposal.proposalType == uint8(ProposalType.Cancel)) {
            return true;
        }

        return _isTerminal(proposalState(proposalId));
    }

    function _isTerminal(ProposalState state) private pure returns (bool) {
        return state == ProposalState.Executed || state == ProposalState.Expired || state == ProposalState.Defeated
            || state == ProposalState.Cancelled;
    }
}
