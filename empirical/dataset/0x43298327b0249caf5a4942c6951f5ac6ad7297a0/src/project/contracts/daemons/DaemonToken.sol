// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DmnToken} from "../token/DmnToken.sol";
import {Random} from "../library/RandomLib.sol";
import {Base64} from "solady/src/utils/Base64.sol";
import {DaemonRenderRequest} from "./DaemonRenderer.sol";
import {DaemonTraits} from "./DaemonTraits.sol";
import {IDaemonRenderer} from "./IDaemonRenderer.sol";

interface IDaemonHookState {
    function corruptionSnapshot(bytes32 poolId) external view returns (bytes32 state, uint64 epoch);
}

interface IDaemonHookLaunchState {
    function launchBlock() external view returns (uint256);
}

interface IDaemonHookFeeRecipient {
    function launchFeeRecipient() external view returns (address);
}

contract DaemonToken is DmnToken {
    error RendererNotSet();
    error ObjectNotFound();
    error MintContextMissing();
    error MintContextExpired();
    error MintContextTooSmall();
    error MintContextAmountMismatch();
    error NotUpgradeBurner();
    error InsufficientFreeBalance();
    error SacrificeObjectNotOwned();
    error NotDmnTransferAgent();
    error ZeroAddressTransfer();
    error BootstrapTransfersLocked();
    error RedeemFeeRecipientNotSet();

    struct MintContext {
        uint256 daemonAmount;
        uint256 maxObjects;
        uint256 expiresBlock;
        uint256 originBlock;
        bytes32 poolId;
        bytes32 state;
        uint256 mintSeed;
    }

    struct DaemonMintBatch {
        uint128 start;
        uint128 end;
        uint64 originBlock;
        bytes32 poolId;
        bytes32 state;
    }

    uint256 public globalMintNonce;
    uint256 public traitEntropy;
    bytes32 public activePoolId;
    address public renderer;

    uint256 public constant REDEEM_FEE_BPS = 100;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    mapping(address recipient => MintContext context) public mintContexts;
    mapping(uint256 objectId => uint256 traitWord) private _objectTraitWord;
    mapping(uint256 objectId => uint256 originBlock) private _objectOriginSwapBlock;
    mapping(uint256 objectId => bytes32 fingerprint) private _objectTraitFingerprint;
    mapping(bytes32 fingerprint => bool dead) public deadTraitFingerprint;
    mapping(address account => bool allowed) public upgradeBurner;
    uint256[] private _detachedObjectInventory;
    DaemonMintBatch[] private _daemonMintBatches;

    bool private _objectSyncSuppressed;
    address private _trustedObjectReceiver;

    event DaemonObjectRangeMinted(
        address indexed owner,
        uint256 indexed startObjectId,
        uint256 indexed endObjectId,
        uint256 originSwapBlock,
        bytes32 poolId
    );
    event DaemonTraitEntropySealed(uint256 indexed blockNumber, bytes32 indexed poolId, uint256 entropy);
    event DaemonTraitFingerprintRetired(uint256 indexed objectId, bytes32 indexed fingerprint);
    event DaemonObjectsSacrificed(address indexed owner, address indexed operator, uint256 count);
    event DaemonPoolObjectsStored(address indexed seller, uint256 count);
    event DaemonPoolObjectsAssigned(address indexed recipient, uint256 count);
    event DaemonObjectsDetached(address indexed owner, uint256 count);
    event DaemonDetachedObjectsAssigned(address indexed recipient, uint256 count);
    event DaemonWrappedObjectRedeemed(
        address indexed wrapper,
        address indexed recipient,
        uint256 indexed retiredObjectId,
        uint256 payoutAmount,
        uint256 feeAmount,
        address feeRecipient,
        uint256 spawnedObjectId
    );

    constructor(address owner_) DmnToken(owner_) {}

    function name() public pure override returns (string memory) {
        return "DAEMON";
    }

    function symbol() public pure override returns (string memory) {
        return "DAEMON";
    }

    function setRenderer(address renderer_) external onlyOwner {
        renderer = renderer_;
    }

    function setUpgradeBurner(address burner, bool allowed) external onlyOwner {
        upgradeBurner[burner] = allowed;
    }

    function setActivePoolId(bytes32 poolId) external onlyHook {
        activePoolId = poolId;
    }

    function sealTraitEntropy(bytes32 poolId, bytes32 state) external onlyHook {
        _sealTraitEntropy(poolId, state);
    }

    function tokenURI() external pure returns (string memory) {
        string memory svg =
            "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' shape-rendering='crispEdges'><rect width='24' height='24' fill='#000000'/><path fill='#0c0c0c' d='M0 0h24v1H0zM0 2h24v1H0zM0 4h24v1H0zM0 6h24v1H0zM0 8h24v1H0zM0 10h24v1H0zM0 12h24v1H0zM0 14h24v1H0zM0 16h24v1H0zM0 18h24v1H0zM0 20h24v1H0zM0 22h24v1H0z'/><path fill='#00ffff' d='M6 8h3v2H6zM15 8h3v2h-3zM8 15h8v2H8z'/><path fill='#000000' d='M7 9h1v1H7zM16 9h1v1h-1zM10 16h4v1h-4z'/></svg>";
        string memory image = string.concat("data:image/svg+xml;base64,", Base64.encode(bytes(svg)));
        string memory json = string.concat(
            '{"name":"DAEMON","symbol":"DAEMON","decimals":18,',
            '"description":"Native ERC20 object token with on-chain generative art powered by Uniswap v4 hooks.",',
            '"image":"',
            image,
            '","icons":[{"src":"',
            image,
            '","sizes":"512x512","type":"image/svg+xml"}]}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function transferDmnFrom(address from, address to, uint256 objectId) external {
        if (!_ownerOwnsDmn(from, objectId)) revert SacrificeObjectNotOwned();
        bool trustedAgent = msg.sender != from && upgradeBurner[msg.sender];
        if (msg.sender != from && !trustedAgent) revert NotDmnTransferAgent();
        if (trustedAgent) _trustedObjectReceiver = msg.sender;
        _transferDmn(from, to, objectId);
        _afterDmnTransferred(from, to, objectId);
        if (trustedAgent) _trustedObjectReceiver = address(0);
    }

    function redeemWrappedObject(address to, uint256 objectId)
        external
        returns (uint256 payoutAmount, uint256 feeAmount, uint256 spawnedObjectId)
    {
        if (!upgradeBurner[msg.sender]) revert NotUpgradeBurner();
        if (!_ownerOwnsDmn(msg.sender, objectId)) revert SacrificeObjectNotOwned();

        address feeRecipient = redeemFeeRecipient();
        feeAmount = (UNIT_PER_DMN * REDEEM_FEE_BPS) / BPS_DENOMINATOR;
        payoutAmount = UNIT_PER_DMN - feeAmount;

        uint256 balanceBeforePayout = balanceOf(to);
        uint256 wholeBeforePayout = balanceBeforePayout / UNIT_PER_DMN;
        uint256 wholeAfterPayout = (balanceBeforePayout + payoutAmount) / UNIT_PER_DMN;
        uint256 objectsOwed = to != feeRecipient && wholeAfterPayout > wholeBeforePayout ? 1 : 0;

        _burnDmn(msg.sender, objectId);

        _objectSyncSuppressed = true;
        _transfer(msg.sender, to, payoutAmount);
        _transfer(msg.sender, feeRecipient, feeAmount);
        _objectSyncSuppressed = false;

        if (objectsOwed != 0) {
            (bytes32 poolId, bytes32 state,) = currentCorruptionSnapshot();
            MintContext memory context = MintContext({
                daemonAmount: payoutAmount,
                maxObjects: objectsOwed,
                expiresBlock: block.number,
                originBlock: block.number,
                poolId: poolId,
                state: state,
                mintSeed: _redeemMintSeed(to, objectId)
            });
            spawnedObjectId = _dmnsTotalCount + 1;
            _mintDmnsWithContext(to, objectsOwed, context);
        }

        emit DaemonWrappedObjectRedeemed(
            msg.sender, to, objectId, payoutAmount, feeAmount, feeRecipient, spawnedObjectId
        );
    }

    function redeemFeeRecipient() public view returns (address recipient) {
        address hook_ = hook;
        if (hook_ == address(0)) revert RedeemFeeRecipientNotSet();
        recipient = IDaemonHookFeeRecipient(hook_).launchFeeRecipient();
        if (recipient == address(0)) revert RedeemFeeRecipientNotSet();
    }

    function registerMintContext(
        address recipient,
        uint256 daemonAmount,
        uint256 maxObjects,
        bytes32 poolId,
        bytes32 state
    ) external onlyHook {
        if (daemonAmount == 0 || maxObjects == 0) {
            delete mintContexts[recipient];
            return;
        }
        MintContext storage existing = mintContexts[recipient];
        if (existing.expiresBlock == block.number && existing.poolId == poolId) {
            uint256 mergedSeed = _mintContextSeed(recipient, daemonAmount, maxObjects, poolId, state);
            existing.daemonAmount += daemonAmount;
            existing.maxObjects += maxObjects;
            existing.state = keccak256(
                abi.encodePacked(
                    "TEST_MINT_CONTEXT_MERGE_V3", existing.state, state, existing.daemonAmount, existing.maxObjects
                )
            );
            existing.mintSeed = uint256(
                keccak256(
                    abi.encode(
                        "TEST_MINT_CONTEXT_SEED_MERGE_V3",
                        existing.mintSeed,
                        mergedSeed,
                        existing.daemonAmount,
                        existing.maxObjects,
                        existing.state
                    )
                )
            );
            if (existing.mintSeed == 0) existing.mintSeed = 1;
            return;
        }
        mintContexts[recipient] = MintContext({
            daemonAmount: daemonAmount,
            maxObjects: maxObjects,
            expiresBlock: block.number,
            originBlock: block.number,
            poolId: poolId,
            state: state,
            mintSeed: _mintContextSeed(recipient, daemonAmount, maxObjects, poolId, state)
        });
    }

    function traitFingerprint(uint256 traitWord) external pure returns (bytes32) {
        return DaemonTraits.fingerprint(traitWord);
    }

    function objectSeed(uint256 objectId) external view returns (uint256 seed) {
        seed = _dmnSeed(objectId);
        if (seed == 0) revert ObjectNotFound();
    }

    function objectTraitWord(uint256 objectId) public view returns (uint256 traitWord) {
        if (!_dmnExists(objectId)) revert ObjectNotFound();
        traitWord = _objectTraitWord[objectId];
        if (traitWord == 0) traitWord = DaemonTraits.derive(_traitDerivationSeed(), objectId);
    }

    function objectOriginSwapBlock(uint256 objectId) public view returns (uint256 originBlock) {
        if (!_dmnExists(objectId)) revert ObjectNotFound();
        originBlock = _objectOriginSwapBlock[objectId];
        if (originBlock == 0) originBlock = _mintBatchForObject(objectId).originBlock;
    }

    function objectTraitFingerprint(uint256 objectId) public view returns (bytes32 fingerprint) {
        if (!_dmnExists(objectId)) revert ObjectNotFound();
        fingerprint = _objectTraitFingerprint[objectId];
        if (fingerprint == bytes32(0)) fingerprint = DaemonTraits.fingerprint(objectTraitWord(objectId));
    }

    function objectURI(uint256 objectId) external view returns (string memory) {
        if (renderer == address(0)) revert RendererNotSet();
        uint256 seed = _dmnSeed(objectId);
        if (seed == 0) revert ObjectNotFound();
        (bytes32 poolId, bytes32 state, uint64 epoch) = currentCorruptionSnapshot();
        return IDaemonRenderer(renderer)
            .tokenURI(
                DaemonRenderRequest({
                    objectId: objectId,
                    originSwapBlock: objectOriginSwapBlock(objectId),
                    seed: seed,
                    traitWord: objectTraitWord(objectId),
                    corruptionState: state,
                    poolId: poolId,
                    corruptionEpoch: epoch,
                    tier: 1,
                    frozen: false
                })
            );
    }

    function currentCorruptionSnapshot() public view returns (bytes32 poolId, bytes32 state, uint64 epoch) {
        poolId = activePoolId;
        if (hook.code.length == 0 || poolId == bytes32(0)) return (poolId, bytes32(0), 0);
        try IDaemonHookState(hook).corruptionSnapshot(poolId) returns (bytes32 hookState, uint64 hookEpoch) {
            return (poolId, hookState, hookEpoch);
        } catch {
            return (poolId, bytes32(0), 0);
        }
    }

    function poolObjectInventoryCount() external view returns (uint256) {
        return _detachedObjectInventory.length;
    }

    function detachedObjectInventoryCount() external view returns (uint256) {
        return _detachedObjectInventory.length;
    }

    function suspendedObjectCount(address account) public view returns (uint256 count) {
        uint256 maxAllowed = balanceOf(account) / UNIT_PER_DMN;
        uint256 currentCount = OwnerDmnsCount(account);
        if (maxAllowed > currentCount) count = maxAllowed - currentCount;
    }

    function sacrificeObjectsForUpgrade(address from, uint256[] calldata objectIds) external {
        if (!upgradeBurner[msg.sender]) revert NotUpgradeBurner();
        uint256 count = objectIds.length;
        if (count == 0) return;
        uint256 amount = count * UNIT_PER_DMN;
        if (balanceOf(from) < amount) revert InsufficientFreeBalance();

        _objectSyncSuppressed = true;
        for (uint256 i = 0; i < count; ++i) {
            if (!_ownerOwnsDmn(from, objectIds[i])) revert SacrificeObjectNotOwned();
            _burnDmn(from, objectIds[i]);
            _burn(from, UNIT_PER_DMN);
        }
        _objectSyncSuppressed = false;

        emit DaemonObjectsSacrificed(from, msg.sender, count);
    }

    function _onTokenTransfer(address from, address to, uint256 amount, Random memory) internal override {
        if (_objectSyncSuppressed || pool == address(0)) return;

        if (from == pool && to != address(0)) {
            if (to == _notMintableAccount) return;
            require(isStarted(), "not started");
            MintContext memory context = mintContexts[to];
            bool hasMintContext = context.expiresBlock == block.number && context.expiresBlock != 0;
            if (context.expiresBlock != 0 && !hasMintContext) delete mintContexts[to];
            if (hasMintContext && amount != 0 && context.daemonAmount < amount) revert MintContextAmountMismatch();
            uint256 maxAllowed = balanceOf(to) / UNIT_PER_DMN;
            uint256 currentCount = OwnerDmnsCount(to);
            uint256 owed = currentCount < maxAllowed ? maxAllowed - currentCount : 0;
            if (owed == 0) {
                if (hasMintContext) _consumeMintContext(to, amount, 0);
                return;
            }
            uint256 assignedFromInventory = _assignDetachedInventory(to, owed);
            uint256 mintQty = owed - assignedFromInventory;
            if (mintQty != 0) {
                if (!hasMintContext) revert MintContextMissing();
                uint256 contextMintQty = mintQty > context.maxObjects ? context.maxObjects : mintQty;
                _consumeMintContext(to, amount, contextMintQty);
                if (contextMintQty != 0) _mintDmnsWithContext(to, contextMintQty, context);
            } else if (hasMintContext) {
                _consumeMintContext(to, amount, 0);
            }
            return;
        }

        if (_isProtectedObjectReceiver(to) && to != _trustedObjectReceiver) revert AddressCanNotReceiveDmn();
        if (from == to || amount == 0) return;

        uint256 toBalanceAfter = balanceOf(to);
        uint256 toWholeBefore = (toBalanceAfter - amount) / UNIT_PER_DMN;
        uint256 toWholeAfter = toBalanceAfter / UNIT_PER_DMN;
        uint256 toWholeIncrease = toWholeAfter > toWholeBefore ? toWholeAfter - toWholeBefore : 0;

        uint256 fromMaxAllowed = balanceOf(from) / UNIT_PER_DMN;
        uint256 fromCount = OwnerDmnsCount(from);
        uint256 fromRemoveCount = fromCount > fromMaxAllowed ? fromCount - fromMaxAllowed : 0;

        uint256 toMaxAllowed = toWholeAfter;
        uint256 toCount = OwnerDmnsCount(to);
        uint256 toReceiveAllowed = toCount < toMaxAllowed ? toMaxAllowed - toCount : 0;

        if (!_canReceiveDmns(to)) {
            toReceiveAllowed = 0;
        }

        if (fromRemoveCount == 0) {
            uint256 assignQty = toReceiveAllowed < toWholeIncrease ? toReceiveAllowed : toWholeIncrease;
            if (assignQty != 0) _assignDetachedInventory(to, assignQty);
            return;
        }

        uint256 moveQty = fromRemoveCount < toReceiveAllowed ? fromRemoveCount : toReceiveAllowed;
        if (moveQty > 0) _moveDmns(from, to, moveQty);

        if (toReceiveAllowed > moveQty && toWholeIncrease > moveQty) {
            uint256 remainingIncrease = toWholeIncrease - moveQty;
            uint256 remainingReceive = toReceiveAllowed - moveQty;
            uint256 assignQty = remainingReceive < remainingIncrease ? remainingReceive : remainingIncrease;
            if (assignQty != 0) _assignDetachedInventory(to, assignQty);
        }

        uint256 remaining = fromRemoveCount - moveQty;
        if (remaining == 0) return;
        _detachObjects(from, remaining, to == pool);
    }

    function _mintDmns(address user, uint256 qty, Random memory random) internal override {
        if (qty == 0) return;
        MintContext memory context = _validateMintContext(user, 0);
        if (context.maxObjects < qty) revert MintContextTooSmall();
        _consumeMintContext(user, context.daemonAmount, qty);
        random;
        _mintDmnsWithContext(user, qty, context);
    }

    function _mintDmnsWithContext(address user, uint256 qty, MintContext memory context) private {
        uint256 rangeSeed = uint256(
            keccak256(
                abi.encode(
                    "TEST_OBJECT_RANGE_V3",
                    block.chainid,
                    address(this),
                    _dmnsTotalCount + 1,
                    qty,
                    ++globalMintNonce,
                    user,
                    context.poolId,
                    context.state,
                    context.mintSeed
                )
            )
        );
        (uint256 start, uint256 end) = _mintDmnRange(user, qty, rangeSeed);
        _daemonMintBatches.push(
            DaemonMintBatch({
                start: uint128(start),
                end: uint128(end),
                originBlock: uint64(context.originBlock),
                poolId: context.poolId,
                state: context.state
            })
        );
        globalMintNonce += qty - 1;
        emit DaemonObjectRangeMinted(user, start, end, context.originBlock, context.poolId);
    }

    function _burnDmn(address owner, uint256 objectId) internal override returns (uint256 seed) {
        bytes32 fingerprint = objectTraitFingerprint(objectId);
        if (fingerprint != bytes32(0)) {
            deadTraitFingerprint[fingerprint] = true;
            delete _objectTraitFingerprint[objectId];
            delete _objectTraitWord[objectId];
            delete _objectOriginSwapBlock[objectId];
            emit DaemonTraitFingerprintRetired(objectId, fingerprint);
        }
        return super._burnDmn(owner, objectId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);
        amount;
        if (from != address(0) && to == address(0) && !_objectSyncSuppressed) revert ZeroAddressTransfer();
        if (from == _notMintableAccount && pool != address(0) && _tradingLaunched()) {
            revert BootstrapTransfersLocked();
        }
    }

    function _validateMintContext(address recipient, uint256 amount) private view returns (MintContext memory context) {
        context = mintContexts[recipient];
        if (context.expiresBlock == 0) revert MintContextMissing();
        if (context.expiresBlock != block.number) revert MintContextExpired();
        if (amount != 0 && context.daemonAmount < amount) revert MintContextAmountMismatch();
    }

    function _consumeMintContext(address recipient, uint256 amount, uint256 objectsMinted) private {
        MintContext storage context = mintContexts[recipient];
        if (amount >= context.daemonAmount) {
            delete mintContexts[recipient];
            return;
        }
        context.daemonAmount -= amount;
        context.maxObjects = context.maxObjects > objectsMinted ? context.maxObjects - objectsMinted : 0;
    }

    function _canReceiveDmns(address addr) internal view override returns (bool) {
        if (!super._canReceiveDmns(addr)) return false;
        if (_isProtectedObjectReceiver(addr) && addr != _trustedObjectReceiver) return false;
        return true;
    }

    function _detachObjects(address from, uint256 qty, bool poolSale) private {
        uint256 stored;
        for (uint256 i = 0; i < qty; ++i) {
            uint256 count = OwnerDmnsCount(from);
            if (count == 0) break;
            uint256 objectId = this.OwnerDmn(from, count - 1).id;
            _removeDmnFromOwner(from, objectId);
            _materializeDmn(objectId);
            _detachedObjectInventory.push(objectId);
            unchecked {
                ++stored;
            }
        }
        if (poolSale) emit DaemonPoolObjectsStored(from, stored);
        else emit DaemonObjectsDetached(from, stored);
    }

    function _assignDetachedInventory(address to, uint256 qty) private returns (uint256 assigned) {
        while (assigned < qty && _detachedObjectInventory.length != 0) {
            uint256 lastIndex = _detachedObjectInventory.length - 1;
            uint256 objectId = _detachedObjectInventory[lastIndex];
            _detachedObjectInventory.pop();
            _insertExistingDmnToOwner(to, objectId);
            unchecked {
                ++assigned;
            }
        }
        if (assigned != 0) {
            emit DaemonPoolObjectsAssigned(to, assigned);
            emit DaemonDetachedObjectsAssigned(to, assigned);
        }
    }

    function _isProtectedObjectReceiver(address addr) private view returns (bool) {
        return addr == address(this) || addr == hook || addr == renderer || upgradeBurner[addr];
    }

    function _mintContextSeed(
        address recipient,
        uint256 daemonAmount,
        uint256 maxObjects,
        bytes32 poolId,
        bytes32 state
    ) private view returns (uint256 seed) {
        seed = uint256(
            keccak256(
                abi.encode(
                    "TEST_MINT_CONTEXT_SEED_V3",
                    block.chainid,
                    address(this),
                    recipient,
                    daemonAmount,
                    maxObjects,
                    poolId,
                    state,
                    block.number,
                    globalMintNonce
                )
            )
        );
        if (seed == 0) seed = 1;
    }

    function _redeemMintSeed(address recipient, uint256 retiredObjectId) private view returns (uint256 seed) {
        seed = uint256(
            keccak256(
                abi.encode(
                    "TEST_REDEEM_MINT_SEED_V3",
                    block.chainid,
                    address(this),
                    msg.sender,
                    recipient,
                    retiredObjectId,
                    _dmnsTotalCount,
                    block.number,
                    globalMintNonce
                )
            )
        );
        if (seed == 0) seed = 1;
    }

    function _sealTraitEntropy(bytes32 poolId, bytes32 state) private {
        if (traitEntropy != 0) return;
        uint256 entropy = uint256(
            keccak256(
                abi.encode(
                    "TEST_TRAIT_ENTROPY_V3",
                    block.chainid,
                    address(this),
                    hook,
                    poolId,
                    state,
                    block.number,
                    block.prevrandao,
                    blockhash(block.number - 1)
                )
            )
        );
        if (entropy == 0) entropy = 1;
        traitEntropy = entropy;
        emit DaemonTraitEntropySealed(block.number, poolId, entropy);
    }

    function _traitDerivationSeed() private view returns (uint256) {
        uint256 entropy = traitEntropy;
        if (entropy == 0) entropy = uint256(keccak256(abi.encodePacked("TEST_TRAIT_ENTROPY_FALLBACK_V3", hook)));
        return entropy;
    }

    function _tradingLaunched() private view returns (bool) {
        if (hook.code.length == 0) return false;
        try IDaemonHookLaunchState(hook).launchBlock() returns (uint256 launchedAt) {
            return launchedAt != 0;
        } catch {
            return false;
        }
    }

    function _mintBatchForObject(uint256 objectId) private view returns (DaemonMintBatch memory batch) {
        uint256 low;
        uint256 high = _daemonMintBatches.length;
        while (low < high) {
            uint256 mid = (low + high) / 2;
            batch = _daemonMintBatches[mid];
            if (objectId < batch.start) {
                high = mid;
            } else if (objectId > batch.end) {
                low = mid + 1;
            } else {
                return batch;
            }
        }
        if (_objectOriginSwapBlock[objectId] != 0) {
            return DaemonMintBatch({
                start: uint128(objectId),
                end: uint128(objectId),
                originBlock: uint64(_objectOriginSwapBlock[objectId]),
                poolId: bytes32(0),
                state: bytes32(0)
            });
        }
        revert ObjectNotFound();
    }
}
