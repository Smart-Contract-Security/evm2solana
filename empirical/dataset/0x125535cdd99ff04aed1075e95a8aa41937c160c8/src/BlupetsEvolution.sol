// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IBlupetsCore} from "./IBlupetsCore.sol";
import {IBlupetsRandomness} from "./IBlupetsRandomness.sol";
import {BlupetsEvolutionMatrix} from "./BlupetsEvolutionMatrix.sol";

contract BlupetsEvolution {
    enum RequestKind {
        None,
        Reveal,
        BatchReveal,
        Merge
    }

    struct PendingRequest {
        RequestKind kind;
        address user;
        uint256 keeperId;
        uint256 burnId;
        uint8 fromStage;
        uint8 nextStage;
        uint8 lineage;
        uint8 vibe;
        bool fulfilled;
        uint16 finalizedCount;
        uint64 requestedAt;
        uint256 randomWord;
    }

    uint8 public constant STAGE_T0 = 0;
    uint8 public constant STAGE_T1 = 1;
    uint8 public constant STAGE_T2 = 2;
    uint8 public constant STAGE_T3 = 3;
    uint8 public constant STAGE_T4 = 4;
    uint8 public constant LINEAGE_ORIGIN = 36;
    uint8 public constant FORM_UNHATCHED = 0;
    uint8 public constant FLAG_CUSTOM_HATCH = 1;
    uint8 public constant BASE_LINEAGE_COUNT = 8;
    uint8 public constant FAMILY_LINEAGE_COUNT = 36;
    uint8 public constant LINEAGE_COUNT = BASE_LINEAGE_COUNT;
    uint8 public constant VIBE_COUNT = 64;
    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint16 public constant CUSTOM_HATCH_BPS = 25;
    uint256 public constant MAX_BATCH_REVEAL = 20;
    uint256 public constant REQUEST_TIMEOUT = 0;

    IBlupetsCore public immutable core;
    IBlupetsRandomness public randomness;
    address public owner;
    bool public revealPaused;
    bool public mergePaused;

    mapping(uint256 => PendingRequest) public requests;
    mapping(uint256 => address) public requestRandomness;
    mapping(uint256 => uint256[]) private _batchRevealTokens;
    mapping(uint256 => uint256) public tokenToRequest;

    event RevealRequested(uint256 indexed tokenId, uint256 indexed requestId);
    event BatchRevealRequested(uint256 indexed requestId, address indexed owner, uint256 count);
    event RandomnessReceived(uint256 indexed requestId, RequestKind kind);
    event RevealResolved(uint256 indexed tokenId, uint8 lineage, uint8 vibe, bool customHatch);
    event BatchRevealFinalized(uint256 indexed requestId, uint256 finalizedCount, uint256 totalCount);
    event MergeRequested(
        uint256 indexed keeperId,
        uint256 indexed burnId,
        uint256 indexed requestId,
        uint8 fromStage,
        uint8 toStage,
        uint8 vibe
    );
    event MergeResolved(
        uint256 indexed keeperId, uint256 indexed burnId, uint8 fromStage, uint8 toStage, uint8 lineage, uint8 form
    );
    event RequestCanceled(uint256 indexed requestId, RequestKind kind, uint256 unlockedCount);
    event RandomnessUpdated(address indexed randomness);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error NotOwner();
    error NotRandomness();
    error NotTokenOwner();
    error InvalidStage();
    error InvalidBatchSize();
    error SameToken();
    error Incompatible();
    error TokenPending();
    error UnknownRequest();
    error RequestNotFulfilled();
    error InvalidVibeSource();
    error InvalidOwner();
    error InvalidDependency();
    error InvalidRandomnessRequest();
    error InvalidTokenId();
    error RequestAlreadyFulfilled();

    constructor(address core_, address randomness_) {
        if (core_ == address(0) || randomness_ == address(0)) revert InvalidDependency();
        core = IBlupetsCore(core_);
        randomness = IBlupetsRandomness(randomness_);
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidOwner();
        owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }

    function setRandomness(address randomness_) external onlyOwner {
        if (randomness_ == address(0)) revert InvalidDependency();
        randomness = IBlupetsRandomness(randomness_);
        emit RandomnessUpdated(randomness_);
    }

    function setRevealPaused(bool paused) external onlyOwner {
        revealPaused = paused;
    }

    function setMergePaused(bool paused) external onlyOwner {
        mergePaused = paused;
    }

    function requestReveal(uint256 tokenId) external returns (uint256 requestId) {
        if (revealPaused) revert InvalidStage();
        if (core.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (tokenToRequest[tokenId] != 0 || core.isTokenLocked(tokenId)) revert TokenPending();

        IBlupetsCore.TokenState memory state = core.tokenState(tokenId);
        if (state.stage != STAGE_T0) revert InvalidStage();

        core.lockToken(tokenId);
        requestId = _requestRandomWords();
        requestRandomness[requestId] = address(randomness);
        requests[requestId] = PendingRequest({
            kind: RequestKind.Reveal,
            user: msg.sender,
            keeperId: tokenId,
            burnId: 0,
            fromStage: STAGE_T0,
            nextStage: STAGE_T1,
            lineage: 0,
            vibe: 0,
            fulfilled: false,
            finalizedCount: 0,
            requestedAt: uint64(block.timestamp),
            randomWord: 0
        });
        tokenToRequest[tokenId] = requestId;
        emit RevealRequested(tokenId, requestId);
    }

    function requestBatchReveal(uint256[] calldata tokenIds) external returns (uint256 requestId) {
        if (revealPaused) revert InvalidStage();
        if (tokenIds.length == 0 || tokenIds.length > MAX_BATCH_REVEAL) revert InvalidBatchSize();

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            if (core.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
            if (tokenToRequest[tokenId] != 0 || core.isTokenLocked(tokenId)) revert TokenPending();
            for (uint256 j = 0; j < i; j++) {
                if (tokenIds[j] == tokenId) revert TokenPending();
            }

            IBlupetsCore.TokenState memory state = core.tokenState(tokenId);
            if (state.stage != STAGE_T0) revert InvalidStage();
        }

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            core.lockToken(tokenId);
        }

        requestId = _requestRandomWords();
        requestRandomness[requestId] = address(randomness);
        requests[requestId] = PendingRequest({
            kind: RequestKind.BatchReveal,
            user: msg.sender,
            keeperId: tokenIds[0],
            burnId: 0,
            fromStage: STAGE_T0,
            nextStage: STAGE_T1,
            lineage: 0,
            vibe: 0,
            fulfilled: false,
            finalizedCount: 0,
            requestedAt: uint64(block.timestamp),
            randomWord: 0
        });

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            tokenToRequest[tokenId] = requestId;
            _batchRevealTokens[requestId].push(tokenId);
            emit RevealRequested(tokenId, requestId);
        }

        emit BatchRevealRequested(requestId, msg.sender, tokenIds.length);
    }

    function requestMerge(uint256 keeperId, uint256 burnId, uint256 vibeSourceTokenId)
        external
        returns (uint256 requestId)
    {
        if (mergePaused) revert InvalidStage();
        if (keeperId == burnId) revert SameToken();
        if (keeperId > type(uint32).max || burnId > type(uint32).max) revert InvalidTokenId();
        if (vibeSourceTokenId != keeperId && vibeSourceTokenId != burnId) revert InvalidVibeSource();
        if (core.ownerOf(keeperId) != msg.sender || core.ownerOf(burnId) != msg.sender) revert NotTokenOwner();
        if (
            tokenToRequest[keeperId] != 0 || tokenToRequest[burnId] != 0 || core.isTokenLocked(keeperId)
                || core.isTokenLocked(burnId)
        ) {
            revert TokenPending();
        }

        IBlupetsCore.TokenState memory keeper = core.tokenState(keeperId);
        IBlupetsCore.TokenState memory burner = core.tokenState(burnId);
        if (keeper.stage < STAGE_T1 || keeper.stage > STAGE_T3 || burner.stage != keeper.stage) revert InvalidStage();
        if ((keeper.flags & FLAG_CUSTOM_HATCH) != 0 || (burner.flags & FLAG_CUSTOM_HATCH) != 0) revert InvalidStage();

        uint8 vibe = vibeSourceTokenId == keeperId ? keeper.vibe : burner.vibe;
        uint8 nextStage = keeper.stage + 1;
        uint8 nextLineage = _mergeLineage(keeper.stage, keeper.lineage, burner.lineage);
        core.lockToken(keeperId);
        core.lockToken(burnId);
        requestId = _requestRandomWords();
        requestRandomness[requestId] = address(randomness);

        requests[requestId] = PendingRequest({
            kind: RequestKind.Merge,
            user: msg.sender,
            keeperId: keeperId,
            burnId: burnId,
            fromStage: keeper.stage,
            nextStage: nextStage,
            lineage: nextLineage,
            vibe: vibe,
            fulfilled: false,
            finalizedCount: 0,
            requestedAt: uint64(block.timestamp),
            randomWord: 0
        });
        tokenToRequest[keeperId] = requestId;
        tokenToRequest[burnId] = requestId;

        emit MergeRequested(keeperId, burnId, requestId, keeper.stage, nextStage, vibe);
    }

    function rawFulfillRandomWords(uint256 requestId, uint256 randomWord) external {
        address expectedRandomness = requestRandomness[requestId];
        if (expectedRandomness == address(0)) revert UnknownRequest();
        if (msg.sender != expectedRandomness) revert NotRandomness();
        delete requestRandomness[requestId];
        PendingRequest storage request = requests[requestId];
        if (request.kind == RequestKind.None) revert UnknownRequest();

        request.randomWord = randomWord;
        request.fulfilled = true;
        emit RandomnessReceived(requestId, request.kind);
    }

    function finalizeRequest(uint256 requestId, uint256 maxItems) external {
        PendingRequest memory request = requests[requestId];
        if (request.kind == RequestKind.None) revert UnknownRequest();
        if (!request.fulfilled) revert RequestNotFulfilled();

        if (request.kind == RequestKind.BatchReveal) {
            _finalizeBatchReveal(requestId, request.randomWord, maxItems);
        } else if (request.kind == RequestKind.Reveal) {
            delete requests[requestId];
            _resolveReveal(request, request.randomWord);
        } else if (request.kind == RequestKind.Merge) {
            delete requests[requestId];
            _resolveMerge(request, request.randomWord);
        } else {
            revert UnknownRequest();
        }
    }

    function cancelUnfulfilledRequest(uint256 requestId, uint256 maxItems) external onlyOwner {
        PendingRequest memory request = requests[requestId];
        if (request.kind == RequestKind.None) revert UnknownRequest();
        if (request.fulfilled) revert RequestAlreadyFulfilled();

        delete requestRandomness[requestId];

        if (request.kind == RequestKind.BatchReveal) {
            _cancelExpiredBatchReveal(requestId, request, maxItems);
        } else if (request.kind == RequestKind.Reveal) {
            delete requests[requestId];
            delete tokenToRequest[request.keeperId];
            core.unlockToken(request.keeperId);
            emit RequestCanceled(requestId, request.kind, 1);
        } else if (request.kind == RequestKind.Merge) {
            delete requests[requestId];
            delete tokenToRequest[request.keeperId];
            delete tokenToRequest[request.burnId];
            core.unlockToken(request.keeperId);
            core.unlockToken(request.burnId);
            emit RequestCanceled(requestId, request.kind, 2);
        } else {
            revert UnknownRequest();
        }
    }

    function batchRevealTokenIds(uint256 requestId) external view returns (uint256[] memory) {
        return _batchRevealTokens[requestId];
    }

    function familyLineageForBasePair(uint8 a, uint8 b) external pure returns (uint8) {
        return BlupetsEvolutionMatrix.familyLineageForBasePair(a, b);
    }

    function _finalizeBatchReveal(uint256 requestId, uint256 randomWord, uint256 maxItems) internal {
        if (maxItems == 0) revert InvalidBatchSize();

        PendingRequest storage request = requests[requestId];
        uint256[] storage tokenIds = _batchRevealTokens[requestId];
        uint256 totalCount = tokenIds.length;
        uint256 start = request.finalizedCount;
        if (totalCount == 0 || start >= totalCount) revert UnknownRequest();

        uint256 end = start + maxItems;
        if (end > totalCount) end = totalCount;

        for (uint256 i = start; i < end; i++) {
            uint256 tokenId = tokenIds[i];
            PendingRequest memory revealRequest = PendingRequest({
                kind: RequestKind.Reveal,
                user: request.user,
                keeperId: tokenId,
                burnId: 0,
                fromStage: STAGE_T0,
                nextStage: STAGE_T1,
                lineage: 0,
                vibe: 0,
                fulfilled: true,
                finalizedCount: 0,
                requestedAt: request.requestedAt,
                randomWord: 0
            });
            _resolveReveal(revealRequest, uint256(keccak256(abi.encode(randomWord, tokenId, i))));
        }

        if (end == totalCount) {
            delete _batchRevealTokens[requestId];
            delete requests[requestId];
        } else {
            // casting to uint16 is safe because totalCount is bounded by MAX_BATCH_REVEAL.
            // forge-lint: disable-next-line(unsafe-typecast)
            request.finalizedCount = uint16(end);
        }

        emit BatchRevealFinalized(requestId, end, totalCount);
    }

    function _cancelExpiredBatchReveal(uint256 requestId, PendingRequest memory request, uint256 maxItems) internal {
        if (maxItems == 0) revert InvalidBatchSize();

        uint256[] storage tokenIds = _batchRevealTokens[requestId];
        uint256 totalCount = tokenIds.length;
        uint256 start = request.finalizedCount;
        if (totalCount == 0 || start >= totalCount) revert UnknownRequest();

        uint256 end = start + maxItems;
        if (end > totalCount) end = totalCount;

        for (uint256 i = start; i < end; i++) {
            uint256 tokenId = tokenIds[i];
            delete tokenToRequest[tokenId];
            core.unlockToken(tokenId);
        }

        if (end == totalCount) {
            delete _batchRevealTokens[requestId];
            delete requests[requestId];
        } else {
            // casting to uint16 is safe because totalCount is bounded by MAX_BATCH_REVEAL.
            // forge-lint: disable-next-line(unsafe-typecast)
            requests[requestId].finalizedCount = uint16(end);
        }

        emit RequestCanceled(requestId, request.kind, end - start);
    }

    function _resolveReveal(PendingRequest memory request, uint256 randomWord) internal {
        uint256 tokenId = request.keeperId;
        delete tokenToRequest[tokenId];

        IBlupetsCore.TokenState memory nextState = core.tokenState(tokenId);
        uint8 vibe = uint8(uint256(keccak256(abi.encode(randomWord, tokenId, "VIBE"))) % VIBE_COUNT);
        bool customHatch =
            uint256(keccak256(abi.encode(randomWord, tokenId, "HATCH"))) % BPS_DENOMINATOR < CUSTOM_HATCH_BPS;

        nextState.vibe = vibe;
        nextState.parentA = 0;
        nextState.parentB = 0;
        if (customHatch) {
            nextState.stage = STAGE_T4;
            nextState.lineage = LINEAGE_ORIGIN;
            nextState.form = FORM_UNHATCHED;
            nextState.flags |= FLAG_CUSTOM_HATCH;
        } else {
            nextState.stage = STAGE_T1;
            nextState.lineage =
                uint8(uint256(keccak256(abi.encode(randomWord, tokenId, "LINEAGE"))) % BASE_LINEAGE_COUNT);
            nextState.form = 0;
            nextState.flags = 0;
        }
        nextState.updatedAt = uint64(block.timestamp);

        core.evolve(tokenId, nextState);
        emit RevealResolved(tokenId, nextState.lineage, vibe, customHatch);
    }

    function _resolveMerge(PendingRequest memory request, uint256 randomWord) internal {
        delete tokenToRequest[request.keeperId];
        delete tokenToRequest[request.burnId];

        IBlupetsCore.TokenState memory nextState = core.tokenState(request.keeperId);
        nextState.stage = request.nextStage;
        nextState.lineage = request.lineage;
        nextState.form = BlupetsEvolutionMatrix.rollForm(request.nextStage, randomWord);
        nextState.vibe = request.vibe;
        nextState.flags = 0;
        nextState.parentA = uint32(request.keeperId);
        nextState.parentB = uint32(request.burnId);
        nextState.updatedAt = uint64(block.timestamp);

        core.burnForMerge(request.burnId);
        core.evolve(request.keeperId, nextState);
        emit MergeResolved(
            request.keeperId, request.burnId, request.fromStage, request.nextStage, request.lineage, nextState.form
        );
    }

    function _mergeLineage(uint8 stage, uint8 keeperLineage, uint8 burnerLineage) internal pure returns (uint8) {
        if (stage == STAGE_T1) {
            if (keeperLineage >= BASE_LINEAGE_COUNT || burnerLineage >= BASE_LINEAGE_COUNT) revert InvalidStage();
            return BlupetsEvolutionMatrix.familyLineageForBasePair(keeperLineage, burnerLineage);
        }

        if (stage == STAGE_T2 || stage == STAGE_T3) {
            if (keeperLineage >= FAMILY_LINEAGE_COUNT || burnerLineage >= FAMILY_LINEAGE_COUNT) revert InvalidStage();
            if (keeperLineage != burnerLineage) revert Incompatible();
            return keeperLineage;
        }

        revert InvalidStage();
    }

    function _requestRandomWords() internal returns (uint256 requestId) {
        requestId = randomness.requestRandomWords();
        if (
            requestId == 0 || requestRandomness[requestId] != address(0) || requests[requestId].kind != RequestKind.None
        ) {
            revert InvalidRandomnessRequest();
        }
    }
}
