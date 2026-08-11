//SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "Solady/utils/SSTORE2.sol";
import "./utils/JSON.sol";

import "./utils/baseSVG.sol";
import "./utils/ebisu.sol";

import "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {ITroveManager} from "../Interfaces/ITroveManager.sol";

interface IMetadataNFT {
    struct TroveData {
        uint256 _tokenId;
        address _owner;
        address _collToken;
        address _boldToken;
        uint256 _collAmount;
        uint256 _debtAmount;
        uint256 _interestRate;
        ITroveManager.Status _status;
    }

    function uri(TroveData memory _troveData) external view returns (string memory);
}

contract MetadataNFT is IMetadataNFT {
    FixedAssetReader public immutable mainAssetReader;
    FixedAssetReader public immutable heroAssetReader;

    constructor(FixedAssetReader _mainAssetReader, FixedAssetReader _heroAssetReader) {
        mainAssetReader = _mainAssetReader;
        heroAssetReader = _heroAssetReader;
    }

    function uri(TroveData memory _troveData) public view returns (string memory) {
        string memory attr = attributes(_troveData);
        return json.formattedMetadata(
            string.concat("Ebisu Money - ", IERC20Metadata(_troveData._collToken).name()),
            string.concat(
                "Ebisu Money is a collateralized debt platform. Users can lock up ",
                IERC20Metadata(_troveData._collToken).symbol(),
                " to issue stablecoin tokens (ebUSD) to their own Ethereum address. The individual collateralized debt positions are called Troves, and are represented as NFTs."
            ),
            renderSVGImage(_troveData),
            attr
        );
    }

    function renderSVGImage(TroveData memory _troveData) internal view returns (string memory) {
        return svg._svg(
            baseSVG._svgProps(),
            string.concat(
                baseSVG._baseElements(mainAssetReader),
                ebisuSVG._hero(_troveData._tokenId, heroAssetReader),
                dynamicTextComponents(_troveData)
            )
        );
    }

    function attributes(TroveData memory _troveData) public pure returns (string memory) {
        //include: collateral token address, collateral amount, debt token address, debt amount, interest rate, status
        return string.concat(
            '[{"trait_type": "Collateral Token", "value": "',
            LibString.toHexString(_troveData._collToken),
            '"}, {"trait_type": "Collateral Amount", "value": "',
            LibString.toString(_troveData._collAmount),
            '"}, {"trait_type": "Debt Token", "value": "',
            LibString.toHexString(_troveData._boldToken),
            '"}, {"trait_type": "Debt Amount", "value": "',
            LibString.toString(_troveData._debtAmount),
            '"}, {"trait_type": "Interest Rate", "value": "',
            LibString.toString(_troveData._interestRate),
            '"}, {"trait_type": "Status", "value": "',
            _status2Str(_troveData._status),
            '"} ]'
        );
    }

    function dynamicTextComponents(TroveData memory _troveData) public view returns (string memory) {
        string memory id = LibString.toHexString(_troveData._tokenId);
        id = string.concat(LibString.slice(id, 0, 6), "...", LibString.slice(id, 38, 42));

        uint8 collDecimals = IERC20Metadata(_troveData._collToken).decimals();

        return string.concat(
            baseSVG._formattedIdEl(id),
            baseSVG._formattedAddressEl(_troveData._owner),
            baseSVG._collLogo("COLLATERAL", mainAssetReader),
            baseSVG._statusEl(_status2Str(_troveData._status)),
            baseSVG._dynamicTextEls(_troveData._debtAmount, _troveData._collAmount, _troveData._interestRate, collDecimals)
        );
    }

    function _status2Str(ITroveManager.Status status) internal pure returns (string memory) {
        if (status == ITroveManager.Status.active) return "Active";
        if (status == ITroveManager.Status.closedByOwner) return "Closed";
        if (status == ITroveManager.Status.closedByLiquidation) return "Liquidated";
        if (status == ITroveManager.Status.zombie) return "Below Min Debt";
        return "";
    }
}
