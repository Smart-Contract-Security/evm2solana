// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC165} from "./IERC165.sol";
import {IERC721Receiver} from "./IERC721Receiver.sol";
import {IERC1155Receiver} from "./IERC1155Receiver.sol";

/// @title IStudioVault
/// @notice Governance vault that owns StudioToken and executes approved proposals.
interface IStudioVault is IERC165, IERC721Receiver, IERC1155Receiver {
    /// @notice Supported proposal categories.
    enum ProposalType {
        None,
        ParamChange,
        Distribute,
        SupplyOp,
        Transfer,
        ExternalCall,
        Cancel
    }

    /// @notice Current proposal lifecycle state.
    enum ProposalState {
        Active,
        Passed,
        Defeated,
        Expired,
        Executed,
        Cancelled
    }

    /// @notice On-chain proposal record.
    struct Proposal {
        uint8 proposalType;
        address creator;
        uint256 createdAtBlock;
        uint256 snapshotBlock;
        uint256 votingDeadline;
        uint16 thresholdBpsAtCreate;
        uint32 executionWindowAtCreate;
        uint256 yesVotes;
        uint256 passedAt;
        bool executed;
        bool cancelled;
        uint256 distSnapshotBlock;
        uint256 totalSupplyAtDistSnapshot;
        uint256 balanceAtDistSnapshot;
        bytes data;
    }

    /// @notice Emitted when a proposal is created.
    event ProposalCreated(
        uint256 indexed proposalId,
        uint8 indexed proposalType,
        address indexed creator,
        bytes data,
        uint256 snapshotBlock,
        uint256 votingDeadline,
        uint16 thresholdBpsAtCreate,
        uint32 executionWindowAtCreate
    );
    /// @notice Emitted when a holder votes in favor of a proposal.
    event VoteCast(uint256 indexed proposalId, address indexed voter, uint256 weight, uint256 newYesVotes);
    /// @notice Emitted when quorum threshold is reached.
    event ProposalPassed(uint256 indexed proposalId, uint256 passedAt);
    /// @notice Emitted when a passed proposal is executed.
    event ProposalExecuted(uint256 indexed proposalId, address indexed executor);
    /// @notice Emitted when a cancel proposal invalidates a target proposal.
    event ProposalCancelled(uint256 indexed targetProposalId, uint256 indexed cancelProposalId);
    /// @notice Emitted when a holder claims distribution proceeds.
    event ClaimedDistribution(uint256 indexed proposalId, address indexed holder, uint256 delivered);
    /// @notice Emitted when a governance parameter value is changed.
    event GovernanceParamChanged(uint8 indexed targetParam, uint256 oldValue, uint256 newValue);
    /// @notice Emitted when distribution snapshot values are fixed during execution.
    event DistributionSnapshot(
        uint256 indexed proposalId,
        address asset,
        uint256 balanceAtDistSnapshot,
        uint256 totalSupplyAtDistSnapshot,
        uint256 distSnapshotBlock
    );
    /// @notice Emitted for each executed step in an external-call batch.
    event T5BatchEntryExecuted(
        uint256 indexed proposalId, uint256 idx, address indexed target, uint256 value, bytes4 indexed selector
    );
    /// @notice Emitted when the StudioToken instance is deployed.
    event StudioTokenDeployed(address indexed token);
    /// @notice Emitted when native token is received.
    event ReceivedETH(address indexed sender, uint256 value);
    /// @notice Emitted when an ERC721 token is received.
    event ReceivedERC721(address indexed token, address indexed from, uint256 indexed tokenId);
    /// @notice Emitted when an ERC1155 single transfer is received.
    event ReceivedERC1155(address indexed token, address indexed from, uint256 indexed id, uint256 amount);
    /// @notice Emitted when an ERC1155 batch transfer is received.
    event ReceivedERC1155Batch(address indexed token, address indexed from, uint256[] ids, uint256[] amounts);

    /// @notice Creates a new governance proposal.
    /// @param proposalType Encoded `ProposalType` value.
    /// @param data ABI-encoded payload expected by the given proposal type.
    /// @return proposalId Newly assigned proposal identifier.
    function createProposal(uint8 proposalType, bytes calldata data) external returns (uint256 proposalId);

    /// @notice Creates a cancel proposal targeting a currently passed proposal.
    /// @param targetProposalId Proposal to cancel.
    /// @return proposalId Newly assigned cancel-proposal identifier.
    function createCancelProposal(uint256 targetProposalId) external returns (uint256 proposalId);

    /// @notice Casts an affirmative vote using snapshot voting power.
    /// @param proposalId Proposal to vote for.
    function vote(uint256 proposalId) external;

    /// @notice Executes a passed proposal that is still within execution window.
    /// @param proposalId Proposal to execute.
    function execute(uint256 proposalId) external;

    /// @notice Claims caller's share from an executed distribution proposal.
    /// @param proposalId Distribution proposal identifier.
    function claim(uint256 proposalId) external;

    /// @notice Returns currently claimable distribution amount for a holder.
    /// @param proposalId Distribution proposal identifier.
    /// @param holder Holder to evaluate.
    /// @return amount Claimable amount under current vault balances.
    function getClaimable(uint256 proposalId, address holder) external view returns (uint256 amount);

    /// @notice Returns stored proposal data by identifier.
    /// @param proposalId Proposal identifier.
    /// @return proposal Full proposal struct.
    function getProposal(uint256 proposalId) external view returns (Proposal memory proposal);

    /// @notice Returns first non-terminal proposal in FIFO queue.
    /// @return head Current executable queue head or `proposalCount + 1`.
    function getQueueHead() external view returns (uint256 head);

    /// @notice Computes current proposal state.
    /// @param proposalId Proposal identifier.
    /// @return state Current proposal state.
    function proposalState(uint256 proposalId) external view returns (ProposalState state);
}
