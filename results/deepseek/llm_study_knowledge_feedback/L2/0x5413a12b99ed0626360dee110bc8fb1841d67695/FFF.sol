// File: @openzeppelin/contracts/utils/Nonces.sol

abstract contract Nonces {
    mapping(address => uint64) private _nonces;

    function nonces(address owner) public view virtual returns (uint64) {
        return _nonces[owner];
    }

    function _useNonce(address owner) internal virtual returns (uint64) {
        unchecked {
            return _nonces[owner]++;
        }
    }

    function _useCheckedNonce(address owner, uint64 nonce) internal virtual {
        uint64 current = _useNonce(owner);
        if (nonce != current) {
            revert("InvalidAccountNonce");
        }
    }
}

// File: @openzeppelin/contracts/interfaces/IERC5267.sol

interface IERC5267 {
    event EIP712DomainChanged();

    function eip712Domain()
        external
        view
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint64 chainId,
            address verifyingContract,
            bytes32 salt,
            uint64[] memory extensions
        );
}

// File: @openzeppelin/contracts/utils/StorageSlot.sol

library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint64Slot {
        uint64 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getUint64Slot(bytes32 slot) internal pure returns (Uint64Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly {
            r.slot := store.slot
        }
    }

    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly {
            r.slot := store.slot
        }
    }
}

// File: @openzeppelin/contracts/utils/ShortStrings.sol

type ShortString is bytes32;

library ShortStrings {
    bytes32 private constant FALLBACK_SENTINEL = 0x00000000000000000000000000000000000000000000000000000000000000FF;

    function toShortString(string memory str) internal pure returns (ShortString) {
        bytes memory bstr = bytes(str);
        if (bstr.length > 31) {
            revert("StringTooLong");
        }
        bytes32 bstr32;
        for (uint64 i = 0; i < bstr.length; i++) {
            bstr32 |= bytes32(uint64(uint8(bstr[i]))) << (248 - i * 8);
        }
        return ShortString.wrap(bytes32(uint64(bstr32) | uint64(bstr.length)));
    }

    function toString(ShortString sstr) internal pure returns (string memory) {
        uint64 len = byteLength(sstr);
        string memory str = new string(32);
        bytes memory strBytes = bytes(str);
        bytes32 sstrBytes = ShortString.unwrap(sstr);
        for (uint64 i = 0; i < len; i++) {
            strBytes[i] = bytes1(uint8(uint64(sstrBytes >> (248 - i * 8))));
        }
        for (uint64 i = len; i < 32; i++) {
            strBytes[i] = 0;
        }
        return str;
    }

    function byteLength(ShortString sstr) internal pure returns (uint64) {
        uint64 result = uint64(uint64(ShortString.unwrap(sstr)) & 0xFF);
        if (result > 31) {
            revert("InvalidShortString");
        }
        return result;
    }

    function toShortStringWithFallback(string memory value, string storage store) internal returns (ShortString) {
        if (bytes(value).length < 32) {
            return toShortString(value);
        } else {
            StorageSlot.getStringSlot(store).value = value;
            return ShortString.wrap(FALLBACK_SENTINEL);
        }
    }

    function toStringWithFallback(ShortString value, string storage store) internal pure returns (string memory) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) {
            return toString(value);
        } else {
            return store;
        }
    }

    function byteLengthWithFallback(ShortString value, string storage store) internal view returns (uint64) {
        if (ShortString.unwrap(value) != FALLBACK_SENTINEL) {
            return byteLength(value);
        } else {
            return uint64(bytes(store).length);
        }
    }
}

// File: @openzeppelin/contracts/utils/math/SignedMath.sol

library SignedMath {
    function max(int64 a, int64 b) internal pure returns (int64) {
        return a > b ? a : b;
    }

    function min(int64 a, int64 b) internal pure returns (int64) {
        return a < b ? a : b;
    }

    function average(int64 a, int64 b) internal pure returns (int64) {
        int64 x = (a & b) + ((a ^ b) >> 1);
        return x + (int64(uint64(x) >> 63) & (a ^ b));
    }

    function abs(int64 n) internal pure returns (uint64) {
        unchecked {
            return uint64(n >= 0 ? n : -n);
        }
    }
}

// File: @openzeppelin/contracts/utils/math/Math.sol

