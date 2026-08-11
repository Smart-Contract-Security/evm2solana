// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";

/**
 * @title  IAccessPredicate
 * @notice Inlined from ERC-8257 reference. Defined here at 0.8.17 instead
 *         of importing 0.8.24-pragma'd upstream to keep the repo single-version
 *         alongside SeaDrop (which pins 0.8.17). Wire-compatible with the
 *         canonical interface.
 */
interface IAccessPredicate {
    struct AccessRequirement {
        bytes4 kind;
        bytes data;
        string label;
    }

    enum RequirementLogic { AND, OR }

    function hasAccess(uint256 toolId, address account, bytes calldata data)
        external view returns (bool);

    function name() external view returns (string memory);

    function getRequirements(uint256 toolId)
        external view
        returns (AccessRequirement[] memory requirements, RequirementLogic logic);
}

/**
 * @title  WancaiHolderPredicate
 * @notice ERC-8257 access predicate that gates a tool to wallets holding
 *         at least `minBalance` WANCAI 万财 NFTs.
 *
 *  Registry: 0x265BB2DBFC0A8165C9A1941Eb1372F349baD2cf1 (Ethereum mainnet + Base)
 *
 *  Usage:
 *   1. Deploy this contract with (wancaiAddress, 1)
 *   2. Register the tool on ToolRegistry with `accessPredicate = address(this)`
 *   3. Agents call ToolRegistry.hasAccess(toolId, account) which forwards here
 *
 *  The predicate is `view`-only and stateless beyond its immutable config —
 *  cheap to call, safe to call from any context.
 */
contract WancaiHolderPredicate is IAccessPredicate {
    /// @notice WANCAI NFT contract being gated against.
    IERC721 public immutable wancai;

    /// @notice Minimum WANCAI balance required for access.
    uint256 public immutable minBalance;

    /// @notice ERC-165-style kind identifier for ERC-721 ownership predicates.
    bytes4 public constant KIND = bytes4(keccak256("erc721:owner"));

    constructor(address wancai_, uint256 minBalance_) {
        require(wancai_ != address(0), "WancaiHolderPredicate: zero address");
        wancai = IERC721(wancai_);
        minBalance = minBalance_ == 0 ? 1 : minBalance_;
    }

    /**
     * @inheritdoc IAccessPredicate
     * @dev `toolId` and `data` are unused — this predicate is bound to a single
     *      collection set at construction. Per-tool overrides not supported by
     *      design; deploy separate predicate instances if needed.
     */
    function hasAccess(uint256 /* toolId */, address account, bytes calldata /* data */)
        external view override returns (bool)
    {
        return wancai.balanceOf(account) >= minBalance;
    }

    function name() external pure override returns (string memory) {
        return "WANCAI Holder Predicate";
    }

    function getRequirements(uint256 /* toolId */)
        external view override
        returns (AccessRequirement[] memory requirements, RequirementLogic logic)
    {
        requirements = new AccessRequirement[](1);
        requirements[0] = AccessRequirement({
            kind: KIND,
            data: abi.encode(address(wancai), minBalance),
            label: string.concat(
                "Hold at least ",
                _toString(minBalance),
                " WANCAI NFT(s)"
            )
        });
        logic = RequirementLogic.AND;
    }

    // ERC-165 (optional per ERC-8257, but a good signal for indexers)
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IAccessPredicate).interfaceId
            || interfaceId == 0x01ffc9a7; // ERC-165 itself
    }

    function _toString(uint256 v) private pure returns (string memory) {
        if (v == 0) return "0";
        uint256 temp = v;
        uint256 digits;
        while (temp != 0) { digits++; temp /= 10; }
        bytes memory buf = new bytes(digits);
        while (v != 0) {
            digits -= 1;
            buf[digits] = bytes1(uint8(48 + uint256(v % 10)));
            v /= 10;
        }
        return string(buf);
    }
}
