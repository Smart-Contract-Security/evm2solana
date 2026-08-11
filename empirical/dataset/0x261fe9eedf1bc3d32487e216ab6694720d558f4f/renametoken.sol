// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 ██████╗ ███████╗███╗   ██╗ █████╗ ███╗   ███╗███████╗
 ██╔══██╗██╔════╝████╗  ██║██╔══██╗████╗ ████║██╔════╝
 ██████╔╝█████╗  ██╔██╗ ██║███████║██╔████╔██║█████╗
 ██╔══██╗██╔══╝  ██║╚██╗██║██╔══██║██║╚██╔╝██║██╔══╝
 ██║  ██║███████╗██║ ╚████║██║  ██║██║ ╚═╝ ██║███████╗
 ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝

           TICKER: RENAME (forever, never changes)
           NAME:   set by anyone, anytime

  THIS CONTRACT IS A GAME
  ───────────────────────
  The ticker on every wallet, every chart, every DEX is RENAME and it
  always will be. But the long-form name of the token (the part next to
  the ticker) is mutable. Anyone can change it. That's the whole point.

  TWO PHASES. THE GAME HAS A "BEFORE" AND AN "AFTER."

  ── PHASE 1: GENESIS (right now, at deploy) ──
   • The name starts EMPTY. There is no AI-generated launch name. The
     ticker is RENAME and that's all anyone gets to know about it on
     chain. Snipe the description, not the branding.
   • Renaming is FREE. No fee. No crown refund. No burn.
   • Cooldown is 30 seconds — short enough to play with on testnet
     or mainnet without it feeling broken.
   • Every rename is recorded. Counts toward the leaderboard.
   • This is the playtest phase. Find the bugs. Set silly names.
     Get a feel for it. Cost: gas only.

  ── PHASE 2: THE GAME IS LIVE ──
   • Whoever deployed the contract has ONE button they can press:
     `igniteGame()`. They can press it exactly once, whenever they want.
     After they press it, they have no powers left at all. That's their
     entire role: they choose when the free phase ends.
   • Once ignited, renaming costs ETH. The fee starts at 0.0005 ETH and
     follows a bonded curve: +15% per rename. It decays back toward the
     floor when nobody renames (linear, ~1 ETH/day equivalent rate).
   • Cooldown drops to 60 seconds. Fast game.
   • When you get dethroned, you accrue a CROWN REFUND in storage:
     a share of the new namer's fee proportional to how long you held
     the throne (+1% per hour, capped at 50%). Pull it whenever.
   • The non-refunded portion of every fee goes to 0x...dEaD. Burned.
   • Stats keep accumulating across both phases. Genesis-phase renamers
     keep their badge numbers forever.

  ── WHY THIS STRUCTURE ──
   The deployer's only power is timing. They cannot pause, mint, freeze,
   change parameters, or rename for free in Phase 2. They cannot un-ignite.
   They cannot extend their power. The toggle is a one-way valve.

  ── SAFETY ──
   • Strict ERC-20 (EIP-20 + EIP-6093 errors). Fixed supply at deploy.
   • Name field is a `string`; only `name()` is mutable, never balances,
     allowances, supply, decimals, or symbol.
   • Reentrancy guards on rename and claim.
   • Checks-Effects-Interactions on every ETH movement.
   • Pull-pattern crown refunds (a malicious dethroned namer cannot
     grief future namers by rejecting ETH).
   • Name validated: 1–64 bytes, printable ASCII only (0x20–0x7E).
   • Direct ETH sends to the contract revert.
   • No upgradeable proxy. No admin in Phase 2.

  HAVE FUN. THE TICKER IS THE ONLY CONSTANT.
*/

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

