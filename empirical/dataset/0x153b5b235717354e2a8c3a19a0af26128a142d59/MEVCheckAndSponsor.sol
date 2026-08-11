//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
pragma experimental ABIEncoderV2;

// This contract performs checks on sponsoring amount, executor address, and pays coinbase
contract MEVCheckAndSponsor {
    error NotEnoughFundsToSponsor();
    error InvalidAddress();
    error FailedToSponsor();
    error OutDatedTargetBlock();

    function checkNativeTxsAndSend(
        address[] calldata _executors,
        uint256[] calldata _gasUnitsToFunds,
        uint256[] calldata _prefunds,
        uint256 targetedBlock
    ) external payable {
        require(
            _executors.length == _gasUnitsToFunds.length && _executors.length == _prefunds.length,
            "executors and gas units must be the same length"
        );

        uint256 leftover = msg.value;
        for (uint256 i = 0; i < _executors.length; i++) {
            uint256 spent = _checkNativeTxAndSend(
                _executors[i],
                _gasUnitsToFunds[i],
                _prefunds[i],
                targetedBlock
            );
            leftover = leftover - spent;
        }

        block.coinbase.call{value: leftover}(new bytes(0));
    }

    function checkNativeTxAndSend(
        address _executor,
        uint256 _gasUnitsToFund,
        uint256 _prefund,
        uint256 targetedBlock
    ) external payable {
        uint256 leftover = msg.value;
        uint256 spent = _checkNativeTxAndSend(
            _executor,
            _gasUnitsToFund,
            _prefund,
            targetedBlock
        );
        leftover = leftover - spent;
        block.coinbase.call{value: leftover}(new bytes(0));
    }

    function _checkNativeTxAndSend(
        address _executor,
        uint256 _gasUnitsToFund,
        uint256 _prefund,
        uint256 targetedBlock
    ) internal returns (uint256 transferedAmount) {
        if (_executor == address(0)) {
            revert InvalidAddress();
        }

        if (targetedBlock < block.number) {
            revert OutDatedTargetBlock();
        }

        transferedAmount = (_gasUnitsToFund * block.basefee) + _prefund;

        (bool success, ) = payable(_executor).call{value: transferedAmount}("");

        if (!success) {
            revert FailedToSponsor();
        }
    }
}