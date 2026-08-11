// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice EIP-4788 / SSZ verifier for post-Capella execution block hashes.
/// @dev Adapted from Axiom's MIT-licensed beacon-blockhash-verifier. This
///      version is view-only and returns the proven block hash instead of
///      storing it in verifier-local storage.
contract BeaconBlockhashVerifier {
    enum ProofKind {
        CurrentBlock,
        RecentHistoricalBlock,
        HistoricalBlock
    }

    struct SszProof {
        bytes32 leaf;
        bytes32[] proof;
    }

    struct CurrentBlockProof {
        uint256 timestamp;
        SszProof currentStateRootProof;
        SszProof executionPayloadProof;
        SszProof blockNumberProof;
        SszProof blockhashProof;
    }

    struct RecentHistoricalBlockProof {
        uint256 timestamp;
        SszProof currentStateRootProof;
        SszProof historicalStateRootProof;
        uint256 historicalStateRootLocalIndex;
        SszProof executionPayloadProof;
        SszProof blockNumberProof;
        SszProof blockhashProof;
    }

    struct HistoricalBlockProof {
        uint256 timestamp;
        SszProof currentStateRootProof;
        SszProof summaryRootProof;
        uint256 stateSummaryRootLocalIndex;
        SszProof historicalStateRootProof;
        uint256 historicalStateRootLocalIndex;
        SszProof executionPayloadProof;
        SszProof blockNumberProof;
        SszProof blockhashProof;
    }

    address internal constant BEACON_ROOTS = 0x000F3df6D732807Ef1319fB7B8bB8522d0Beac02;

    // --- Container tree heights (pinned to the current fork: Fulu) -------
    //
    // The beacon block, beacon state, and execution-payload-header are SSZ
    // *containers*; a container's Merkle tree height is ceil(log2(fieldCount)).
    // These are schema-specific and pinned to the live mainnet layout. They
    // change only when a fork's field count crosses a power of two (e.g. the
    // BeaconState went 28 fields / height 5 in Deneb -> 37 / height 6 in
    // Electra+). We pin them so the verifier fails *closed* if the schema ever
    // diverges from what it was built for, rather than fail open by accepting
    // a proof of the wrong node. The next state-tree crossing (64 fields) is
    // many forks away; when it happens, deploy a new verifier with new heights.
    uint256 internal constant BLOCK_TREE_HEIGHT = 3; // BeaconBlock (5 fields)
    uint256 internal constant BEACON_STATE_TREE_HEIGHT = 6; // Fulu BeaconState (37 fields)
    uint256 internal constant EXECUTION_PAYLOAD_HEADER_TREE_HEIGHT = 5; // ExecutionPayloadHeader (17 fields)

    // --- Fixed structural heights ---------------------------------------
    // Vectors/lists with stable SSZ presets; part of the type, not a fork's
    // field count.
    uint256 internal constant HISTORICAL_SUMMARY_TREE_HEIGHT = 1; // HistoricalSummary (2 fields)
    uint256 internal constant STATE_ROOTS_VECTOR_TREE_HEIGHT = 13; // Vector[Root, 8192]
    uint256 internal constant HISTORICAL_SUMMARY_ROOT_VECTOR_TREE_HEIGHT = 24; // List[HistoricalSummary, 2^24]

    // Combined proof depths through the BeaconState container.
    uint256 internal constant HISTORICAL_STATE_ROOT_PROOF_HEIGHT =
        BEACON_STATE_TREE_HEIGHT + STATE_ROOTS_VECTOR_TREE_HEIGHT; // 6 + 13 = 19
    uint256 internal constant HISTORICAL_STATE_SUMMARY_ROOT_PROOF_HEIGHT =
        BEACON_STATE_TREE_HEIGHT + HISTORICAL_SUMMARY_TREE_HEIGHT + HISTORICAL_SUMMARY_ROOT_VECTOR_TREE_HEIGHT + 1; // 32

    uint256 internal constant STATE_ROOT_LOCAL_INDEX = 3;
    uint256 internal constant EXECUTION_PAYLOAD_LOCAL_INDEX = 24;
    uint256 internal constant BLOCK_NUMBER_LOCAL_INDEX = 6;
    uint256 internal constant BLOCKHASH_LOCAL_INDEX = 12;
    uint256 internal constant STATE_SUMMARY_ROOT_LOCAL_INDEX = 1;
    uint256 internal constant STATE_ROOTS_VECTOR_LOCAL_INDEX = 6;
    uint256 internal constant HISTORICAL_SUMMARY_LIST_LOCAL_INDEX = 27;

    uint256 internal constant STATE_ROOTS_VECTOR_NODES = 2 ** STATE_ROOTS_VECTOR_TREE_HEIGHT;
    uint256 internal constant STATE_ROOTS_VECTOR_MIN_LOCAL_INDEX =
        STATE_ROOTS_VECTOR_NODES * STATE_ROOTS_VECTOR_LOCAL_INDEX;
    uint256 internal constant STATE_ROOTS_VECTOR_MAX_LOCAL_INDEX =
        STATE_ROOTS_VECTOR_MIN_LOCAL_INDEX + STATE_ROOTS_VECTOR_NODES;

    uint256 internal constant HR_NODES_PER_S_NODE = 2 ** (HISTORICAL_SUMMARY_ROOT_VECTOR_TREE_HEIGHT + 1);
    uint256 internal constant HSF_NODES_PER_S_NODE = HR_NODES_PER_S_NODE * (2 ** HISTORICAL_SUMMARY_TREE_HEIGHT);
    uint256 internal constant HISTORICAL_SUMMARY_FIELDS_LOCAL_INDEX_MIN =
        HSF_NODES_PER_S_NODE * HISTORICAL_SUMMARY_LIST_LOCAL_INDEX;
    uint256 internal constant HISTORICAL_SUMMARY_TREE_NODES = 2 ** HISTORICAL_SUMMARY_TREE_HEIGHT;
    uint256 internal constant HISTORICAL_SUMMARY_VECTOR_LIMIT = 2 ** HISTORICAL_SUMMARY_ROOT_VECTOR_TREE_HEIGHT;
    uint256 internal constant HISTORICAL_SUMMARY_FIELDS_LOCAL_INDEX_MAX =
        HISTORICAL_SUMMARY_FIELDS_LOCAL_INDEX_MIN + (HISTORICAL_SUMMARY_VECTOR_LIMIT * HISTORICAL_SUMMARY_TREE_NODES);
    uint256 internal constant STATE_SUMMARY_TREE_MAX_LOCAL_INDEX = 2 ** STATE_ROOTS_VECTOR_TREE_HEIGHT;

    error BeaconRootFetchFailed();
    error InvalidProofKind();
    error InvalidCurrentStateRoot();
    error InvalidSummaryRoot();
    error InvalidHistoricalStateRoot();
    error InvalidExecutionPayload();
    error InvalidBlockNumber();
    error InvalidBlockhash();

    /// @notice Opaque proof entrypoint used by RandaoOracle.
    /// @dev Encode proof as:
    ///      abi.encode(ProofKind.HistoricalBlock, abi.encode(HistoricalBlockProof(...)))
    ///      and similarly for the other proof kinds.
    function verifyBlockHash(uint64 blockNumber, bytes calldata proof) public view virtual returns (bytes32 blockHash) {
        (ProofKind kind, bytes memory encodedProof) = abi.decode(proof, (ProofKind, bytes));

        if (kind == ProofKind.CurrentBlock) {
            return verifyCurrentBlockhash(blockNumber, abi.decode(encodedProof, (CurrentBlockProof)));
        }
        if (kind == ProofKind.RecentHistoricalBlock) {
            return verifyRecentHistoricalBlockhash(blockNumber, abi.decode(encodedProof, (RecentHistoricalBlockProof)));
        }
        if (kind == ProofKind.HistoricalBlock) {
            return verifyHistoricalBlockhash(blockNumber, abi.decode(encodedProof, (HistoricalBlockProof)));
        }

        revert InvalidProofKind();
    }

    function verifyCurrentBlockhash(uint64 blockNumber, CurrentBlockProof memory proof)
        public
        view
        returns (bytes32 blockHash)
    {
        bytes32 currentBeaconBlockRoot = _fetchBeaconRoot(proof.timestamp);

        _verifyBeaconStateRoot(proof.currentStateRootProof, currentBeaconBlockRoot);
        _verifyExecutionPayload(proof.executionPayloadProof, proof.currentStateRootProof.leaf);
        _verifyExecutionBlockNumber(proof.blockNumberProof, proof.executionPayloadProof.leaf, blockNumber);
        _verifyExecutionBlockhash(proof.blockhashProof, proof.executionPayloadProof.leaf);

        return proof.blockhashProof.leaf;
    }

    function verifyRecentHistoricalBlockhash(uint64 blockNumber, RecentHistoricalBlockProof memory proof)
        public
        view
        returns (bytes32 blockHash)
    {
        bytes32 currentBeaconBlockRoot = _fetchBeaconRoot(proof.timestamp);

        _verifyBeaconStateRoot(proof.currentStateRootProof, currentBeaconBlockRoot);
        _verifyHistoricalStateRootIntoBeaconStateRoot(
            proof.historicalStateRootProof, proof.historicalStateRootLocalIndex, proof.currentStateRootProof.leaf
        );
        _verifyExecutionPayload(proof.executionPayloadProof, proof.historicalStateRootProof.leaf);
        _verifyExecutionBlockNumber(proof.blockNumberProof, proof.executionPayloadProof.leaf, blockNumber);
        _verifyExecutionBlockhash(proof.blockhashProof, proof.executionPayloadProof.leaf);

        return proof.blockhashProof.leaf;
    }

    function verifyHistoricalBlockhash(uint64 blockNumber, HistoricalBlockProof memory proof)
        public
        view
        returns (bytes32 blockHash)
    {
        bytes32 currentBeaconBlockRoot = _fetchBeaconRoot(proof.timestamp);

        _verifyBeaconStateRoot(proof.currentStateRootProof, currentBeaconBlockRoot);
        _verifyHistoricalStateSummaryRoot(
            proof.summaryRootProof, proof.stateSummaryRootLocalIndex, proof.currentStateRootProof.leaf
        );
        _verifyHistoricalStateRootIntoStateSummaryRoot(
            proof.historicalStateRootProof, proof.historicalStateRootLocalIndex, proof.summaryRootProof.leaf
        );
        _verifyExecutionPayload(proof.executionPayloadProof, proof.historicalStateRootProof.leaf);
        _verifyExecutionBlockNumber(proof.blockNumberProof, proof.executionPayloadProof.leaf, blockNumber);
        _verifyExecutionBlockhash(proof.blockhashProof, proof.executionPayloadProof.leaf);

        return proof.blockhashProof.leaf;
    }

    function _verifyBeaconStateRoot(SszProof memory stateRootProof, bytes32 beaconBlockRoot) internal pure {
        // state_root in the BeaconBlock container.
        if (!_processInclusionProofSha256({
                proof: stateRootProof.proof,
                leaf: stateRootProof.leaf,
                localIndex: STATE_ROOT_LOCAL_INDEX,
                root: beaconBlockRoot,
                expectedHeight: BLOCK_TREE_HEIGHT
            })) revert InvalidCurrentStateRoot();
    }

    function _verifyHistoricalStateRootIntoBeaconStateRoot(
        SszProof memory historicalStateRootProof,
        uint256 historicalStateRootLocalIndex,
        bytes32 beaconStateRoot
    ) internal pure {
        if (
            historicalStateRootLocalIndex < STATE_ROOTS_VECTOR_MIN_LOCAL_INDEX
                || historicalStateRootLocalIndex >= STATE_ROOTS_VECTOR_MAX_LOCAL_INDEX
        ) revert InvalidHistoricalStateRoot();

        // state_roots vector (13) hanging off the BeaconState container (6).
        if (!_processInclusionProofSha256({
                proof: historicalStateRootProof.proof,
                leaf: historicalStateRootProof.leaf,
                localIndex: historicalStateRootLocalIndex,
                root: beaconStateRoot,
                expectedHeight: HISTORICAL_STATE_ROOT_PROOF_HEIGHT
            })) revert InvalidHistoricalStateRoot();
    }

    function _verifyHistoricalStateSummaryRoot(
        SszProof memory summaryRootProof,
        uint256 stateSummaryRootLocalIndex,
        bytes32 beaconStateRoot
    ) internal pure {
        if (stateSummaryRootLocalIndex % HISTORICAL_SUMMARY_TREE_NODES != STATE_SUMMARY_ROOT_LOCAL_INDEX) {
            revert InvalidSummaryRoot();
        }
        if (
            stateSummaryRootLocalIndex < HISTORICAL_SUMMARY_FIELDS_LOCAL_INDEX_MIN
                || stateSummaryRootLocalIndex >= HISTORICAL_SUMMARY_FIELDS_LOCAL_INDEX_MAX
        ) revert InvalidSummaryRoot();

        // historical_summaries list + HistoricalSummary container + length
        // mix-in beneath the BeaconState container (6): 6 + 1 + 24 + 1 = 32.
        if (!_processInclusionProofSha256({
                proof: summaryRootProof.proof,
                leaf: summaryRootProof.leaf,
                localIndex: stateSummaryRootLocalIndex,
                root: beaconStateRoot,
                expectedHeight: HISTORICAL_STATE_SUMMARY_ROOT_PROOF_HEIGHT
            })) revert InvalidSummaryRoot();
    }

    function _verifyHistoricalStateRootIntoStateSummaryRoot(
        SszProof memory historicalStateRootProof,
        uint256 historicalStateRootLocalIndex,
        bytes32 stateSummaryRoot
    ) internal pure {
        if (historicalStateRootLocalIndex >= STATE_SUMMARY_TREE_MAX_LOCAL_INDEX) {
            revert InvalidHistoricalStateRoot();
        }

        // Pure state_roots vector (a state_summary_root is the root of one such
        // vector): fixed height 13, no container traversal.
        if (!_processInclusionProofSha256({
                proof: historicalStateRootProof.proof,
                leaf: historicalStateRootProof.leaf,
                root: stateSummaryRoot,
                localIndex: historicalStateRootLocalIndex,
                expectedHeight: STATE_ROOTS_VECTOR_TREE_HEIGHT
            })) revert InvalidHistoricalStateRoot();
    }

    function _verifyExecutionPayload(SszProof memory executionPayloadProof, bytes32 beaconStateRoot) internal pure {
        // latest_execution_payload_header in the BeaconState container (6).
        if (!_processInclusionProofSha256({
                proof: executionPayloadProof.proof,
                leaf: executionPayloadProof.leaf,
                root: beaconStateRoot,
                localIndex: EXECUTION_PAYLOAD_LOCAL_INDEX,
                expectedHeight: BEACON_STATE_TREE_HEIGHT
            })) revert InvalidExecutionPayload();
    }

    function _verifyExecutionBlockNumber(
        SszProof memory blockNumberProof,
        bytes32 executionPayloadRoot,
        uint64 expectedBlockNumber
    ) internal pure {
        // block_number in the ExecutionPayloadHeader container (5).
        if (!_processInclusionProofSha256({
                proof: blockNumberProof.proof,
                leaf: blockNumberProof.leaf,
                root: executionPayloadRoot,
                localIndex: BLOCK_NUMBER_LOCAL_INDEX,
                expectedHeight: EXECUTION_PAYLOAD_HEADER_TREE_HEIGHT
            })) revert InvalidBlockNumber();

        if (_parseSszUint64(blockNumberProof.leaf) != expectedBlockNumber) {
            revert InvalidBlockNumber();
        }
    }

    function _verifyExecutionBlockhash(SszProof memory blockhashProof, bytes32 executionPayloadRoot) internal pure {
        // block_hash in the ExecutionPayloadHeader container (5).
        if (!_processInclusionProofSha256({
                proof: blockhashProof.proof,
                leaf: blockhashProof.leaf,
                root: executionPayloadRoot,
                localIndex: BLOCKHASH_LOCAL_INDEX,
                expectedHeight: EXECUTION_PAYLOAD_HEADER_TREE_HEIGHT
            })) revert InvalidBlockhash();
    }

    /// @dev Verifies an SSZ Merkle inclusion proof of `leaf` at `localIndex`
    ///      against `root`, requiring the branch to be exactly `expectedHeight`
    ///      deep. `localIndex` must fit within that height, otherwise the loop
    ///      would silently drop its high bits and prove a different node than
    ///      the caller named.
    function _processInclusionProofSha256(
        bytes32[] memory proof,
        bytes32 leaf,
        bytes32 root,
        uint256 localIndex,
        uint256 expectedHeight
    ) internal pure returns (bool valid) {
        if (proof.length != expectedHeight) return false;
        if (localIndex >= 2 ** expectedHeight) return false;

        bytes32 node = leaf;
        for (uint256 i = 0; i < expectedHeight; i++) {
            bytes32 sibling = proof[i];
            if (localIndex % 2 == 0) {
                node = sha256(abi.encodePacked(node, sibling));
            } else {
                node = sha256(abi.encodePacked(sibling, node));
            }
            localIndex /= 2;
        }

        return node == root;
    }

    function _fetchBeaconRoot(uint256 rootTimestamp) internal view returns (bytes32 beaconRoot) {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, rootTimestamp)
            if iszero(staticcall(gas(), BEACON_ROOTS, 0x00, 0x20, 0x00, 0x20)) {
                mstore(0x00, 0x1aa72f96) // `BeaconRootFetchFailed()`.
                revert(0x1c, 0x04)
            }
            beaconRoot := mload(0x00)
        }
    }

    function _parseSszUint64(bytes32 leaf) internal pure returns (uint64 value) {
        // SSZ encodes uint64 little-endian: byte i contributes value * 256**i.
        uint256 parsed;
        for (uint256 i = 0; i < 8; i++) {
            parsed += uint256(uint8(leaf[i])) * (256 ** i);
        }
        for (uint256 i = 8; i < 32; i++) {
            if (leaf[i] != bytes1(0)) revert InvalidBlockNumber();
        }
        value = uint64(parsed);
    }
}
