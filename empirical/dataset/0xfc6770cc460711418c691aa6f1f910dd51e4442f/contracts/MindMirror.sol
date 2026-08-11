// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC721} from "./solady/tokens/ERC721.sol";
import {Ownable} from "./solady/auth/Ownable.sol";
import {MindArt} from "./MindArt.sol";

interface IMindHook {
    function handleNFTTransfer(address from, address to, uint256 id, address operator) external;
    function handleNFTApprove(address owner, uint256 id, address operator) external;
    function handleNFTSetApprovalForAll(address owner, bool approved, address operator) external;
    function seedOf(uint256 id) external view returns (bytes32);
}

/// @title MindMirror
/// @notice ERC-721 mirror NFTs with on-chain smiley SVG.
contract MindMirror is ERC721, Ownable {
    error MirrorOnly();
    error HookZero();

    IMindHook public immutable hook;

    string private _name = "Nevermind Face";
    string private _symbol = "FACE";

    constructor(address owner_, address hook_) {
        if (hook_ == address(0)) revert HookZero();
        _initializeOwner(owner_);
        hook = IMindHook(hook_);
    }

    modifier onlyHook() {
        if (msg.sender != address(hook)) revert MirrorOnly();
        _;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (_ownerOf(id) == address(0)) revert MirrorOnly();
        return MindArt.tokenURI(hook.seedOf(id), id);
    }

    function mint(address to, uint256 id) external onlyHook {
        _mint(to, id);
    }

    function burn(uint256 id) external onlyHook {
        _burn(id);
    }

    function _beforeTokenTransfer(address from, address to, uint256 id) internal override {
        super._beforeTokenTransfer(from, to, id);
        if (from != address(0) && to != address(0)) {
            hook.handleNFTTransfer(from, to, id, msg.sender);
        }
    }

    function approve(address spender, uint256 id) public payable override {
        address owner = ownerOf(id);
        super.approve(spender, id);
        hook.handleNFTApprove(owner, id, spender);
    }

    function setApprovalForAll(address operator, bool approved) public override {
        super.setApprovalForAll(operator, approved);
        hook.handleNFTSetApprovalForAll(msg.sender, approved, operator);
    }
}
