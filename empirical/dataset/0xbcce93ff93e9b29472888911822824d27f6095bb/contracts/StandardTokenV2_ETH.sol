// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";

/**
 * @title StandardTokenV2
 * @dev Standard ERC-20 token with fixed supply, immutable on-chain metadata,
 *      ERC-2612 permit, burn, and ERC-165. No admin, no owner, no fees,
 *      no blacklist, no mint after deployment. All metadata is set at
 *      deployment and can never be changed.
 */
contract StandardTokenV2_ETH is ERC20, ERC20Burnable, ERC20Permit, IERC165 {
    uint256 public constant MAX_SUPPLY = 1_000_000_000_000 * 10 ** 18;

    address private immutable _creator;
    string private _image;
    string private _description;
    string private _website;
    string private _twitter;
    string private _telegram;
    string private _discord;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 supply_,
        address initialHolder_,
        address creator_,
        string memory image_,
        string memory description_,
        string memory website_,
        string memory twitter_,
        string memory telegram_,
        string memory discord_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        require(initialHolder_ != address(0), "ERC20: zero address");
        require(supply_ > 0, "ERC20: supply must be > 0");
        require(supply_ <= MAX_SUPPLY, "ERC20: supply exceeds max");
        _creator = creator_;
        _image = image_;
        _description = description_;
        _website = website_;
        _twitter = twitter_;
        _telegram = telegram_;
        _discord = discord_;
        _mint(initialHolder_, supply_);
    }

    // ──────────────────── Views ──────────────────────────────────

    function creator() external view returns (address) {
        return _creator;
    }

    function imageUrl() external view returns (string memory) {
        return _image;
    }

    function description() external view returns (string memory) {
        return _description;
    }

    function website() external view returns (string memory) {
        return _website;
    }

    function twitter() external view returns (string memory) {
        return _twitter;
    }

    function telegram() external view returns (string memory) {
        return _telegram;
    }

    function discord() external view returns (string memory) {
        return _discord;
    }

    function allData()
        external
        view
        returns (
            address creator_,
            string memory image,
            string memory desc,
            string memory web,
            string memory twit,
            string memory tg,
            string memory disc
        )
    {
        return (_creator, _image, _description, _website, _twitter, _telegram, _discord);
    }

    // ──────────────────── ERC-165 ────────────────────────────────

    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC20).interfaceId;
    }
}
