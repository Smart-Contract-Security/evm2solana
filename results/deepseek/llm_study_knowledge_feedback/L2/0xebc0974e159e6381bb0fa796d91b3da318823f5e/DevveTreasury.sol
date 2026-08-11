// File: @openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol

interface IERC20Upgradeable {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
    function transferFrom(address from, address to, uint64 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
}

// File: @openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol

library AddressUpgradeable {
    function isContract(address account) internal view returns (bool) {
        return account != address(0);
    }

    function sendValue(address payable recipient, uint64 amount) internal {
        require(tx.accounts.dataAccount.lamports >= amount, "Address: insufficient balance");
        tx.accounts.dataAccount.lamports -= amount;
        recipient.lamports += amount;
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(address target, bytes memory data, uint64 value, string memory errorMessage) internal returns (bytes memory) {
        require(tx.accounts.dataAccount.lamports >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");
        (bool success, bytes memory returndata) = target.call(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    function verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                revert(errorMessage);
            } else {
                revert(errorMessage);
            }
        }
    }
}

// File: @openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol

abstract contract Initializable {
    bool private _initialized;
    bool private _initializing;

    modifier initializer() {
        require(_initializing ? _isConstructor() : !_initialized, "Initializable: contract is already initialized");
        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
        }
    }

    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    function _isConstructor() private view returns (bool) {
        return !AddressUpgradeable.isContract(address(this));
    }
}

// File: @openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol

abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {}
    function __Context_init_unchained() internal onlyInitializing {}

    function _msgSender() internal view virtual returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    uint64[50] private __gap;
}

// File: @openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol

abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
        _transferOwnership(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    uint64[49] private __gap;
}

library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    function toString(uint64 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint64 temp = value;
        uint64 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint64(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function toHexString(uint64 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint64 temp = value;
        uint64 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    function toHexString(uint64 value, uint64 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint64 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}

// File: @openzeppelin/contracts/utils/cryptography/ECDSA.sol

library ECDSA {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS,
        InvalidSignatureV
    }

    function _throwError(RecoverError error) private pure {
        if (error == RecoverError.NoError) {
            return;
        } else if (error == RecoverError.InvalidSignature) {
            revert("ECDSA: invalid signature");
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert("ECDSA: invalid signature length");
        } else if (error == RecoverError.InvalidSignatureS) {
            revert("ECDSA: invalid signature 's' value");
        } else if (error == RecoverError.InvalidSignatureV) {
            revert("ECDSA: invalid signature 'v' value");
        }
    }

    function tryRecover(bytes32 hash, bytes memory signature) internal pure returns (address, RecoverError) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            bytes memory rBytes = new bytes(32);
            bytes memory sBytes = new bytes(32);
            for (uint64 i = 0; i < 32; i++) {
                rBytes[i] = signature[i];
                sBytes[i] = signature[i + 32];
            }
            r = abi.decode(rBytes, (bytes32));
            s = abi.decode(sBytes, (bytes32));
            v = uint8(signature[64]);
            return tryRecover(hash, v, r, s);
        } else if (signature.length == 64) {
            bytes32 r;
            bytes32 vs;
            bytes memory rBytes = new bytes(32);
            bytes memory vsBytes = new bytes(32);
            for (uint64 i = 0; i < 32; i++) {
                rBytes[i] = signature[i];
                vsBytes[i] = signature[i + 32];
            }
            r = abi.decode(rBytes, (bytes32));
            vs = abi.decode(vsBytes, (bytes32));
            return tryRecover(hash, r, vs);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength);
        }
    }

    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, signature);
        _throwError(error);
        return recovered;
    }

    function tryRecover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address, RecoverError) {
        bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        uint8 v = uint8((uint64(bytes32(vs)) >> 255) + 27);
        return tryRecover(hash, v, r, s);
    }

    function recover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, r, vs);
        _throwError(error);
        return recovered;
    }

    function tryRecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address, RecoverError) {
        if (uint64(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS);
        }
        if (v != 27 && v != 28) {
            return (address(0), RecoverError.InvalidSignatureV);
        }
        revert("ECDSA: ecrecover not available on Solana");
    }

    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, v, r, s);
        _throwError(error);
        return recovered;
    }

    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(s.length), s));
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

