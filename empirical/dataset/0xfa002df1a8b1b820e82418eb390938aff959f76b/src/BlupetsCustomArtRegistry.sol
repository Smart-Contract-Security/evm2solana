// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IBlupetsCore} from "./IBlupetsCore.sol";
import {IBlupetsCustomArtRegistry} from "./IBlupetsCustomArtRegistry.sol";

contract BlupetsCustomArtRegistry is IBlupetsCustomArtRegistry {
    uint8 public constant STAGE_T4 = 4;
    uint8 public constant FLAG_CUSTOM_HATCH = 1;

    struct CustomArt {
        bool active;
        bytes32 artKey;
        string lineage;
        string form;
    }

    IBlupetsCore public immutable core;
    address public owner;
    mapping(address => bool) public artManagers;
    mapping(uint256 => CustomArt) private _customArt;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event ArtManagerUpdated(address indexed manager, bool allowed);
    event CustomArtSet(uint256 indexed tokenId, bytes32 indexed artKey, string lineage, string form);

    error NotOwner();
    error NotArtManager();
    error NotEligibleCustomHatch();
    error InvalidOwner();
    error InvalidCore();

    constructor(address core_) {
        if (core_ == address(0)) revert InvalidCore();
        core = IBlupetsCore(core_);
        owner = msg.sender;
        artManagers[msg.sender] = true;
        emit OwnershipTransferred(address(0), msg.sender);
        emit ArtManagerUpdated(msg.sender, true);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyArtManager() {
        if (!artManagers[msg.sender]) revert NotArtManager();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidOwner();
        owner = newOwner;
        emit OwnershipTransferred(msg.sender, newOwner);
    }

    function setArtManager(address manager, bool allowed) external onlyOwner {
        artManagers[manager] = allowed;
        emit ArtManagerUpdated(manager, allowed);
    }

    function setCustomArt(uint256 tokenId, bytes32 artKey, string calldata lineage, string calldata form)
        external
        onlyArtManager
    {
        IBlupetsCore.TokenState memory state = core.tokenState(tokenId);
        if (state.stage != STAGE_T4 || (state.flags & FLAG_CUSTOM_HATCH) == 0) revert NotEligibleCustomHatch();

        _customArt[tokenId] = CustomArt({active: true, artKey: artKey, lineage: lineage, form: form});
        core.notifyMetadataUpdate(tokenId);
        emit CustomArtSet(tokenId, artKey, lineage, form);
    }

    function customArt(uint256 tokenId)
        external
        view
        returns (bool active, bytes32 artKey, string memory lineage, string memory form)
    {
        CustomArt storage art = _customArt[tokenId];
        return (art.active, art.artKey, art.lineage, art.form);
    }
}
