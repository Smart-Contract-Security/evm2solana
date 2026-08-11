// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "./Transferer.sol";
import "./OwnerHinkal.sol";
import "./types/CircomData.sol";
import "./types/Dimensions.sol";
import "./types/IHinkal.sol";
import "./types/StealthAddressStructure.sol";

/// @title HinkalWrapper
/// @notice Wrapper contract that captures transaction context (sender and ETH value) before delegatecall
/// @dev This allows external actions to access the original msg.sender and msg.value even after delegatecall
contract HinkalWrapper is Transferer, OwnerHinkal {
    address internal sender;
    uint256 internal ethAmount;
    address internal hinkal;

    constructor(address _hinkal) {
        require(
            _hinkal != address(0),
            "HinkalWrapper: Invalid Hinkal address"
        );
        hinkal = _hinkal;
    }

    receive() external payable {}

    function transact(
        uint[2] calldata a,
        uint[2][2] calldata b,
        uint[2] calldata c,
        Dimensions calldata dimensions,
        CircomData calldata circomData
    ) external payable {
        sender = msg.sender;
        ethAmount = msg.value;

        IHinkal(hinkal).transact(a, b, c, dimensions, circomData);

        sender = address(0);
    }

    function getEth() external returns (uint256) {
        uint256 amount = ethAmount;
        if (amount > 0) {
            ethAmount = 0; // Clear before transfer to prevent reentrancy
            transferETH(msg.sender, amount);
        }
        return amount;
    }

    function getSender() external view returns (address) {
        return sender;
    }

    function setHinkalAddress(address _hinkal) external onlyOwner {
        require(
            _hinkal != address(0),
            "HinkalWrapper: Invalid Hinkal address"
        );
        hinkal = _hinkal;
    }

    function prooflessDeposit(
        address feeRecipient,
        address feeToken,
        uint256 feeAmount,
        address[] calldata erc20Addresses,
        uint256[] calldata amounts,
        uint256[] calldata tokenIds,
        StealthAddressStructure[] calldata stealthAddressStructures
    ) external payable {
        require(
            erc20Addresses.length == amounts.length &&
                erc20Addresses.length == tokenIds.length &&
                erc20Addresses.length == stealthAddressStructures.length,
            "length mismatch"
        );
        uint256 ethForHinkal = _settleFee(feeRecipient, feeToken, feeAmount);
        _pullAndApproveDepositTokens(erc20Addresses, amounts);
        IHinkal(hinkal).prooflessDeposit{value: ethForHinkal}(erc20Addresses, amounts, tokenIds, stealthAddressStructures);
    }

    function _settleFee(address feeRecipient, address feeToken, uint256 feeAmount) internal returns (uint256 ethForHinkal) {
        ethForHinkal = msg.value;
        if (feeToken == address(0)) {
            require(msg.value >= feeAmount, "insufficient ETH for fee");
            ethForHinkal = msg.value - feeAmount;
            if (feeAmount > 0) transferETH(feeRecipient, feeAmount);
        } else if (feeAmount > 0) {
            transferERC20TokenFrom(feeToken, msg.sender, feeRecipient, feeAmount);
        }
    }

    function _pullAndApproveDepositTokens(address[] calldata erc20Addresses, uint256[] calldata amounts) internal {
        uint256 len = erc20Addresses.length;
        address[] memory uniqueTokens = new address[](len);
        uint256[] memory uniqueAmounts = new uint256[](len);
        uint256 uniqueCount;

        for (uint256 i = 0; i < len; i++) {
            address token = erc20Addresses[i];
            if (token == address(0) || amounts[i] == 0) continue;

            transferERC20TokenFrom(token, msg.sender, address(this), amounts[i]);

            uint256 idx = uniqueCount;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (uniqueTokens[j] == token) { idx = j; break; }
            }
            if (idx == uniqueCount) {
                uniqueTokens[uniqueCount] = token;
                uniqueCount++;
            }
            uniqueAmounts[idx] += amounts[i];
        }

        for (uint256 k = 0; k < uniqueCount; k++) {
            approveERC20Token(uniqueTokens[k], hinkal, uniqueAmounts[k]);
        }
    }

}