// File: @openzeppelin/contracts/utils/cryptography/draft-EIP712.sol

abstract contract EIP712 {
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint64 private immutable _CACHED_CHAIN_ID;
    address private immutable _CACHED_THIS;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    bytes32 private immutable _TYPE_HASH;

    constructor(string memory name, string memory version) {
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes(version));
        bytes32 typeHash = keccak256(
            "EIP712Domain(string name,string version,uint64 chainId,address verifyingContract)"
        );
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        _CACHED_CHAIN_ID = 0;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(typeHash, hashedName, hashedVersion);
        _CACHED_THIS = address(this);
        _TYPE_HASH = typeHash;
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _CACHED_THIS && 0 == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
        }
    }

    function _buildDomainSeparator(bytes32 typeHash, bytes32 nameHash, bytes32 versionHash) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, nameHash, versionHash, uint64(0), address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return ECDSA.toTypedDataHash(_domainSeparatorV4(), structHash);
    }
}

// File: whitelist.sol

contract whitelistChecker is EIP712 {
    string private constant SIGNING_DOMAIN = "DevvE_LAUNCHPAD";
    string private constant SIGNATURE_VERSION = "1";

    struct Whitelist {
        address userAddress;
        uint64 timestamp;
        uint64 projectId;
        uint64 amount;
        uint64 platformFee;
        bool inETH;
        bytes signature;
    }

    constructor() EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {}

    function getSigner(Whitelist memory whitelist) public view returns (address) {
        return _verify(whitelist);
    }

    function _hash(Whitelist memory whitelist) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
                keccak256("Whitelist(address userAddress,uint64 timestamp,uint64 projectId,uint64 amount,uint64 platformFee,bool inETH)"),
                whitelist.userAddress,
                whitelist.timestamp,
                whitelist.projectId,
                whitelist.amount,
                whitelist.platformFee,
                whitelist.inETH
            )));
    }

    function _verify(Whitelist memory whitelist) internal view returns (address) {
        bytes32 digest = _hash(whitelist);
        return ECDSA.recover(digest, whitelist.signature);
    }
}

// File: @openzeppelin/contracts/utils/Context.sol

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract ReentrancyGuardUpgradeable is Initializable {
    uint64 private constant _NOT_ENTERED = 1;
    uint64 private constant _ENTERED = 2;

    uint64 private _status;

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    uint64[49] private __gap;
}

interface IERC20PermitUpgradeable {
    function permit(address owner, address spender, uint64 value, uint64 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function nonces(address owner) external view returns (uint64);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

library SafeERC20Upgradeable {
    using AddressUpgradeable for address;

    function safeTransfer(address token, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Upgradeable.transfer.selector, to, value));
    }

