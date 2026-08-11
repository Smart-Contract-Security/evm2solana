import 'solana';

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
            assembly {
                r := calldataload(signature.offset)
                s := calldataload(add(signature.offset, 32))
                v := byte(0, calldataload(add(signature.offset, 64)))
            }
            return tryRecover(hash, v, r, s);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength, bytes32(uint64(signature.length)));
        }
    }

    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, signature);
        if (error == RecoverError.InvalidSignature) {
            revert("ECDSAInvalidSignature");
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert("ECDSAInvalidSignatureLength");
        } else if (error == RecoverError.InvalidSignatureS) {
            revert("ECDSAInvalidSignatureS");
        }
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
        if (error == RecoverError.InvalidSignature) {
            revert("ECDSAInvalidSignature");
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert("ECDSAInvalidSignatureLength");
        } else if (error == RecoverError.InvalidSignatureS) {
            revert("ECDSAInvalidSignatureS");
        }
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

        address signer = verify_ecdsa(hash, v, r, s);
        if (signer == address(0)) {
            return (address(0), RecoverError.InvalidSignature, bytes32(0));
        }

        return (signer, RecoverError.NoError, bytes32(0));
    }

    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        (address recovered, RecoverError error, bytes32 errorArg) = tryRecover(hash, v, r, s);
        if (error == RecoverError.InvalidSignature) {
            revert("ECDSAInvalidSignature");
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert("ECDSAInvalidSignatureLength");
        } else if (error == RecoverError.InvalidSignatureS) {
            revert("ECDSAInvalidSignatureS");
        }
        return recovered;
    }

    function verify_ecdsa(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
        bytes memory signature = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            signature[i] = r[i];
        }
        for (uint i = 0; i < 32; i++) {
            signature[i + 32] = s[i];
        }
        uint64 recoveryId = uint64(v - 27);
        bytes32[2] memory pubkey;
        uint64 result = secp256k1_recover(hash, recoveryId, signature, pubkey);
        if (result != 0) {
            return address(0);
        }
        bytes memory pubkeyBytes = new bytes(64);
        for (uint i = 0; i < 32; i++) {
            pubkeyBytes[i] = pubkey[0][i];
        }
        for (uint i = 0; i < 32; i++) {
            pubkeyBytes[i + 32] = pubkey[1][i];
        }
        bytes32 hashPubkey = keccak256(pubkeyBytes);
        address signer;
        assembly {
            signer := hashPubkey
        }
        return signer;
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != ENTERED);
        _status = ENTERED;
        _;
        _status = NOT_ENTERED;
    }

    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

library Address {
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.call{accounts: []}(data);
        if (!success) {
            if (returndata.length > 0) {
                revert("FailedInnerCall");
            } else {
                revert("FailedInnerCall");
            }
        }
        return returndata;
    }
}

interface IERC20Permit {
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

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

library SafeERC20 {
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        bytes memory data = abi.encodeWithSelector(token.transfer.selector, to, value);
        address(token).functionCall(data);
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        bytes memory data = abi.encodeWithSelector(token.transferFrom.selector, from, to, value);
        address(token).functionCall(data);
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            require(currentAllowance >= requestedDecrease);
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeWithSelector(token.approve.selector, spender, value);
        (bool success, bytes memory returndata) = address(token).call{accounts: []}(approvalCall);
        if (!success || (returndata.length != 0 && !abi.decode(returndata, (bool)))) {
            bytes memory resetCall = abi.encodeWithSelector(token.approve.selector, spender, 0);
            address(token).functionCall(resetCall);
            address(token).functionCall(approvalCall);
        }
    }
}

interface IERC20Errors {
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);
}

interface IERC721Errors {
    error ERC721InvalidOwner(address owner);
    error ERC721NonexistentToken(uint256 tokenId);
    error ERC721IncorrectOwner(address sender, uint256 tokenId, address owner);
    error ERC721InvalidSender(address sender);
    error ERC721InvalidReceiver(address receiver);
    error ERC721InsufficientApproval(address operator, uint256 tokenId);
    error ERC721InvalidApprover(address approver);
    error ERC721InvalidOperator(address operator);
}