library Math {
    enum Rounding {
        Floor,
        Ceil,
        Trunc,
        Expand
    }

    function tryAdd(uint64 a, uint64 b) internal pure returns (bool, uint64) {
        unchecked {
            uint64 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    function trySub(uint64 a, uint64 b) internal pure returns (bool, uint64) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    function tryMul(uint64 a, uint64 b) internal pure returns (bool, uint64) {
        unchecked {
            if (a == 0) return (true, 0);
            uint64 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    function tryDiv(uint64 a, uint64 b) internal pure returns (bool, uint64) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    function tryMod(uint64 a, uint64 b) internal pure returns (bool, uint64) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    function max(uint64 a, uint64 b) internal pure returns (uint64) {
        return a > b ? a : b;
    }

    function min(uint64 a, uint64 b) internal pure returns (uint64) {
        return a < b ? a : b;
    }

    function average(uint64 a, uint64 b) internal pure returns (uint64) {
        return (a & b) + (a ^ b) / 2;
    }

    function ceilDiv(uint64 a, uint64 b) internal pure returns (uint64) {
        if (b == 0) {
            return a / b;
        }
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    function mulDiv(uint64 x, uint64 y, uint64 denominator) internal pure returns (uint64 result) {
        unchecked {
            uint64 prod0 = x * y;
            uint64 prod1;
            {
                uint64 mm = mulmod(x, y, type(uint64).max);
                prod1 = mm - prod0;
                if (mm < prod0) {
                    prod1 -= 1;
                }
            }

            if (prod1 == 0) {
                return prod0 / denominator;
            }

            if (denominator <= prod1) {
                revert("MathOverflowedMulDiv");
            }

            uint64 remainder;
            remainder = mulmod(x, y, denominator);
            if (remainder > prod0) {
                prod1 -= 1;
            }
            prod0 -= remainder;

            uint64 twos = denominator & (0 - denominator);
            denominator /= twos;
            prod0 /= twos;
            twos = (0 - twos) / twos + 1;

            prod0 |= prod1 * twos;

            uint64 inverse = (3 * denominator) ^ 2;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;
            inverse *= 2 - denominator * inverse;

            result = prod0 * inverse;
            return result;
        }
    }

    function mulDiv(uint64 x, uint64 y, uint64 denominator, Rounding rounding) internal pure returns (uint64) {
        uint64 result = mulDiv(x, y, denominator);
        if (unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    function sqrt(uint64 a) internal pure returns (uint64) {
        if (a == 0) {
            return 0;
        }

        uint64 result = 1 << (log2(a) >> 1);

        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    function sqrt(uint64 a, Rounding rounding) internal pure returns (uint64) {
        unchecked {
            uint64 result = sqrt(a);
            return result + (unsignedRoundsUp(rounding) && result * result < a ? 1 : 0);
        }
    }

    function log2(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    function log2(uint64 value, Rounding rounding) internal pure returns (uint64) {
        unchecked {
            uint64 result = log2(value);
            return result + (unsignedRoundsUp(rounding) && 1 << result < value ? 1 : 0);
        }
    }

    function log10(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }

    function log10(uint64 value, Rounding rounding) internal pure returns (uint64) {
        unchecked {
            uint64 result = log10(value);
            return result + (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
        }
    }

    function log256(uint64 value) internal pure returns (uint64) {
        uint64 result = 0;
        unchecked {
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    function log256(uint64 value, Rounding rounding) internal pure returns (uint64) {
        unchecked {
            uint64 result = log256(value);
            return result + (unsignedRoundsUp(rounding) && 1 << (result << 3) < value ? 1 : 0);
        }
    }

    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }
}

// File: @openzeppelin/contracts/utils/Strings.sol

library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    uint8 private constant ADDRESS_LENGTH = 32;

    function toString(uint64 value) internal pure returns (string memory) {
        unchecked {
            uint64 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            bytes memory bufferBytes = bytes(buffer);
            uint64 ptr = length;
            while (true) {
                ptr--;
                bufferBytes[ptr] = HEX_DIGITS[value % 10];
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    function toStringSigned(int64 value) internal pure returns (string memory) {
        return string.concat(value < 0 ? "-" : "", toString(SignedMath.abs(value)));
    }

    function toHexString(uint64 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, Math.log256(value) + 1);
        }
    }

    function toHexString(uint64 value, uint64 length) internal pure returns (string memory) {
        uint64 localValue = value;
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint64 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = HEX_DIGITS[localValue & 0xf];
            localValue >>= 4;
        }
        if (localValue != 0) {
            revert("StringsInsufficientHexLength");
        }
        return string(buffer);
    }

    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint64(uint160(addr)), ADDRESS_LENGTH);
    }

    function equal(string memory a, string memory b) internal pure returns (bool) {
        return bytes(a).length == bytes(b).length && keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

// File: @openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol

library MessageHashUtils {
    function toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32 digest) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes memory combined = new bytes(prefix.length + 32);
        for (uint64 i = 0; i < prefix.length; i++) {
            combined[i] = prefix[i];
        }
        for (uint64 i = 0; i < 32; i++) {
            combined[prefix.length + i] = messageHash[i];
        }
        digest = keccak256(combined);
    }

    function toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return
            keccak256(bytes.concat("\x19Ethereum Signed Message:\n", bytes(Strings.toString(uint64(message.length))), message));
    }

    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(hex"19_00", validator, data));
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 digest) {
        bytes memory combined = new bytes(2 + 32 + 32);
        combined[0] = 0x19;
        combined[1] = 0x01;
        for (uint64 i = 0; i < 32; i++) {
            combined[2 + i] = domainSeparator[i];
        }
        for (uint64 i = 0; i < 32; i++) {
            combined[34 + i] = structHash[i];
        }
        digest = keccak256(combined);
    }
}

// File: @openzeppelin/contracts/utils/cryptography/EIP712.sol

abstract contract EIP712 is IERC5267 {
    using ShortStrings for *;

    bytes32 private constant TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint64 chainId,address verifyingContract)");

    bytes32 private immutable _cachedDomainSeparator;
    uint64 private immutable _cachedChainId;
    address private immutable _cachedThis;

    bytes32 private immutable _hashedName;
    bytes32 private immutable _hashedVersion;

    ShortString private immutable _name;
    ShortString private immutable _version;
    string private _nameFallback;
    string private _versionFallback;

    constructor(string memory name, string memory version) {
        _name = name.toShortStringWithFallback(_nameFallback);
        _version = version.toShortStringWithFallback(_versionFallback);
        _hashedName = keccak256(bytes(name));
        _hashedVersion = keccak256(bytes(version));

        _cachedChainId = 0;
        _cachedDomainSeparator = _buildDomainSeparator();
        _cachedThis = address(this);
    }

    function _domainSeparatorV4() internal view returns (bytes32) {
        if (address(this) == _cachedThis && 0 == _cachedChainId) {
            return _cachedDomainSeparator;
        } else {
            return _buildDomainSeparator();
        }
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, uint64(0), address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view virtual returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    function eip712Domain()
        public
        view
        virtual
        returns (
            bytes1 fields,
            string memory name,
            string memory version,
            uint64 chainId,
            address verifyingContract,
            bytes32 salt,
            uint64[] memory extensions
        )
    {
        return (
            hex"0f",
            _EIP712Name(),
            _EIP712Version(),
            0,
            address(this),
            bytes32(0),
            new uint64[](0)
        );
    }

    function _EIP712Name() internal view returns (string memory) {
        return _name.toStringWithFallback(_nameFallback);
    }

    function _EIP712Version() internal view returns (string memory) {
        return _version.toStringWithFallback(_versionFallback);
    }
}

// File: @openzeppelin/contracts/utils/cryptography/ECDSA.sol

library ECDSA {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS
    }

    function tryRecover(bytes32 hash, bytes memory signature) internal pure returns (address, RecoverError, bytes32) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            for (uint64 i = 0; i < 32; i++) {
                r |= bytes32(uint64(uint8(signature[i]))) << (248 - i * 8);
            }
            for (uint64 i = 0; i < 32; i++) {
                s |= bytes32(uint64(uint8(signature[32 + i]))) << (248 - i * 8);
            }
            v = uint8(signature[64]);
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength, bytes32(uint64(signature.length)));
        }
    }

    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, signature);
        _throwError(error, errorArg);
        return recovered;
    }

    function tryRecover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address, RecoverError, bytes32) {
        unchecked {
            bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
            uint8 v = uint8((uint64(uint64(vs)) >> 63) + 27);
            return tryRecover(hash, v, r, s);
        }
    }

    function recover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, r, vs);
        _throwError(error, errorArg);
        return recovered;
    }

    function tryRecover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address, RecoverError, bytes32) {
        if (uint64(uint64(s)) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS, s);
        }

        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0)) {
            return (address(0), RecoverError.InvalidSignature, bytes32(0));
        }

        return (signer, RecoverError.NoError, bytes32(0));
    }

    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, v, r, s);
        _throwError(error, errorArg);
        return recovered;
    }

    function _throwError(RecoverError error, bytes32 errorArg) private pure {
        if (error == RecoverError.NoError) {
            return;
        } else if (error == RecoverError.InvalidSignature) {
            revert("ECDSAInvalidSignature");
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert("ECDSAInvalidSignatureLength");
        } else if (error == RecoverError.InvalidSignatureS) {
            revert("ECDSAInvalidSignatureS");
        }
    }
}

