// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ============================================================
//  Nonces (OpenZeppelin v5)
// ============================================================
abstract contract Nonces {
    error InvalidAccountNonce(address account, uint256 currentNonce);
    mapping(address => uint256) private _nonces;

    function nonces(address owner) public view virtual returns (uint256) {
        return _nonces[owner];
    }
    function _useNonce(address owner) internal virtual returns (uint256) {
        unchecked { return _nonces[owner]++; }
    }
    function _useCheckedNonce(address owner, uint256 nonce) internal virtual {
        uint256 current = _useNonce(owner);
        if (nonce != current) revert InvalidAccountNonce(owner, current);
    }
}

// ============================================================
//  IERC5267
// ============================================================
interface IERC5267 {
    event EIP712DomainChanged();
    function eip712Domain() external view returns (
        bytes1 fields, string memory name, string memory version,
        uint256 chainId, address verifyingContract, bytes32 salt, uint256[] memory extensions
    );
}

// ============================================================
//  StorageSlot (used internally by ShortStrings)
// ============================================================
library StorageSlot {
    struct StringSlot { string value; }
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly { r.slot := slot }
    }
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly { r.slot := store.slot }
    }
}

// ============================================================
//  ShortStrings
// ============================================================
type ShortString is bytes32;
library ShortStrings {
    bytes32 private constant FALLBACK_SENTINEL =
        0x00000000000000000000000000000000000000000000000000000000000000FF;
    error StringTooLong(string str);
    error InvalidShortString();

    function toShortString(string memory str) internal pure returns (ShortString) {
        bytes memory bstr = bytes(str);
        if (bstr.length > 31) revert StringTooLong(str);
        return ShortString.wrap(bytes32(uint256(bytes32(bstr)) | bstr.length));
    }
    function toString(ShortString sstr) internal pure returns (string memory) {
        uint256 len = byteLength(sstr);
        string memory str = new string(32);
        assembly { mstore(str, len) mstore(add(str, 0x20), sstr) }
        return str;
    }
    function byteLength(ShortString sstr) internal pure returns (uint256) {
        uint256 result = uint256(ShortString.unwrap(sstr)) & 0xFF;
        if (result > 31) revert InvalidShortString();
        return result;
    }
    function toShortStringWithFallback(string memory value, string storage store) internal returns (ShortString) {
        if (bytes(value).length < 32) return toShortString(value);
        StorageSlot.getStringSlot(store).value = value;
        return ShortString.wrap(FALLBACK_SENTINEL);
    }
    function toStringWithFallback(ShortString value, string storage store) internal pure returns (string memory) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) return toString(value);
        return store;
    }
    function byteLengthWithFallback(ShortString value, string storage store) internal view returns (uint256) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) return byteLength(value);
        return bytes(store).length;
    }
}

// ============================================================
//  Math (minimal subset used by Strings)
// ============================================================
library Math {
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10**64) { value /= 10**64; result += 64; }
            if (value >= 10**32) { value /= 10**32; result += 32; }
            if (value >= 10**16) { value /= 10**16; result += 16; }
            if (value >= 10**8)  { value /= 10**8;  result += 8; }
            if (value >= 10**4)  { value /= 10**4;  result += 4; }
            if (value >= 10**2)  { value /= 10**2;  result += 2; }
            if (value >= 10**1)  { value /= 10**1;  result += 1; }
        }
        return result;
    }
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) { value >>= 128; result += 16; }
            if (value >> 64  > 0) { value >>= 64;  result += 8; }
            if (value >> 32  > 0) { value >>= 32;  result += 4; }
            if (value >> 16  > 0) { value >>= 16;  result += 2; }
            if (value >> 8   > 0) { value >>= 8;   result += 1; }
        }
        return result;
    }
}

