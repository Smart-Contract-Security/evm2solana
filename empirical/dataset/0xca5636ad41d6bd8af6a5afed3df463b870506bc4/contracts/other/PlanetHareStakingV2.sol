// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";

contract PlanetHareStakingV2 is Ownable {

    uint256 public lockPeriod = 300;
    address public haresAddress;

    struct Staking {
        uint256 tokenID;
        address owner;
        uint256 releaseAfter;
    }

    uint256 public id;
    mapping(uint256 => Staking) public stakings;
    mapping(address => uint256) public count;

    event Stake(uint256 indexed id, uint256 tokenID, address owner, uint256 releaseAfter);
    event Redeem(uint256 indexed id);

    constructor (address _haresAddress) {
        require(_haresAddress != address(0), "Invalid address");
        haresAddress = _haresAddress;
    }

    function setHaresAddress(address _haresAddress) public onlyOwner {
        haresAddress = _haresAddress;
    }

    function setLockPeriod(uint256 _period) public onlyOwner {
        lockPeriod = _period;
    }

    function stake(uint256[] memory _tokenIDs) public {
        require(count[msg.sender] + _tokenIDs.length <= 24, "Staking up to 24");

        IERC721 hares = IERC721(haresAddress);

        for (uint256 i = 0; i < _tokenIDs.length; i++) {

            hares.transferFrom(msg.sender, address(this), _tokenIDs[i]);

            uint256 releaseAfter = block.timestamp + lockPeriod;

            stakings[id] = Staking(_tokenIDs[i], msg.sender, releaseAfter);
            emit Stake(id, _tokenIDs[i], msg.sender, releaseAfter);
            id++;
        }
        count[msg.sender] += _tokenIDs.length;
    }

    function redeem(uint256[] memory _ids) public {
        IERC721 hares = IERC721(haresAddress);
        
        for (uint256 i = 0; i < _ids.length; i++) {
            uint256 _id = _ids[i];

            Staking storage staking = stakings[_id];
            require(staking.owner == msg.sender, "Not owner");
            require(staking.releaseAfter < block.timestamp, "Locked");

            hares.transferFrom(address(this), msg.sender, staking.tokenID);

            delete stakings[_id];
            emit Redeem(_id);
        }
        count[msg.sender] -= _ids.length;
    }
}