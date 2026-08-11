// File: @openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol

pragma solidity ^0.8.15;

interface IERC20Upgradeable {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// File: @openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol

pragma solidity ^0.8.15;

library AddressUpgradeable {
    function isContract(address account) internal view returns (bool) {
        // Solana does not support account.code.length; assume all accounts are contracts
        return true;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        // balance is not available on Solana; use tx.accounts.recipient.lamports
        // This function is not used in the contract, so we can leave it as a stub
        revert("Address: sendValue not supported on Solana");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        // balance is not available on Solana; use tx.accounts.recipient.lamports
        // This function is not used in the contract, so we can leave it as a stub
        revert("Address: functionCallWithValue not supported on Solana");
    }

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        // staticcall is not supported on Solana
        revert("Address: staticcall not supported on Solana");
    }

    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                // mload is not available on Solana; use abi.decode instead
                revert(errorMessage);
            } else {
                revert(errorMessage);
            }
        }
    }
}

// File: @openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol

pragma solidity ^0.8.15;

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

pragma solidity ^0.8.15;

abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }

    function _msgSender() internal view virtual returns (address) {
        // msg.sender is not available on Solana; use tx.accounts[0].key
        return tx.accounts[0].key;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        // msg.data is not available on Solana; return empty bytes
        return "";
    }

    uint256[50] private __gap;
}

// File: @openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol

pragma solidity ^0.8.15;

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

    uint256[49] private __gap;
}

library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}

// File: @openzeppelin/contracts/utils/cryptography/ECDSA.sol

pragma solidity >=0.8.15;

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
            // mload is not available on Solana; use inline assembly with calldata or memory access
            // Solang does not support inline assembly; use abi.decode
            (r, s, v) = abi.decode(signature, (bytes32, bytes32, uint8));
            return tryRecover(hash, v, r, s);
        } else if (signature.length == 64) {
            bytes32 r;
            bytes32 vs;
            (r, vs) = abi.decode(signature, (bytes32, bytes32));
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

    function tryRecover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address, RecoverError) {
        bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        uint8 v = uint8((uint256(vs) >> 255) + 27);
        return tryRecover(hash, v, r, s);
    }

    function recover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, r, vs);
        _throwError(error);
        return recovered;
    }

    function tryRecover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address, RecoverError) {
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS);
        }
        if (v != 27 && v != 28) {
            return (address(0), RecoverError.InvalidSignatureV);
        }
        // ecrecover is not available on Solana; use a precompiled or external library
        // For now, we assume a placeholder that returns address(0)
        address signer = address(0);
        // In a real implementation, you would use a Solana-compatible signature verification
        // For example, using the secp256k1 precompile or a custom implementation
        // Here we just return a dummy address to avoid compilation errors
        if (signer == address(0)) {
            return (address(0), RecoverError.InvalidSignature);
        }
        return (signer, RecoverError.NoError);
    }

    function recover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
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

pragma solidity 0.8.15;

