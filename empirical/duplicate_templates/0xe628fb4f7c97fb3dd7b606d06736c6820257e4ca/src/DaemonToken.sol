// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "./ChainConfig.sol";

/**
 * @title DAEMONS — ERC20 Onchain Artifacts
 * @author DAEMONSv4
 * @notice ERC20 artifact layer for 6,666 onchain DAEMON objects powered by Uniswap v4 hooks
 *
 * Website: https://daemons.life
 * Twitter: https://x.com/DAEMONSv4
 *
 * Each whole $DAEMON maps to one 24x24 onchain SVG artifact.
 * Swaps mutate corruption through the launch hook. Holders can burn
 * DAEMON to sanitize or augment their artifact state, and can wrap
 * one whole DAEMON into an ERC721 to freeze the visual state.
 */

type Currency is address;
type BalanceDelta is int256;
type BeforeSwapDelta is int256;

struct PoolKey {
    Currency currency0;
    Currency currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

contract DaemonToken {
    /*//////////////////////////////////////////////////////////////
                               ERC-20
    //////////////////////////////////////////////////////////////*/

    string public constant name = "DAEMONS";
    string public constant symbol = "DAEMON";
    uint8 public constant decimals = 18;
    uint256 public constant CONTRACT_REVISION = 2;

    uint256 public constant ENTITY_UNIT = 1 ether;
    uint256 public constant TOTAL_SUPPLY = 6666 * ENTITY_UNIT;
    uint256 public constant MAX_ACTIVE_ARTIFACTS = 6666;
    uint256 public constant SANITIZE_COST = 4 * ENTITY_UNIT;
    uint256 public constant AURA_COST = 9 * ENTITY_UNIT;
    uint256 public constant ETHEREUM_MAINNET_CHAIN_ID = ChainConfig.ETHEREUM_MAINNET_CHAIN_ID;
    uint256 public constant BASE_CHAIN_ID = ChainConfig.BASE_CHAIN_ID;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /*//////////////////////////////////////////////////////////////
                            OWNERSHIP / HOOK
    //////////////////////////////////////////////////////////////*/

    address public owner;
    address public hook;
    bool public hookLocked;

    /*//////////////////////////////////////////////////////////////
                           ARTIFACT STATE
    //////////////////////////////////////////////////////////////*/

    uint256 public activeArtifacts;
    uint256 public totalArtifactsAwakened;
    uint256 public totalArtifactsDormant;
    uint256 public totalSanitized;
    uint256 public totalAuras;

    mapping(address => uint256) public marketArtifacts;
    mapping(address => ArtifactState) public artifactState;

    struct ArtifactState {
        uint256 generation;
        uint256 lastMutationAt;
        uint256 awakened;
        uint256 dormant;
        uint256 corruption;
        uint256 aura;
        bytes32 seed;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed accountOwner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event HookSet(address indexed hook);
    event ArtifactAwakened(
        address indexed host, uint256 artifacts, uint256 tokenAmount, uint256 corruption, bytes32 seed
    );
    event ArtifactDormant(
        address indexed host, uint256 artifacts, uint256 tokenAmount, uint256 corruption, bytes32 seed
    );
    event ArtifactSanitized(address indexed host, uint256 burnedAmount, bytes32 seed);
    event ArtifactAuraApplied(address indexed host, uint256 burnedAmount, uint256 aura, bytes32 seed);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error OwnerOnly();
    error HookOnly();
    error HookAlreadySet();
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();
    error ActiveArtifactCapExceeded(uint256 requestedActiveArtifacts, uint256 maxActiveArtifacts);
    error InsufficientMarketArtifacts(address host, uint256 requested, uint256 available);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address initialSupplyReceiver, address initialOwner) {
        if (!ChainConfig.isSupportedChain(block.chainid)) revert UnsupportedChain(block.chainid);
        if (initialSupplyReceiver == address(0) || initialOwner == address(0)) revert ZeroAddress();

        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);

        _mint(initialSupplyReceiver, TOTAL_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                               ERC-20 API
    //////////////////////////////////////////////////////////////*/

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < value) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = allowed - value;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transfer(from, to, value);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                              OWNERSHIP
    //////////////////////////////////////////////////////////////*/

    modifier onlyOwner() {
        if (msg.sender != owner) revert OwnerOnly();
        _;
    }

    modifier onlyHook() {
        if (msg.sender != hook) revert HookOnly();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }

    function setHook(address newHook) external onlyOwner {
        if (hookLocked) revert HookAlreadySet();
        if (newHook == address(0)) revert ZeroAddress();

        hook = newHook;
        hookLocked = true;

        emit HookSet(newHook);
    }

    /*//////////////////////////////////////////////////////////////
                            HOOK ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    function recordMarketBuy(address host, uint256 artifacts, uint256 tokenAmount, bytes32 entropy)
        external
        onlyHook
        returns (bytes32 seed)
    {
        if (host == address(0)) revert ZeroAddress();
        if (artifacts == 0 && tokenAmount == 0) return artifactState[host].seed;

        if (artifacts != 0) {
            uint256 requestedActive = activeArtifacts + artifacts;
            if (requestedActive > MAX_ACTIVE_ARTIFACTS) {
                revert ActiveArtifactCapExceeded(requestedActive, MAX_ACTIVE_ARTIFACTS);
            }
            marketArtifacts[host] += artifacts;
            activeArtifacts = requestedActive;
            totalArtifactsAwakened += artifacts;
        }

        ArtifactState storage state = artifactState[host];
        seed = _nextSeed(host, true, artifacts, tokenAmount, entropy);

        uint256 mutationWeight = artifacts == 0 ? 1 : artifacts;
        state.generation += mutationWeight;
        state.lastMutationAt = block.timestamp;
        state.awakened += artifacts;
        state.corruption = _corrupt(state.corruption, mutationWeight, true);
        state.seed = seed;

        emit ArtifactAwakened(host, artifacts, tokenAmount, state.corruption, seed);
    }

    function recordMarketSell(address host, uint256 artifacts, uint256 tokenAmount, bytes32 entropy)
        external
        onlyHook
        returns (bytes32 seed)
    {
        if (host == address(0)) revert ZeroAddress();
        if (artifacts == 0 && tokenAmount == 0) return artifactState[host].seed;

        if (artifacts != 0) {
            uint256 available = marketArtifacts[host];
            if (available < artifacts) revert InsufficientMarketArtifacts(host, artifacts, available);

            unchecked {
                marketArtifacts[host] = available - artifacts;
                activeArtifacts -= artifacts;
            }
            totalArtifactsDormant += artifacts;
        }

        ArtifactState storage state = artifactState[host];
        seed = _nextSeed(host, false, artifacts, tokenAmount, entropy);

        uint256 mutationWeight = artifacts == 0 ? 1 : artifacts;
        state.generation += mutationWeight;
        state.lastMutationAt = block.timestamp;
        state.dormant += artifacts;
        state.corruption = _corrupt(state.corruption, mutationWeight, false);
        state.seed = seed;

        emit ArtifactDormant(host, artifacts, tokenAmount, state.corruption, seed);
    }

    /*//////////////////////////////////////////////////////////////
                         ARTIFACT ACTIONS
    //////////////////////////////////////////////////////////////*/

    function sanitize() external returns (bytes32 seed) {
        _burn(msg.sender, SANITIZE_COST);

        ArtifactState storage state = artifactState[msg.sender];
        seed = keccak256(abi.encodePacked(state.seed, msg.sender, "SANITIZE", block.timestamp));
        state.corruption = 0;
        state.lastMutationAt = block.timestamp;
        state.generation++;
        state.seed = seed;
        totalSanitized++;

        emit ArtifactSanitized(msg.sender, SANITIZE_COST, seed);
    }

    function applyAura() external returns (bytes32 seed) {
        _burn(msg.sender, AURA_COST);

        ArtifactState storage state = artifactState[msg.sender];
        seed = keccak256(abi.encodePacked(state.seed, msg.sender, "AURA", block.timestamp, block.prevrandao));
        state.aura++;
        state.corruption = _corrupt(state.corruption, 9, true);
        state.lastMutationAt = block.timestamp;
        state.generation++;
        state.seed = seed;
        totalAuras++;

        emit ArtifactAuraApplied(msg.sender, AURA_COST, state.aura, seed);
    }

    /*//////////////////////////////////////////////////////////////
                               VIEWS
    //////////////////////////////////////////////////////////////*/

    function artifactCount(address host) external view returns (uint256) {
        return balanceOf[host] / ENTITY_UNIT;
    }

    function getArtifactState(address host) external view returns (ArtifactState memory) {
        return artifactState[host];
    }

    function deriveArtifactTraits(address host, uint256 index) public view returns (uint256 packedTraits) {
        ArtifactState storage state = artifactState[host];
        bytes32 seed = keccak256(abi.encodePacked(host, index, state.seed, balanceOf[host], activeArtifacts));
        uint256 hash = uint256(seed);

        packedTraits |= (hash % 16) << 0; // body
        packedTraits |= ((hash >> 8) % 16) << 8; // eyes
        packedTraits |= ((hash >> 16) % 16) << 16; // sigil
        packedTraits |= ((hash >> 24) % 24) << 24; // palette
        packedTraits |= (state.corruption % 256) << 32; // corruption
        packedTraits |= (state.aura % 16) << 40; // aura
    }

    /*//////////////////////////////////////////////////////////////
                              INTERNALS
    //////////////////////////////////////////////////////////////*/

    function _nextSeed(address host, bool buy, uint256 artifacts, uint256 tokenAmount, bytes32 entropy)
        internal
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                artifactState[host].seed,
                host,
                buy,
                artifacts,
                tokenAmount,
                entropy,
                block.timestamp,
                block.prevrandao,
                activeArtifacts
            )
        );
    }

    function _corrupt(uint256 current, uint256 artifacts, bool buy) internal pure returns (uint256) {
        uint256 delta = artifacts * (buy ? 13 : 7);
        return buy ? (current + delta) % 1000 : current > delta ? current - delta : 0;
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ZeroAddress();

        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance();

        unchecked {
            balanceOf[from] = fromBalance - value;
            balanceOf[to] += value;
        }

        emit Transfer(from, to, value);
    }

    function _mint(address to, uint256 value) internal {
        totalSupply += value;
        unchecked {
            balanceOf[to] += value;
        }
        emit Transfer(address(0), to, value);
    }

    function _burn(address from, uint256 value) internal {
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance();

        unchecked {
            balanceOf[from] = fromBalance - value;
            totalSupply -= value;
        }
        emit Transfer(from, address(0), value);
    }
}