interface IERC1155Errors {
    error ERC1155InsufficientBalance(address sender, uint256 balance, uint256 needed, uint256 tokenId);
    error ERC1155InvalidSender(address sender);
    error ERC1155InvalidReceiver(address receiver);
    error ERC1155MissingApprovalForAll(address operator, address owner);
    error ERC1155InvalidApprover(address approver);
    error ERC1155InvalidOperator(address operator);
    error ERC1155InvalidArrayLength(uint256 idsLength, uint256 valuesLength);
}

library SignedMath {
    function max(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }

    function min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    function average(int256 a, int256 b) internal pure returns (int256) {
        int256 x = (a & b) + ((a ^ b) >> 1);
        return x + (int256(uint256(x) >> 255) & (a ^ b));
    }

    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            return uint256(n >= 0 ? n : -n);
        }
    }
}

library Math {
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a & b) + (a ^ b) / 2;
    }

    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            return a / b;
        }
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            uint256 prod0 = x * y;
            uint256 prod1;
            assembly {
                let mm := mulmod(x, y, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            if (prod1 == 0) {
                return prod0 / denominator;
            }

            require(denominator > prod1);

            uint256 remainder;
            assembly {
                remainder := mulmod(x, y, denominator)
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint256 twos = denominator & (0 - denominator);
            assembly {
                denominator := div(denominator, twos)
                prod0 := div(prod0, twos)
                twos := add(div(sub(0, twos), twos), 1)
            }

            prod0 |= prod1 * twos;

            uint256 inverse = (3 * denominator) ^ 2;
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

    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 result = 1 << (log2(a) >> 1);

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

    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + (unsignedRoundsUp(rounding) && result * result < a ? 1 : 0);
        }
    }

    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
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

    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + (unsignedRoundsUp(rounding) && 1 << result < value ? 1 : 0);
        }
    }

    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
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

    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
        }
    }

    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
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

    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (unsignedRoundsUp(rounding) && 1 << (result << 3) < value ? 1 : 0);
        }
    }

    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }

    enum Rounding {
        Floor,
        Ceil,
        Trunc,
        Expand
    }
}

library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    uint8 private constant ADDRESS_LENGTH = 20;

    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                assembly {
                    mstore8(ptr, byte(mod(value, 10), HEX_DIGITS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    function toStringSigned(int256 value) internal pure returns (string memory) {
        return string.concat(value < 0 ? "-" : "", toString(SignedMath.abs(value)));
    }

    function toHexString(uint256 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, Math.log256(value) + 1);
        }
    }

    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        uint256 localValue = value;
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = HEX_DIGITS[localValue & 0xf];
            localValue >>= 4;
        }
        require(localValue == 0);
        return string(buffer);
    }

    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), ADDRESS_LENGTH);
    }

    function equal(string memory a, string memory b) internal pure returns (bool) {
        return bytes(a).length == bytes(b).length && keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

library MessageHashUtils {
    function toEthSignedMessageHash(bytes32 messageHash) internal pure returns (bytes32 digest) {
        bytes memory prefix = "\x19Ethereum Signed Message:\n32";
        bytes memory combined = new bytes(prefix.length + 32);
        for (uint i = 0; i < prefix.length; i++) {
            combined[i] = prefix[i];
        }
        for (uint i = 0; i < 32; i++) {
            combined[prefix.length + i] = messageHash[i];
        }
        digest = keccak256(combined);
    }

    function toEthSignedMessageHash(bytes memory message) internal pure returns (bytes32) {
        return
            keccak256(bytes.concat("\x19Ethereum Signed Message:\n", bytes(Strings.toString(message.length)), message));
    }

    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(hex"1900", validator, data));
    }

    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 digest) {
        bytes memory data = new bytes(66);
        data[0] = 0x19;
        data[1] = 0x01;
        for (uint i = 0; i < 32; i++) {
            data[2 + i] = domainSeparator[i];
        }
        for (uint i = 0; i < 32; i++) {
            data[34 + i] = structHash[i];
        }
        digest = keccak256(data);
    }
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        require(initialOwner != address(0));
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        require(owner() == _msgSender());
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0));
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

