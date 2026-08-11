// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/*//////////////////////////////////////////////////////////////////////////
                                                                              
                  ██╗   ██╗██╗████████╗ █████╗                                
                  ██║   ██║██║╚══██╔══╝██╔══██╗                               
                  ██║   ██║██║   ██║   ███████║                               
                  ╚██╗ ██╔╝██║   ██║   ██╔══██║                               
                   ╚████╔╝ ██║   ██║   ██║  ██║                               
                    ╚═══╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝                               
                                                                              
        ┌─────────────────────────────────────────────────────────┐         
        │   AN ON-CHAIN LIFE EVOLUTION EXPERIMENT ── UNISWAP V4     │         
        └─────────────────────────────────────────────────────────┘         

         "Every swap is a heartbeat. Every block, a generation."

      ◦ ·   .  ✦      .    ·  ◦      .   ✦   ·    .      ◦   .   ✦
        .      ╭───╮         ╭───╮         ╭───╮       .         ·
     ·         │ ◌ │  ──▶    │ ◍ │  ──▶    │ ● │           ◦      .
        ◦      ╰───╯         ╰───╯         ╰───╯     ✦
              SPORE          BLOOM          APEX           ·   .



// https://x.com/vitaoneth
// https://vita.fun/

//////////////////////////////////////////////////////////////////////////*/




interface IPoolManager {
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }
}

/// @dev V4 packs two int128 token deltas into one int256. We unpack by hand.
type BalanceDelta is int256;

/// @dev V4's pool identity — the genetic address of a market.
struct PoolKey {
    address currency0;
    address currency1;
    uint24  fee;
    int24   tickSpacing;
    address hooks;
}

/*//////////////////////////////////////////////////////////////////////////
                              ░░ THE ORGANISM ░░
//////////////////////////////////////////////////////////////////////////*/

