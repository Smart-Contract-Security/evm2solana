// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*

  NormlRouter — single-approval entrypoint for all Norml user actions.

  Security envelope (modeled after Uniswap Universal Router + Seaport):

    - Immutable. No upgradeability, no admin, no owner. Once deployed, the
      code and its target addresses cannot change.
    - Hardcoded targets only. Every external call goes to one of the
      pre-set Norml contracts. There is no `execute(bytes)`, no
      `call(target, data)`, no `delegatecall` anywhere.
    - No token sweeping. The router never holds user funds across calls.
    - Per-call exact allowances, zero-first-then-set, zeroed after the
      target's pull. Max allowances are never written from the router.
    - User identity preserved via typed *For(user, ...) on the targets.
    - Reentrancy-guarded on every entry point that touches ERC-20.
    - SafeERC20-style wrappers tolerate non-bool-returning tokens.

  UX:

    - One time: user calls `approve(NORML_TOKEN, NormlRouter, max)`.
    - Every subsequent Norml action (stake, unstake, claim, ...) is a
      single tx with no further approvals.

*/

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

interface INormlForUs {
    function stakeFor(address user, uint256 tokenId, uint256 amount) external;
    function unstakeFor(address user, uint256 tokenId, uint256 amount) external;
    function LIQUID_EDITION() external view returns (address);
}

interface INormlForMe {
    function mintFor(address user, uint256 amount)
        external
        payable
        returns (uint256 tokenId);
    function addTokensFor(address user, uint256 tokenId, uint256 amount) external;
    function burnAndUnlockFor(address user, uint256 tokenId) external;
    function NORML_TOKEN() external view returns (address);
    function mintPrice() external view returns (uint256);
}

contract NormlRouter {
    // ---------------------------------------------------------------------
    // Immutable wiring. Set once at construction; no setters exist.
    // ---------------------------------------------------------------------

    /// @notice SuperRare-issued NORML ERC-20.
    address public immutable NORML_TOKEN;

    /// @notice Per-NFT staking contract (NormlForUs).
    address public immutable NORML_FOR_US;

    /// @notice Generative/global staking contract (NormlForMe).
    address public immutable NORML_FOR_ME;

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error ZeroAddress();
    error ZeroAmount();
    error TransferFailed();
    error ApproveFailed();
    error TokenMismatch();
    error Reentrancy();

    // ---------------------------------------------------------------------
    // Reentrancy guard
    // ---------------------------------------------------------------------

    uint256 private _locked = 1;

    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    // ---------------------------------------------------------------------
    // Construction
    // ---------------------------------------------------------------------

    constructor(
        address normlToken,
        address normlForUs,
        address normlForMe
    ) {
        if (
            normlToken == address(0) ||
            normlForUs == address(0) ||
            normlForMe == address(0)
        ) revert ZeroAddress();

        // Sanity-check: targets must hold the same NORML ERC-20.
        if (INormlForUs(normlForUs).LIQUID_EDITION() != normlToken) revert TokenMismatch();
        if (INormlForMe(normlForMe).NORML_TOKEN() != normlToken) revert TokenMismatch();

        NORML_TOKEN = normlToken;
        NORML_FOR_US = normlForUs;
        NORML_FOR_ME = normlForMe;
    }

    // ---------------------------------------------------------------------
    // SafeERC20-style helpers — tolerate tokens that return no data.
    // ---------------------------------------------------------------------

    function _safeTransferFrom(address from, address to, uint256 amount) internal {
        (bool ok, bytes memory data) = NORML_TOKEN.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert TransferFailed();
    }

    function _safeApprove(address spender, uint256 amount) internal {
        (bool ok, bytes memory data) = NORML_TOKEN.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        );
        if (!ok || (data.length != 0 && !abi.decode(data, (bool)))) revert ApproveFailed();
    }

    /// @dev Reset router->target allowance to 0. Tolerate failures.
    function _resetAllowance(address target) internal {
        (bool ok, ) = NORML_TOKEN.call(
            abi.encodeWithSelector(IERC20.approve.selector, target, uint256(0))
        );
        ok; // silence unused warning
    }

    /// @dev Zero-first-then-set exact allowance for USDT-style tokens.
    function _setExactAllowance(address target, uint256 amount) internal {
        _resetAllowance(target);
        _safeApprove(target, amount);
    }

    /// @dev Pull `amount` NORML from `user` to router, then set exact
    ///      allowance for `target`.
    function _pullAndApprove(address user, address target, uint256 amount) internal {
        if (amount == 0) revert ZeroAmount();
        _safeTransferFrom(user, address(this), amount);
        _setExactAllowance(target, amount);
    }

    // ---------------------------------------------------------------------
    // NormlForUs (per-NFT staking)
    // ---------------------------------------------------------------------

    function stakeForUs(uint256 tokenId, uint256 amount) external nonReentrant {
        _pullAndApprove(msg.sender, NORML_FOR_US, amount);
        INormlForUs(NORML_FOR_US).stakeFor(msg.sender, tokenId, amount);
        _resetAllowance(NORML_FOR_US);
    }

    function unstakeForUs(uint256 tokenId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        INormlForUs(NORML_FOR_US).unstakeFor(msg.sender, tokenId, amount);
    }

    // ---------------------------------------------------------------------
    // NormlForMe ("Normal 4 Me" NFT)
    // ---------------------------------------------------------------------

    /// @notice Mint a Normal 4 Me NFT through the router.
    /// @dev    `msg.value` must equal `NormlForMe.mintPrice()`. Caller must
    ///         have approved this router to spend `amount` NORML.
    function mintNormalForMe(uint256 amount)
        external
        payable
        nonReentrant
        returns (uint256 tokenId)
    {
        _pullAndApprove(msg.sender, NORML_FOR_ME, amount);
        tokenId = INormlForMe(NORML_FOR_ME).mintFor{value: msg.value}(
            msg.sender,
            amount
        );
        _resetAllowance(NORML_FOR_ME);
    }

    /// @notice Add more NORML to an existing Normal 4 Me NFT through the router.
    function addToNormalForMe(uint256 tokenId, uint256 amount) external nonReentrant {
        _pullAndApprove(msg.sender, NORML_FOR_ME, amount);
        INormlForMe(NORML_FOR_ME).addTokensFor(msg.sender, tokenId, amount);
        _resetAllowance(NORML_FOR_ME);
    }

    /// @notice Burn a Normal 4 Me NFT and unlock its NORML through the router.
    function burnAndUnlockNormalForMe(uint256 tokenId) external nonReentrant {
        INormlForMe(NORML_FOR_ME).burnAndUnlockFor(msg.sender, tokenId);
    }

    // ---------------------------------------------------------------------
    // Norml8 / Bidders Edition
    // ---------------------------------------------------------------------
    // Bidders Edition is owner-airdropped — no router entry point.


    // ---------------------------------------------------------------------
    // Hardening
    // ---------------------------------------------------------------------

    /// @dev Accept ETH only as part of in-flight payable router calls. Reject
    ///      bare sends.
    receive() external payable { revert(); }
    fallback() external payable { revert(); }
}