abstract contract ERC165 is IERC165 {
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

interface IERC721 is IERC165 {
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function setApprovalForAll(address operator, bool approved) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

interface IERC4906 is IERC165, IERC721 {
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);
}

interface IERC721Enumerable is IERC721 {
    function totalSupply() external view returns (uint256);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);
    function tokenByIndex(uint256 index) external view returns (uint256);
}

interface IERC721Metadata is IERC721 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}

abstract contract ERC721 is Context, ERC165, IERC721, IERC721Metadata, IERC721Errors {
    using Strings for uint256;

    string private _name;
    string private _symbol;

    mapping(uint256 tokenId => address) private _owners;
    mapping(address owner => uint256) private _balances;
    mapping(uint256 tokenId => address) private _tokenApprovals;
    mapping(address owner => mapping(address operator => bool)) private _operatorApprovals;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function balanceOf(address owner) public view virtual returns (uint256) {
        require(owner != address(0));
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view virtual returns (address) {
        return _requireOwned(tokenId);
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function tokenURI(uint256 tokenId) public view virtual returns (string memory) {
        _requireOwned(tokenId);
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string.concat(baseURI, tokenId.toString()) : "";
    }

    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    function approve(address to, uint256 tokenId) public virtual {
        _approve(to, tokenId, _msgSender());
    }

    function getApproved(uint256 tokenId) public view virtual returns (address) {
        _requireOwned(tokenId);
        return _getApproved(tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public virtual {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view virtual returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public virtual {
        require(to != address(0));
        address previousOwner = _update(to, tokenId, _msgSender());
        require(previousOwner == from);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public virtual {
        transferFrom(from, to, tokenId);
        _checkOnERC721Received(from, to, tokenId, data);
    }

    function _ownerOf(uint256 tokenId) internal view virtual returns (address) {
        return _owners[tokenId];
    }

    function _getApproved(uint256 tokenId) internal view virtual returns (address) {
        return _tokenApprovals[tokenId];
    }

    function _isAuthorized(address owner, address spender, uint256 tokenId) internal view virtual returns (bool) {
        return
            spender != address(0) &&
            (owner == spender || isApprovedForAll(owner, spender) || _getApproved(tokenId) == spender);
    }

    function _checkAuthorized(address owner, address spender, uint256 tokenId) internal view virtual {
        require(_isAuthorized(owner, spender, tokenId));
    }

    function _increaseBalance(address account, uint128 value) internal virtual {
        unchecked {
            _balances[account] += value;
        }
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual returns (address) {
        address from = _ownerOf(tokenId);

        if (auth != address(0)) {
            _checkAuthorized(from, auth, tokenId);
        }

        if (from != address(0)) {
            _approve(address(0), tokenId, address(0), false);
            unchecked {
                _balances[from] -= 1;
            }
        }

        if (to != address(0)) {
            unchecked {
                _balances[to] += 1;
            }
        }

        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        return from;
    }

    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0));
        address previousOwner = _update(to, tokenId, address(0));
        require(previousOwner == address(0));
    }

    function _safeMint(address to, uint256 tokenId) internal {
        _safeMint(to, tokenId, "");
    }

    function _safeMint(address to, uint256 tokenId, bytes memory data) internal virtual {
        _mint(to, tokenId);
        _checkOnERC721Received(address(0), to, tokenId, data);
    }

    function _burn(uint256 tokenId) internal {
        address previousOwner = _update(address(0), tokenId, address(0));
        require(previousOwner != address(0));
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(to != address(0));
        address previousOwner = _update(to, tokenId, address(0));
        require(previousOwner != address(0));
        require(previousOwner == from);
    }

    function _safeTransfer(address from, address to, uint256 tokenId) internal {
        _safeTransfer(from, to, tokenId, "");
    }

    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory data) internal virtual {
        _transfer(from, to, tokenId);
        _checkOnERC721Received(from, to, tokenId, data);
    }

    function _approve(address to, uint256 tokenId, address auth) internal {
        _approve(to, tokenId, auth, true);
    }

    function _approve(address to, uint256 tokenId, address auth, bool emitEvent) internal virtual {
        if (emitEvent || auth != address(0)) {
            address owner = _requireOwned(tokenId);
            require(auth == address(0) || owner == auth || isApprovedForAll(owner, auth));
            if (emitEvent) {
                emit Approval(owner, to, tokenId);
            }
        }
        _tokenApprovals[tokenId] = to;
    }

    function _setApprovalForAll(address owner, address operator, bool approved) internal virtual {
        require(operator != address(0));
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    function _requireOwned(uint256 tokenId) internal view returns (address) {
        address owner = _ownerOf(tokenId);
        require(owner != address(0));
        return owner;
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) private {
        bytes memory encodedCall = abi.encodeWithSelector(IERC721Receiver.onERC721Received.selector, _msgSender(), from, tokenId, data);
        (bool success, bytes memory returndata) = to.call{accounts: []}(encodedCall);
        if (success && returndata.length >= 32) {
            bytes4 retval = abi.decode(returndata, (bytes4));
            require(retval == IERC721Receiver.onERC721Received.selector);
        } else {
            revert("ERC721InvalidReceiver");
        }
    }
}

abstract contract ERC721URIStorage is IERC4906, ERC721 {
    using Strings for uint256;

    bytes4 private constant ERC4906_INTERFACE_ID = bytes4(0x49064906);

    mapping(uint256 tokenId => string) private _tokenURIs;

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721, IERC165) returns (bool) {
        return interfaceId == ERC4906_INTERFACE_ID || super.supportsInterface(interfaceId);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireOwned(tokenId);

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        if (bytes(_tokenURI).length > 0) {
            return string.concat(base, _tokenURI);
        }

        return super.tokenURI(tokenId);
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        _tokenURIs[tokenId] = _tokenURI;
        emit MetadataUpdate(tokenId);
    }
}

abstract contract ERC721Enumerable is ERC721, IERC721Enumerable {
    mapping(address owner => mapping(uint256 index => uint256)) private _ownedTokens;
    mapping(uint256 tokenId => uint256) private _ownedTokensIndex;

    uint256[] private _allTokens;
    mapping(uint256 tokenId => uint256) private _allTokensIndex;

    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721) returns (bool) {
        return interfaceId == type(IERC721Enumerable).interfaceId || super.supportsInterface(interfaceId);
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual returns (uint256) {
        require(index < balanceOf(owner));
        return _ownedTokens[owner][index];
    }

    function totalSupply() public view virtual returns (uint256) {
        return _allTokens.length;
    }

    function tokenByIndex(uint256 index) public view virtual returns (uint256) {
        require(index < totalSupply());
        return _allTokens[index];
    }

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address previousOwner = super._update(to, tokenId, auth);

        if (previousOwner == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (previousOwner != to) {
            _removeTokenFromOwnerEnumeration(previousOwner, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (previousOwner != to) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }

        return previousOwner;
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = balanceOf(to) - 1;
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        uint256 lastTokenIndex = balanceOf(from);
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];
            _ownedTokens[from][tokenIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId] = tokenIndex;
        }

        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId;
        _allTokensIndex[lastTokenId] = tokenIndex;

        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }

    function _increaseBalance(address account, uint128 amount) internal virtual override {
        require(amount == 0);
        super._increaseBalance(account, amount);
    }
}

contract MetaCraftVNode is ERC721, IERC721Receiver, ReentrancyGuard {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    uint256 public _tokenIds;
    address private immutable owner;

    mapping(address => bool) public _mintedAddresses;
    string public constant nodeTokenURI = "ipfs://QmZ1n7S2UHFmBbiGFzFHYsTJoLwbU29rTDquxPccSNqajg";
    uint256 public mintPrice;
    bool public locked = true;
    bool public halted = false;

    mapping(address => address) public parent;
    mapping(uint256 => address) public tokenOwner;
    mapping(address => NodeInfo) public nodes;

    uint256 constant public PRICE_INCREMENT = 1;
    uint256 constant public ID_INCREMENT = 5;
    uint256 constant public MAX_ID = 50000;

    address public publicKey;
    address public feeAddress;

    address public immutable ERC20Token;
    uint256 public immutable tokenDecimals;

    event NodeStatusChange(address owner, address parent, uint256 tokenId, string status, uint256 timestamp);
    event TransactionSigned(address by, uint transactionId);

    event NodeEvents(
        uint256 timeStamp,
        address eventSender,
        string eventName
    );

    struct TokenInfo {
        uint256 tokenId;
        address tokenOwner;
        uint256 tokenPrice;
        uint256 mintTimestamp;
    }
    struct NodeInfo {
        address nodeAddress;
        address nodeParent;
        uint256 stakeYears;
        TokenInfo tokenInfo;
    }
    enum TransactionType {
        AddOwner,
        RemoveOwner,
        SetParameter,
        SetSalesAddress
    }
    struct SetTransaction {
        TransactionType txType;
        bytes data;
        uint8 signatureCount;
        uint256 timestamp;
        uint256 readyForExecutionTimestamp;
        bool executed;
    }

    mapping(uint => SetTransaction) private _settransactions;
    uint[] private _pendingTransactions;
    mapping(uint => mapping(address => bool)) private signatures;

    modifier notExecuted(uint transactionId) {
        SetTransaction memory transaction = _settransactions[transactionId];
        require(transaction.timestamp > 0);
        require(!_settransactions[transactionId].executed);
        _;
    }

    mapping(address => uint8) private _validOwners;
    uint256 public constant observationPeriod = 24 hours;
    uint256 public constant maxPendingTime = 96 hours;

    uint constant MIN_SIGNATURES = 3;
    address[] public validOwners;
    uint private _transactionIdx;

    constructor(
        string memory _name,
        string memory _symbol,
        address _erc20Token,
        uint256 _decimals
    ) ERC721(_name, _symbol) {
        ERC20Token = _erc20Token;
        tokenDecimals = _decimals;
        owner = tx.accounts.dataAccount.key;

        address addr1 = address(bytes32(0x486d3D3e599985B00547783E447c2d799d7d2eE5));
        address addr2 = address(bytes32(0x498d09597e35f00ECaB97f5A10F6369aDde00364));
        address addr3 = address(bytes32(0xa1813Fb2A6882E8248CD4d4C789480F50CAf7ca4));

        _validOwners[addr1] = 1;
        _validOwners[addr2] = 1;
        _validOwners[addr3] = 1;

        validOwners.push(addr1);
        validOwners.push(addr2);
        validOwners.push(addr3);

        publicKey = address(bytes32(0xEe8b45a0c599e8E6512297f99687BF5FE3359147));
        feeAddress = address(bytes32(0x498d09597e35f00ECaB97f5A10F6369aDde00364));
    }

    function onERC721Received(address, address, uint256, bytes calldata)
    external
    override
    pure
    returns(bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    modifier onlySelf() {
        require(tx.accounts.dataAccount.key == address(this));
        _;
    }

    modifier validOwner() {
        require(_validOwners[tx.accounts.dataAccount.key] == 1);
        _;
    }

    function addOwner(address _owner)
        public
    {
        require(tx.accounts.dataAccount.key == owner);
        require(_validOwners[_owner] != 1);
        require(_owner != address(0));

        TransactionType txType = TransactionType.AddOwner;
        bytes memory data = abi.encodeWithSelector(MetaCraftVNode.setOwner.selector, _owner, uint8(1));
        addSetTransaction(txType, data);

        emit NodeEvents(block.timestamp, tx.accounts.dataAccount.key, "AddValieOwner");
    }

    function removeOwner(address _owner)
        public
    {
        require(tx.accounts.dataAccount.key == owner);
        require(_validOwners[_owner] == 1);
        require(_owner != address(0));

        TransactionType txType = TransactionType.RemoveOwner;
        bytes memory data = abi.encodeWithSelector(MetaCraftVNode.setOwner.selector, _owner, uint8(0));
        addSetTransaction(txType, data);

        emit NodeEvents(block.timestamp, tx.accounts.dataAccount.key, "RemoveValieOwner");
    }

    function setParameters(bool isLock_, bool isHalt_)
        public
    {
        require(tx.accounts.dataAccount.key == owner);

        TransactionType txType = TransactionType.SetParameter;
        bytes memory data = abi.encodeWithSelector(MetaCraftVNode.setLockHalt.selector, isLock_, isHalt_);
        addSetTransaction(txType, data);

        emit NodeEvents(block.timestamp, tx.accounts.dataAccount.key, "setParamters");
    }

    function setSalesAddress(address _feeAddress)
        public
    {
        require(tx.accounts.dataAccount.key == owner);

        TransactionType txType = TransactionType.SetSalesAddress;
        bytes memory data = abi.encodeWithSelector(MetaCraftVNode.setFeeAddress.selector, _feeAddress);
        addSetTransaction(txType, data);

        emit NodeEvents(block.timestamp, tx.accounts.dataAccount.key, "setSalesAddress");
    }

    function isValidFunctionSelector(TransactionType _type, bytes4 selector) private pure returns (bool) {
        if (_type == TransactionType.AddOwner && selector == MetaCraftVNode.setOwner.selector) return true;
        if (_type == TransactionType.RemoveOwner && selector == MetaCraftVNode.setOwner.selector) return true;
        if (_type == TransactionType.SetParameter && selector == MetaCraftVNode.setLockHalt.selector) return true;
        if (_type == TransactionType.SetSalesAddress && selector == MetaCraftVNode.setFeeAddress.selector) return true;
        return false;
    }

    function deleteMaxPendingTx()
        private
    {
        require(_pendingTransactions.length <= 1);

        if (_pendingTransactions.length == 1) {
            uint txId = _pendingTransactions[0];
            SetTransaction storage pendingsetTx = _settransactions[txId];
            if (pendingsetTx.timestamp > 0) {
                if (block.timestamp - pendingsetTx.timestamp > maxPendingTime) {
                    deleteSetTx(txId);
                } else revert("has pending txs yet! Please sign them first");
            }
        }
    }

    function setOwner(address _owner, uint8 _status) public onlySelf {
        _validOwners[_owner] = _status;

        if (_status == 0) {
            uint256 ownerLength = validOwners.length;
            for (uint256 i = 0; i < ownerLength; i++) {
                if (validOwners[i] == _owner) {
                    validOwners[i] = validOwners[ownerLength - 1];
                    validOwners.pop();
                    break;
                }
            }
        } else if (_status == 1) {
            validOwners.push(_owner);
        }
    }

    function setLockHalt(bool isLock_, bool isHalt_) public onlySelf {
        locked = isLock_;
        halted = isHalt_;
    }

    function setFeeAddress(address _feeAddress) public onlySelf {
        feeAddress = _feeAddress;
    }

    function addSetTransaction(TransactionType _type, bytes memory _data) private {
        require(tx.accounts.dataAccount.key == owner);
        require(_data.length >= 4);
        require(isValidFunctionSelector(_type, bytes4(_data)));

        deleteMaxPendingTx();

        uint256 transactionId = _transactionIdx++;

        _settransactions[transactionId] = SetTransaction({
            txType: _type,
            data: _data,
            signatureCount: 0,
            timestamp: block.timestamp,
            readyForExecutionTimestamp: block.timestamp,
            executed: false
        });
        _pendingTransactions.push(transactionId);
    }

    function signSetTransaction(uint transactionId) public validOwner notExecuted(transactionId) {
        SetTransaction memory transaction = _settransactions[transactionId];
        require(transaction.timestamp > 0);
        require(!transaction.executed);
        require(!signatures[transactionId][tx.accounts.dataAccount.key]);

        if (transaction.txType == TransactionType.SetSalesAddress) {
            require(block.timestamp - transaction.timestamp >= 24 hours);
        }

        signatures[transactionId][tx.accounts.dataAccount.key] = true;
        _settransactions[transactionId].signatureCount++;
        _settransactions[transactionId].timestamp = block.timestamp;
        uint ownerCount = validOwners.length;
        uint signCount = ownerCount >= 3 ? MIN_SIGNATURES : ownerCount;
        if (_settransactions[transactionId].signatureCount == signCount) {
            if (transaction.txType == TransactionType.SetSalesAddress) {
                _settransactions[transactionId].readyForExecutionTimestamp = block.timestamp + observationPeriod;
            } else {
                _settransactions[transactionId].readyForExecutionTimestamp = block.timestamp;
                executeSetTransaction(transactionId);
            }
        }
        emit TransactionSigned(tx.accounts.dataAccount.key, transactionId);
    }

    function executeSetTransaction(uint transactionId)
        validOwner
        public
    {
        SetTransaction storage transaction = _settransactions[transactionId];
        require(transaction.signatureCount >= MIN_SIGNATURES);
        require(transaction.readyForExecutionTimestamp > 0);
        require(block.timestamp >= transaction.readyForExecutionTimestamp);

        (bool success,) = address(this).call{accounts: []}(transaction.data);
        require(success);

        transaction.executed = true;
        deleteSetTx(transactionId);
    }

    function deleteSetTx(uint transactionId)
        private
    {
        SetTransaction memory transaction = _settransactions[transactionId];
        require(transaction.timestamp > 0);

        uint256 txLength = _pendingTransactions.length;
        for (uint256 i = 0; i < txLength; i++) {
            if (_pendingTransactions[i] == transactionId) {
                _pendingTransactions[i] = _pendingTransactions[txLength - 1];
                _pendingTransactions.pop();
                break;
            }
        }
        delete _settransactions[transactionId];
    }

    function getPendingTransactions()
        view
        public
        returns (uint[] memory)
    {
        return _pendingTransactions;
    }

    function getPendingTransaction(uint transactionId)
        view
        public
        returns (SetTransaction memory)
    {
        SetTransaction memory pendingsetTx = _settransactions[transactionId];
        return pendingsetTx;
    }

    function getValidOwner(address _owner) view public returns (uint, address[] memory) {
        return (_validOwners[_owner], validOwners);
    }

    function tokenURI(uint256 tokenId) public view virtual
        override(ERC721)
        returns (string memory)
    {
        require(tokenId <= _tokenIds);
        return nodeTokenURI;
    }

    function buyNode(
        uint256 timestamp,
        bytes32 nonce,
        bytes calldata signature,
        address parentAddress,
        uint256 maxPrice,
        uint256 stakeYear
    )
        nonReentrant
        notContract
        external
        returns (uint256)
    {
        require(!halted);

        bytes32 challenge = getChallenge(timestamp, nonce, parentAddress, tx.accounts.dataAccount.key);
        bool isVerified = verified(publicKey, challenge, signature);
        require(isVerified);
        require(!_mintedAddresses[tx.accounts.dataAccount.key]);
        if (parentAddress != address(0)) {
            require(_mintedAddresses[parentAddress]);
            if (parent[tx.accounts.dataAccount.key] == address(0)) parent[tx.accounts.dataAccount.key] = parentAddress;
            else require(parent[tx.accounts.dataAccount.key] == parentAddress);
        } else if (parentAddress == address(0)) {
            parent[tx.accounts.dataAccount.key] = address(0);
        }

        uint256 newItemId = ++_tokenIds;

        mintPrice = calculatePrice(newItemId);
        require(mintPrice <= maxPrice);

        IERC20(ERC20Token).safeTransferFrom(tx.accounts.dataAccount.key, feeAddress, mintPrice);

        _mint(address(this), newItemId);

        tokenOwner[newItemId] = tx.accounts.dataAccount.key;

        _mintedAddresses[tx.accounts.dataAccount.key] = true;

        TokenInfo memory token = TokenInfo({
            tokenId: newItemId,
            tokenOwner: tx.accounts.dataAccount.key,
            tokenPrice: mintPrice,
            mintTimestamp: block.timestamp
        });
        NodeInfo memory node = NodeInfo({
            nodeAddress: tx.accounts.dataAccount.key,
            nodeParent: parent[tx.accounts.dataAccount.key],
            stakeYears: stakeYear,
            tokenInfo: token
        });

        nodes[tx.accounts.dataAccount.key] = node;

        emit NodeStatusChange(tx.accounts.dataAccount.key, parent[tx.accounts.dataAccount.key], newItemId, "Mint", block.timestamp);

        return newItemId;
    }

    function userFetchToken(
        uint256 tokenId,
        address receiver
    )
        public
        nonReentrant
        notContract
    {
        require(tokenOwner[tokenId] == tx.accounts.dataAccount.key);
        require(!locked);
        this.safeTransferFrom(address(this), receiver, tokenId);
        emit NodeStatusChange(tx.accounts.dataAccount.key, parent[tx.accounts.dataAccount.key], tokenId, "Fetch", block.timestamp);
    }

    function getTokenOwner(uint256 tokenId) public view returns (address) {
        return tokenOwner[tokenId];
    }

    function ownerOf(uint256 tokenId) public override view returns (address) {
        address currentOwner = super.ownerOf(tokenId);
        if (currentOwner == address(this)) return tokenOwner[tokenId];
        else return super.ownerOf(tokenId);
    }

    function getAddressInfo(address userAddress) public view returns (NodeInfo memory) {
        return nodes[userAddress];
    }

    function AddressMinted(address userAddress) public view returns (bool) {
        return _mintedAddresses[userAddress];
    }

    function getNodesInfo() public view returns (uint256, uint256, uint256, uint256) {
        uint256 currentTokenId = _tokenIds;
        uint256 nextPrice = calculatePrice(currentTokenId + 1);
        return (nextPrice, currentTokenId + 1, currentTokenId, mintPrice);
    }

    function uint256ToString(uint256 value) public pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            temp /= 10;
            digits++;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function getChallenge(uint256 timestamp,
                          bytes32 nonce,
                          address parentAddress,
                          address userAddress
    ) public pure returns (bytes32) {
        bytes32 challenge = keccak256(abi.encodePacked(userAddress, timestamp, nonce, parentAddress));
        return challenge;
    }

    function verified(
        address expectedSigner,
        bytes32 messageHash,
        bytes memory signature
    ) public pure returns (bool) {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(messageHash);
        address recoveredSigner = ethSignedMessageHash.recover(signature);
        return (recoveredSigner == expectedSigner);
    }

    function getEthSignedMessageHash(bytes32 _messageHash) private pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    modifier notContract() {
        require(!_isContract(tx.accounts.dataAccount.key));
        _;
    }

    function _isContract(address addr) internal view returns (bool) {
        return false;
    }

    function calculatePrice(uint256 id) public view returns (uint256) {
        require(id <= MAX_ID);
        uint256 priceLevel = ((id - 1) / ID_INCREMENT) + 1;
        return priceLevel * PRICE_INCREMENT * 10 ** tokenDecimals;
    }
}