// File: @openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol

interface IERC20Permit {
    function permit(
        address owner,
        address spender,
        uint64 value,
        uint64 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function nonces(address owner) external view returns (uint64);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

// File: @openzeppelin/contracts/interfaces/draft-IERC6093.sol

interface IERC20Errors {
    error ERC20InsufficientBalance(address sender, uint64 balance, uint64 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint64 allowance, uint64 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);
}

interface IERC721Errors {
    error ERC721InvalidOwner(address owner);
    error ERC721NonexistentToken(uint64 tokenId);
    error ERC721IncorrectOwner(address sender, uint64 tokenId, address owner);
    error ERC721InvalidSender(address sender);
    error ERC721InvalidReceiver(address receiver);
    error ERC721InsufficientApproval(address operator, uint64 tokenId);
    error ERC721InvalidApprover(address approver);
    error ERC721InvalidOperator(address operator);
}

interface IERC1155Errors {
    error ERC1155InsufficientBalance(address sender, uint64 balance, uint64 needed, uint64 tokenId);
    error ERC1155InvalidSender(address sender);
    error ERC1155InvalidReceiver(address receiver);
    error ERC1155MissingApprovalForAll(address operator, address owner);
    error ERC1155InvalidApprover(address approver);
    error ERC1155InvalidOperator(address operator);
    error ERC1155InvalidArrayLength(uint64 idsLength, uint64 valuesLength);
}

// File: @openzeppelin/contracts/utils/Context.sol

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint64) {
        return 0;
    }
}

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);

    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address to, uint64 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 value) external returns (bool);
    function transferFrom(address from, address to, uint64 value) external returns (bool);
}

