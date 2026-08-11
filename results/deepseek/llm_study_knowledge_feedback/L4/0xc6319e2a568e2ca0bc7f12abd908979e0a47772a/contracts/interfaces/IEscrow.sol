// SPDX-License-Identifier: MIT

import 'solana';

interface IEscrow {
    enum EscrowStatuses {
        Launched,
        Pending,
        Partial,
        Paid,
        Complete,
        Cancelled,
        ToCancel
    }

    function status() external view returns (EscrowStatuses);

    function setup(
        address _reputationOracle,
        address _recordingOracle,
        address _exchangeOracle,
        string calldata _manifest,
        string calldata _manifestHash
    ) external;

    function requestCancellation() external;

    function withdraw(address _token) external;

    function complete() external;

    function cancel() external;

    function storeResults(string calldata _url, string calldata _hash) external;

    function storeResults(
        string calldata _url,
        string calldata _hash,
        uint64 _fundsToReserve
    ) external;

    function bulkPayOut(
        address[] calldata _recipients,
        uint64[] calldata _amounts,
        string calldata _url,
        string calldata _hash,
        uint64 _txId,
        bool forceComplete
    ) external;

    function bulkPayOut(
        address[] calldata _recipients,
        uint64[] calldata _amounts,
        string calldata _url,
        string calldata _hash,
        string calldata _payoutId,
        bool forceComplete
    ) external;
}