    function safeTransferFrom(address token, address from, address to, uint64 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Upgradeable.transferFrom.selector, from, to, value));
    }

    function safeApprove(address token, address spender, uint64 value) internal {
        require((value == 0) || (IERC20Upgradeable(token).allowance(address(this), spender) == 0), "SafeERC20: approve from non-zero to non-zero allowance");
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Upgradeable.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(address token, address spender, uint64 value) internal {
        uint64 newAllowance = IERC20Upgradeable(token).allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(IERC20Upgradeable.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(address token, address spender, uint64 value) internal {
        unchecked {
            uint64 oldAllowance = IERC20Upgradeable(token).allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint64 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(IERC20Upgradeable.approve.selector, spender, newAllowance));
        }
    }

    function safePermit(address token, address owner, address spender, uint64 value, uint64 deadline, uint8 v, bytes32 r, bytes32 s) internal {
        uint64 nonceBefore = IERC20PermitUpgradeable(token).nonces(owner);
        IERC20PermitUpgradeable(token).permit(owner, spender, value, deadline, v, r, s);
        uint64 nonceAfter = IERC20PermitUpgradeable(token).nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        bytes memory returndata = token.functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// File: @openzeppelin/contracts/access/Ownable.sol

contract DevveTreasury is OwnableUpgradeable, whitelistChecker, ReentrancyGuardUpgradeable {
    address public designatedSigner;
    event randomFunction(uint64 randomNumber, uint64 validFrom, uint64 validTo, address _forWhichItIsValid);

    mapping(uint64 => mapping(address => uint64)) public investorInvestedAmountPerProjectInETH;
    mapping(uint64 => mapping(address => uint64)) public investorInvestedAmountPerProjectInUSDT;
    mapping(uint64 => uint64) public projectTotalCollectedInETH;
    mapping(uint64 => uint64) public projectTotalCollectedInUSDT;
    mapping(uint64 => uint64) public projectCollectedInUSDT;
    mapping(uint64 => mapping(bool => bool)) internal onlyOncePerProject;
    mapping(uint64 => mapping(bool => uint64)) public fundsWithdrawn;
    mapping(address => mapping(uint64 => bool)) internal nonceStore;
    mapping(address => mapping(uint64 => bool)) public isRefundedInETH;
    mapping(address => mapping(uint64 => bool)) public isRefundedInUSDT;
    mapping(address => mapping(uint64 => uint64)) internal whichCurreny;
    mapping(uint64 => mapping(uint64 => address[])) public projectUsersInETH;
    mapping(uint64 => mapping(uint64 => address[])) public projectUsersInUSDT;
    mapping(uint64 => uint64) internal projectIdToSlotsInETH;
    mapping(uint64 => uint64) internal projectIdToSlotsInUSDT;
    mapping(address => mapping(uint64 => bool)) public refundAmountInUSDT;
    mapping(address => mapping(uint64 => bool)) public refundAmountInETH;
    mapping(address => bool) public isOwner;
    uint64 public refundAmunt = 0;

    mapping(uint64 => address[]) internal projectUsers;
    mapping(uint64 => mapping(uint64 => bool)) public PlatformFee;
    using SafeERC20Upgradeable for address;
    address public usdt;
    event Deposit(address sender, address receiver, uint64 amount, uint64 projectid);
    event DesignatedSigner(address sender);
    event Owner(address sender);

    constructor() {
        designatedSigner = tx.accounts.dataAccount.key;
        isOwner[tx.accounts.dataAccount.key] = true;
    }

    function setUSDTAddress(address _usdt) external onlyOwner {
        usdt = _usdt;
    }

    function setDesignatedSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "validate Address");
        designatedSigner = _signer;
        emit DesignatedSigner(_signer);
    }

    modifier onlyOnce(uint64 projectId, bool inETH) {
        require(!onlyOncePerProject[projectId][inETH], 'Already Claimed');
        _;
    }

    function setOwners(address _address, bool _setStatus) external onlyOwner {
        require(_address != address(0), "validate Address");
        isOwner[_address] = _setStatus;
        emit Owner(_address);
    }

    function investInProjects(Whitelist memory users) external nonReentrant {
        require(getSigner(users) == designatedSigner, '!Signer');
        require(users.userAddress == tx.accounts.dataAccount.key, '!User');
        require(!nonceStore[users.userAddress][users.timestamp], '!Nonce Used');
        nonceStore[users.userAddress][users.timestamp] = true;
        if (!users.inETH) {
            require(whichCurreny[tx.accounts.dataAccount.key][users.projectId] != 2, '!Allowed');
            if (whichCurreny[tx.accounts.dataAccount.key][users.projectId] == 0)
                whichCurreny[tx.accounts.dataAccount.key][users.projectId] = 1;
            uint64 _amountToWithdraw = (users.amount * 10**6 / 100);
            SafeERC20Upgradeable.safeTransferFrom(usdt, tx.accounts.dataAccount.key, address(this), _amountToWithdraw);
            investorInvestedAmountPerProjectInUSDT[users.projectId][tx.accounts.dataAccount.key] += _amountToWithdraw;
            projectTotalCollectedInUSDT[users.projectId] += _amountToWithdraw;
            projectCollectedInUSDT[users.projectId] += _amountToWithdraw;
            if (projectUsersInUSDT[users.projectId][projectIdToSlotsInUSDT[users.projectId]].length > 200) {
                projectIdToSlotsInUSDT[users.projectId] += 1;
            }
            projectUsersInUSDT[users.projectId][projectIdToSlotsInUSDT[users.projectId]].push(tx.accounts.dataAccount.key);
            emit Deposit(tx.accounts.dataAccount.key, address(this), _amountToWithdraw, users.projectId);
        } else {
            uint64 msgValue = uint64(tx.accounts.dataAccount.lamports);
            investorInvestedAmountPerProjectInETH[users.projectId][tx.accounts.dataAccount.key] += msgValue;
            projectTotalCollectedInETH[users.projectId] += msgValue;
            if (projectUsersInETH[users.projectId][projectIdToSlotsInETH[users.projectId]].length > 200) {
                projectIdToSlotsInETH[users.projectId] += 1;
            }
            projectUsersInETH[users.projectId][projectIdToSlotsInETH[users.projectId]].push(tx.accounts.dataAccount.key);
            emit Deposit(tx.accounts.dataAccount.key, address(this), msgValue, users.projectId);
        }
        projectUsers[users.projectId].push(tx.accounts.dataAccount.key);
    }

    function withdrawAdminShare(uint64 projectId, bool inETH, Whitelist memory users) external onlyOnce(projectId, inETH) {
        require(tx.accounts.dataAccount.key == owner() || isOwner[tx.accounts.dataAccount.key], "!Owner");
        require(getSigner(users) == designatedSigner, '!Signer');
        require(users.userAddress == tx.accounts.dataAccount.key, '!User');
        require(!nonceStore[users.userAddress][users.timestamp], '!Nonce Used');
        nonceStore[users.userAddress][users.timestamp] = true;
        if (!inETH) {
            uint64 amountToWithdraw = projectCollectedInUSDT[projectId];
            amountToWithdraw = (amountToWithdraw * (users.platformFee)) / 100;
            onlyOncePerProject[projectId][inETH] = true;
            SafeERC20Upgradeable.safeTransfer(usdt, tx.accounts.dataAccount.key, amountToWithdraw);
        } else {
            uint64 amountToWithdraw = projectTotalCollectedInETH[projectId];
            amountToWithdraw = (amountToWithdraw * (users.platformFee)) / 100;
            onlyOncePerProject[projectId][inETH] = true;
            tx.accounts.dataAccount.lamports += amountToWithdraw;
        }
    }

    function settleProjectOwnerFunds(Whitelist memory users) external nonReentrant {
        require(tx.accounts.dataAccount.key == owner() || isOwner[tx.accounts.dataAccount.key], "!Owner");
        require(getSigner(users) == designatedSigner, 'Invalid Signer');
        require(!nonceStore[users.userAddress][users.timestamp], '!Nonce Used');
        nonceStore[users.userAddress][users.timestamp] = true;
        uint64 _amountToWithdraw = users.amount;
        if (!users.inETH) {
            fundsWithdrawn[users.projectId][users.inETH] += _amountToWithdraw;
            uint64 deducedAmount = projectCollectedInUSDT[users.projectId] - (projectCollectedInUSDT[users.projectId] * (users.platformFee)) / 100;
            require(deducedAmount >= fundsWithdrawn[users.projectId][users.inETH], "check deducedAmount");
            projectCollectedInUSDT[users.projectId] -= _amountToWithdraw;
            SafeERC20Upgradeable.safeTransfer(usdt, users.userAddress, _amountToWithdraw);
        } else {
            fundsWithdrawn[users.projectId][users.inETH] += _amountToWithdraw;
            uint64 deducedAmount = projectTotalCollectedInETH[users.projectId] - (projectTotalCollectedInETH[users.projectId] * (users.platformFee)) / 100;
            require(deducedAmount >= fundsWithdrawn[users.projectId][users.inETH], "check deducedAmount");
            projectTotalCollectedInETH[users.projectId] -= _amountToWithdraw;
            tx.accounts.dataAccount.lamports -= _amountToWithdraw;
        }
    }

    function refund(Whitelist memory users) external nonReentrant {
        require(getSigner(users) == designatedSigner, 'Invalid Signer');
        require(tx.accounts.dataAccount.key == users.userAddress, "not a user");
        require(!nonceStore[users.userAddress][users.timestamp], '!Nonce Used');
        nonceStore[users.userAddress][users.timestamp] = true;
        uint64 amount = (users.amount * 10**6 / 100);
        if (whichCurreny[users.userAddress][users.projectId] == 1) {
            require(!refundAmountInUSDT[users.userAddress][users.projectId], "!Refund completed");
            require(investorInvestedAmountPerProjectInUSDT[users.projectId][users.userAddress] >= amount, "Invalid Amount to retrieve");
            investorInvestedAmountPerProjectInUSDT[users.projectId][users.userAddress] -= amount;
            projectCollectedInUSDT[users.projectId] -= amount;
            refundAmountInUSDT[users.userAddress][users.projectId] = true;
            SafeERC20Upgradeable.safeTransfer(usdt, users.userAddress, amount);
        } else {
            require(!refundAmountInETH[users.userAddress][users.projectId], "!Refund completed");
            require(investorInvestedAmountPerProjectInETH[users.projectId][users.userAddress] >= amount, 'Invalid Amount to retrieve');
            investorInvestedAmountPerProjectInETH[users.projectId][users.userAddress] -= amount;
            projectTotalCollectedInETH[users.projectId] -= amount;
            refundAmountInETH[users.userAddress][users.projectId] = true;
            tx.accounts.dataAccount.lamports -= amount;
        }
    }

    function withdrawAllFundsOfAProject(uint64 projectID) external {
        require(tx.accounts.dataAccount.key == owner() || isOwner[tx.accounts.dataAccount.key], "!Owner");
        uint64 _usdtAmount = projectCollectedInUSDT[projectID];
        uint64 _ethAmount = projectTotalCollectedInETH[projectID];
        require(_usdtAmount > 0 || _ethAmount > 0, '!Funds');
        SafeERC20Upgradeable.safeTransfer(usdt, tx.accounts.dataAccount.key, _usdtAmount);
        projectTotalCollectedInETH[projectID] -= _ethAmount;
        projectCollectedInUSDT[projectID] -= _usdtAmount;
        tx.accounts.dataAccount.lamports += _ethAmount;
    }

    function setplatformFee(uint64 projectId, uint64 _platformFee) external {
        require(tx.accounts.dataAccount.key == owner() || isOwner[tx.accounts.dataAccount.key], "!Owner");
        PlatformFee[projectId][_platformFee] = true;
    }

    function refundFromAdminInETH(uint64 projectId, uint64 slotId) external {
        require(tx.accounts.dataAccount.key == owner() || isOwner[tx.accounts.dataAccount.key], "!Owner");
        uint64 numberOfUsers = uint64(projectUsersInETH[projectId][slotId].length);
        for (uint64 i = 0; i < numberOfUsers; i++) {
            address user = projectUsersInETH[projectId][slotId][i];
            require(!isRefundedInETH[user][projectId], 'Already refunded');
            isRefundedInETH[user][projectId] = true;
            uint64 invested = investorInvestedAmountPerProjectInETH[projectId][user];
            projectTotalCollectedInETH[projectId] -= invested;
            investorInvestedAmountPerProjectInETH[projectId][user] -= invested;
            tx.accounts.dataAccount.lamports -= invested;
        }
    }

    function refundFromAdminInUSDT(uint64 projectId, uint64 slotId) external {
        require(tx.accounts.dataAccount.key == owner() || isOwner[tx.accounts.dataAccount.key], "!Owner");
        uint64 numberOfUsers = uint64(projectUsersInUSDT[projectId][slotId].length);
        for (uint64 i = 0; i < numberOfUsers; i++) {
            address user = projectUsersInUSDT[projectId][slotId][i];
            require(!isRefundedInUSDT[user][projectId], 'Already refunded');
            isRefundedInUSDT[user][projectId] = true;
            uint64 invested = investorInvestedAmountPerProjectInUSDT[projectId][user];
            refundAmunt += invested;
            projectCollectedInUSDT[projectId] -= invested;
            investorInvestedAmountPerProjectInUSDT[projectId][user] -= invested;
            SafeERC20Upgradeable.safeTransfer(usdt, user, invested);
        }
    }

    function initialize(address _address) external initializer {
        usdt = _address;
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    function totalInvestorsInProject(uint64 projectId, uint64 slotId) external view returns (uint64, uint64) {
        uint64 inETH = uint64(projectUsersInETH[projectId][slotId].length);
        uint64 inUSDT = uint64(projectUsersInUSDT[projectId][slotId].length);
        return (inETH, inUSDT);
    }
}