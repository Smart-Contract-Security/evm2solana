// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721}             from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20}             from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20}          from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable}            from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard}    from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Base64}             from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings}            from "@openzeppelin/contracts/utils/Strings.sol";

import {IUniswapV2Pair}     from "./interfaces/IUniswapV2Pair.sol";
import {IWETH}              from "./interfaces/IWETH.sol";

/**
 * @title GateCoin — soulbound ERC-721 + phase-3 mint controller (unified).
 *
 *  The Gate Coin IS the only thing minted by this contract, and the only way
 *  to obtain it is the payable `mint(qty, ref)` flow below. Combining the
 *  two means:
 *    - No `setMinter` rug vector (the NFT can never start emitting from a
 *      different controller).
 *    - One Etherscan page, one ABI on the frontend.
 *    - Internal mint loop instead of external call — cheaper gas.
 *
 *  == NFT layer ==
 *    9 999 hard cap, sequential tokenIds [1, 9999].
 *    ≤ 3 per wallet.
 *    Soulbound: every non-mint transfer reverts in `_update`.
 *
 *  == Mint layer ==
 *    mint(qty, ref) — payable, price = `mintPriceWei` ETH per token.
 *    Per-tx split:
 *       30% → POOL INJECTION  (wrap → pair.transfer(WETH) → pair.sync)
 *       10% → REFERRER        (valid EOA + non-self; else fallback to dev)
 *       60% → DEV wallet
 *    Side-effect on the wallet's first mint:
 *       `spinCredited` is set to `true` in MintRecord (local UX flag) and
 *       `SpinUnlocked` is emitted. The actual spin entitlement S is
 *       materialized on-demand by RushClaim from the pure `spinReward()`
 *       function below — RushClaim reads `gateCoin.spinReward(user)` and
 *       `gateCoin.balanceOf(user) > 0` directly, gated by no privileged
 *       caller. There is no cross-contract `creditSpin` trust path.
 *
 *  == Anti-flash-loan ==
 *    `tx.origin == msg.sender` — contracts cannot call mint. (Same posture
 *    as RushBurn — see contracts/README.md for rationale.)
 *
 *  == No circular dependency ==
 *    RushClaim reads from GateCoin (`spinReward`, `balanceOf`); GateCoin
 *    does NOT call back into RushClaim. Wiring order at deploy:
 *      1. Deploy GateCoin.
 *      2. Deploy RushClaim(rush, gateCoin, burn).
 */
