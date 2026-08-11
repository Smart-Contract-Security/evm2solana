import 'solana';

contract EscrowFactory {
    uint64 constant STANDARD_DURATION = 8640000;
    string constant ERROR_ZERO_ADDRESS = 'Zero Address';

    uint64 public counter;
    mapping(address => uint64) public escrowCounters;
    address public lastEscrow;
    address public staking;
    uint64 public minimumStake;
    address public admin;
    address public kvstore;
    address public owner;

    event Launched(address token, address escrow);
    event LaunchedV2(address token, address escrow, string jobRequesterId);
    event SetStakingAddress(address stakingAddress);
    event SetMinumumStake(uint64 minimumStake);
    event SetKVStoreAddress(address kvStoreAddress);

    constructor() {
        owner = tx.accounts.dataAccount.key;
    }

    function initialize(
        address _staking,
        uint64 _minimumStake,
        address _kvstore
    ) external {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        require(_staking != address(0), ERROR_ZERO_ADDRESS);
        _setKVStoreAddress(_kvstore);
        _setStakingAddress(_staking);
        _setMinimumStake(_minimumStake);
        _setEscrowAdmin(tx.accounts.dataAccount.key);
    }

    function _launchEscrow(
        address _token,
        string calldata _jobRequesterId
    ) private {
        (uint64 availableStake) = IStaking(staking).getAvailableStake{accounts: [tx.accounts.dataAccount]}(tx.accounts.dataAccount.key);
        require(availableStake >= minimumStake, 'Insufficient stake');
        require(admin != address(0), ERROR_ZERO_ADDRESS);

        Escrow escrow = new Escrow{program_id: address(0)}();
        escrow.initialize{accounts: [tx.accounts.dataAccount]}(_token, tx.accounts.dataAccount.key, admin, STANDARD_DURATION, kvstore);
        counter++;
        escrowCounters[address(escrow)] = counter;
        lastEscrow = address(escrow);

        emit LaunchedV2(_token, lastEscrow, _jobRequesterId);
    }

    function createEscrow(
        address _token,
        string calldata _jobRequesterId
    ) external returns (address) {
        _launchEscrow(_token, _jobRequesterId);
        return lastEscrow;
    }

    function createFundAndSetupEscrow(
        address _token,
        uint64 _amount,
        string calldata _jobRequesterId,
        address _reputationOracle,
        address _recordingOracle,
        address _exchangeOracle,
        string calldata _url,
        string calldata _hash
    ) external returns (address) {
        require(_amount > 0, 'Amount is 0');

        _launchEscrow(_token, _jobRequesterId);
        IERC20(_token).transferFrom{accounts: [tx.accounts.dataAccount, lastEscrow]}(tx.accounts.dataAccount.key, lastEscrow, _amount);
        IEscrow(lastEscrow).setup{accounts: [tx.accounts.dataAccount]}(_reputationOracle, _recordingOracle, _exchangeOracle, _url, _hash);

        return lastEscrow;
    }

    function hasEscrow(address _address) external view returns (bool) {
        return escrowCounters[_address] != 0;
    }

    function setStakingAddress(address _stakingAddress) external {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        _setStakingAddress(_stakingAddress);
    }

    function _setStakingAddress(address _stakingAddress) private {
        require(_stakingAddress != address(0), ERROR_ZERO_ADDRESS);
        staking = _stakingAddress;
        emit SetStakingAddress(_stakingAddress);
    }

    function setMinimumStake(uint64 _minimumStake) external {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        _setMinimumStake(_minimumStake);
    }

    function _setMinimumStake(uint64 _minimumStake) private {
        require(_minimumStake > 0, 'Must be a positive number');
        minimumStake = _minimumStake;
        emit SetMinumumStake(minimumStake);
    }

    function setAdmin(address _admin) external {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        _setEscrowAdmin(_admin);
    }

    function _setEscrowAdmin(address _admin) private {
        require(_admin != address(0), ERROR_ZERO_ADDRESS);
        admin = _admin;
    }

    function setKVStoreAddress(address _kvstore) external {
        require(tx.accounts.dataAccount.key == owner, "Not owner");
        _setKVStoreAddress(_kvstore);
    }

    function _setKVStoreAddress(address _kvstore) private {
        require(_kvstore != address(0), ERROR_ZERO_ADDRESS);
        kvstore = _kvstore;
        emit SetKVStoreAddress(_kvstore);
    }

    uint64[43] private __gap;
}

interface IStaking {
    function getAvailableStake(address staker) external view returns (uint64);
}

interface IERC20 {
    function transferFrom(address from, address to, uint64 amount) external returns (bool);
}

interface IEscrow {
    function initialize(address _token, address _sender, address _admin, uint64 _duration, address _kvstore) external;
    function setup(address _reputationOracle, address _recordingOracle, address _exchangeOracle, string calldata _url, string calldata _hash) external;
}