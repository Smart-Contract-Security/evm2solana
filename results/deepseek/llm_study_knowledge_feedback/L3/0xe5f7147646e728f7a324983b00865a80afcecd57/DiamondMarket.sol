import 'solana';

abstract contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal pure returns (uint64) {
        return 0;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address previousOwner, address newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0), "Ownable: owner is zero address");
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function _checkOwner() internal view {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

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
            assembly {
                let mm := mulmod(x, y, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            if (prod1 == 0) {
                return prod0 / denominator;
            }

            require(denominator > prod1, "Math: mulDiv overflow");

            uint64 remainder;
            assembly {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint64 twos = denominator & (0 - denominator);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }

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
            if (value >= 10 ** 19) {
                value /= 10 ** 19;
                result += 19;
            }
            if (value >= 10 ** 9) {
                value /= 10 ** 9;
                result += 9;
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

library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    uint8 private constant ADDRESS_LENGTH = 32;

    function toString(uint64 value) internal pure returns (string memory) {
        unchecked {
            uint64 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            bytes memory bufferBytes = bytes(buffer);
            uint64 localValue = value;
            for (uint64 i = length; i > 0; i--) {
                bufferBytes[i - 1] = HEX_DIGITS[localValue % 10];
                localValue /= 10;
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
        require(localValue == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint64(uint256(addr)), ADDRESS_LENGTH);
    }

    function equal(string memory a, string memory b) internal pure returns (bool) {
        return bytes(a).length == bytes(b).length && sha256(bytes(a)) == sha256(bytes(b));
    }
}

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
        digest = sha256(combined);
    }

    function toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return
            sha256(bytes.concat("\x19Ethereum Signed Message:\n", bytes(Strings.toString(uint64(message.length))), message));
    }

    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        return sha256(abi.encodePacked(hex"19_00", validator, data));
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
        digest = sha256(combined);
    }
}

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

type ShortString is bytes32;

library ShortStrings {
    bytes32 private constant FALLBACK_SENTINEL = 0x00000000000000000000000000000000000000000000000000000000000000FF;

    function toShortString(string memory str) internal pure returns (ShortString) {
        bytes memory bstr = bytes(str);
        require(bstr.length <= 31, "ShortStrings: string too long");
        return ShortString.wrap(bytes32(uint256(bytes32(bstr)) | bstr.length));
    }

    function toString(ShortString sstr) internal pure returns (string memory) {
        uint64 len = byteLength(sstr);
        string memory str = new string(len);
        bytes memory strBytes = bytes(str);
        bytes32 sstrBytes = ShortString.unwrap(sstr);
        for (uint64 i = 0; i < len; i++) {
            strBytes[i] = sstrBytes[i];
        }
        return str;
    }

    function byteLength(ShortString sstr) internal pure returns (uint64) {
        uint64 result = uint64(ShortString.unwrap(sstr)) & 0xFF;
        require(result <= 31, "ShortStrings: invalid short string");
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

abstract contract EIP712 is IERC5267 {
    using ShortStrings for *;

    bytes32 private constant TYPE_HASH =
        sha256("EIP712Domain(string name,string version,uint64 chainId,address verifyingContract)");

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
        _hashedName = sha256(bytes(name));
        _hashedVersion = sha256(bytes(version));

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
        return sha256(abi.encode(TYPE_HASH, _hashedName, _hashedVersion, uint64(0), address(this)));
    }

    function _hashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(_domainSeparatorV4(), structHash);
    }

    function eip712Domain()
        public
        view
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
                r |= bytes32(uint256(uint8(signature[i])) << (248 - i * 8));
            }
            for (uint64 i = 0; i < 32; i++) {
                s |= bytes32(uint256(uint8(signature[32 + i])) << (248 - i * 8));
            }
            v = uint8(signature[64]);
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength, bytes32(uint256(signature.length)));
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
            uint8 v = uint8((uint256(vs) >> 255) + 27);
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
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS, s);
        }

        address signer = recoverSigner(hash, v, r, s);
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

    function recoverSigner(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        bytes32 messageHash = hash;
        bytes32 prefixedHash = sha256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        return address(uint160(uint256(sha256(abi.encodePacked(prefixedHash, v, r, s)))));
    }

    function _throwError(RecoverError error, bytes32 errorArg) private pure {
        if (error == RecoverError.NoError) {
            return;
        } else if (error == RecoverError.InvalidSignature) {
            revert("ECDSA: invalid signature");
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert("ECDSA: invalid signature length");
        } else if (error == RecoverError.InvalidSignatureS) {
            revert("ECDSA: invalid signature 's' value");
        }
    }
}

