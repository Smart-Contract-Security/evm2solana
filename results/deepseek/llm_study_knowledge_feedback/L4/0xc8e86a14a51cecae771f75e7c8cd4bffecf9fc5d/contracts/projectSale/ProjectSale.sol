// SPDX-License-Identifier: BSD-3-Clause

import "solana";

interface IERC20 {
    function transfer(address to, uint64 amount) external returns (bool);
    function approve(address spender, uint64 amount) external returns (bool);
    function transferFrom(address from, address to, uint64 amount) external returns (bool);
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function allowance(address owner, address spender) external view returns (uint64);
}

interface IERC20Metadata {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

interface IAllocationProvider {
    function allocationOf(address _account) external view returns (uint64);
}

interface IStakingAmounts {
    function stakedOf(address _account) external view returns (uint64);
}

interface IProjectSale {
    function register(uint64 _timestamp, bytes memory _signature) external;
    function deposit(uint64 _amount, uint64 _timestamp, bytes memory _signature) external;
    function depositAmountWithFees(uint64 _amount) external view returns (uint64);
    function isRegistered(address _account) external view returns (bool);
    function depositedOf(address _account) external view returns (uint64);
    function depositableOf(address _account) external view returns (uint64);
    function stakingRoundAllocationOf(address _account) external view returns (uint64);
    function publicRoundAllocationOf(address _account) external view returns (uint64);
}

contract ProjectSale is IProjectSale {
    using EnumerableMap for EnumerableMap.AddressToUintMap;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 constant SIGNER = keccak256("SIGNER");
    string constant SIGNING_DOMAIN = "ProjectSale";
    string constant SIGNATURE_VERSION = "1";
    uint64 max_signature_delay = 180;

    struct SaleDetails {
        uint64 totalSaleValueCap;
        uint64 projectTokenPrice;
        uint64 projectTokenAmount;
        address saleClaimAddress;
        address feeClaimAddress;
        uint64 totalSaleValue;
        uint64 totalGuaranteedSaleValue;
        uint64 totalPublicSaleValue;
        uint64 publicSaleDepositCap;
        address stakingAmounts;
        uint64 minStake;
        uint64 registerFee;
        uint8 nom;
        uint8 denom;
    }

    struct SaleTimes {
        uint64 registerStart;
        uint64 registerEnd;
        uint64 stakingRoundStart;
        uint64 stakingRoundEnd;
        uint64 publicRoundStart;
        uint64 publicRoundEnd;
    }

    enum SaleStatus {
        NOT_FINALIZED,
        FINALIZED
    }

    SaleStatus private _saleStatus;
    uint8 public FCFS_ROUND_FEE = 0;
    uint8 public PUBLIC_ROUND_FEE = 0;
    uint8 public STAKING_ROUND_FEE = 0;

    bool public isFcfs = false;

    address public allocationProvider;
    SaleDetails public saleDetails;
    SaleTimes public saleTimes;

    address public immutable usdToken;

    address public saleClaimAddress;
    address public feeClaimAddress;

    EnumerableMap.AddressToUintMap private _depositBalances;
    EnumerableMap.AddressToUintMap private _creditDepositBalances;
    mapping(address => uint64) private _publicSaleDepositBalances;

    EnumerableSet.AddressSet private _participants;

    address private _admin;
    address private _signer;

    modifier onlyDuringRegisteration() {
        require(
            block.timestamp >= saleTimes.registerStart
        );
        require(
            block.timestamp <= saleTimes.registerEnd
        );
        _;
    }

    modifier onlyAdmin() {
        require(tx.accounts.dataAccount.key == _admin);
        _;
    }

    modifier whenNotPaused() {
        _;
    }

    modifier nonReentrant() {
        _;
    }

    @payer(payer)
    @space(512 + 32 * 100)
    constructor(
        SaleTimes memory _saleTimes,
        address _allocationProvider,
        address _usdToken,
        uint64 _projectTokenPrice,
        uint64 _projectTokenAmount,
        uint64 _totalSaleValueCap,
        address _saleClaimAddress,
        address _feeClaimAddress,
        address _stakingAmounts,
        @seed bytes seed
    ) {
        require(
            _saleTimes.registerStart < _saleTimes.registerEnd
        );
        require(
            _saleTimes.registerEnd < _saleTimes.stakingRoundStart
        );
        require(
            _saleTimes.stakingRoundStart < _saleTimes.stakingRoundEnd
        );
        require(
            _saleTimes.stakingRoundEnd < _saleTimes.publicRoundStart
        );
        require(
            _saleTimes.publicRoundStart < _saleTimes.publicRoundEnd
        );
        require(
            (_projectTokenPrice * _projectTokenAmount) / (10 ** 18) == _totalSaleValueCap
        );
        require(
            _allocationProvider != address(0)
        );
        require(
            _stakingAmounts != address(0)
        );

        saleTimes = _saleTimes;
        usdToken = _usdToken;
        saleDetails.totalSaleValueCap = _totalSaleValueCap;
        saleDetails.projectTokenPrice = _projectTokenPrice;
        saleDetails.projectTokenAmount = _projectTokenAmount;
        saleDetails.publicSaleDepositCap = 15000 * (10 ** IERC20Metadata(_usdToken).decimals());
        saleDetails.stakingAmounts = _stakingAmounts;
        _saleStatus = SaleStatus.NOT_FINALIZED;

        allocationProvider = _allocationProvider;

        feeClaimAddress = _feeClaimAddress;
        saleClaimAddress = _saleClaimAddress;
        saleDetails.nom = 10;
        saleDetails.denom = 40;

        _admin = tx.accounts.dataAccount.key;
        _signer = tx.accounts.dataAccount.key;
    }

    function setSaleCap(uint64 _totalSaleValueCap) external onlyAdmin {
        saleDetails.totalSaleValueCap = _totalSaleValueCap;
    }

    function setFees(
        uint8 _stakingRoundFee,
        uint8 _publicRoundFee,
        uint8 _fcsfRoundFee
    ) external onlyAdmin {
        STAKING_ROUND_FEE = _stakingRoundFee;
        PUBLIC_ROUND_FEE = _publicRoundFee;
        FCFS_ROUND_FEE = _fcsfRoundFee;
    }

    function setPublicRoundMultiplier(
        uint8 _nom,
        uint8 _denom
    ) external onlyAdmin {
        saleDetails.nom = _nom;
        saleDetails.denom = _denom;
    }

    function activateFCFS() external onlyAdmin {
        require(!isFcfs);
        require(
            saleTimes.publicRoundStart < block.timestamp
        );
        isFcfs = true;
    }

    function deactivateFCFS() external onlyAdmin {
        require(isFcfs);
        isFcfs = false;
    }

    function pause() external onlyAdmin {
        // Pause not implemented
    }

    function unpause() external onlyAdmin {
        // Unpause not implemented
    }

    function setRegisterFee(uint64 _registerFee) external onlyAdmin {
        saleDetails.registerFee = _registerFee;
    }

    function setStakingAmounts(
        address _stakingAmounts,
        uint64 _minStake
    ) external onlyAdmin {
        require(
            _stakingAmounts != address(0)
        );
        saleDetails.stakingAmounts = _stakingAmounts;
        saleDetails.minStake = _minStake;
    }

    function updateAllocationProvider(
        address _allocationProvider
    ) external onlyAdmin {
        require(
            _allocationProvider != address(0)
        );
        allocationProvider = _allocationProvider;
    }

    function updateTimes(SaleTimes memory _saleTimes) external onlyAdmin {
        require(_saleStatus == SaleStatus.NOT_FINALIZED);
        require(
            _saleTimes.registerStart < _saleTimes.registerEnd &&
                _saleTimes.stakingRoundStart < _saleTimes.stakingRoundEnd &&
                _saleTimes.publicRoundStart < _saleTimes.publicRoundEnd
        );
        require(
            _saleTimes.registerEnd < _saleTimes.stakingRoundStart &&
                _saleTimes.stakingRoundEnd < _saleTimes.publicRoundStart
        );

        saleTimes = _saleTimes;
    }

    function setPublicSaleCap(uint64 _publicSaleDepositCap) external onlyAdmin {
        require(_publicSaleDepositCap > 0);
        saleDetails.publicSaleDepositCap = _publicSaleDepositCap;
    }

    function updateSaleClaimAddress(address _newAddress) external onlyAdmin {
        require(_newAddress != address(0));
        saleClaimAddress = _newAddress;
    }

    function updateFeeClaimAddress(address _newAddress) external onlyAdmin {
        require(_newAddress != address(0));
        feeClaimAddress = _newAddress;
    }

    function register(
        uint64 _timestamp,
        bytes memory _signature
    ) external override whenNotPaused onlyDuringRegisteration {
        require(
            block.timestamp <= _timestamp + max_signature_delay
        );
        require(verify(tx.accounts.dataAccount.key, _timestamp, _signature));
        require(!isRegistered(tx.accounts.dataAccount.key));

        _participants.add(tx.accounts.dataAccount.key);
        if (saleDetails.registerFee > 0) {
            // Transfer register fee via token transfer instead of native value
            IERC20(usdToken).transferFrom(tx.accounts.dataAccount.key, feeClaimAddress, saleDetails.registerFee);
        }

        emit Registered(tx.accounts.dataAccount.key);
    }

    function adminRegister(address _user) external onlyAdmin whenNotPaused {
        require(!isRegistered(_user));
        _participants.add(_user);
        emit Registered(_user);
    }

    function batchAdminRegister(
        address[] memory _users
    ) external onlyAdmin whenNotPaused {
        for (uint64 i = 0; i < _users.length; i++) {
            if (!isRegistered(_users[i])) {
                _participants.add(_users[i]);
                emit Registered(_users[i]);
            }
        }
    }

    function deposit(
        uint64 _amount,
        uint64 _timestamp,
        bytes memory _signature
    ) external override nonReentrant whenNotPaused {
        require(
            block.timestamp <= _timestamp + max_signature_delay
        );
        require(verify(tx.accounts.dataAccount.key, _timestamp, _signature));
        require(_amount > 0);
        require(
            (isStakingRound() && isRegistered(tx.accounts.dataAccount.key)) || isPublicRound()
        );
        uint64 depositableAmount = depositableOf(tx.accounts.dataAccount.key);
        require(depositableAmount > 0);

        uint64 fee;
        if (isPublicRound()) {
            require(
                _publicSaleDepositBalances[tx.accounts.dataAccount.key] + _amount <=
                    saleDetails.publicSaleDepositCap
            );
            if (_amount > depositableAmount) {
                _amount = depositableAmount;
            }
            if (isFcfs) {
                require(
                    IStakingAmounts(saleDetails.stakingAmounts).stakedOf(tx.accounts.dataAccount.key) >= saleDetails.minStake
                );
                fee = (_amount * FCFS_ROUND_FEE) / 100;
            } else {
                fee = (_amount * PUBLIC_ROUND_FEE) / 100;
            }
            _publicSaleDepositBalances[tx.accounts.dataAccount.key] += _amount;
            saleDetails.totalPublicSaleValue += _amount;
        } else {
            require(_amount <= depositableAmount);
            fee = (_amount * STAKING_ROUND_FEE) / 100;
        }

        (bool found, uint64 _deposited) = _depositBalances.tryGet(tx.accounts.dataAccount.key);
        if (found) {
            _depositBalances.set(tx.accounts.dataAccount.key, _deposited + _amount);
        } else {
            _depositBalances.set(tx.accounts.dataAccount.key, _amount);
        }

        saleDetails.totalSaleValue += _amount;
        if (isStakingRound()) {
            saleDetails.totalGuaranteedSaleValue += _amount;
        }
        IERC20(usdToken).transferFrom(tx.accounts.dataAccount.key, saleClaimAddress, _amount);
        if (fee > 0) {
            require(
                IERC20(usdToken).balanceOf(tx.accounts.dataAccount.key) >= fee
            );
            IERC20(usdToken).transferFrom(tx.accounts.dataAccount.key, feeClaimAddress, fee);
        }
        emit Deposit(tx.accounts.dataAccount.key, _amount);
    }

    function participantCount() external view returns (uint64) {
        return _participants.length();
    }

    function participantAt(uint64 index) external view returns (address) {
        require(index < _participants.length());
        return _participants.at(index);
    }

    function participantsBetween(
        uint64 start,
        uint64 end
    ) external view returns (address[] memory) {
        require(start <= end);
        require(end <= _participants.length());
        address[] memory _participantsArray = new address[](end - start);
        for (uint64 i = start; i < end; i++) {
            _participantsArray[i - start] = _participants.at(i);
        }
        return _participantsArray;
    }

    function totalSaleValue() external view returns (uint64) {
        return saleDetails.totalSaleValue;
    }

    function totalSaleValueCap() external view returns (uint64) {
        return saleDetails.totalSaleValueCap;
    }

    function publicSaleDepositedOf(address _account) external view returns (uint64) {
        return _publicSaleDepositBalances[_account];
    }

    function depositAmountWithFees(uint64 _amount) external view override returns (uint64) {
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
        uint64 _start,
        uint64 _end
    ) external view returns (address[] memory, uint64[] memory) {
        if (_end > _depositBalances.length()) {
            _end = _depositBalances.length();
        }
        require(_start < _end);

        address[] memory addresses = new address[](_end - _start);
        uint64[] memory amounts = new uint64[](_end - _start);

        for (uint64 i = _start; i < _end; i++) {
            (address _address, uint64 _amount) = _depositBalances.at(i);
            addresses[i - _start] = _address;
            amounts[i - _start] = _amount;
        }

        return (addresses, amounts);
    }

    function isStakingRound() public view returns (bool) {
        return
            block.timestamp >= saleTimes.stakingRoundStart &&
            block.timestamp <= saleTimes.stakingRoundEnd;
    }

    function isPublicRound() public view returns (bool) {
        return
            block.timestamp >= saleTimes.publicRoundStart &&
            block.timestamp <= saleTimes.publicRoundEnd;
    }

    function isRegistered(address _account) public view override returns (bool) {
        return _participants.contains(_account);
    }

    function depositedOf(address _account) public view override returns (uint64) {
        (bool success, uint64 _deposited) = _depositBalances.tryGet(_account);
        if (success) {
            return _deposited;
        }
        return 0;
    }

    function depositableOf(address _account) public view override returns (uint64) {
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

    function stakingRoundAllocationOf(address _account) public view override returns (uint64) {
        return
            IAllocationProvider(allocationProvider).allocationOf(_account) - depositedOf(_account);
    }

    function getSaleNom() public view returns (uint64) {
        if (saleDetails.nom != 10) {
            return saleDetails.nom;
        } else {
            uint64 percentageSold = (saleDetails.totalGuaranteedSaleValue * 100) /
                saleDetails.totalSaleValueCap;

            return 100 - percentageSold;
        }
    }

    function publicRoundAllocationOf(address _account) public view override returns (uint64) {
        uint64 alloc = (IAllocationProvider(allocationProvider).allocationOf(_account) *
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
        uint64 _timestamp,
        bytes memory _signature
    ) internal view returns (bool) {
        bytes32 digest = keccak256(
            abi.encode(
                keccak256("Verify(address address,uint64 timestamp)"),
                _address,
                _timestamp
            )
        );
        address signer = recover(digest, _signature);
        return signer == _signer;
    }

    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;
        // Manually extract r, s, v from signature bytes
        // signature layout: [32 bytes r][32 bytes s][1 byte v]
        require(signature.length == 65);
        for (uint64 i = 0; i < 32; i++) {
            r |= bytes32(uint64(signature[i])) << (8 * (31 - i));
        }
        for (uint64 i = 32; i < 64; i++) {
            s |= bytes32(uint64(signature[i])) << (8 * (63 - i));
        }
        v = uint8(signature[64]);
        if (v < 27) {
            v += 27;
        }
        require(v == 27 || v == 28);
        // Solana does not have ecrecover, use signature verification via Solana syscall
        // We'll use the Solana secp256k1 recover via the imported solana library
        return solana.secp256k1_recover(hash, v, r, s);
    }

    event Registered(address indexed account);
    event Deposit(address indexed account, uint64 amount);
}

library EnumerableMap {
    struct AddressToUintMap {
        mapping(address => uint64) _values;
        address[] _keys;
    }

    function set(AddressToUintMap storage map, address key, uint64 value) internal {
        if (!contains(map, key)) {
            map._keys.push(key);
        }
        map._values[key] = value;
    }

    function remove(AddressToUintMap storage map, address key) internal {
        map._values[key] = 0;
        for (uint64 i = 0; i < map._keys.length; i++) {
            if (map._keys[i] == key) {
                map._keys[i] = map._keys[map._keys.length - 1];
                map._keys.pop();
                break;
            }
        }
    }

    function tryGet(AddressToUintMap storage map, address key) internal view returns (bool, uint64) {
        if (contains(map, key)) {
            return (true, map._values[key]);
        }
        return (false, 0);
    }

    function get(AddressToUintMap storage map, address key) internal view returns (uint64) {
        require(contains(map, key));
        return map._values[key];
    }

    function contains(AddressToUintMap storage map, address key) internal view returns (bool) {
        return map._values[key] != 0;
    }

    function length(AddressToUintMap storage map) internal view returns (uint64) {
        return uint64(map._keys.length);
    }

    function at(AddressToUintMap storage map, uint64 index) internal view returns (address, uint64) {
        require(index < length(map));
        address key = map._keys[index];
        return (key, map._values[key]);
    }
}

library EnumerableSet {
    struct AddressSet {
        mapping(address => bool) _values;
        address[] _keys;
    }

    function add(AddressSet storage set, address value) internal {
        if (!contains(set, value)) {
            set._values[value] = true;
            set._keys.push(value);
        }
    }

    function remove(AddressSet storage set, address value) internal {
        set._values[value] = false;
        for (uint64 i = 0; i < set._keys.length; i++) {
            if (set._keys[i] == value) {
                set._keys[i] = set._keys[set._keys.length - 1];
                set._keys.pop();
                break;
            }
        }
    }

    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return set._values[value];
    }

    function length(AddressSet storage set) internal view returns (uint64) {
        return uint64(set._keys.length);
    }

    function at(AddressSet storage set, uint64 index) internal view returns (address) {
        require(index < length(set));
        return set._keys[index];
    }
}