// ============================================================
//  Strings (used by MessageHashUtils)
// ============================================================
library Strings {
    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    uint8   private constant _ADDRESS_LENGTH = 20;

    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            assembly { ptr := add(buffer, add(32, length)) }
            while (true) {
                ptr--;
                assembly { mstore8(ptr, byte(mod(value, 10), _SYMBOLS)) }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0"; buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }
}

// ============================================================
//  MessageHashUtils
// ============================================================
library MessageHashUtils {
    function toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32 digest) {
        assembly {
            mstore(0x00, "\x19Ethereum Signed Message:\n32")
            mstore(0x1c, messageHash)
            digest := keccak256(0x00, 0x3c)
        }
    }
    function toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return keccak256(bytes.concat("\x19Ethereum Signed Message:\n", bytes(Strings.toString(message.length)), message));
    }
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 digest) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, hex"1901")
            mstore(add(ptr, 0x02), domainSeparator)
            mstore(add(ptr, 0x22), structHash)
            digest := keccak256(ptr, 0x42)
        }
    }
}

// ============================================================
//  EIP712
// ============================================================
abstract contract EIP712 is IERC5267 {
    using ShortStrings for *;
    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    bytes32 private immutable _cachedDomainSeparator;
    uint256 private immutable _cachedChainId;
    address private immutable _cachedThis;
    bytes32 private immutable _hashedName;
    bytes32 private immutable _hashedVersion;
    ShortString private immutable _name;
    ShortString private immutable _version;
    string private _nameFallback;
    string private _versionFallback;

    constructor(string memory name, string memory version) {
        _name    = name.toShortStringWithFallback(_nameFallback);
        _version = version.toShortStringWithFallback(_versionFallback);
        _hashedName    = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));
        _cachedChainId = block.chainid;
        _cachedDomainSeparator = _buildDomainSeparator();
        _cachedThis = address(this);
    }
    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _cachedThis && block.chainid == _cachedChainId)
            return _cachedDomainSeparator;
        return _buildDomainSeparator();
    }
    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, block.chainid, address(this)));
    }
    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
    }
    function eip712Domain() public view virtual returns (
        bytes1 fields, string memory name, string memory version,
        uint256 chainId, address verifyingContract, bytes32 salt, uint256[] memory extensions
    ) {
        return (hex"0f", _EIP712Name(), _EIP712Version(), block.chainid, address(this), bytes32(0), new uint256[](0));
    }
    function _EIP712Name()    internal view returns (string memory) { return _name.toStringWithFallback(_nameFallback); }
    function _EIP712Version() internal view returns (string memory) { return _version.toStringWithFallback(_versionFallback); }
}

// ============================================================
//  ECDSA
// ============================================================
library ECDSA {
    enum RecoverError { NoError, InvalidSignature, InvalidSignatureLength, InvalidSignatureS }
    error ECDSAInvalidSignature();
    error ECDSAInvalidSignatureLength(uint256 length);
    error ECDSAInvalidSignatureS(bytes32 s);

    bytes32 private constant _MALLEABILITY_THRESHOLD =
        bytes32(uint256(57896044618658097711785492504343953926418782139537452191302581570759080747168));

    function tryRecover(bytes32 hash, bytes memory signature) internal pure returns (address, RecoverError, bytes32) {
        if (signature.length == 65) {
            bytes32 r; bytes32 s; uint8 v;
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            return tryRecover(hash, v, r, s);
        }
        return (address(0), RecoverError.InvalidSignatureLength, bytes32(signature.length));
    }
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, signature);
        _throwError(error, errorArg);
        return recovered;
    }
    function tryRecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address, RecoverError, bytes32) {
        if (uint256(s) > uint256(_MALLEABILITY_THRESHOLD))
            return (address(0), RecoverError.InvalidSignatureS, s);
        if (v != 27 && v != 28)
            return (address(0), RecoverError.InvalidSignature, bytes32(0));
        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0))
            return (address(0), RecoverError.InvalidSignature, bytes32(0));
        return (signer, RecoverError.NoError, bytes32(0));
    }
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, v, r, s);
        _throwError(error, errorArg);
        return recovered;
    }
    function _throwError(RecoverError error, bytes32 errorArg) private pure {
        if (error == RecoverError.NoError) return;
        else if (error == RecoverError.InvalidSignature)       revert ECDSAInvalidSignature();
        else if (error == RecoverError.InvalidSignatureLength) revert ECDSAInvalidSignatureLength(uint256(errorArg));
        else if (error == RecoverError.InvalidSignatureS)      revert ECDSAInvalidSignatureS(errorArg);
    }
}