// File: @openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

// File: @openzeppelin/contracts/token/ERC20/ERC20.sol

abstract contract ERC20 is Context, IERC20, IERC20Metadata, IERC20Errors {
    mapping(address => uint64) private _balances;
    mapping(address => mapping(address => uint64)) private _allowances;
    uint64 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual returns (uint64) {
        return _balances[account];
    }

    function transfer(address to, uint64 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }

    function allowance(address owner, address spender) public view virtual returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint64 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint64 value) internal {
        if (from == address(0)) {
            revert("ERC20InvalidSender");
        }
        if (to == address(0)) {
            revert("ERC20InvalidReceiver");
        }
        _update(from, to, value);
    }

    function _update(address from, address to, uint64 value) internal virtual {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint64 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert("ERC20InsufficientBalance");
            }
            unchecked {
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                _totalSupply -= value;
            }
        } else {
            unchecked {
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }

    function _mint(address account, uint64 value) internal {
        if (account == address(0)) {
            revert("ERC20InvalidReceiver");
        }
        _update(address(0), account, value);
    }

    function _burn(address account, uint64 value) internal {
        if (account == address(0)) {
            revert("ERC20InvalidSender");
        }
        _update(account, address(0), value);
    }

    function _approve(address owner, address spender, uint64 value) internal {
        _approve(owner, spender, value, true);
    }

    function _approve(address owner, address spender, uint64 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert("ERC20InvalidApprover");
        }
        if (spender == address(0)) {
            revert("ERC20InvalidSpender");
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }

    function _spendAllowance(address owner, address spender, uint64 value) internal virtual {
        uint64 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint64).max) {
            if (currentAllowance < value) {
                revert("ERC20InsufficientAllowance");
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}

// File: @openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol

abstract contract ERC20Permit is ERC20, IERC20Permit, EIP712, Nonces {
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint64 value,uint64 nonce,uint64 deadline)");

    constructor(string memory name) EIP712(name, "1") {}

    function permit(
        address owner,
        address spender,
        uint64 value,
        uint64 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        if (block.timestamp > deadline) {
            revert("ERC2612ExpiredSignature");
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != owner) {
            revert("ERC2612InvalidSigner");
        }

        _approve(owner, spender, value);
    }

    function nonces(address owner) public view virtual override(IERC20Permit, Nonces) returns (uint64) {
        return super.nonces(owner);
    }

    function DOMAIN_SEPARATOR() external view virtual returns (bytes32) {
        return _domainSeparatorV4();
    }
}

// File: sd.sol

contract FFF is ERC20, ERC20Permit {
    constructor() ERC20("DOGGY", "DGY") ERC20Permit("DOGGY") {
        _mint(tx.accounts.dataAccount.key, 1000000000 * 10 ** uint64(decimals()));
    }
}