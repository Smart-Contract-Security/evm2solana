// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721}          from "solady/src/tokens/ERC721.sol";
import {Ownable}         from "solady/src/auth/Ownable.sol";
import {LibString}       from "solady/src/utils/LibString.sol";
import {Base64}          from "solady/src/utils/Base64.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

import {ICrystalForge}   from "./ICrystalForge.sol";

interface IERC20Min {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title CrystalForge — Dark Crystal NFT collection (max 333 supply).
///
/// Mint:   bond 1,000,000 $DARK + 0.005 ETH per Crystal -> mint ERC-721.
///         Rarity (Common 70% / Rare 20% / Epic 8% / Legendary 2%) is rolled
///         on-chain from block.prevrandao at mint time.
///
/// Yield:  receives $DARK rewards from the DarkHook on every taxed buy.
///         Distributed pro-rata by Crystal POWER (1 / 2 / 4 / 10 by rarity).
///
/// Shatter:burn the Crystal to reclaim 80% of the bonded $DARK + 80% of the
///         bonded ETH. The remaining 20% stays in the contract — half is
///         credited to the remaining Crystal holders, half stays as treasury.
///
/// On-chain pixel SVG: every Crystal renders a unique pixel-art SVG via
/// tokenURI() — encoded in base64, no IPFS, no off-chain dependencies.
contract CrystalForge is ERC721, Ownable, ICrystalForge {
    using LibString          for uint256;
    using SafeTransferLib    for address;

    IERC20Min public immutable dark;

    uint256 public constant MAX_SUPPLY      = 333;
    uint256 public constant DARK_PER_MINT   = 1_000_000e18;
    uint256 public constant ETH_PER_MINT    = 0.005 ether;
    uint256 public constant SHATTER_BPS     = 8_000;     // 80% returned
    uint256 public constant BPS_DENOM       = 10_000;

    // Rarity & power
    enum Rarity { Common, Rare, Epic, Legendary }
    uint256[4] public POWER_BY_RARITY = [uint256(1), 2, 4, 10];

    struct Crystal {
        Rarity  rarity;
        uint64  mintTimestamp;
        uint96  bondedDark;     // 96 bits fits 1e24 with room
        uint96  bondedEth;
    }

    uint256 public nextId;            // 0-indexed counter; range [0, MAX_SUPPLY)
    mapping(uint256 => Crystal) public crystals;

    // Reward accounting (MasterChef-style by POWER, not by token count)
    address public hook;              // DarkHook — the only address that calls notifyReward
    bool    public hookFrozen;
    uint256 public totalPower;        // sum of POWER_BY_RARITY over all live crystals
    uint256 public accDarkPerPower;   // scaled by 1e18
    uint256 public totalRewards;      // cumulative DARK streamed in
    mapping(uint256 => uint256) public rewardDebt;  // tokenId -> debt at last touch

    event Forged(uint256 indexed tokenId, address indexed owner, Rarity rarity, uint96 darkBonded, uint96 ethBonded);
    event Shattered(uint256 indexed tokenId, address indexed owner, uint96 darkReturned, uint96 ethReturned);
    event Claimed(uint256 indexed tokenId, address indexed owner, uint256 amount);
    event RewardAdded(uint256 amount, uint256 newAccPerPower);
    event HookSet(address indexed hook);

    constructor(address darkToken, address owner_) {
        require(darkToken != address(0), "zero token");
        dark = IERC20Min(darkToken);
        _initializeOwner(owner_);
    }

    function name()   public pure override returns (string memory) { return "Dark Crystal"; }
    function symbol() public pure override returns (string memory) { return "CRYSTAL"; }

    function setHook(address newHook) external onlyOwner {
        require(!hookFrozen, "frozen");
        require(newHook != address(0), "zero hook");
        hook = newHook;
        hookFrozen = true;
        emit HookSet(newHook);
    }

    // ---- Forge / Shatter ----------------------------------------------------

    function forge() external payable returns (uint256 tokenId) {
        require(msg.value == ETH_PER_MINT, "ETH != mint price");
        require(nextId < MAX_SUPPLY, "sold out");

        // Pull DARK
        require(dark.transferFrom(msg.sender, address(this), DARK_PER_MINT), "dark pull failed");

        // Roll rarity from block.prevrandao + nextId
        Rarity r = _rollRarity(nextId);
        uint256 power = POWER_BY_RARITY[uint256(r)];

        tokenId = nextId++;
        crystals[tokenId] = Crystal({
            rarity:        r,
            mintTimestamp: uint64(block.timestamp),
            bondedDark:    uint96(DARK_PER_MINT),
            bondedEth:     uint96(ETH_PER_MINT)
        });

        totalPower += power;
        rewardDebt[tokenId] = (power * accDarkPerPower) / 1e18;

        _mint(msg.sender, tokenId);
        emit Forged(tokenId, msg.sender, r, uint96(DARK_PER_MINT), uint96(ETH_PER_MINT));
    }

    function shatter(uint256 tokenId) external {
        require(_ownerOf(tokenId) == msg.sender, "not owner");
        Crystal memory c = crystals[tokenId];
        uint256 power = POWER_BY_RARITY[uint256(c.rarity)];

        // Pay out pending rewards before shattering
        _claim(tokenId, msg.sender, power);

        // Remove from totalPower
        totalPower -= power;
        delete crystals[tokenId];
        delete rewardDebt[tokenId];
        _burn(tokenId);

        // 80% returned
        uint256 darkBack = (uint256(c.bondedDark) * SHATTER_BPS) / BPS_DENOM;
        uint256 ethBack  = (uint256(c.bondedEth)  * SHATTER_BPS) / BPS_DENOM;

        // 10% of the residual (= 2% of bond) credited to remaining holders as a DARK reward boost
        if (totalPower > 0) {
            uint256 boost = uint256(c.bondedDark) - darkBack;  // 20% of dark bond stays
            uint256 toRemainders = boost / 2;  // half boost, half stays as treasury
            accDarkPerPower += (toRemainders * 1e18) / totalPower;
            totalRewards    += toRemainders;
            emit RewardAdded(toRemainders, accDarkPerPower);
        }

        // Pay holder
        require(dark.transfer(msg.sender, darkBack), "dark return failed");
        (bool ok, ) = payable(msg.sender).call{value: ethBack}("");
        require(ok, "eth return failed");

        emit Shattered(tokenId, msg.sender, uint96(darkBack), uint96(ethBack));
    }

    function claim(uint256 tokenId) external returns (uint256 owed) {
        address holder = _ownerOf(tokenId);
        require(holder == msg.sender, "not owner");
        uint256 power = POWER_BY_RARITY[uint256(crystals[tokenId].rarity)];
        owed = _claim(tokenId, msg.sender, power);
        require(owed > 0, "nothing");
    }

    // ---- Hook integration ---------------------------------------------------

    function notifyReward(uint256 amount) external {
        require(msg.sender == hook, "only hook");
        if (totalPower == 0 || amount == 0) return;
        accDarkPerPower += (amount * 1e18) / totalPower;
        totalRewards    += amount;
        emit RewardAdded(amount, accDarkPerPower);
    }

    // ---- Views --------------------------------------------------------------

    function earned(uint256 tokenId) public view returns (uint256) {
        uint256 power = POWER_BY_RARITY[uint256(crystals[tokenId].rarity)];
        uint256 raw   = (power * accDarkPerPower) / 1e18;
        uint256 debt  = rewardDebt[tokenId];
        if (raw <= debt) return 0;
        return raw - debt;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "nonexistent");
        Crystal memory c = crystals[tokenId];

        string memory svg = _buildSvg(tokenId, c.rarity);
        string memory rarityStr = ["Common", "Rare", "Epic", "Legendary"][uint256(c.rarity)];
        string memory powerStr  = POWER_BY_RARITY[uint256(c.rarity)].toString();

        bytes memory json = abi.encodePacked(
            '{"name":"Dark Crystal #', tokenId.toString(),
            '","description":"A Dark Crystal forged on Ethereum mainnet. Power: ', powerStr,
            '","image":"data:image/svg+xml;base64,', Base64.encode(bytes(svg)),
            '","attributes":[',
                '{"trait_type":"Rarity","value":"', rarityStr, '"},',
                '{"trait_type":"Power","value":', powerStr, '},',
                '{"trait_type":"Bonded DARK","value":', uint256(c.bondedDark).toString(), '},',
                '{"trait_type":"Bonded ETH","value":', uint256(c.bondedEth).toString(), '}',
            ']}'
        );
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    // ---- Internals ----------------------------------------------------------

    function _claim(uint256 tokenId, address to, uint256 power) internal returns (uint256 owed) {
        uint256 raw  = (power * accDarkPerPower) / 1e18;
        uint256 debt = rewardDebt[tokenId];
        if (raw > debt) {
            owed = raw - debt;
            rewardDebt[tokenId] = raw;
            require(dark.transfer(to, owed), "claim transfer failed");
            emit Claimed(tokenId, to, owed);
        }
    }

    function _rollRarity(uint256 seed) internal view returns (Rarity) {
        uint256 r = uint256(keccak256(abi.encodePacked(block.prevrandao, seed, msg.sender))) % 100;
        if (r < 2)  return Rarity.Legendary; //  2%
        if (r < 10) return Rarity.Epic;       //  8%
        if (r < 30) return Rarity.Rare;       // 20%
        return Rarity.Common;                 // 70%
    }

    /// @dev On-chain pixel SVG: 16x16 grid of crystal pixels, colored by rarity.
    function _buildSvg(uint256 tokenId, Rarity r) internal pure returns (string memory) {
        (string memory bg, string memory gem, string memory glow) = _palette(r);

        // 16x16 pixel crystal: hand-drawn shape, scaled to 512x512 via viewBox
        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges" width="512" height="512">',
            '<rect width="16" height="16" fill="', bg, '"/>',
            // Glow ring
            '<rect x="3" y="3" width="10" height="10" fill="none" stroke="', glow, '" stroke-width="0.2" opacity="0.6"/>',
            // Crystal body (diamond shape, pixel-perfect)
            '<polygon points="8,2 11,5 11,10 8,13 5,10 5,5" fill="', gem, '"/>',
            // Highlight stripe
            '<polygon points="8,2 9,5 9,10 8,11 7,10 7,5" fill="', glow, '" opacity="0.4"/>',
            // Sparkles
            '<rect x="2" y="2" width="1" height="1" fill="', glow, '" opacity="0.8"/>',
            '<rect x="13" y="3" width="1" height="1" fill="', glow, '" opacity="0.6"/>',
            '<rect x="13" y="12" width="1" height="1" fill="', glow, '" opacity="0.8"/>',
            '<rect x="2" y="13" width="1" height="1" fill="', glow, '" opacity="0.6"/>',
            _ledger(tokenId),
            '</svg>'
        ));
    }

    function _ledger(uint256 tokenId) internal pure returns (string memory) {
        return string(abi.encodePacked(
            '<text x="0.4" y="15.6" font-size="1.3" fill="#888" font-family="monospace">#',
            tokenId.toString(),
            '</text>'
        ));
    }

    function _palette(Rarity r) internal pure returns (string memory bg, string memory gem, string memory glow) {
        if (r == Rarity.Legendary) return ("#0a0014", "#ff2bd6", "#ffffff");
        if (r == Rarity.Epic)      return ("#100022", "#a020f0", "#ff7bff");
        if (r == Rarity.Rare)      return ("#15001f", "#6b1aa5", "#cc66ff");
        return ("#1a0033", "#4a1577", "#9966cc");                  // Common
    }

    receive() external payable {}
}
