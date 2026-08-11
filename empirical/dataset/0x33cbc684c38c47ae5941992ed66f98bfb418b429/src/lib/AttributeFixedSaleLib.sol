// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

library AttributeFixedSaleLib {
    uint16 internal constant BASE_POINTS = 10000;
    uint16 internal constant FIXED_SALE_ARTIST_POINTS = 3000;
    uint64 internal constant DEFAULT_FIXED_SALE_DURATION = 24 hours;

    struct FixedSaleConfig {
        address artist;
        uint96 unitPrice;
        uint32 saleSupply;
        uint32 minted;
        uint64 saleStart;
        uint64 saleEnd;
        uint16 artistPoints;
        uint16 artistFreeClaimAllowance;
        uint16 treasuryFreeClaimAllowance;
        bool active;
        bool exists;
    }

    struct FixedSaleClaimed {
        uint16 artist;
        uint16 treasury;
    }

    error ExceedsMaxBatchSize();
    error InvalidFixedSaleTreasury();
    error InvalidFixedSaleConfig();
    error FixedSaleInactive();
    error FixedSaleNotStarted();
    error FixedSaleEnded();
    error FixedSaleSoldOut();
    error InvalidFixedSaleSignature();
    error FixedSaleTicketExpired();
    error NotEligibleUpgradedHolder();
    error FixedSaleAllocationExceeded();
    error ExactPaymentRequired();
    error InvalidAttributeContract();
    error TicketAlreadyUsed();
    error FixedSaleTransferFailed();

    event TicketUsed(uint256 indexed ticketId, address indexed minter, uint256 numberOfTokens, uint256 totalPrice);
    event FixedSaleTokenConfigured(
        uint256 indexed tokenId,
        address indexed artist,
        uint96 unitPrice,
        uint32 saleSupply,
        uint64 saleStart,
        uint64 saleEnd,
        uint16 artistPoints,
        uint16 artistFreeClaimAllowance,
        uint16 treasuryFreeClaimAllowance,
        bool active
    );
    event FixedSaleMinted(
        address indexed buyer,
        uint256 indexed tokenId,
        uint32 quantity,
        uint256 indexed eligibleDePunkTokenId,
        uint256 totalPrice,
        uint256 artistAmount,
        uint256 treasuryAmount
    );
    event FixedSaleAllocationClaimed(
        address indexed claimer, uint256 indexed tokenId, uint32 quantity, bool artistAllocation
    );

    function configureFixedSaleToken(
        uint256 fixedSaleConfigsSlot,
        uint256 fixedSaleTokenIdsSlot,
        uint256 maxSuppliesSlot,
        uint256 fixedSaleClaimedSlot,
        uint256 tokenId,
        address artist,
        uint96 unitPrice,
        uint32 saleSupply,
        uint64 saleStart,
        uint64 saleEnd,
        uint16 artistPoints,
        uint16 artistFreeClaimAllowance,
        uint16 treasuryFreeClaimAllowance,
        bool active
    ) external {
        if (
            tokenId == 0 || _uintMappingValue(maxSuppliesSlot, tokenId) != 0 || artist == address(0) || unitPrice == 0
                || saleSupply == 0
        ) {
            revert InvalidFixedSaleConfig();
        }
        if (artistPoints != FIXED_SALE_ARTIST_POINTS) revert InvalidFixedSaleConfig();
        uint64 effectiveSaleStart = saleStart == 0 ? uint64(block.timestamp) : saleStart;
        uint64 effectiveSaleEnd = saleEnd == 0 ? effectiveSaleStart + DEFAULT_FIXED_SALE_DURATION : saleEnd;
        if (effectiveSaleEnd <= effectiveSaleStart) revert InvalidFixedSaleConfig();

        FixedSaleConfig storage config = _config(fixedSaleConfigsSlot, tokenId);
        if (!config.exists) {
            _pushArrayValue(fixedSaleTokenIdsSlot, tokenId);
            config.exists = true;
        } else if (config.minted > 0 || block.timestamp >= config.saleStart) {
            if (
                config.unitPrice != unitPrice || config.saleSupply != saleSupply
                    || config.saleStart != effectiveSaleStart || config.saleEnd != effectiveSaleEnd
            ) {
                revert InvalidFixedSaleConfig();
            }
        }
        if (config.minted > saleSupply) revert InvalidFixedSaleConfig();
        FixedSaleClaimed storage claimed = _claimed(fixedSaleClaimedSlot, tokenId);
        if (claimed.artist > artistFreeClaimAllowance || claimed.treasury > treasuryFreeClaimAllowance) {
            revert InvalidFixedSaleConfig();
        }

        config.artist = artist;
        config.unitPrice = unitPrice;
        config.saleSupply = saleSupply;
        config.saleStart = effectiveSaleStart;
        config.saleEnd = effectiveSaleEnd;
        config.artistPoints = artistPoints;
        config.artistFreeClaimAllowance = artistFreeClaimAllowance;
        config.treasuryFreeClaimAllowance = treasuryFreeClaimAllowance;
        config.active = active;

        emit FixedSaleTokenConfigured(
            tokenId,
            artist,
            unitPrice,
            saleSupply,
            effectiveSaleStart,
            effectiveSaleEnd,
            artistPoints,
            artistFreeClaimAllowance,
            treasuryFreeClaimAllowance,
            active
        );
    }

    function mintFixedSaleToken(
        uint256 fixedSaleConfigsSlot,
        uint256 usedTicketsSlot,
        address dePunkContract,
        address signerAddress,
        address fixedSaleTreasury,
        uint256 tokenId,
        uint32 quantity,
        uint256 eligibleDePunkTokenId,
        uint256 ticketId,
        uint256 totalPrice,
        uint256 deadline,
        bytes calldata signature
    ) external {
        FixedSaleConfig storage config = _config(fixedSaleConfigsSlot, tokenId);
        if (!config.exists || !config.active) revert FixedSaleInactive();
        if (quantity == 0) revert ExceedsMaxBatchSize();
        if (block.timestamp < config.saleStart) revert FixedSaleNotStarted();
        if (block.timestamp > config.saleEnd) revert FixedSaleEnded();
        if (block.timestamp > deadline) revert FixedSaleTicketExpired();
        if (_boolMappingValue(usedTicketsSlot, ticketId)) revert TicketAlreadyUsed();
        if (msg.value != totalPrice || totalPrice != uint256(config.unitPrice) * quantity) {
            revert ExactPaymentRequired();
        }
        if (fixedSaleTreasury == address(0)) revert InvalidFixedSaleTreasury();
        if (config.minted + quantity > config.saleSupply) revert FixedSaleSoldOut();

        _validateUpgradedHolder(dePunkContract, eligibleDePunkTokenId);
        _verifyFixedSaleSignature(
            signerAddress, tokenId, quantity, eligibleDePunkTokenId, ticketId, totalPrice, deadline, signature
        );

        _setBoolMappingValue(usedTicketsSlot, ticketId, true);
        config.minted += quantity;

        (uint256 artistAmount, uint256 treasuryAmount) =
            _distributeFixedSalePayment(config.artist, config.artistPoints, fixedSaleTreasury, msg.value);

        emit TicketUsed(ticketId, msg.sender, quantity, totalPrice);
        emit FixedSaleMinted(
            msg.sender, tokenId, quantity, eligibleDePunkTokenId, totalPrice, artistAmount, treasuryAmount
        );
    }

    function claimFixedSaleAllocation(
        uint256 fixedSaleConfigsSlot,
        uint256 fixedSaleClaimedSlot,
        address fixedSaleTreasury,
        uint256 tokenId,
        uint32 quantity
    ) external {
        FixedSaleConfig storage config = _config(fixedSaleConfigsSlot, tokenId);
        if (!config.exists) revert FixedSaleInactive();
        if (quantity == 0) revert ExceedsMaxBatchSize();
        if (config.minted + quantity > config.saleSupply) revert FixedSaleSoldOut();

        FixedSaleClaimed storage claimed = _claimed(fixedSaleClaimedSlot, tokenId);
        bool artistAllocation;
        if (msg.sender == config.artist) {
            if (claimed.artist + quantity > config.artistFreeClaimAllowance) {
                revert FixedSaleAllocationExceeded();
            }
            claimed.artist += uint16(quantity);
            artistAllocation = true;
        } else if (msg.sender == fixedSaleTreasury) {
            if (claimed.treasury + quantity > config.treasuryFreeClaimAllowance) {
                revert FixedSaleAllocationExceeded();
            }
            claimed.treasury += uint16(quantity);
        } else {
            revert FixedSaleAllocationExceeded();
        }

        config.minted += quantity;
        emit FixedSaleAllocationClaimed(msg.sender, tokenId, quantity, artistAllocation);
    }

    function getFixedSaleTokenIds(uint256 fixedSaleTokenIdsSlot) external view returns (uint256[] memory) {
        uint256[] storage tokenIds = _tokenIds(fixedSaleTokenIdsSlot);
        return tokenIds;
    }

    function getFixedSaleConfig(uint256 fixedSaleConfigsSlot, uint256 tokenId)
        external
        view
        returns (FixedSaleConfig memory)
    {
        FixedSaleConfig storage config = _config(fixedSaleConfigsSlot, tokenId);
        if (!config.exists) revert InvalidTypeId();
        return config;
    }

    function getFixedSaleRemainingSupply(uint256 fixedSaleConfigsSlot, uint256 tokenId)
        external
        view
        returns (uint256)
    {
        FixedSaleConfig storage config = _config(fixedSaleConfigsSlot, tokenId);
        if (!config.exists) revert InvalidTypeId();
        return config.saleSupply - config.minted;
    }

    function getFixedSaleClaimed(uint256 fixedSaleConfigsSlot, uint256 fixedSaleClaimedSlot, uint256 tokenId)
        external
        view
        returns (uint16 artistClaimed, uint16 treasuryClaimed)
    {
        if (!_config(fixedSaleConfigsSlot, tokenId).exists) revert InvalidTypeId();
        FixedSaleClaimed storage claimed = _claimed(fixedSaleClaimedSlot, tokenId);
        return (claimed.artist, claimed.treasury);
    }

    error InvalidTypeId();

    function _config(uint256 fixedSaleConfigsSlot, uint256 tokenId)
        private
        pure
        returns (FixedSaleConfig storage config)
    {
        bytes32 slot = _mappingValueSlot(fixedSaleConfigsSlot, tokenId);
        assembly {
            config.slot := slot
        }
    }

    function _claimed(uint256 fixedSaleClaimedSlot, uint256 tokenId)
        private
        pure
        returns (FixedSaleClaimed storage claimed)
    {
        bytes32 slot = _mappingValueSlot(fixedSaleClaimedSlot, tokenId);
        assembly {
            claimed.slot := slot
        }
    }

    function _tokenIds(uint256 fixedSaleTokenIdsSlot) private pure returns (uint256[] storage tokenIds) {
        assembly {
            tokenIds.slot := fixedSaleTokenIdsSlot
        }
    }

    function _uintMappingValue(uint256 mappingSlot, uint256 key) private view returns (uint256 value) {
        bytes32 valueSlot = _mappingValueSlot(mappingSlot, key);
        assembly {
            value := sload(valueSlot)
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

    function _pushArrayValue(uint256 arraySlot, uint256 value) private {
        assembly {
            let length := sload(arraySlot)
            mstore(0x00, arraySlot)
            let dataSlot := keccak256(0x00, 0x20)
            sstore(add(dataSlot, length), value)
            sstore(arraySlot, add(length, 1))
        }
    }

    function _mappingValueSlot(uint256 mappingSlot, uint256 key) private pure returns (bytes32 valueSlot) {
        assembly {
            mstore(0x00, key)
            mstore(0x20, mappingSlot)
            valueSlot := keccak256(0x00, 0x40)
        }
    }

    function _validateUpgradedHolder(address dePunkContract, uint256 eligibleDePunkTokenId) private view {
        if (dePunkContract == address(0)) revert InvalidAttributeContract();
        IAttributeFixedSaleUpgradeGate dePunk = IAttributeFixedSaleUpgradeGate(dePunkContract);
        try dePunk.ownerOf(eligibleDePunkTokenId) returns (address tokenOwner) {
            if (tokenOwner != msg.sender) revert NotEligibleUpgradedHolder();
        } catch {
            revert NotEligibleUpgradedHolder();
        }
        if (!dePunk.hasUpgraded(eligibleDePunkTokenId)) revert NotEligibleUpgradedHolder();
    }

    function _verifyFixedSaleSignature(
        address signerAddress,
        uint256 tokenId,
        uint32 quantity,
        uint256 eligibleDePunkTokenId,
        uint256 ticketId,
        uint256 totalPrice,
        uint256 deadline,
        bytes calldata signature
    ) private view {
        bytes32 messageHash = keccak256(
            abi.encodePacked(
                msg.sender,
                tokenId,
                quantity,
                eligibleDePunkTokenId,
                ticketId,
                totalPrice,
                deadline,
                address(this),
                block.chainid
            )
        );
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        if (_recoverSigner(ethSignedMessageHash, signature) != signerAddress) revert InvalidFixedSaleSignature();
    }

    function _distributeFixedSalePayment(
        address artist,
        uint16 artistPoints,
        address fixedSaleTreasury,
        uint256 totalAmount
    ) private returns (uint256 artistAmount, uint256 treasuryAmount) {
        artistAmount = (totalAmount * artistPoints) / BASE_POINTS;
        treasuryAmount = totalAmount - artistAmount;
        _sendETH(artist, artistAmount);
        _sendETH(fixedSaleTreasury, treasuryAmount);
    }

    function _sendETH(address recipient, uint256 amount) private {
        if (amount == 0) return;
        (bool success,) = recipient.call{value: amount}("");
        if (!success) revert FixedSaleTransferFailed();
    }

    function _recoverSigner(bytes32 hash, bytes calldata signature) private pure returns (address) {
        if (signature.length != 65) {
            return address(0);
        }

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := byte(0, calldataload(add(signature.offset, 0x40)))
        }

        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }

        return ecrecover(hash, v, r, s);
    }
}

interface IAttributeFixedSaleUpgradeGate {
    function ownerOf(uint256 tokenId) external view returns (address);
    function hasUpgraded(uint256 tokenId) external view returns (bool);
}