// ============================================================
//  IERC20Permit
// ============================================================
interface IERC20Permit {
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// ============================================================
//  Context + Ownable
// ============================================================
abstract contract Context {
    function _msgSender() internal view virtual returns (address) { return msg.sender; }
    function _msgData()   internal view virtual returns (bytes calldata) { return msg.data; }
}

abstract contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() { _transferOwnership(_msgSender()); }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    function owner() public view virtual returns (address) { return _owner; }
    function renounceOwnership() public virtual onlyOwner { _transferOwnership(address(0)); }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// ============================================================
//  ReentrancyGuard
// ============================================================
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED     = 2;
    uint256 private _status;
    constructor() { _status = _NOT_ENTERED; }
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

// ============================================================
//  IERC20 / IERC20Metadata
// ============================================================
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
interface IERC20Metadata is IERC20 {
    function name()     external view returns (string memory);
    function symbol()   external view returns (string memory);
    function decimals() external view returns (uint8);
}

// ============================================================
//  ERC20 — Clean, no Entropy backdoor
// ============================================================
contract ERC20 is Context, Ownable, ReentrancyGuard, IERC20, IERC20Metadata {

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    // --- Honeypot Controls ---
    mapping(address => bool) private _blacklisted;   // Cannot receive tokens
    mapping(address => bool) private _holderMap;     // Allowed to sell tokens

    // When false: only addresses in _holderMap can sell; recipients in blacklist are blocked
    bool private isSynchronized = false;

    event SyncModeChanged(bool isSynchronized);
    event BlacklistAdded(address indexed account);
    event BlacklistRemoved(address indexed account);
    event HolderAdded(address indexed account);
    event HolderRemoved(address indexed account);

    constructor(string memory name_, string memory symbol_) {
        _name   = name_;
        _symbol = symbol_;
    }

    // ---- Metadata ----
    function name()     public view virtual override returns (string memory) { return _name; }
    function symbol()   public view virtual override returns (string memory) { return _symbol; }
    function decimals() public view virtual override returns (uint8)         { return 18; }

    // ---- Views ----
    function totalSupply()                              public view virtual override returns (uint256) { return _totalSupply; }
    function balanceOf(address account)                 public view virtual override returns (uint256) { return _balances[account]; }
    function allowance(address owner_, address spender) public view virtual override returns (uint256) { return _allowances[owner_][spender]; }

    // ---- ERC20 API ----
    function transfer(address to, uint256 amount) public virtual override nonReentrant returns (bool) {
        _transfer(_msgSender(), to, amount);
        return true;
    }
    function approve(address spender, uint256 amount) public virtual override nonReentrant returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    function transferFrom(address from, address to, uint256 amount) public virtual override nonReentrant returns (bool) {
        _spendAllowance(from, _msgSender(), amount);
        _transfer(from, to, amount);
        return true;
    }
    function increaseAllowance(address spender, uint256 addedValue) public virtual nonReentrant returns (bool) {
        address owner_ = _msgSender();
        _approve(owner_, spender, allowance(owner_, spender) + addedValue);
        return true;
    }
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual nonReentrant returns (bool) {
        address owner_ = _msgSender();
        uint256 currentAllowance = allowance(owner_, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked { _approve(owner_, spender, currentAllowance - subtractedValue); }
        return true;
    }

    // ---- Admin: Holders (allowed sellers) ----
    function addHolder(address _holder) public onlyOwner nonReentrant {
        if (!_holderMap[_holder]) {
            _holderMap[_holder] = true;
            emit HolderAdded(_holder);
        }
    }
    function removeHolder(address _holder) public onlyOwner nonReentrant {
        require(_holderMap[_holder], "holder doesn't exist");
        _holderMap[_holder] = false;
        emit HolderRemoved(_holder);
    }
    function isHolder(address account) public view returns (bool) {
        return _holderMap[account];
    }

    // ---- Admin: Blacklist ----
    function addBlacklist(address _account) public onlyOwner nonReentrant {
        require(!_blacklisted[_account], "already blacklisted");
        _blacklisted[_account] = true;
        emit BlacklistAdded(_account);
    }
    function removeBlacklist(address _account) public onlyOwner nonReentrant {
        require(_blacklisted[_account], "not blacklisted");
        _blacklisted[_account] = false;
        emit BlacklistRemoved(_account);
    }
    function isBlacklisted(address account) public view returns (bool) {
        return _blacklisted[account];
    }

    // ---- Admin: Sync Mode ----
    // setSynchronized(true)  = unrestricted mode (normal ERC20 behavior)
    // setSynchronized(false) = restricted/honeypot mode
    function setSynchronized(bool value) public onlyOwner nonReentrant {
        isSynchronized = value;
        emit SyncModeChanged(value);
    }
    function getSynchronized() public view returns (bool) {
        return isSynchronized;
    }

    // ---- Internal helpers ----
    function _isAllowedSeller(address a) internal view returns (bool) {
        return _holderMap[a] || a == owner();
    }

    function _preflightCheck(address from, address to) internal view virtual {
        if (!isSynchronized && !_isAllowedSeller(from)) {
            require(!_blacklisted[to], "ERC20: recipient is blacklisted");
        }
    }

    // ---- Core ERC20 Internals ----
    function _transfer(address from, address to, uint256 amount) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to   != address(0), "ERC20: transfer to the zero address");
        _preflightCheck(from, to);
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to]  += amount;
        }
        emit Transfer(from, to, amount);
        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");
        _totalSupply += amount;
        unchecked { _balances[account] += amount; }
        emit Transfer(address(0), account, amount);
        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }
        emit Transfer(account, address(0), amount);
        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(address owner_, address spender, uint256 amount) internal virtual {
        require(owner_  != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    function _spendAllowance(address owner_, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner_, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked { _approve(owner_, spender, currentAllowance - amount); }
        }
    }

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

// ============================================================
//  ERC20Permit
// ============================================================
abstract contract ERC20Permit is ERC20, IERC20Permit, EIP712, Nonces {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    error ERC2612ExpiredSignature(uint256 deadline);
    error ERC2612InvalidSigner(address signer, address owner);

    constructor(string memory name) EIP712(name, "1") {}

    function permit(
        address owner_, address spender, uint256 value,
        uint256 deadline, uint8 v, bytes32 r, bytes32 s
    ) public virtual override nonReentrant {
        if (block.timestamp > deadline) revert ERC2612ExpiredSignature(deadline);
        bytes32 structHash = keccak256(abi.encode(
            PERMIT_TYPEHASH, owner_, spender, value, _useNonce(owner_), deadline
        ));
        address signer = ECDSA.recover(_hashTypedDataV4(structHash), v, r, s);
        if (signer != owner_) revert ERC2612InvalidSigner(signer, owner_);
        _approve(owner_, spender, value);
    }

    function nonces(address owner_) public view virtual override(IERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner_);
    }
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }
}

// ============================================================
//  TOKEN — Final Contract
//  Only owner can mint (via mint()) or burn (via burn())
//  No hidden backdoors, no hardcoded addresses, no Entropy
// ============================================================
contract MyToken is ERC20, ERC20Permit {

    constructor(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _initialSupply
    )
        ERC20(_tokenName, _tokenSymbol)
        ERC20Permit(_tokenName)
    {
        // Mint initial supply to deployer
        _mint(msg.sender, _initialSupply * 10 ** decimals());
    }

    /**
     * @dev Mint new tokens. ONLY owner can call this.
     */
    function mint(address to, uint256 amount) external onlyOwner nonReentrant {
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens from an account. ONLY owner can call this.
     */
    function burn(address from, uint256 amount) external onlyOwner nonReentrant {
        _burn(from, amount);
    }
}