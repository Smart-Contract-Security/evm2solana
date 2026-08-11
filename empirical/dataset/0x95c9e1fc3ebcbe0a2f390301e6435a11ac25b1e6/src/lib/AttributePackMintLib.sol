// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../LibPRNG.sol";
import "../interfaces/IVRFCoordinatorV2_5.sol";

library AttributePackMintLib {
    using LibPRNG for LibPRNG.PRNG;

    struct RequestSlots {
        uint256 shufflerSlot;
        uint256 pendingReservedTokensSlot;
        uint256 usedTicketsSlot;
        uint256 pendingMintRequestsSlot;
    }

    struct RequestConfig {
        uint256 totalAttributeSupply;
        address signerAddress;
        uint8 maxTokensPerMint;
        address vrfCoordinator;
        uint256 vrfSubscriptionId;
        bytes32 vrfKeyHash;
        uint32 vrfCallbackGasLimit;
        uint16 vrfRequestConfirmations;
        address team;
    }

    struct RequestInput {
        uint256 numberOfTokens;
        uint256 ticketId;
        uint256 totalPrice;
    }

    error ExceedsMaxBatchSize();
    error InsufficientPayment();
    error InsufficientRemainingSupply();
    error InvalidSignature();
    error TicketAlreadyUsed();
    error UnknownRequest();
    error VRFNotTimedOut();
    error InvalidTypeId();
    error FeeTransferFailed();

    event AttributeMinted(address indexed to, uint256 indexed typeId, uint256 randomValue);
    event TicketUsed(uint256 indexed ticketId, address indexed minter, uint256 numberOfTokens, uint256 totalPrice);
    event VRFMintRequested(uint256 indexed requestId, address indexed minter, uint256 numberOfTokens, uint256 ticketId);
    event VRFTimedOut(uint256 indexed oldRequestId, uint256 indexed newRequestId, address indexed minter);
    event VRFMintCancelled(uint256 indexed requestId, address indexed minter, uint256 numberOfTokens);

    function requestMint(
        RequestSlots memory slots,
        RequestConfig memory config,
        RequestInput memory input,
        bytes calldata signature
    ) external {
        if (input.numberOfTokens == 0 || input.numberOfTokens > config.maxTokensPerMint) {
            revert ExceedsMaxBatchSize();
        }
        uint256 remainingTokens =
            config.totalAttributeSupply - _numShuffled(slots.shufflerSlot) - _load(slots.pendingReservedTokensSlot);
        if (remainingTokens < input.numberOfTokens) revert InsufficientRemainingSupply();
        if (msg.value != input.totalPrice) revert InsufficientPayment();
        if (_boolMappingValue(slots.usedTicketsSlot, input.ticketId)) revert TicketAlreadyUsed();

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                msg.sender, input.numberOfTokens, input.ticketId, input.totalPrice, address(this), block.chainid
            )
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        if (_recoverSigner(ethSignedMessageHash, signature) != config.signerAddress) revert InvalidSignature();

        _setBoolMappingValue(slots.usedTicketsSlot, input.ticketId, true);
        _distributePayment(config.team, msg.value);
        _store(slots.pendingReservedTokensSlot, _load(slots.pendingReservedTokensSlot) + input.numberOfTokens);

        uint256 requestId = IVRFCoordinatorV2_5(config.vrfCoordinator)
            .requestRandomWords(
                VRFV2PlusClient.RandomWordsRequest({
                keyHash: config.vrfKeyHash,
                subId: config.vrfSubscriptionId,
                requestConfirmations: config.vrfRequestConfirmations,
                callbackGasLimit: config.vrfCallbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
            })
            );

        _storeMintRequest(
            slots.pendingMintRequestsSlot, requestId, msg.sender, uint32(input.numberOfTokens), input.ticketId
        );

        emit VRFMintRequested(requestId, msg.sender, input.numberOfTokens, input.ticketId);
        emit TicketUsed(input.ticketId, msg.sender, input.numberOfTokens, input.totalPrice);
    }

    function drawMint(
        uint256 shufflerSlot,
        uint256 cumulativeSuppliesSlot,
        uint256 addedTokenIdsSlot,
        uint256 remainingSupplyPerTokenSlot,
        address minter,
        uint256 numberOfTokens,
        uint256 randomWord
    ) external returns (uint256[] memory ids, uint256[] memory amounts) {
        LibPRNG.PRNG memory prng;
        prng.seed(randomWord);

        ids = new uint256[](numberOfTokens);
        amounts = new uint256[](numberOfTokens);

        for (uint256 i = 0; i < numberOfTokens;) {
            uint256 shuffledIndex = LibPRNG.next(_shuffler(shufflerSlot), prng.next());
            uint256 typeIdToMint = _tokenIdForShuffledIndex(cumulativeSuppliesSlot, addedTokenIdsSlot, shuffledIndex);

            ids[i] = typeIdToMint;
            amounts[i] = 1;
            _setUintMappingValue(
                remainingSupplyPerTokenSlot,
                typeIdToMint,
                _uintMappingValue(remainingSupplyPerTokenSlot, typeIdToMint) - 1
            );

            emit AttributeMinted(minter, typeIdToMint, prng.state);

            unchecked {
                ++i;
            }
        }
    }

    function recoverFromVRFTimeout(
        uint256 pendingMintRequestsSlot,
        address vrfCoordinator,
        uint256 vrfSubscriptionId,
        bytes32 vrfKeyHash,
        uint32 vrfCallbackGasLimit,
        uint16 vrfRequestConfirmations,
        uint256 oldRequestId
    ) external {
        (address minter, uint32 numberOfTokens, uint64 requestTime, uint256 ticketId) =
            _loadMintRequest(pendingMintRequestsSlot, oldRequestId);
        if (minter == address(0)) revert UnknownRequest();
        if (block.timestamp <= requestTime + 24 hours) revert VRFNotTimedOut();

        _clearMintRequest(pendingMintRequestsSlot, oldRequestId);

        uint256 newRequestId = IVRFCoordinatorV2_5(vrfCoordinator)
            .requestRandomWords(
                VRFV2PlusClient.RandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: vrfRequestConfirmations,
                callbackGasLimit: vrfCallbackGasLimit,
                numWords: 1,
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: true}))
            })
            );

        _storeMintRequest(pendingMintRequestsSlot, newRequestId, minter, numberOfTokens, ticketId);

        emit VRFTimedOut(oldRequestId, newRequestId, minter);
    }

    function emergencyCancelMintRequest(
        uint256 pendingMintRequestsSlot,
        uint256 pendingReservedTokensSlot,
        uint256 requestId
    ) external {
        (address minter, uint32 numberOfTokens,,) = _loadMintRequest(pendingMintRequestsSlot, requestId);
        if (minter == address(0)) revert UnknownRequest();
        _clearMintRequest(pendingMintRequestsSlot, requestId);
        _store(pendingReservedTokensSlot, _load(pendingReservedTokensSlot) - numberOfTokens);
        emit VRFMintCancelled(requestId, minter, numberOfTokens);
    }

    function _tokenIdForShuffledIndex(uint256 cumulativeSuppliesSlot, uint256 addedTokenIdsSlot, uint256 shuffledIndex)
        private
        view
        returns (uint256)
    {
        uint256 length = _arrayLength(cumulativeSuppliesSlot);
        uint256 low = 0;
        uint256 high = length;
        while (low < high) {
            uint256 mid = (low + high) >> 1;
            if (shuffledIndex < _arrayValue(cumulativeSuppliesSlot, mid)) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        if (low == length) revert InvalidTypeId();
        return _arrayValue(addedTokenIdsSlot, low);
    }

    function _loadMintRequest(uint256 pendingMintRequestsSlot, uint256 requestId)
        private
        view
        returns (address minter, uint32 numberOfTokens, uint64 requestTime, uint256 ticketId)
    {
        bytes32 baseSlot = _mappingValueSlot(pendingMintRequestsSlot, requestId);
        uint256 packed;
        assembly {
            packed := sload(baseSlot)
            ticketId := sload(add(baseSlot, 1))
        }
        minter = address(uint160(packed));
        requestTime = uint64(packed >> 160);
        numberOfTokens = uint32(packed >> 224);
    }

    function _storeMintRequest(
        uint256 pendingMintRequestsSlot,
        uint256 requestId,
        address minter,
        uint32 numberOfTokens,
        uint256 ticketId
    ) private {
        bytes32 baseSlot = _mappingValueSlot(pendingMintRequestsSlot, requestId);
        uint256 packed = uint160(minter) | (uint256(uint64(block.timestamp)) << 160) | (uint256(numberOfTokens) << 224);
        assembly {
            sstore(baseSlot, packed)
            sstore(add(baseSlot, 1), ticketId)
        }
    }

    function _clearMintRequest(uint256 pendingMintRequestsSlot, uint256 requestId) private {
        bytes32 baseSlot = _mappingValueSlot(pendingMintRequestsSlot, requestId);
        assembly {
            sstore(baseSlot, 0)
            sstore(add(baseSlot, 1), 0)
        }
    }

    function _recoverSigner(bytes32 hash, bytes calldata signature) private pure returns (address) {
        if (signature.length != 65) return address(0);

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) return address(0);

        return ecrecover(hash, v, r, s);
    }

    function _distributePayment(address team, uint256 totalAmount) private {
        if (totalAmount == 0) return;
        _sendETH(team, totalAmount);
    }

    function _sendETH(address recipient, uint256 amount) private {
        if (amount == 0) return;
        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert FeeTransferFailed();
    }

    function _shuffler(uint256 shufflerSlot) private pure returns (LibPRNG.LazyShuffler storage shuffler) {
        assembly {
            shuffler.slot := shufflerSlot
        }
    }

    function _numShuffled(uint256 shufflerSlot) private view returns (uint256 result) {
        assembly {
            result := and(0xffffffff, sload(shufflerSlot))
        }
    }

    function _load(uint256 slot) private view returns (uint256 value) {
        assembly {
            value := sload(slot)
        }
    }

    function _store(uint256 slot, uint256 value) private {
        assembly {
            sstore(slot, value)
        }
    }

    function _arrayLength(uint256 arraySlot) private view returns (uint256 length) {
        assembly {
            length := sload(arraySlot)
        }
    }

    function _arrayValue(uint256 arraySlot, uint256 index) private view returns (uint256 value) {
        assembly {
            mstore(0x00, arraySlot)
            value := sload(add(keccak256(0x00, 0x20), index))
        }
    }

    function _uintMappingValue(uint256 mappingSlot, uint256 key) private view returns (uint256 value) {
        bytes32 valueSlot = _mappingValueSlot(mappingSlot, key);
        assembly {
            value := sload(valueSlot)
        }
    }

    function _setUintMappingValue(uint256 mappingSlot, uint256 key, uint256 value) private {
        bytes32 valueSlot = _mappingValueSlot(mappingSlot, key);
        assembly {
            sstore(valueSlot, value)
        }
    }

    function _boolMappingValue(uint256 mappingSlot, uint256 key) private view returns (bool value) {
        bytes32 valueSlot = _mappingValueSlot(mappingSlot, key);
        assembly {
            value := iszero(iszero(sload(valueSlot)))
        }
    }

    function _setBoolMappingValue(uint256 mappingSlot, uint256 key, bool value) private {
        bytes32 valueSlot = _mappingValueSlot(mappingSlot, key);
        assembly {
            sstore(valueSlot, value)
        }
    }

    function _mappingValueSlot(uint256 mappingSlot, uint256 key) private pure returns (bytes32 valueSlot) {
        assembly {
            mstore(0x00, key)
            mstore(0x20, mappingSlot)
            valueSlot := keccak256(0x00, 0x40)
        }
    }
}