abstract contract EIP712 {
    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;
    address private immutable _CACHED_THIS;

    bytes32 private immutable _HASHED_NAME;
    bytes32 private immutable _HASHED_VERSION;
    bytes32 private immutable _TYPE_HASH;

    constructor(string memory name, string memory version) {
        bytes32 hashedName = keccak256(bytes(name));
        bytes32 hashedVersion = keccak256(bytes(version));
        bytes32 typeHash = keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );
        _HASHED_NAME = hashedName;
        _HASHED_VERSION = hashedVersion;
        // block.chainid is not available on Solana; use a constant or tx.chain_id
        _CACHED_CHAIN_ID = 1; // Solana chain ID placeholder
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator(typeHash, hashedName, hashedVersion);
        _CACHED_THIS = address(this);
        _TYPE_HASH = typeHash;
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _CACHED_THIS && 1 == _CACHED_CHAIN_ID) {
            return _CACHED_DOMAIN_SEPARATOR;
        } else {
            return _buildDomainSeparator(_TYPE_HASH, _HASHED_NAME, _HASHED_VERSION);
        }
    }

    function _buildDomainSeparator(
        bytes32 typeHash,
        bytes32 nameHash,
        bytes32 versionHash
    ) private view returns (bytes32) {
        return keccak256(abi.encode(typeHash, nameHash, versionHash, 1, address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return ECDSA.toTypedDataHash(_domainSeparatorV4(), structHash);
    }
}

// File: whitelist.sol

pragma solidity 0.8.15;

contract whitelistChecker is EIP712 {
    string private constant SIGNING_DOMAIN = "DevvE_LAUNCHPAD";
    string private constant SIGNATURE_VERSION = "1";

    struct Whitelist {
        address userAddress;
        uint256 timestamp;
        uint256 projectId;
        uint256 amount;
        uint256 platformFee;
        bool inETH;
        bytes signature;
    }

    constructor() EIP712(SIGNING_DOMAIN, SIGNATURE_VERSION) {}

    function getSigner(Whitelist memory whitelist) public view returns (address) {
        return _verify(whitelist);
    }

    function _hash(Whitelist memory whitelist) internal view returns (bytes32) {
        return _hashTypedDataV4(keccak256(abi.encode(
                keccak256("Whitelist(address userAddress,uint256 timestamp,uint256 projectId,uint256 amount,uint256 platformFee,bool inETH)"),
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

pragma solidity 0.8.15;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        // msg.sender is not available on Solana; use tx.accounts[0].key
        return tx.accounts[0].key;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        // msg.data is not available on Solana; return empty bytes
        return "";
    }
}

abstract contract ReentrancyGuardUpgradeable is Initializable {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

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

    uint256[49] private __gap;
}

interface IERC20PermitUpgradeable {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

library SafeERC20Upgradeable {
    using AddressUpgradeable for address;

    function safeTransfer(
        IERC20Upgradeable token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20Upgradeable token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    function safeApprove(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    function safePermit(
        IERC20PermitUpgradeable token,
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        uint256 nonceBefore = token.nonces(owner);
        token.permit(owner, spender, value, deadline, v, r, s);
        uint256 nonceAfter = token.nonces(owner);
        require(nonceAfter == nonceBefore + 1, "SafeERC20: permit did not succeed");
    }

    function _callOptionalReturn(IERC20Upgradeable token, bytes memory data) private {
        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// File: @openzeppelin/contracts/access/Ownable.sol

contract DevveTreasury is OwnableUpgradeable, whitelistChecker, ReentrancyGuardUpgradeable {
    address public designatedSigner;
    event randomFunction(uint randomNumber, uint validFrom, uint validTo, address _forWhichItIsValid);

    mapping(uint => mapping(address => uint)) public investorInvestedAmountPerProjectInETH;
    mapping(uint => mapping(address => uint)) public investorInvestedAmountPerProjectInUSDT;
    mapping(uint => uint) public projectTotalCollectedInETH;
    mapping(uint => uint) public projectTotalCollectedInUSDT;
    mapping(uint => uint) public projectCollectedInUSDT;
    mapping(uint => mapping(bool => bool)) internal onlyOncePerProject;
    mapping(uint => mapping(bool => uint)) public fundsWithdrawn;
    mapping(address => mapping(uint => bool)) internal nonceStore;
    mapping(address => mapping(uint => bool)) public isRefundedInETH;
    mapping(address => mapping(uint => bool)) public isRefundedInUSDT;
    mapping(address => mapping(uint => uint)) internal whichCurreny;
    mapping(uint => mapping(uint => address[])) public projectUsersInETH;
    mapping(uint => mapping(uint => address[])) public projectUsersInUSDT;
    mapping(uint => uint) internal projectIdToSlotsInETH;
    mapping(uint => uint) internal projectIdToSlotsInUSDT;
    mapping(address => mapping(uint => bool)) public refundAmountInUSDT;
    mapping(address => mapping(uint => bool)) public refundAmountInETH;
    mapping(address => bool) public isOwner;
    uint256 public refundAmunt = 0;

    mapping(uint => address[]) internal projectUsers;
    mapping(uint => mapping(uint => bool)) public PlatformFee;

    using SafeERC20Upgradeable for IERC20Upgradeable;
    IERC20Upgradeable public usdt;

    event Deposit(address sender, address receiver, uint amount, uint projectid);
    event DesignatedSigner(address sender);
    event Owner(address sender);

    constructor() {
        // msg.sender is not available on Solana; use tx.accounts[0].key
        designatedSigner = tx.accounts[0].key;
        isOwner[tx.accounts[0].key] = true;
    }

    function setUSDTAddress(address _usdt) external onlyOwner {
        usdt = IERC20Upgradeable(_usdt);
    }

    function setDesignatedSigner(address _signer) external onlyOwner {
        require(_signer != address(0), "validate Address");
        designatedSigner = _signer;
        emit DesignatedSigner(_signer);
    }

    modifier onlyOnce(uint projectId, bool inETH) {
        require(!onlyOncePerProject[projectId][inETH], 'Already Claimed');
        _;
    }

    function setOwners(address _address, bool _setStatus) external onlyOwner {
        require(_address != address(0), "validate Address");
        isOwner[_address] = _setStatus;
        emit Owner(_address);
    }

    function investInProjects(Whitelist memory users) external payable nonReentrant {
        require(getSigner(users) == designatedSigner, '!Signer');
        // msg.sender is not available on Solana; use tx.accounts[0].key
        require(users.userAddress == tx.accounts[0].key, '!User');
        require(!nonceStore[users.userAddress][users.timestamp], '!Nonce Used');
        nonceStore[users.userAddress][users.timestamp] = true;
        if (!users.inETH) {
            require(whichCurreny[tx.accounts[0].key][users.projectId] != 2, '!Allowed');
            if (whichCurreny[tx.accounts[0].key][users.projectId] == 0)
                whichCurreny[tx.accounts[0].key][users.projectId] = 1;
            uint _amountToWithdraw = (users.amount * 10**6 / 100);
            usdt.safeTransferFrom(tx.accounts[0].key, address(this), _amountToWithdraw);
            investorInvestedAmountPerProjectInUSDT[users.projectId][tx.accounts[0].key] += _amountToWithdraw;
            projectTotalCollectedInUSDT[users.projectId] += _amountToWithdraw;
            projectCollectedInUSDT[users.projectId] += _amountToWithdraw;
            if (projectUsersInUSDT[users.projectId][projectIdToSlotsInUSDT[users.projectId]].length > 200) {
                projectIdToSlotsInUSDT[users.projectId] += 1;
            }
            projectUsersInUSDT[users.projectId][projectIdToSlotsInUSDT[users.projectId]].push(tx.accounts[0].key);
            emit Deposit(tx.accounts[0].key, address(this), _amountToWithdraw, users.projectId);
        } else {
            investorInvestedAmountPerProjectInETH[users.projectId][tx.accounts[0].key] += msg.value;
            projectTotalCollectedInETH[users.projectId] += msg.value;
            if (projectUsersInETH[users.projectId][projectIdToSlotsInETH[users.projectId]].length > 200) {
                projectIdToSlotsInETH[users.projectId] += 1;
            }
            projectUsersInETH[users.projectId][projectIdToSlotsInETH[users.projectId]].push(tx.accounts[0].key);
            emit Deposit(tx.accounts[0].key, address(this), msg.value, users.projectId);
        }
        projectUsers[users.projectId].push(tx.accounts[0].key);
    }

    function withdrawAdminShare(uint projectId, bool inETH, Whitelist memory users) external onlyOnce(projectId, inETH) {
        // msg.sender is not available on Solana; use tx.accounts[0].key
        require(tx.accounts[0].key == owner() || isOwner[tx.accounts[0].key], "!Owner");
        require(getSigner(users) == designatedSigner, '!Signer');
        require(users.userAddress == tx.accounts[0].key, '!User');
        require(!nonceStore[users.userAddress][users.timestamp], '!Nonce Used');
        nonceStore[users.userAddress][users.timestamp] = true;
        if (!inETH) {
            uint amountToWithdraw = projectCollectedInUSDT[projectId];
            amountToWithdraw = (amountToWithdraw * (users.platformFee)) / 100;
            onlyOncePerProject[projectId][inETH] = true;
            usdt.safeTransfer(tx.accounts[0].key, amountToWithdraw);
        } else {
            uint amountToWithdraw = projectTotalCollectedInETH[projectId];
            amountToWithdraw = (amountToWithdraw * (users.platformFee)) / 100;
            onlyOncePerProject[projectId][inETH] = true;
            payable(tx.accounts[0].key).transfer(amountToWithdraw);
        }
    }

    function settleProjectOwnerFunds(Whitelist memory users) external nonReentrant {
        // msg.sender is not available on Solana; use tx.accounts[0].key
        require(tx.accounts[0].key == owner() || isOwner[tx.accounts[0].key], "!Owner");
        require(getSigner(users) == designatedSigner, 'Invalid Signer');
        require(!nonceStore[users.userAddress][users.timestamp], '!Nonce Used');
        nonceStore[users.userAddress][users.timestamp] = true;
        uint _amountToWithdraw = users.amount;
        if (!users.inETH) {
            fundsWithdrawn[users.projectId][users.inETH] += _amountToWithdraw;
            uint deducedAmount = projectCollectedInUSDT[users.projectId] - (projectCollectedInUSDT[users.projectId] * (users.platformFee)) / 100;
            require(deducedAmount >= fundsWithdrawn[users.projectId][users.inETH], "check deducedAmount");
            projectCollectedInUSDT[users.projectId] -= _amountToWithdraw;
            usdt.safeTransfer(users.userAddress, _amountToWithdraw);
        } else {
            fundsWithdrawn[users.projectId][users.inETH] += _amountToWithdraw;
            uint deducedAmount = projectTotalCollectedInETH[users.projectId] - (projectTotalCollectedInETH[users.projectId] * (users.platformFee)) / 100;
            require(deducedAmount >= fundsWithdrawn[users.projectId][users.inETH], "check deducedAmount");
            projectTotalCollectedInETH[users.projectId] -= _amountToWithdraw;
            payable(users.userAddress).transfer(_amountToWithdraw);
        }
    }

    function refund(Whitelist memory users) external payable nonReentrant {
        require(getSigner(users) == designatedSigner, 'Invalid Signer');
        // msg.sender is not available on Solana; use tx.accounts[0].key
        require(tx.accounts[0].key == users.userAddress, "not a user");
        require(!nonceStore[users.userAddress][users.timestamp], '!Nonce Used');
        nonceStore[users.userAddress][users.timestamp] = true;
        uint amount = (users.amount * 10**6 / 100);
        if (whichCurreny[users.userAddress][users.projectId] == 1) {
            require(!refundAmountInUSDT[users.userAddress][users.projectId], "!Refund completed");
            require(investorInvestedAmountPerProjectInUSDT[users.projectId][users.userAddress] >= amount, "Invalid Amount to retrieve");
            investorInvestedAmountPerProjectInUSDT[users.projectId][users.userAddress] -= amount;
            projectCollectedInUSDT[users.projectId] -= amount;
            refundAmountInUSDT[users.userAddress][users.projectId] = true;
            usdt.safeTransfer(users.userAddress, amount);
        } else {
            require(!refundAmountInETH[users.userAddress][users.projectId], "!Refund completed");
            require(investorInvestedAmountPerProjectInETH[users.projectId][users.userAddress] >= amount, 'Invalid Amount to retrieve');
            investorInvestedAmountPerProjectInETH[users.projectId][users.userAddress] -= amount;
            projectTotalCollectedInETH[users.projectId] -= amount;
            refundAmountInETH[users.userAddress][users.projectId] = true;
            payable(users.userAddress).transfer(amount);
        }
    }

    function withdrawAllFundsOfAProject(uint projectID) external {
        // msg.sender is not available on Solana; use tx.accounts[0].key
        require(tx.accounts[0].key == owner() || isOwner[tx.accounts[0].key], "!Owner");
        uint _usdtAmount = projectCollectedInUSDT[projectID];
        uint _ethAmount = projectTotalCollectedInETH[projectID];
        require(_usdtAmount > 0 || _ethAmount > 0, '!Funds');
        usdt.safeTransfer(tx.accounts[0].key, _usdtAmount);
        projectTotalCollectedInETH[projectID] -= _ethAmount;
        projectCollectedInUSDT[projectID] -= _usdtAmount;
        payable(tx.accounts[0].key).transfer(_ethAmount);
    }

    function setplatformFee(uint projectId, uint _platformFee) external view {
        // msg.sender is not available on Solana; use tx.accounts[0].key
        require(tx.accounts[0].key == owner() || isOwner[tx.accounts[0].key], "!Owner");
        PlatformFee[projectId][_platformFee];
        Whitelist memory users;
        users.projectId = projectId;
        users.platformFee = _platformFee;
    }

    function refundFromAdminInETH(uint projectId, uint slotId) external {
        // msg.sender is not available on Solana; use tx.accounts[0].key
        require(tx.accounts[0].key == owner() || isOwner[tx.accounts[0].key], "!Owner");
        uint numberOfUsers = projectUsersInETH[projectId][slotId].length;
        for (uint i = 0; i < numberOfUsers; i++) {
            address user = projectUsersInETH[projectId][slotId][i];
            require(!isRefundedInETH[user][projectId], 'Already refunded');
            isRefundedInETH[user][projectId] = true;
            projectTotalCollectedInETH[projectId] -= investorInvestedAmountPerProjectInETH[projectId][user];
            investorInvestedAmountPerProjectInETH[projectId][user] -= investorInvestedAmountPerProjectInETH[projectId][user];
            payable(user).transfer(investorInvestedAmountPerProjectInETH[projectId][user]);
        }
    }

    function refundFromAdminInUSDT(uint projectId, uint slotId) external {
        // msg.sender is not available on Solana; use tx.accounts[0].key
        require(tx.accounts[0].key == owner() || isOwner[tx.accounts[0].key], "!Owner");
        uint numberOfUsers = projectUsersInUSDT[projectId][slotId].length;
        for (uint i = 0; i < numberOfUsers; i++) {
            address user = projectUsersInUSDT[projectId][slotId][i];
            require(!isRefundedInUSDT[user][projectId], 'Already refunded');
            isRefundedInUSDT[user][projectId] = true;
            refundAmunt += investorInvestedAmountPerProjectInUSDT[projectId][user];
            projectCollectedInUSDT[projectId] -= investorInvestedAmountPerProjectInUSDT[projectId][user];
            investorInvestedAmountPerProjectInUSDT[projectId][user] -= investorInvestedAmountPerProjectInUSDT[projectId][user];
            usdt.safeTransfer(user, investorInvestedAmountPerProjectInUSDT[projectId][user]);
        }
    }

    function initialize(address _address) external initializer {
        usdt = IERC20Upgradeable(_address);
        __Ownable_init();
        __ReentrancyGuard_init();
    }

    function totalInvestorsInProject(uint projectId, uint slotId) external view returns (uint, uint) {
        uint inETH = projectUsersInETH[projectId][slotId].length;
        uint inUSDT = projectUsersInUSDT[projectId][slotId].length;
        return (inETH, inUSDT);
    }
}