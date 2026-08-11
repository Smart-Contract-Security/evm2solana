// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.16;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "contracts/allocation/IAllocationProvider.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import "./interface/IProjectSale.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "contracts/staking/IStakingAmounts.sol";
import "@openzeppelin/contracts/utils/cryptography/draft-EIP712.sol";

/**
 * @title ProjectSale contract
 * @author Finceptor
 * @notice This contract is responsible for the sale of a project' tokens.
 * @dev Used with the following contracts:
 * - KYCProvider
 * - StakingAllocationProvider
 */
contract ProjectSale is IProjectSale, ReentrancyGuard, Pausable, AccessControl, EIP712 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IERC20Metadata;
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant SIGNER = keccak256("SIGNER");
    string private constant SIGNING_DOMAIN = "ProjectSale";
    string private constant SIGNATURE_VERSION = "1";
    uint256 public max_signature_delay = 180;

    struct SaleDetails {
        /// @notice Total value of tokens to be sold
        uint256 totalSaleValueCap;
        /// @notice Price of the project token
        uint256 projectTokenPrice;
        /// @notice Amount of project tokens to be sold
        uint256 projectTokenAmount;
        /// @notice Address to claim deposited funds
        address saleClaimAddress;
        /// @notice Address to claim fees
        address feeClaimAddress;
        /// @notice Total current value of tokens sold
        uint256 totalSaleValue;
        /// @notice Total guaranteed sale value
        uint256 totalGuaranteedSaleValue;
        /// @notice Total current public sale value
        uint256 totalPublicSaleValue;
        /// @notice Pubic sale deposit cap per user
        uint256 publicSaleDepositCap;
        /// @notice The Staking Amounts holder contract
        IStakingAmounts stakingAmounts;
        /// @notice Minimum stake amount to participate in the public sale
        uint256 minStake;
        /// @notice The fee taken on registers
        uint256 registerFee;
        /// @notice The nominator of the allocation multiplier on public round
        uint8 nom;
        /// @notice The denominator of the allocation multiplier on public round
        uint8 denom;
    }

    struct SaleTimes {
        uint256 registerStart;
        uint256 registerEnd;
        uint256 stakingRoundStart;
        uint256 stakingRoundEnd;
        uint256 publicRoundStart;
        uint256 publicRoundEnd;
    }

    /**
     * @notice Sale status enum
     * @dev `NOT_FINALIZED` sale has not been finalized yet
     * @dev `FINALIZED` sale has been finalized
     */
    enum SaleStatus {
        NOT_FINALIZED,
        FINALIZED
    }

    /// @notice Sale status
    SaleStatus private _saleStatus;
    /// @notice Fee to be taken on public round deposits
    uint8 public FCFS_ROUND_FEE = 0;
    uint8 public PUBLIC_ROUND_FEE = 0;
    uint8 public STAKING_ROUND_FEE = 0;

    bool public isFcfs = false;

    /// @notice External provider for allocation
    address public allocationProvider;
    /// @notice Sale details
    SaleDetails public saleDetails;
    /// @notice Sale times
    SaleTimes public saleTimes;

    /// @notice USD token to be used for staking and public round deposits
    IERC20Metadata public immutable usdToken;

    /// @notice Address to claim deposited funds
    address public saleClaimAddress;
    /// @notice Address to claim fees
    address public feeClaimAddress;

    /// @notice Mapping of deposited values of addresses
    EnumerableMap.AddressToUintMap private _depositBalances;
    /// @notice Mapping of credit deposited values of addresses
    EnumerableMap.AddressToUintMap private _creditDepositBalances;
    /// @notice Public sale deposit balances
    mapping(address => uint256) private _publicSaleDepositBalances;

    /// @notice Mapping of registered addresses
    EnumerableSet.AddressSet private _participants;

    /**
     * @dev Throws if block time isn't between `registerStart` and `registerEnd`
     */
    modifier onlyDuringRegisteration() {
        require(
            block.timestamp >= saleTimes.registerStart,
            "ProjectSale: registration period has not started yet"
        );
        require(
            block.timestamp <= saleTimes.registerEnd,
            "ProjectSale: registration period has ended"
        );
        _;
    }

    /**
     * @notice Constructor for ProjectSale contract that initializes the sale.
     * @param _saleTimes Sale times
     * @param _allocationProvider External provider for allocation
     * @param _usdToken Address of USD token
     * @param _projectTokenPrice Price of project token
     * @param _projectTokenAmount Amount of project tokens to be sold
     * @param _totalSaleValueCap Total value of tokens to be sold
     * @param _saleClaimAddress Address to claim deposited funds
     * @param _feeClaimAddress Address to claim fees
     * @dev _projectTokenPrice * _projectTokenAmount == _totalSaleValueCap
     */
    constructor(
        SaleTimes memory _saleTimes,
        address _allocationProvider,
        address _usdToken,
        uint256 _projectTokenPrice,
        uint256 _projectTokenAmount,
        uint256 _totalSaleValueCap,
        address _saleClaimAddress,
        address _feeClaimAddress,
        address _stakingAmounts
    ) EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {
        require(
            _saleTimes.registerStart < _saleTimes.registerEnd,
            "ProjectSale: registerStart must be before registerEnd"
        );
        require(
            _saleTimes.registerEnd < _saleTimes.stakingRoundStart,
            "ProjectSale: registerEnd must be before stakingRoundStart"
        );
        require(
            _saleTimes.stakingRoundStart < _saleTimes.stakingRoundEnd,
            "ProjectSale: stakingRoundStart must be before stakingRoundEnd"
        );
        require(
            _saleTimes.stakingRoundEnd < _saleTimes.publicRoundStart,
            "ProjectSale: stakingRoundEnd must be before publicRoundStart"
        );
        require(
            _saleTimes.publicRoundStart < _saleTimes.publicRoundEnd,
            "ProjectSale: publicRoundStart must be before publicRoundEnd"
        );
        require(
            (_projectTokenPrice * _projectTokenAmount) / (10 ** 18) == _totalSaleValueCap,
            "ProjectSale: invalid sale value"
        );
        require(
            address(_allocationProvider) != address(0),
            "ProjectSale: allocation provider cannot be zero address"
        );
        require(
            _stakingAmounts != address(0),
            "ProjectSale: staking amounts cannot be zero address"
        );

        // Sale Details
        saleTimes = _saleTimes;
        usdToken = IERC20Metadata(_usdToken);
        saleDetails.totalSaleValueCap = _totalSaleValueCap;
        saleDetails.projectTokenPrice = _projectTokenPrice;
        saleDetails.projectTokenAmount = _projectTokenAmount;
        saleDetails.publicSaleDepositCap = 15000 * (10 ** usdToken.decimals());
        saleDetails.stakingAmounts = IStakingAmounts(_stakingAmounts);
        _saleStatus = SaleStatus.NOT_FINALIZED;

        // External provider for allocation
        allocationProvider = _allocationProvider;

        feeClaimAddress = _feeClaimAddress;
        saleClaimAddress = _saleClaimAddress;
        saleDetails.nom = 10;
        saleDetails.denom = 40;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SIGNER, msg.sender);
    }

    function setSaleCap(uint256 _totalSaleValueCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        saleDetails.totalSaleValueCap = _totalSaleValueCap;
    }

    function setFees(
        uint8 _stakingRoundFee,
        uint8 _publicRoundFee,
        uint8 _fcsfRoundFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        STAKING_ROUND_FEE = _stakingRoundFee;
        PUBLIC_ROUND_FEE = _publicRoundFee;
        FCFS_ROUND_FEE = _fcsfRoundFee;
    }

    function setPublicRoundMultiplier(
        uint8 _nom,
        uint8 _denom
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        saleDetails.nom = _nom;
        saleDetails.denom = _denom;
    }

    function activateFCFS() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!isFcfs, "ProjectSale: FCFS is already active");
        require(
            saleTimes.publicRoundStart < block.timestamp,
            "ProjectSale: Public round has not started yet"
        );
        isFcfs = true;
    }

    function deactivateFCFS() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isFcfs, "ProjectSale: FCFS is already inactive");
        isFcfs = false;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function setRegisterFee(uint256 _registerFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        saleDetails.registerFee = _registerFee;
    }

    function setStakingAmounts(
        address _stakingAmounts,
        uint256 _minStake
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            address(_stakingAmounts) != address(0),
            "ProjectSale: staking amounts cannot be zero address"
        );
        saleDetails.stakingAmounts = IStakingAmounts(_stakingAmounts);
        saleDetails.minStake = _minStake;
    }

    function updateAllocationProvider(
        address _allocationProvider
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(
            _allocationProvider != address(0),
            "ProjectSale: allocation provider cannot be zero address"
        );
        allocationProvider = _allocationProvider;
    }

    /**
     * @notice Fuction to update sale times.
     * @dev Can only be called by the owner. And when sale is not finalized.
     * @param _saleTimes New sale times.
     */
    function updateTimes(SaleTimes memory _saleTimes) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_saleStatus == SaleStatus.NOT_FINALIZED, "ProjectSale: sale is finalized");
        require(
            _saleTimes.registerStart < _saleTimes.registerEnd &&
                _saleTimes.stakingRoundStart < _saleTimes.stakingRoundEnd &&
                _saleTimes.publicRoundStart < _saleTimes.publicRoundEnd,
            "ProjectSale: invalid time"
        );
        require(
            _saleTimes.registerEnd < _saleTimes.stakingRoundStart &&
                _saleTimes.stakingRoundEnd < _saleTimes.publicRoundStart,
            "ProjectSale: invalid time"
        );

        saleTimes = _saleTimes;
    }

    /**
     * @notice Fuction to update public sale deposit cap.
     * @dev Can only be called by the owner.
     * @param _publicSaleDepositCap New public sale deposit cap.
     */
    function setPublicSaleCap(uint256 _publicSaleDepositCap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_publicSaleDepositCap > 0, "ProjectSale: cap cannot be zero");
        saleDetails.publicSaleDepositCap = _publicSaleDepositCap;
    }

    /**
     * @notice Fuction to update sale funds receiver address.
     * @dev Can only be called by the owner.
     * @param _newAddress New sale funds receiver address.
     */
    function updateSaleClaimAddress(address _newAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newAddress != address(0), "ProjectSale: address cannot be zero");
        saleClaimAddress = _newAddress;
    }

    /**
     * @notice Fuction to update fee funds receiver address.
     * @dev Can only be called by the owner.
     * @param _newAddress New fee funds receiver address.
     */
    function updateFeeClaimAddress(address _newAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newAddress != address(0), "ProjectSale: address cannot be zero");
        feeClaimAddress = _newAddress;
    }

    /**
     * @notice Registers the sender to the sale.
     * @dev Only allowed during registeration period.
     */
    function register(
        uint256 _timestamp,
        bytes memory _signature
    ) external payable override whenNotPaused onlyDuringRegisteration {
        require(
            block.timestamp <= _timestamp + max_signature_delay,
            "ProjectSalePro: signature expired"
        );
        require(verify(msg.sender, _timestamp, _signature), "ProjectSalePro: Invalid signature");
        require(!isRegistered(msg.sender), "ProjectSale: already registered");
        require(msg.value >= saleDetails.registerFee, "ProjectSale: insufficient fee");

        _participants.add(msg.sender);
        if (saleDetails.registerFee > 0) {
            (bool sent, ) = payable(feeClaimAddress).call{value: saleDetails.registerFee}("");
            require(sent, "Failed to send fee");
        }

        // Refund any excess Ether sent
        uint256 refundAmount = msg.value - saleDetails.registerFee;
        if (refundAmount > 0) {
            (bool refundSuccess, ) = msg.sender.call{value: refundAmount}("");
            require(refundSuccess, "Refund failed");
        }
        emit Registered(msg.sender);
    }

    /**
     * @notice Registers the given address to the sale.
     * @dev Only allowed before staking period start and by the contract owner.
     * @param _user Address to be registered.
     */
    function adminRegister(address _user) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        require(!isRegistered(_user), "ProjectSale: already registered");
        _participants.add(_user);
        emit Registered(_user);
    }

    /**
     * @notice Registers the given addresses to the sale.
     * @dev Only allowed before staking period start and by the contract owner.
     * @param _users Addresses to be registered.
     */
    function batchAdminRegister(
        address[] memory _users
    ) external onlyRole(DEFAULT_ADMIN_ROLE) whenNotPaused {
        for (uint256 i = 0; i < _users.length; i++) {
            //require(!isRegistered(_users[i]), "ProjectSale: already registered");
            if (!isRegistered(_users[i])) {
                _participants.add(_users[i]);
                emit Registered(_users[i]);
            }
        }
    }

    /**
     * @notice Function to deposit tokens to the sale.
     * Deposits from whitelisted account are allowed
     * if it is during the staking round and the account is registered or
     * if it is during the public round.
     * @dev Also includes depositable amount from credit token,
     * `creditDeposit()` should be used first if user has credit.
     * @param _amount is the amount of tokens to be deposited
     */
    function deposit(
        uint256 _amount,
        uint256 _timestamp,
        bytes memory _signature
    ) external override nonReentrant whenNotPaused {
        require(
            block.timestamp <= _timestamp + max_signature_delay,
            "ProjectSalePro: signature expired"
        );
        require(verify(msg.sender, _timestamp, _signature), "ProjectSalePro: Invalid signature");
        require(_amount > 0, "ProjectSale: amount is zero");
        require(
            (isStakingRound() && isRegistered(msg.sender)) || isPublicRound(),
            "ProjectSale: not allowed to deposit"
        );
        uint256 depositableAmount = depositableOf(msg.sender);
        require(depositableAmount > 0, "ProjectSale: depositable amount is zero");

        uint256 fee;
        if (isPublicRound()) {
            require(
                _publicSaleDepositBalances[msg.sender] + _amount <=
                    saleDetails.publicSaleDepositCap,
                "ProjectSale: amount exceeds depositable amount"
            );
            if (_amount > depositableAmount) {
                _amount = depositableAmount;
            }
            if (isFcfs) {
                require(
                    saleDetails.stakingAmounts.stakedOf(msg.sender) >= saleDetails.minStake,
                    "ProjectSale: You do not have enough Staked FINC to participate in the Public Sale"
                );
                fee = (_amount * FCFS_ROUND_FEE) / 100;
            } else {
                fee = (_amount * PUBLIC_ROUND_FEE) / 100;
            }
            _publicSaleDepositBalances[msg.sender] += _amount;
            saleDetails.totalPublicSaleValue += _amount;
        } else {
            require(_amount <= depositableAmount, "ProjectSale: amount exceeds depositable amount");
            fee = (_amount * STAKING_ROUND_FEE) / 100;
        }

        (bool found, uint256 _deposited) = _depositBalances.tryGet(msg.sender);
        if (found) {
            _depositBalances.set(msg.sender, _deposited + _amount);
        } else {
            _depositBalances.set(msg.sender, _amount);
        }

        saleDetails.totalSaleValue += _amount;
        if (isStakingRound()) {
            saleDetails.totalGuaranteedSaleValue += _amount;
        }
        usdToken.safeTransferFrom(msg.sender, saleClaimAddress, _amount);
        if (fee > 0) {
            require(
                usdToken.balanceOf(msg.sender) >= fee,
                "ProjectSale: insufficient balance for fee"
            );
            usdToken.safeTransferFrom(msg.sender, feeClaimAddress, fee);
        }
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice Function to get the total number of participants.
     * @return uint256 is the total number of participants.
     */
    function participantCount() external view returns (uint256) {
        return _participants.length();
    }

    /**
     * @notice Function to get the participant at the given index.
     * @param index is the index of the participant.
     * @return address is the participant.
     */
    function participantAt(uint256 index) external view returns (address) {
        require(index < _participants.length(), "ProjectSale: index out of bounds");
        return _participants.at(index);
    }

    /**
     * @notice Function to get participants between the given indexes.
     * @param start is the start index.
     * @param end is the end index.
     * @return address[] is the array of participants.
     */
    function participantsBetween(
        uint256 start,
        uint256 end
    ) external view returns (address[] memory) {
        require(start <= end, "ProjectSale: start > end");
        require(end <= _participants.length(), "ProjectSale: index out of bounds");
        address[] memory _participantsArray = new address[](end - start);
        for (uint256 i = start; i < end; i++) {
            _participantsArray[i - start] = _participants.at(i);
        }
        return _participantsArray;
    }

    /**
     * @notice Function to view the total sale value
     * @return uint256 is the total sale value.
     */
    function totalSaleValue() external view returns (uint256) {
        return saleDetails.totalSaleValue;
    }

    /**
     * @notice Function to view the total sale value cap
     * @return uint256 is the total sale value cap.
     */
    function totalSaleValueCap() external view returns (uint256) {
        return saleDetails.totalSaleValueCap;
    }

    /**
     * @notice Function to view the total public sale deposited of a user
     * @param _account is the address to check.
     * @return uint256 is the total public sale deposited.
     */
    function publicSaleDepositedOf(address _account) external view returns (uint256) {
        return _publicSaleDepositBalances[_account];
    }

    /**
     * @notice Function to view the final deposit value of any given amount with fees included.
     * @param _amount is the amount to check.
     * @return uint256 is the final deposit value with fees.
     */
    function depositAmountWithFees(uint256 _amount) external view override returns (uint256) {
        if (
            block.timestamp >= saleTimes.stakingRoundStart &&
            block.timestamp <= saleTimes.stakingRoundEnd
        ) {
            return (_amount * (100 + STAKING_ROUND_FEE)) / 100;
        }
        if (
            block.timestamp >= saleTimes.publicRoundStart &&
            block.timestamp <= saleTimes.publicRoundEnd
        ) {
            if (isFcfs) {
                return (_amount * (100 + FCFS_ROUND_FEE)) / 100;
            } else {
                return (_amount * (100 + PUBLIC_ROUND_FEE)) / 100;
            }
        }
        return _amount;
    }

    function getDepositAmounts(
        uint256 _start,
        uint256 _end
    ) external view returns (address[] memory, uint256[] memory) {
        if (_end > _depositBalances.length()) {
            _end = _depositBalances.length();
        }
        require(_start < _end, "Invalid start index");

        address[] memory addresses = new address[](_end - _start);
        uint256[] memory amounts = new uint256[](_end - _start);

        for (uint256 i = _start; i < _end; i++) {
            (address _address, uint256 _amount) = _depositBalances.at(i);
            addresses[i - _start] = _address;
            amounts[i - _start] = _amount;
        }

        return (addresses, amounts);
    }

    /**
     * @dev Returns true if time is between staking round
     * @return True if time is between staking round
     */
    function isStakingRound() public view returns (bool) {
        return
            block.timestamp >= saleTimes.stakingRoundStart &&
            block.timestamp <= saleTimes.stakingRoundEnd;
    }

    /**
     * @dev Returns true if time is between public round
     * @return True if time is between public round
     */
    function isPublicRound() public view returns (bool) {
        return
            block.timestamp >= saleTimes.publicRoundStart &&
            block.timestamp <= saleTimes.publicRoundEnd;
    }

    /**
     * @notice Function to see if an address is registered or not.
     * @param _account is the address to check.
     * @return bool is if the address is registered or not.
     */
    function isRegistered(address _account) public view override returns (bool) {
        return _participants.contains(_account);
    }

    /**
     * @notice Function to see total deposited amount of an address.
     * @param _account is the address to check.
     * @return uint256 is the total deposited amount.
     */
    function depositedOf(address _account) public view override returns (uint256) {
        (bool success, uint256 _deposited) = _depositBalances.tryGet(_account);
        if (success) {
            return _deposited;
        }
        return 0;
    }

    /**
     * @notice Function to see remaining depositable amount from direct and staking alloction of an address.
     * @dev If its the public round, every address gets the same amount.
     * @param _account is the address to check.
     * @return uint256 is the remaining depositable amount.
     */
    function depositableOf(address _account) public view override returns (uint256) {
        if (
            (isRegistered(_account) && isStakingRound()) ||
            (block.timestamp < saleTimes.stakingRoundStart)
        ) {
            return stakingRoundAllocationOf(_account);
        } else if (isPublicRound() && !isFcfs) {
            return publicRoundAllocationOf(_account);
        } else if (isPublicRound() && isFcfs) {
            return
                saleDetails.publicSaleDepositCap - _publicSaleDepositBalances[_account] <
                    saleDetails.totalSaleValueCap - saleDetails.totalSaleValue
                    ? saleDetails.publicSaleDepositCap - _publicSaleDepositBalances[_account]
                    : saleDetails.totalSaleValueCap - saleDetails.totalSaleValue;
        } else {
            return 0;
        }
    }

    /**
     * @notice Function to see remaining depositable amount from direct and staking alloction of an address.
     * @dev Only relevant in the staking round.
     * @param _account is the address to check.
     * @return uint256 is the remaining depositable amount.
     */
    function stakingRoundAllocationOf(address _account) public view override returns (uint256) {
        return
            IAllocationProvider(allocationProvider).allocationOf(_account) - depositedOf(_account);
    }

    function getSaleNom() public view returns (uint256) {
        if (saleDetails.nom != 10) {
            return saleDetails.nom;
        } else {
            // Calculte percentage left of sale
            uint256 percentageSold = (saleDetails.totalGuaranteedSaleValue * 100) /
                saleDetails.totalSaleValueCap;

            return 100 - percentageSold;
        }
    }

    function publicRoundAllocationOf(address _account) public view override returns (uint256) {
        uint256 alloc = (IAllocationProvider(allocationProvider).allocationOf(_account) *
            getSaleNom()) / saleDetails.denom;
        if (alloc > saleDetails.publicSaleDepositCap) {
            alloc = saleDetails.publicSaleDepositCap;
        }
        alloc = alloc - _publicSaleDepositBalances[_account];

        if (alloc > saleDetails.totalSaleValueCap - saleDetails.totalSaleValue) {
            alloc = saleDetails.totalSaleValueCap - saleDetails.totalSaleValue;
        }
        return alloc;
    }

    function verify(
        address _address,
        uint256 _timestamp,
        bytes memory _signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256("Verify(address address,uint256 timestamp)"),
                    _address,
                    _timestamp
                )
            )
        );
        address signer = ECDSA.recover(digest, _signature);
        return hasRole(SIGNER, signer);
    }
}