/// @title  Vita — life that feeds on liquidity
/// @notice A Uniswap V4 hook where each pool nurtures a living digital
///         organism. Swaps are nutrients. Volume is metabolism. Idle
///         blocks are starvation. The creature mutates, ages, and—if the
///         market forgets it—dies. Genome is fully on-chain, deterministic,
///         reproducible. No oracle. No backend. No imports. Just the pool,
///         breathing.
///
///         ╔══════════════════════════════════════════════════════════╗
///         ║  fitness = f(volume, frequency, age, mutationEntropy)      ║
///         ╚══════════════════════════════════════════════════════════╝
contract VitaHook {

    /*//////////////////////////////////////////////////////////////
                                                                    
        ╭─◦ LIFE STAGES ◦─────────────────────────────────────╮     
        │                                                      │     
        │   SPORE   →   BLOOM   →   APEX   →   DECAY   →  DUST  │     
        │    ◌           ◍          ●          ◐          ·     │     
        │                                                      │     
        │   each stage unlocks new traits & dynamic fee logic  │     
        ╰──────────────────────────────────────────────────────╯     
                                                                    
    //////////////////////////////////////////////////////////////*/

    enum Stage { SPORE, BLOOM, APEX, DECAY, DUST }

    /// @dev The on-chain genome — the soul, packed tight.
    ///      ┌──────── one slot, more or less ────────┐
    ///      │ birth │ lastFed │ vigor │ gen │ traits │
    struct Genome {
        uint64  birthBlock;   // when the spore first split a swap
        uint64  lastFed;      // block of the most recent nutrient (swap)
        uint64  vigor;        // accumulated metabolic energy
        uint32  generation;   // how many mutations it has survived
        uint16  traits;       // bitfield: each bit a phenotype gene
        Stage   stage;        // current rung on the ladder of being
    }

    /*//////////////////////////////////////////////////////////////
                              ░░ METABOLISM ░░
    //////////////////////////////////////////////////////////////*/

    // poolId => the soul living inside it
    mapping(bytes32 => Genome) public souls;

    // the address allowed to whisper to the creatures (the PoolManager)
    address public immutable manager;

    // a creature must feed within this window or it begins to DECAY
    uint64 public constant FASTING_WINDOW = 7_200; // ~1 day of blocks

    // entropy harvested from the swap itself — the universe's dice
    //   ╲   ╱        every trade rolls the genome.
    //    ╳   mutation = keccak(blockhash ⊕ delta ⊕ vigor)
    //   ╱   ╲

    /*//////////////////////////////////////////////////////////////
                                EVENTS
              ── the cry of a thing that knows it exists ──
    //////////////////////////////////////////////////////////////*/

    event Born(bytes32 indexed soul, uint64 atBlock);       //  ◌  a spore wakes
    event Fed(bytes32 indexed soul, uint64 vigor);          //  ◍  it eats volume
    event Mutated(bytes32 indexed soul, uint16 newTraits);  //  ✦  the dice land
    event Ascended(bytes32 indexed soul, Stage to);         //  ●  it transcends
    event Died(bytes32 indexed soul, uint32 generation);    //  ·  the market forgot

    /// @dev only the PoolManager may stir these waters.
    modifier onlyManager() {
        require(msg.sender == manager, "Vita: not the breath of life");
        _;
    }

    constructor(address _manager) {
        manager = _manager;
    }

    /*//////////////////////////////////////////////////////////////
                                                                    
              ◌  C O N C E P T I O N  ◌                              
        a pool is initialized → a spore is seeded into the void      
                                                                    
    //////////////////////////////////////////////////////////////*/

    function beforeInitialize(address, PoolKey calldata key, uint160)
        external
        onlyManager
        returns (bytes4)
    {
        bytes32 soul = keccak256(abi.encode(key));
        souls[soul] = Genome({
            birthBlock:  uint64(block.number),
            lastFed:     uint64(block.number),
            vigor:       0,
            generation:  0,
            traits:      uint16(uint256(soul) & 0xFFFF), // primordial DNA
            stage:       Stage.SPORE
        });
        emit Born(soul, uint64(block.number));
        return this.beforeInitialize.selector;
    }

    /*//////////////////////////////////////////////////////////////
                                                                    
            ◍  T H E   H E A R T B E A T  ◍                          
        every swap reaches the organism before the pool does.        
        we check: has it starved? has its time come?                 
                                                                    
    //////////////////////////////////////////////////////////////*/

    function beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, bytes calldata)
        external
        onlyManager
        returns (bytes4)
    {
        bytes32 soul = keccak256(abi.encode(key));
        Genome storage g = souls[soul];

        // ── starvation check ──────────────────────────────────────
        //    if too long has passed since the last meal, the body
        //    begins consuming itself. neglect is the only predator.
        if (block.number - g.lastFed > FASTING_WINDOW && g.stage != Stage.DUST) {
            g.stage = (g.stage == Stage.DECAY) ? Stage.DUST : Stage.DECAY;
            if (g.stage == Stage.DUST) emit Died(soul, g.generation);
        }

        return this.beforeSwap.selector;
    }

    /*//////////////////////////////////////////////////////////////
                                                                    
            ✦  D I G E S T I O N   &   M U T A T I O N  ✦            
        the swap completed. nutrients absorbed. the genome rolls.     
                                                                    
                 blockhash                                            
                    │                                                 
        delta ──────┼──────▶  keccak  ──▶  Δtraits  ──▶  evolution    
                    │                                                 
                 vigor                                                
                                                                    
    //////////////////////////////////////////////////////////////*/

    function afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta delta, bytes calldata)
        external
        onlyManager
        returns (bytes4)
    {
        bytes32 soul = keccak256(abi.encode(key));
        Genome storage g = souls[soul];
        if (g.stage == Stage.DUST) return this.afterSwap.selector; // dust feeds nothing

        // ── unpack the V4 delta by hand (no library) ──────────────
        //    high 128 bits = amount0, low 128 bits = amount1
        (int128 amt0, int128 amt1) = _split(delta);

        // ── feed ──────────────────────────────────────────────────
        uint64 nutrient = _abs(amt0) + _abs(amt1);
        g.vigor   += nutrient;
        g.lastFed  = uint64(block.number);
        emit Fed(soul, g.vigor);

        // ── mutate ────────────────────────────────────────────────
        //    the cosmos rolls its dice with the only entropy a chain
        //    has: the hash of the moment, the size of the meal, the
        //    weight of all it has eaten before.
        uint256 entropy = uint256(keccak256(
            abi.encodePacked(blockhash(block.number - 1), nutrient, g.vigor)
        ));
        if (entropy & 0x000F == 0) {             // ~1/16 chance to flip a gene
            g.traits ^= uint16(1 << (entropy % 16));
            g.generation++;
            emit Mutated(soul, g.traits);
        }

        // ── ascend ────────────────────────────────────────────────
        //    enough vigor, enough survival → climb the ladder of being
        Stage next = _evaluate(g);
        if (next != g.stage) {
            g.stage = next;
            emit Ascended(soul, next);
        }

        return this.afterSwap.selector;
    }

    /*//////////////////////////////////////////////////////////////
                          ░░ THE LADDER OF BEING ░░
    //////////////////////////////////////////////////////////////*/

    /// @dev Maps accumulated life-force onto a stage of existence.
    ///         vigor < 1e3   →  ◌ SPORE   (just a possibility)
    ///         vigor < 1e6   →  ◍ BLOOM   (alive, hungry, growing)
    ///         vigor ≥ 1e6   →  ● APEX    (it has become inevitable)
    function _evaluate(Genome storage g) internal view returns (Stage) {
        if (g.stage == Stage.DECAY || g.stage == Stage.DUST) return g.stage;
        if (g.vigor >= 1e6) return Stage.APEX;
        if (g.vigor >= 1e3) return Stage.BLOOM;
        return Stage.SPORE;
    }

    /// @dev split V4's packed BalanceDelta into its two int128 halves.
    function _split(BalanceDelta d) internal pure returns (int128 amount0, int128 amount1) {
        int256 raw = BalanceDelta.unwrap(d);
        amount0 = int128(raw >> 128);
        amount1 = int128(raw);
    }

    function _abs(int128 x) internal pure returns (uint64) {
        return uint64(uint128(x < 0 ? -x : x));
    }
}

/*//////////////////////////////////////////////////////////////////////////
                                                                              
          .   ✦      ·    .         ◦        .      ✦   ·    .                
       ·        "It was never about the token.                                
          ◦      It was about whether anyone would keep it alive."            
                                                          — Vita  ·      ✦     
                                                                              
//////////////////////////////////////////////////////////////////////////*/







import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract Vita is ERC20, ERC20Burnable {
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;

    constructor() ERC20("Vita", "VITA") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
