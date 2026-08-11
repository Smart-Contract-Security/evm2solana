// SPDX-License-Identifier: MIT

import 'solana';

interface IKVStore {
    function get(
        address _account,
        string memory _key
    ) external view returns (string memory);
}

enum EscrowStatuses {
    Launched,
    Pending,
    Partial,
    Paid,
    Complete,
    Cancelled,
    ToCancel
}

interface IEscrow {
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
    function cancel() external;
    function complete() external;
    function storeResults(
        string calldata _url,
        string calldata _hash
    ) external;
    function storeResultsV2(
        string calldata _url,
        string calldata _hash,
        uint256 _fundsToReserve
    ) external;
    function bulkPayOut(
        address[] calldata _recipients,
        uint256[] calldata _amounts,
        string calldata _url,
        string calldata _hash,
        uint256 _txId,
        bool forceComplete
    ) external;
    function bulkPayOutV2(
        address[] calldata _recipients,
        uint256[] calldata _amounts,
        string calldata _url,
        string calldata _hash,
        string calldata _payoutId,
        bool forceComplete
    ) external;
}

contract Escrow is IEscrow {
    string private constant ERROR_ZERO_ADDRESS = 'Zero address';
    string private constant FEE_KEY = 'fee';
    uint8 private constant MAX_ORACLE_FEE = 25;
    uint32 private constant BULK_MAX_COUNT = 100;

    event IntermediateStorage(string url, string hash);
    event Pending(string manifest, string hash);
    event PendingV2(
        string manifest,
        string hash,
        address reputationOracle,
        address recordingOracle,
        address exchangeOracle
    );
    event PendingV3(
        string manifest,
        string hash,
        address reputationOracle,
        address recordingOracle,
        address exchangeOracle,
        uint8 reputationOracleFeePercentage,
        uint8 recordingOracleFeePercentage,
        uint8 exchangeOracleFeePercentage
    );
    event BulkTransfer(
        uint256 txId,
        address[] recipients,
        uint256[] amounts,
        bool isPartial
    );
    event BulkTransferV2(
        uint256 txId,
        address[] recipients,
        uint256[] amounts,
        bool isPartial,
        string finalResultsUrl
    );
    event BulkTransferV3(
        bytes32 payoutId,
        address[] recipients,
        uint256[] amounts,
        bool isPartial,
        string finalResultsUrl,
        string finalResultsHash
    );
    event Cancelled();
    event Completed();
    event Fund(uint256 amount);
    event Withdraw(address token, uint256 amount);
    event CancellationRequested();
    event CancellationRefund(uint256 amount);
    event OracleFeeTransfer(address[] oracles, uint256[] amounts);

    EscrowStatuses public override status;

    address public reputationOracle;
    address public recordingOracle;
    address public exchangeOracle;

    address public launcher;
    address public admin;
    address public escrowFactory;
    address public token;
    address public kvstore;

    uint8 public reputationOracleFeePercentage;
    uint8 public recordingOracleFeePercentage;
    uint8 public exchangeOracleFeePercentage;

    string public manifest;
    string public manifestHash;
    string public intermediateResultsUrl;
    string public intermediateResultsHash;
    string public finalResultsUrl;
    string public finalResultsHash;

    uint256 public duration;
    mapping(bytes32 => bool) private payouts;
    uint256 public fundAmount;
    uint256 public remainingFunds;
    uint256 public reservedFunds;

    bool private locked;

    modifier nonReentrant() {
        require(!locked, 'Reentrant call');
        locked = true;
        _;
        locked = false;
    }

    @payer(payer)
    @space(512 + 32 * 1024)
    constructor(
        address _token,
        address _launcher,
        address _admin,
        uint256 _duration,
        address _kvstore
    ) {
        require(_launcher != address(0), ERROR_ZERO_ADDRESS);
        require(_admin != address(0), ERROR_ZERO_ADDRESS);
        require(_token != address(0), ERROR_ZERO_ADDRESS);
        require(_kvstore != address(0), ERROR_ZERO_ADDRESS);
        require(_duration > 0, 'Duration is 0');

        token = _token;
        launcher = _launcher;
        admin = _admin;
        kvstore = _kvstore;
        escrowFactory = tx.accounts.dataAccount.key;

        status = EscrowStatuses.Launched;
        duration = _duration + block.timestamp;
    }

    function getBalance() public view returns (uint256) {
        return getTokenBalance(token);
    }

    function getTokenBalance(address _token) public view returns (uint256) {
        AccountInfo account = tx.accounts.tokens[_token];
        return account.lamports;
    }

    function setup(
        address _reputationOracle,
        address _recordingOracle,
        address _exchangeOracle,
        string calldata _manifest,
        string calldata _manifestHash
    ) external override adminLauncherOrFactory notExpired {
        require(_reputationOracle != address(0), 'Invalid reputation oracle');
        require(_recordingOracle != address(0), 'Invalid recording oracle');
        require(_exchangeOracle != address(0), 'Invalid exchange oracle');

        uint8 _reputationOracleFeePercentage = _getOracleFee(_reputationOracle);
        uint8 _recordingOracleFeePercentage = _getOracleFee(_recordingOracle);
        uint8 _exchangeOracleFeePercentage = _getOracleFee(_exchangeOracle);

        require(status == EscrowStatuses.Launched, 'Wrong status');

        reputationOracle = _reputationOracle;
        recordingOracle = _recordingOracle;
        exchangeOracle = _exchangeOracle;

        reputationOracleFeePercentage = _reputationOracleFeePercentage;
        recordingOracleFeePercentage = _recordingOracleFeePercentage;
        exchangeOracleFeePercentage = _exchangeOracleFeePercentage;

        manifest = _manifest;
        manifestHash = _manifestHash;
        status = EscrowStatuses.Pending;

        uint256 balance = getBalance();
        require(balance > 0, 'Zero balance');

        fundAmount = balance;
        uint256 reputationOracleFee = (balance *
            _reputationOracleFeePercentage) / 100;
        uint256 recordingOracleFee = (balance * _recordingOracleFeePercentage) /
            100;
        uint256 exchangeOracleFee = (balance * _exchangeOracleFeePercentage) /
            100;
        remainingFunds =
            balance -
            reputationOracleFee -
            recordingOracleFee -
            exchangeOracleFee;

        emit PendingV3(
            _manifest,
            _manifestHash,
            _reputationOracle,
            _recordingOracle,
            _exchangeOracle,
            _reputationOracleFeePercentage,
            _recordingOracleFeePercentage,
            _exchangeOracleFeePercentage
        );
        emit Fund(balance);
    }

    function _getOracleFee(address _oracle) private view returns (uint8) {
        IKVStore kvstoreContract = IKVStore(kvstore);
        return _parseUint8(kvstoreContract.get{accounts: [tx.accounts.kvstore]}(_oracle, FEE_KEY));
    }

    function _parseUint8(string memory _value) private pure returns (uint8) {
        bytes memory valueBytes = bytes(_value);
        require(valueBytes.length > 0, 'Invalid oracle fee');

        uint256 parsedValue = 0;
        for (uint256 i = 0; i < valueBytes.length; i++) {
            uint8 c = uint8(valueBytes[i]);
            require(c >= 48 && c <= 57, 'Invalid oracle fee');
            parsedValue = parsedValue * 10 + (c - 48);
            require(parsedValue <= MAX_ORACLE_FEE, 'Percentage out of bounds');
        }

        return uint8(parsedValue);
    }

    function requestCancellation()
        external
        override
        adminOrLauncher
        nonReentrant
    {
        require(
            status != EscrowStatuses.ToCancel &&
                (remainingFunds != 0 || status == EscrowStatuses.Launched),
            'Invalid status'
        );

        EscrowStatuses previousStatus = status;
        status = EscrowStatuses.ToCancel;
        emit CancellationRequested();

        if (duration <= block.timestamp) {
            _finalize();
            return;
        }

        if (previousStatus == EscrowStatuses.Launched) {
            uint256 balance = getBalance();
            if (balance > 0) {
                _safeTransfer(token, launcher, balance);
            }
            status = EscrowStatuses.Cancelled;
            emit Cancelled();
        }
    }

    function withdraw(
        address _token
    ) external override adminOrLauncher nonReentrant {
        uint256 amount;
        if (_token == token) {
            uint256 balance = getBalance();
            uint256 lockedFunds = remainingFunds +
                ((fundAmount * reputationOracleFeePercentage) / 100) +
                ((fundAmount * recordingOracleFeePercentage) / 100) +
                ((fundAmount * exchangeOracleFeePercentage) / 100);
            require(balance > lockedFunds, 'No funds');
            amount = balance - lockedFunds;
        } else {
            amount = getTokenBalance(_token);
        }

        require(amount > 0, 'No funds');
        _safeTransfer(_token, tx.accounts.dataAccount.key, amount);

        emit Withdraw(_token, amount);
    }

    function cancel() external override notExpired adminOrReputationOracle {
        require(status == EscrowStatuses.ToCancel, 'Invalid status');
        require(reservedFunds == 0, 'Reserved funds');
        _finalize();
    }

    function complete() external override notExpired adminOrReputationOracle {
        require(
            status == EscrowStatuses.Paid ||
                status == EscrowStatuses.Partial ||
                (status == EscrowStatuses.Pending &&
                    bytes(intermediateResultsUrl).length > 0 &&
                    reservedFunds == 0),
            'Invalid status'
        );
        _finalize();
    }

    function _finalize() private {
        bool isCancellation = status == EscrowStatuses.ToCancel;
        uint256 _remainingFunds = remainingFunds;

        uint256 _reputationOracleFee = (fundAmount *
            reputationOracleFeePercentage) / 100;
        uint256 _recordingOracleFee = (fundAmount *
            recordingOracleFeePercentage) / 100;
        uint256 _exchangeOracleFee = (fundAmount *
            exchangeOracleFeePercentage) / 100;
        uint256 _totalOracleFee = _reputationOracleFee +
            _recordingOracleFee +
            _exchangeOracleFee;

        fundAmount = 0;
        remainingFunds = 0;
        reservedFunds = 0;

        if (bytes(intermediateResultsUrl).length != 0) {
            address[] memory oracles = new address[](3);
            uint256[] memory amounts = new uint256[](3);

            oracles[0] = reputationOracle;
            oracles[1] = recordingOracle;
            oracles[2] = exchangeOracle;
            amounts[0] = _reputationOracleFee;
            amounts[1] = _recordingOracleFee;
            amounts[2] = _exchangeOracleFee;

            if (_reputationOracleFee > 0) {
                _safeTransfer(token, reputationOracle, _reputationOracleFee);
            }
            if (_recordingOracleFee > 0) {
                _safeTransfer(token, recordingOracle, _recordingOracleFee);
            }
            if (_exchangeOracleFee > 0) {
                _safeTransfer(token, exchangeOracle, _exchangeOracleFee);
            }

            emit OracleFeeTransfer(oracles, amounts);
        } else {
            _remainingFunds += _totalOracleFee;
        }

        if (_remainingFunds > 0) {
            _safeTransfer(token, launcher, _remainingFunds);
            if (isCancellation) {
                emit CancellationRefund(_remainingFunds);
            }
        }

        if (isCancellation) {
            status = EscrowStatuses.Cancelled;
            emit Cancelled();
        } else {
            status = EscrowStatuses.Complete;
            emit Completed();
        }
    }

    function storeResults(
        string calldata _url,
        string calldata _hash
    ) external override adminOrRecordingOracle notExpired {
        require(false, 'DEPRECATED_SIGNATURE');
    }

    function storeResultsV2(
        string calldata _url,
        string calldata _hash,
        uint256 _fundsToReserve
    ) external override adminOrRecordingOracle notExpired {
        require(
            status == EscrowStatuses.Pending ||
                status == EscrowStatuses.Partial ||
                status == EscrowStatuses.ToCancel,
            'Invalid status'
        );
        if (_fundsToReserve > 0) {
            require(bytes(_url).length != 0, 'Empty URL');
            require(bytes(_hash).length != 0, 'Empty hash');
        }
        require(
            _fundsToReserve <= remainingFunds - reservedFunds,
            'Insufficient unreserved funds'
        );

        intermediateResultsUrl = _url;
        intermediateResultsHash = _hash;
        reservedFunds += _fundsToReserve;

        emit IntermediateStorage(_url, _hash);

        if (status == EscrowStatuses.ToCancel) {
            if (_fundsToReserve == 0) {
                _finalize();
                return;
            }

            uint256 unreservedFunds = remainingFunds - reservedFunds;
            if (unreservedFunds > 0) {
                _safeTransfer(token, launcher, unreservedFunds);
                emit CancellationRefund(unreservedFunds);
                remainingFunds = reservedFunds;
            }
        }
    }

    function bulkPayOut(
        address[] calldata _recipients,
        uint256[] calldata _amounts,
        string calldata _url,
        string calldata _hash,
        uint256 _txId,
        bool forceComplete
    ) external override {
        require(false, 'DEPRECATED_SIGNATURE');
    }

    function bulkPayOutV2(
        address[] calldata _recipients,
        uint256[] calldata _amounts,
        string calldata _url,
        string calldata _hash,
        string calldata _payoutId,
        bool forceComplete
    ) external override adminOrReputationOracle notExpired nonReentrant {
        bytes32 payoutId = keccak256(bytes(_payoutId));
        require(remainingFunds != 0, 'No funds');
        require(!payouts[payoutId], 'payoutId already exists');
        uint256 length = _amounts.length;
        require(_recipients.length == length, 'Length mismatch');
        require(length > 0, 'Empty amounts');
        require(length <= BULK_MAX_COUNT, 'Too many recipients');
        require(
            bytes(_url).length != 0 && bytes(_hash).length != 0,
            'Empty url/hash'
        );

        uint256 totalBulkAmount;

        for (uint256 i; i < length; ) {
            uint256 amount = _amounts[i];
            require(amount > 0, 'Zero amount');
            totalBulkAmount += amount;
            unchecked {
                ++i;
            }
        }

        require(totalBulkAmount <= reservedFunds, 'Not enough funds');

        unchecked {
            remainingFunds -= totalBulkAmount;
            reservedFunds -= totalBulkAmount;
        }

        for (uint256 i; i < length; ) {
            _safeTransfer(token, _recipients[i], _amounts[i]);
            unchecked {
                ++i;
            }
        }

        finalResultsUrl = _url;
        finalResultsHash = _hash;
        payouts[payoutId] = true;

        bool isPartial = remainingFunds != 0 && !forceComplete;

        emit BulkTransferV3(
            payoutId,
            _recipients,
            _amounts,
            isPartial,
            _url,
            _hash
        );

        if (!isPartial) {
            _finalize();
        } else if (status != EscrowStatuses.ToCancel) {
            status = EscrowStatuses.Partial;
        }
    }

    function _safeTransfer(address _token, address _to, uint256 _amount) private {
        AccountInfo from = tx.accounts.tokens[_token];
        AccountInfo to = tx.accounts.tokens[_to];
        require(from.lamports >= _amount, 'Insufficient balance');
        from.lamports -= _amount;
        to.lamports += _amount;
    }

    modifier adminOrLauncher() {
        require(tx.accounts.dataAccount.key == admin || tx.accounts.dataAccount.key == launcher, 'Unauthorised');
        _;
    }

    modifier adminLauncherOrFactory() {
        require(
            tx.accounts.dataAccount.key == admin ||
                tx.accounts.dataAccount.key == launcher ||
                tx.accounts.dataAccount.key == escrowFactory,
            'Unauthorised'
        );
        _;
    }

    modifier adminOrReputationOracle() {
        require(
            tx.accounts.dataAccount.key == admin || tx.accounts.dataAccount.key == reputationOracle,
            'Unauthorised'
        );
        _;
    }

    modifier adminOrRecordingOracle() {
        require(
            tx.accounts.dataAccount.key == admin || tx.accounts.dataAccount.key == recordingOracle,
            'Unauthorised'
        );
        _;
    }

    modifier notExpired() {
        require(duration > block.timestamp, 'Expired');
        _;
    }
}