contract DiamondMarket is EIP712, Ownable {
    using ECDSA for bytes32;
    address public treasurer;
    address public signer;
    address public USD;
    address public GOLD;
    address public testUSD;
    bool public isTest = true;

    uint64 public buyPrice;
    uint64 public sellPrice;
    mapping(address => uint64) public nonces;

    event Bought(address who, uint64 quantity, uint64 amount);
    event Sold(address who, uint64 quantity, uint64 amount);

    event Withdrew(address who, uint64 amount);
    event Received(address who, uint64 amount);

    struct Selling {
        address recipient;
        uint64 nonce;
        uint32 quantity;
        uint32 expired;
    }

    bytes32 constant SELLING_TYPEHASH =
        sha256(
            "Selling(address recipient,uint64 nonce,uint32 quantity,uint32 expired)"
        );

    constructor(
        address _treasurer,
        address _signer,
        address _usd,
        address _testUsd,
        address _gold,
        uint64 _buyPrice,
        uint64 _sellPrice
    ) EIP712("Swords Dungeons Diamond Market", "v1") Ownable(tx.accounts.dataAccount.key) {
        treasurer = _treasurer;
        USD = _usd;
        testUSD = _testUsd;
        GOLD = _gold;
        buyPrice = _buyPrice;
        sellPrice = _sellPrice;
        signer = _signer;
    }

    function withdraw(address payable to) external onlyOwner {
        uint64 amount = to.lamports();
        to.transfer(amount);
        emit Withdrew(to, amount);
    }

    function setPrice(uint64 _buy, uint64 _sell) external onlyOwner {
        buyPrice = _buy;
        sellPrice = _sell;
    }

    function setSigner(address _signer) public onlyOwner {
        require(_signer != address(0));
        signer = _signer;
    }

    function setTreasurer(address _treasurer) public onlyOwner {
        require(_treasurer != address(0));
        treasurer = _treasurer;
    }

    function setUsd(address _usd) public onlyOwner {
        require(_usd != address(0));
        USD = _usd;
    }

    function setGold(address _gold) public onlyOwner {
        require(_gold != address(0));
        GOLD = _gold;
    }

    function setTestUsd(address _testUsd) public onlyOwner {
        require(_testUsd != address(0));
        testUSD = _testUsd;
    }

    function setTest(bool _isTest) public onlyOwner {
        isTest = _isTest;
    }

    function refund(
        address[] memory recipients,
        uint64[] memory amounts
    ) public onlyOwner {
        require(
            recipients.length == amounts.length,
            "wrong number of recipients"
        );
        for (uint32 i = 0; i < recipients.length; i++) {
            IERC20(USD).transferFrom(treasurer, recipients[i], amounts[i]);
        }
    }

    function rechargeGold(uint64 amount, uint32 expired) external {
        require(
            expired > block.timestamp,
            "DiamondMarket rechargeGold: expired!"
        );
        IERC20(GOLD).transferFrom(tx.accounts.dataAccount.key, treasurer, amount);
    }

    function buy(uint32 quantity, uint32 expired) external {
        require(expired > block.timestamp, "DiamondMarket buy: expired!");
        uint64 amount = uint64(quantity) * buyPrice;
        IERC20(USD).transferFrom(tx.accounts.dataAccount.key, treasurer, amount);
        emit Bought(tx.accounts.dataAccount.key, quantity, amount);
    }

    function permitSell(
        uint32 quantity,
        uint32 expired,
        bytes memory signature
    ) external {
        address recipient = _msgSender();
        Selling memory selling = Selling({
            recipient: recipient,
            nonce: nonces[recipient],
            quantity: quantity,
            expired: expired
        });
        require(
            verify(selling, signature),
            "DiamondMarket: signature is wrong!"
        );
        require(expired > block.timestamp, "DiamondMarket: expired!");

        uint64 amount = uint64(quantity) * sellPrice;
        if (isTest) {
            IERC20(testUSD).transferFrom(treasurer, recipient, amount);
        } else {
            IERC20(USD).transferFrom(treasurer, recipient, amount);
        }

        emit Sold(recipient, quantity, amount);
        nonces[recipient] += 1;
    }

    function getNonce(address user) public view returns (uint64 nonce) {
        nonce = nonces[user];
    }

    function hash(Selling memory selling) internal pure returns (bytes32) {
        return
            sha256(
                abi.encode(
                    SELLING_TYPEHASH,
                    selling.recipient,
                    selling.nonce,
                    selling.quantity,
                    selling.expired
                )
            );
    }

    function verify(
        Selling memory selling,
        bytes memory signature
    ) internal view returns (bool) {
        bytes32 digest = _hashTypedDataV4(hash(selling));
        address addr = digest.recover(signature);
        return addr == signer;
    }
}