contract Rename is IERC20, IERC20Metadata {
    // ─────────────────────── ERC-20 errors (EIP-6093) ───────────────────────
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);

    // ────────────────────────── Game errors ──────────────────────────
    error NameTooLong(uint256 given, uint256 max);
    error NameTooShort();
    error NameHasIllegalByte(uint256 index, uint8 byteValue);
    error InsufficientFee(uint256 paid, uint256 required);
    error CooldownActive(uint256 secondsRemaining);
    error NothingToClaim();
    error EthTransferFailed();
    error Reentrancy();
    error AlreadyIgnited();
    error NotIgniter();
    error EthNotAcceptedInGenesis();

    // ────────────────────────── ERC-20 state ──────────────────────────
    string  private _name;                       // mutable — that's the point
    string  private constant _SYMBOL = "RENAME"; // ticker — immutable forever
    uint8   private constant _DECIMALS = 18;
    uint256 private immutable _totalSupply;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // ────────────────────────── Two-phase state ──────────────────────────
    /// @notice The address that deployed the contract. Their ONE power is to
    /// flip `gameIgnited` from false to true, exactly once. After that, this
    /// address has zero special privileges in the contract.
    address public immutable igniter;

    /// @notice false during Genesis (free renames), true once the paid game starts.
    bool public gameIgnited;

    /// @notice timestamp of ignition. 0 while in Genesis.
    uint64 public ignitedAt;

    // ────────────────────────── Game parameters ──────────────────────────
    // Phase 1 (Genesis): free, fast.
    uint256 public constant GENESIS_COOLDOWN = 30 seconds;

    // Phase 2 (Live): paid, bonded curve.
    uint256 public constant LIVE_COOLDOWN     = 60 seconds;
    uint256 public constant FEE_FLOOR         = 0.0005 ether;
    uint256 public constant FEE_GROWTH_BPS    = 11_500;            // +15% per rename
    uint256 public constant DECAY_PER_SECOND  = 11_574_074_074_074; // ~1 ETH/day

    // Crown refund (Phase 2 only): % of the new fee paid back to the dethroned namer.
    uint256 public constant CROWN_BPS_PER_HOUR = 100;    // +1% / hour of reign
    uint256 public constant MAX_CROWN_BPS      = 5_000;  // capped at 50%

    // Name rules (both phases).
    uint256 public constant MAX_NAME_BYTES = 64;
    uint256 public constant MIN_NAME_BYTES = 1;

    address public constant BURN_SINK = 0x000000000000000000000000000000000000dEaD;

    // ────────────────────────── Throne state ──────────────────────────
    address public currentNamer;
    uint64  public throneSince;     // when currentNamer took the throne
    uint64  public lastRenameAt;    // for cooldown + decay
    uint128 public feeAtLastRename; // peak fee right after the last rename, decays from here

    // ────────────────────────── Stats / leaderboard ──────────────────────────
    uint256 public totalRenames;
    mapping(address => uint256) public renameCountOf;
    mapping(address => uint256) public ethSpentOnRenamesBy;
    mapping(address => uint256) public pendingCrownRefund;

    address public longestReignHolder;
    uint256 public longestReignDuration;

    // ────────────────────────── Reentrancy guard ──────────────────────────
    uint256 private _reentrancyStatus = 1; // 1 = unlocked, 2 = locked
    modifier nonReentrant() {
        if (_reentrancyStatus == 2) revert Reentrancy();
        _reentrancyStatus = 2;
        _;
        _reentrancyStatus = 1;
    }

    // ────────────────────────────── Events ──────────────────────────────
    event Renamed(
        address indexed newNamer,
        address indexed previousNamer,
        string  newName,
        uint256 renameNumber,
        uint256 feePaid,
        uint256 crownRefundToPrevious,
        uint256 reignDurationOfPrevious,
        bool    duringGenesis
    );
    event CrownRefundClaimed(address indexed namer, uint256 amount);
    event NewLongestReign(address indexed holder, uint256 durationSeconds);
    event Burned(uint256 amount);
    event GameIgnited(address indexed igniter, uint256 timestamp);

    // ────────────────────────────── Constructor ──────────────────────────────
    /// @notice Deploys the token. The NAME IS EMPTY at deploy. Anyone can set it
    /// for free during Genesis. The igniter can later flip the game to paid mode.
    /// @param initialSupply total supply in whole tokens (will be multiplied by 10**decimals)
    /// @param recipient who receives the entire supply at deploy
    constructor(uint256 initialSupply, address recipient) {
        if (recipient == address(0)) revert ERC20InvalidReceiver(address(0));

        // Name starts as "???" — mysterious placeholder, no branding hint.
        // Anyone can rename it instantly during Genesis for free.
        _name = "???";

        _totalSupply = initialSupply * (10 ** uint256(_DECIMALS));
        _balances[recipient] = _totalSupply;
        emit Transfer(address(0), recipient, _totalSupply);

        igniter         = msg.sender;
        gameIgnited     = false;
        currentNamer    = address(0);
        throneSince     = uint64(block.timestamp);
        lastRenameAt    = uint64(block.timestamp);
        feeAtLastRename = uint128(FEE_FLOOR); // only matters once ignited
    }

    // ═════════════════════════════════════════════════════════════════════
    //                          IGNITION (one-shot)
    // ═════════════════════════════════════════════════════════════════════

    /// @notice The igniter flips the contract into paid mode. One-way, one-shot.
    /// After this, the igniter has no remaining powers.
    function igniteGame() external {
        if (msg.sender != igniter) revert NotIgniter();
        if (gameIgnited) revert AlreadyIgnited();
        gameIgnited = true;
        ignitedAt = uint64(block.timestamp);
        // Reset rename cadence so the first paid renamer doesn't have to fight
        // Genesis-phase cooldown timing.
        lastRenameAt    = uint64(block.timestamp);
        feeAtLastRename = uint128(FEE_FLOOR);
        emit GameIgnited(msg.sender, block.timestamp);
    }

    // ═════════════════════════════════════════════════════════════════════
    //                           THE NAME GAME
    // ═════════════════════════════════════════════════════════════════════

    /// @notice Set the token's name. Free during Genesis, paid after ignition.
    /// Any overpayment in Phase 2 is refunded in the same tx.
    function rename(string calldata newName) external payable nonReentrant {
        bytes memory nb = bytes(newName);
        _validateName(nb);

        bool ignited = gameIgnited;
        uint256 cooldown = ignited ? LIVE_COOLDOWN : GENESIS_COOLDOWN;
        uint256 elapsed = block.timestamp - lastRenameAt;
        if (elapsed < cooldown) revert CooldownActive(cooldown - elapsed);

        uint256 fee = 0;
        if (ignited) {
            fee = currentRenameFee();
            if (msg.value < fee) revert InsufficientFee(msg.value, fee);
        } else {
            // Genesis phase: paying ETH would be wasted (no refund path), so we
            // disallow it loudly rather than silently keep the funds.
            if (msg.value != 0) revert EthNotAcceptedInGenesis();
        }

        // ── Effects ──
        address previousNamer = currentNamer;
        uint256 reignDuration = block.timestamp - throneSince;

        uint256 crown = 0;
        if (ignited && previousNamer != address(0)) {
            uint256 bps = (reignDuration / 1 hours) * CROWN_BPS_PER_HOUR;
            if (bps > MAX_CROWN_BPS) bps = MAX_CROWN_BPS;
            crown = (fee * bps) / 10_000;
            if (crown > 0) {
                pendingCrownRefund[previousNamer] += crown;
            }
        }

        // Longest-reign tracking — works in both phases, so Genesis throne-hoarders
        // can also earn the bragging-rights badge.
        if (previousNamer != address(0) && reignDuration > longestReignDuration) {
            longestReignDuration = reignDuration;
            longestReignHolder = previousNamer;
            emit NewLongestReign(previousNamer, reignDuration);
        }

        _name        = newName;
        currentNamer = msg.sender;
        throneSince  = uint64(block.timestamp);
        lastRenameAt = uint64(block.timestamp);

        if (ignited) {
            uint256 nextFee = (fee * FEE_GROWTH_BPS) / 10_000;
            if (nextFee > type(uint128).max) nextFee = type(uint128).max;
            feeAtLastRename = uint128(nextFee);
        }

        unchecked {
            totalRenames += 1;
            renameCountOf[msg.sender] += 1;
            if (ignited) ethSpentOnRenamesBy[msg.sender] += fee;
        }

        emit Renamed(
            msg.sender,
            previousNamer,
            newName,
            totalRenames,
            fee,
            crown,
            reignDuration,
            !ignited
        );

        // ── Interactions (last) ──
        if (ignited) {
            uint256 toBurn = fee - crown;
            if (toBurn > 0) {
                (bool ok, ) = BURN_SINK.call{value: toBurn}("");
                if (!ok) revert EthTransferFailed();
                emit Burned(toBurn);
            }
            uint256 overpay = msg.value - fee;
            if (overpay > 0) {
                (bool ok2, ) = msg.sender.call{value: overpay}("");
                if (!ok2) revert EthTransferFailed();
            }
        }
    }

    /// @notice Claim accumulated crown refunds (pull pattern).
    function claimCrownRefund() external nonReentrant {
        uint256 amt = pendingCrownRefund[msg.sender];
        if (amt == 0) revert NothingToClaim();
        pendingCrownRefund[msg.sender] = 0;
        (bool ok, ) = msg.sender.call{value: amt}("");
        if (!ok) revert EthTransferFailed();
        emit CrownRefundClaimed(msg.sender, amt);
    }

    // ═════════════════════════════════════════════════════════════════════
    //                              VIEWS
    // ═════════════════════════════════════════════════════════════════════

    /// @notice Current required fee (0 during Genesis, decayed bonded curve in Phase 2).
    function currentRenameFee() public view returns (uint256) {
        if (!gameIgnited) return 0;
        uint256 elapsed = block.timestamp - lastRenameAt;
        uint256 decay   = elapsed * DECAY_PER_SECOND;
        uint256 peak    = uint256(feeAtLastRename);
        if (decay >= peak) return FEE_FLOOR;
        uint256 fee = peak - decay;
        return fee < FEE_FLOOR ? FEE_FLOOR : fee;
    }

    function currentReignDuration() external view returns (uint256) {
        return block.timestamp - throneSince;
    }

    function cooldownRemaining() external view returns (uint256) {
        uint256 cd = gameIgnited ? LIVE_COOLDOWN : GENESIS_COOLDOWN;
        uint256 elapsed = block.timestamp - lastRenameAt;
        if (elapsed >= cd) return 0;
        return cd - elapsed;
    }

    /// @notice One-call dashboard read for front-ends.
    function gameState() external view returns (
        string  memory currentName_,
        bool    ignited_,
        address namer_,
        uint256 reignDuration_,
        uint256 fee_,
        uint256 cooldown_,
        uint256 totalRenames_,
        address longestReignHolder_,
        uint256 longestReignDuration_
    ) {
        currentName_          = _name;
        ignited_              = gameIgnited;
        namer_                = currentNamer;
        reignDuration_        = block.timestamp - throneSince;
        fee_                  = currentRenameFee();
        uint256 cd            = ignited_ ? LIVE_COOLDOWN : GENESIS_COOLDOWN;
        uint256 elapsed       = block.timestamp - lastRenameAt;
        cooldown_             = elapsed >= cd ? 0 : cd - elapsed;
        totalRenames_         = totalRenames;
        longestReignHolder_   = longestReignHolder;
        longestReignDuration_ = longestReignDuration;
    }

    // ═════════════════════════════════════════════════════════════════════
    //                         NAME VALIDATION
    // ═════════════════════════════════════════════════════════════════════

    /// @dev 1–64 bytes, printable ASCII only (0x20–0x7E). Blocks control bytes,
    /// nulls, arbitrary binary, and non-ASCII Unicode (so on-chain bytes stay
    /// predictable). Front-ends are free to render names however they want.
    function _validateName(bytes memory nb) internal pure {
        uint256 n = nb.length;
        if (n < MIN_NAME_BYTES) revert NameTooShort();
        if (n > MAX_NAME_BYTES) revert NameTooLong(n, MAX_NAME_BYTES);
        for (uint256 i = 0; i < n; i++) {
            uint8 b = uint8(nb[i]);
            if (b < 0x20 || b > 0x7E) revert NameHasIllegalByte(i, b);
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //                         ERC-20 METADATA
    // ═════════════════════════════════════════════════════════════════════

    function name() external view override returns (string memory) { return _name; }
    function symbol() external pure override returns (string memory) { return _SYMBOL; }
    function decimals() external pure override returns (uint8) { return _DECIMALS; }

    // ═════════════════════════════════════════════════════════════════════
    //                         ERC-20 CORE
    // ═════════════════════════════════════════════════════════════════════

    function totalSupply() external view override returns (uint256) { return _totalSupply; }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function allowance(address owner_, address spender) external view override returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        _spendAllowance(from, msg.sender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) revert ERC20InvalidSender(address(0));
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBal = _balances[from];
        if (fromBal < value) revert ERC20InsufficientBalance(from, fromBal, value);
        unchecked {
            _balances[from] = fromBal - value;
            _balances[to]  += value;
        }
        emit Transfer(from, to, value);
    }

    function _approve(address owner_, address spender, uint256 value) internal {
        if (owner_ == address(0)) revert ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        _allowances[owner_][spender] = value;
        emit Approval(owner_, spender, value);
    }

    function _spendAllowance(address owner_, address spender, uint256 value) internal {
        uint256 current = _allowances[owner_][spender];
        if (current != type(uint256).max) {
            if (current < value) revert ERC20InsufficientAllowance(spender, current, value);
            unchecked { _allowances[owner_][spender] = current - value; }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //                         SAFETY RAILS
    // ═════════════════════════════════════════════════════════════════════

    receive() external payable {
        revert("Use rename() to send ETH");
    }
    fallback() external payable {
        revert("Use rename() to send ETH");
    }
}
