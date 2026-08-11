// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './Escrow.sol';

contract EscrowFactory {
    uint256 constant STANDARD_DURATION = 8640000;
    string constant ERROR_ZERO_ADDRESS = 'Zero Address';

    address public owner;
    uint256 public counter;
    mapping(address => uint256) public escrowCounters;
    address public lastEscrow;
    address public staking;
    uint256 public minimumStake;
    address public admin;
    address public kvstore;

    event Launched(address token, address escrow);
    event LaunchedV2(address token, address escrow, string jobRequesterId);
    event SetStakingAddress(address indexed stakingAddress);
    event SetMinumumStake(uint256 indexed minimumStake);
    event SetKVStoreAddress(address indexed kvStoreAddress);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(tx.accounts[0].key == owner, "Ownable: caller is not the owner");
        _;
    }

    constructor() {
        owner = tx.accounts[0].key;
        emit OwnershipTransferred(address(0), tx.accounts[0].key);
    }

    function initialize(
        address _staking,
        uint256 _minimumStake,
        address _kvstore
    ) external payable {
        require(owner == address(0), "Already initialized");
        owner = tx.accounts[0].key;
        emit OwnershipTransferred(address(0), tx.accounts[0].key);
        require(_staking != address(0), ERROR_ZERO_ADDRESS);
        _setKVStoreAddress(_kvstore);
        _setStakingAddress(_staking);
        _setMinimumStake(_minimumStake);
        _setEscrowAdmin(tx.accounts[0].key);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function _launchEscrow(
        address _token,
        string calldata _jobRequesterId
    ) private {
        uint256 availableStake = IStaking(staking).getAvailableStake(
            tx.accounts[0].key
        );
        require(availableStake >= minimumStake, 'Insufficient stake');
        require(admin != address(0), ERROR_ZERO_ADDRESS);

        Escrow escrow = new Escrow(
            _token,
            tx.accounts[0].key,
            admin,
            STANDARD_DURATION,
            kvstore
        );
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
        uint256 _amount,
        string calldata _jobRequesterId,
        address _reputationOracle,
        address _recordingOracle,
        address _exchangeOracle,
        string calldata _url,
        string calldata _hash
    ) external returns (address) {
        require(_amount > 0, 'Amount is 0');

        _launchEscrow(_token, _jobRequesterId);
        IERC20(_token).transferFrom(
            tx.accounts[0].key,
            address(lastEscrow),
            _amount
        );
        Escrow(lastEscrow).setup(
            _reputationOracle,
            _recordingOracle,
            _exchangeOracle,
            _url,
            _hash
        );

        return lastEscrow;
    }

    function hasEscrow(address _address) external view returns (bool) {
        return escrowCounters[_address] != 0;
    }

    function setStakingAddress(address _stakingAddress) external onlyOwner {
        _setStakingAddress(_stakingAddress);
    }

    function _setStakingAddress(address _stakingAddress) private {
        require(_stakingAddress != address(0), ERROR_ZERO_ADDRESS);
        staking = _stakingAddress;
        emit SetStakingAddress(_stakingAddress);
    }

    function setMinimumStake(uint256 _minimumStake) external onlyOwner {
        _setMinimumStake(_minimumStake);
    }

    function _setMinimumStake(uint256 _minimumStake) private {
        require(_minimumStake > 0, 'Must be a positive number');
        minimumStake = _minimumStake;
        emit SetMinumumStake(minimumStake);
    }

    function setAdmin(address _admin) external onlyOwner {
        _setEscrowAdmin(_admin);
    }

    function _setEscrowAdmin(address _admin) private {
        require(_admin != address(0), ERROR_ZERO_ADDRESS);
        admin = _admin;
    }

    function setKVStoreAddress(address _kvstore) external onlyOwner {
        _setKVStoreAddress(_kvstore);
    }

    function _setKVStoreAddress(address _kvstore) private {
        require(_kvstore != address(0), ERROR_ZERO_ADDRESS);
        kvstore = _kvstore;
        emit SetKVStoreAddress(_kvstore);
    }
}

interface IStaking {
    function getAvailableStake(address staker) external view returns (uint256);
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}