contract GateCoin is ERC721, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /* ============================ errors ============================ */
    error NotEOA();
    error PhaseClosed();
    error PhaseAlreadyOpen();
    error WrongValue();
    error ZeroQty();
    error WalletCap();
    error SupplyCap();
    error PoolNotSet();
    error TransfersDisabled();
    error ZeroDevWallet();

    /* ============================ NFT constants ============================ */
    uint256 public constant MAX_SUPPLY     = 9_999;
    uint8   public constant MAX_PER_WALLET = 3;

    /* ============================ spin reveal ============================
       Deterministic mirror of site-react/src/spin-logic.js. Reward for a
       given wallet is fixed by keccak256(wallet || SEED). Five quantile
       slots in [0,1) mapped to RUSH tiers, summed. Same math both sides —
       contract credits exactly the value the user saw on the site.

       Tiers (matches frontend):
         p=0.45 →    500       p=0.05 → 10_000
         p=0.30 →  1_500       p=0.03 → 30_000   (★ jackpot)
         p=0.17 →  4_000
    ============================================================== */
    bytes32 public constant SPIN_SEED =
        0xb1c4e7f29a5d3068e1c4b9a8f2d637e09c5a2b8f1e3d6749a0c2f5b8e1d4a7c0;
    uint256 private constant _ONE_RUSH = 1e18;

    /* ============================ split (BPS) ============================ */
    uint16 public constant POOL_BPS = 3_000;   // 30%
    uint16 public constant REF_BPS  = 1_000;   // 10%
    uint16 public constant DEV_BPS  = 6_000;   // 60%
    uint16 public constant BPS      = 10_000;

    /* ============================ wires ============================ */
    IERC20          public immutable rush;
    IWETH           public immutable weth;
    IUniswapV2Pair  public pair;
    address payable public devWallet;
    uint256         public mintPriceWei;
    bool            public phaseOpen;

    /* ============================ nft state ============================ */
    uint256 public totalMinted;

    /* ============================ per-wallet ============================ */
    struct MintRecord {
        uint16  count;
        bool    spinCredited;
        address referrer;     // first VALID non-fallback referrer (sticky)
        uint64  firstMintAt;
    }
    mapping(address => MintRecord) public mints;

    /* ============================ aggregates ============================ */
    uint256 public totalEthPaid;
    uint256 public totalEthToPool;
    uint256 public totalEthToRef;
    uint256 public totalEthToDev;
    mapping(address => uint256) public refEthEarned;
    mapping(address => uint256) public refMintCount;

    /* ============================ events ============================ */

    /* -- admin -- */
    event PairSet(address indexed pair);
    event DevWalletSet(address indexed dev);
    event PriceSet(uint256 mintPriceWei);
    event PhaseOpened(uint64 timestamp);
    event PhaseClosedEvent(uint64 timestamp);

    /* -- NFT (per token) -- */
    event Minted(address indexed to, uint256 indexed tokenId);

    /* -- mint flow (per tx) -- */
    event MintExecuted(
        address indexed user,
        address indexed referrer,
        uint8   qty,
        uint256 firstTokenId,
        uint256 ethPaid
    );
    event MintSplit(
        address indexed user,
        uint256 ethTotal,
        uint256 ethToPool,
        uint256 ethToRef,
        uint256 ethToDev
    );
    event ReferralPaid(
        address indexed referrer,
        address indexed user,
        uint256 ethAmount,
        bool    devFallback
    );
    event PoolInjected(
        uint256 ethDonated,
        uint112 newReserveRush,
        uint112 newReserveWeth
    );
    event SpinUnlocked(address indexed user, uint256 rushAmount);

    /* ============================ ctor / admin ============================ */
    constructor(
        address         _rush,
        address         _weth,
        address payable _dev,
        uint256         _mintPriceWei
    )
        ERC721("Rush Gate Coin", "RUSH-GATE")
        Ownable(msg.sender)
    {
        if (_dev == address(0)) revert ZeroDevWallet();
        rush         = IERC20(_rush);
        weth         = IWETH(_weth);
        devWallet    = _dev;
        mintPriceWei = _mintPriceWei;
        emit DevWalletSet(_dev);
        emit PriceSet(_mintPriceWei);
    }

    /// Wire Uniswap V2 pair (created in P2). Locks once phase opens.
    function setPair(address p) external onlyOwner {
        if (phaseOpen) revert PhaseAlreadyOpen();
        pair = IUniswapV2Pair(p);
        emit PairSet(p);
    }

    function setPrice(uint256 newPriceWei) external onlyOwner {
        if (phaseOpen) revert PhaseAlreadyOpen();
        mintPriceWei = newPriceWei;
        emit PriceSet(newPriceWei);
    }

    /// Owner can rotate the dev wallet (e.g. to a multisig) AT ANY TIME.
    /// Zero is rejected — sending ETH to 0x0 silently burns it on EVM.
    function setDevWallet(address payable d) external onlyOwner {
        if (d == address(0)) revert ZeroDevWallet();
        devWallet = d;
        emit DevWalletSet(d);
    }

    function openPhase() external onlyOwner {
        if (address(pair) == address(0)) revert PoolNotSet();
        phaseOpen = true;
        emit PhaseOpened(uint64(block.timestamp));
    }

    function closePhase() external onlyOwner {
        phaseOpen = false;
        emit PhaseClosedEvent(uint64(block.timestamp));
    }

    /* ============================ mint ============================ */
    function mint(uint8 qty, address referrer) external payable nonReentrant {
        if (msg.sender != tx.origin)                  revert NotEOA();
        if (!phaseOpen)                               revert PhaseClosed();
        if (qty == 0)                                 revert ZeroQty();
        if (msg.value != uint256(qty) * mintPriceWei) revert WrongValue();

        MintRecord storage rec = mints[msg.sender];
        if (uint256(rec.count) + qty > MAX_PER_WALLET) revert WalletCap();
        if (totalMinted + qty > MAX_SUPPLY)            revert SupplyCap();

        // ---- referrer resolution (returns devWallet on any invalid input) ----
        address effectiveRef = _resolveRef(msg.sender, referrer, rec);

        // ---- split (remainder goes to dev to absorb rounding dust) ----
        uint256 total  = msg.value;
        uint256 toPool = (total * POOL_BPS) / BPS;
        uint256 toRef  = (total * REF_BPS)  / BPS;
        uint256 toDev  = total - toPool - toRef;

        // ---- mint NFTs ----
        uint256 firstId = totalMinted + 1;
        for (uint256 i = 0; i < qty; i++) {
            uint256 tokenId = firstId + i;
            _safeMint(msg.sender, tokenId);
            emit Minted(msg.sender, tokenId);
        }
        totalMinted += qty;

        // ---- first-mint side effects ----
        // Note: we do NOT call into RushClaim here. The spin entitlement S
        // is materialized lazily by RushClaim itself (it calls our pure
        // `spinReward()` directly when the user first claims). This:
        //   - removes the only cross-contract write surface (no `creditSpin`
        //     to spoof, no `minter` address for the owner to point at an EOA);
        //   - shaves an external call + storage write off every first mint;
        //   - keeps the on-chain enforcement of "no mint, no spin" (RushClaim
        //     gates materialization on `gateCoin.balanceOf(user) > 0`).
        if (rec.count == 0) {
            rec.firstMintAt = uint64(block.timestamp);

            uint256 s = spinReward(msg.sender);
            if (s > 0) {
                rec.spinCredited = true;          // local UX flag (read by frontend)
                emit SpinUnlocked(msg.sender, s); // indexer-friendly notification
            }
        }

        // ---- sticky-bind referrer (only real EOAs, not dev fallback) ----
        if (rec.referrer == address(0) && effectiveRef != devWallet) {
            rec.referrer = effectiveRef;
        }

        rec.count += qty;

        // ---- aggregates ----
        totalEthPaid   += total;
        totalEthToPool += toPool;
        totalEthToRef  += toRef;
        totalEthToDev  += toDev;

        // ---- payouts ----
        _injectPool(toPool);
        _payReferrer(effectiveRef, msg.sender, toRef);
        _sendEth(devWallet, toDev);

        emit MintExecuted(msg.sender, effectiveRef, qty, firstId, total);
        emit MintSplit(msg.sender, total, toPool, toRef, toDev);
    }

    /* ============================ spin math (public, pure) ============================
       Anyone can query their pre-determined reward without minting.
       Frontend uses this as a view to render the "your spin" preview.
    ============================================================== */
    function spinReward(address wallet) public pure returns (uint256 s) {
        bytes32 h = keccak256(abi.encodePacked(wallet, SPIN_SEED));
        uint256 hUint = uint256(h);
        unchecked {
            for (uint256 i = 0; i < 5; i++) {
                // big-endian: slot 0 = bytes[0..3] = high 32 bits
                uint32 slot = uint32(hUint >> (224 - i * 32));
                s += _tierValue(slot);
            }
        }
    }

    function _tierValue(uint32 slot) private pure returns (uint256) {
        // 2^32 thresholds matching JS quantiles 0.45/0.75/0.92/0.97/1.00
        if (slot < 1_932_735_283) return    500 * _ONE_RUSH;
        if (slot < 3_221_225_472) return  1_500 * _ONE_RUSH;
        if (slot < 3_951_369_912) return  4_000 * _ONE_RUSH;
        if (slot < 4_166_117_888) return 10_000 * _ONE_RUSH;
        return                         30_000 * _ONE_RUSH;
    }

    /* ============================ internals ============================ */
    function _resolveRef(address user, address ref, MintRecord storage rec)
        internal
        view
        returns (address)
    {
        // sticky bind from a previous mint
        if (rec.referrer != address(0))   return rec.referrer;

        if (ref == address(0))            return devWallet;   // empty
        if (ref == user)                  return devWallet;   // self
        if (ref.code.length != 0)         return devWallet;   // contract
        return ref;
    }

    function _injectPool(uint256 ethAmount) internal {
        if (ethAmount == 0) return;
        if (address(pair) == address(0)) revert PoolNotSet();

        // single-sided donation: wrap → transfer → sync. Grows k permanently.
        weth.deposit{value: ethAmount}();
        require(weth.transfer(address(pair), ethAmount), "GateCoin: weth transfer failed");
        pair.sync();

        (uint112 r0, uint112 r1,) = pair.getReserves();
        address t0 = pair.token0();
        (uint112 rRush, uint112 rWeth) = t0 == address(rush) ? (r0, r1) : (r1, r0);
        emit PoolInjected(ethAmount, rRush, rWeth);
    }

    function _payReferrer(address ref, address user, uint256 amount) internal {
        if (amount == 0) return;
        bool fallbackDev = (ref == devWallet);
        _sendEth(payable(ref), amount);
        if (!fallbackDev) {
            refEthEarned[ref] += amount;
            refMintCount[ref] += 1;
        }
        emit ReferralPaid(ref, user, amount, fallbackDev);
    }

    function _sendEth(address payable to, uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = to.call{value: amount}("");
        require(ok, "GateCoin: eth send failed");
    }

    /* ============================ on-chain art ============================
       Every Gate Coin renders as an SVG embedded in a data: URI. No IPFS,
       no off-chain dependency — what you see is in the contract bytecode.

       Card aesthetic matches site-react/src/components/mint/GateCoinCard.jsx:
         gold border + corner pluses
         "GATE COIN" header
         #0001..#9999 token id (jumbo)
         ★ star emblem
         [ SOULBOUND ] pink dashed tag
         bound-to owner short-address (cyan)
    ============================================================== */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        address ownerAddr = _ownerOf(tokenId);
        // Art itself is identical across every token — pure coin on the binary
        // background, no text overlays. Per-token identity lives in the JSON
        // metadata's `name` and `attributes`.
        string memory svgB64 = Base64.encode(bytes(_renderSVG()));
        bytes memory json = bytes(_buildJSON(tokenId, ownerAddr, svgB64));
        return string.concat("data:application/json;base64,", Base64.encode(json));
    }

    function _buildJSON(uint256 tokenId, address ownerAddr, string memory svgB64)
        internal
        pure
        returns (string memory)
    {
        return string.concat(_jsonHead(tokenId), _jsonImage(svgB64), _jsonAttrs(tokenId, ownerAddr));
    }

    function _jsonHead(uint256 tokenId) internal pure returns (string memory) {
        return string.concat(
            '{"name":"Gate Coin #', _pad4(tokenId),
            '","description":"Soulbound Gate Coin \\u2014 phase-3 entitlement ticket for the $RUSH protocol. Non-transferable.",'
        );
    }

    function _jsonImage(string memory svgB64) internal pure returns (string memory) {
        return string.concat('"image":"data:image/svg+xml;base64,', svgB64, '",');
    }

    function _jsonAttrs(uint256 tokenId, address ownerAddr) internal pure returns (string memory) {
        return string.concat(
            '"attributes":[',
                '{"trait_type":"Token ID","value":"', Strings.toString(tokenId), '"},',
                '{"trait_type":"Bound To","value":"', Strings.toHexString(uint160(ownerAddr), 20), '"},',
                '{"trait_type":"Soulbound","value":"true"},',
                '{"trait_type":"Series","value":"P3 Gate"}',
            ']}'
        );
    }

    /// The art is identical across every Gate Coin — a pure gold-striped
    /// coin on the site's binary "01010" background. Per-token identity is
    /// expressed in the JSON metadata (`name`, `attributes`), not in the
    /// rendered image. Square viewBox 400×400 so wallets/marketplaces don't
    /// letterbox.
    function _renderSVG() internal pure returns (string memory) {
        return string.concat(_svgDefs(), _svgBody(), "</svg>");
    }

    function _svgDefs() internal pure returns (string memory) {
        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400" ',
            'viewBox="0 0 400 400" font-family="monospace">',
            '<defs>',
                _bgPattern(),
                _coinPattern(),
                _coinHighlight(),
                '<clipPath id="cClip"><circle cx="200" cy="200" r="172"/></clipPath>',
            '</defs>'
        );
    }

    // Background — purple ASCII noise mirroring the site's
    // AsciiBackground.jsx (same bg color #0a0414, same muted-purple tier
    // colors, same ASCII charset feel). Three text rows per tile, each
    // in a different purple tier, gives the layered noise look of the
    // animated canvas on the site.
    function _bgPattern() internal pure returns (string memory) {
        return string.concat(
            '<pattern id="bg" x="0" y="0" width="220" height="42" patternUnits="userSpaceOnUse">',
                '<rect width="220" height="42" fill="#0a0414"/>',
                '<text x="0" y="13" font-size="12" font-weight="bold" fill="#5a3a8c" textLength="220" lengthAdjust="spacingAndGlyphs">@#$%*+=-_~RUSH#$@*+=ABC0123</text>',
                '<text x="0" y="27" font-size="12" font-weight="bold" fill="#3a266a" textLength="220" lengthAdjust="spacingAndGlyphs">RUSH###$$$_~+=-?!@#$%*+=ABC</text>',
                '<text x="0" y="41" font-size="12" font-weight="bold" fill="#241650" textLength="220" lengthAdjust="spacingAndGlyphs">ABC0123!*+=_~^?@#$%RUSH##$$</text>',
            '</pattern>'
        );
    }

    /// Coin face — dense gold ASCII rows (#, $, %) clipped to the circle.
    /// Three-row tile gives the avatar's banded look (mid → bright → mid).
    function _coinPattern() internal pure returns (string memory) {
        return string.concat(
            '<pattern id="coin" x="0" y="0" width="140" height="42" patternUnits="userSpaceOnUse">',
                '<rect width="140" height="42" fill="#1a0c00"/>',
                '<text x="0" y="13" font-size="15" font-weight="bold" fill="#eab820" textLength="140" lengthAdjust="spacingAndGlyphs">####$$####$###%%####</text>',
                '<text x="0" y="27" font-size="15" font-weight="bold" fill="#ffd700" textLength="140" lengthAdjust="spacingAndGlyphs">####$$$###%%####$$###</text>',
                '<text x="0" y="41" font-size="15" font-weight="bold" fill="#c08810" textLength="140" lengthAdjust="spacingAndGlyphs">###%%###$$####%%####</text>',
            '</pattern>'
        );
    }

    /// Soft upper highlight overlay → 3D bevel feel without any neon glow.
    function _coinHighlight() internal pure returns (string memory) {
        return string.concat(
            '<radialGradient id="hl" cx="42%" cy="32%" r="55%">',
                '<stop offset="0%" stop-color="#fff5a0" stop-opacity="0.28"/>',
                '<stop offset="100%" stop-color="#fff5a0" stop-opacity="0"/>',
            '</radialGradient>'
        );
    }

    function _svgBody() internal pure returns (string memory) {
        return string.concat(
            '<rect width="400" height="400" fill="url(#bg)"/>',
            '<g clip-path="url(#cClip)">',
                '<rect width="400" height="400" fill="url(#coin)"/>',
                '<rect width="400" height="400" fill="url(#hl)"/>',
            '</g>'
        );
    }

    function _pad4(uint256 n) internal pure returns (string memory s) {
        s = Strings.toString(n);
        if (n >= 1000) return s;
        if (n >= 100)  return string.concat("0",   s);
        if (n >= 10)   return string.concat("00",  s);
        return                string.concat("000", s);
    }

    /* ============================ soulbound override ============================ */
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address from)
    {
        from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert TransfersDisabled();
        return super._update(to, tokenId, auth);
    }

    function approve(address, uint256)               public pure override { revert TransfersDisabled(); }
    function setApprovalForAll(address, bool)        public pure override { revert TransfersDisabled(); }

    /* ============================ rescue ============================ */
    function rescueERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }
}
