// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./base64.sol";
import "./LibString.sol";
import "@openzeppelin/contracts@5.0.2/access/Ownable.sol";

interface IVessel {
    function craftToPayload(uint _tokenId) external view returns (bytes memory);
}

interface ISVG {
    function svg() external view returns (string memory);
}

interface IDriftHtml {
    function renderHTML(uint _craftStorage) external view returns (string memory);
}

contract The_Long_Drift_renderer is Ownable {

    IVessel public vessel;
    ISVG public svg;
    IDriftHtml public driftHtml;

    uint public craftStorage        = 2140;

    string public title             = "The Long Drift";
    string public artistName        = "dav";
    string public description       = "Sequence 007";
    string public storageType       = "Fully On-Chain";
    string public medium            = "Music";
    string public sequence          = "007";

    mapping (uint => uint) public noteToCraft;

    constructor() 
        Ownable(msg.sender)
    {
        vessel = IVessel(0xECb92Cc7112b80A2234936315BbB493fb48d1463);
        svg = ISVG(0xD949CBf06A329542769dF0B0EC25d104CF4F7b9a);
        driftHtml = IDriftHtml(0xdE70c0e9C88926aEA8165E8161F158967e63D16B);
    }

    function generateTraits() public view returns (string memory) {

        string memory traits = string(abi.encodePacked(
            '{"trait_type": "Artist", "value": "',
            artistName,
            '"}, ',
            '{"trait_type": "Storage", "value": "',
            storageType,
            '"}, ',
            '{"trait_type": "Sequence", "value": "',
            sequence,
            '"}, ',
            '{"trait_type": "Medium", "value": "',
            medium,
            '"}'
        ));
        return traits;
    }

    function uri(uint _tokenId) public view returns (string memory) {

            string memory json = Base64.encode(
                bytes(
                    string(
                        abi.encodePacked(
                            '{"name":"', title,
                            '","image": "data:image/svg+xml;base64,', getImage(),
                            '","animation_url":"data:text/html;base64,', 
                            Base64.encode(bytes(getHtml())),
                            '","description":"', description,
                            '","attributes": [', generateTraits(), ']}'
                        )
                    )
                )
            );
            return string(abi.encodePacked("data:application/json;base64,", json));

    }

    function getHtml() public view returns (string memory htmlCode) {
        return driftHtml.renderHTML(craftStorage);
    }

    function getImage() public view returns (string memory) {
        return svg.svg();
    }

    function setCraftStorage(uint _craft) public onlyOwner {
        craftStorage = _craft;
    }

    function setSVG(address _a) public onlyOwner {
        svg = ISVG(_a);
    }

    function setHTML(address _a) public onlyOwner {
        driftHtml = IDriftHtml(_a);
    }

}
