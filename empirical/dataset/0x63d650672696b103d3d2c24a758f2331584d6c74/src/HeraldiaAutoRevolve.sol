// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { OwnableBasic } from "@limitbreak/creator-token-standards/src/access/OwnableBasic.sol";
import { Heraldia } from "./Heraldia.sol";

contract HeraldiaAutoRevolve is OwnableBasic {

    error NotTokenOwner();
    error InvalidInterval();
    error AutoRevolveNotEnabled();

    event AutoRevolveEnabled(
        uint256 indexed tokenId,
        address indexed wallet,
        uint256 intervalSeconds,
        uint256 startedAt
    );
    event AutoRevolveDisabled(uint256 indexed tokenId);

    enum RevolveInterval {
        Daily,        // 0 → 86400
        Every3Days,   // 1 → 259200
        Every5Days,   // 2 → 432000
        Weekly,       // 3 → 604800
        Monthly,      // 4 → 2592000
        FiveMinutes   // 5 → 300 (owner only)
    }

    struct RevolveConfig {
        bool            enabled;
        address         wallet;
        RevolveInterval interval;
        uint256         intervalSeconds;
        uint256         startedAt;
    }

    Heraldia public heraldiaContract;

    mapping(uint256 => RevolveConfig) private _configs;

    constructor(Heraldia _heraldia) OwnableBasic() {
        heraldiaContract = _heraldia;
    }

    function enableAutoRevolve(uint256 tokenId, RevolveInterval interval) external {
        if (heraldiaContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (interval == RevolveInterval.FiveMinutes && msg.sender != owner()) revert InvalidInterval();

        uint256 intervalSecs = _intervalToSeconds(interval);

        _configs[tokenId] = RevolveConfig({
            enabled:         true,
            wallet:          msg.sender,
            interval:        interval,
            intervalSeconds: intervalSecs,
            startedAt:       block.timestamp
        });

        emit AutoRevolveEnabled(tokenId, msg.sender, intervalSecs, block.timestamp);
    }

    function disableAutoRevolve(uint256 tokenId) external {
        if (heraldiaContract.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        delete _configs[tokenId];
        emit AutoRevolveDisabled(tokenId);
    }

    function adminDisable(uint256 tokenId) external onlyOwner {
        delete _configs[tokenId];
        emit AutoRevolveDisabled(tokenId);
    }

    function setHeraldiaContract(address _heraldia) external onlyOwner {
        heraldiaContract = Heraldia(_heraldia);
    }

    function getConfig(uint256 tokenId) external view returns (RevolveConfig memory) {
        return _configs[tokenId];
    }

    function computeHash(uint256 tokenId) external view returns (bytes32) {
        RevolveConfig memory cfg = _configs[tokenId];
        if (!cfg.enabled) revert AutoRevolveNotEnabled();
        address currentOwner = heraldiaContract.ownerOf(tokenId);
        if (cfg.wallet != currentOwner) revert AutoRevolveNotEnabled();
        uint256 rotations = (block.timestamp - cfg.startedAt) / cfg.intervalSeconds;
        return keccak256(abi.encodePacked(cfg.wallet, tokenId, rotations));
    }

    function currentRotation(uint256 tokenId) external view returns (uint256) {
        RevolveConfig memory cfg = _configs[tokenId];
        if (!cfg.enabled) revert AutoRevolveNotEnabled();
        return (block.timestamp - cfg.startedAt) / cfg.intervalSeconds;
    }

    function _intervalToSeconds(RevolveInterval interval) internal pure returns (uint256) {
        if (interval == RevolveInterval.Daily)        return 86400;
        if (interval == RevolveInterval.Every3Days)   return 259200;
        if (interval == RevolveInterval.Every5Days)   return 432000;
        if (interval == RevolveInterval.Weekly)       return 604800;
        if (interval == RevolveInterval.Monthly)      return 2592000;
        if (interval == RevolveInterval.FiveMinutes)  return 300;
        revert InvalidInterval();
    }
}
